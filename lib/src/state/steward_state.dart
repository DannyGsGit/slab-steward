import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../model/difficulty.dart';
import '../model/lens.dart';
import '../model/staged_edit.dart';
import '../model/trail.dart';
import '../osm/changeset_download.dart';
import '../osm/changeset_preview.dart';
import '../osm/osm_api.dart';
import '../osm/submission_gate.dart';

/// What one application of a difficulty across a set of trails did.
///
/// A batch is rarely uniform — some trails already carry the value, and some
/// couldn't be read from the OSM API at all — and saying so afterwards is the
/// difference between a bulk edit the rider trusts and one they have to audit
/// by hand.
typedef BatchResult = ({int staged, int unchanged, int unreadable});

/// What the app knows right now: how the map is filtered, which trails (if any)
/// the rider is working on, and what edits are waiting to be submitted.
///
/// Deliberately a plain [ChangeNotifier] — the app is one screen, and reaching
/// for a state-management package before there's a second one would be
/// premature.
class StewardState extends ChangeNotifier {
  StewardState({OsmApi? osmApi}) : _osmApi = osmApi ?? OsmApi();

  final OsmApi _osmApi;

  /// How many way reads may be in flight at once while resolving a bulk
  /// selection. Steward is a well-behaved OSM API client before it is a fast
  /// one.
  static const maxConcurrentReads = 4;

  /// How many trails the in-view list will name. A viewport at the overlay's
  /// minimum zoom can hold thousands; a list that long is not a list.
  static const maxVisibleTrails = 250;

  TravelMode _mode = TravelMode.mtb;
  Lens _lens = Lens.completeness;

  /// Every trail Steward has looked at this session, provisional or
  /// authoritative, keyed by OSM way id. Selection, the in-view list and the
  /// editors all address trails through here, so a trail upgraded once is
  /// upgraded everywhere.
  final Map<int, Trail> _trails = {};

  /// The working set, in the order trails joined it.
  final Set<int> _selection = <int>{};

  /// Way ids with an OSM API read in flight, and the last read failure per
  /// way. A failure belongs to the way, not to the selection: dropping a trail
  /// and picking it up again shouldn't quietly forget that OSM couldn't answer
  /// for it. A fresh read clears it.
  final Set<int> _loading = <int>{};
  final Map<int, String> _readErrors = {};

  /// Bumped per way whenever a read starts, so a slow response for a trail the
  /// rider has since dropped — or re-read — lands nowhere.
  final Map<int, int> _fetchTokens = {};

  bool _isTrailListOpen = false;
  bool _hasListedVisibleTrails = false;
  bool _visibleTrailsTruncated = false;
  List<int> _visibleWayIds = const [];

  /// Edits waiting to go out as one changeset, in the order they were staged.
  final List<StagedEdit> _stagedEdits = [];

  TravelMode get mode => _mode;
  Lens get lens => _lens;

  /// Bumped whenever the map style needs rebuilding.
  int get styleRevision => _styleRevision;
  int _styleRevision = 0;

  /// Bumped whenever the staged set changes, so the map can tell a re-staged
  /// edit from an unchanged one without diffing the list itself.
  int get stagedRevision => _stagedRevision;
  int _stagedRevision = 0;

  void setMode(TravelMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    // "Unknown access" asks a question that has no meaning without a mode.
    if (mode == TravelMode.all && _lens == Lens.access) _lens = Lens.none;
    _styleRevision++;
    notifyListeners();
  }

  void setLens(Lens lens) {
    if (_lens == lens) return;
    _lens = lens;
    _styleRevision++;
    notifyListeners();
  }

  // --- Selection -----------------------------------------------------------

  /// Every trail Steward knows about, however it was found.
  Trail? trailFor(int osmWayId) => _trails[osmWayId];

  /// The working set, in the order trails joined it.
  List<Trail> get selectedTrails => [
    for (final id in _selection) ?_trails[id],
  ];

  /// The one selected trail, or null when none or several are. The detail
  /// panel is a single-trail view by definition; several trails get the bulk
  /// editor instead.
  Trail? get selected =>
      _selection.length == 1 ? _trails[_selection.first] : null;

  int get selectionCount => _selection.length;
  bool get hasSelection => _selection.isNotEmpty;
  bool get hasMultiSelection => _selection.length > 1;
  bool isSelected(int osmWayId) => _selection.contains(osmWayId);

  bool isLoadingDetails(int osmWayId) => _loading.contains(osmWayId);

  /// Why the OSM API couldn't be asked about this way, if it couldn't.
  String? readErrorFor(int osmWayId) => _readErrors[osmWayId];

  /// Selected trails whose tags came from the OSM API, which is the only set
  /// an edit may be composed against.
  List<Trail> get editableSelection => [
    for (final trail in selectedTrails)
      if (trail.isAuthoritative) trail,
  ];

  /// Selects one trail and drops the rest — a plain click.
  ///
  /// The panel renders immediately off the tile properties; the editor will
  /// only ever act on the authoritative version, which this then fetches.
  Future<void> selectFromTile(Map<String, Object?> tileProperties) async {
    final trail = _rememberTile(tileProperties);
    if (trail == null) return;

    _abandonReadsOutside({trail.osmWayId});
    _selection
      ..clear()
      ..add(trail.osmWayId);
    notifyListeners();

    await ensureAuthoritative(trail.osmWayId);
  }

  /// Adds a trail to the working set, or removes it if it's already there —
  /// ctrl/cmd-click on the map, and the in-view list's checkboxes.
  Future<void> toggleFromTile(Map<String, Object?> tileProperties) async {
    final trail = _rememberTile(tileProperties);
    if (trail == null) return;
    await setSelected(trail.osmWayId, !_selection.contains(trail.osmWayId));
  }

  /// Adds or removes one known trail.
  ///
  /// Reads authoritative tags on the way in: one trail at a time is a
  /// deliberate act, and the map can't draw a trail it has no geometry for.
  Future<void> setSelected(int osmWayId, bool selected) async {
    if (selected == _selection.contains(osmWayId)) return;
    if (selected) {
      if (!_trails.containsKey(osmWayId)) return;
      _selection.add(osmWayId);
      notifyListeners();
      await ensureAuthoritative(osmWayId);
      return;
    }
    _selection.remove(osmWayId);
    _abandonRead(osmWayId);
    notifyListeners();
  }

  /// Replaces the working set wholesale — "select all", "select none".
  ///
  /// Deliberately does *not* read authoritative tags. This is one click that
  /// can name a hundred trails, and a hundred OSM API calls is not a
  /// reasonable answer to it; [resolveSelection] fetches them at the point
  /// there is actually an edit to compose.
  void setSelection(Iterable<int> osmWayIds) {
    final next = <int>{
      for (final id in osmWayIds)
        if (_trails.containsKey(id)) id,
    };
    if (setEquals(next, _selection)) return;
    _abandonReadsOutside(next);
    _selection
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void clearSelection() {
    if (_selection.isEmpty) return;
    _abandonReadsOutside(const {});
    _selection.clear();
    notifyListeners();
  }

  /// Reads authoritative tags and geometry for [osmWayId], unless they're
  /// already in hand or already on their way.
  Future<void> ensureAuthoritative(int osmWayId) async {
    final known = _trails[osmWayId];
    if (known == null || known.isAuthoritative) return;
    if (_loading.contains(osmWayId)) return;

    final token = _fetchTokens[osmWayId] = (_fetchTokens[osmWayId] ?? 0) + 1;
    _loading.add(osmWayId);
    _readErrors.remove(osmWayId);
    notifyListeners();

    try {
      final way = await _osmApi.fetchWay(osmWayId);
      if (_fetchTokens[osmWayId] != token) return;
      _trails[osmWayId] = known.mergeAuthoritative(
        tags: way.tags,
        version: way.version,
        geometry: way.geometry,
        nodeIds: way.nodeIds,
      );
    } on OsmApiException catch (e) {
      if (_fetchTokens[osmWayId] != token) return;
      _readErrors[osmWayId] = e.isGone
          ? 'This trail is no longer in OpenStreetMap. The map tiles may be out of date.'
          : e.message;
    } finally {
      if (_fetchTokens[osmWayId] == token) {
        _loading.remove(osmWayId);
        notifyListeners();
      }
    }
  }

  /// Reads authoritative tags for every selected trail that still needs them,
  /// a few at a time, reporting progress as it goes.
  ///
  /// This is what a bulk edit calls before it stages anything: the whole point
  /// of gating the editor on authoritative tags is that a changeset composed
  /// against tile data is built on a version that may already be stale, and a
  /// batch of a hundred is no less exposed to that than a single trail.
  Future<void> resolveSelection({
    void Function(int done, int total)? onProgress,
  }) async {
    final pending = Queue<int>.of([
      for (final id in _selection)
        if (_trails[id]?.isAuthoritative == false) id,
    ]);
    final total = pending.length;
    if (total == 0) return;

    var done = 0;
    onProgress?.call(0, total);
    Future<void> worker() async {
      while (pending.isNotEmpty) {
        await ensureAuthoritative(pending.removeFirst());
        onProgress?.call(++done, total);
      }
    }

    await Future.wait([
      for (var i = 0; i < math.min(maxConcurrentReads, total); i++) worker(),
    ]);
  }

  /// Files a trail the map has just reported, without clobbering tags the OSM
  /// API already confirmed. Returns null for a tile feature with no usable
  /// OSM way id, which isn't something Steward can edit.
  Trail? _rememberTile(Map<String, Object?> tileProperties) {
    final Trail provisional;
    try {
      provisional = Trail.fromTileProperties(tileProperties);
    } catch (_) {
      return null;
    }
    final known = _trails[provisional.osmWayId];
    if (known != null && known.isAuthoritative) return known;
    return _trails[provisional.osmWayId] = provisional;
  }

  void _abandonRead(int osmWayId) {
    if (!_loading.remove(osmWayId)) return;
    _fetchTokens[osmWayId] = (_fetchTokens[osmWayId] ?? 0) + 1;
  }

  void _abandonReadsOutside(Set<int> keep) {
    for (final id in _loading.toList()) {
      if (!keep.contains(id)) _abandonRead(id);
    }
  }

  // --- The in-view trail list ----------------------------------------------

  bool get isTrailListOpen => _isTrailListOpen;

  /// True once the map has answered at least once, so an empty list can say
  /// "no trails here" rather than sitting blank while the first query runs.
  bool get hasListedVisibleTrails => _hasListedVisibleTrails;

  /// True when the viewport held more trails than [maxVisibleTrails].
  bool get visibleTrailsTruncated => _visibleTrailsTruncated;

  /// The trails the map is drawing right now, in the order the list shows
  /// them: named trails alphabetically, then the unnamed ones.
  List<Trail> get visibleTrails => [
    for (final id in _visibleWayIds) ?_trails[id],
  ];

  void setTrailListOpen(bool open) {
    if (_isTrailListOpen == open) return;
    _isTrailListOpen = open;
    if (!open) {
      // The list is only ever as good as the viewport it was taken from, so
      // it's re-queried on open rather than kept warm.
      _hasListedVisibleTrails = false;
      _visibleWayIds = const [];
      _visibleTrailsTruncated = false;
    }
    notifyListeners();
  }

  void toggleTrailList() => setTrailListOpen(!_isTrailListOpen);

  /// Takes the map's report of what's on screen. Tile features repeat across
  /// tile boundaries, so this dedupes by way id.
  void setVisibleTrails(Iterable<Map<String, Object?>> tileProperties) {
    final ids = <int>{};
    for (final props in tileProperties) {
      final trail = _rememberTile(props);
      if (trail != null) ids.add(trail.osmWayId);
    }
    final ordered = (ids.toList()..sort(_byListOrder))
        .take(maxVisibleTrails)
        .toList();

    // The map re-reports the same viewport every time a tile finishes loading.
    // Only an actual change to the list is worth a rebuild.
    final wasListed = _hasListedVisibleTrails;
    _hasListedVisibleTrails = true;
    _visibleTrailsTruncated = ids.length > maxVisibleTrails;
    if (wasListed && listEquals(ordered, _visibleWayIds)) return;
    _visibleWayIds = ordered;
    notifyListeners();
  }

  int _byListOrder(int a, int b) {
    final nameA = _trails[a]?.name;
    final nameB = _trails[b]?.name;
    if (nameA == null || nameB == null) {
      // Unnamed trails sink below the named ones — a rider is looking for a
      // trail they know, and they know it by name.
      if (nameA != nameB) return nameA == null ? 1 : -1;
      return a.compareTo(b);
    }
    final byName = nameA.toLowerCase().compareTo(nameB.toLowerCase());
    return byName != 0 ? byName : a.compareTo(b);
  }

  // --- Staging -------------------------------------------------------------

  List<StagedEdit> get stagedEdits => List.unmodifiable(_stagedEdits);

  int get stagedEditCount => _stagedEdits.length;

  bool get hasStagedEdits => _stagedEdits.isNotEmpty;

  /// The staged edits grouped by trail, both trails and edits in staging
  /// order, which is the order the review list reads best in.
  Map<int, List<StagedEdit>> get stagedEditsByTrail {
    final grouped = <int, List<StagedEdit>>{};
    for (final edit in _stagedEdits) {
      grouped.putIfAbsent(edit.osmWayId, () => []).add(edit);
    }
    return grouped;
  }

  /// The staged edits grouped into what the map draws: one glow, and one
  /// badge, per trail with something pending.
  List<StagedTrail> get stagedTrails => [
    for (final entry in stagedEditsByTrail.entries)
      StagedTrail(osmWayId: entry.key, edits: entry.value),
  ];

  /// The pending change to one attribute of one trail, if there is one.
  StagedEdit? stagedEditFor(int osmWayId, TrailAttribute attribute) {
    for (final edit in _stagedEdits) {
      if (edit.osmWayId == osmWayId && edit.attribute == attribute) return edit;
    }
    return null;
  }

  /// Stages [edit], replacing any earlier edit to the same attribute of the
  /// same trail — a rider who changes their mind twice should end up with one
  /// pending change, not three.
  void stageEdit(StagedEdit edit) {
    _removeEdit(edit.osmWayId, edit.attribute);
    _stagedEdits.add(edit);
    _stagedRevision++;
    notifyListeners();
  }

  /// Stages [value] against every trail in [trails] at once.
  ///
  /// One edit per trail, however many trails there are — a batch is a
  /// convenience for composing changes, not a different kind of change, and
  /// the review list has to be able to show each one on its own. Picking the
  /// value OSM already holds isn't an edit, and is also how a rider walks back
  /// a pending change, so those trails are unstaged instead.
  ///
  /// Trails whose tags aren't authoritative are left alone and counted in the
  /// result: the editor never composes a changeset against tile data.
  BatchResult applyDifficulty(Iterable<Trail> trails, Difficulty value) {
    var staged = 0;
    var unchanged = 0;
    var unreadable = 0;
    var touched = false;

    for (final trail in trails) {
      if (!trail.isAuthoritative) {
        unreadable++;
        continue;
      }
      final removed = _removeEdit(trail.osmWayId, TrailAttribute.difficulty);
      if (value == trail.difficulty) {
        unchanged++;
        touched |= removed;
        continue;
      }
      _stagedEdits.add(StagedEdit.difficulty(trail, value));
      staged++;
      touched = true;
    }

    if (touched) {
      _stagedRevision++;
      notifyListeners();
    }
    return (staged: staged, unchanged: unchanged, unreadable: unreadable);
  }

  void unstageEdit(int osmWayId, TrailAttribute attribute) {
    if (!_removeEdit(osmWayId, attribute)) return;
    _stagedRevision++;
    notifyListeners();
  }

  /// Drops every pending edit for one trail.
  void unstageTrail(int osmWayId) {
    final before = _stagedEdits.length;
    _stagedEdits.removeWhere((e) => e.osmWayId == osmWayId);
    if (_stagedEdits.length == before) return;
    _stagedRevision++;
    notifyListeners();
  }

  void clearStagedEdits() {
    if (_stagedEdits.isEmpty) return;
    _stagedEdits.clear();
    _stagedRevision++;
    notifyListeners();
  }

  /// A fresh gate for one submit attempt: comment quality, the campaign
  /// hashtag, a live re-read of every staged trail, and a conflict check
  /// against what each edit was staged on. See
  /// docs/slab-steward-osm-changeset-spec.md §4.
  SubmissionGate createSubmissionGate() => SubmissionGate(osmApi: _osmApi);

  /// Resolves a submission conflict in the rider's favor: keeps the pending
  /// value but rebases the edit onto the live tags/version the gate just
  /// fetched, so a retry compares against data that's actually current.
  void rebaseEditOnLive(int osmWayId, TrailAttribute attribute, OsmWay live) {
    final edit = stagedEditFor(osmWayId, attribute);
    if (edit == null) return;
    final liveTrail = Trail(
      osmWayId: live.id,
      tags: live.tags,
      isAuthoritative: true,
      version: live.version,
      geometry: live.geometry,
      nodeIds: live.nodeIds,
    );
    switch (attribute) {
      case TrailAttribute.difficulty:
        stageEdit(StagedEdit.difficulty(liveTrail, edit.difficulty!));
    }
  }

  /// Writes out the changeset a passed [gate] approved and clears the staged
  /// edits it covered.
  ///
  /// Nothing reaches OpenStreetMap yet — there is no token to write under
  /// until OSM sign-in lands. Instead, this renders the changeset-create and
  /// osmChange-upload calls a real submit would make and saves them, so the
  /// shape of that future request can be checked by hand. Callers must say
  /// so in the UI. The gate has already fetched fresh tags and versions for
  /// everything going to OSM, so nothing here does network I/O.
  String finalizeSubmission({
    required SubmissionGate gate,
    required bool requestReview,
  }) {
    assert(gate.finalComment.trim().isNotEmpty, 'A changeset needs a comment');
    final localOnly = [
      for (final trail in stagedTrails)
        if (trail.edits.every((e) => !e.changesOsm)) trail,
    ];
    final preview = buildChangesetPreview(
      comment: gate.finalComment,
      requestReview: requestReview,
      writes: gate.resolvedWrites,
      localOnlyTrails: localOnly,
    );
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]'), '')
        .replaceAll(RegExp(r'\.\d+Z$'), 'Z');
    final savedTo = saveChangesetPreview('submit_$timestamp.txt', preview);
    clearStagedEdits();
    return savedTo;
  }

  bool _removeEdit(int osmWayId, TrailAttribute attribute) {
    final before = _stagedEdits.length;
    _stagedEdits.removeWhere(
      (e) => e.osmWayId == osmWayId && e.attribute == attribute,
    );
    return _stagedEdits.length != before;
  }

  @override
  void dispose() {
    _osmApi.dispose();
    super.dispose();
  }
}

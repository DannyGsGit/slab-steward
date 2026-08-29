import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../model/difficulty.dart';
import '../model/ebike_class.dart';
import '../model/electric_bicycle.dart';
import '../model/lens.dart';
import '../model/sidebar_section.dart';
import '../model/staged_edit.dart';
import '../model/steward_stats.dart';
import '../map/otm_conventions.dart' show renderedTagKeys;
import '../model/trail.dart';
import '../model/trail_filters.dart';
import '../model/trail_overrides.dart';
import '../osm/osm_api.dart';
import '../osm/osm_auth.dart';
import '../osm/osm_environment.dart';
import '../osm/submission_gate.dart';

/// What one application of a value across a set of trails did.
///
/// A batch is rarely uniform — some trails already carry the value, some
/// couldn't be read from the OSM API at all, and some hold an answer Steward
/// is not willing to overwrite — and saying so afterwards is the difference
/// between a bulk edit the rider trusts and one they have to audit by hand.
typedef BatchResult = ({
  int staged,
  int unchanged,
  int unreadable,
  int protected,
});

/// What the app knows right now: how the map is filtered, which trails (if any)
/// the rider is working on, and what edits are waiting to be submitted.
///
/// Deliberately a plain [ChangeNotifier] — the app is one screen, and reaching
/// for a state-management package before there's a second one would be
/// premature.
class StewardState extends ChangeNotifier {
  StewardState({
    OsmApi? osmApi,
    OsmAuthState? auth,
    this.environment = osmEnvironment,
  }) : _osmApi = osmApi ?? OsmApi(),
       auth = auth ?? OsmAuthState() {
    this.auth.restoreSession();
    overrides = TrailOverrides(onChanged: _onOverridesChanged);
    overrides.load();
  }

  /// Tags Steward has seen that the tileset hasn't caught up with. See
  /// [TrailOverrides] — this is what keeps a trail from snapping back to
  /// "unrated" the moment its edit is submitted.
  late final TrailOverrides overrides;

  void _onOverridesChanged() {
    _styleRevision++;
    notifyListeners();
  }

  /// Whether [tile] and [live] would draw differently. See [renderedTagKeys].
  static bool _rendersDifferently(
    Map<String, String> tile,
    Map<String, String> live,
  ) => renderedTagKeys.any((key) => tile[key] != live[key]);

  /// Notes what the API just told us about [osmWayId], so the map can draw it
  /// from that rather than from a tile build that predates it.
  void _recordOverride(
    int osmWayId,
    Map<String, String> tags,
    OverrideSource source,
  ) => overrides.record(osmWayId, tags, source: source);

  final OsmApi _osmApi;

  /// Which of the two configurations this build runs — passed on to every
  /// gate [createSubmissionGate] makes. Injectable only so tests can exercise
  /// both in one run; the app always takes the build's [osmEnvironment].
  final OsmEnvironment environment;

  /// The rider's OSM sign-in — required before [createSubmissionGate]'s
  /// gate can actually submit anything, via [SubmissionGate.submit].
  final OsmAuthState auth;

  /// How many way reads may be in flight at once while resolving a bulk
  /// selection. Steward is a well-behaved OSM API client before it is a fast
  /// one.
  static const maxConcurrentReads = 4;

  /// How many trails the in-view list will name. A viewport at the overlay's
  /// minimum zoom can hold thousands; a list that long is not a list.
  static const maxVisibleTrails = 250;

  /// Who the map is asking about. Empty is a legal answer — it asks nobody,
  /// which is the old "all trails".
  final Set<TravelMode> _modes = {TravelMode.mtb};

  /// The kinds of line the map draws. See [TrailKind].
  final Set<TrailKind> _kinds = TrailKind.defaults;

  /// The lenses the map colours by. Defaults to the attribute lenses — the
  /// "is this trail finished?" question Steward exists to answer.
  final Set<Lens> _lenses = {Lens.difficulty, Lens.electricBicycle};

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

  /// What the rider has done through Steward, or null before the first load —
  /// distinct from "loaded and empty", which [StewardStats.isEmpty] answers.
  StewardStats? _stats;
  bool _isLoadingStats = false;
  String? _statsError;

  /// The open sidebar pane, or null when the rail is collapsed to the map.
  SidebarSection? _activeSection = SidebarSection.map;

  /// What was open before a map click took the pane over for the editor, so
  /// clearing the selection puts the rider back where they were rather than
  /// collapsing the sidebar out from under them.
  SidebarSection? _sectionBeforeSelection;
  bool _hasListedVisibleTrails = false;
  bool _visibleTrailsTruncated = false;
  List<int> _visibleWayIds = const [];

  /// Edits waiting to go out as one changeset, in the order they were staged.
  final List<StagedEdit> _stagedEdits = [];

  Set<TravelMode> get modes => UnmodifiableSetView(_modes);

  Set<TrailKind> get kinds => UnmodifiableSetView(_kinds);

  /// The lenses currently applied. A trail passes only when it answers every
  /// one of them; an empty selection colours nothing.
  Set<Lens> get lenses => UnmodifiableSetView(_lenses);

  /// Bumped whenever the map style needs rebuilding.
  int get styleRevision => _styleRevision;
  int _styleRevision = 0;

  /// Bumped whenever the staged set changes, so the map can tell a re-staged
  /// edit from an unchanged one without diffing the list itself.
  int get stagedRevision => _stagedRevision;
  int _stagedRevision = 0;

  /// Adds or removes one travel mode, leaving the rest alone.
  void setModeEnabled(TravelMode mode, bool enabled) {
    if (_modes.contains(mode) == enabled) return;
    if (enabled) {
      _modes.add(mode);
    } else {
      _modes.remove(mode);
    }
    // "Unknown access" asks a question that has no meaning with nobody to
    // ask it about.
    if (_modes.isEmpty) _lenses.remove(Lens.access);
    _styleRevision++;
    notifyListeners();
  }

  void setModes(Set<TravelMode> modes) {
    if (setEquals(_modes, modes)) return;
    _modes
      ..clear()
      ..addAll(modes);
    if (_modes.isEmpty) _lenses.remove(Lens.access);
    _styleRevision++;
    notifyListeners();
  }

  /// Draws, or stops drawing, one kind of line.
  void setKindEnabled(TrailKind kind, bool enabled) {
    if (_kinds.contains(kind) == enabled) return;
    if (enabled) {
      _kinds.add(kind);
    } else {
      _kinds.remove(kind);
    }
    _styleRevision++;
    notifyListeners();
  }

  void setLenses(Set<Lens> lenses) {
    if (setEquals(_lenses, lenses)) return;
    _lenses
      ..clear()
      ..addAll(lenses);
    _styleRevision++;
    notifyListeners();
  }

  /// Adds or removes one lens, leaving the rest of the selection alone.
  void setLensEnabled(Lens lens, bool enabled) {
    if (_lenses.contains(lens) == enabled) return;
    if (enabled) {
      _lenses.add(lens);
    } else {
      _lenses.remove(lens);
    }
    _styleRevision++;
    notifyListeners();
  }

  // --- Selection -----------------------------------------------------------

  /// Every trail Steward knows about, however it was found.
  Trail? trailFor(int osmWayId) => _trails[osmWayId];

  /// The working set, in the order trails joined it.
  List<Trail> get selectedTrails => [for (final id in _selection) ?_trails[id]];

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
    // Clicking a trail is a request to work on it, so the editor comes to the
    // front — the sidebar is where the panel that used to float over the map
    // now lives.
    _showSelectionPane();
    notifyListeners();

    await ensureAuthoritative(trail.osmWayId);
  }

  /// Adds a trail to the working set, or removes it if it's already there —
  /// ctrl/cmd-click on the map, and the in-view list's checkboxes.
  Future<void> toggleFromTile(Map<String, Object?> tileProperties) async {
    final trail = _rememberTile(tileProperties);
    if (trail == null) return;
    final add = !_selection.contains(trail.osmWayId);
    // Adding from the map is the same act of intent a plain click is, so it
    // brings the editor forward. Ticking a row in the in-view list is not —
    // that would pull the list out from under the rider mid-sweep.
    if (add) _showSelectionPane();
    await setSelected(trail.osmWayId, add);
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

  /// Adds every trail the map reported under a selection box to the working
  /// set — ctrl/cmd-drag on the map.
  ///
  /// Additive, and never subtractive: the box is the same modified gesture as
  /// the click it extends, and a rider sweeping across a network is assembling
  /// a set rather than toggling each trail in it. A box that catches a trail
  /// already selected leaves it selected.
  ///
  /// Deliberately does *not* read authoritative tags, for the reason
  /// [setSelection] gives: one gesture can name a hundred trails, and
  /// [resolveSelection] reads them at the point there is an edit to compose.
  /// Tile features repeat across tile boundaries, so this dedupes by way id.
  void addFromTiles(Iterable<Map<String, Object?>> tileProperties) {
    var added = false;
    for (final props in tileProperties) {
      final trail = _rememberTile(props);
      if (trail == null) continue;
      added |= _selection.add(trail.osmWayId);
    }
    if (!added) return;
    _showSelectionPane();
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
    // The editor pane has nothing left to edit, so the rider goes back to
    // whatever they were doing before they clicked a trail.
    if (_activeSection == SidebarSection.selection) {
      _activeSection = _sectionBeforeSelection;
      _sectionBeforeSelection = null;
    }
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
      // The read is by definition newer than the tiles, and carries whatever
      // anyone else has changed since they were cut — but most trails haven't
      // changed, and caching a read that only repeats what the map already
      // draws would restyle the map on every first click for nothing.
      if (!known.isAuthoritative && _rendersDifferently(known.tags, way.tags)) {
        _recordOverride(osmWayId, way.tags, OverrideSource.read);
      }
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

  /// The hashtag Steward stamps on every changeset it opens — see
  /// [SubmissionGate.submit]. Scoping stats to it is what keeps a rider's
  /// years of other OSM history out of a view meant to show what they've done
  /// *here*.
  static const stewardHashtag = 'slabsteward';

  StewardStats? get stats => _stats;
  bool get isLoadingStats => _isLoadingStats;
  String? get statsError => _statsError;

  /// Fetches the rider's Steward changesets and summarises them, unless a
  /// load is already in flight. Requires a signed-in rider — the stats pane
  /// checks [OsmAuthState.isSignedIn] before ever calling this.
  Future<void> loadStats() async {
    final identity = auth.identity;
    final token = auth.bearerToken;
    if (identity == null || token == null || _isLoadingStats) return;

    _isLoadingStats = true;
    _statsError = null;
    notifyListeners();
    try {
      final changesets = await _osmApi.fetchChangesets(
        userId: identity.id,
        hashtag: stewardHashtag,
        bearerToken: token,
      );
      _stats = StewardStats.from(changesets);
    } on OsmApiException catch (e) {
      _statsError = e.message;
    } finally {
      _isLoadingStats = false;
      notifyListeners();
    }
  }

  /// Drops whatever stats were loaded — called on sign-out, so a pane left
  /// open doesn't keep showing the last rider's numbers under a new name.
  void clearStats() {
    if (_stats == null && _statsError == null) return;
    _stats = null;
    _statsError = null;
    notifyListeners();
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

  // --- The sidebar ---------------------------------------------------------

  /// The pane the sidebar is showing, or null when it is collapsed and the
  /// map has the whole window.
  SidebarSection? get activeSection => _activeSection;

  /// Whether the in-view list is the pane on screen. The map only reports
  /// what's in the viewport while something is there to read it.
  bool get isTrailListOpen => _activeSection == SidebarSection.trails;

  /// Brings the editor forward, remembering what it displaced.
  void _showSelectionPane() {
    if (_activeSection == SidebarSection.selection) return;
    _sectionBeforeSelection = _activeSection;
    // The in-view list is answered from the viewport; it isn't the pane on
    // screen any more, so it goes back to being re-read on open.
    if (_activeSection == SidebarSection.trails) _forgetVisibleTrails();
    _activeSection = SidebarSection.selection;
  }

  void openSection(SidebarSection section) {
    if (_activeSection == section) return;
    _forgetVisibleTrails();
    _activeSection = section;
    // Opening a pane by hand replaces whatever the editor would have gone
    // back to: that choice is now the rider's current place.
    _sectionBeforeSelection = null;
    notifyListeners();
  }

  void closeSection() {
    if (_activeSection == null) return;
    _forgetVisibleTrails();
    _activeSection = null;
    notifyListeners();
  }

  /// What a rail button does: opens its pane, or collapses the sidebar if that
  /// pane is already the one open.
  void toggleSection(SidebarSection section) =>
      _activeSection == section ? closeSection() : openSection(section);

  /// The list is only ever as good as the viewport it was taken from, so it's
  /// re-queried on open rather than kept warm.
  void _forgetVisibleTrails() {
    _hasListedVisibleTrails = false;
    _visibleWayIds = const [];
    _visibleTrailsTruncated = false;
  }

  // --- The in-view trail list ----------------------------------------------

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
  BatchResult applyDifficulty(Iterable<Trail> trails, Difficulty value) =>
      _applyAcross(
        trails,
        TrailAttribute.difficulty,
        isCurrent: (trail) => trail.difficulty == value,
        stage: (trail) => StagedEdit.difficulty(trail, value),
      );

  /// Stages an e-bike permission across [trails], on exactly the terms
  /// [applyDifficulty] describes, with one addition: a trail already answering
  /// with a value outside Steward's two options is left alone.
  ///
  /// `electric_bicycle` is one key, so writing to it *replaces* what's there —
  /// there is no additive form. A trail tagged `designated` or `permissive`
  /// already says everything "allowed" would say and more, and a rider working
  /// through forty trails would never see it go. So Steward doesn't write it:
  /// those trails come back counted as protected, to be named rather than
  /// silently downgraded.
  ///
  /// [cap] is the class the rider answered about — "up to Class 1" — in the
  /// vocabulary of wherever they are. Left out, each trail is asked about the
  /// cap for its own location; see [Trail.ebikeJurisdiction].
  BatchResult applyElectricBicycle(
    Iterable<Trail> trails,
    EbikeAccess value, {
    EbikeClass? cap,
  }) => _applyAcross(
    trails,
    TrailAttribute.electricBicycle,
    isCurrent: (trail) => trail.electricBicycle == value,
    isProtected: (trail) => trail.hasUnmappedElectricBicycle,
    stage: (trail) => StagedEdit.electricBicycle(trail, value, cap: cap),
  );

  /// The shared body of the per-attribute bulk appliers: every attribute
  /// stages, skips and walks back on the same rules, and one trail is just a
  /// batch of one.
  BatchResult _applyAcross(
    Iterable<Trail> trails,
    TrailAttribute attribute, {
    required bool Function(Trail trail) isCurrent,
    required StagedEdit Function(Trail trail) stage,
    bool Function(Trail trail)? isProtected,
  }) {
    var staged = 0;
    var unchanged = 0;
    var unreadable = 0;
    var protected = 0;
    var touched = false;

    for (final trail in trails) {
      if (!trail.isAuthoritative) {
        unreadable++;
        continue;
      }
      // Checked before anything is removed: a protected trail is one this
      // batch never touches, including any edit already staged on it.
      if (isProtected?.call(trail) ?? false) {
        protected++;
        continue;
      }
      final removed = _removeEdit(trail.osmWayId, attribute);
      if (isCurrent(trail)) {
        unchanged++;
        touched |= removed;
        continue;
      }
      _stagedEdits.add(stage(trail));
      staged++;
      touched = true;
    }

    if (touched) {
      _stagedRevision++;
      notifyListeners();
    }
    return (
      staged: staged,
      unchanged: unchanged,
      unreadable: unreadable,
      protected: protected,
    );
  }

  /// Stages a difficulty on one trail the rider has just picked a value for,
  /// reading its authoritative tags first if they aren't in hand yet.
  Future<BatchResult> setDifficulty(int osmWayId, Difficulty value) =>
      _stageOnTrail(osmWayId, (trail) => applyDifficulty([trail], value));

  /// Stages an e-bike permission on one trail, the same way [setDifficulty]
  /// stages a rating.
  Future<BatchResult> setElectricBicycle(
    int osmWayId,
    EbikeAccess value, {
    EbikeClass? cap,
  }) => _stageOnTrail(
    osmWayId,
    (trail) => applyElectricBicycle([trail], value, cap: cap),
  );

  /// Resolves one trail and applies [stage] to it.
  ///
  /// The editors read a trail straight off the tile, so picking a value is
  /// usually the first moment there is any reason to spend an OSM API call on
  /// it — the read happens here, at the moment of intent, rather than for
  /// every trail on screen up front. A trail OSM couldn't answer for stages
  /// nothing and reports itself unreadable; [readErrorFor] says why.
  Future<BatchResult> _stageOnTrail(
    int osmWayId,
    BatchResult Function(Trail trail) stage,
  ) async {
    await ensureAuthoritative(osmWayId);
    final trail = _trails[osmWayId];
    if (trail == null || !trail.isAuthoritative) {
      return (staged: 0, unchanged: 0, unreadable: 1, protected: 0);
    }
    return stage(trail);
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

  /// Called once a changeset has closed: folds every edit that just went out
  /// into [overrides], then empties the staging area.
  ///
  /// The two halves belong together. Clearing alone is what made a submitted
  /// trail *lose* its blue staged glow and fall back to the tileset's stale
  /// magenta — the work landing was the moment the map stopped showing it.
  void applySubmitted() {
    for (final trail in stagedEditsByTrail.entries) {
      final tags = <String, String>{...trail.value.first.baseTags};
      for (final edit in trail.value) {
        edit.tagChanges.forEach((key, value) {
          if (value == null) {
            tags.remove(key);
          } else {
            tags[key] = value;
          }
        });
      }
      _recordOverride(trail.key, tags, OverrideSource.submitted);
    }
    clearStagedEdits();
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
  /// docs/specs/slab-steward-osm-changeset-spec.md §4.
  SubmissionGate createSubmissionGate() =>
      SubmissionGate(osmApi: _osmApi, environment: environment);

  /// Resolves a submission conflict in the rider's favor: keeps the pending
  /// value but rebases the edit onto the live tags/version the gate just
  /// fetched, so a retry compares against data that's actually current.
  void rebaseEditOnLive(int osmWayId, TrailAttribute attribute, OsmWay live) {
    final edit = stagedEditFor(osmWayId, attribute);
    if (edit == null) return;
    _recordOverride(osmWayId, live.tags, OverrideSource.read);
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
      case TrailAttribute.electricBicycle:
        stageEdit(
          StagedEdit.electricBicycle(
            liveTrail,
            edit.electricBicycle!,
            cap: edit.ebikeClass,
          ),
        );
    }
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
    auth.dispose();
    super.dispose();
  }
}

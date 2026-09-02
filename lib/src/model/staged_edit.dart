import 'dart:math' as math;

import 'difficulty.dart';
import 'ebike_class.dart';
import 'electric_bicycle.dart';
import 'trail.dart';

/// A trail attribute the guided editor can change.
///
/// Surface and sanction status are the next two, and the panel builds its rows
/// off this enum so adding one is a matter of teaching [StagedEdit] how to
/// diff it.
enum TrailAttribute {
  difficulty('Difficulty'),
  electricBicycle('E-bike access');

  const TrailAttribute(this.label);

  final String label;
}

/// One pending change to one attribute of one trail.
///
/// The tag diff is computed at staging time against the trail's authoritative
/// tags, so [tagChanges] only ever holds keys whose value actually differs —
/// which is what makes [changesOsm] trustworthy, and what lets the preview show
/// the user exactly what the changeset will carry.
class StagedEdit {
  const StagedEdit({
    required this.osmWayId,
    required this.attribute,
    required this.fromLabel,
    required this.toLabel,
    required this.tagChanges,
    this.trailName,
    this.baseVersion,
    this.geometry,
    this.nodeIds,
    this.baseTags = const {},
    this.difficulty,
    this.electricBicycle,
    this.ebikeClass,
    this.note,
  });

  /// Stages a difficulty rating against [trail]'s current tags.
  factory StagedEdit.difficulty(Trail trail, Difficulty value) {
    // Un-rated writes no tag at all, so a "clear the rating" edit is a
    // deletion. The picker doesn't offer it yet, but the diff handles it.
    final desired = value.imbaScale?.toString();
    final current = trail.tags[Difficulty.osmKey];
    return StagedEdit(
      osmWayId: trail.osmWayId,
      trailName: trail.name,
      baseVersion: trail.version,
      geometry: trail.geometry,
      nodeIds: trail.nodeIds,
      baseTags: trail.tags,
      attribute: TrailAttribute.difficulty,
      fromLabel: trail.hasDifficulty ? trail.difficulty.label : 'Not rated',
      toLabel: value.label,
      difficulty: value,
      tagChanges: {if (desired != current) Difficulty.osmKey: desired},
      // Pro Line writes the same 4 as Expert; the distinction it adds lives in
      // Commons, which isn't built. Say so rather than let the user believe
      // OSM will carry it.
      note: value.isCommonsOnly ? Difficulty.commonsOnlyNote : null,
    );
  }

  /// Stages an e-bike permission against [trail]'s current tags, about the
  /// machine [cap] names.
  ///
  /// The cap is what the rider picked "up to" — a Class 1 in Bend, a pedelec
  /// in Bergamo, and the same `electric_bicycle` key underneath both. It is
  /// resolved from the trail's own position when the caller doesn't say; see
  /// [Trail.ebikeJurisdiction].
  ///
  /// Only the rung being answered about is written. A cap says what *may*
  /// ride, and Steward does not turn that into a ban on everything above it:
  /// the keys those rungs use — `moped`, `motorcycle` — make claims about a
  /// trail far past the question a rider was asked.
  factory StagedEdit.electricBicycle(
    Trail trail,
    EbikeAccess value, {
    EbikeClass? cap,
  }) {
    final ebikeClass = cap ?? trail.ebikeJurisdiction.cap;
    final key = ebikeClass.osmKey;
    final current = trail.tags[key];
    return StagedEdit(
      osmWayId: trail.osmWayId,
      trailName: trail.name,
      baseVersion: trail.version,
      geometry: trail.geometry,
      nodeIds: trail.nodeIds,
      baseTags: trail.tags,
      attribute: TrailAttribute.electricBicycle,
      // A value the picker can't express is still what OSM says, so the
      // before/after names it rather than claiming the trail said nothing.
      fromLabel: switch ((trail.electricBicycle, current)) {
        (final mapped?, _) => mapped.label,
        (null, final raw?) => raw,
        _ => 'Not recorded',
      },
      // The class is part of what is being said, so it is part of the
      // before/after a rider reads back: "allowed up to Class 1".
      toLabel: value == EbikeAccess.allowed
          ? '${value.label} up to ${ebikeClass.label}'
          : value.label,
      electricBicycle: value,
      ebikeClass: ebikeClass,
      tagChanges: {if (value.osmValue != current) key: value.osmValue},
    );
  }

  final int osmWayId;

  /// Captured at staging time so the review list can name the trail without
  /// holding on to the whole [Trail], or re-fetching one the rider has since
  /// clicked away from.
  final String? trailName;

  /// The OSM version this edit was composed against. A changeset built on a
  /// stale version clobbers someone else's work, so submit re-checks it.
  final int? baseVersion;

  /// The trail's shape as of staging time, so the map can keep drawing the
  /// pending change after the rider has clicked away — nothing re-fetches
  /// geometry for a trail that is no longer selected. Null when the edit was
  /// somehow staged before the OSM API answered.
  final List<List<double>>? geometry;

  /// The way's member node IDs at staging time, in [geometry] order. Needed
  /// to write a real `<way>` element without truncating it — see
  /// [Trail.nodeIds].
  final List<int>? nodeIds;

  /// The trail's full tag set at staging time, before [tagChanges] is
  /// applied. An OSM way modify replaces the whole element, so the upload
  /// needs every tag the way carries, not just the ones this edit touches.
  final Map<String, String> baseTags;

  final TrailAttribute attribute;

  /// Plain-language before / after, per the product description's §2 preview.
  final String fromLabel;
  final String toLabel;

  /// The tag diff, already reduced to keys that actually change. A null value
  /// means "delete this tag".
  final Map<String, String?> tagChanges;

  /// Set when [attribute] is [TrailAttribute.difficulty], so the UI can draw
  /// the signage glyph for the staged value.
  final Difficulty? difficulty;

  /// Set when [attribute] is [TrailAttribute.electricBicycle], for the same
  /// reason [difficulty] is.
  final EbikeAccess? electricBicycle;

  /// The rung [electricBicycle] answers about, and whose key this edit
  /// writes. Kept so a re-staged edit — a rebase onto live tags, say — asks
  /// the same question again rather than falling back to a default.
  final EbikeClass? ebikeClass;

  /// A caveat worth showing next to this edit, if any.
  final String? note;

  String get trailLabel => trailName ?? 'Unnamed trail';

  /// False when the change is real to SLAB but invisible to OSM — Pro Line
  /// over an already-Expert trail is the only case today.
  bool get changesOsm => tagChanges.isNotEmpty;

  String get summary => '$fromLabel → $toLabel';

  /// `mtb:scale:imba=3`, or `mtb:scale:imba` removed — for the curious, per
  /// the product description's "plus the actual changeset" preview.
  Iterable<String> get tagDiffLines => tagChanges.entries.map(
    (e) => e.value == null ? '${e.key} removed' : '${e.key}=${e.value}',
  );
}

/// Every pending edit to one trail, plus what the map needs to draw it: the
/// glow follows [geometry], and the badge shows [difficulty] and
/// [electricBicycle].
class StagedTrail {
  const StagedTrail({required this.osmWayId, required this.edits});

  final int osmWayId;

  /// In staging order, never empty.
  final List<StagedEdit> edits;

  String get trailLabel => edits.first.trailLabel;

  /// The shape captured by whichever edit still has one.
  List<List<double>>? get geometry {
    for (final edit in edits) {
      if (edit.geometry != null) return edit.geometry;
    }
    return null;
  }

  /// The member node IDs captured by whichever edit still has them.
  List<int>? get nodeIds {
    for (final edit in edits) {
      if (edit.nodeIds != null) return edit.nodeIds;
    }
    return null;
  }

  /// The OSM version this trail's edits were composed against, for the same
  /// reason [StagedEdit.baseVersion] exists — a stale version clobbers
  /// someone else's work.
  int? get baseVersion {
    for (final edit in edits) {
      if (edit.baseVersion != null) return edit.baseVersion;
    }
    return null;
  }

  /// The way's resulting tag set: every edit's [StagedEdit.baseTags],
  /// overlaid with every edit's [StagedEdit.tagChanges] in staging order.
  /// What the changeset upload's `<way>` element should carry.
  Map<String, String> get resultingTags {
    final tags = <String, String>{};
    for (final edit in edits) {
      tags.addAll(edit.baseTags);
    }
    for (final edit in edits) {
      for (final change in edit.tagChanges.entries) {
        if (change.value == null) {
          tags.remove(change.key);
        } else {
          tags[change.key] = change.value!;
        }
      }
    }
    return tags;
  }

  /// The pending difficulty, when difficulty is one of the staged edits.
  Difficulty? get difficulty {
    for (final edit in edits) {
      if (edit.attribute == TrailAttribute.difficulty) return edit.difficulty;
    }
    return null;
  }

  /// The rating this trail will carry once its edits land: the staged one
  /// where difficulty is being edited, and whatever OSM already says where it
  /// isn't. [Difficulty.unrated] when neither says anything — which is what
  /// the map's purple glow means.
  Difficulty get resultingDifficulty =>
      Difficulty.fromImba(resultingTags[Difficulty.osmKey]);

  /// The pending e-bike permission, when one is among the staged edits. The
  /// map badge draws it beside [difficulty] — a trail can have both pending.
  EbikeAccess? get electricBicycle {
    for (final edit in edits) {
      if (edit.attribute == TrailAttribute.electricBicycle) {
        return edit.electricBicycle;
      }
    }
    return null;
  }

  Map<String, Object?>? toGeoJsonFeature() {
    final shape = geometry;
    if (shape == null) return null;
    return {
      'type': 'Feature',
      'properties': {'osmWayId': osmWayId},
      'geometry': {'type': 'LineString', 'coordinates': shape},
    };
  }

  /// `[lon, lat]` halfway along the trail — where the badge sits.
  ///
  /// Measured in degrees with longitude squeezed by the latitude, which is
  /// close enough to true distance at the scale of one trail and avoids
  /// dragging in a projection for the sake of placing a 24px glyph.
  List<double>? get badgePoint {
    final shape = geometry;
    if (shape == null || shape.isEmpty) return null;
    if (shape.length == 1) return shape.first;

    final spans = <double>[];
    var total = 0.0;
    for (var i = 1; i < shape.length; i++) {
      final span = _distance(shape[i - 1], shape[i]);
      spans.add(span);
      total += span;
    }
    if (total == 0) return shape.first;

    var travelled = 0.0;
    for (var i = 0; i < spans.length; i++) {
      if (travelled + spans[i] >= total / 2) {
        final t = spans[i] == 0 ? 0.0 : (total / 2 - travelled) / spans[i];
        final a = shape[i];
        final b = shape[i + 1];
        return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
      }
      travelled += spans[i];
    }
    return shape.last;
  }

  static double _distance(List<double> a, List<double> b) {
    final lonScale = math.cos((a[1] + b[1]) / 2 * math.pi / 180);
    final dx = (b[0] - a[0]) * lonScale;
    final dy = b[1] - a[1];
    return math.sqrt(dx * dx + dy * dy);
  }
}

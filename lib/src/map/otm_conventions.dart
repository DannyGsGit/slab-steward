/// Trail rendering conventions ported from OpenTrailMap.
///
/// Source: https://github.com/osmus/OpenTrailMap
///   - `style/constants.js`      → the palette below
///   - `js/accessExpressions.js` → the access / specified-ness expressions
///   - `js/styleGenerator.js`    → layer set and filter composition
///
/// Steward deliberately mirrors these rather than inventing its own, so a rider
/// who knows OpenTrailMap reads a Steward map the same way: dashed means
/// informal, faded means you can't ride it, purple means OSM doesn't know.
///
/// The one place Steward departs from them is colour. OpenTrailMap paints a
/// trail by the question being asked of it; SLAB paints it by its IMBA rating
/// — see `docs/specs/map_view.md` — and says the rest with glows.
///
/// Expressions are plain JSON-encodable Dart lists — MapLibre style
/// expressions, handed to the map as part of a style document.
library;

import '../model/difficulty.dart';
import '../model/trail_filters.dart';

/// A MapLibre style expression.
typedef Expr = List<Object?>;

/// Where Steward files a feature's OSM way id in the property bag it passes
/// around — see [osmWayIdFromTileFeature] for where that id now comes from.
///
/// The tileset used to publish this as a column and no longer does, so nothing
/// reads it off a tile any more; the map view splices it in.
const tileIdKey = 'OSM_ID';

/// Planetiler's element-type digit for a way.
///
/// The trails tileset stopped publishing `OSM_ID`, `OSM_VERSION` and the
/// `MIN_/MAX_LON/LAT` bounds as feature attributes — the 2026-08-17 planet
/// build serves tags plus `OSM_TIMESTAMP` and nothing else. Identity moved to
/// the MVT feature id, which planetiler encodes as `osmId * 10 + type`, type
/// being 1 for a node, 2 for a way and 3 for a relation.
const _wayTypeDigit = 2;

/// The OSM way id behind a rendered tile feature, or null if the feature isn't
/// a way Steward can edit.
///
/// A trail with no recoverable id is not something a steward can fix, so it is
/// dropped rather than guessed at.
int? osmWayIdFromTileFeature(Object? featureId) {
  final id = switch (featureId) {
    final num n => n.toInt(),
    // Android hands ids back as strings — see `RenderedFeature.id`.
    final String s => int.tryParse(s),
    _ => null,
  };
  if (id == null || id <= 0 || id % 10 != _wayTypeDigit) return null;
  return id ~/ 10;
}

/// The tile feature id a given OSM way is drawn under — the inverse of
/// [osmWayIdFromTileFeature], for matching an override against the feature the
/// map is rendering.
int tileFeatureIdForWay(int osmWayId) => osmWayId * 10 + _wayTypeDigit;

/// A feature's own id, as an expression. The tileset's identity column in all
/// but name — see [osmWayIdFromTileFeature].
final Expr _featureId = ['id'];

/// How the expressions below reach a feature's tags.
///
/// [TagSource.tiles] is the plain reading: ask the vector tile the feature
/// came from. That tileset is a periodic planet build — six days stale is
/// normal — so a trail someone just rated still renders as unrated, which is
/// precisely the question the lenses exist to answer.
///
/// [TagSource.overriding] answers from Steward's own fresher knowledge for
/// the trails it holds tags for, and falls through to the tile for every
/// other feature. Substituting at the tag level rather than at the verdict
/// means the conventions below stay the single definition of what "specified"
/// and "allowed" mean: the same expressions simply run against better data.
class TagSource {
  const TagSource.tiles() : _byTileId = const {};

  /// [byTileId] is keyed by OSM way id — the same id the API answers for.
  /// The expressions below encode it to the tile's own feature id, which is
  /// where identity lives now; see [tileFeatureIdForWay].
  const TagSource.overriding(Map<int, Map<String, String>> byTileId)
    : _byTileId = byTileId;

  final Map<int, Map<String, String>> _byTileId;

  bool get isEmpty => _byTileId.isEmpty;

  /// A feature's value for [key], as an expression.
  ///
  /// An overridden trail answers only from its override: a trail whose
  /// override has no [key] reads as empty string, *not* as whatever the tile
  /// still says, because that is how a tag deletion has to look.
  Expr get(String key) {
    if (isEmpty) return ['get', key];
    // Grouped by value, so a hundred trails that all gained `surface=dirt`
    // cost one branch rather than a hundred.
    final idsByValue = <String, List<int>>{};
    _byTileId.forEach((id, tags) {
      idsByValue
          .putIfAbsent(tags[key] ?? '', () => [])
          .add(tileFeatureIdForWay(id));
    });
    return [
      'match',
      _featureId,
      for (final entry in idsByValue.entries) ...[entry.value, entry.key],
      // `to-string` both pins the branch types together — MapLibre infers a
      // `match`'s output type from its branches — and turns a tag the tile
      // doesn't carry into the same empty string an override uses for one it
      // has deleted.
      [
        'to-string',
        ['get', key],
      ],
    ];
  }

  /// Whether a feature carries [key] at all, as an expression.
  Expr has(String key) {
    if (isEmpty) return ['has', key];
    final present = <int>[];
    final absent = <int>[];
    _byTileId.forEach((id, tags) {
      (tags.containsKey(key) ? present : absent).add(tileFeatureIdForWay(id));
    });
    return [
      'case',
      if (present.isNotEmpty) ...[
        [
          'in',
          _featureId,
          ['literal', present],
        ],
        true,
      ],
      if (absent.isNotEmpty) ...[
        [
          'in',
          _featureId,
          ['literal', absent],
        ],
        false,
      ],
      ['has', key],
    ];
  }
}

// ---------------------------------------------------------------------------
// Palette — style/constants.js
// ---------------------------------------------------------------------------

/// A plain trail, in no scheme that has an opinion about it. Only the legend
/// draws this now — on the map every line takes its colour from the rating,
/// per `docs/specs/map_view.md`.
const trailColor = '#4f2e28';

/// Attribute is missing — the thing a steward is here to fix. Also the colour
/// of an un-rated trail, which is the same statement about difficulty: OSM
/// doesn't say. See [difficultyColor].
const unspecifiedColor = '#c100cc';

// --- Difficulty ------------------------------------------------------------
//
// The map's primary vocabulary: a trail line is coloured by its IMBA rating,
// in SLAB's own signage colours, so the line under the wheel and the chip on
// the sign agree. Taken from `assets/slab/difficulty/*.svg` — change them
// there and here together.

/// IMBA 0 and 1 — the green-circle tier.
const easyTrailColor = '#2f6b4d';

/// IMBA 2, the blue square.
const mediumTrailColor = '#3b5fc6';

/// IMBA 3, the black diamond.
const hardTrailColor = '#16191c';

/// IMBA 4, the double black. Red rather than a second black: the spec's "very
/// hard" has to be tellable from "hard" at a glance, and two blacks aren't.
const veryHardTrailColor = '#ef4b18';

/// Trails a mode isn't allowed on keep their rating colour and are drawn
/// through this, so "you can't ride here" reads as a fade rather than as a
/// second, competing hue.
const disallowedOpacity = 0.45;

/// The glow on trails matching the Highlight rules — the ones a steward is
/// hunting for.
const highlightGlowColor = '#ffd400';

/// The glow on trails in the working set.
const selectionColor = '#00d1c1';

const labelColor = '#333333';
const labelHaloColor = '#ffffff';
const bridgeCasingColor = '#bbbbbb';

/// The line colour for a rating.
///
/// [Difficulty.beginner] rides with [Difficulty.easy] rather than taking the
/// purple its signage chip wears: on the map purple is spoken for — it is what
/// an un-rated trail draws in — and IMBA 0 and 1 are the same green tier on a
/// trailhead board anyway.
String difficultyColor(Difficulty difficulty) => switch (difficulty) {
  Difficulty.beginner || Difficulty.easy => easyTrailColor,
  Difficulty.medium => mediumTrailColor,
  Difficulty.difficult => hardTrailColor,
  Difficulty.expert || Difficulty.proLine => veryHardTrailColor,
  Difficulty.unrated => unspecifiedColor,
};

/// A trail's line colour, read from its own `mtb:scale:imba`.
///
/// Through [TagSource] like every other expression here, so a trail the rider
/// has just rated recolours from Steward's override rather than waiting for
/// the next planet build.
Expr difficultyLineColor(TagSource tags) {
  // Grouped by colour, so the two ratings that share the green tier cost one
  // branch rather than two.
  final scalesByColor = <String, List<String>>{};
  for (final difficulty in Difficulty.values) {
    final scale = difficulty.imbaScale;
    if (scale == null) continue;
    final scales = scalesByColor.putIfAbsent(
      difficultyColor(difficulty),
      () => [],
    );
    if (!scales.contains('$scale')) scales.add('$scale');
  }
  return [
    'match',
    // A trail with no rating at all reads as the empty string rather than as
    // null, which `match` would refuse — and lands on the un-rated default,
    // which is exactly what "no rating" means.
    ['to-string', tags.get(Difficulty.osmKey)],
    for (final entry in scalesByColor.entries) ...[entry.value, entry.key],
    difficultyColor(Difficulty.unrated),
  ];
}

// ---------------------------------------------------------------------------
// Access expressions — js/accessExpressions.js
// ---------------------------------------------------------------------------

/// Values that mean "you may not go here". `limited` is there for wheelchair.
const _noAccessValues = ['no', 'private', 'discouraged', 'limited'];

final Expr _noAccessLiteral = ['literal', _noAccessValues];

/// The trails tileset also carries waterways and ferries; Steward only edits
/// land trails, so everything is scoped to features with a `highway` tag.
Expr isHighway(TagSource tags) => tags.has('highway');

Expr _isNotHighway(TagSource tags) => ['!', isHighway(tags)];

/// Tags that would independently forbid a mode, keyed by mode.
/// Only the modes Steward offers are ported.
Expr? _impliedNo(String mode, TagSource tags) => switch (mode) {
  'mtb' => [
    'any',
    ['in', tags.get('vehicle'), _noAccessLiteral],
    ['in', tags.get('bicycle'), _noAccessLiteral],
    _isNotHighway(tags),
  ],
  'foot' => _isNotHighway(tags),
  _ => null,
};

/// Tags that would independently permit a mode, keyed by mode.
Expr? _impliedYes(String mode, TagSource tags) => switch (mode) {
  'foot' => [
    'in',
    tags.get('highway'),
    [
      'literal',
      ['path', 'footway', 'steps', 'service', 'unclassified', 'residential'],
    ],
  ],
  _ => null,
};

Expr _notNoAccess(String key, TagSource tags) => [
  '!',
  ['in', tags.get(key), _noAccessLiteral],
];

/// True for features the given travel mode is allowed on.
Expr modeIsAllowed(String mode, TagSource tags) {
  final expr = <Object?>[
    'all',
    [
      'any',
      [
        'all',
        ['!', tags.has(mode)],
        _notNoAccess('access', tags),
      ],
      ['all', tags.has(mode), _notNoAccess(mode, tags)],
    ],
  ];
  final impliedNo = _impliedNo(mode, tags);
  if (impliedNo != null) {
    expr.add([
      'any',
      tags.has(mode),
      ['!', impliedNo],
    ]);
  }
  return expr;
}

/// True for features tagged well enough to say *whether or not* the mode is
/// allowed. A trail that is merely silent on the subject is not "specified" —
/// that distinction is what the purple/teal lens is measuring.
Expr accessIsSpecified(String mode, TagSource tags) {
  final unknownWithoutOwnTag = <Object?>[
    'all',
    ['!', tags.has(mode)],
    _notNoAccess('access', tags),
  ];
  final impliedYes = _impliedYes(mode, tags);
  if (impliedYes != null) unknownWithoutOwnTag.add(['!', impliedYes]);
  final impliedNo = _impliedNo(mode, tags);
  if (impliedNo != null) unknownWithoutOwnTag.add(['!', impliedNo]);

  return [
    '!',
    [
      'any',
      unknownWithoutOwnTag,
      // Explicitly `unknown` is never specified, whatever else is present.
      ['==', tags.get(mode), 'unknown'],
    ],
  ];
}

/// Every tag the expressions in this file read.
///
/// Two trails that agree on all of these render identically, whatever else
/// differs between them — which is what lets Steward tell a read that
/// contradicts the tileset from one that merely repeats it in more detail.
/// The tileset carries a subset of OSM's tags, so a raw tag-map comparison
/// would call every single read a contradiction.
///
/// Keep this in step with the expressions above; it is derived from them by
/// hand because a style expression can't be asked what it reads.
const renderedTagKeys = {
  'highway',
  'informal',
  'bridge',
  'name',
  'access',
  'vehicle',
  'bicycle',
  'foot',
  'mtb',
  'mtb:scale:imba',
  'surface',
  'electric_bicycle',
  'electric_mofa',
};

/// Surface values that mean pavement.
///
/// The paved half of OSM's `surface` vocabulary, plus the two spellings of
/// concrete that carry a suffix. `sett` and `cobblestone` are in here because
/// they are laid surfaces even where they ride like anything but.
const _pavedSurfaces = [
  'asphalt',
  'chipseal',
  'cobblestone',
  'concrete',
  'concrete:lanes',
  'concrete:plates',
  'metal',
  'paved',
  'paving_stones',
  'sett',
];

/// True for features of the kind [kind] names.
///
/// A trail can match several — a paved informal footway is a real thing in
/// OSM — which is exactly why the toggles are independent and a trail is
/// hidden when it matches any kind that is switched off.
Expr trailKindMatches(TrailKind kind, TagSource tags) => switch (kind) {
  TrailKind.informal => ['==', tags.get('informal'), 'yes'],
  TrailKind.track => ['==', tags.get('highway'), 'track'],
  TrailKind.footway => ['==', tags.get('highway'), 'footway'],
  TrailKind.paved => [
    'in',
    tags.get('surface'),
    ['literal', _pavedSurfaces],
  ],
};

/// True for features none of the switched-off kinds claim — what the map is
/// willing to draw at all.
///
/// Applied to every layer in the overlay, hit targets included: a trail the
/// rider has hidden must not be selectable through the line that is no longer
/// there.
Expr isKindShown(Set<TrailKind> shown, TagSource tags) {
  final hidden = [
    for (final kind in TrailKind.values)
      if (!shown.contains(kind)) ['!', trailKindMatches(kind, tags)],
  ];
  return hidden.isEmpty ? ['literal', true] : ['all', ...hidden];
}

/// True when at least one of [keys] carries a usable value.
Expr attributeIsSpecified(List<String> keys, TagSource tags) => [
  'any',
  for (final key in keys)
    [
      'all',
      tags.has(key),
      ['!=', tags.get(key), 'unknown'],
    ],
];

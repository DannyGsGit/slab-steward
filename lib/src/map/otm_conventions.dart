/// Trail rendering conventions ported from OpenTrailMap.
///
/// Source: https://github.com/osmus/OpenTrailMap
///   - `style/constants.js`      → the palette below
///   - `js/accessExpressions.js` → the access / specified-ness expressions
///   - `js/styleGenerator.js`    → layer set and filter composition
///
/// Steward deliberately mirrors these rather than inventing its own, so a rider
/// who knows OpenTrailMap reads a Steward map the same way: dashed means
/// informal, pale means you can't ride it, purple means OSM doesn't know.
///
/// Expressions are plain JSON-encodable Dart lists — MapLibre style
/// expressions, handed to the map as part of a style document.
library;

/// A MapLibre style expression.
typedef Expr = List<Object?>;

/// The tileset column carrying a feature's OSM way id.
const tileIdKey = 'OSM_ID';

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

  /// [byTileId] is keyed by the id the *tileset* uses — the same OSM way id
  /// the API answers for.
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
      idsByValue.putIfAbsent(tags[key] ?? '', () => []).add(id);
    });
    return [
      'match',
      ['get', tileIdKey],
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
      (tags.containsKey(key) ? present : absent).add(id);
    });
    return [
      'case',
      if (present.isNotEmpty) ...[
        [
          'in',
          ['get', tileIdKey],
          ['literal', present],
        ],
        true,
      ],
      if (absent.isNotEmpty) ...[
        [
          'in',
          ['get', tileIdKey],
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

const trailColor = '#4f2e28';
const noAccessTrailColor = '#cc9e7e';

/// Attribute is present and readable.
const specifiedColor = '#007f79';

/// Attribute is missing — the thing a steward is here to fix.
const unspecifiedColor = '#c100cc';

const selectionColor = '#ffd400';

/// Steward's own, not OpenTrailMap's: the halo drawn around a trail that has
/// an edit waiting to be submitted. Blue because nothing else in the trail
/// palette is — a pending change has to read as *ours*, not as data.
const stagedEditColor = '#2f80ed';
const labelColor = '#333333';
const labelHaloColor = '#ffffff';
const bridgeCasingColor = '#bbbbbb';

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
};

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

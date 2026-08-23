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

final Expr _noAccessLiteral = [
  'literal',
  _noAccessValues,
];

/// The trails tileset also carries waterways and ferries; Steward only edits
/// land trails, so everything is scoped to features with a `highway` tag.
final Expr isHighway = ['has', 'highway'];

final Expr _isNotHighway = [
  '!',
  isHighway,
];

/// Tags that would independently forbid a mode, keyed by mode.
/// Only the modes Steward offers are ported.
final Map<String, Expr> _impliedNo = {
  'mtb': [
    'any',
    ['in', ['get', 'vehicle'], _noAccessLiteral],
    ['in', ['get', 'bicycle'], _noAccessLiteral],
    _isNotHighway,
  ],
  'foot': _isNotHighway,
};

/// Tags that would independently permit a mode, keyed by mode.
final Map<String, Expr> _impliedYes = {
  'foot': [
    'in',
    ['get', 'highway'],
    [
      'literal',
      ['path', 'footway', 'steps', 'service', 'unclassified', 'residential'],
    ],
  ],
};

Expr _notNoAccess(String key) => [
  '!',
  ['in', ['get', key], _noAccessLiteral],
];

/// True for features the given travel mode is allowed on.
Expr modeIsAllowed(String mode) {
  final expr = <Object?>[
    'all',
    [
      'any',
      ['all', ['!', ['has', mode]], _notNoAccess('access')],
      ['all', ['has', mode], _notNoAccess(mode)],
    ],
  ];
  final impliedNo = _impliedNo[mode];
  if (impliedNo != null) {
    expr.add(['any', ['has', mode], ['!', impliedNo]]);
  }
  return expr;
}

/// True for features tagged well enough to say *whether or not* the mode is
/// allowed. A trail that is merely silent on the subject is not "specified" —
/// that distinction is what the purple/teal lens is measuring.
Expr accessIsSpecified(String mode) {
  final unknownWithoutOwnTag = <Object?>[
    'all',
    ['!', ['has', mode]],
    _notNoAccess('access'),
  ];
  final impliedYes = _impliedYes[mode];
  if (impliedYes != null) unknownWithoutOwnTag.add(['!', impliedYes]);
  final impliedNo = _impliedNo[mode];
  if (impliedNo != null) unknownWithoutOwnTag.add(['!', impliedNo]);

  return [
    '!',
    [
      'any',
      unknownWithoutOwnTag,
      // Explicitly `unknown` is never specified, whatever else is present.
      ['==', ['get', mode], 'unknown'],
    ],
  ];
}

/// True when at least one of [keys] carries a usable value.
Expr attributeIsSpecified(List<String> keys) => [
  'any',
  for (final key in keys)
    ['all', ['has', key], ['!=', ['get', key], 'unknown']],
];

/// Builds the map style: OpenStreetMap US's published OpenTrailMap basemap with
/// Steward's trail overlay spliced into it.
///
/// This is a port of `js/styleGenerator.js` from
/// https://github.com/osmus/OpenTrailMap, trimmed to what Steward needs (land
/// trails only — no waterways, no oneway arrows, since v1 edits neither).
library;

import 'dart:convert';

import '../model/lens.dart';
import 'otm_conventions.dart';

/// OpenTrailMap's published basemap stylesheet.
const openTrailMapStyleUrl = 'https://opentrailmap.us/style.json';

/// The public OSM US trails tileset. Carries `mtb:scale:imba`, `surface`,
/// `informal`, `OSM_ID` and `OSM_VERSION` — everything the discovery half of
/// Steward needs, without touching Overpass.
const _trailsTileJsonUrl = 'https://tiles.openstreetmap.us/vector/trails.json';

const _trailsSourceId = 'trails';
const _trailsSourceLayer = 'trail';

/// GeoJSON source holding the geometry of the currently selected trail.
///
/// The Flutter MapLibre binding has no `setFeatureState`, so selection is drawn
/// from its own source rather than as a feature-state highlight the way
/// OpenTrailMap does it. Geometry arrives from the OSM API on selection.
const selectionSourceId = 'steward-selection';

/// GeoJSON source holding the geometry of every trail with a pending edit.
///
/// Same reason as [selectionSourceId] — no feature-state binding — but a
/// separate source because the two are independent: a trail keeps its glow
/// after the rider clicks away from it.
const stagedSourceId = 'steward-staged';

/// Layer the map hit-tests against. A wide transparent line, so thin trails are
/// still easy to click.
const pointerTargetLayerId = 'trails-pointer-targets';

/// Marker layer in the published basemap that the overlay is inserted before.
const _qaInsertionPoint = 'qa_insertion_point';

/// Basemap layers that would double-render the trails the overlay draws itself.
const _basemapTrailLayerIds = [
  'trails_official',
  'trails_informal',
  'trail_labels',
  'oneway_arrows',
];

/// The trail tileset is far too dense to draw whole-country, and the lenses are
/// only meaningful at street scale.
const overlayMinZoom = 10.0;

const _emptyFeatureCollection = '{"type":"FeatureCollection","features":[]}';

final Expr _lineWidth = ['interpolate', ['linear'], ['zoom'], 12, 1, 22, 5];
final Expr _selectedLineWidth = ['interpolate', ['linear'], ['zoom'], 12, 9, 22, 13];

/// The glow is drawn as two blurred lines rather than one: the wide outer
/// wash is what catches the eye from across the map, and the tighter inner
/// pass keeps the trail's own line from looking washed out at close zoom.
final Expr _stagedGlowWidth = ['interpolate', ['linear'], ['zoom'], 12, 14, 22, 28];
final Expr _stagedCoreWidth = ['interpolate', ['linear'], ['zoom'], 12, 7, 22, 15];

/// Everything a set of overlay layers is built from, resolved once per
/// (mode, lens) pair.
class _OverlayContext {
  _OverlayContext(this.mode, this.lens);

  final TravelMode mode;
  final Lens lens;

  /// Trails the chosen mode is allowed on.
  late final Expr allowed = switch (mode.osmKey) {
    null => ['literal', true],
    final key => modeIsAllowed(key),
  };

  /// Whether the trail answers the lens' question.
  late final Expr specified = switch (lens) {
    Lens.none => ['literal', true],
    Lens.access => switch (mode.osmKey) {
      null => ['literal', true],
      final key => accessIsSpecified(key),
    },
    _ => lens.requiresAllKeys
        ? ['all', for (final k in lens.keys) attributeIsSpecified([k])]
        : attributeIsSpecified(lens.keys),
  };

  /// Colour for trails that pass the lens.
  String get passColor => lens.tintsSpecified ? specifiedColor : trailColor;

  /// OpenTrailMap hides trails the chosen mode can't use. Steward shows them
  /// pale and marked instead — the same visual vocabulary, but a steward still
  /// needs to be able to click a trail in order to fix its tags, and a hidden
  /// trail can't be clicked.
  bool get showsDisallowed => mode.osmKey != null;

  bool get showsUnspecified => lens.showsUnspecified;
}

/// Per-layer filters. The union of these is what labels and hit targets use.
Map<String, Expr> _trailFilters(_OverlayContext ctx) {
  final informal = <Object?>['==', ['get', 'informal'], 'yes'];
  final formal = <Object?>['!=', ['get', 'informal'], 'yes'];
  final allowed = ctx.allowed;
  final specified = ctx.specified;
  final disallowed = <Object?>['!', allowed];

  return {
    'paths': ['all', isHighway, allowed, specified, formal],
    'informal-paths': ['all', isHighway, allowed, specified, informal],
    // Deliberately not filtered by [specified]: "you can't ride here" outranks
    // "the data is missing", and a trail that matched neither condition would
    // fall through every layer and vanish off the map.
    'disallowed-paths': [
      'all', ctx.showsDisallowed, isHighway, disallowed, formal,
    ],
    'disallowed-informal-paths': [
      'all', ctx.showsDisallowed, isHighway, disallowed, informal,
    ],
    'unspecified-paths': [
      'all', ctx.showsUnspecified, isHighway, allowed, ['!', specified], formal,
    ],
    'unspecified-informal-paths': [
      'all', ctx.showsUnspecified, isHighway, allowed, ['!', specified], informal,
    ],
  };
}

Map<String, Object?> _trailLine(
  String id,
  Map<String, Object?> paint, [
  Map<String, Object?> extra = const {},
]) => {
  'id': id,
  'source': _trailsSourceId,
  'source-layer': _trailsSourceLayer,
  'type': 'line',
  'layout': {'line-cap': 'round', 'line-join': 'round'},
  'paint': paint,
  ...extra,
};

/// The overlay's layers, bottom to top.
List<Map<String, Object?>> _trailLayers(
  _OverlayContext ctx,
  Map<String, Expr> filters,
  Expr combinedFilter,
) {
  // Informal trails are dashed, as are trails the chosen mode isn't allowed on.
  final lines = <(String, String, bool)>[
    ('informal-paths', ctx.passColor, true),
    ('disallowed-informal-paths', noAccessTrailColor, true),
    ('unspecified-informal-paths', unspecifiedColor, true),
    ('disallowed-paths', noAccessTrailColor, true),
  ];
  final linesAboveSymbols = <(String, String, bool)>[
    ('unspecified-paths', unspecifiedColor, false),
    ('paths', ctx.passColor, false),
  ];

  Map<String, Object?> lineLayer((String, String, bool) spec) {
    final (id, color, isDashed) = spec;
    return _trailLine(
      id,
      {
        'line-width': _lineWidth,
        'line-color': color,
        if (isDashed) 'line-dasharray': [2, 2],
      },
      {'filter': filters[id]},
    );
  }

  return [
    _trailLine(
      'bridge-casings',
      {
        'line-gap-width': _lineWidth,
        'line-width': ['interpolate', ['linear'], ['zoom'], 16, 2, 20, 6],
        'line-color': bridgeCasingColor,
      },
      {
        'minzoom': 14,
        'layout': {'line-cap': 'butt', 'line-join': 'round'},
        'filter': [
          'all',
          ['has', 'bridge'],
          [
            '!',
            [
              'in',
              ['get', 'bridge'],
              ['literal', ['no', 'abandoned', 'raised', 'proposed', 'dismantled']],
            ],
          ],
          combinedFilter,
        ],
      },
    ),
    {
      'id': 'staged-glow',
      'source': stagedSourceId,
      'type': 'line',
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {
        'line-color': stagedEditColor,
        'line-width': _stagedGlowWidth,
        'line-blur': 8,
        'line-opacity': 0.35,
      },
    },
    {
      'id': 'staged-glow-core',
      'source': stagedSourceId,
      'type': 'line',
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {
        'line-color': stagedEditColor,
        'line-width': _stagedCoreWidth,
        'line-blur': 3,
        'line-opacity': 0.55,
      },
    },
    {
      'id': 'selected-trail',
      'source': selectionSourceId,
      'type': 'line',
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {
        'line-color': selectionColor,
        'line-width': _selectedLineWidth,
        'line-opacity': 0.75,
      },
    },
    ...lines.map(lineLayer),
    {
      'id': 'disallowed-symbols',
      'source': _trailsSourceId,
      'source-layer': _trailsSourceLayer,
      'type': 'symbol',
      'minzoom': 13,
      'filter': ['all', ctx.showsDisallowed, ['!', ctx.allowed], combinedFilter],
      'layout': {
        'symbol-placement': 'line',
        'symbol-spacing': 200,
        'icon-image': 'no_entry',
        'icon-size': 0.4,
        'icon-overlap': 'always',
        'icon-rotation-alignment': 'viewport',
      },
      'paint': {
        'icon-color': '#ee2222',
        'icon-halo-color': labelHaloColor,
        'icon-halo-width': 1.75,
        'icon-halo-blur': 0.5,
      },
    },
    ...linesAboveSymbols.map(lineLayer),
    {
      'id': 'trails-labels',
      'source': _trailsSourceId,
      'source-layer': _trailsSourceLayer,
      'type': 'symbol',
      'minzoom': 14,
      'filter': ['all', ['has', 'name'], combinedFilter],
      'layout': {
        'text-field': ['get', 'name'],
        'text-font': ['Noto Sans Regular'],
        'text-size': 12,
        'symbol-placement': 'line',
        'text-max-angle': 30,
      },
      'paint': {
        'text-color': labelColor,
        'text-halo-width': 1.5,
        'text-halo-color': labelHaloColor,
      },
    },
    {
      'id': pointerTargetLayerId,
      'source': _trailsSourceId,
      'source-layer': _trailsSourceLayer,
      'type': 'line',
      'paint': {'line-color': 'transparent', 'line-width': 16},
      'filter': combinedFilter,
    },
  ];
}

/// Splices Steward's trail overlay into [baseStyle] and returns the result as a
/// style document ready to hand to MapLibre.
///
/// [baseStyle] is mutated in place — callers pass a fresh decode each time.
Map<String, Object?> buildStewardStyle(
  Map<String, Object?> baseStyle, {
  required TravelMode mode,
  required Lens lens,
}) {
  final sources = baseStyle['sources'] as Map<String, Object?>;
  sources[_trailsSourceId] = {
    'type': 'vector',
    'url': _trailsTileJsonUrl,
    'attribution':
        'Trails © <a href="https://openstreetmap.org/copyright">OpenStreetMap</a> '
        'contributors · tiles by <a href="https://openstreetmap.us">OpenStreetMap US</a>',
  };
  for (final id in [selectionSourceId, stagedSourceId]) {
    sources[id] = {
      'type': 'geojson',
      'data': jsonDecode(_emptyFeatureCollection),
    };
  }

  final layers = (baseStyle['layers'] as List).cast<Map<String, Object?>>();

  // Hide the basemap's own trail layers so trails aren't drawn twice.
  for (final layer in layers) {
    if (_basemapTrailLayerIds.contains(layer['id'])) {
      layer['layout'] = {
        ...?(layer['layout'] as Map<String, Object?>?),
        'visibility': 'none',
      };
    }
  }

  final ctx = _OverlayContext(mode, lens);
  final filters = _trailFilters(ctx);
  final combinedFilter = <Object?>['any', ...filters.values];

  final overlay = _trailLayers(ctx, filters, combinedFilter)
      .map((layer) => {'minzoom': overlayMinZoom, ...layer})
      .toList();

  final insertionIndex = layers.indexWhere((l) => l['id'] == _qaInsertionPoint);
  if (insertionIndex < 0) {
    throw StateError('Base style is missing its "$_qaInsertionPoint" marker layer');
  }
  layers.insertAll(insertionIndex, overlay);

  return baseStyle;
}

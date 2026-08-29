/// Builds the map style: OpenStreetMap US's published OpenTrailMap basemap with
/// Steward's trail overlay spliced into it.
///
/// This is a port of `js/styleGenerator.js` from
/// https://github.com/osmus/OpenTrailMap, trimmed to what Steward needs (land
/// trails only — no waterways, no oneway arrows, since v1 edits neither).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/lens.dart';
import '../model/trail_filters.dart';
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

final Expr _lineWidth = [
  'interpolate',
  ['linear'],
  ['zoom'],
  12,
  1,
  22,
  5,
];
final Expr _selectedLineWidth = [
  'interpolate',
  ['linear'],
  ['zoom'],
  12,
  9,
  22,
  13,
];

/// The glow is drawn as two blurred lines rather than one: the wide outer
/// wash is what catches the eye from across the map, and the tighter inner
/// pass keeps the trail's own line from looking washed out at close zoom.
final Expr _stagedGlowWidth = [
  'interpolate',
  ['linear'],
  ['zoom'],
  12,
  14,
  22,
  28,
];
final Expr _stagedCoreWidth = [
  'interpolate',
  ['linear'],
  ['zoom'],
  12,
  7,
  22,
  15,
];

/// Everything a set of overlay layers is built from, resolved once per
/// (mode, selection) pair.
class _OverlayContext {
  _OverlayContext(this.modes, this.kinds, this.lenses, this.tags);

  /// Who the map is being asked about. Empty asks nothing: every trail is
  /// "allowed", and nothing is drawn as shut.
  final Set<TravelMode> modes;

  /// The kinds of line the rider is willing to see.
  final Set<TrailKind> kinds;

  /// The questions being asked. A trail has to answer all of them to pass.
  final Set<Lens> lenses;

  /// Where the filters read tags from — the tileset, or the tileset corrected
  /// by what Steward has since read or written.
  final TagSource tags;

  /// Trails every chosen mode is allowed on.
  ///
  /// All-of rather than any-of: a rider who ticks both bikes and walkers is
  /// asking about the shared-use network, not about the union of two
  /// networks.
  late final Expr allowed = switch ([
    for (final mode in modes) modeIsAllowed(mode.osmKey, tags),
  ]) {
    [] => ['literal', true],
    [final only] => only,
    final tests => ['all', ...tests],
  };

  /// Trails of a kind the rider hasn't switched off.
  late final Expr shown = isKindShown(kinds, tags);

  /// One test per question the selection actually asks. [Lens.access] under
  /// [TravelMode.all] asks nothing, so it contributes nothing.
  late final List<Expr> _tests = [
    for (final lens in lenses.inOrder)
      if (lens == Lens.access)
        for (final mode in modes) accessIsSpecified(mode.osmKey, tags)
      // Any one of a lens' keys answering it is enough — see [Lens.keys].
      else
        attributeIsSpecified(lens.keys, tags),
  ];

  /// Whether the trail answers every selected lens' question.
  ///
  /// All-of, so stacking lenses narrows: this is what the old fixed
  /// "Missing any" lens did across its three keys, generalised to whatever the
  /// rider has ticked.
  late final Expr specified = switch (_tests) {
    [] => ['literal', true],
    [final only] => only,
    final tests => ['all', ...tests],
  };

  /// Colour for trails that pass every selected lens.
  String get passColor => lenses.tintsSpecified ? specifiedColor : trailColor;

  /// OpenTrailMap hides trails the chosen mode can't use. Steward shows them
  /// pale and marked instead — the same visual vocabulary, but a steward still
  /// needs to be able to click a trail in order to fix its tags, and a hidden
  /// trail can't be clicked.
  bool get showsDisallowed => modes.isNotEmpty;

  /// Nothing is purple when nothing is being asked.
  bool get showsUnspecified => _tests.isNotEmpty;
}

/// Per-layer filters. The union of these is what labels and hit targets use.
Map<String, Expr> _trailFilters(_OverlayContext ctx) {
  final informal = <Object?>['==', ctx.tags.get('informal'), 'yes'];
  final formal = <Object?>['!=', ctx.tags.get('informal'), 'yes'];
  final allowed = ctx.allowed;
  final specified = ctx.specified;
  final disallowed = <Object?>['!', allowed];
  // Everything the overlay is willing to draw at all: a trail line, of a kind
  // the rider hasn't switched off.
  final drawable = <Object?>['all', isHighway(ctx.tags), ctx.shown];

  return {
    'paths': ['all', drawable, allowed, specified, formal],
    'informal-paths': ['all', drawable, allowed, specified, informal],
    // Deliberately not filtered by [specified]: "you can't ride here" outranks
    // "the data is missing", and a trail that matched neither condition would
    // fall through every layer and vanish off the map.
    'disallowed-paths': [
      'all',
      ctx.showsDisallowed,
      drawable,
      disallowed,
      formal,
    ],
    'disallowed-informal-paths': [
      'all',
      ctx.showsDisallowed,
      drawable,
      disallowed,
      informal,
    ],
    'unspecified-paths': [
      'all',
      ctx.showsUnspecified,
      drawable,
      allowed,
      ['!', specified],
      formal,
    ],
    'unspecified-informal-paths': [
      'all',
      ctx.showsUnspecified,
      drawable,
      allowed,
      ['!', specified],
      informal,
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
        'line-width': [
          'interpolate',
          ['linear'],
          ['zoom'],
          16,
          2,
          20,
          6,
        ],
        'line-color': bridgeCasingColor,
      },
      {
        'minzoom': 14,
        'layout': {'line-cap': 'butt', 'line-join': 'round'},
        'filter': [
          'all',
          ctx.tags.has('bridge'),
          [
            '!',
            [
              'in',
              ctx.tags.get('bridge'),
              [
                'literal',
                ['no', 'abandoned', 'raised', 'proposed', 'dismantled'],
              ],
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
      'filter': [
        'all',
        ctx.showsDisallowed,
        ['!', ctx.allowed],
        combinedFilter,
      ],
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
      'filter': ['all', ctx.tags.has('name'), combinedFilter],
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

/// The planet-build timestamp the trail tileset was cut from, or null if the
/// TileJSON can't be read or doesn't say.
///
/// Published by planetiler in the TileJSON as `timestamp`, and typically some
/// days behind live OSM — which is the whole reason [TagSource.overriding]
/// exists, and the clock an override is measured against.
Future<DateTime?> fetchTilesetBuiltAt() async {
  try {
    final response = await http.get(Uri.parse(_trailsTileJsonUrl));
    if (response.statusCode != 200) return null;
    final stamp =
        (jsonDecode(response.body) as Map<String, Object?>)['timestamp'];
    return stamp is String ? DateTime.parse(stamp).toUtc() : null;
  } catch (_) {
    return null;
  }
}

/// Splices Steward's trail overlay into [baseStyle] and returns the result as a
/// style document ready to hand to MapLibre.
///
/// [baseStyle] is mutated in place — callers pass a fresh decode each time.
Map<String, Object?> buildStewardStyle(
  Map<String, Object?> baseStyle, {
  required Set<TravelMode> modes,
  required Set<Lens> lenses,
  Set<TrailKind> kinds = const {...TrailKind.values},
  TagSource tags = const TagSource.tiles(),
}) {
  final sources = baseStyle['sources'] as Map<String, Object?>;
  sources[_trailsSourceId] = {
    'type': 'vector',
    'url': _trailsTileJsonUrl,
    'attribution':
        'Trails © <a href="https://openstreetmap.org/copyright">OpenStreetMap</a> '
        'contributors, tiles by <a href="https://openstreetmap.us">OpenStreetMap US</a>',
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

  final ctx = _OverlayContext(modes, kinds, lenses, tags);
  final filters = _trailFilters(ctx);

  // What the overlay draws, for the layers that need to cover all of it —
  // labels, hit targets, bridge casings, the no-entry symbols.
  //
  // The obvious spelling is `['any', ...filters.values]`, and that is what
  // this was. But the six line layers *partition* the trails — allowed and
  // specified, allowed and not, and disallowed — so their union has always
  // been exactly this, and spelling it out cost the four layers below a
  // verbatim copy of all six filters each. Harmless when a filter is a dozen
  // bytes; with [TagSource.overriding] substituting tags into every one of
  // them, it was 80% of the style document. `lens_override_test.dart` holds
  // the two spellings to each other.
  //
  // The kind toggles ride along here rather than being a seventh layer: a
  // hidden kind is hidden from the labels and the hit targets too, or a rider
  // would still be able to click the sidewalk they just switched off.
  final combinedFilter = <Object?>['all', isHighway(ctx.tags), ctx.shown];

  final overlay = _trailLayers(
    ctx,
    filters,
    combinedFilter,
  ).map((layer) => {'minzoom': overlayMinZoom, ...layer}).toList();

  final insertionIndex = layers.indexWhere((l) => l['id'] == _qaInsertionPoint);
  if (insertionIndex < 0) {
    throw StateError(
      'Base style is missing its "$_qaInsertionPoint" marker layer',
    );
  }
  layers.insertAll(insertionIndex, overlay);

  return baseStyle;
}

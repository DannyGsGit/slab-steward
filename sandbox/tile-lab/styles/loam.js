// "Loam" — the summer bike-park map.
//
// Modelled on the painted resort poster: a mountain that is overwhelmingly dark
// forest green, thinning to rock and then snow above treeline, with trails
// reading as thin bright ribbons laid over the dark. The earlier cut of this
// style was a dry tan topo — pleasant, but it looked like a desert, and thin
// coloured lines had nothing to contrast against.
//
// Two decisions carry the look:
//
//   * The green is *data*, not elevation. It would be easier to put forest into
//     the elevation ramp, but that paints Moab green too. The ramp only handles
//     the part that really is a function of height — treeline giving way to
//     scree and then snow — and the forest itself comes from `landcover=wood`,
//     so a place with no trees renders with no trees.
//   * The trail overlay is unchanged. On dark ground the app's existing cream
//     casing suddenly does what the poster's dark keyline does for its yellow
//     runs: it separates the line from the hillside. Nothing about the
//     difficulty palette had to move.

import {
  buildSources, GLYPHS, FONT, FONT_BOLD, FONT_ITALIC,
  byZoom, byZoomExp, imbaColorOnDark, IS_TRAIL, IS_LIFT, PEAK_LABEL, IS_NAMED_PEAK,
} from './common.js';

export const meta = {
  id: 'loam',
  name: 'Loam',
  blurb: 'Painted bike-park poster. Deep conifer, rock and snow above treeline, trails as bright ribbons.',
  mapTone: 'dark',
  bg: '#5E7348',
};

export function build(ctx = {}) {
  return {
    version: 8,
    name: 'Loam',
    glyphs: GLYPHS,
    sources: buildSources(ctx),
    // A real summer sky rather than the old warm haze — the poster is painted
    // under a blue one, and it is most of what sells the pitched view.
    sky: {
      'sky-color': '#5C9BD1',
      'horizon-color': '#C7DCEA',
      'fog-color': '#D8E2D0',
      'fog-ground-blend': 0.5,
      'horizon-fog-blend': 0.45,
      'sky-horizon-blend': 0.7,
      'atmosphere-blend': byZoom(4, 0.6, 12, 0.2),
    },
    layers: [
      { id: 'bg', type: 'background', paint: { 'background-color': meta.bg } },

      // --- Elevation: treeline, scree, snow ---------------------------------
      // Deliberately *not* carrying the forest. This ramp is the open ground:
      // muted khaki at valley-floor heights, alpine-meadow green through the
      // elevations a resort actually cuts its runs in, bare rock where the
      // trees stop, snow on top. Where there is forest, the landcover fill
      // below covers this entirely.
      //
      // The khaki low end is not decoration. A ramp that starts at meadow green
      // paints every flat town in the country highlighter-green — Bentonville
      // at 400 m came out uniformly fluorescent. Towns and farmland live below
      // ~500 m far more often than alpine meadow does, so the green starts
      // above them.
      {
        id: 'relief',
        type: 'color-relief',
        source: 'dem',
        paint: {
          'color-relief-opacity': 0.95,
          'color-relief-color': [
            'interpolate', ['linear'], ['elevation'],
            -100, '#BCC096',
            300, '#B0B983',
            700, '#9FB462',
            1200, '#A7B56D',
            1550, '#ACA87C',
            1800, '#B3AB94',
            2100, '#C2B8A4',
            2500, '#D8D2C5',
            2900, '#F0EEE9',
            4200, '#FFFFFF',
          ],
        },
      },

      // --- Shading, pass one ------------------------------------------------
      // Under the landcover, for the reason Piste learned the hard way: a white
      // highlight drawn over dark conifer turns it to fog.
      {
        id: 'hillshade',
        type: 'hillshade',
        source: 'dem',
        paint: {
          'hillshade-method': 'igor',
          'hillshade-exaggeration': 0.6,
          'hillshade-illumination-direction': 320,
          'hillshade-shadow-color': '#243A20',
          'hillshade-highlight-color': '#FFFBEC',
          'hillshade-accent-color': 'rgba(36,58,32,0.25)',
        },
      },

      {
        id: 'water',
        type: 'fill',
        source: 'omt',
        'source-layer': 'water',
        filter: ['!=', ['get', 'brunnel'], 'tunnel'],
        paint: { 'fill-color': '#3F7E8A', 'fill-opacity': 0.92 },
      },
      {
        id: 'waterway',
        type: 'line',
        source: 'omt',
        'source-layer': 'waterway',
        paint: {
          'line-color': '#4A8A93',
          'line-width': byZoom(9, 0.5, 14, 1.8),
          'line-opacity': 0.85,
        },
      },

      // --- Ground cover ------------------------------------------------------
      // Meadow and scrub first, then conifer over it. The clearings a resort
      // cuts for its runs show up here as gaps in the wood polygons, which is
      // the same free ribbon effect Piste leans on — softer in summer, because
      // the gap is grass rather than snow.
      {
        id: 'meadow',
        type: 'fill',
        source: 'omt',
        'source-layer': 'landcover',
        filter: ['match', ['get', 'class'], ['grass', 'farmland'], true, false],
        paint: {
          'fill-color': '#88A855',
          'fill-opacity': byZoom(8, 0.30, 13, 0.45),
        },
      },
      {
        id: 'forest',
        type: 'fill',
        source: 'omt',
        'source-layer': 'landcover',
        filter: ['==', ['get', 'class'], 'wood'],
        paint: {
          'fill-color': '#2E4A2B',
          'fill-opacity': byZoom(8, 0.50, 12, 0.66, 15, 0.74),
        },
      },
      {
        id: 'forest-edge',
        type: 'line',
        source: 'omt',
        'source-layer': 'landcover',
        filter: ['==', ['get', 'class'], 'wood'],
        paint: {
          'line-color': '#243C21',
          'line-width': byZoom(10, 2, 15, 8),
          'line-blur': byZoom(10, 2.5, 15, 10),
          'line-opacity': 0.35,
        },
      },
      {
        id: 'glacier',
        type: 'fill',
        source: 'omt',
        'source-layer': 'landcover',
        filter: ['==', ['get', 'class'], 'ice'],
        paint: { 'fill-color': '#FFFFFF', 'fill-opacity': 0.9 },
      },

      // --- Shading, pass two --------------------------------------------------
      // Shadow only, over the canopy, so the forest has gullies and ridgelines
      // in it instead of being a flat green slab. No white in it, so nothing it
      // touches gets bleached.
      {
        id: 'hillshade-canopy',
        type: 'hillshade',
        source: 'dem',
        paint: {
          'hillshade-method': 'igor',
          'hillshade-exaggeration': 0.4,
          'hillshade-illumination-direction': 320,
          'hillshade-shadow-color': '#0F2310',
          'hillshade-highlight-color': 'rgba(255,255,255,0)',
          'hillshade-accent-color': 'rgba(15,35,16,0.25)',
        },
      },

      // --- Contours ------------------------------------------------------------
      // Kept, but demoted. The poster has no contour lines at all — it says
      // everything about shape with paint. Loam still owes the rider a gradient
      // they can measure, so these stay as quiet texture rather than as the
      // subject, tinted into the terrain instead of drawn on top of it. The
      // panel toggle turns them off entirely for the pure painted look.
      {
        id: 'contour',
        type: 'line',
        source: 'contours',
        'source-layer': 'contours',
        filter: ['==', ['get', 'level'], 0],
        paint: {
          'line-color': '#2A3D22',
          'line-width': 0.5,
          'line-opacity': byZoom(12, 0, 13.5, 0.16),
        },
      },
      {
        id: 'contour-index',
        type: 'line',
        source: 'contours',
        'source-layer': 'contours',
        filter: ['>', ['get', 'level'], 0],
        paint: {
          'line-color': '#243620',
          'line-width': byZoom(11, 0.7, 16, 1.2),
          'line-opacity': byZoom(11, 0, 12.5, 0.26),
        },
      },
      {
        id: 'contour-label',
        type: 'symbol',
        source: 'contours',
        'source-layer': 'contours',
        filter: ['>', ['get', 'level'], 0],
        minzoom: 13,
        layout: {
          'symbol-placement': 'line',
          'text-field': ['concat', ['to-string', ['get', 'ele']], "'"],
          'text-font': FONT_ITALIC,
          'text-size': 9,
          'text-max-angle': 25,
          'symbol-spacing': 380,
          'text-rotation-alignment': 'map',
          'text-padding': 6,
        },
        paint: {
          'text-color': '#E8E7D6',
          'text-halo-color': 'rgba(24,40,20,0.6)',
          'text-halo-width': 1.4,
          'text-opacity': 0.75,
        },
      },

      // --- Roads ---------------------------------------------------------------
      {
        id: 'road-casing',
        type: 'line',
        source: 'omt',
        'source-layer': 'transportation',
        filter: ['match', ['get', 'class'],
          ['motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'minor', 'service'], true, false],
        paint: {
          'line-color': '#3A3325',
          'line-width': byZoomExp(1.4, 10, 2.2, 16, 10),
          'line-opacity': 0.45,
        },
      },
      {
        id: 'road',
        type: 'line',
        source: 'omt',
        'source-layer': 'transportation',
        filter: ['match', ['get', 'class'],
          ['motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'minor', 'service'], true, false],
        paint: {
          'line-color': '#F2E9D2',
          'line-width': byZoomExp(1.4, 10, 1.2, 16, 7),
        },
      },
      // The fire road down the mountain. Red, the way the poster's legend calls
      // it — "Summer Road" is its own category there, and on a bike map the
      // climbing road genuinely is a different kind of thing from a trail.
      {
        id: 'track',
        type: 'line',
        source: 'omt',
        'source-layer': 'transportation',
        filter: ['==', ['get', 'class'], 'track'],
        paint: {
          'line-color': '#B5472F',
          'line-width': byZoom(12, 1.1, 17, 3),
          'line-opacity': 0.9,
        },
      },

      // --- Lifts -----------------------------------------------------------------
      {
        id: 'lift-casing',
        type: 'line',
        source: 'omt',
        'source-layer': 'transportation',
        filter: IS_LIFT,
        paint: {
          'line-color': '#FFF8E3',
          'line-width': byZoom(11, 2.6, 17, 6),
          'line-opacity': 0.7,
        },
      },
      {
        id: 'lift',
        type: 'line',
        source: 'omt',
        'source-layer': 'transportation',
        filter: IS_LIFT,
        paint: {
          'line-color': '#14140F',
          'line-width': byZoom(11, 0.9, 17, 2),
        },
      },
      {
        id: 'lift-towers',
        type: 'symbol',
        source: 'omt',
        'source-layer': 'transportation',
        filter: IS_LIFT,
        minzoom: 12,
        layout: {
          'symbol-placement': 'line',
          'symbol-spacing': 34,
          'icon-image': 'lift-tower-warm',
          'icon-allow-overlap': true,
          'icon-rotation-alignment': 'map',
        },
      },

      // --- Trails ------------------------------------------------------------------
      // Unchanged in colour, and now doing far more work: against dark conifer
      // the cream casing reads as the poster's keyline and the difficulty colour
      // sits inside it like a painted ribbon. Slightly thinner than before —
      // the poster's lines are fine, and they can afford to be once the ground
      // behind them is dark.
      {
        id: 'trail-casing',
        type: 'line',
        source: 'trails',
        'source-layer': 'trail',
        filter: IS_TRAIL,
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': '#FFF8E3',
          'line-width': byZoomExp(1.45, 11, 1.9, 14, 3.8, 18, 10),
          'line-opacity': 0.95,
        },
      },
      {
        id: 'trail',
        type: 'line',
        source: 'trails',
        'source-layer': 'trail',
        filter: IS_TRAIL,
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': imbaColorOnDark,
          'line-width': byZoomExp(1.45, 11, 1, 14, 2.3, 18, 6.5),
        },
      },
      {
        id: 'trail-glyph',
        type: 'symbol',
        source: 'trails',
        'source-layer': 'trail',
        filter: ['all', IS_TRAIL, ['has', 'mtb:scale:imba']],
        minzoom: 13,
        layout: {
          'symbol-placement': 'line',
          'symbol-spacing': 170,
          'icon-image': [
            'match', ['get', 'mtb:scale:imba'],
            ['0', '1'], 'imba-easy',
            ['2'], 'imba-medium',
            ['3'], 'imba-hard',
            ['4'], 'imba-veryhard',
            'imba-easy',
          ],
          'icon-size': byZoom(13, 0.7, 17, 1),
          'icon-allow-overlap': false,
          'icon-rotation-alignment': 'viewport',
        },
      },

      // --- Labels ---------------------------------------------------------------------
      {
        id: 'trail-label',
        type: 'symbol',
        source: 'trails',
        'source-layer': 'trail',
        filter: ['all', IS_TRAIL, ['has', 'name']],
        minzoom: 13.5,
        layout: {
          'symbol-placement': 'line',
          'text-field': ['get', 'name'],
          'text-font': FONT_BOLD,
          'text-size': byZoom(13.5, 10, 17, 13),
          'text-max-angle': 35,
          'text-letter-spacing': 0.02,
        },
        paint: {
          'text-color': '#1E2B18',
          'text-halo-color': '#FFF8E3',
          'text-halo-width': 1.9,
        },
      },
      {
        id: 'lift-label',
        type: 'symbol',
        source: 'omt',
        'source-layer': 'transportation_name',
        filter: ['==', ['get', 'class'], 'aerialway'],
        minzoom: 13,
        layout: {
          'symbol-placement': 'line',
          'text-field': ['get', 'name'],
          'text-font': FONT_BOLD,
          'text-size': 11,
          'text-letter-spacing': 0.08,
          'text-offset': [0, 1.1],
        },
        paint: {
          'text-color': '#14140F',
          'text-halo-color': '#FFF8E3',
          'text-halo-width': 2,
        },
      },

      // Summit marker and summit plate are two layers because a symbol layer
      // gets one icon, and this wants both the triangle and the callout.
      {
        id: 'peak-marker',
        type: 'symbol',
        source: 'omt',
        'source-layer': 'mountain_peak',
        filter: IS_NAMED_PEAK,
        minzoom: 10,
        layout: {
          'icon-image': 'peak-snow',
          'icon-size': 0.9,
          'icon-allow-overlap': true,
        },
      },
      {
        id: 'peak',
        type: 'symbol',
        source: 'omt',
        'source-layer': 'mountain_peak',
        filter: IS_NAMED_PEAK,
        minzoom: 10,
        layout: {
          'icon-image': 'label-plate',
          'icon-text-fit': 'both',
          'icon-text-fit-padding': [3, 6, 3, 6],
          'text-field': PEAK_LABEL,
          'text-font': FONT_BOLD,
          'text-size': 10.5,
          'text-offset': [0, 1.4],
          'text-anchor': 'top',
          'text-line-height': 1.15,
        },
        paint: { 'text-color': '#26331C' },
      },
      // The poster's white callout boxes. Villages, base areas, the places a
      // rider navigates by.
      {
        id: 'place',
        type: 'symbol',
        source: 'omt',
        'source-layer': 'place',
        filter: ['match', ['get', 'class'], ['city', 'town', 'village', 'hamlet'], true, false],
        layout: {
          'icon-image': 'label-plate',
          'icon-text-fit': 'both',
          'icon-text-fit-padding': [3, 7, 3, 7],
          'text-field': ['get', 'name'],
          'text-font': FONT_BOLD,
          'text-size': byZoom(8, 10, 14, 12.5),
          'text-letter-spacing': 0.12,
          'text-transform': 'uppercase',
        },
        paint: { 'text-color': '#26331C' },
      },
    ],
  };
}

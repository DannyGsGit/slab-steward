// "Ridgeline" — engraved ink on paper.
//
// The argument this style is making: the terrain does not need colour at all.
// Strip the landcover fills, put the relief in grey, crank the contours up to
// engraving weight, and let the *only* colour on the map be the difficulty of
// the trail. On a map whose whole job is "which line should I ride", that is
// arguably the most honest hierarchy of the three — nothing competes with the
// thing the rider came to read.
//
// It is also the cheapest to render and the easiest to keep legible on a phone.

import {
  buildSources, GLYPHS, FONT, FONT_BOLD,
  byZoom, byZoomExp, imbaColor, IS_TRAIL, IS_LIFT, PEAK_LABEL, IS_NAMED_PEAK,
} from './common.js';

export const meta = {
  id: 'ridgeline',
  name: 'Ridgeline',
  blurb: 'Engraved ink on paper. Grey relief, heavy contours, difficulty as the only colour on the map.',
  mapTone: 'light',
  bg: '#F4F1E9',
};

export function build(ctx = {}) {
  return {
    version: 8,
    name: 'Ridgeline',
    glyphs: GLYPHS,
    sources: buildSources(ctx),
    sky: {
      'sky-color': '#D6D2C6',
      'horizon-color': '#F4F1E9',
      'fog-color': '#F4F1E9',
      'fog-ground-blend': 0.6,
      'sky-horizon-blend': 0.9,
      'atmosphere-blend': byZoom(4, 0.4, 12, 0.1),
    },
    layers: [
      { id: 'bg', type: 'background', paint: { 'background-color': meta.bg } },

      // Paper tone only — a hint that high ground is lighter, nothing more.
      {
        id: 'relief',
        type: 'color-relief',
        source: 'dem',
        paint: {
          'color-relief-opacity': 0.5,
          'color-relief-color': [
            'interpolate', ['linear'], ['elevation'],
            -100, '#E2DED2',
            800, '#EDE9DE',
            1800, '#F5F2E9',
            3000, '#FBF9F3',
            4200, '#FFFFFF',
          ],
        },
      },
      {
        id: 'water',
        type: 'fill',
        source: 'omt',
        'source-layer': 'water',
        filter: ['!=', ['get', 'brunnel'], 'tunnel'],
        paint: { 'fill-color': '#D7DCD9', 'fill-opacity': 0.9 },
      },

      // `multidirectional` rather than `igor`: with no colour doing any work,
      // the shading has to carry every ridge and gully, and lighting it from
      // several angles is what keeps north-facing slopes from going flat.
      {
        id: 'hillshade',
        type: 'hillshade',
        source: 'dem',
        paint: {
          'hillshade-method': 'multidirectional',
          'hillshade-exaggeration': 0.32,
          'hillshade-illumination-direction': 335,
          'hillshade-shadow-color': '#77746A',
          'hillshade-highlight-color': '#FFFFFF',
          'hillshade-accent-color': 'rgba(80,78,70,0.20)',
        },
      },

      // Engraving weight. Minor lines are visible two zooms earlier than in the
      // other styles, and the index lines are nearly as heavy as the trails.
      {
        id: 'contour',
        type: 'line',
        source: 'contours',
        'source-layer': 'contours',
        filter: ['==', ['get', 'level'], 0],
        paint: {
          'line-color': '#6E6B60',
          'line-width': 0.5,
          'line-opacity': byZoom(10.5, 0, 12, 0.38),
        },
      },
      {
        id: 'contour-index',
        type: 'line',
        source: 'contours',
        'source-layer': 'contours',
        filter: ['>', ['get', 'level'], 0],
        paint: {
          'line-color': '#4F4C43',
          'line-width': byZoom(10, 0.8, 16, 1.6),
          'line-opacity': byZoom(9.5, 0, 11, 0.65),
        },
      },
      {
        id: 'contour-label',
        type: 'symbol',
        source: 'contours',
        'source-layer': 'contours',
        filter: ['>', ['get', 'level'], 0],
        minzoom: 12,
        layout: {
          'symbol-placement': 'line',
          'text-field': ['concat', ['to-string', ['get', 'ele']], "'"],
          'text-font': FONT,
          'text-size': 9.5,
          'text-max-angle': 25,
          'symbol-spacing': 300,
          'text-rotation-alignment': 'map',
          'text-padding': 6,
        },
        paint: {
          'text-color': '#4F4C43',
          'text-halo-color': '#F4F1E9',
          'text-halo-width': 1.8,
        },
      },

      {
        id: 'road',
        type: 'line',
        source: 'omt',
        'source-layer': 'transportation',
        filter: ['match', ['get', 'class'],
          ['motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'minor', 'track'], true, false],
        paint: {
          'line-color': '#8A8779',
          'line-width': byZoomExp(1.4, 10, 0.6, 16, 3),
          'line-opacity': 0.55,
        },
      },
      {
        id: 'lift',
        type: 'line',
        source: 'omt',
        'source-layer': 'transportation',
        filter: IS_LIFT,
        paint: {
          'line-color': '#2A281F',
          'line-width': byZoom(11, 0.9, 17, 1.8),
          'line-dasharray': [6, 2],
        },
      },

      // The only colour on the map.
      {
        id: 'trail-casing',
        type: 'line',
        source: 'trails',
        'source-layer': 'trail',
        filter: IS_TRAIL,
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': '#F4F1E9',
          'line-width': byZoomExp(1.45, 11, 2.6, 14, 5.5, 18, 15),
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
          'line-color': imbaColor,
          'line-width': byZoomExp(1.45, 11, 1.2, 14, 2.8, 18, 7.5),
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
          'icon-rotation-alignment': 'viewport',
        },
      },
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
        },
        paint: {
          'text-color': '#2A281F',
          'text-halo-color': '#F4F1E9',
          'text-halo-width': 2,
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
          'icon-image': 'peak-ink',
          'icon-size': 0.9,
          'text-field': PEAK_LABEL,
          'text-font': FONT_BOLD,
          'text-size': 11,
          'text-offset': [0, 0.9],
          'text-anchor': 'top',
          'text-optional': true,
        },
        paint: {
          'text-color': '#2A281F',
          'text-halo-color': '#F4F1E9',
          'text-halo-width': 2,
        },
      },
      {
        id: 'place',
        type: 'symbol',
        source: 'omt',
        'source-layer': 'place',
        filter: ['match', ['get', 'class'], ['city', 'town', 'village', 'hamlet'], true, false],
        layout: {
          'text-field': ['get', 'name'],
          'text-font': FONT,
          'text-size': byZoom(8, 11, 14, 15),
          'text-letter-spacing': 0.14,
          'text-transform': 'uppercase',
        },
        paint: {
          'text-color': '#6E6B60',
          'text-halo-color': '#F4F1E9',
          'text-halo-width': 2,
        },
      },
    ],
  };
}

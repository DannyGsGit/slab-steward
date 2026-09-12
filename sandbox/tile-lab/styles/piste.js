// "Piste" — the painted winter resort map.
//
// The look it is chasing is the airbrushed trail-map poster: snow-white
// terrain that is *sculpted* rather than coloured, near-black conifer forest,
// and runs reading as pale ribbons cut through that forest. Almost none of
// that comes from the vector tiles — it comes from the DEM. The hillshade is
// doing the painting; landcover is only telling it where the trees are.

import {
  buildSources, GLYPHS, FONT, FONT_BOLD, ATTRIBUTION,
  byZoom, byZoomExp, imbaColor, IS_TRAIL, IS_LIFT, isPiste, PEAK_LABEL, IS_NAMED_PEAK,
} from './common.js';

export const meta = {
  id: 'piste',
  name: 'Piste',
  blurb: 'Painted winter resort map. Snow-white relief, black-green conifer, runs as cut ribbons.',
  // The map is near-white, so the lab's own chrome has to sit dark on it.
  mapTone: 'light',
  bg: '#EEF3F8',
};

export function build(ctx = {}) {
  return {
    version: 8,
    name: 'Piste',
    glyphs: GLYPHS,
    sources: buildSources(ctx),
    // A little sky at the horizon once the map is pitched — without it a 3D
    // ski map ends in a hard cut where the terrain stops.
    sky: {
      'sky-color': '#B9D3EA',
      'horizon-color': '#EAF2F8',
      'fog-color': '#F4F8FB',
      'fog-ground-blend': 0.6,
      'horizon-fog-blend': 0.5,
      'sky-horizon-blend': 0.7,
      'atmosphere-blend': byZoom(4, 0.6, 12, 0.2),
    },
    layers: [
      { id: 'bg', type: 'background', paint: { 'background-color': meta.bg } },

      // --- Elevation tint ------------------------------------------------
      // Valleys read slightly grey and warm, ridgelines go pure white. It is
      // subtle on purpose: on a real ski poster the altitude cue is mostly
      // "the top is brighter than the bottom".
      {
        id: 'relief',
        type: 'color-relief',
        source: 'dem',
        paint: {
          'color-relief-opacity': 0.9,
          'color-relief-color': [
            'interpolate', ['linear'], ['elevation'],
            -100, '#DCE6EE',
            300, '#E8F0F6',
            800, '#F2F7FB',
            1400, '#F9FCFD',
            2000, '#FFFFFF',
            4200, '#FFFFFF',
          ],
        },
      },

      // --- The shading ------------------------------------------------------
      // *Under* the landcover, not over it. Drawn on top, the white highlight
      // bleaches the conifer to fog and the whole mountain goes monochrome —
      // which is exactly what the first cut of this style did. Underneath, the
      // snow in the gaps takes the shading at full strength while the forest
      // keeps its colour and lets the terrain read through its last 20% of
      // transparency instead.
      //
      // `igor` is the soft, low-contrast method — the closest of the five to an
      // airbrush, and the least likely to turn a noisy DEM into gravel.
      {
        id: 'hillshade',
        type: 'hillshade',
        source: 'dem',
        paint: {
          'hillshade-method': 'igor',
          'hillshade-exaggeration': 0.55,
          'hillshade-illumination-direction': 335,
          'hillshade-shadow-color': '#5D7A9B',
          'hillshade-highlight-color': '#FFFFFF',
          'hillshade-accent-color': 'rgba(78,106,138,0.30)',
        },
      },

      // --- Water ----------------------------------------------------------
      {
        id: 'water',
        type: 'fill',
        source: 'omt',
        'source-layer': 'water',
        filter: ['!=', ['get', 'brunnel'], 'tunnel'],
        paint: { 'fill-color': '#C2D8EA', 'fill-opacity': 0.9 },
      },
      {
        id: 'waterway',
        type: 'line',
        source: 'omt',
        'source-layer': 'waterway',
        paint: {
          'line-color': '#BBD3E8',
          'line-width': byZoom(9, 0.4, 14, 1.4),
        },
      },

      // --- Forest ----------------------------------------------------------
      // The load-bearing layer of the entire style, and the reason this look is
      // reachable without rendering anything: OSM's `wood` polygons already
      // have the ski runs cut out of them. Make the forest dark enough and
      // every run becomes a white ribbon on its own — negative space, exactly
      // the way the painted posters do it. No piste geometry required.
      //
      // Two layers doing one job: a near-black conifer fill, then a blurred
      // line on the same outline. The blur is what stops the treeline looking
      // like a polygon — it airbrushes the edge.
      {
        id: 'forest',
        type: 'fill',
        source: 'omt',
        'source-layer': 'landcover',
        filter: ['==', ['get', 'class'], 'wood'],
        paint: {
          'fill-color': '#13302A',
          'fill-opacity': byZoom(8, 0.55, 12, 0.78, 15, 0.86),
        },
      },
      {
        id: 'forest-edge',
        type: 'line',
        source: 'omt',
        'source-layer': 'landcover',
        filter: ['==', ['get', 'class'], 'wood'],
        paint: {
          'line-color': '#16302A',
          'line-width': byZoom(10, 2, 15, 9),
          'line-blur': byZoom(10, 2.5, 15, 11),
          'line-opacity': 0.38,
        },
      },
      {
        id: 'glacier',
        type: 'fill',
        source: 'omt',
        'source-layer': 'landcover',
        filter: ['==', ['get', 'class'], 'ice'],
        paint: { 'fill-color': '#FFFFFF', 'fill-opacity': 0.85 },
      },

      // A second pass over the canopy, shadow only — highlight is fully
      // transparent. The first hillshade sits under the forest and so never
      // reaches it, which leaves the trees a flat dark slab with no mountain
      // in them. This one puts the gullies and ridgelines back without
      // re-introducing the bleaching, because there is no white in it to
      // bleach with.
      {
        id: 'hillshade-canopy',
        type: 'hillshade',
        source: 'dem',
        paint: {
          'hillshade-method': 'igor',
          'hillshade-exaggeration': 0.35,
          'hillshade-illumination-direction': 335,
          'hillshade-shadow-color': '#07211C',
          'hillshade-highlight-color': 'rgba(255,255,255,0)',
          'hillshade-accent-color': 'rgba(7,33,28,0.25)',
        },
      },

      // --- Contours ---------------------------------------------------------
      // Whisper-quiet here. A winter poster shows shape through paint, not
      // through lines; these are for orientation at high zoom only.
      {
        id: 'contour',
        type: 'line',
        source: 'contours',
        'source-layer': 'contours',
        filter: ['==', ['get', 'level'], 0],
        paint: {
          'line-color': '#7C97B4',
          'line-width': 0.5,
          'line-opacity': byZoom(12, 0, 13.5, 0.25),
        },
      },
      {
        id: 'contour-index',
        type: 'line',
        source: 'contours',
        'source-layer': 'contours',
        filter: ['>', ['get', 'level'], 0],
        paint: {
          'line-color': '#6E8CAC',
          'line-width': 1,
          'line-opacity': byZoom(11, 0, 12.5, 0.35),
        },
      },

      // --- Roads, kept faint -------------------------------------------------
      // A resort map shows the access road and nothing else. Anything more and
      // the town starts competing with the mountain.
      {
        id: 'road',
        type: 'line',
        source: 'omt',
        'source-layer': 'transportation',
        filter: ['match', ['get', 'class'],
          ['motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'minor'], true, false],
        paint: {
          'line-color': '#FFFFFF',
          'line-width': byZoomExp(1.4, 10, 1.2, 16, 8),
          'line-opacity': 0.85,
        },
      },
      {
        id: 'road-edge',
        type: 'line',
        source: 'omt',
        'source-layer': 'transportation',
        filter: ['match', ['get', 'class'],
          ['motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'minor'], true, false],
        paint: {
          'line-color': '#A9BCCE',
          'line-width': byZoomExp(1.4, 10, 1.8, 16, 10),
          'line-opacity': 0.35,
          'line-gap-width': 0,
        },
      },

      // --- Summer trails, backgrounded ----------------------------------------
      // Still drawn, still in the app's difficulty colours, but sitting back so
      // the winter layer reads first.
      {
        id: 'trail',
        type: 'line',
        source: 'trails',
        'source-layer': 'trail',
        filter: IS_TRAIL,
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': imbaColor,
          'line-width': byZoomExp(1.4, 12, 0.8, 17, 3),
          'line-opacity': 0.32,
          'line-dasharray': [3, 2],
        },
      },

      // --- Ski runs ------------------------------------------------------------
      // The signature move of the whole style. A run is not a coloured line, it
      // is an *absence of forest* — so it is drawn as a soft white ribbon with a
      // faint edge, which is what a cut through conifer actually looks like from
      // above.
      {
        id: 'piste-ribbon',
        type: 'line',
        source: 'trails',
        'source-layer': 'trail',
        filter: isPiste('downhill'),
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': '#FFFFFF',
          'line-width': byZoomExp(1.5, 11, 2.5, 14, 7, 17, 24),
          'line-blur': byZoom(11, 1, 17, 5),
          'line-opacity': 0.9,
        },
      },
      {
        id: 'piste-edge',
        type: 'line',
        source: 'trails',
        'source-layer': 'trail',
        filter: isPiste('downhill'),
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': '#8FA8C0',
          'line-width': byZoomExp(1.5, 11, 3, 14, 8.5, 17, 28),
          'line-opacity': 0.3,
          'line-blur': byZoom(11, 2, 17, 7),
        },
      },
      // Nordic and touring read as routes over the snow rather than cuts in it,
      // so they stay lines.
      {
        id: 'piste-nordic',
        type: 'line',
        source: 'trails',
        'source-layer': 'trail',
        filter: ['match', ['get', 'piste:type'], ['nordic', 'skitour', 'snowshoe'], true, false],
        layout: { 'line-cap': 'round' },
        paint: {
          'line-color': '#2C5C8A',
          'line-width': byZoom(11, 1, 17, 3),
          'line-dasharray': [1, 2.5],
          'line-opacity': 0.8,
        },
      },

      // --- Lifts ----------------------------------------------------------------
      // White casing so the line survives crossing dark forest, black cable over
      // it, tower dots along it. Drawn above the runs, as on every resort map.
      {
        id: 'lift-casing',
        type: 'line',
        source: 'omt',
        'source-layer': 'transportation',
        filter: IS_LIFT,
        paint: {
          'line-color': '#FFFFFF',
          'line-width': byZoom(11, 3, 17, 7),
          'line-opacity': 0.9,
        },
      },
      {
        id: 'lift',
        type: 'line',
        source: 'omt',
        'source-layer': 'transportation',
        filter: IS_LIFT,
        paint: {
          'line-color': '#14181C',
          'line-width': byZoom(11, 1, 17, 2.2),
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
          'icon-image': 'lift-tower',
          'icon-allow-overlap': true,
          'icon-rotation-alignment': 'map',
        },
      },

      // --- Labels -----------------------------------------------------------------
      {
        id: 'piste-label',
        type: 'symbol',
        source: 'trails',
        'source-layer': 'trail',
        filter: ['all', isPiste('downhill'), ['has', 'name']],
        minzoom: 13,
        layout: {
          'symbol-placement': 'line',
          'text-field': ['get', 'name'],
          'text-font': FONT_BOLD,
          'text-size': byZoom(13, 10, 17, 14),
          'text-letter-spacing': 0.04,
          'text-max-angle': 35,
        },
        paint: {
          'text-color': '#16324D',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 1.8,
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
          'text-color': '#14181C',
          'text-halo-color': '#FFFFFF',
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
          'icon-image': 'peak',
          'icon-size': 0.9,
          'text-field': PEAK_LABEL,
          'text-font': FONT_BOLD,
          'text-size': 11,
          'text-offset': [0, 0.9],
          'text-anchor': 'top',
          'text-optional': true,
        },
        paint: {
          'text-color': '#1B3550',
          'text-halo-color': '#FFFFFF',
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
          'text-letter-spacing': 0.12,
          'text-transform': 'uppercase',
        },
        paint: {
          'text-color': '#4A6480',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 2,
        },
      },
    ],
  };
}

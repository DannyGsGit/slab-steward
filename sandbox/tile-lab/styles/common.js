// Shared vocabulary for every style in the lab.
//
// Everything here is key-free and public: the point of the lab is to find out
// how far a *style* can carry the ski-resort / bike-park look before anyone
// pays for tiles or stands up a renderer. See ../README.md for what each
// source is and what it can't do.

// --- Sources ---------------------------------------------------------------

/// OpenFreeMap's planet build, OpenMapTiles schema. Carries landcover, water,
/// mountain_peak and — the reason it beats the alternatives for this look —
/// `transportation` class `aerialway`, i.e. chairlifts and gondolas.
export const OMT_TILEJSON = 'https://tiles.openfreemap.org/planet';

/// The same OSM US trails tileset Steward already draws from, so a line that
/// looks right here looks right in the app. `mtb:scale:imba` and `piste:type`
/// both ride along in it.
export const TRAILS_TILEJSON = 'https://tiles.openstreetmap.us/vector/trails.json';

/// AWS's public terrarium DEM. Feeds the hillshade, the elevation tint and the
/// client-side contours — three of the four things that make a painted trail
/// map look painted.
export const DEM_TILES =
  'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png';

export const GLYPHS = 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf';

export const FONT = ['Noto Sans Regular'];
export const FONT_BOLD = ['Noto Sans Bold'];
export const FONT_ITALIC = ['Noto Sans Italic'];

export const ATTRIBUTION = [
  '<a href="https://www.openstreetmap.org/copyright">&copy; OpenStreetMap</a>',
  '<a href="https://openfreemap.org/">OpenFreeMap</a>',
  '<a href="https://tiles.openstreetmap.us/">OSM US</a>',
  '<a href="https://registry.opendata.aws/terrain-tiles/">Terrain Tiles</a>',
].join(' &middot; ');

/// Source block shared by every style. `demUrl` and `contourUrl` come from the
/// one maplibre-contour DemSource the app sets up, so the DEM is fetched once
/// and both the shading and the contour lines read the same tiles.
export function buildSources({ demUrl, contourUrl }) {
  return {
    omt: { type: 'vector', url: OMT_TILEJSON },
    trails: { type: 'vector', url: TRAILS_TILEJSON },
    dem: {
      type: 'raster-dem',
      tiles: [demUrl],
      encoding: 'terrarium',
      tileSize: 256,
      maxzoom: 14,
      attribution: ATTRIBUTION,
    },
    contours: { type: 'vector', tiles: [contourUrl], maxzoom: 15 },
  };
}

// --- Difficulty ------------------------------------------------------------
//
// Lifted from lib/src/map/otm_conventions.dart. The basemap is what the lab is
// changing, so the trail overlay keeps the app's signage colours — that way a
// candidate basemap is judged with the real overlay sitting on top of it, not
// a prettier stand-in. Change them there and here together.

export const EASY = '#2f6b4d';       // IMBA 0-1, green circle
export const MEDIUM = '#3b5fc6';     // IMBA 2, blue square
export const HARD = '#16191c';       // IMBA 3, black diamond
export const VERY_HARD = '#ef4b18';  // IMBA 4, double black
export const UNRATED = '#c100cc';    // OSM doesn't say

/// The same five ratings, re-tuned for a dark basemap.
///
/// Not a second opinion about difficulty — the same semantics at a luminance
/// that survives being drawn on near-black conifer. The app's palette was
/// picked against OpenTrailMap's light basemap, and `easy`'s deep green is
/// nearly invisible on a dark green hillside; raising it is the same move a
/// dark theme makes on any other token. Hue and ordering are untouched, and
/// `hard` stays black on purpose — a dark core inside a bright keyline is
/// exactly how the painted posters draw their expert lines.
///
/// If a dark basemap ever graduates into the app, this is the pair
/// `otm_conventions.dart` would need to grow.
export const EASY_DARK = '#4E9E5F';
export const MEDIUM_DARK = '#4A86DB';
export const HARD_DARK = '#16191c';
export const VERY_HARD_DARK = '#F4602A';
export const UNRATED_DARK = '#D45BE0';

/// A trail line's colour, read off `mtb:scale:imba` exactly as the app reads it.
export const imbaColor = [
  'match', ['get', 'mtb:scale:imba'],
  ['0', '1'], EASY,
  ['2'], MEDIUM,
  ['3'], HARD,
  ['4'], VERY_HARD,
  UNRATED,
];

/// [imbaColor] for styles whose ground is dark. Same expression, dark-tuned stops.
export const imbaColorOnDark = [
  'match', ['get', 'mtb:scale:imba'],
  ['0', '1'], EASY_DARK,
  ['2'], MEDIUM_DARK,
  ['3'], HARD_DARK,
  ['4'], VERY_HARD_DARK,
  UNRATED_DARK,
];

// --- Filters ---------------------------------------------------------------

/// Lines the lab treats as "a trail" — what a rider or a hiker would follow.
///
/// `footway` is admitted only when it is tagged informal, which is the lab's
/// version of the app's informal-trails-first default. Drawn unconditionally it
/// swamps everything: in a resort village the sidewalks outnumber the trails
/// several times over, and the tileset carries no `footway=sidewalk` to sort
/// them out with — `informal` is the nearest thing it has. The first cut of
/// these styles drew every footway and the town disappeared under them.
export const IS_TRAIL = [
  'all',
  ['any',
    ['match', ['get', 'highway'], ['path', 'cycleway', 'bridleway', 'track'], true, false],
    ['all', ['==', ['get', 'highway'], 'footway'], ['==', ['get', 'informal'], 'yes']],
  ],
  ['!', ['has', 'piste:type']],
];

export const isPiste = (kind) => ['==', ['get', 'piste:type'], kind];

/// Chairlifts and gondolas, from the OpenMapTiles transportation layer.
export const IS_LIFT = ['==', ['get', 'class'], 'aerialway'];

// --- Expression helpers ----------------------------------------------------

/// `['interpolate', ['linear'], ['zoom'], z0, v0, z1, v1, ...]` without the noise.
export function byZoom(...stops) {
  return ['interpolate', ['linear'], ['zoom'], ...stops];
}

/// Same, but eased — nicer for widths that grow over many zooms.
export function byZoomExp(base, ...stops) {
  return ['interpolate', ['exponential', base], ['zoom'], ...stops];
}

/// Metres to feet, for elevation labels. US trail maps are in feet.
export const feet = (m) => ['round', ['*', m, 3.28084]];

/// Summit label: the name, and the elevation in feet only when the tile
/// actually carries one. Without the guard every unnamed, un-surveyed bump in
/// `mountain_peak` prints a confident "0'".
export const PEAK_LABEL = [
  'concat',
  ['get', 'name'],
  ['case',
    ['has', 'ele'], ['concat', '\n', feet(['to-number', ['get', 'ele'], 0]), "'"],
    ''],
];

/// Only summits worth interrupting the map for.
///
/// `class` does the real work here, not `rank`. The `mountain_peak` layer also
/// carries saddles, passes, cliffs and ridges, and a pitched view down a range
/// pulls in dozens of them — a skyline crowded with "Drop Pass" and "Waterfall
/// Cliffs" rather than summits. Ranking can't fix that, because nearly every
/// feature in it comes through as rank 1; restricting the class can.
export const IS_NAMED_PEAK = [
  'all',
  ['has', 'name'],
  ['==', ['get', 'class'], 'peak'],
  ['<=', ['coalesce', ['to-number', ['get', 'rank'], 1], 1], 3],
];

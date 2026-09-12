// Tile Lab — a bench for trying basemap styles under Steward's trail overlay.
//
// One map, three styles, and the knobs that actually change how a trail map
// feels: terrain, shading strength, contours, and paper grain. Everything is
// live — nothing here needs a rebuild to see a change.

import { installIcons } from './icons.js';
import { DEM_TILES, ATTRIBUTION } from './styles/common.js';
import * as piste from './styles/piste.js';
import * as loam from './styles/loam.js';
import * as ridgeline from './styles/ridgeline.js';

const STYLES = [piste, loam, ridgeline];

const PLACES = [
  { name: 'Whistler, BC',      center: [-122.9487, 50.1100], zoom: 13.2, pitch: 55, bearing: -20 },
  // Framed the way the bike-park poster is: village at the bottom of the
  // screen, Whistler Peak at the top, looking south up the mountain.
  { name: 'Whistler Bike Park', center: [-122.9530, 50.0880], zoom: 12.9, pitch: 68, bearing: 180 },
  { name: 'Northstar, Tahoe',  center: [-120.1210, 39.2746], zoom: 13.4, pitch: 55, bearing: 15 },
  { name: 'Winter Park, CO',   center: [-105.7625, 39.8868], zoom: 13.2, pitch: 58, bearing: -35 },
  { name: 'Snowshoe, WV',      center: [-79.9939, 38.4121],  zoom: 13.6, pitch: 50, bearing: 0 },
  { name: 'Moab, UT',          center: [-109.5498, 38.5733], zoom: 12.8, pitch: 55, bearing: 40 },
  { name: 'Bentonville, AR',   center: [-94.2088, 36.3729],  zoom: 13.5, pitch: 0,  bearing: 0 },
];

// --- DEM ------------------------------------------------------------------
//
// One DemSource feeds three things: the hillshade, the elevation tint and the
// contour lines. Going through maplibre-contour rather than pointing the
// raster-dem source straight at AWS is what makes that sharing possible — the
// terrarium PNG is fetched and decoded once per tile instead of three times.
//
// `multiplier: 3.28084` makes the contour features carry feet, so the label
// layers can print `['get','ele']` with no arithmetic and the intervals below
// are the round numbers a US trail map actually uses.
const demSource = new mlcontour.DemSource({
  url: DEM_TILES,
  encoding: 'terrarium',
  maxzoom: 14,
  worker: true,
});
demSource.setupMaplibre(maplibregl);

const contourUrl = demSource.contourProtocolUrl({
  multiplier: 3.28084,
  overzoom: 1,
  thresholds: {
    10: [1000, 5000],
    11: [500, 2500],
    12: [200, 1000],
    13: [100, 500],
    14: [50, 250],
    15: [40, 200],
  },
  elevationKey: 'ele',
  levelKey: 'level',
  contourLayer: 'contours',
});

const ctx = { demUrl: demSource.sharedDemProtocolUrl, contourUrl };

// --- State ----------------------------------------------------------------

const state = {
  style: 'piste',
  terrain: true,
  terrainExaggeration: 1.3,
  hillshade: null,   // null = whatever the style asked for
  contours: true,
  grain: 0.18,
  overlay: 1,
};

// --- Map ------------------------------------------------------------------

const start = PLACES[0];
const map = new maplibregl.Map({
  container: 'map',
  style: styleFor(state.style),
  center: start.center,
  zoom: start.zoom,
  pitch: start.pitch,
  bearing: start.bearing,
  maxPitch: 85,
  hash: true,
  attributionControl: false,
});

map.addControl(new maplibregl.NavigationControl({ visualizePitch: true }), 'bottom-right');
map.addControl(new maplibregl.AttributionControl({ compact: true, customAttribution: ATTRIBUTION }), 'bottom-right');
map.addControl(new maplibregl.ScaleControl({ unit: 'imperial' }), 'bottom-left');

function styleFor(id) {
  return STYLES.find((s) => s.meta.id === id).build(ctx);
}

// setStyle drops runtime-added images and the terrain, so both are re-applied
// every time a style loads rather than once at startup.
map.on('style.load', () => {
  installIcons(map);
  captureOverlayBase();
  applyTerrain();
  applyHillshade();
  applyContours();
  applyOverlay();
  document.body.style.setProperty('--map-bg', metaFor(state.style).bg);
});

function metaFor(id) {
  return STYLES.find((s) => s.meta.id === id).meta;
}

// --- Knobs ----------------------------------------------------------------

function applyTerrain() {
  if (state.terrain) {
    map.setTerrain({ source: 'dem', exaggeration: state.terrainExaggeration });
  } else {
    map.setTerrain(null);
  }
}

// Some styles shade in two passes — one under the landcover, one over it. The
// slider drives both, keeping the ratio the style chose.
const CANOPY_RATIO = 0.64;

function applyHillshade() {
  if (state.hillshade === null || !map.getLayer('hillshade')) return;
  map.setPaintProperty('hillshade', 'hillshade-exaggeration', state.hillshade);
  if (map.getLayer('hillshade-canopy')) {
    map.setPaintProperty('hillshade-canopy', 'hillshade-exaggeration',
      state.hillshade * CANOPY_RATIO);
  }
}

// --- Trail overlay --------------------------------------------------------
//
// The lab is here to judge a *basemap*, and at somewhere like Whistler the
// trail overlay is dense enough to bury one — most of those lines are magenta,
// because most trails are un-rated, which is the whole reason Steward exists.
// That is honest data and it stays honest: rather than filtering it away, this
// fades the whole overlay so the tiles underneath can be looked at.
//
// Every layer drawn from the `trails` source is found by source rather than by
// a hand-kept id list, so a new trail layer in any style is picked up for free.

const overlayBase = new Map();

function overlayLayers() {
  // getStyle() is undefined in the gap between setStyle and style.load, and
  // the slider can be moved during it. Note this can't gate on
  // isStyleLoaded() — that is still false inside the style.load handler
  // itself, which is precisely when the overlay needs re-applying.
  let style = null;
  try { style = map.getStyle(); } catch { /* style torn down mid-swap */ }
  return style?.layers?.filter((l) => l.source === 'trails') ?? [];
}

function opacityProps(type) {
  return type === 'symbol' ? ['icon-opacity', 'text-opacity'] : ['line-opacity'];
}

function captureOverlayBase() {
  overlayBase.clear();
  for (const l of overlayLayers()) {
    for (const prop of opacityProps(l.type)) {
      overlayBase.set(`${l.id}|${prop}`, map.getPaintProperty(l.id, prop) ?? 1);
    }
  }
}

function applyOverlay() {
  for (const l of overlayLayers()) {
    for (const prop of opacityProps(l.type)) {
      const base = overlayBase.get(`${l.id}|${prop}`) ?? 1;
      // A style's own opacity may itself be a zoom expression, so scale rather
      // than replace — multiplying an expression is still a valid expression.
      const value = typeof base === 'number'
        ? base * state.overlay
        : ['*', base, state.overlay];
      map.setPaintProperty(l.id, prop, value);
    }
  }
}

function applyContours() {
  const vis = state.contours ? 'visible' : 'none';
  for (const id of ['contour', 'contour-index', 'contour-label']) {
    if (map.getLayer(id)) map.setLayoutProperty(id, 'visibility', vis);
  }
}

function setStyleId(id) {
  state.style = id;
  // A style has its own opinion about shading strength; drop the override so
  // switching styles shows the style, not the last slider position.
  state.hillshade = null;
  // Drop terrain first. Swapping the style out from under a live terrain mesh
  // leaves the renderer holding a draped source that no longer exists, which
  // surfaces as a `shaderPreludeCode` throw on the next frame. style.load puts
  // it straight back.
  map.setTerrain(null);
  map.setStyle(styleFor(id), { diff: false });
  syncUI();
}

// --- Paper grain ----------------------------------------------------------
//
// The one effect here that no style JSON can express: a turbulence field
// multiplied over the whole canvas. It is a small thing that does a lot of
// work — it is most of the difference between "a vector map" and "a printed
// trail map", because print has tooth and a GPU canvas does not.
//
// It lives in CSS rather than in the map, which also means it costs nothing
// per frame. Porting it to Flutter is a BlendMode.multiply overlay on the
// map widget — see ../README.md.
function grainDataUri() {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="220" height="220">
    <filter id="g" x="0" y="0" width="100%" height="100%">
      <feTurbulence type="fractalNoise" baseFrequency="0.75" numOctaves="4" stitchTiles="stitch"/>
      <feColorMatrix type="saturate" values="0"/>
    </filter>
    <rect width="220" height="220" filter="url(#g)"/>
  </svg>`;
  return `url("data:image/svg+xml;utf8,${encodeURIComponent(svg)}")`;
}

const grainEl = document.getElementById('grain');
grainEl.style.backgroundImage = grainDataUri();

function applyGrain() {
  grainEl.style.opacity = String(state.grain);
}

// --- UI -------------------------------------------------------------------

const el = (id) => document.getElementById(id);

function buildStyleButtons() {
  const host = el('styles');
  host.innerHTML = '';
  for (const s of STYLES) {
    const b = document.createElement('button');
    b.className = 'style-btn';
    b.dataset.id = s.meta.id;
    b.innerHTML = `<strong>${s.meta.name}</strong><span>${s.meta.blurb}</span>`;
    b.onclick = () => setStyleId(s.meta.id);
    host.appendChild(b);
  }
}

function buildPlaces() {
  const sel = el('place');
  for (const [i, p] of PLACES.entries()) {
    const o = document.createElement('option');
    o.value = String(i);
    o.textContent = p.name;
    sel.appendChild(o);
  }
  sel.onchange = () => {
    const p = PLACES[Number(sel.value)];
    map.flyTo({ center: p.center, zoom: p.zoom, pitch: p.pitch, bearing: p.bearing, duration: 1800 });
  };
}

function syncUI() {
  for (const b of document.querySelectorAll('.style-btn')) {
    b.classList.toggle('on', b.dataset.id === state.style);
  }
  el('terrain').checked = state.terrain;
  el('contours').checked = state.contours;
  el('exag').value = String(state.terrainExaggeration);
  el('exag-out').textContent = state.terrainExaggeration.toFixed(1) + '×';
  const hs = state.hillshade ?? currentHillshade();
  el('shade').value = String(hs);
  el('shade-out').textContent = hs.toFixed(2);
  el('grain').value = String(state.grain);
  el('grain-out').textContent = Math.round(state.grain * 100) + '%';
  el('overlay').value = String(state.overlay);
  el('overlay-out').textContent = Math.round(state.overlay * 100) + '%';
}

function currentHillshade() {
  try {
    return map.getPaintProperty('hillshade', 'hillshade-exaggeration') ?? 0.5;
  } catch {
    return 0.5;
  }
}

function wire() {
  el('terrain').onchange = (e) => { state.terrain = e.target.checked; applyTerrain(); };
  el('contours').onchange = (e) => { state.contours = e.target.checked; applyContours(); };

  el('exag').oninput = (e) => {
    state.terrainExaggeration = Number(e.target.value);
    el('exag-out').textContent = state.terrainExaggeration.toFixed(1) + '×';
    if (state.terrain) applyTerrain();
  };
  el('shade').oninput = (e) => {
    state.hillshade = Number(e.target.value);
    el('shade-out').textContent = state.hillshade.toFixed(2);
    applyHillshade();
  };
  el('overlay').oninput = (e) => {
    state.overlay = Number(e.target.value);
    el('overlay-out').textContent = Math.round(state.overlay * 100) + '%';
    applyOverlay();
  };
  el('grain').oninput = (e) => {
    state.grain = Number(e.target.value);
    el('grain-out').textContent = Math.round(state.grain * 100) + '%';
    applyGrain();
  };

  // The export the lab exists to produce: the style as MapLibre sees it right
  // now, ready to paste into a Dart style builder.
  el('export').onclick = async () => {
    const json = JSON.stringify(map.getStyle(), null, 2);
    try {
      await navigator.clipboard.writeText(json);
      flash('Style JSON copied');
    } catch {
      console.log(json);
      flash('Style JSON logged to console');
    }
  };

  el('panel-toggle').onclick = () => document.body.classList.toggle('collapsed');
}

let flashTimer;
function flash(msg) {
  const f = el('flash');
  f.textContent = msg;
  f.classList.add('on');
  clearTimeout(flashTimer);
  flashTimer = setTimeout(() => f.classList.remove('on'), 1800);
}

// --- Inspector -------------------------------------------------------------
//
// Click any line to see what the tiles actually carry for it. This is how you
// find out that the tag you wanted to style by isn't in the tileset.
map.on('click', (e) => {
  const feats = map.queryRenderedFeatures(e.point, {
    layers: ['trail', 'trail-casing', 'piste-ribbon', 'piste-nordic', 'lift', 'road']
      .filter((id) => map.getLayer(id)),
  });
  const box = el('inspect');
  if (!feats.length) { box.classList.remove('on'); return; }
  const p = feats[0].properties;
  const rows = Object.entries(p)
    .filter(([k]) => !k.startsWith('name:') && k !== 'OSM_TIMESTAMP')
    .slice(0, 16)
    .map(([k, v]) => `<tr><td>${k}</td><td>${String(v)}</td></tr>`)
    .join('');
  box.innerHTML = `<div class="inspect-head">${feats[0].layer.id}<button id="inspect-x">&times;</button></div><table>${rows}</table>`;
  box.classList.add('on');
  el('inspect-x').onclick = () => box.classList.remove('on');
});

map.on('error', (e) => console.warn('[map]', e && e.error ? e.error.message : e));

buildStyleButtons();
buildPlaces();
wire();
applyGrain();
syncUI();
map.once('idle', syncUI);

// Console handle. Tweak a paint property against the live map, then fold the
// result back into the style file:
//   lab.map.setPaintProperty('forest', 'fill-color', '#123')
window.lab = {
  map, state, setStyleId, PLACES, STYLES,
  setGrain(v) { state.grain = v; applyGrain(); syncUI(); },
  setOverlay(v) { state.overlay = v; applyOverlay(); syncUI(); },
  goto(i) { const p = PLACES[i]; map.jumpTo({ center: p.center, zoom: p.zoom, pitch: p.pitch, bearing: p.bearing }); },
};

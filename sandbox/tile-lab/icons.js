// Runtime-generated sprite images.
//
// Drawn on a canvas and handed to `map.addImage` rather than shipped as a
// sprite sheet: the lab is for changing its mind quickly, and a sprite is a
// build step. It also means every icon is defined in the same file as the
// colours it uses. If a style graduates into the app, these become a real
// sprite — see ../README.md.

const DPR = 2; // Draw at 2x and declare pixelRatio 2, so icons stay crisp.

function canvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w * DPR;
  c.height = h * DPR;
  const ctx = c.getContext('2d');
  ctx.scale(DPR, DPR);
  return { c, ctx };
}

function toImage(c) {
  const ctx = c.getContext('2d');
  return {
    width: c.width,
    height: c.height,
    data: ctx.getImageData(0, 0, c.width, c.height).data,
  };
}

/// A difficulty chip: the shape carries the rating the way trailhead signage
/// does, so a colourblind rider still gets the message.
function difficultyChip(shape, fill) {
  const S = 13;
  const { c, ctx } = canvas(S, S);
  const m = S / 2;
  ctx.fillStyle = '#FFFFFF';
  ctx.strokeStyle = '#FFFFFF';
  ctx.lineWidth = 2.4;
  ctx.lineJoin = 'round';

  const path = () => {
    ctx.beginPath();
    if (shape === 'circle') {
      ctx.arc(m, m, 4.1, 0, Math.PI * 2);
    } else if (shape === 'square') {
      const r = 3.6;
      ctx.rect(m - r, m - r, r * 2, r * 2);
    } else if (shape === 'diamond') {
      const r = 4.6;
      ctx.moveTo(m, m - r); ctx.lineTo(m + r, m); ctx.lineTo(m, m + r); ctx.lineTo(m - r, m);
      ctx.closePath();
    } else if (shape === 'double-diamond') {
      const r = 4.3, o = 2.1;
      for (const dx of [-o, o]) {
        ctx.moveTo(m + dx, m - r); ctx.lineTo(m + dx + r * 0.75, m);
        ctx.lineTo(m + dx, m + r); ctx.lineTo(m + dx - r * 0.75, m);
        ctx.closePath();
      }
    }
  };

  path();
  ctx.stroke();   // white keyline, so the chip survives any background
  ctx.fillStyle = fill;
  path();
  ctx.fill();
  return toImage(c);
}

/// A lift tower. A dot rather than the cross-tick a printed map would use:
/// icon rotation along a line is bearing-dependent, and a dot reads identically
/// whichever way the cable runs.
function liftTower(fill, ring) {
  const S = 7;
  const { c, ctx } = canvas(S, S);
  const m = S / 2;
  ctx.beginPath(); ctx.arc(m, m, 2.4, 0, Math.PI * 2);
  ctx.fillStyle = ring; ctx.fill();
  ctx.beginPath(); ctx.arc(m, m, 1.4, 0, Math.PI * 2);
  ctx.fillStyle = fill; ctx.fill();
  return toImage(c);
}

/// A summit marker — the filled triangle every topo sheet uses.
function peak(fill, halo) {
  const S = 12;
  const { c, ctx } = canvas(S, S);
  const tri = () => {
    ctx.beginPath();
    ctx.moveTo(6, 2.2); ctx.lineTo(10, 9.2); ctx.lineTo(2, 9.2);
    ctx.closePath();
  };
  ctx.lineJoin = 'round';
  ctx.lineWidth = 2.2;
  ctx.strokeStyle = halo;
  tri(); ctx.stroke();
  ctx.fillStyle = fill;
  tri(); ctx.fill();
  return toImage(c);
}

/// The white callout plate the painted resort maps put lodge, station and summit
/// names on. Nine-sliced, so one small image stretches to fit any label.
///
/// Drawn at pixelRatio 1 deliberately: `stretchX`/`stretchY`/`content` are in
/// the image's own pixel coordinates, and keeping the ratio at 1 means those
/// numbers are the same ones drawn here, with no doubling to reason about.
function labelPlate(fill, border) {
  const S = 20;
  const c = document.createElement('canvas');
  c.width = S; c.height = S;
  const ctx = c.getContext('2d');
  ctx.fillStyle = fill;
  ctx.fillRect(0, 0, S, S);
  ctx.strokeStyle = border;
  ctx.lineWidth = 1;
  ctx.strokeRect(0.5, 0.5, S - 1, S - 1);
  return toImage(c);
}

const PLATE_META = {
  pixelRatio: 1,
  stretchX: [[6, 14]],
  stretchY: [[6, 14]],
  content: [3, 3, 17, 17],
};

const DEFS = {
  'imba-easy': () => difficultyChip('circle', '#2f6b4d'),
  'imba-medium': () => difficultyChip('square', '#3b5fc6'),
  'imba-hard': () => difficultyChip('diamond', '#16191c'),
  'imba-veryhard': () => difficultyChip('double-diamond', '#ef4b18'),
  'lift-tower': () => liftTower('#14181C', '#FFFFFF'),
  'lift-tower-warm': () => liftTower('#4A3520', '#FDF6E6'),
  'peak': () => peak('#1B3550', '#FFFFFF'),
  'peak-warm': () => peak('#4A3520', '#FDF6E6'),
  'peak-ink': () => peak('#2A281F', '#F4F1E9'),
  'peak-snow': () => peak('#FFFDF6', '#26331C'),
  'label-plate': () => labelPlate('#FFFDF6', '#3A4A2E'),
};

/// Images whose metadata is more than a pixel ratio.
const META = {
  'label-plate': PLATE_META,
};

/// Adds every icon the styles reference. Safe to call on each style load —
/// `addImage` throws on a duplicate id, so existing images are skipped.
export function installIcons(map) {
  for (const [id, make] of Object.entries(DEFS)) {
    if (map.hasImage(id)) continue;
    map.addImage(id, make(), META[id] ?? { pixelRatio: DPR });
  }
}

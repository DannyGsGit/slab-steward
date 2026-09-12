// Capture the same view in every style, for side-by-side comparison.
//
// Flipping between styles by hand tells you which one you clicked last; two
// PNGs of the same ridge tell you which one is better. Optional — the lab
// itself needs nothing installed.
//
//   cd sandbox/tile-lab && python3 -m http.server 8791 &
//   npx --yes playwright install chromium      # first run only
//   node tools/shoot.mjs                       # all styles, all places
//   node tools/shoot.mjs piste whistler        # one style, one place
//
// Output lands in _shots/ (git-ignored).

import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = resolve(HERE, '../_shots');
const URL = process.env.LAB_URL ?? 'http://localhost:8791/index.html';

// Map settle time. Terrain, contours and the DEM all stream in; screenshotting
// early gives you a picture of a half-loaded map, which is worse than useless
// for judging a style.
const SETTLE = Number(process.env.LAB_SETTLE ?? 11000);

const STYLES = ['piste', 'loam', 'ridgeline'];
const PLACES = ['whistler', 'bikepark', 'northstar', 'winterpark', 'snowshoe', 'moab', 'bentonville'];

const [styleArg, placeArg] = process.argv.slice(2);
const styles = styleArg ? [styleArg] : STYLES;
const places = placeArg ? [placeArg] : ['whistler'];

mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch({
  executablePath: process.env.CHROME_EXE || undefined,
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
});
const page = await browser.newPage({ viewport: { width: 1200, height: 820 } });
page.on('pageerror', (e) => console.error('  page error:', e.message));

await page.goto(URL, { waitUntil: 'load' });
await page.waitForFunction(() => !!window.lab, { timeout: 30000 });
await page.waitForTimeout(SETTLE);

for (const place of places) {
  const placeIndex = PLACES.indexOf(place);
  if (placeIndex < 0) throw new Error(`unknown place "${place}" — one of ${PLACES.join(', ')}`);
  for (const style of styles) {
    await page.evaluate(([s, i]) => {
      window.lab.setStyleId(s);
      window.lab.goto(i);
    }, [style, placeIndex]);
    await page.waitForTimeout(SETTLE);
    await page.evaluate(() => document.body.classList.add('collapsed'));
    await page.waitForTimeout(400);
    const file = `${OUT}/${style}-${place}.png`;
    await page.screenshot({ path: file });
    await page.evaluate(() => document.body.classList.remove('collapsed'));
    console.log('wrote', file);
  }
}

await browser.close();

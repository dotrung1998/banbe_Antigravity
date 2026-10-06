// READ-ONLY probe: where do map pins actually render vs where the map projects their lat/lng?
import { test } from '@playwright/test';
import { setupToHome } from '../../../tests/helpers.js';
import { adminClient } from '../../../tests/e2e/setup.mjs';
test('probe: marker geometry', async ({ page }) => {
  await setupToHome(page);
  await page.click('[data-testid="tab-map"]');
  await page.waitForSelector('[data-screen-label="MapExplore"]');
  await page.locator('[data-testid^="map-pin-"]').first().waitFor({ timeout: 10000 });
  await page.waitForTimeout(1500);
  const out = await page.evaluate(() => {
    const map = window.__mapExploreMapForTests; const cont = map.getContainer().getBoundingClientRect();
    const pins = [...document.querySelectorAll('[data-testid^="map-pin-"],[data-testid^="map-dot-"]')];
    return { viewport: [innerWidth, innerHeight], zoom: map.getZoom(), center: map.getCenter(), n: pins.length,
      wrapperPosition: pins[0] && getComputedStyle(pins[0].parentElement.parentElement || pins[0].parentElement).position,
      elPosition: pins[0] && getComputedStyle(pins[0].parentElement).position,
      pins: pins.slice(0, 6).map(p => { const r = p.getBoundingClientRect(); return { id: p.dataset.testid, x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) }; }) };
  });
  console.log('MARKERS', JSON.stringify(out));
  const { data: rows } = await adminClient().from('events').select('id,lat,lng').like('organizer_id', 'e2e-fixture-org-%');
  const coords = Object.fromEntries(rows.map(r => [r.id, [r.lng, r.lat]]));
  const cmp = await page.evaluate((coords) => { const map = window.__mapExploreMapForTests; const c = map.getContainer().getBoundingClientRect();
    return [...document.querySelectorAll('[data-testid^="map-pin-"]')].map(p => { const id = p.dataset.testid.replace('map-pin-', ''); const pr = map.project(coords[id]); const r = p.getBoundingClientRect();
      return { id: id, dx: Math.round(r.x + r.width / 2 - c.x - pr.x), dy: Math.round(r.y + r.height / 2 - c.y - pr.y) }; }); }, coords);
  console.log('OFFSETS(actual - projected, px)', JSON.stringify(cmp));
  const proj = await page.evaluate(() => { const map = window.__mapExploreMapForTests; const c = map.getContainer().getBoundingClientRect();
    return [...document.querySelectorAll('[data-testid^="map-pin-"]')].slice(0, 6).map(p => ({ id: p.dataset.testid })).length + ' ' + JSON.stringify(map.project([106.683, 10.7754]))+' '+JSON.stringify([c.x,c.y]); });
  console.log('PROJECT bepnho', proj);
});

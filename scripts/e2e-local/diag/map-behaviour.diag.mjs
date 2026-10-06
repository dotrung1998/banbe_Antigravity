// READ-ONLY probes mirroring the steps of failing map-explore specs, logging state instead of asserting.
import { test } from '@playwright/test';
import { setupToHome } from '../../../tests/helpers.js';
async function openMap(page) {
  await setupToHome(page); await page.click('[data-testid="tab-map"]'); await page.waitForSelector('[data-screen-label="MapExplore"]');
  const pin = page.locator('[data-testid^="map-pin-"]').first(); await pin.waitFor({ timeout: 10000 }); return pin;
}
test('probe 62: what is under the click point used by the map-background spec', async ({ page }) => {
  const pin = await openMap(page);
  await pin.click(); await page.waitForTimeout(1200);
  const box = await page.locator('[data-screen-label="MapExplore"] > div').first().boundingBox();
  const x = box.x + box.width / 2, y = box.y + 60;
  const hit = await page.evaluate(([x, y]) => { const e = document.elementFromPoint(x, y); return { tag: e?.tagName, testid: e?.closest('[data-testid]')?.dataset.testid, text: (e?.textContent || '').slice(0, 30), cls: e?.className }; }, [x, y]);
  console.log('P62 click point', JSON.stringify({ x, y }), 'hit', JSON.stringify(hit), 'search-here present =', await page.locator('[data-testid="map-search-here"]').count(), 'map box', JSON.stringify(box));
});
test('probe 353: detent weights through a detail round trip + poll', async ({ page }) => {
  const pin = await openMap(page);
  const w = async (l) => console.log('P353', l, await page.evaluate(() => ({ large: getComputedStyle(document.querySelector('[data-testid="map-sheet-list-large"]')).fontWeight, small: getComputedStyle(document.querySelector('[data-testid="map-sheet-list-small"]')).fontWeight })).catch(() => 'no sheet'));
  await w('initial'); await pin.click(); await page.waitForTimeout(500); await w('after pin click');
  await page.click('[data-testid="map-sheet-list-small"]'); await page.waitForTimeout(500); await w('after list-small click');
  await page.locator('[data-testid="map-card-cta"]').click(); await page.waitForTimeout(500);
  await page.locator('[data-testid="event-detail-back"]').click(); await page.waitForSelector('[data-screen-label="MapExplore"]'); await page.waitForTimeout(300); await w('after return');
  await page.waitForTimeout(5600); await w('after poll');
});
test('probe task7: Home first card -> open in map -> selected card', async ({ page }) => {
  await setupToHome(page);
  const first = page.locator('[data-testid^="home-event-"]').first();
  console.log('P7 first home card testid', await first.getAttribute('data-testid'));
  await first.click(); await page.waitForSelector('[data-screen-label="Event"]');
  await page.locator('[data-testid="event-open-in-map"]').click(); await page.waitForSelector('[data-screen-label="MapExplore"]'); await page.waitForTimeout(1500);
  console.log('P7 selected card =', await page.locator('[data-testid="map-selected-card"]').count(), 'list rows =', await page.locator('[data-testid^="map-list-item-"]').count());
  await page.waitForTimeout(5600);
  console.log('P7 after poll: card =', await page.locator('[data-testid="map-selected-card"]').count(), 'rows =', await page.locator('[data-testid^="map-list-item-"]').count());
});

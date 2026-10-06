// READ-ONLY: sample the sheet-detent buttons/card/selected-pin across a post-return poll cycle (spec 'first post-return polling cycle').
import { test } from '@playwright/test';
import { setupToHome } from '../../../tests/helpers.js';
test('probe 353 timeline', async ({ page }) => {
  await setupToHome(page); await page.click('[data-testid="tab-map"]'); await page.waitForSelector('[data-screen-label="MapExplore"]');
  const pin = page.locator('[data-testid^="map-pin-"]').first(); await pin.waitFor({ timeout: 10000 });
  await pin.click(); await page.click('[data-testid="map-sheet-list-small"]'); await page.waitForTimeout(400);
  await page.locator('[data-testid="map-card-cta"]').click(); await page.waitForSelector('[data-screen-label="Event"]');
  await page.locator('[data-testid="event-detail-back"]').click(); await page.waitForSelector('[data-screen-label="MapExplore"]');
  const t0 = Date.now(); const rows = [];
  while (Date.now() - t0 < 7000) {
    rows.push(await page.evaluate((t) => { const q = (s) => document.querySelector(s); const fw = (s) => q(s) ? getComputedStyle(q(s)).fontWeight : '-';
      return `${t}ms large=${fw('[data-testid="map-sheet-list-large"]')} small=${fw('[data-testid="map-sheet-list-small"]')} card=${q('[data-testid="map-selected-card"]') ? 1 : 0} pins=${document.querySelectorAll('[data-testid^="map-pin-"]').length}`; }, Date.now() - t0));
    await page.waitForTimeout(500);
  }
  console.log('P353T\n' + rows.join('\n'));
});

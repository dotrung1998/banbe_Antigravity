// @ts-check
import { test, expect } from '@playwright/test';
import { guestToHome } from './helpers.js';

// Note 68 — the compact Event Detail on a 6.1" phone (390×844): Date / Time / Place, the Host row and the CTA are
// visible without scrolling, the three tiles share one height, the host appears once, and no gap between sections
// is above 24px.
// Signed out (read-only guest browsing, note 49): the shared signed-in test account is held at the DOB account gate.
test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

test.describe('Event Detail — compact layout (note 68)', () => {
  for (const theme of ['theme-light', 'theme-dark']) test(`key facts, host and CTA above the fold; equal tiles; host once; gaps ≤ 24 (${theme})`, async ({ page }) => {
    await guestToHome(page, theme);
    await page.click('[data-testid="home-event-bepnho"]');
    await expect(page.locator('[data-screen-label="Event"]')).toBeVisible();
    await page.waitForTimeout(900); // the open animation

    for (const id of ['event-fact-when', 'event-fact-time', 'event-fact-where', 'event-organizer-row', 'event-reserve-bar']) {
      const box = await page.getByTestId(id).boundingBox();
      expect(box, id).not.toBeNull();
      expect(box.y + box.height, `${id} is above the fold`).toBeLessThanOrEqual(844);
    }
    // ...and not hidden under the sticky action area.
    const bar = await page.getByTestId('event-action-area').boundingBox();
    const host = await page.getByTestId('event-organizer-row').boundingBox();
    expect(host.y + host.height).toBeLessThanOrEqual(bar.y);

    const heights = await Promise.all(['event-fact-when', 'event-fact-time', 'event-fact-where'].map(async id => (await page.getByTestId(id).boundingBox()).height));
    expect(Math.max(...heights) - Math.min(...heights)).toBeLessThanOrEqual(1);

    // The host is shown once (regression: a track-record line used to repeat it above the Host card).
    await expect(page.getByTestId('event-track-record')).toHaveCount(0);
    await expect(page.getByTestId('event-organizer-row')).toHaveCount(1);

    // Every gap between the sheet's sections is at most 24px.
    const gaps = await page.getByTestId('event-host-section').evaluate((el) => {
      const sheet = el.parentElement;
      const kids = [...sheet.children].filter(k => getComputedStyle(k).position !== 'fixed' && k.getBoundingClientRect().height > 0);
      const out = [];
      for (let i = 1; i < kids.length; i++) out.push(Math.round(kids[i].getBoundingClientRect().top - kids[i - 1].getBoundingClientRect().bottom));
      return out;
    });
    for (const g of gaps) expect(g).toBeLessThanOrEqual(24);

    await page.screenshot({ path: process.env.SHOT_DIR ? `${process.env.SHOT_DIR}/event-detail-390-${theme}.png` : undefined });
  });
});

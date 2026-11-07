// @ts-check
import { test, expect } from '@playwright/test';
import { guestToHome } from './helpers.js';

// Notes 68 + 70, reshaped by V8 (note 75) on a 6.1" phone (390×844): the whole ticket stub (date, time, place, price and
// the seat chip) is on screen above the sticky bar, the title sits on the photo above it, the host appears once, and
// no gap between sections is above 24px. The bar is V8's: 1·2·3 preset chips over the stepper + CTA, one qty for both.
// Note 70's one-row bar (≤ 12% of the screen, no presets) is superseded by owner decision; its ceiling is now 21%.
// Signed out (read-only guest browsing, note 49): the shared signed-in test account is held at the DOB account gate.
test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

const BAR_SHARE = 0.21;

test.describe('Event Detail — V8 ticket stub (note 75)', () => {
  for (const theme of ['theme-light', 'theme-dark']) test(`stub above the bar; presets and stepper share one qty; host once; gaps ≤ 24 (${theme})`, async ({ page }) => {
    await guestToHome(page, theme);
    await page.click('[data-testid="home-event-bepnho"]');
    await expect(page.locator('[data-screen-label="Event"]')).toBeVisible();
    await page.waitForTimeout(900); // the open animation

    // The whole stub is on screen without scrolling, above the sticky action area.
    const bar = await page.getByTestId('event-action-area').boundingBox();
    for (const id of ['event-fact-when', 'event-fact-time', 'event-fact-where', 'event-price', 'event-seat-status', 'event-reserve-bar']) {
      const box = await page.getByTestId(id).boundingBox();
      expect(box, id).not.toBeNull();
      expect(box.y + box.height, `${id} is above the fold`).toBeLessThanOrEqual(844);
      if (id !== 'event-reserve-bar') expect(box.y + box.height, `${id} is above the sticky bar`).toBeLessThanOrEqual(bar.y);
    }
    // The title sits on the photo, above the stub.
    const title = await page.getByTestId('event-hero-title').boundingBox();
    const stub = await page.getByTestId('event-ticket-stub').boundingBox();
    expect(title.y + title.height).toBeLessThanOrEqual(stub.y + 1);
    // V8 seat chip: "N tickets left", never "of M".
    await expect(page.getByTestId('event-seat-status')).toHaveText(/^(Còn \d+ vé|\d+ tickets? left)$/);

    // The host is shown once (regression: a track-record line used to repeat it above the Host card).
    await expect(page.getByTestId('event-track-record')).toHaveCount(0);
    await expect(page.getByTestId('event-organizer-row')).toHaveCount(1);

    // Every gap between the sheet's sections is at most 24px.
    const gaps = await page.getByTestId('event-sheet').evaluate((sheet) => {
      const kids = [...sheet.children].filter(k => getComputedStyle(k).position !== 'fixed' && k.getBoundingClientRect().height > 0);
      const out = [];
      for (let i = 1; i < kids.length; i++) out.push(Math.round(kids[i].getBoundingClientRect().top - kids[i - 1].getBoundingClientRect().bottom));
      return out;
    });
    for (const g of gaps) expect(g).toBeLessThanOrEqual(24);

    // The bar: presets + stepper + CTA + the trust line within 21% of the screen.
    const area = await page.getByTestId('event-action-area').boundingBox();
    expect(area.height, 'booking bar height').toBeLessThanOrEqual(844 * BAR_SHARE);
    for (const n of [1, 2, 3]) await expect(page.getByTestId(`event-qty-${n}`)).toBeVisible();

    // One qty: a chip sets the stepper, the stepper lights the chip; 4+ would light none (capped at the seats left here).
    await expect(page.getByTestId('event-qty-1')).toHaveAttribute('aria-pressed', 'true');
    const total1 = await page.getByTestId('event-reserve-bar').innerText();
    await page.getByTestId('event-qty-2').click();
    await expect(page.getByTestId('event-qty-value')).toHaveText('2');
    await expect(page.getByTestId('event-qty-2')).toHaveAttribute('aria-pressed', 'true');
    await expect(page.getByTestId('event-qty-1')).toHaveAttribute('aria-pressed', 'false');
    expect(await page.getByTestId('event-reserve-bar').innerText()).not.toBe(total1);
    await page.getByTestId('event-qty-plus').click();
    await expect(page.getByTestId('event-qty-value')).toHaveText('3');
    await expect(page.getByTestId('event-qty-3')).toHaveAttribute('aria-pressed', 'true');
    await page.getByTestId('event-qty-minus').click();
    await page.getByTestId('event-qty-minus').click();
    await expect(page.getByTestId('event-qty-1')).toHaveAttribute('aria-pressed', 'true');
    // The stepper never offers more than the seats left (bepnho: 3 of 3), and neither do the chips.
    const seatText = await page.getByTestId('event-seat-status').innerText();
    const left = Number((seatText.match(/\d+/) || [])[0]);
    if (left > 0 && left < 3) await expect(page.getByTestId('event-qty-3')).toBeDisabled();
    for (let i = 0; i < 6; i++) if (await page.getByTestId('event-qty-plus').isEnabled()) await page.getByTestId('event-qty-plus').click();
    if (left > 0) await expect(page.getByTestId('event-qty-value')).toHaveText(String(Math.min(6, left)));

    // No raw technical copy or heavy separators, and no Vietnamese date on an English screen.
    const text = await page.locator('[data-screen-label="Event"]').innerText();
    for (const bad of ['Any of:', 'Interests:', '▪', 'km away\n']) expect(text, bad).not.toContain(bad);
    await expect(page.getByTestId('event-fact-when')).not.toContainText(/^Th \d|CN,/);

    await page.screenshot({ path: process.env.SHOT_DIR ? `${process.env.SHOT_DIR}/event-detail-390-${theme}.png` : undefined });
  });
});

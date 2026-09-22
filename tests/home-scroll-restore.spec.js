// @ts-check
import { test, expect } from '@playwright/test';

// Task 2 (2026-09-22 twelfth follow-up) — verifies the EXISTING scroll
// save/restore mechanism (App.jsx's Shell, scrollPositions.current keyed by
// state.screen, restored via useLayoutEffect + a settle-window
// ResizeObserver — see that file's own comments) actually holds for the
// specific real-device-reported round trip: scroll Home down, open an
// event, back out, land back at (approximately) the same scroll offset
// rather than snapping to the top.
test('scrolling Home down, opening an event, and going back preserves scroll position', async ({ page }) => {
  await page.goto('/');
  await page.waitForSelector('[data-screen-label="Home"]', { timeout: 10000 });

  // Scroll deep enough to guarantee we're well past the first screenful.
  await page.evaluate(() => {
    const el = document.querySelector('div[style*="overflow"]');
    if (el) el.scrollTop = 1400;
  });
  await page.waitForTimeout(150);
  const before = await page.evaluate(() => document.querySelector('div[style*="overflow"]')?.scrollTop);
  expect(before).toBeGreaterThan(800);

  // Click whichever event card is currently near the restored scroll offset.
  const anyCard = page.locator('[data-testid^="home-event-"]');
  const count = await anyCard.count();
  let opened = false;
  for (let i = 0; i < count; i++) {
    const box = await anyCard.nth(i).boundingBox();
    if (box && box.y > 0 && box.y < 700) { await anyCard.nth(i).click({ force: true }); opened = true; break; }
  }
  expect(opened).toBe(true);
  await expect(page.locator('[data-screen-label="Event"]')).toBeVisible({ timeout: 8000 });

  await page.click('[data-testid="event-detail-back"]');
  await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
  await page.waitForTimeout(600); // let the settle-window ResizeObserver logic finish
  const after = await page.evaluate(() => document.querySelector('div[style*="overflow"]')?.scrollTop);
  expect(Math.abs(after - before)).toBeLessThan(150);
});

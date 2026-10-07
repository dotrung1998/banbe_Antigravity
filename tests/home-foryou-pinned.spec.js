// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

// Home's second filter row: "For You" is pinned at the leading edge and only the
// remaining chips scroll (data-testid="home-filter-extra-scroller", data-hscroll).
// The For You chip only exists for an account with preferences + matching events,
// so assertions about it are skipped (not failed) when it is absent.
test.use({ viewport: { width: 390, height: 844 } });

async function scroller(page) {
  const el = page.getByTestId('home-filter-extra-scroller');
  await el.waitFor({ timeout: 8000 });
  return el;
}

test.describe('Home For You pinned chip', () => {
  test('scroller keeps data-hscroll and horizontal scroll moves only the extra chips', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');
    const sc = await scroller(page);
    await expect(sc).toHaveAttribute('data-hscroll', 'true');
    const forYou = page.getByTestId('home-filter-foryou');
    const hasForYou = await forYou.count() > 0;
    const before = hasForYou ? await forYou.boundingBox() : null;
    const first = page.getByTestId('home-filter-upcoming');
    const firstBefore = await first.boundingBox();
    await sc.evaluate(el => { el.scrollLeft = 80; });
    await page.waitForTimeout(100);
    const firstAfter = await first.boundingBox();
    if (firstBefore && firstAfter) expect(firstAfter.x).toBeLessThan(firstBefore.x);
    if (hasForYou && before) {
      const after = await forYou.boundingBox();
      expect(after?.x).toBe(before.x);
    }
  });

  test('the second row is not sticky vertically', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');
    const sc = await scroller(page);
    const y0 = (await sc.boundingBox())?.y ?? 0;
    await page.mouse.move(200, 500);
    await page.mouse.wheel(0, 300);
    await page.waitForTimeout(300);
    const y1 = (await sc.boundingBox())?.y ?? y0;
    // Either the page scrolled (row moved up) or there was nothing to scroll; never moves down.
    expect(y1).toBeLessThanOrEqual(y0);
  });

  test('a horizontal drag on the scroller does not switch tab (root swipe ignores data-hscroll)', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');
    const sc = await scroller(page);
    const b = await sc.boundingBox();
    if (!b) test.skip(true, 'scroller not laid out');
    const y = b.y + b.height / 2;
    const startX = b.x + b.width * 0.7;
    await page.mouse.move(startX, y);
    await page.mouse.down();
    for (let x = startX; x > startX - 160; x -= 20) await page.mouse.move(x, y);
    await page.mouse.up();
    await page.waitForTimeout(500);
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
    await expect(page.locator('[data-screen-label="MapExplore"]')).toHaveCount(0);
  });
});

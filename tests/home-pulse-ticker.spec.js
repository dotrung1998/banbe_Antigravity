// @ts-check
import { test, expect } from '@playwright/test';

// Note 51 — Banbe Pulse is one slim ticker line under Home's search bar (it used to be a big tile in the story row
// with a teaser bubble, and left a tall empty band when there were no stories). Run signed out (Pulse is public), with
// the ranking mocked so the content is deterministic.
test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

const json = (body) => ({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
const RANKED = {
  success: true,
  items: [
    { event_id: 'e1', event_name: 'Supper club 6 món ở Quận 3', score: 42 },
    { event_id: 'e2', event_name: 'Đêm nhạc acoustic Thảo Điền', score: 31 },
    { event_id: 'e3', event_name: 'Gallery walk Bình Thạnh', score: 20 },
  ],
};

async function openGuestHome(page, { ranked = RANKED } = {}) {
  await page.route('**/rest/v1/rpc/goc_pulse_ranked', (r) => r.fulfill(json(ranked)));
  await page.goto('/');
  for (let i = 0; i < 40; i++) {
    if (await page.getByTestId('lang-en').isVisible().catch(() => false)) { await page.getByTestId('lang-en').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('onboarding-continue').isVisible().catch(() => false)) { await page.getByTestId('onboarding-continue').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('welcome-explore').isVisible().catch(() => false)) { await page.getByTestId('welcome-explore').click(); break; }
    if (await page.locator('[data-screen-label="Home"]').isVisible().catch(() => false)) break;
    await page.waitForTimeout(400);
  }
  await page.waitForSelector('[data-screen-label="Home"]', { timeout: 20000 });
  await page.getByTestId('home-pulse-ticker').waitFor();
}

test.describe('Home Pulse ticker', () => {
  test('sits right under the search bar as one slim line and shows the ranked events', async ({ page }) => {
    await openGuestHome(page);
    const search = await page.getByTestId('home-search-bar').boundingBox();
    const ticker = await page.getByTestId('home-pulse-ticker').boundingBox();
    expect(ticker.y).toBeGreaterThan(search.y + search.height - 1);
    expect(ticker.y - (search.y + search.height)).toBeLessThan(20);
    expect(ticker.height).toBeLessThanOrEqual(44);
    await expect(page.getByTestId('home-pulse-ticker')).toHaveAttribute('data-items', '3');
    await expect(page.getByTestId('home-pulse-ticker-run')).toBeVisible();
    // Names come from the server ranking, and the looped copy is hidden from assistive tech (read once).
    await expect(page.getByTestId('home-pulse-ticker-run')).toContainText('Supper club 6 món ở Quận 3');
    const label = await page.getByTestId('home-pulse-ticker').getAttribute('aria-label');
    expect(label).toContain('Gallery walk Bình Thạnh');
    expect(await page.locator('[data-testid="home-pulse-ticker-run"] [aria-hidden="true"]').count()).toBeGreaterThan(0);
  });

  test('it scrolls, and pauses under the pointer', async ({ page }) => {
    await openGuestHome(page);
    const run = page.getByTestId('home-pulse-ticker-run');
    const name = await run.evaluate((el) => getComputedStyle(el).animationName);
    expect(name).toBe('bbTicker');
    const x0 = (await run.boundingBox()).x;
    await page.waitForTimeout(900);
    const x1 = (await run.boundingBox()).x;
    expect(x1).toBeLessThan(x0); // moved left
    await page.getByTestId('home-pulse-ticker').hover();
    await expect.poll(() => run.evaluate((el) => getComputedStyle(el).animationPlayState)).toBe('paused');
  });

  test('tapping it opens the Pulse viewer', async ({ page }) => {
    await openGuestHome(page);
    await page.getByTestId('home-pulse-ticker').click();
    await expect(page.getByTestId('pulse-viewer')).toBeVisible();
  });

  test('no ranking yet: a static invitation, still tappable, never an empty box', async ({ page }) => {
    await openGuestHome(page, { ranked: { success: true, items: [] } });
    await expect(page.getByTestId('home-pulse-ticker-empty')).toBeVisible();
    await expect(page.getByTestId('home-pulse-ticker-run')).toHaveCount(0);
    await page.getByTestId('home-pulse-ticker').click();
    await expect(page.getByTestId('pulse-viewer')).toBeVisible();
  });

  test('with no stories there is no story row and no tall empty band above the categories', async ({ page }) => {
    await openGuestHome(page);
    await expect(page.getByTestId('home-story-row')).toHaveCount(0);
    const ticker = await page.getByTestId('home-pulse-ticker').boundingBox();
    const cats = await page.getByTestId('home-category-row').boundingBox();
    // Between the ticker and the categories there is only the guest banner (about 80px), not a 100px Pulse tile band.
    expect(cats.y - (ticker.y + ticker.height)).toBeLessThan(130);
  });
});

test.describe('Home Pulse ticker, reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });
  test('no animation: one static, ellipsised line with the top events', async ({ page }) => {
    await openGuestHome(page);
    await expect(page.getByTestId('home-pulse-ticker-run')).toHaveCount(0);
    await expect(page.getByTestId('home-pulse-ticker')).toContainText('Supper club 6 món ở Quận 3');
    const box = await page.getByTestId('home-pulse-ticker').boundingBox();
    expect(box.height).toBeLessThanOrEqual(44);
  });
});

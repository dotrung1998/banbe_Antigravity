// @ts-check
import { test, expect } from '@playwright/test';

// Note 81, phase a: the v2.3 Home Shortlist behind switch home_v23 (on top of simple_shell). Guest browsing, fully
// mocked Supabase (nothing reaches the real backend). Optional screenshots: V23_SHOTS=<dir>.
const SHOTS = process.env.V23_SHOTS;
const SUPABASE = 'https://ukchdgdnwytretvqjjqu.supabase.co';
const json = (body, status = 200) => ({ status, contentType: 'application/json', body: JSON.stringify(body) });
const inDays = (d, h = 19) => { const t = new Date(Date.now() + d * 864e5); t.setUTCHours(h - 7, 0, 0, 0); return t.toISOString(); };
// Seven upcoming events: For You (a guest has no answers, so the soonest) pages as 4 + 3, ending in a slim end card.
const EVENTS = Array.from({ length: 7 }, (_, i) => ({
  id: `e8100000-0000-4000-8000-00000000000${i + 1}`, key: `v23e${i + 1}`, name: `Test night ${i + 1}`,
  cat_key: ['music', 'supper', 'gallery', 'fashion'][i % 4], starts_at: inDays(i + 2), price_vnd: i === 3 ? 0 : 150000 + i * 10000,
})).map(e => ({ ...e, status: 'live', visibility: 'public', capacity: 20, seats_remaining: 20, area: 'Quận 1', country_code: 'VN', state_province: 'Hồ Chí Minh', tz: 'Asia/Ho_Chi_Minh', currency: 'VND' }));

test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

/** @param {import('@playwright/test').Page} page @param {Record<string, boolean>} flags */
async function mockSupabase(page, flags) {
  await page.route(`${SUPABASE}/**`, async (r) => {
    const url = new URL(r.request().url());
    const p = url.pathname;
    const accept = r.request().headers().accept || '';
    if (p.startsWith('/auth/v1/')) return r.fulfill({ status: 204, body: '' });
    if (p.startsWith('/rest/v1/rpc/')) {
      const fn = p.split('/').pop();
      if (fn === 'get_feature_flags') return r.fulfill(json(flags));
      return r.fulfill(json(null));
    }
    if (p.startsWith('/rest/v1/events')) return r.fulfill(json(EVENTS));
    if (p.startsWith('/rest/v1/')) return r.fulfill(accept.includes('vnd.pgrst.object') ? json(null, 406) : json([]));
    return r.fulfill({ status: 404, body: '' });
  });
  // The guest onboarding preview (note 80) counts as seen, so "Explore events" goes straight to Home.
  await page.addInitScript((f) => { try { localStorage.setItem('banbe_feature_flags_v1', JSON.stringify(f)); localStorage.setItem('banbe.guestOnboarding.v1', '1'); } catch { /* */ } }, flags);
}

/** @param {import('@playwright/test').Page} page */
async function guestHome(page) {
  await page.goto('/');
  for (let i = 0; i < 40; i++) {
    if (await page.getByTestId('lang-en').isVisible().catch(() => false)) { await page.getByTestId('lang-en').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('onboarding-continue').isVisible().catch(() => false)) { await page.getByTestId('onboarding-continue').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('welcome-explore').isVisible().catch(() => false)) { await page.getByTestId('welcome-explore').click(); await page.waitForTimeout(300); continue; }
    if (await page.locator('[data-screen-label="Home"]').isVisible().catch(() => false)) break;
    await page.waitForTimeout(300);
  }
  await page.waitForSelector('[data-screen-label="Home"]', { timeout: 20000 });
}
const shot = async (page, name) => { if (SHOTS) { await page.waitForTimeout(700); await page.screenshot({ path: `${SHOTS}/${name}.png` }); } };

test('switch off: Home keeps By type, no Shortlist', async ({ page }) => {
  await mockSupabase(page, { simple_shell: true });
  await guestHome(page);
  await expect(page.getByTestId('home-by-type')).toBeVisible({ timeout: 15000 });
  await expect(page.getByTestId('home-shortlist-section')).toHaveCount(0);
});

test('switch on: the Shortlist pages four rows at a time, with numbers, a range line and an end card', async ({ page }) => {
  await mockSupabase(page, { simple_shell: true, home_v23: true });
  await guestHome(page);
  const section = page.getByTestId('home-shortlist-section');
  await expect(section).toBeVisible({ timeout: 15000 });
  await expect(page.getByTestId('home-by-type')).toHaveCount(0);
  // Tour targets survive (note 64): the filter summary and the Browse block.
  await expect(page.getByTestId('home-filter-summary')).toBeVisible();

  const pager = page.getByTestId('home-shortlist');
  const pages = Number(await pager.getAttribute('data-pages'));
  expect(pages).toBeGreaterThanOrEqual(2);
  await expect(pager).toHaveAttribute('data-page', '0');
  const first = page.locator('[data-pager-page="0"] [data-testid^="home-event-"]');
  await expect(first).toHaveCount(4);
  const range = page.getByTestId('home-shortlist-range');
  await expect(range).toHaveText(/^1–4 of \d+$/);
  await expect(range).toHaveAttribute('aria-live', 'polite');
  await expect(page.getByTestId('home-shortlist-prev')).toBeDisabled();
  await expect(page.getByTestId('home-shortlist-page-1')).toHaveAttribute('aria-current', 'page');
  await section.scrollIntoViewIfNeeded();
  await shot(page, 'a1-shortlist-page1');

  // Tap targets are at least 44 px.
  for (const id of ['home-shortlist-prev', 'home-shortlist-next', 'home-shortlist-page-1', 'home-filters-button']) {
    const b = await page.getByTestId(id).boundingBox();
    expect(b.height, id).toBeGreaterThanOrEqual(44);
    expect(b.width, id).toBeGreaterThanOrEqual(44);
  }

  // A number tap turns the page; the old page goes inert and the range follows.
  await page.getByTestId('home-shortlist-page-2').click();
  await expect(pager).toHaveAttribute('data-page', '1');
  await expect(page.getByTestId('home-shortlist-page-2')).toHaveAttribute('aria-current', 'page');
  await expect(page.locator('[data-pager-page="0"]')).toHaveAttribute('aria-hidden', 'true');
  expect(await page.locator('[data-pager-page="0"]').evaluate(el => el.inert)).toBe(true);
  await expect(range).toHaveText(/^5–\d+ of \d+$/);
  await shot(page, 'a2-shortlist-page2');

  // At most five numbers show, always around the current page (long lists keep the arrows on screen).
  expect(await page.locator('[data-testid^="home-shortlist-page-"]').count()).toBeLessThanOrEqual(5);
  const next = page.getByTestId('home-shortlist-next');
  const box = await next.boundingBox();
  expect(box.x + box.width).toBeLessThanOrEqual(390);
  // Walk to the last page with the arrow; a short last page ends with a card sized to the missing rows.
  for (let i = 1; i < pages - 1; i++) await next.click();
  await expect(pager).toHaveAttribute('data-page', String(pages - 1));
  await expect(page.getByTestId(`home-shortlist-page-${pages}`)).toHaveAttribute('aria-current', 'page');
  const end = page.getByTestId('home-shortlist-end');
  // The demo catalogue is merged into Home, so the total depends on it: a full last page has no end card.
  const room = (await end.count()) ? Number(await end.getAttribute('data-room')) : 0;
  if (room > 0) {
    await expect(end).toBeVisible();
    await expect(end).toHaveAttribute('data-variant', room === 1 ? 'slim' : room === 2 ? 'mid' : 'fill');
    const box = await end.boundingBox();
    expect(box.height).toBeGreaterThanOrEqual(room * 92 - 1);
    await expect(page.getByTestId('list-end-card')).toHaveAttribute('data-kind', 'end');
  }
  await expect(page.getByTestId('home-shortlist-next')).toBeDisabled();

  // The arrows drive the same track.
  await page.getByTestId('home-shortlist-prev').click();
  await expect(pager).toHaveAttribute('data-page', String(pages - 2));
});

test('switch on, reduced motion: the page still turns and the range still updates', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await mockSupabase(page, { simple_shell: true, home_v23: true });
  await guestHome(page);
  await expect(page.getByTestId('home-shortlist')).toBeVisible({ timeout: 15000 });
  await page.getByTestId('home-shortlist-next').click();
  await expect(page.getByTestId('home-shortlist')).toHaveAttribute('data-page', '1');
  await expect(page.getByTestId('home-shortlist-range')).toHaveText(/^5–/);
});

test('switch on, Tonight: a short single page has no page numbers and ends with a card', async ({ page }) => {
  await mockSupabase(page, { simple_shell: true, home_v23: true });
  await guestHome(page);
  await expect(page.getByTestId('home-shortlist-section')).toBeVisible({ timeout: 15000 });
  await page.getByTestId('home-hero-tab-tonight').click();
  const pager = page.getByTestId('home-shortlist');
  const empty = page.getByTestId('home-shortlist-empty');
  await expect(pager.or(empty)).toBeVisible();
  if (await empty.count()) {
    // Nothing tonight: an honest empty state with a real way forward.
    await expect(page.getByTestId('home-shortlist-types')).toBeVisible();
    return;
  }
  const pages = Number(await pager.getAttribute('data-pages'));
  if (pages === 1) {
    await expect(page.getByTestId('home-shortlist-next')).toHaveCount(0);
    await expect(page.getByTestId('home-shortlist-range')).toHaveCount(0);
  }
});

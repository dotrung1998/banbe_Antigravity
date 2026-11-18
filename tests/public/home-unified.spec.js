// @ts-check
import { test, expect } from '@playwright/test';

// Note 99: unified discovery on Home (switch unified_discovery, on top of home_v23 + simple_shell). Guest browsing, fully
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

const ON = { simple_shell: true, home_v23: true, unified_discovery: true };

test('switch off: Browse by type still opens /browse, no state bar or map banner', async ({ page }) => {
  await mockSupabase(page, { simple_shell: true, home_v23: true });
  await guestHome(page);
  await expect(page.getByTestId('home-shortlist-section')).toBeVisible({ timeout: 15000 });
  await expect(page.locator('[data-testid="home-browse"][data-unified="1"]')).toHaveCount(0);
  await expect(page.getByTestId('home-map-banner')).toHaveCount(0);
});

const total = async (page) => Number((await page.getByTestId('home-shortlist-range').textContent()).match(/(\d+)$/)[1]);

test('tabs are the shared time: Weekend narrows the list, For You widens it again', async ({ page }) => {
  await mockSupabase(page, ON);
  await guestHome(page);
  await expect(page.getByTestId('home-shortlist-range')).toBeVisible({ timeout: 15000 });
  const all = await total(page);
  await page.getByTestId('home-hero-tab-weekend').click();
  await expect(page.getByTestId('home-hero-tab-weekend')).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByTestId('home-state-bar')).toHaveCount(0); // time alone is the tab, not a filter
  const weekend = await page.getByTestId('home-shortlist-range').count() ? await total(page) : 0;
  expect(weekend).toBeLessThan(all);
  await page.getByTestId('home-hero-tab-foryou').click();
  await expect(page.getByTestId('home-shortlist-range')).toHaveText(new RegExp(`of ${all}$`));
  await shot(page, 'unified-home');
});

test('a type tile filters Home in place, the state bar says so and clears it', async ({ page }) => {
  await mockSupabase(page, ON);
  await guestHome(page);
  const grid = page.locator('[data-testid="home-browse"][data-unified="1"]');
  await expect(grid).toBeVisible({ timeout: 15000 });
  const all = await total(page);
  const tile = grid.locator('[data-testid^="home-browse-"]:not([data-testid="home-browse-find"]):not([data-testid="home-browse-all"])').first();
  const key = (await tile.getAttribute('data-testid')).replace('home-browse-', '');
  const n = Number((await tile.locator('small').textContent()).match(/\d+/)[0]);
  await tile.click();
  await expect(page.locator('[data-screen-label="Home"]')).toBeVisible(); // stays on Home
  await expect(grid.getByTestId(`home-browse-${key}`)).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('home-state-bar')).toBeVisible();
  await expect(page.getByTestId('home-shortlist-range')).toHaveText(new RegExp(`of ${n}$`)); // the list follows the type
  await expect(page.getByTestId('home-filter-summary')).toContainText(String(n));
  await expect(page.getByTestId('home-filter-badge')).toHaveText('1');
  await page.getByTestId('home-state-bar-clear').click();
  await expect(page.getByTestId('home-state-bar')).toHaveCount(0);
  await expect(grid.getByTestId(`home-browse-${key}`)).toHaveAttribute('aria-pressed', 'false');
});

test('All types: the sheet searches types and a type outside the tiles takes over the 6th tile', async ({ page }) => {
  await mockSupabase(page, ON);
  await guestHome(page);
  const grid = page.locator('[data-testid="home-browse"][data-unified="1"]');
  const find = grid.getByTestId('home-browse-find');
  await expect(find).toBeVisible({ timeout: 15000 });
  const tiles = await grid.locator('[data-testid^="home-browse-"]').evaluateAll(els => els.map(e => e.getAttribute('data-testid').replace('home-browse-', '')));
  await find.click();
  await expect(page.getByTestId('home-type-sheet')).toBeVisible();
  const sheetKeys = await page.locator('[data-testid^="home-type-sheet-"][aria-pressed]').evaluateAll(els => els.map(e => e.getAttribute('data-testid').replace('home-type-sheet-', '')));
  // With a catalogue of more types than tiles, pick one that is not a tile (it takes over the 6th tile); with five or
  // fewer types every type is a tile, so the pick just selects that tile (the takeover rule is unit-tested).
  const outside = sheetKeys.find(k => k !== 'all' && !tiles.includes(k));
  const key = outside || sheetKeys.find(k => k !== 'all');
  await page.getByTestId('home-type-sheet-search').fill('zzzz');
  await expect(page.locator('[data-testid^="home-type-sheet-"][aria-pressed]')).toHaveCount(0);
  await page.getByTestId('home-type-sheet-search').fill('');
  await page.getByTestId(`home-type-sheet-${key}`).click();
  await expect(page.getByTestId('home-type-sheet')).toHaveCount(0);
  if (outside) {
    await expect(find).toHaveAttribute('data-picked', key);
    await expect(find).toHaveAttribute('aria-pressed', 'true');
  } else {
    await expect(grid.getByTestId(`home-browse-${key}`)).toHaveAttribute('aria-pressed', 'true');
  }
});

test('the map banner opens the Map with the same count', async ({ page }) => {
  await mockSupabase(page, ON);
  await guestHome(page);
  await expect(page.getByTestId('home-shortlist-range')).toBeVisible({ timeout: 15000 });
  const all = await total(page);
  const banner = page.getByTestId('home-map-banner');
  await banner.scrollIntoViewIfNeeded();
  await expect(banner).toContainText(`${all} `);
  await banner.click();
  await expect(page.locator('[data-screen-label="Home"]')).toBeHidden({ timeout: 15000 });
});

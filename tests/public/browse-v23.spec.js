// @ts-check
import { test, expect } from '@playwright/test';

// Note 81, phase b: Browse by type / See all behind switch home_v23. Guest browsing, fully mocked Supabase.
// Optional screenshots: V23_SHOTS=<dir>.
const SHOTS = process.env.V23_SHOTS;
const SUPABASE = 'https://ukchdgdnwytretvqjjqu.supabase.co';
const json = (body, status = 200) => ({ status, contentType: 'application/json', body: JSON.stringify(body) });
const inDays = (d, h = 19) => { const t = new Date(Date.now() + d * 864e5); t.setUTCHours(h - 7, 0, 0, 0); return t.toISOString(); };
// Six music hosts (the deck shows 4 faces + 2), nine music events (3 pages with the demo catalogue merged in or not).
const ORGS = Array.from({ length: 6 }, (_, i) => ({ id: `org_v23_${i + 1}`, name: ['Gác Test', 'Băng Test', 'Đêm Test', 'Sax Test', 'Piano Test', 'Bass Test'][i], avatar_path: '' }));
const EVENTS = Array.from({ length: 9 }, (_, i) => ({
  id: `e8200000-0000-4000-8000-00000000000${i + 1}`, name: i === 0 ? 'Jazz test night' : `Music test ${i + 1}`,
  cat_key: 'music', starts_at: inDays(i + 2), price_vnd: i === 1 ? 0 : 150000, organizer_id: ORGS[i % 6].id,
})).map(e => ({ ...e, status: 'live', visibility: 'public', capacity: 20, seats_remaining: 20, area: 'Quận 1', country_code: 'VN', state_province: 'Hồ Chí Minh', tz: 'Asia/Ho_Chi_Minh', currency: 'VND' }));
const FLAGS = { simple_shell: true, home_v23: true };

test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

/** @param {import('@playwright/test').Page} page */
async function mockSupabase(page) {
  await page.route(`${SUPABASE}/**`, async (r) => {
    const url = new URL(r.request().url());
    const p = url.pathname;
    const accept = r.request().headers().accept || '';
    if (p.startsWith('/auth/v1/')) return r.fulfill({ status: 204, body: '' });
    if (p.startsWith('/rest/v1/rpc/')) {
      const fn = p.split('/').pop();
      if (fn === 'get_feature_flags') return r.fulfill(json(FLAGS));
      if (fn === 'get_organizer_profile') return r.fulfill(json({ success: true, organizer: { id: ORGS[0].id, name: ORGS[0].name }, events: [], following: false }));
      return r.fulfill(json(null));
    }
    if (p.startsWith('/rest/v1/events')) return r.fulfill(json(EVENTS));
    if (p.startsWith('/rest/v1/organizers')) return r.fulfill(json(ORGS));
    if (p.startsWith('/rest/v1/')) return r.fulfill(accept.includes('vnd.pgrst.object') ? json(null, 406) : json([]));
    return r.fulfill({ status: 404, body: '' });
  });
  await page.addInitScript((f) => { try { localStorage.setItem('banbe_feature_flags_v1', JSON.stringify(f)); localStorage.setItem('banbe.guestOnboarding.v1', '1'); } catch { /* */ } }, FLAGS);
}

/** @param {import('@playwright/test').Page} page @param {string} path */
async function guestOpen(page, path = '/') {
  await page.goto(path);
  for (let i = 0; i < 40; i++) {
    if (await page.getByTestId('browse-screen').isVisible().catch(() => false)) return;
    if (await page.getByTestId('lang-en').isVisible().catch(() => false)) { await page.getByTestId('lang-en').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('onboarding-continue').isVisible().catch(() => false)) { await page.getByTestId('onboarding-continue').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('welcome-explore').isVisible().catch(() => false)) { await page.getByTestId('welcome-explore').click(); await page.waitForTimeout(300); continue; }
    if (path === '/' && await page.locator('[data-screen-label="Home"]').isVisible().catch(() => false)) return;
    await page.waitForTimeout(300);
  }
}
const shot = async (page, name) => { if (SHOTS) { await page.waitForTimeout(700); await page.screenshot({ path: `${SHOTS}/${name}.png` }); } };

test('a guest deep link opens Browse on that type; Back returns Home', async ({ page }) => {
  await mockSupabase(page);
  await guestOpen(page, '/browse/music');
  const screen = page.getByTestId('browse-screen');
  await expect(screen).toBeVisible({ timeout: 20000 });
  await expect(screen).toHaveAttribute('data-type', 'music');
  await expect(page.getByTestId('browse-title')).toHaveText('Music');
  await expect(page.getByTestId('browse-type-music')).toHaveAttribute('aria-selected', 'true');
  await shot(page, 'b1-browse-music');
  await page.getByTestId('browse-back').click();
  await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
  await expect(page).toHaveURL(/\/$/);
});

test('rail of four ends in See all, which opens that tab; browser back and forward keep the list', async ({ page }) => {
  await mockSupabase(page);
  await guestOpen(page, '/');
  const rail = page.getByTestId('home-hero-rail');
  await expect(rail).toBeVisible({ timeout: 20000 });
  expect(await rail.locator('[data-testid^="home-hero-card-"]').count()).toBeLessThanOrEqual(4);
  await page.getByTestId('home-hero-see-all').click();
  await expect(page.getByTestId('browse-screen')).toHaveAttribute('data-scope', 'foryou');
  await expect(page).toHaveURL(/\/see-all\/foryou$/);
  await page.getByTestId('browse-type-music').click();
  await expect(page).toHaveURL(/\/see-all\/foryou\/music$/);
  await page.goBack();
  await expect(page).toHaveURL(/\/see-all\/foryou$/);
  await page.goForward();
  await expect(page.getByTestId('browse-screen')).toHaveAttribute('data-type', 'music');
});

test('host deck shows four faces and +N, the host list searches and opens the real profile, Back returns to the list', async ({ page }) => {
  await mockSupabase(page);
  await guestOpen(page, '/browse/music');
  const deck = page.getByTestId('browse-host-deck');
  await expect(deck).toBeVisible({ timeout: 20000 });
  await expect(deck).toHaveAttribute('data-hosts', '6');
  await expect(page.getByTestId('browse-host-more')).toHaveText('+2');
  await expect(deck).toContainText('and 4 more hosts');
  await deck.click();
  await expect(page.getByTestId('host-list-sheet')).toBeVisible();
  await page.getByTestId('host-list-search').fill('gac');
  await expect(page.locator('[data-testid^="host-list-row-"]')).toHaveCount(1);
  await shot(page, 'b2-host-list');
  await page.getByTestId(`host-list-row-${ORGS[0].id}`).click();
  await expect(page).toHaveURL(new RegExp(`/org/${ORGS[0].id}$`));
  await page.goBack();
  await expect(page.getByTestId('browse-screen')).toHaveAttribute('data-type', 'music');
});

test('search: the magnifier turns the title into a field, Done keeps the query, × clears it', async ({ page }) => {
  await mockSupabase(page);
  await guestOpen(page, '/browse/music');
  await expect(page.getByTestId('browse-screen')).toBeVisible({ timeout: 20000 });
  const before = await page.getByTestId('browse-count').textContent();
  await page.getByTestId('browse-search').click();
  const input = page.getByTestId('browse-search-input');
  await expect(input).toBeFocused();
  await input.fill('jazz test');
  await page.keyboard.press('Enter');
  await expect(input).toHaveCount(0);
  await expect(page.getByTestId('browse-nav-title')).toHaveText('“jazz test” · Music');
  await expect(page.getByTestId('browse-count')).toHaveText('1 event');
  await expect(page.getByTestId('list-end-card')).toHaveAttribute('data-kind', 'search');
  await page.getByTestId('browse-search').click();
  await page.getByTestId('browse-search').click(); // now the × button
  await expect(page.getByTestId('browse-count')).toHaveText(before || '');
});

test('own Filters: When, Price, Seats only, with a badge and a live count', async ({ page }) => {
  await mockSupabase(page);
  await guestOpen(page, '/browse/music');
  await expect(page.getByTestId('browse-screen')).toBeVisible({ timeout: 20000 });
  await page.getByTestId('browse-filters-button').click();
  const sheet = page.getByTestId('home-filter-sheet');
  await expect(sheet).toHaveAttribute('aria-label', 'Filter Music');
  await expect(sheet.locator('[data-testid^="home-filter-cat-"]')).toHaveCount(0);
  await expect(page.getByTestId('home-filter-area')).toHaveCount(0);
  await expect(page.getByTestId('home-sort-soonest')).toHaveCount(0);
  await page.getByTestId('home-filter-free').click();
  const apply = page.getByTestId('home-filter-apply');
  const n = Number(await apply.getAttribute('data-count'));
  expect(n).toBeGreaterThan(0);
  await apply.click();
  await expect(page.getByTestId('browse-filter-badge')).toHaveText('1');
  await expect(page.getByTestId('browse-count')).toHaveText(new RegExp(`^${n} event`));
});

test('swipe signs: a slim edge tab toward the next page and a cue line that fades after the first turn', async ({ page }) => {
  await mockSupabase(page);
  await guestOpen(page, '/browse/music');
  await expect(page.getByTestId('browse-screen')).toBeVisible({ timeout: 20000 });
  const list = page.getByTestId('browse-list');
  const pages = Number(await list.getAttribute('data-pages'));
  expect(pages).toBeGreaterThanOrEqual(2);
  const next = page.getByTestId('browse-list-hint-next');
  await expect(next).toBeVisible();
  // Slim enough to stay clear of the prices; no pages lean or bounce at the edge.
  expect((await next.boundingBox()).width).toBeLessThanOrEqual(20);
  await expect(page.getByTestId('browse-list-hint-prev')).toHaveCount(0);
  await expect(page.getByTestId('browse-list-cue')).toHaveAttribute('data-gone', 'false');
  // The first visit nudges the tab once, so it may still be moving.
  await next.click({ force: true });
  await expect(list).toHaveAttribute('data-page', '1');
  await expect(page.getByTestId('browse-list-cue')).toHaveAttribute('data-gone', 'true');
  await expect(page.getByTestId('browse-list-hint-prev')).toBeVisible();
  // Rows have no chevron.
  await expect(page.locator('[data-testid^="browse-event-"]').first()).not.toContainText('›');
});

test('reduced motion: the host deck does not turn over', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await mockSupabase(page);
  await guestOpen(page, '/browse/music');
  const deck = page.getByTestId('browse-host-deck');
  await expect(deck).toBeVisible({ timeout: 20000 });
  const first = await deck.innerHTML();
  await page.waitForTimeout(3600);
  expect(await deck.innerHTML()).toBe(first);
});

test('the next tab nudges only on the very first visit; both tabs darken while the list is swiped', async ({ page }) => {
  await mockSupabase(page);
  await guestOpen(page, '/browse/music');
  const next = page.getByTestId('browse-list-hint-next');
  await expect(next).toBeVisible({ timeout: 20000 });
  await expect(next).toHaveAttribute('data-nudge', 'true');
  expect(await page.evaluate(() => localStorage.getItem('banbe.v23.pagerNudgeSeen'))).toBe('1');
  // Swiping the track: the tabs' wrapper flags the swipe (darker tabs), then settles back.
  const wrap = page.locator('[data-swiping]').first();
  await page.getByTestId('browse-list-track').evaluate((el) => { el.scrollLeft = 80; el.dispatchEvent(new Event('scroll')); });
  await expect(wrap).toHaveAttribute('data-swiping', '1');
  await expect(wrap).toHaveAttribute('data-swiping', '0', { timeout: 2000 });
  // A later visit: no nudge.
  await page.reload();
  await expect(page.getByTestId('browse-list-hint-next')).toBeVisible({ timeout: 20000 });
  await expect(page.getByTestId('browse-list-hint-next')).toHaveAttribute('data-nudge', 'false');
});

test('end and empty cards use the v2.3 paper card (dashed edge, serif line)', async ({ page }) => {
  await mockSupabase(page);
  await guestOpen(page, '/browse/music');
  await expect(page.getByTestId('browse-screen')).toBeVisible({ timeout: 20000 });
  await page.getByTestId('browse-search').click();
  const input = page.getByTestId('browse-search-input');
  if (await input.isVisible().catch(() => false)) {
    await input.fill('zzzz no such event');
    const card = page.getByTestId('list-end-card');
    await expect(card).toBeVisible();
    expect(await card.evaluate(el => getComputedStyle(el).borderTopStyle)).toBe('dashed');
    await expect(page.getByTestId('browse-empty-clear')).toBeVisible();
  }
});

test('closing an event flies the cover back over the list it came from, without replaying the list', async ({ page }) => {
  await mockSupabase(page);
  await guestOpen(page, '/browse/music');
  const row = page.locator('[data-testid^="browse-event-"]').first();
  await expect(row).toBeVisible({ timeout: 20000 });
  await page.waitForTimeout(900);
  await row.click();
  await expect(page.getByTestId('event-detail-back')).toBeVisible({ timeout: 15000 });
  await page.waitForTimeout(900);
  await page.getByTestId('event-detail-back').click();
  // The overlay exists while the list is already back underneath it.
  await expect(page.getByTestId('zoom-return-fly')).toHaveCount(1);
  await expect(page).toHaveURL(/\/browse\/music$/);
  expect(await page.evaluate(() => document.documentElement.dataset.zoomReturn)).toBe('1');
  await expect(page.getByTestId('zoom-return-fly')).toHaveCount(0, { timeout: 3000 });
  // The list stays put (no late push-in once the cover has landed).
  const box = await page.locator('[data-testid^="browse-event-"]').first().boundingBox();
  expect(Math.round(box.x)).toBe(0);
});

test('font choice: Serif or Be Vietnam Pro, each one typeface for titles AND text; an old stored choice reads as Be Vietnam Pro', async ({ page }) => {
  await mockSupabase(page);
  for (const [stored, font, re] of [['serif', 'serif', /Iowan|Palatino|Georgia/], ['vietnam', 'vietnam', /Be Vietnam Pro/], ['current', 'vietnam', /Be Vietnam Pro/]]) {
    await page.addInitScript((f) => { try { localStorage.setItem('banbe.font.v1', f); } catch { /* */ } }, stored);
    await guestOpen(page, '/browse/music');
    await expect(page.getByTestId('browse-screen')).toBeVisible({ timeout: 20000 });
    expect(await page.evaluate(() => document.documentElement.dataset.bbFont)).toBe(font);
    const [title, text] = await page.evaluate(() => {
      const row = document.querySelector('[data-testid^="browse-event-"]');
      return [getComputedStyle(row.querySelector('span:nth-child(2)')).fontFamily, getComputedStyle(document.body).fontFamily];
    });
    expect(title, `${stored} title`).toMatch(re);
    expect(text, `${stored} text`).toMatch(re);
  }
});

// @ts-check
import { test, expect } from '@playwright/test';

// Note 81: the v2.3 Event Detail (switch home_v23): the prototype's layout (cinematic hero, ticket stub with the
// tear-off price strip, editorial sections, glass nav past 140 px), the compact/full floating reserve bar, 1·2·3·4+
// with the in-place stepper. Guest deep link, fully mocked Supabase. Optional screenshots: V23_SHOTS=<dir>.
const SHOTS = process.env.V23_SHOTS;
const SUPABASE = 'https://ukchdgdnwytretvqjjqu.supabase.co';
const json = (body, status = 200) => ({ status, contentType: 'application/json', body: JSON.stringify(body) });
const inDays = (d, h = 19) => { const t = new Date(Date.now() + d * 864e5); t.setUTCHours(h - 7, 0, 0, 0); return t.toISOString(); };
const BIG = 'e8400000-0000-4000-8000-000000000001';
const SMALL = 'e8400000-0000-4000-8000-000000000002';
const ROW = (id, name, capacity) => ({
  id, name, cat_key: 'supper', starts_at: inDays(5), price_vnd: 850000, capacity, seats_remaining: capacity, status: 'live', visibility: 'public',
  area: 'Quận 1', country_code: 'VN', state_province: 'Hồ Chí Minh', tz: 'Asia/Ho_Chi_Minh', currency: 'VND', organizer_id: 'org_v23_detail',
  description: 'A long table, five courses and strangers side by side. '.repeat(6), details: { v: 1, alcohol: 'included', min_age: '18' },
  intro: 'Host intro paragraph one.\n\nHost intro paragraph two.',
});
const EVENTS = { [BIG]: ROW(BIG, 'Big table test', 20), [SMALL]: ROW(SMALL, 'Small table test', 3) };

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
      if (fn === 'get_public_event_fill') {
        const ids = JSON.parse(r.request().postData() || '{}').p_event_ids || [];
        return r.fulfill(json(ids.filter(id => EVENTS[id]).map(id => ({ event_id: id, booked: 0, capacity: EVENTS[id].capacity }))));
      }
      return r.fulfill(json(null));
    }
    if (p.startsWith('/rest/v1/events')) {
      const id = (url.searchParams.get('id') || '').replace(/^eq\./, '');
      if (accept.includes('vnd.pgrst.object')) return r.fulfill(EVENTS[id] ? json(EVENTS[id]) : json(null, 406));
      return r.fulfill(json(id && EVENTS[id] ? [EVENTS[id]] : Object.values(EVENTS)));
    }
    if (p.startsWith('/rest/v1/')) return r.fulfill(accept.includes('vnd.pgrst.object') ? json(null, 406) : json([]));
    return r.fulfill({ status: 404, body: '' });
  });
  await page.addInitScript((f) => { try { localStorage.setItem('banbe_feature_flags_v1', JSON.stringify(f)); localStorage.setItem('banbe.guestOnboarding.v1', '1'); } catch { /* */ } }, flags);
}

/** @param {import('@playwright/test').Page} page @param {string} id */
async function openEvent(page, id) {
  await page.goto(`/event/${id}`);
  for (let i = 0; i < 40; i++) {
    if (await page.getByTestId('event-ticket-stub').isVisible().catch(() => false)) break;
    for (const t of ['lang-en', 'onboarding-continue', 'welcome-explore']) {
      if (await page.getByTestId(t).isVisible().catch(() => false)) { await page.getByTestId(t).click(); await page.waitForTimeout(300); break; }
    }
    await page.waitForTimeout(300);
  }
  await expect(page.getByTestId('event-ticket-stub')).toBeVisible({ timeout: 20000 });
}
const scrollTo = (page, y) => page.getByTestId('event-scroller').evaluate((el, v) => { el.scrollTop = v; el.dispatchEvent(new Event('scroll')); }, y);
const shot = async (page, name) => { if (SHOTS) { await page.waitForTimeout(600); await page.screenshot({ path: `${SHOTS}/${name}.png` }); } };
const ON = { simple_shell: true, home_v23: true };

test('switch off: the V8 bar and stub stay as they are', async ({ page }) => {
  await mockSupabase(page, { simple_shell: true });
  await openEvent(page, BIG);
  await expect(page.getByTestId('event-bar-v23')).toHaveCount(0);
  await expect(page.getByTestId('event-price-strip')).toHaveCount(0);
  await expect(page.getByTestId('event-qty-1')).toBeVisible();
});

test('tear-off strip; the bar opens compact, grows past 40 px and compacts again at the top', async ({ page }) => {
  await mockSupabase(page, ON);
  await openEvent(page, BIG);
  await expect(page.getByTestId('event-price-strip')).toBeVisible();
  await expect(page.getByTestId('event-stub-lip')).toBeVisible();
  const bar = page.getByTestId('event-bar-v23');
  await expect(bar).toHaveAttribute('data-compact', 'true');
  // Compact: the quantity and a plain Reserve (the total appears once the bar grows).
  await expect(page.getByTestId('event-reserve-bar')).toHaveText('Reserve');
  await expect(page.getByTestId('event-bar-total-value')).toHaveCount(0);
  await shot(page, 'd1-compact');
  await scrollTo(page, 30);
  await expect(bar).toHaveAttribute('data-compact', 'true');
  await scrollTo(page, 120);
  await expect(bar).toHaveAttribute('data-compact', 'false');
  await expect(page.getByTestId('event-bar-total-value')).toHaveText('850.000₫');
  await expect(page.getByTestId('event-bar-total-sub')).toHaveText('per ticket');
  await expect(page.getByTestId('event-trust-line')).toBeVisible();
  const h = (await page.getByTestId('event-action-area').boundingBox()).height;
  expect(h).toBeLessThanOrEqual(844 * 0.21);
  await scrollTo(page, 30);
  await expect(bar).toHaveAttribute('data-compact', 'false');
  await scrollTo(page, 0);
  await expect(bar).toHaveAttribute('data-compact', 'true');
});

test('1·2·3·4+: totals multiply, 4+ becomes a stepper with the guest dots, capped at 6, back to chips at 3', async ({ page }) => {
  await mockSupabase(page, ON);
  await openEvent(page, BIG);
  await scrollTo(page, 120);
  await page.getByTestId('event-qty-2').click();
  await expect(page.getByTestId('event-bar-total-value')).toHaveText('1.700.000₫');
  await expect(page.getByTestId('event-bar-total-sub')).toHaveText('Total · 2 × 850.000₫');
  await page.getByTestId('event-qty-more').click();
  await expect(page.getByTestId('event-qty-stepper')).toBeVisible();
  await expect(page.getByTestId('event-guest-line')).toHaveText('You + 3 guests · up to 6');
  await expect(page.getByTestId('event-guest-line').locator('[data-dot="guest"]')).toHaveCount(3);
  await page.getByTestId('event-qty-plus').click();
  await page.getByTestId('event-qty-plus').click();
  await expect(page.getByTestId('event-qty-value')).toContainText('6');
  await expect(page.getByTestId('event-qty-plus')).toBeDisabled();
  await expect(page.getByTestId('event-guest-line')).toHaveText('You + 5 guests · 6 is the most per person');
  await expect(page.getByTestId('event-bar-total-value')).toHaveText('5.100.000₫');
  await shot(page, 'd2-stepper-6');
  for (let i = 0; i < 3; i++) await page.getByTestId('event-qty-minus').click();
  await expect(page.getByTestId('event-qty-stepper')).toHaveCount(0);
  await expect(page.getByTestId('event-qty-3')).toHaveAttribute('aria-pressed', 'true');
  // Tap targets.
  for (const id of ['event-qty-1', 'event-qty-more', 'event-reserve-bar']) {
    const b = await page.getByTestId(id).boundingBox();
    expect(b.height, id).toBeGreaterThanOrEqual(44);
    expect(b.width, id).toBeGreaterThanOrEqual(44);
  }
});

test('3 seats left: 4+ stays visible but quiet, and a tap says how many are left', async ({ page }) => {
  await mockSupabase(page, ON);
  await openEvent(page, SMALL);
  const more = page.getByTestId('event-qty-more');
  await expect(more).toHaveAttribute('aria-disabled', 'true');
  await more.click({ force: true });
  await expect(page.getByTestId('event-qty-refusal')).toHaveText('Only 3 tickets left for this one');
  await expect(page.getByTestId('event-qty-stepper')).toHaveCount(0);
});

test('v2.3 layout: serif hero title, one glass Back, the nav with tabs and reading progress past 140 px', async ({ page }) => {
  await mockSupabase(page, ON);
  await openEvent(page, BIG);
  await expect(page.getByTestId('event-detail-v23')).toBeVisible();
  const h1 = page.getByTestId('event-hero-title').locator('h1');
  await expect(h1).toHaveText('Big table test');
  expect(await h1.evaluate(el => getComputedStyle(el).fontFamily)).toMatch(/Iowan|Palatino|Georgia/);
  await expect(page.getByTestId('event-detail-back')).toBeVisible();
  const nav = page.getByTestId('event-nav-bar');
  await expect(nav).toHaveAttribute('aria-hidden', 'true');
  await scrollTo(page, 100);
  await expect(nav).toHaveAttribute('aria-hidden', 'true');
  await scrollTo(page, 400);
  await expect(nav).toHaveAttribute('aria-hidden', 'false');
  await expect(page.getByTestId('event-detail-back')).toHaveClass(/hide/);
  await expect(page.getByTestId('event-tab-overview')).toBeVisible();
  const p = await page.getByTestId('event-read-progress').evaluate(el => el.style.transform);
  expect(p).toMatch(/scaleX\(0\.\d+|scaleX\(1\)/);
  await shot(page, 'v23-nav');
  await page.getByTestId('event-tab-safe').click();
  await expect(page.getByTestId('event-tab-safe')).toHaveAttribute('aria-current', 'true');
  await expect(page.getByTestId('event-protection')).toBeInViewport();
  for (const id of ['event-nav-back', 'event-detail-save', 'event-detail-share', 'event-detail-more']) {
    const b = await page.getByTestId(id).boundingBox();
    expect(b.height, id).toBeGreaterThanOrEqual(44);
  }
});

test('About has no "More ›" sheet link any more; Read more also shows the host\'s long intro', async ({ page }) => {
  await mockSupabase(page, ON);
  await openEvent(page, BIG);
  await expect(page.getByTestId('event-included-section')).toHaveCount(0);
  await expect(page.getByTestId('event-intro-section')).toHaveCount(0);
  await page.getByTestId('event-read-more').click();
  await expect(page.getByTestId('event-intro-section')).toContainText('Host intro paragraph one.');
  await expect(page.getByTestId('event-intro-section')).toContainText('Host intro paragraph two.');
  await expect(page.getByTestId('event-read-more')).toHaveAttribute('aria-expanded', 'true');
});

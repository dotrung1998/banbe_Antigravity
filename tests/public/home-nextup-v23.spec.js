// @ts-check
import { test, expect } from '@playwright/test';

// Note 81: the v2.3 Home "Next up" ticket cards (one per event, soonest first, people across bookings, the button
// that event needs). Fully mocked Supabase; the signed-in viewer and their bookings come from the dev state setter.
const SUPABASE = 'https://ukchdgdnwytretvqjjqu.supabase.co';
const json = (body, status = 200) => ({ status, contentType: 'application/json', body: JSON.stringify(body) });
const inDays = (d, h = 19) => { const t = new Date(Date.now() + d * 864e5); t.setUTCHours(h - 7, 0, 0, 0); return t.toISOString(); };
const day = (iso) => iso.slice(0, 10);
const A = 'e8500000-0000-4000-8000-0000000000a1';
const B = 'e8500000-0000-4000-8000-0000000000b2';
const row = (id, name, d) => ({ id, slug: id, name, cat_key: 'supper', cat_label: 'Supper club', starts_at: inDays(d), event_date: day(inDays(d)), event_time: '19:00:00', end_time: '22:30:00', end_open: false,
  price_vnd: 500000, capacity: 20, seats_remaining: 20, status: 'live', visibility: 'public', area: 'Quận 3', lat: 10.78, lng: 106.69, country_code: 'VN', state_province: 'Hồ Chí Minh', tz: 'Asia/Ho_Chi_Minh', currency: 'VND' });
const EVENTS = [row(A, 'Soon table', 3), row(B, 'Later table', 9)];
const USER = { id: '00000000-0000-4000-8000-0000000000e9', name: 'Trung', email: 't@example.com' };
const mins = (m) => new Date(Date.now() + m * 60000).toISOString();
const BOOKINGS = [
  { id: 'nb1', event_id: B, qty: 2, status: 'confirmed', payment_state: 'confirmed', created_at: mins(-500), events: { id: B, event_date: EVENTS[1].event_date, event_time: '19:00:00' } },
  { id: 'nb2', event_id: A, qty: 1, status: 'confirmed', payment_state: 'confirmed', created_at: mins(-600), events: { id: A, event_date: EVENTS[0].event_date, event_time: '19:00:00' } },
  { id: 'nb3', event_id: A, qty: 2, status: 'pending', payment_state: 'holding', hold_expires_at: mins(20), created_at: mins(-5), events: { id: A, event_date: EVENTS[0].event_date, event_time: '19:00:00' } },
];
const FLAGS = { simple_shell: true, home_v23: true };

test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] }, timezoneId: 'Asia/Ho_Chi_Minh' });

test('one ticket card per event, soonest first, people across bookings, the button each event needs', async ({ page }) => {
  await page.route(`${SUPABASE}/**`, async (r) => {
    const url = new URL(r.request().url());
    const p = url.pathname;
    const one = (r.request().headers().accept || '').includes('vnd.pgrst.object');
    if (p.startsWith('/auth/v1/')) return r.fulfill({ status: 204, body: '' });
    if (p.startsWith('/rest/v1/rpc/')) return r.fulfill(json(p.endsWith('get_feature_flags') ? FLAGS : null));
    if (p.startsWith('/rest/v1/events')) return r.fulfill(one ? json(EVENTS[0]) : json(EVENTS));
    if (p.startsWith('/rest/v1/bookings')) return r.fulfill(one ? json(null, 406) : json(BOOKINGS));
    if (p.startsWith('/rest/v1/')) return r.fulfill(one ? json(null, 406) : json([]));
    return r.fulfill({ status: 404, body: '' });
  });
  await page.addInitScript((f) => { try { localStorage.setItem('banbe_feature_flags_v1', JSON.stringify(f)); localStorage.setItem('banbe.guestOnboarding.v1', '1'); } catch { /* */ } }, FLAGS);
  await page.goto('/');
  for (let i = 0; i < 40; i++) {
    if (await page.getByTestId('home-shortlist').isVisible().catch(() => false)) break;
    for (const t of ['lang-en', 'onboarding-continue', 'welcome-explore']) {
      if (await page.getByTestId(t).isVisible().catch(() => false)) { await page.getByTestId(t).click(); await page.waitForTimeout(300); break; }
    }
    await page.waitForTimeout(300);
  }
  await page.evaluate(([u, b]) => window.__banbeDevSet({ user: u, accountType: 'participant', lang: 'en', paymentBookings: b }), [USER, BOOKINGS]);
  const nu = page.getByTestId('home-nextup');
  await expect(nu).toBeVisible({ timeout: 15000 });
  await expect(nu).toHaveAttribute('data-count', '2');
  const cards = page.locator('[data-testid^="home-nextup-card-"]');
  await expect(cards.first()).toHaveAttribute('data-testid', `home-nextup-card-${A}`);
  await expect(cards.first()).toHaveAttribute('data-state', 'pay');
  const first = cards.first();
  await expect(first.getByTestId('home-nextup-people')).toHaveText('3 people');
  await expect(first).toContainText('2 bookings');
  await expect(first.getByTestId('home-nextup-status')).toContainText('1 ready');
  await expect(first).toContainText('2 waiting');
  await expect(first.getByTestId('home-nextup-starts')).toHaveText('19:00');
  await expect(first).toContainText('to 22:30');
  await expect(first.getByTestId('home-nextup-chip')).toHaveText('In 3 days');
  await expect(first.getByTestId('home-nextup-primary')).toHaveText('Pay now');
  await expect(first.getByTestId('home-nextup-directions')).toBeVisible();
  await expect(page.getByTestId('home-nextup-count')).toHaveText('1 of 2');
  await page.locator('[data-testid="home-nextup"] [role="tab"]').nth(1).click();
  await expect(page.getByTestId('home-nextup-count')).toHaveText('2 of 2');
  const second = cards.nth(1);
  await expect(second).toHaveAttribute('data-state', 'ready');
  await expect(second.getByTestId('home-nextup-primary')).toHaveText('Show ticket');
  for (const id of ['home-nextup-primary', 'home-nextup-schedule']) {
    expect((await first.getByTestId(id).or(page.getByTestId(id)).first().boundingBox()).height).toBeGreaterThanOrEqual(44);
  }
});

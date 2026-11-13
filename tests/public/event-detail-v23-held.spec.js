// @ts-check
import { test, expect } from '@playwright/test';

// Note 81, phase e: the v2.3 stub stamps (Held · time left in honey, Confirmed in moss) from the viewer's real bookings,
// and adding tickets after a hold as a SECOND booking (Reserve in "add tickets" mode), capped at 6 per person across
// bookings. Fully mocked Supabase; the signed-in viewer comes from the dev-only state setter, the bookings from the mock.
const SHOTS = process.env.V23_SHOTS;
const SUPABASE = 'https://ukchdgdnwytretvqjjqu.supabase.co';
const json = (body, status = 200) => ({ status, contentType: 'application/json', body: JSON.stringify(body) });
const inDays = (d, h = 19) => { const t = new Date(Date.now() + d * 864e5); t.setUTCHours(h - 7, 0, 0, 0); return t.toISOString(); };
const inMin = (m) => new Date(Date.now() + m * 60000).toISOString();
const ID = 'e8400000-0000-4000-8000-0000000000e1';
const EV = {
  id: ID, slug: ID, name: 'Held table test', cat_key: 'supper', starts_at: inDays(5), price_vnd: 850000, capacity: 20, seats_remaining: 20, status: 'live', visibility: 'public',
  area: 'Quận 1', country_code: 'VN', state_province: 'Hồ Chí Minh', tz: 'Asia/Ho_Chi_Minh', currency: 'VND', organizer_id: 'org_v23_held',
  description: 'A long table, five courses and strangers side by side. '.repeat(6), details: { v: 1, alcohol: 'included', min_age: '18' },
};
const USER = { id: '00000000-0000-4000-8000-0000000000e1', name: 'Trung', email: 't@example.com', handle: 'trungtest' };
const booking = (o) => ({ id: 'b-e1', event_id: ID, user_id: USER.id, qty: 2, status: 'pending', payment_state: 'holding', hold_expires_at: inMin(25), code: 'E1E1E1', created_at: new Date().toISOString(), ...o });

test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

/** @param {import('@playwright/test').Page} page @param {{ rows: any[] }} db */
async function mock(page, db) {
  const flags = { simple_shell: true, home_v23: true };
  await page.route(`${SUPABASE}/**`, async (r) => {
    const url = new URL(r.request().url());
    const p = url.pathname;
    const accept = r.request().headers().accept || '';
    const one = accept.includes('vnd.pgrst.object');
    if (p.startsWith('/auth/v1/')) return r.fulfill({ status: 204, body: '' });
    if (p.startsWith('/rest/v1/rpc/')) {
      const fn = p.split('/').pop();
      if (fn === 'get_feature_flags') return r.fulfill(json(flags));
      if (fn === 'get_public_event_fill') return r.fulfill(json([{ event_id: ID, booked: db.rows.reduce((n, b) => n + b.qty, 0), capacity: 20 }]));
      return r.fulfill(json(null));
    }
    if (p.startsWith('/rest/v1/events')) return r.fulfill(one ? json(EV) : json([EV]));
    if (p.startsWith('/rest/v1/bookings')) return r.fulfill(one ? (db.rows[0] ? json(db.rows[0]) : json(null, 406)) : json(db.rows));
    if (p.startsWith('/rest/v1/')) return r.fulfill(one ? json(null, 406) : json([]));
    return r.fulfill({ status: 404, body: '' });
  });
  await page.addInitScript((f) => { try { localStorage.setItem('banbe_feature_flags_v1', JSON.stringify(f)); localStorage.setItem('banbe.guestOnboarding.v1', '1'); } catch { /* */ } }, flags);
}
const devSet = (page, patch) => page.evaluate((x) => window.__banbeDevSet(x), patch);

/** Opens the event as a guest, then signs the viewer in through the dev setter (the app then loads their bookings). */
async function openSignedIn(page) {
  await page.goto(`/event/${ID}`);
  for (let i = 0; i < 40; i++) {
    if (await page.getByTestId('event-ticket-stub').isVisible().catch(() => false)) break;
    for (const t of ['lang-en', 'onboarding-continue', 'welcome-explore']) {
      if (await page.getByTestId(t).isVisible().catch(() => false)) { await page.getByTestId(t).click(); await page.waitForTimeout(300); break; }
    }
    await page.waitForTimeout(300);
  }
  await expect(page.getByTestId('event-ticket-stub')).toBeVisible({ timeout: 20000 });
  const fetched = page.waitForResponse(r => r.url().includes('/rest/v1/bookings'), { timeout: 8000 }).catch(() => null);
  await devSet(page, { user: USER, accountType: 'participant', lang: 'en' });
  await fetched;
  await page.waitForTimeout(400);
}
const shot = async (page, name) => { if (SHOTS) { await page.waitForTimeout(700); await page.screenshot({ path: `${SHOTS}/${name}.png` }); } };
const scrollTo = (page, y) => page.getByTestId('event-scroller').evaluate((el, v) => { el.scrollTop = v; el.dispatchEvent(new Event('scroll')); }, y);

test('held: honey stamp with the time left, the stub shows what you hold, the bar opens the booking', async ({ page }) => {
  const db = { rows: [booking({})] };
  await mock(page, db);
  await openSignedIn(page);
  const stamp = page.getByTestId('event-stub-stamp');
  await expect(stamp).toHaveAttribute('data-kind', 'held');
  await expect(stamp).toHaveText(/^Held · (2[0-5]) min$/);
  await expect(page.getByTestId('event-seat-status')).toHaveCount(0);
  await expect(page.getByTestId('event-price')).toContainText('1.700.000₫');
  await expect(page.getByTestId('event-price')).toContainText('· 2 tickets');
  const btn = page.getByTestId('event-reserve-bar');
  await expect(btn).toHaveAttribute('data-state', 'held');
  await expect(btn).toHaveText('Seats held');
  await expect(page.getByTestId('event-qty-1')).toBeDisabled();
  await shot(page, 'e1-held');
});

test('add tickets: above what you hold the bar says +X · N more · M in all, and Add opens Reserve for the new names', async ({ page }) => {
  const db = { rows: [booking({})] };
  await mock(page, db);
  await openSignedIn(page);
  await scrollTo(page, 160);
  await page.getByTestId('event-qty-3').click();
  const btn = page.getByTestId('event-reserve-bar');
  await expect(btn).toHaveAttribute('data-state', 'adding');
  await expect(btn).toHaveText('Add 1 ticket');
  await expect(page.getByTestId('event-bar-total-value')).toHaveText('+850.000₫');
  await expect(page.getByTestId('event-bar-total-sub')).toHaveText('1 more · 3 in all');
  await expect(page.getByTestId('event-trust-line')).toContainText('new booking');
  await shot(page, 'e2-adding');
  await btn.click();
  await expect(page.getByTestId('reserve-adding-note')).toContainText('You already hold 2');
  await expect(page.getByTestId('reserve-attendee-0')).toBeVisible();
  await expect(page.getByTestId('reserve-attendee-1')).toHaveCount(0);
  // No ticket here is the buyer's own: a date picker and an optional email on ticket 1.
  await expect(page.getByTestId('reserve-attendee-0-dob')).toBeVisible();
  await expect(page.getByTestId('reserve-attendee-0-email')).toBeVisible();
  await expect(page.getByTestId('reserve-attendee-0-name')).toHaveValue('');
  await expect(page.getByTestId('reserve-submit')).toContainText('Hold 1 more seat');
  await shot(page, 'e3-reserve-adding');
});

test('6 per person counts what you hold: holding 5, the stepper stops at 6 and says why', async ({ page }) => {
  const db = { rows: [booking({ qty: 3 }), booking({ id: 'b-e2', qty: 2, payment_state: 'pending_verification', verify_due_at: inMin(50) })] };
  await mock(page, db);
  await openSignedIn(page);
  await scrollTo(page, 160);
  await expect(page.getByTestId('event-qty-stepper')).toBeVisible();
  await expect(page.getByTestId('event-qty-minus')).toBeDisabled();
  await page.getByTestId('event-qty-plus').click();
  await expect(page.getByTestId('event-qty-plus')).toBeDisabled();
  await expect(page.getByTestId('event-guest-line')).toHaveText('5 held · adding 1 · 6 is the most per person');
  await expect(page.getByTestId('event-reserve-bar')).toHaveText('Add 1 ticket');
});

test('confirmed: the stamp turns moss and slams in on the change; the bar opens the ticket', async ({ page }) => {
  const db = { rows: [booking({})] };
  await mock(page, db);
  await openSignedIn(page);
  await expect(page.getByTestId('event-stub-stamp')).toHaveAttribute('data-kind', 'held');
  // The host confirms (what the next booking refresh brings).
  const confirmedRow = booking({ status: 'confirmed', payment_state: 'confirmed', hold_expires_at: null });
  db.rows = [confirmedRow];
  await devSet(page, { booking: confirmedRow, myEventBookings: [confirmedRow] });
  const stamp = page.getByTestId('event-stub-stamp');
  await expect(stamp).toHaveAttribute('data-kind', 'confirmed');
  await expect(stamp).toHaveText('Confirmed');
  expect(await stamp.evaluate(el => el.getAnimations().length)).toBeGreaterThan(0);
  const btn = page.getByTestId('event-reserve-bar');
  await expect(btn).toHaveAttribute('data-state', 'ticket');
  await expect(btn).toHaveText('View your ticket');
  await shot(page, 'e4-confirmed');
});

test('nothing held: no stamp, the seat pill and the plain Reserve', async ({ page }) => {
  const db = { rows: [booking({ status: 'cancelled' })] };
  await mock(page, db);
  await openSignedIn(page);
  await expect(page.getByTestId('event-stub-stamp')).toHaveCount(0);
  await expect(page.getByTestId('event-seat-status')).toBeVisible();
  await expect(page.getByTestId('event-reserve-bar')).toHaveAttribute('data-state', 'reserve');
});

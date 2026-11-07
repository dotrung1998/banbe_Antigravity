// @ts-check
import { test, expect as baseExpect } from '@playwright/test';
import { guestToHome } from './helpers.js';
import { EVENTS } from '../src/data/events.js';

// These tests run against the real backend and in parallel; a slow machine should not turn a 5s wait into a failure.
const expect = baseExpect.configure({ timeout: 10_000 });

// Note 78 (steps 4+): the paper ticket, the What's next strip and the QR modes on the Confirmed screen. No earlier spec
// renders this screen (a booking's event_id must match a hardcoded demo key, see dispute-flow-e2e.spec.js), so it is
// rendered from the dev-only state setter, like note69-web-parity.spec.js. The clock is pinned so "today" and "N days"
// do not depend on when the suite runs (Vietnam noon, 2026-11-05).
test.use({ storageState: { cookies: [], origins: [] }, viewport: { width: 390, height: 844 } });

const NOW = new Date('2026-11-05T05:00:00Z');
const H = 3600000;
const devSet = (page, patch) => page.evaluate((p) => window.__banbeDevSet(p), patch);
const USER = { id: '00000000-0000-4000-8000-000000000078', name: 'Trung', email: 't@example.com', handle: 'trungtest' };
const iso = (ms) => new Date(NOW.getTime() + ms).toISOString();

/** state patch for one case: [paymentState, bookingStatus, eventStatus|null, startsInMs, extra booking fields] */
const CASES = {
  upcoming: { pay: 'confirmed', status: 'confirmed', ev: 'live', start: 72 * H },
  today: { pay: 'confirmed', status: 'confirmed', ev: 'live', start: 2 * H },
  checkedIn: { pay: 'confirmed', status: 'attended', ev: 'live', start: 1 * H },
  holding: { pay: 'holding', status: 'pending', ev: 'live', start: 72 * H, booking: { hold_expires_at: iso(20 * 60000) } },
  awaiting: { pay: 'pending_verification', status: 'pending', ev: 'live', start: 72 * H, booking: { verify_due_at: iso(H) } },
  review: { pay: 'disputed', status: 'confirmed', ev: 'live', start: 72 * H },
  expired: { pay: 'expired', status: 'expired', ev: 'live', start: 72 * H },
  ended: { pay: 'confirmed', status: 'confirmed', ev: 'ended', start: -13 * H },
  cancelled: { pay: 'confirmed', status: 'confirmed', ev: 'cancelled', start: 72 * H },
  bookingCancelled: { pay: 'cancelled', status: 'cancelled', ev: 'live', start: 72 * H },
};
const KEY_OF = { bookingCancelled: 'cancelled' };
const LIVE_QR = ['upcoming', 'today', 'checkedIn'];

const ready = new WeakSet();
async function openTicket(page, name, extra = {}) {
  const c = CASES[name];
  if (!ready.has(page)) {
    // Pins Date only; install() would also fake requestAnimationFrame, which Playwright's stable-element check needs.
    await page.clock.setFixedTime(NOW);
    await guestToHome(page);
    // Setting the event key makes the app fetch that event's real row and the user's booking. Let both land first,
    // otherwise they overwrite the state injected below a moment later.
    // Two fetches race each other (the user's booking, and the event's own status row), so wait for both.
    const bookingFetched = page.waitForResponse((r) => /\/rest\/v1\/bookings\?/.test(r.url()) && r.url().includes('event_id=eq.'), { timeout: 8000 }).catch(() => null);
    const eventFetched = page.waitForResponse((r) => r.url().includes('/rest/v1/events') && r.url().includes('slug=eq.bepnho') && r.url().includes('starts_at'), { timeout: 8000 }).catch(() => null);
    await devSet(page, { user: USER, accountType: 'participant', eventKey: 'bepnho' });
    await Promise.all([bookingFetched, eventFetched]);
    await page.waitForTimeout(500);
    ready.add(page);
  }
  await devSet(page, {
    lang: 'en',
    liveEvent: { status: c.ev, starts_at: iso(c.start), tz: 'Asia/Ho_Chi_Minh' },
    booking: { id: 'b-78', event_id: 'bepnho', status: c.status, payment_state: c.pay, qty: 1, code: '1B159C', admission_token: 'tok-78-real-admission', ...c.booking },
    bookingAttendees: [], screen: 'confirmed', confirmedBack: 'home', ...extra,
  });
  await expect(page.locator('[data-screen-label="Confirmed"]')).toBeVisible();
}

for (const name of Object.keys(CASES)) {
  test(`${name}: strip case, QR mode and entry code`, async ({ page }) => {
    await openTicket(page, name);
    await expect(page.getByTestId('confirmed-strip')).toHaveAttribute('data-case', KEY_OF[name] || name);
    const live = LIVE_QR.includes(name);
    // The real admission token is only ever drawn for a live ticket; everything else is a placeholder.
    await expect(page.getByTestId('ticket-qr-real')).toHaveCount(live ? 1 : 0);
    await expect(page.getByTestId('ticket-qr-placeholder')).toHaveCount(live ? 0 : 1);
    await expect(page.getByTestId('confirmed-entry-code')).toHaveText(live ? '1B1 59C' : '••• •••');
    if (!live) await expect(page.getByTestId('ticket-qr-label')).toBeVisible();
  });
}

test('holding and awaiting keep payment one tap away, with their own clocks; cancelled and expired do not', async ({ page }) => {
  await openTicket(page, 'holding');
  await expect(page.getByTestId('confirmed-pay')).toBeVisible();
  await expect(page.getByTestId('confirmed-hold-countdown')).toHaveText(/\d{2}:\d{2}/);
  await openTicket(page, 'awaiting');
  await expect(page.getByTestId('confirmed-pay')).toBeVisible();
  await expect(page.getByTestId('confirmed-verify-countdown')).toHaveText(/\d/);
  for (const name of ['bookingCancelled', 'cancelled', 'expired', 'review']) {
    await openTicket(page, name);
    await expect(page.getByTestId('confirmed-pay')).toHaveCount(0);
  }
});

test('there is no celebration card above the ticket, live or not', async ({ page }) => {
  for (const name of ['upcoming', 'checkedIn', 'cancelled', 'ended']) {
    await openTicket(page, name);
    await expect(page.getByTestId('confirmed-ticket-reveal')).toHaveCount(0);
    await expect(page.getByTestId('confirmed-checkin-moment')).toHaveCount(0);
  }
});

test('Message host from the strip opens the chat, and its Back returns to the same ticket', async ({ page }) => {
  await openTicket(page, 'awaiting');
  await page.getByTestId('confirmed-strip-toggle').click();
  await page.getByTestId('confirmed-strip-link').click();
  await expect(page.getByTestId('chat-back')).toContainText('Ticket');
  await page.getByTestId('chat-back').click();
  await expect(page.locator('[data-screen-label="Confirmed"]')).toBeVisible();
  await expect(page.getByTestId('confirmed-strip')).toHaveAttribute('data-case', 'awaiting');
});

test('a cancelled booking is no longer "Awaiting payment"', async ({ page }) => {
  await openTicket(page, 'bookingCancelled');
  await expect(page.getByTestId('confirmed-strip-heading')).toHaveText('This booking was cancelled');
  await expect(page.getByTestId('confirmed-status')).toHaveText('Cancelled');
});

test('the strip expands and collapses, and says only what the data holds', async ({ page }) => {
  await openTicket(page, 'upcoming');
  const toggle = page.getByTestId('confirmed-strip-toggle');
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  await expect(page.getByTestId('confirmed-strip-heading')).toHaveText('3 days to go');
  await expect(page.getByTestId('confirmed-strip-detail')).toBeHidden();
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  await expect(page.getByTestId('confirmed-strip-detail')).toContainText('Your ticket is ready');
  await expect(page.getByTestId('confirmed-strip-link')).toContainText('Add to calendar');
  await toggle.click();
  await expect(page.getByTestId('confirmed-strip-detail')).toBeHidden();
  // checked in has nothing to expand: no button at all
  await openTicket(page, 'checkedIn');
  await expect(page.getByTestId('confirmed-strip-toggle')).toHaveCount(0);
  await expect(page.getByTestId('confirmed-strip-heading')).toHaveText("You're in");
});

test('the strip link runs the existing action (Reserve again after an expired hold)', async ({ page }) => {
  await openTicket(page, 'expired');
  await page.getByTestId('confirmed-strip-toggle').click();
  await expect(page.getByTestId('confirmed-strip-detail')).toContainText('released back');
  await page.getByTestId('confirmed-strip-link').click();
  await expect(page.locator('[data-screen-label="Confirmed"]')).toHaveCount(0);
});

test('the ticket shows the event name and Date, Time and Area tiles', async ({ page }) => {
  await openTicket(page, 'upcoming');
  await expect(page.getByTestId('confirmed-ticket-title')).toContainText('Bếp Nhỏ');
  await expect(page.getByTestId('confirmed-tile-date')).toContainText('Sun 8 Nov');
  await expect(page.getByTestId('confirmed-tile-time')).toContainText('12:00');
  await expect(page.getByTestId('confirmed-tile-area')).toContainText('Bình Thạnh');
  await expect(page.getByTestId('confirmed-tile-area')).not.toContainText('km');
});

test('the policy paragraph is collapsed by default and unchanged when opened', async ({ page }) => {
  await openTicket(page, 'upcoming');
  await expect(page.getByTestId('confirmed-policy-text')).toHaveCount(0);
  await page.getByTestId('confirmed-policy-toggle').click();
  await expect(page.getByTestId('confirmed-policy-text')).toHaveText('banbe does not collect money. Pay the organizer directly using the instructions in chat. If they cancel, they are responsible for your refund.');
  // the screen stays mounted across a language switch, so it is still open and now reads in Vietnamese
  await openTicket(page, 'upcoming', { lang: 'vi' });
  await expect(page.getByTestId('confirmed-policy-text')).toHaveText('banbe không thu tiền. Hãy chuyển khoản trực tiếp cho người tổ chức theo hướng dẫn trong tin nhắn. Nếu họ hủy, họ có trách nhiệm hoàn tiền cho bạn.');
  // an expired hold keeps hiding it, as before
  await openTicket(page, 'expired');
  await expect(page.getByTestId('confirmed-policy-toggle')).toHaveCount(0);
});

test('existing action ids still resolve', async ({ page }) => {
  await openTicket(page, 'upcoming');
  await expect(page.getByTestId('confirmed-add-to-calendar')).toBeVisible();
  await expect(page.getByTestId('confirmed-more-button')).toBeVisible();
  await expect(page.getByTestId('confirmed-back')).toBeVisible();
});

for (const [name, viewport] of [['upcoming', { width: 320, height: 640 }], ['awaiting', { width: 320, height: 640 }], ['cancelled', { width: 320, height: 640 }]]) {
  test(`${name} in Vietnamese at 320px: no sideways scroll, dark theme too`, async ({ page }) => {
    await page.setViewportSize(viewport);
    for (const theme of ['light', 'dark']) {
      await openTicket(page, name, { lang: 'vi', theme });
      const over = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
      expect(over, `${name} ${theme}`).toBeLessThanOrEqual(0);
      await expect(page.getByTestId('confirmed-strip-heading')).toBeVisible();
    }
  });
}

test('reduced motion: the strip opens without a height animation', async ({ page }) => {
  await openTicket(page, 'upcoming');
  // applied after the helper's onboarding walk (which stalls under reduced motion); a state patch re-renders the screen
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await devSet(page, { screen: 'confirmed' });
  await page.getByTestId('confirmed-strip-toggle').click();
  const t = await page.getByTestId('confirmed-strip-panel').evaluate((el) => getComputedStyle(el).transitionDuration);
  expect(t).toBe('0s');
});

// ---- Step 5: one stub per attendee, paged sideways, torn off on a live check-in ------------------------------------
const att = (n, checkedAt = null) => ({ id: `a-${n}`, booking_id: 'b-78', seat_no: n, name: ['Linh', 'Minh', 'An'][n - 1], ticket_code: `1B159${n}`, admission_token: `tok-a${n}`, date_of_birth: null, checked_in_at: checkedAt });
const store = { list: [] };
const inflight = new WeakMap(); // page -> number of booking_attendees requests still on their way
async function mockAttendees(page, list) {
  store.list = list;
  if (!inflight.has(page)) {
    let n = 0;
    const isIt = (r) => r.url().includes('/rest/v1/booking_attendees') && r.method() !== 'OPTIONS';
    page.on('request', (r) => { if (isIt(r)) n++; });
    page.on('requestfinished', (r) => { if (isIt(r)) n--; });
    page.on('requestfailed', (r) => { if (isIt(r)) n--; });
    inflight.set(page, () => n);
  }
  // The screen refetches attendees on open; answer with the test's own list so it is never overwritten.
  await page.route('**/rest/v1/booking_attendees*', (route) => {
    const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' };
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors });
    return route.fulfill({ status: 200, contentType: 'application/json', headers: cors, body: JSON.stringify(store.list) });
  });
}
// The screen fetches attendees when it opens. A slow answer must land BEFORE a simulated scan, or it would restore the
// old, unscanned list over it (the real app has the same ordering; only the test controls when the scan happens).
const attendeesSettled = async (page) => {
  await expect.poll(() => inflight.get(page)()).toBe(0);
  await page.waitForTimeout(200);
};
const flip = async (page, n) => {
  await attendeesSettled(page);
  store.list = store.list.map((a) => (a.seat_no === n ? { ...a, checked_in_at: iso(0) } : a));
  return devSet(page, { bookingAttendees: store.list });
};
const activeDot = (page) => page.locator('[data-testid^="confirmed-stub-dot-"][aria-current="true"]');

test.describe('named tickets: stub pager', () => {
  test('one stub per attendee with dots, a counter and keyboard paging', async ({ page }) => {
    await mockAttendees(page, [att(1), att(2), att(3)]);
    await openTicket(page, 'upcoming', { bookingAttendees: store.list });
    await expect(page.getByTestId('confirmed-stub-pager')).toHaveAttribute('aria-roledescription', 'carousel');
    await expect(page.locator('[data-testid^="confirmed-stub-dot-"]')).toHaveCount(3);
    await expect(page.getByTestId('confirmed-stub-name-1')).toHaveText('Linh');
    await expect(page.getByTestId('ticket-qr-real')).toHaveCount(3);
    await expect(activeDot(page)).toHaveAttribute('data-testid', 'confirmed-stub-dot-1');
    await page.getByTestId('confirmed-stub-pager').focus();
    await page.keyboard.press('ArrowRight');
    await expect(activeDot(page)).toHaveAttribute('data-testid', 'confirmed-stub-dot-2');
    await page.getByTestId('confirmed-stub-dot-3').click();
    await expect(activeDot(page)).toHaveAttribute('data-testid', 'confirmed-stub-dot-3');
  });

  test('a scan while the screen is open tears that stub off and moves on to the next one', async ({ page }) => {
    await mockAttendees(page, [att(1), att(2), att(3)]);
    await openTicket(page, 'upcoming', { bookingAttendees: store.list });
    await expect(page.getByTestId('confirmed-stub-1')).toHaveAttribute('data-torn', 'false');
    // The tear lasts under half a second, so record that it happened instead of racing the window.
    await page.evaluate(() => {
      window.__tore = false;
      new MutationObserver(() => { if (document.querySelector('[data-testid="confirmed-stub-1"]')?.getAttribute('data-tearing') === 'true') window.__tore = true; })
        .observe(document.body, { attributes: true, subtree: true, attributeFilter: ['data-tearing'] });
    });
    await flip(page, 1);
    await expect.poll(() => page.evaluate(() => window.__tore)).toBe(true);
    await expect(page.getByTestId('confirmed-stub-1')).toHaveAttribute('data-torn', 'true');
    await expect(page.getByTestId('confirmed-stub-badge-1')).toContainText('Checked in');
    // the torn stub stays (dimmed, never removed) and the pager has moved to the next ticket still to be scanned
    await expect(page.getByTestId('confirmed-stub-1')).toBeAttached();
    await expect(activeDot(page)).toHaveAttribute('data-testid', 'confirmed-stub-dot-2', { timeout: 8000 });
    await expect(page.getByTestId('confirmed-stub-1')).toHaveAttribute('data-tearing', 'false');
    // scanning the last one that is still open does not jump anywhere (nothing left to advance to except already torn)
    await flip(page, 2);
    await expect(activeDot(page)).toHaveAttribute('data-testid', 'confirmed-stub-dot-3', { timeout: 8000 });
  });

  test('nothing replays on load: an already scanned stub just renders torn and the pager stays put', async ({ page }) => {
    await mockAttendees(page, [att(1, iso(-H)), att(2), att(3)]);
    await openTicket(page, 'upcoming', { bookingAttendees: store.list });
    await expect(page.getByTestId('confirmed-stub-1')).toHaveAttribute('data-torn', 'true');
    await page.waitForTimeout(1200);
    await expect(page.getByTestId('confirmed-stub-1')).toHaveAttribute('data-tearing', 'false');
    await expect(activeDot(page)).toHaveAttribute('data-testid', 'confirmed-stub-dot-1');
  });

  test('reduced motion: no tilt or animation, the move is instant', async ({ page }) => {
    await mockAttendees(page, [att(1), att(2)]);
    await openTicket(page, 'upcoming', { bookingAttendees: store.list });
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await devSet(page, { screen: 'confirmed' });
    await flip(page, 1);
    await expect(page.getByTestId('confirmed-stub-1')).toHaveAttribute('data-torn', 'true');
    await expect(page.getByTestId('confirmed-stub-1')).toHaveAttribute('data-tearing', 'false');
    const css = await page.getByTestId('confirmed-stub-1').evaluate((el) => ({ a: getComputedStyle(el).animationName, t: getComputedStyle(el).transform }));
    expect(css).toEqual({ a: 'none', t: 'none' });
    await expect(activeDot(page)).toHaveAttribute('data-testid', 'confirmed-stub-dot-2', { timeout: 8000 });
  });

  test('a cancelled or ended event draws no real QR on any stub and never tears', async ({ page }) => {
    await mockAttendees(page, [att(1), att(2)]);
    for (const name of ['cancelled', 'ended']) {
      await openTicket(page, name, { bookingAttendees: store.list });
      await expect(page.getByTestId('ticket-qr-real')).toHaveCount(0);
      await expect(page.getByTestId('ticket-qr-placeholder')).toHaveCount(2);
      await flip(page, 1);
      await expect(page.getByTestId('confirmed-stub-1')).toHaveAttribute('data-torn', 'false');
      store.list = store.list.map((a) => ({ ...a, checked_in_at: null }));
    }
  });

  test('a single named ticket has no dots; the PDFs live under More options', async ({ page }) => {
    await mockAttendees(page, [att(1)]);
    await openTicket(page, 'upcoming', { bookingAttendees: store.list });
    await expect(page.locator('[data-testid^="confirmed-stub-dot-"]')).toHaveCount(0);
    await page.getByTestId('confirmed-more-button').click();
    await expect(page.getByTestId('confirmed-download-current')).toBeVisible();
    await expect(page.getByTestId('confirmed-download-all')).toHaveCount(0);
    await mockAttendees(page, [att(1), att(2)]);
    // the menu is still open on the same screen, and now lists Download all as a second attendee appears
    await devSet(page, { bookingAttendees: store.list });
    await expect(page.getByTestId('confirmed-download-all')).toBeVisible();
  });
});

// ---- Door scanning (note 78): when does a booking count as checked in, and how long does the door poll run? -------
// The poll is the screen's existing 6s door watch (real timers here), so these tests wait for real ticks. They count the
// poll's own requests: attendees for named tickets, and the booking row itself (`id=eq.b-78`, which the mount fetches
// never use).
test.describe('door scanning', () => {
  test.describe.configure({ timeout: 90_000 });
  const TICK = 8000; // one poll interval plus slack
  // `id=eq.b-78` as a whole query parameter: the gifted-seats lookup on mount asks for `original_booking_id=eq.b-78`.
  const BOOKING_ROW = /\/rest\/v1\/bookings\?(?:.*&)?id=eq\.b-78(?:&|$)/;
  const stripCase = (page) => page.getByTestId('confirmed-strip').getAttribute('data-case');

  function count(page) {
    const c = { attendees: 0, booking: 0 };
    page.on('request', (r) => {
      if (r.method() !== 'GET') return;
      if (r.url().includes('/rest/v1/booking_attendees')) c.attendees++;
      else if (BOOKING_ROW.test(r.url())) c.booking++;
    });
    return c;
  }
  // The same total, read again later: used to assert that polling really stopped.
  const quiet = async (page, c, key, settleMs = 1500) => {
    await page.waitForTimeout(settleMs); // let a request already on its way finish
    const before = c[key];
    await page.waitForTimeout(TICK);
    expect(c[key], `no new ${key} polls`).toBe(before);
  };

  test('several tickets, after the first scan: the strip stays pre-check-in and the poll keeps running', async ({ page }) => {
    await mockAttendees(page, [att(1), att(2), att(3)]);
    const c = count(page);
    await openTicket(page, 'today', { bookingAttendees: store.list });
    expect(await stripCase(page)).toBe('today');
    await attendeesSettled(page);
    // the next poll brings the first scan
    store.list = [att(1, iso(0)), att(2), att(3)];
    await expect(page.getByTestId('confirmed-stub-1')).toHaveAttribute('data-torn', 'true', { timeout: 15_000 });
    // one of three scanned: still not "You're in"
    expect(await stripCase(page)).toBe('today');
    await expect(page.getByTestId('confirmed-stub-2')).toHaveAttribute('data-torn', 'false');
    // and the poll is still running
    await attendeesSettled(page);
    const ticks = c.booking;
    await expect.poll(() => c.booking, { timeout: 15_000 }).toBeGreaterThan(ticks); // a real tick, not a mount fetch
    expect(await stripCase(page)).toBe('today');
  });

  test('several tickets, after the last scan: the strip says "You\'re in" and the poll stops', async ({ page }) => {
    await mockAttendees(page, [att(1, iso(-60000)), att(2, iso(-30000)), att(3)]);
    const c = count(page);
    await openTicket(page, 'today', { bookingAttendees: store.list });
    expect(await stripCase(page)).toBe('today');
    await attendeesSettled(page);
    store.list = [att(1, iso(-60000)), att(2, iso(-30000)), att(3, iso(0))];
    await expect(page.getByTestId('confirmed-strip')).toHaveAttribute('data-case', 'checkedIn', { timeout: 15_000 });
    await expect(page.getByTestId('confirmed-strip-heading')).toHaveText("You're in");
    await quiet(page, c, 'attendees');
    await quiet(page, c, 'booking');
  });

  test('several tickets: the poll stops when the door window ends, even if some are still unscanned', async ({ page }) => {
    // The screen's separate 6s receipt poll re-renders it, which recomputes the window and would end the door poll as a
    // side effect. Leave that lookup unanswered so only the door poll's own check can stop it.
    await page.route('**/rest/v1/payment_documents*', () => {});
    await mockAttendees(page, [att(1), att(2)]);
    const c = count(page);
    await openTicket(page, 'today', { bookingAttendees: store.list });
    await attendeesSettled(page);
    // Wait for a REAL poll tick (only the tick asks for `id=eq.b-78`; the mount fetches never do), then snapshot right
    // after it, so the next tick is a full interval away and any fetch after the clock jump can only be that tick.
    const ticks = c.booking, fetched = c.attendees;
    // (a tick asks for the booking row, then for the attendees; wait for both so the tick has fully finished)
    await expect.poll(() => c.booking > ticks && c.attendees > fetched, { timeout: 15_000 }).toBe(true);
    await attendeesSettled(page);
    // the window closes 12h after the start (start = now + 2h in this case), so jump past it without re-rendering
    await attendeesSettled(page);
    const attendeesAtClose = c.attendees;
    const bookingAtClose = c.booking;
    await page.clock.setFixedTime(new Date(NOW.getTime() + 15 * H));
    // Not a single further request: the very next tick must see the window is over. (Snapshot BEFORE the jump and wait a
    // full interval and a bit; without the in-tick check the old code made exactly one more request here.)
    await page.waitForTimeout(TICK + 1500);
    expect(c.attendees, 'no attendee poll after the window closed').toBe(attendeesAtClose);
    expect(c.booking, 'no booking poll after the window closed').toBe(bookingAtClose);
  });

  test('a single ticket behaves exactly as before: it polls its booking row only, and stops once that row says attended', async ({ page }) => {
    let status = 'confirmed';
    await page.route('**/rest/v1/bookings*', (route) => {
      const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' };
      const url = route.request().url();
      if (!BOOKING_ROW.test(url)) return route.fallback(); // the mount fetches (event lookup, gifted seats) are not ours
      if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors });
      const row = { id: 'b-78', event_id: 'bepnho', status, payment_state: 'confirmed', qty: 1, code: '1B159C', admission_token: 'tok-78-real-admission' };
      return route.fulfill({ status: 200, headers: { ...cors, 'content-type': 'application/vnd.pgrst.object+json' }, body: JSON.stringify(row) });
    });
    await mockAttendees(page, []);
    const c = count(page);
    await openTicket(page, 'today');
    expect(await stripCase(page)).toBe('today');
    await attendeesSettled(page);
    const attendeesAtMount = c.attendees;
    const polls = c.booking;
    await expect.poll(() => c.booking, { timeout: 15_000 }).toBeGreaterThan(polls); // the booking row is polled
    expect(c.attendees, 'a single ticket never polls attendees').toBe(attendeesAtMount);
    expect(await stripCase(page)).toBe('today');
    // the door scans it: the booking row becomes 'attended'
    status = 'attended';
    await expect(page.getByTestId('confirmed-strip')).toHaveAttribute('data-case', 'checkedIn', { timeout: 15_000 });
    await quiet(page, c, 'booking');
    expect(c.attendees).toBe(attendeesAtMount);
  });
});

// ---- Step 6: the Event details sheet, and Event Detail with a Back that returns to this ticket --------------------------
const BEPNHO = EVENTS.find((e) => e.key === 'bepnho');
const sheet = (page) => page.getByTestId('event-details-sheet');

test.describe('event details sheet', () => {
  test('the event name and the "View event" pill both open it; Escape and the close button close it; focus returns', async ({ page }) => {
    await openTicket(page, 'upcoming');
    await expect(sheet(page)).toHaveCount(0);
    await page.getByTestId('confirmed-open-details').click();
    await expect(sheet(page)).toBeVisible();
    await expect(page.getByRole('dialog')).toHaveAttribute('aria-modal', 'true');
    await page.keyboard.press('Escape');
    await expect(sheet(page)).toHaveCount(0);
    await expect(page.getByTestId('confirmed-open-details')).toBeFocused();
    await page.getByTestId('confirmed-view-event').click();
    await expect(sheet(page)).toBeVisible();
    await page.getByTestId('event-details-close').click();
    await expect(sheet(page)).toHaveCount(0);
    await expect(page.getByTestId('confirmed-view-event')).toBeFocused();
    // scrim click also closes
    await page.getByTestId('confirmed-view-event').click();
    await sheet(page).click({ position: { x: 10, y: 10 } });
    await expect(sheet(page)).toHaveCount(0);
  });

  test('it shows only the real event: title, tiles, About, Included, host, location and the unchanged refund line', async ({ page }) => {
    await openTicket(page, 'upcoming');
    await page.getByTestId('confirmed-open-details').click();
    await expect(page.getByRole('dialog')).toContainText('Bếp Nhỏ');
    await expect(page.getByTestId('event-details-tile-date')).toContainText('Sun 8 Nov');
    await expect(page.getByTestId('event-details-tile-time')).toContainText('12:00');
    await expect(page.getByTestId('event-details-tile-place')).toContainText('Bình Thạnh');
    await expect(page.getByTestId('event-details-about')).toContainText('Mười bốn chỗ');
    await expect(page.getByTestId('event-details-included')).toContainText('rượu gạo');
    await expect(page.getByTestId('event-details-host')).toContainText('Bếp Nhỏ');
    await expect(page.getByTestId('event-details-place')).toContainText('Bình Thạnh');
    await expect(page.getByTestId('event-details-policy')).toHaveText('banbe does not collect money. Pay the organizer directly using the instructions in chat. If they cancel, they are responsible for your refund.');
    // the old interim "Next" block is gone from the ticket page
    await expect(page.getByTestId('confirmed-next')).toHaveCount(0);
  });

  test('an event with nothing written shows no About, no Included and no host: no placeholders', async ({ page }) => {
    await openTicket(page, 'upcoming');
    // switch to a bare real event; wait for the app's own lookups for it, then put the booking back
    const looked = page.waitForResponse((r) => r.url().includes('/rest/v1/events') && r.url().includes('slug=eq.real-78'), { timeout: 8000 }).catch(() => null);
    await devSet(page, { eventKey: 'real-78', realEventsById: { 'real-78': { key: 'real-78', name: 'Quiet night', status: 'live', startsAt: iso(72 * H), area: 'Quận 3', catLabel: 'Music', catKey: 'music', description: '', included: '', includedItems: [], intro: '', organizerName: '', photoUrl: '', priceVnd: 0, seatsRemaining: 5, details: {} } } });
    await looked;
    await page.waitForTimeout(600);
    await devSet(page, { booking: { id: 'b-78', event_id: 'real-78', status: 'confirmed', payment_state: 'confirmed', qty: 1, code: '1B159C', admission_token: 'tok-78-real-admission' }, screen: 'confirmed' });
    await page.getByTestId('confirmed-open-details').click();
    await expect(page.getByRole('dialog')).toContainText('Quiet night');
    await expect(page.getByTestId('event-details-tile-place')).toContainText('Quận 3');
    await expect(page.getByTestId('event-details-about')).toHaveCount(0);
    await expect(page.getByTestId('event-details-included')).toHaveCount(0);
    await expect(page.getByTestId('event-details-host')).toHaveCount(0);
    await expect(page.getByTestId('event-details-cover')).toHaveCount(0);
  });

  test('distance: hidden when not located, hidden beyond 50 km, shown when located and near', async ({ page }) => {
    await openTicket(page, 'upcoming');
    await page.getByTestId('confirmed-open-details').click();
    await expect(page.getByTestId('event-details-distance')).toHaveCount(0); // not located
    await page.getByTestId('event-details-close').click();
    await devSet(page, { located: true, userCoords: { lat: BEPNHO.lat + 5, lng: BEPNHO.lng } }); // about 550 km
    await page.getByTestId('confirmed-open-details').click();
    await expect(page.getByTestId('event-details-distance')).toHaveCount(0);
    await page.getByTestId('event-details-close').click();
    await devSet(page, { located: true, userCoords: { lat: BEPNHO.lat + 0.02, lng: BEPNHO.lng } }); // about 2.2 km
    await page.getByTestId('confirmed-open-details').click();
    await expect(page.getByTestId('event-details-distance')).toHaveText(/^2[.,]\d km$/);
  });

  test('"Open full event page" goes to Event Detail labelled Ticket, and Back returns to the same ticket', async ({ page }) => {
    await openTicket(page, 'upcoming');
    await page.getByTestId('confirmed-open-details').click();
    await expect(page.getByTestId('event-details-open')).toHaveText(/Open full event page/);
    await page.getByTestId('event-details-open').click();
    await expect(sheet(page)).toHaveCount(0); // closed on the way out, so Back finds a closed ticket
    await expect(page.getByTestId('event-detail-back')).toBeVisible();
    await expect(page.getByTestId('event-detail-back')).toHaveAttribute('aria-label', 'Ticket');
    await page.getByTestId('event-detail-back').click();
    // the same ticket: same booking, strip and entry code, sheet closed (and it is not Home)
    await expect(page.locator('[data-screen-label="Confirmed"]')).toBeVisible();
    await expect(page.getByTestId('confirmed-strip')).toHaveAttribute('data-case', 'upcoming');
    await expect(page.getByTestId('confirmed-entry-code')).toHaveText('1B1 59C');
    await expect(sheet(page)).toHaveCount(0);
    await expect(page.locator('[data-screen-label="Home"]')).toHaveCount(0);
  });

  test('for a cancelled or ended event the button says View event page', async ({ page }) => {
    for (const name of ['cancelled', 'ended']) {
      await openTicket(page, name);
      await page.getByTestId('confirmed-view-event').click();
      await expect(page.getByTestId('event-details-open')).toHaveText(/View event page/);
      await page.getByTestId('event-details-close').click();
    }
  });

  test('Message host in the sheet opens the chat, and its Back returns to the ticket', async ({ page }) => {
    await openTicket(page, 'upcoming');
    await page.getByTestId('confirmed-open-details').click();
    await page.getByTestId('event-details-message').click();
    await expect(page.getByTestId('chat-back')).toContainText('Ticket');
    await page.getByTestId('chat-back').click();
    await expect(page.locator('[data-screen-label="Confirmed"]')).toBeVisible();
    await expect(sheet(page)).toHaveCount(0);
  });

  test('reduced motion: the sheet fades instead of sliding', async ({ page }) => {
    await openTicket(page, 'upcoming');
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await devSet(page, { screen: 'confirmed' });
    await page.getByTestId('confirmed-open-details').click();
    const anim = await page.getByRole('dialog').evaluate((el) => getComputedStyle(el).animationName);
    expect(anim).toBe('banbeFade');
  });

  test('Tab stays inside the open sheet', async ({ page }) => {
    await openTicket(page, 'upcoming');
    await page.getByTestId('confirmed-open-details').click();
    for (let i = 0; i < 12; i++) {
      await page.keyboard.press('Tab');
      const inside = await page.evaluate(() => !!document.activeElement?.closest('[role="dialog"]'));
      expect(inside, `Tab press ${i + 1}`).toBe(true);
    }
  });

  test('Vietnamese at 320px, light and dark: the sheet does not scroll sideways', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 640 });
    for (const theme of ['light', 'dark']) {
      await openTicket(page, 'upcoming', { lang: 'vi', theme });
      await page.getByTestId('confirmed-open-details').click();
      const over = await page.evaluate(() => { const d = document.querySelector('[role="dialog"]'); return { page: document.documentElement.scrollWidth - innerWidth, sheet: d.scrollWidth - d.clientWidth }; });
      expect(over.page, `${theme} page`).toBeLessThanOrEqual(0);
      expect(over.sheet, `${theme} sheet`).toBeLessThanOrEqual(0);
      await page.getByTestId('event-details-close').click();
    }
  });
});

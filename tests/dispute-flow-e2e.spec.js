// @ts-check
/// <reference types="@playwright/test" />
//
// Real-backend end-to-end test of the ticket-dispute flow (notes 01-05):
// hold -> mark paid -> organizer "not found" -> temporary dispute chat
// (both directions) -> escalate -> admin resolves (both outcomes) -> the
// decision email.
//
// Unlike every other spec in this suite, this one does NOT mock any network
// route — it creates real Supabase Auth users, writes real rows, and (when
// GMAIL_USER/GMAIL_APP_PASSWORD resolve) sends a real Gmail message. It is
// gated on SUPABASE_SERVICE_ROLE_KEY being available (see tests/e2e/setup.mjs)
// and is NOT part of the default fast suite — run it explicitly:
//   npx playwright test tests/dispute-flow-e2e.spec.js
//
// WHY THE PARTICIPANT SIDE ISN'T CLICKED THROUGH THE UI: Home/EventDetail
// only ever render the static demo catalogue in src/data/events.js — there
// is no live query against the `events` table and no `?event=` URL param
// (confirmed by grep: zero references to `v_event_availability`/
// `seats_remaining` anywhere in src/). A booking's `event_id` has to match
// one of those hardcoded demo keys for Reserve/PaymentDetails/Confirmed to
// ever become reachable by clicking through Home. A fresh event created for
// this test is therefore not click-reachable, and temporarily splicing fake
// rows into the shared demo catalogue would risk the ~268 other tests that
// assert on it. The organizer/admin queues (Verifications.jsx, Disputes.jsx)
// have no such dependency — they query live views (`v_pending_verifications`,
// `v_disputes`) by real ownership/RLS — so those two roles ARE driven
// through the real browser UI below. The participant's three actions (hold,
// mark paid, send a chat message) go through the identical RPCs
// (`hold_seats`, `submit_payment_proof`, `send_dispute_message`) via an
// authenticated supabase-js client signed in with
// `auth.signInWithPassword()` — the exact call the real Login screen's
// password tab makes — so authentication and every server-side check (RLS,
// SECURITY DEFINER functions, triggers) are still fully real; only the
// keystrokes are not simulated. This is worth fixing properly (a `?event=`
// deep link, or a dev-only seed of one live-queryable demo event) if this
// suite is going to grow — flagged in 04-admin-escalation.md.
import { test, expect } from '@playwright/test';
import {
  hasServiceRole, adminClient, anonClient, ensureAdminAccount, createTestUser,
  createOrganizer, createEvent, signIn, cleanup,
} from './e2e/setup.mjs';
import { setupToHome } from './helpers.js';

const SKIP_REASON = 'requires SUPABASE_SERVICE_ROLE_KEY (+ VITE_SUPABASE_ANON_KEY) — '
  + 'this test writes real rows and sends a real email; see tests/e2e/setup.mjs';

test.describe.configure({ mode: 'serial' });

test.describe('Dispute flow — real backend E2E (notes 01-05)', () => {
  /** @type {ReturnType<typeof adminClient>} */
  let admin;
  let adminAcct, organizerUser;
  let organizerId;
  const eventIds = [];
  const userIds = [];

  test.beforeAll(async () => {
    if (!hasServiceRole()) return;
    admin = adminClient();
    adminAcct = await ensureAdminAccount(admin);
    organizerUser = await createTestUser(admin, 'organizer', { role: 'organizer', displayName: 'E2E Organizer' });
    organizerId = await createOrganizer(admin, organizerUser.userId, 'E2E Test Organizer');
    userIds.push(organizerUser.userId);
  });

  test.afterAll(async () => {
    if (!admin) return;
    await cleanup(admin, { userIds, organizerId, eventIds });
  });

  async function loginWithPassword(page, email, password) {
    await setupToHome(page);
    await page.getByText('Tài khoản').first().click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 5000 });
    await page.getByText('Đăng nhập để lưu sự kiện và nhắn tin').click();
    await expect(page.locator('[data-screen-label="Login"]')).toBeVisible({ timeout: 5000 });
    await page.locator('[data-screen-label="Login"]').getByText('Mật khẩu', { exact: true }).click();
    await page.locator('[data-testid="login-email"]').fill(email);
    await page.locator('input[placeholder="Password"], input[placeholder="Mật khẩu"]').first().fill(password);
    await page.locator('[data-testid="login-submit"]').click();
    await expect(page.locator('[data-screen-label="Login"]')).toBeHidden({ timeout: 8000 });
  }

  /**
   * Runs one full pass of the flow for one outcome ('uphold' issues the
   * ticket, matching "Khách đúng ▪︎ cấp vé"; 'release' matches "Mở lại chỗ").
   * Returns the three pass/fail results the ticket asked for.
   */
  async function runDisputeFlow({ browser, label, outcome }) {
    const eventId = await createEvent(admin, organizerId, label);
    eventIds.push(eventId);
    const participant = await createTestUser(admin, `participant-${label}`, { displayName: `E2E Participant ${label}` });
    userIds.push(participant.userId);

    const results = { chatBothDirections: null, statusTransition: null, emailDelivered: null };

    // --- Participant: hold a slot, mark payment sent, send one chat message ---
    // (see file header for why this is RPC-driven rather than click-driven)
    const { client: participantClient } = await signIn(participant.email, participant.password);
    const { data: booking, error: holdError } = await participantClient.rpc('hold_seats', {
      p_event: eventId, p_qty: 1, p_note: null,
    });
    expect(holdError, `hold_seats failed: ${holdError?.message}`).toBeNull();
    expect(booking.payment_state).toBe('holding');
    expect(booking.hold_expires_at).toBeTruthy();
    const bookingId = booking.id;

    // Real upload to the real 'pay-proof' bucket, at the real convention
    // (`<bookingId>/<filename>`, enforced by the storage RLS policy) — a
    // tiny valid PNG, so the later email step's real attachment-download
    // path is exercised too, not just stubbed with a string.
    const tinyPng = Buffer.from(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      'base64'
    );
    const proofPath = `${bookingId}/proof.png`;
    const { error: uploadError } = await participantClient.storage.from('pay-proof').upload(proofPath, tinyPng, { contentType: 'image/png' });
    expect(uploadError, `proof upload failed: ${uploadError?.message}`).toBeNull();

    const { data: submitResult, error: submitError } = await participantClient.rpc('submit_payment_proof', {
      p_booking: bookingId, p_transaction_id: `E2E-${label.toUpperCase()}-TXN`, p_proof_path: proofPath,
    });
    expect(submitError, `submit_payment_proof failed: ${submitError?.message}`).toBeNull();
    expect(submitResult.success).toBe(true);
    // The "timer stops" signal (01-hold-payment.md): hold_expires_at stops
    // being consulted the moment payment_state leaves 'holding' — confirm
    // that transition actually happened, which is what freezes the
    // countdown in PaymentDetails.jsx (payment-countdown -> payment-frozen).
    const { data: afterSubmit } = await admin.from('bookings').select('payment_state').eq('id', bookingId).single();
    expect(afterSubmit.payment_state).toBe('pending_verification');

    // --- Organizer: real UI. "Chưa thấy" (not found) + reason ---
    const organizerContext = await browser.newContext();
    const organizerPage = await organizerContext.newPage();
    await loginWithPassword(organizerPage, organizerUser.email, organizerUser.password);
    await organizerPage.getByText('Tài khoản').first().click();
    await organizerPage.locator('[data-testid="host-verifications"]').click();
    await expect(organizerPage.locator('[data-testid="verifications-title"]')).toBeVisible({ timeout: 5000 });

    const row = organizerPage.locator('[data-testid="verification-row"]');
    await expect(row).toHaveCount(1, { timeout: 8000 }); // only this test's own booking, for this fresh organizer
    await row.locator('[data-testid="verification-reject"]').click();
    await organizerPage.locator('[data-testid="verification-reason"]').fill(`E2E ${label}: proof not found in statement`);
    await organizerPage.locator('[data-testid="verification-reject-confirm"]').click();
    // reject_payment() opens dispute_threads immediately (migration 041) —
    // the chat opener appears on the same row without a page reload.
    await expect(row.locator('[data-testid="verification-open-not-found-chat"]')).toBeVisible({ timeout: 8000 });

    // --- Participant sends first (RPC) so the organizer's real UI panel,
    // once opened, has to actually pull in a message it didn't just send. ---
    const { data: guestSend, error: guestSendError } = await participantClient.rpc('send_dispute_message', {
      p_booking: bookingId, p_body: `Participant ${label}: here is my transfer receipt again.`,
    });
    expect(guestSendError, `guest send_dispute_message failed: ${guestSendError?.message}`).toBeNull();
    expect(guestSend.success, `guest send_dispute_message returned: ${JSON.stringify(guestSend)}`).toBe(true);

    await row.locator('[data-testid="verification-open-not-found-chat"]').click();
    const orgPanel = row.locator('[data-testid="dispute-chat-panel"]');
    await expect(orgPanel).toBeVisible({ timeout: 5000 });
    // 4s poll (DisputeChatPanel.jsx) — generous timeout for the guest's
    // message to actually show up on the organizer's screen.
    await expect(orgPanel.locator('[data-testid="dispute-chat-message"]')).toHaveCount(1, { timeout: 10000 });
    await orgPanel.locator('[data-testid="dispute-chat-input"]').fill(`Organizer ${label}: checking with the bank now.`);
    await orgPanel.locator('[data-testid="dispute-chat-send"]').click();
    await expect(orgPanel.locator('[data-testid="dispute-chat-message"]')).toHaveCount(2, { timeout: 10000 });
    const chatTexts = await orgPanel.locator('[data-testid="dispute-chat-message"]').allTextContents();
    results.chatBothDirections =
      chatTexts.some(t => t.includes('here is my transfer receipt')) &&
      chatTexts.some(t => t.includes('checking with the bank'));
    expect(results.chatBothDirections, `expected both directions in: ${JSON.stringify(chatTexts)}`).toBe(true);

    // --- Organizer escalates to banbe ---
    await row.locator('[data-testid="verification-escalate"]').click();
    await organizerPage.locator('[data-testid="verification-reason"]').fill(`E2E ${label}: cannot reconcile, escalating`);
    await organizerPage.locator('[data-testid="verification-reject-confirm"]').click();
    await expect(async () => {
      const { data } = await admin.from('bookings').select('payment_state').eq('id', bookingId).single();
      expect(data.payment_state).toBe('disputed');
    }).toPass({ timeout: 8000 });
    await organizerContext.close();

    // --- Admin: real UI. Resolve the dispute (both outcomes tested across the two runs). ---
    const adminContext = await browser.newContext();
    const adminPage = await adminContext.newPage();
    await loginWithPassword(adminPage, adminAcct.email, adminAcct.password);
    await adminPage.getByText('Tài khoản').first().click();
    await adminPage.locator('[data-testid="admin-disputes"]').click();
    await expect(adminPage.locator('[data-testid="disputes-title"]')).toBeVisible({ timeout: 5000 });

    const disputeRow = adminPage.locator('[data-testid="dispute-row"]');
    await expect(disputeRow).toHaveCount(1, { timeout: 8000 });
    await disputeRow.locator('[data-testid="dispute-reason-category"]').selectOption('proof_not_found');
    await disputeRow.locator('[data-testid="dispute-note"]').fill(`E2E ${label}: resolved by automated test`);
    if (outcome === 'uphold') {
      await disputeRow.locator('[data-testid="dispute-uphold"]').click();
    } else {
      await disputeRow.locator('[data-testid="dispute-reject"]').click();
    }
    // The row leaving the open list (or the resolve button's own busy-label
    // clearing) is resolve_dispute()'s DB write landing — confirmed below
    // against the database directly, not just the UI's own optimistic state.
    await expect(adminPage.locator('[data-testid="dispute-row"]')).toHaveCount(0, { timeout: 10000 });
    await adminContext.close();

    // --- Check 2: ticket status transition (the exact P0001 regression this repo hit before) ---
    const { data: resolvedBooking } = await admin.from('bookings')
      .select('payment_state, status, dispute_resolved_at, dispute_resolution').eq('id', bookingId).single();
    if (outcome === 'uphold') {
      results.statusTransition = resolvedBooking.payment_state === 'confirmed' && resolvedBooking.status === 'confirmed';
    } else {
      results.statusTransition = resolvedBooking.payment_state === 'expired' && resolvedBooking.status === 'expired';
    }
    expect(results.statusTransition, `unexpected post-resolution state: ${JSON.stringify(resolvedBooking)}`).toBe(true);
    expect(resolvedBooking.dispute_resolved_at).toBeTruthy();

    const { data: thread } = await admin.from('dispute_threads')
      .select('resolved_at, resolution_kind, purge_after, organizer_id').eq('booking_id', bookingId).single();
    expect(thread.resolved_at).toBeTruthy();
    expect(thread.resolution_kind).toBe(outcome === 'uphold' ? 'ticket_issued' : 'cancelled');

    const { data: stats } = await admin.from('dispute_resolution_stats')
      .select('resolution_kind, reason_category, time_to_resolution_seconds').eq('booking_id', bookingId).maybeSingle();
    expect(stats, 'dispute_resolution_stats row missing (migration 047)').toBeTruthy();
    expect(stats.reason_category).toBe('proof_not_found');
    expect(stats.time_to_resolution_seconds).toBeGreaterThanOrEqual(0);

    // --- Check 3: the actual decision email ---
    // /api/dispute-resolved-email is a Vercel serverless function; the local
    // Playwright webServer is plain `vite` (no Vercel runtime), so the
    // browser's own fire-and-forget fetch() to it 404s here — that's a
    // sandbox limitation, not a product bug (flagged in 05-notify-retention.md
    // long before this test). To exercise the REAL handler code (same file,
    // same logic, real Gmail send) rather than just assert around the gap,
    // it's imported and invoked directly with a real admin bearer token.
    const { session: adminSession } = await signIn(adminAcct.email, adminAcct.password);
    const { default: disputeResolvedEmailHandler } = await import('../api/dispute-resolved-email.js');
    const fakeReq = {
      method: 'POST',
      headers: { authorization: `Bearer ${adminSession.access_token}` },
      body: { bookingId },
    };
    let capturedStatus = null;
    let capturedBody = null;
    const fakeRes = {
      setHeader() {},
      status(code) { capturedStatus = code; return this; },
      json(body) { capturedBody = body; return this; },
    };
    await disputeResolvedEmailHandler(fakeReq, fakeRes);

    results.emailDelivered = capturedStatus === 200 && capturedBody?.sent > 0;
    console.log(`[${label}] dispute-resolved-email response:`, capturedStatus, JSON.stringify(capturedBody));

    // Independently confirm getUserById resolves both real accounts to real,
    // non-null emails (the specific bug this ticket named as a suspect).
    const { data: guestAuth } = await admin.auth.admin.getUserById(participant.userId);
    const { data: organizerAuth } = await admin.auth.admin.getUserById(organizerUser.userId);
    expect(guestAuth?.user?.email).toBe(participant.email);
    expect(organizerAuth?.user?.email).toBe(organizerUser.email);

    expect(capturedStatus, `dispute-resolved-email returned ${capturedStatus}: ${JSON.stringify(capturedBody)}`).toBe(200);
    expect(capturedBody.sent, `expected both recipients to receive mail, got: ${JSON.stringify(capturedBody)}`).toBe(2);

    const { data: threadAfterEmail } = await admin.from('dispute_threads').select('email_sent_at').eq('booking_id', bookingId).single();
    expect(threadAfterEmail.email_sent_at, 'email_sent_at was never stamped').toBeTruthy();

    return results;
  }

  test('Run A — "ticket approved" (Khách đúng ▪︎ cấp vé)', async ({ browser }) => {
    test.skip(!hasServiceRole(), SKIP_REASON);
    test.setTimeout(120_000);
    const results = await runDisputeFlow({ browser, label: 'run-a', outcome: 'uphold' });
    expect(results.chatBothDirections).toBe(true);
    expect(results.statusTransition).toBe(true);
  });

  test('Run B — "return to pool" (Mở lại chỗ)', async ({ browser }) => {
    test.skip(!hasServiceRole(), SKIP_REASON);
    test.setTimeout(120_000);
    const results = await runDisputeFlow({ browser, label: 'run-b', outcome: 'release' });
    expect(results.chatBothDirections).toBe(true);
    expect(results.statusTransition).toBe(true);
  });
});

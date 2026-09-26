// @ts-check
/// <reference types="@playwright/test" />
//
// Real-backend E2E of the event submission -> admin review -> publish gate
// (migration 085): create_event_draft() now inserts `status = 'review'`
// (previously 'live' — the actual bug), admin_review_event() is the only
// way it ever becomes 'live' or gets sent back to 'draft' with a reason.
//
// The organizer side goes through the real RPC directly (signInWithPassword,
// same as tests/dispute-flow-e2e.spec.js's own participant actions) rather
// than clicking through Home — same reason that file documents: a fresh
// event isn't click-reachable there unless it happens to land in the
// weekend window. The ADMIN side IS driven through the real UI
// (Account -> "Sự kiện chờ duyệt"), since that's the actual navigation path
// this ticket asked to verify, using the same designated test admin account
// (banbetestadmin@gmail.com) and password-reset convention
// tests/dispute-flow-e2e.spec.js already established.
//
// Gated on SUPABASE_SERVICE_ROLE_KEY. Not part of the default fast suite:
//   npx playwright test tests/e2e/event-review-queue-e2e.spec.js
import { test, expect } from '@playwright/test';
import {
  hasServiceRole, adminClient, anonClient, ensureAdminAccount, createTestUser,
  createOrganizer, signIn, cleanup,
} from './setup.mjs';
import { setupToHome } from '../helpers.js';

const SKIP_REASON = 'requires SUPABASE_SERVICE_ROLE_KEY (+ VITE_SUPABASE_ANON_KEY) — see tests/e2e/setup.mjs';

test.describe.configure({ mode: 'serial' });

test.describe('Event submission -> admin review -> publish — real backend E2E (migration 085)', () => {
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
    organizerUser = await createTestUser(admin, 'review-organizer', { role: 'organizer', displayName: 'E2E Review Organizer' });
    organizerId = await createOrganizer(admin, organizerUser.userId, 'E2E Review Test Organizer');
    userIds.push(organizerUser.userId);
  });

  test.afterAll(async () => {
    if (!admin) return;
    await cleanup(admin, { userIds, organizerId, eventIds });
  });

  async function submitEvent(label) {
    const { client } = await signIn(organizerUser.email, organizerUser.password);
    const { data: event, error } = await client.rpc('create_event_draft', {
      p_name: `E2E Review Event ${label} ${Date.now().toString(36)}`,
      p_category: 'supper', p_description: 'desc', p_location: 'Quận 1',
      p_event_date: '2026-12-01', p_event_time: '19:00',
      p_price_vnd: 100000, p_capacity: 10,
      p_organizer_name: 'E2E Review Test Organizer',
    });
    expect(error, `create_event_draft failed: ${error?.message}`).toBeNull();
    eventIds.push(event.id);
    return event;
  }

  // Signs in as the real admin account and hands back a page already
  // authenticated, WITHOUT clicking through Login.jsx's password form —
  // that UI path is independently broken in this environment right now
  // (confirmed: tests/dispute-flow-e2e.spec.js and tests/notifications-
  // toast.spec.js, both pre-existing and untouched by this change, hang at
  // the exact same step). Builds the session the identical way
  // tests/global-setup.js already does for the shared fast-suite account —
  // a real signInWithPassword() session, just injected as this browser's
  // own localStorage instead of typed into the form, so this test still
  // exercises the real AdminEvents.jsx screen and its real reviewEvent()
  // RPC calls, only skipping the independently-broken login screen itself.
  async function adminPage(browser) {
    const { session } = await signIn(adminAcct.email, adminAcct.password);
    const projectRef = new URL(process.env.VITE_SUPABASE_URL).hostname.split('.')[0];
    const storageKey = `sb-${projectRef}-auth-token`;
    const context = await browser.newContext({
      storageState: {
        cookies: [],
        origins: [{
          origin: 'http://localhost:5173',
          localStorage: [{
            name: storageKey,
            value: JSON.stringify({
              access_token: session.access_token, token_type: 'bearer',
              expires_in: session.expires_in, expires_at: session.expires_at,
              refresh_token: session.refresh_token, user: session.user,
            }),
          }],
        }],
      },
    });
    const page = await context.newPage();
    await setupToHome(page);
    return page;
  }

  test('1. Submit actually inserts a real events row, status=review, owned by the organizer', async () => {
    test.skip(!hasServiceRole(), SKIP_REASON);
    const event = await submitEvent('root-cause');
    expect(event.status).toBe('review');
    expect(event.visibility).toBe('public');
    expect(event.organizer_id).toBe(organizerId);
    // Not publicly discoverable while pending — events_select_public
    // (084) only allows status IN (live, ended, cancelled) or the owner.
    const anon = anonClient();
    const { data: publicRead } = await anon.from('events').select('id').eq('id', event.id).maybeSingle();
    expect(publicRead, 'a pending event must not be publicly readable').toBeNull();
  });

  test('2. Unauthorized non-admin cannot approve/reject, server-enforced not just UI-hidden', async () => {
    test.skip(!hasServiceRole(), SKIP_REASON);
    const event = await submitEvent('unauthorized-attempt');
    const stranger = await createTestUser(admin, 'review-stranger', { displayName: 'E2E Stranger' });
    userIds.push(stranger.userId);
    const { client: strangerClient } = await signIn(stranger.email, stranger.password);

    const { data, error } = await strangerClient.rpc('admin_review_event', {
      p_event_id: event.id, p_approve: true, p_reason: '',
    });
    expect(error).toBeNull();
    expect(data.success).toBe(false);
    expect(data.error).toBe('ADMIN_ONLY');

    // The organizer's own signed-in client can't approve their own
    // submission either — same RPC, same gate.
    const { client: organizerClient } = await signIn(organizerUser.email, organizerUser.password);
    const { data: selfApprove } = await organizerClient.rpc('admin_review_event', {
      p_event_id: event.id, p_approve: true, p_reason: '',
    });
    expect(selfApprove.success).toBe(false);
    expect(selfApprove.error).toBe('ADMIN_ONLY');

    // RLS itself, not just the RPC gate: a non-admin, non-owner reading the
    // pending queue directly gets nothing back.
    const { data: strangerRead } = await strangerClient.from('events').select('id').eq('id', event.id);
    expect(strangerRead).toEqual([]);

    const { data: stillReview } = await admin.from('events').select('status').eq('id', event.id).single();
    expect(stillReview.status).toBe('review');
  });

  test('3. Admin approves through the real "Sự kiện chờ duyệt" queue -> event goes live, host notified', async ({ browser }) => {
    test.skip(!hasServiceRole(), SKIP_REASON);
    const event = await submitEvent('approve-me');

    const page = await adminPage(browser);
    await page.getByText('Tài khoản').first().click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 5000 });
    await page.getByTestId('admin-events').click();
    const queueScreen = page.locator('[data-screen-label="Admin events"]');
    await expect(queueScreen).toBeVisible({ timeout: 5000 });

    const row = queueScreen.locator('[data-testid="admin-event-row"]').filter({ hasText: event.name });
    await expect(row).toBeVisible({ timeout: 8000 });
    await row.getByTestId('admin-event-approve').click();
    await expect(row).toHaveCount(0, { timeout: 8000 });

    await expect(async () => {
      const { data } = await admin.from('events').select('status, reviewed_by, reviewed_at').eq('id', event.id).single();
      expect(data.status).toBe('live');
      expect(data.reviewed_by).toBeTruthy();
      expect(data.reviewed_at).toBeTruthy();
    }).toPass({ timeout: 5000 });

    await expect(async () => {
      const { data } = await admin.from('notifications').select('*').eq('recipient_id', organizerUser.userId).eq('kind', 'event_approved').contains('data', { event_id: event.id });
      expect(data.length).toBeGreaterThan(0);
    }).toPass({ timeout: 5000 });

    // Now publicly discoverable — server-confirmed approval, not a client
    // guess.
    const anon = anonClient();
    const { data: publicRead } = await anon.from('events').select('id, status').eq('id', event.id).maybeSingle();
    expect(publicRead?.status).toBe('live');
  });

  test('4. Admin rejects with a required reason -> event back to draft, host sees the reason, can resubmit', async ({ browser }) => {
    test.skip(!hasServiceRole(), SKIP_REASON);
    const event = await submitEvent('reject-me');
    const reason = 'Thiếu ảnh sự kiện thật';

    const page = await adminPage(browser);
    await page.getByText('Tài khoản').first().click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 5000 });
    await page.getByTestId('admin-events').click();
    const queueScreen = page.locator('[data-screen-label="Admin events"]');
    await expect(queueScreen).toBeVisible({ timeout: 5000 });

    const row = queueScreen.locator('[data-testid="admin-event-row"]').filter({ hasText: event.name });
    await expect(row).toBeVisible({ timeout: 8000 });

    // A reject tap with no reason typed must not go through (client AND
    // server both require one — see reviewEvent()/admin_review_event()).
    await row.getByTestId('admin-event-reject').click();
    await expect(row).toBeVisible();

    await row.getByTestId('admin-event-reason').fill(reason);
    await row.getByTestId('admin-event-reject').click();
    await expect(row).toHaveCount(0, { timeout: 8000 });

    const { data: rejected } = await admin.from('events').select('status, rejection_reason, reviewed_by').eq('id', event.id).single();
    expect(rejected.status).toBe('draft');
    expect(rejected.rejection_reason).toBe(reason);
    expect(rejected.reviewed_by).toBeTruthy();

    const { data: notif } = await admin.from('notifications').select('*').eq('recipient_id', organizerUser.userId).eq('kind', 'event_rejected').contains('data', { event_id: event.id });
    expect(notif.length).toBeGreaterThan(0);

    // Host corrects and resubmits — the SAME event row, not a duplicate.
    const { client: organizerClient } = await signIn(organizerUser.email, organizerUser.password);
    const { data: resubmit, error: resubmitError } = await organizerClient.rpc('resubmit_event_for_review', {
      p_event_id: event.id, p_name: event.name + ' (fixed)', p_category: 'supper',
      p_description: 'fixed desc', p_location: 'Quận 1',
      p_event_date: '2026-12-08', p_event_time: '19:00',
      p_price_vnd: 100000, p_capacity: 10,
    });
    expect(resubmitError).toBeNull();
    expect(resubmit.success).toBe(true);
    const { data: afterResubmit } = await admin.from('events').select('status, rejection_reason, name').eq('id', event.id).single();
    expect(afterResubmit.status).toBe('review');
    expect(afterResubmit.rejection_reason).toBe('');
    expect(afterResubmit.name).toContain('(fixed)');
  });

  test('5. Duplicate-decision race: a second review call on an already-decided event is rejected, not silently reprocessed', async () => {
    test.skip(!hasServiceRole(), SKIP_REASON);
    const event = await submitEvent('race-guard');
    // A real authenticated admin session, not the service-role client —
    // is_platform_admin() reads auth.uid(), which a service-role call has
    // none of.
    const { client: adminClientAuthed } = await signIn(adminAcct.email, adminAcct.password);
    const { data: first } = await adminClientAuthed.rpc('admin_review_event', { p_event_id: event.id, p_approve: true, p_reason: '' });
    expect(first.success).toBe(true);
    const { data: second } = await adminClientAuthed.rpc('admin_review_event', { p_event_id: event.id, p_approve: false, p_reason: 'too late' });
    expect(second.success).toBe(false);
    expect(second.error).toBe('NOT_PENDING');
    const { data: finalRow } = await admin.from('events').select('status').eq('id', event.id).single();
    expect(finalRow.status).toBe('live');
  });
});

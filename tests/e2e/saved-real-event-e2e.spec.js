// @ts-check
/// <reference types="@playwright/test" />
//
// Real-backend end-to-end test of the retention-roadmap blocker: a real,
// host-created event that is NOT one of the 20 static demo events in
// src/data/events.js must still be reachable, saveable, and correctly
// shown — on Home's "Cuối tuần này" section, on EventDetail, and on
// Account's Saved list — using the exact same real event_id everywhere,
// surviving a reload, and disappearing again on unsave.
//
// Drives the shared fast-suite test account (tests/global-setup.js,
// already verified to sign in reliably via storageState) rather than
// creating+logging-in a brand-new account through the UI — that path is a
// separate, pre-existing flakiness (also reproduces on unmodified main in
// tests/notifications-toast.spec.js, unrelated to this change) not worth
// coupling this test's own pass/fail to.
//
// Gated on SUPABASE_SERVICE_ROLE_KEY (see tests/e2e/setup.mjs). Not part
// of the default fast suite — run it explicitly:
//   npx playwright test tests/e2e/saved-real-event-e2e.spec.js
import { test, expect } from '@playwright/test';
import { hasServiceRole, adminClient, createTestUser, createOrganizer, cleanup } from './setup.mjs';
import { setupToHome } from '../helpers.js';
import { thisWeekendWindow } from '../../src/lib/countdown.js';

const SKIP_REASON = 'requires SUPABASE_SERVICE_ROLE_KEY (+ VITE_SUPABASE_ANON_KEY) — '
  + 'this test writes a real event row; see tests/e2e/setup.mjs';
const SHARED_ACCOUNT_EMAIL = 'doqanh0906+banbe-fast-suite-shared@gmail.com';

test.describe('Real (non-catalogue) event — save/weekend E2E (retention roadmap blocker)', () => {
  /** @type {ReturnType<typeof adminClient>} */
  let admin;
  let organizerId;
  let eventId;
  let sharedUserId;
  const userIds = [];
  const eventIds = [];
  const EVENT_NAME = 'E2E Real Event ' + Date.now().toString(36);

  test.beforeAll(async () => {
    if (!hasServiceRole()) return;
    admin = adminClient();

    const { data: registryRow } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', SHARED_ACCOUNT_EMAIL).maybeSingle();
    sharedUserId = registryRow?.auth_user_id;
    expect(sharedUserId, 'shared fast-suite account must already exist (tests/global-setup.js)').toBeTruthy();

    const organizerUser = await createTestUser(admin, 'weekend-organizer', { role: 'organizer', displayName: 'E2E Weekend Organizer' });
    userIds.push(organizerUser.userId);
    organizerId = await createOrganizer(admin, organizerUser.userId, 'E2E Weekend Test Organizer');

    // Inside the applicable weekend window (thisWeekendWindow — same helper
    // loadWeekendEvents uses), well clear of `now` so it's never excluded
    // by the `start` clamp, and NOT one of the 20 static demo ids.
    const { start } = thisWeekendWindow();
    const startsAt = new Date(new Date(start).getTime() + 6 * 3600 * 1000).toISOString();
    eventId = `e2e-weekend-${Date.now().toString(36)}`;
    const { error } = await admin.from('events').insert({
      id: eventId, key: eventId, slug: eventId, organizer_id: organizerId,
      name: EVENT_NAME, cat_key: 'music', cat_label: 'Nhạc', area: 'Quận 1',
      price_vnd: 150000, capacity: 20, seats_remaining: 20, starts_at: startsAt,
      hold_minutes: 30, status: 'live', approval: 'instant', visibility: 'public',
    });
    expect(error, `event insert failed: ${error?.message}`).toBeNull();
    eventIds.push(eventId);
  });

  test.afterAll(async () => {
    if (!admin) return;
    if (sharedUserId && eventId) await admin.from('favorites').delete().eq('user_id', sharedUserId).eq('event_id', eventId);
    await cleanup(admin, { userIds, organizerId, eventIds });
  });

  test('create → discover on weekend section → open → save → persists across reload → unsave', async ({ page }) => {
    test.skip(!hasServiceRole(), SKIP_REASON);

    await setupToHome(page);
    const homeScreen = page.locator('[data-screen-label="Home"]');
    await expect(homeScreen).toBeVisible({ timeout: 5000 });

    // Discover it on the weekend section, using the SAME real event id
    // loadWeekendEvents fetched it under.
    const weekendCard = page.getByTestId(`weekend-event-${eventId}`);
    await expect(weekendCard).toBeVisible({ timeout: 8000 });
    await expect(weekendCard.getByText(EVENT_NAME)).toBeVisible();

    // Save it right from the weekend card.
    await page.getByTestId(`weekend-save-${eventId}`).click();
    await expect(page.getByTestId(`weekend-save-${eventId}`)).toHaveText(/Đã lưu/);

    // Open it — EventDetail must show the REAL name (not a wrong demo
    // event's cosmetic fallback — the blocker this test guards against)
    // and the Save pill must already read "Đã lưu".
    await weekendCard.click();
    const eventScreen = page.locator('[data-screen-label="Event"]');
    await expect(eventScreen).toBeVisible({ timeout: 5000 });
    await expect(eventScreen.getByText(EVENT_NAME)).toBeVisible();
    await expect(page.getByTestId('event-detail-save')).toHaveText(/Đã lưu/);

    // Confirms the real DB row, not just optimistic client state — the
    // persist itself is fire-and-forget from toggleFav's own click handler
    // (see GocContext.jsx), so this polls rather than checking once
    // immediately after the click.
    await expect(async () => {
      const { data: favRow } = await admin.from('favorites').select('*').eq('user_id', sharedUserId).eq('event_id', eventId).maybeSingle();
      expect(favRow, 'favorites row should exist after saving').toBeTruthy();
    }).toPass({ timeout: 5000 });

    // Reload (a fresh session load, same as signing in again) — still saved.
    await page.reload();
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible({ timeout: 8000 });
    await page.getByText('Tài khoản').first().click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 5000 });
    await page.getByTestId('account-saved-card').click();
    const savedScreen = page.locator('[data-screen-label="Saved"]');
    await expect(savedScreen).toBeVisible({ timeout: 5000 });
    await expect(savedScreen.getByText(EVENT_NAME)).toBeVisible({ timeout: 5000 });

    // Open it from the Saved list too, then unsave from EventDetail.
    await savedScreen.getByText(EVENT_NAME).click();
    await expect(eventScreen).toBeVisible({ timeout: 5000 });
    await page.getByTestId('event-detail-save').click();
    await expect(page.getByTestId('event-detail-save')).toHaveText(/^Lưu$/);

    await expect(async () => {
      const { data: favRowAfter } = await admin.from('favorites').select('*').eq('user_id', sharedUserId).eq('event_id', eventId).maybeSingle();
      expect(favRowAfter, 'favorites row should be gone after unsaving').toBeNull();
    }).toPass({ timeout: 5000 });

    // Back on Saved, it's gone.
    await page.getByText('‹ Đã lưu').click();
    await expect(savedScreen).toBeVisible({ timeout: 5000 });
    await expect(savedScreen.getByText(EVENT_NAME)).toHaveCount(0);
  });
});

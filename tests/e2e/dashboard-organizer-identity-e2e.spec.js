// @ts-check
/// <reference types="@playwright/test" />
//
// Regression test for the Part B audit (2026-09-28) — a real-device report
// that Dashboard's own "Sự kiện sắp tới"/"đã qua" shelf for organizer
// "Vườn Sau" listed several events that, opened individually, showed a
// DIFFERENT organizer's own "Ghé <organizer>" name (e.g. "Ghé Phở Khuya",
// "Ghé Compound Garment").
//
// Root cause (confirmed by reading, not guessed): migration 020's demo seed
// assigns each of its ~20 catalogue events its OWN organizer row, owned by
// one of 3 fixed test accounts chosen uniformly at random per event — so a
// single account can end up owning several DISTINCT organizer businesses
// (dotrung1998@gmail.com owns 6: Vườn Sau, Phở Khuya, Compound Garment,
// OBJoff, Zone Publishing, Gác). Dashboard.jsx's "myEvents" used to filter
// on `myOrgEventKeys`, the FULL union of every event across every organizer
// row the signed-in account owns — while the header above it brands only
// ONE of those organizers (`myOrganizerId`, deterministically the
// earliest-created row). So every one of the account's organizers' events
// appeared under just the one branded name. EventDetail's own "Ghé" line
// was never wrong — it always joins each event's own real `organizer_id`
// (see loadRealEventsById/loadWeekendEvents in BanBeContext.jsx) — so this
// was a genuine query-SCOPE bug in Dashboard.jsx, not a bad FK and not an
// EventDetail display bug. No database rows needed changing; the fix is a
// client-side filter (Dashboard.jsx's `myOrgEventKeysForEv`, backed by a
// new `myOrgEventOrganizerId` map BanBeContext.jsx's loadMyEvents populates
// alongside the existing ownership-gate list, which is deliberately left
// untouched — openNotification()/openVerificationDetail() still need the
// FULL union for their own real per-event ownership gate).
//
// Drives the real, designated seed test account dotrung1998@gmail.com
// (migration 020's own comment names it as one of exactly 3 fixed test
// accounts — not a real user's) via an injected signInWithPassword()
// session, the same convention tests/e2e/event-review-queue-e2e.spec.js
// already established for a designated account whose UI login is out of
// scope here. Read-only against organizers/events — this test never
// mutates any of that account's real seed data, only its own password
// (same "normal for a designated test account" reset setup.mjs's own
// ensureAdminAccount() already documents).
//
// Gated on SUPABASE_SERVICE_ROLE_KEY. Not part of the default fast suite:
//   npx playwright test tests/e2e/dashboard-organizer-identity-e2e.spec.js
import { test, expect } from '@playwright/test';
import { hasServiceRole, adminClient, signIn } from './setup.mjs';
import { setupToHome } from '../helpers.js';

const SKIP_REASON = 'requires SUPABASE_SERVICE_ROLE_KEY (+ VITE_SUPABASE_ANON_KEY) — see tests/e2e/setup.mjs';
const TEST_EMAIL = 'dotrung1998@gmail.com';
const TEST_PASSWORD = 'BanbeE2e!Test1234'; // matches setup.mjs's TEST_PASSWORD convention

test.describe('Dashboard organizer-identity scope — real backend E2E', () => {
  /** @type {ReturnType<typeof adminClient>} */
  let admin;
  /** @type {string} */
  let uid;
  /** @type {{ id: string, name: string }} */
  let primaryOrg;
  /** @type {string} */
  let primaryEventId;
  /** @type {{ id: string, orgId: string, orgName: string }[]} */
  let excludedEvents;

  test.beforeAll(async () => {
    if (!hasServiceRole()) return;
    admin = adminClient();

    const { data: registryRow } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', TEST_EMAIL).maybeSingle();
    uid = registryRow?.auth_user_id;
    expect(uid, `${TEST_EMAIL} must already exist (migration 020's seed)`).toBeTruthy();
    await admin.auth.admin.updateUserById(uid, { password: TEST_PASSWORD });

    // Real, live read of every organizer this account owns — same `.or(...)`
    // BanBeContext.jsx's loadMyEvents()/syncUser() use, plus the same
    // deterministic tie-break (`created_at` then `id`, both ascending) the
    // app itself now applies, so this test's expectation is derived from
    // the exact same rule the app uses, never a hardcoded name.
    const { data: organizers, error: orgErr } = await admin.from('organizers')
      .select('id, name, created_at')
      .or(`owner_id.eq.${uid},user_id.eq.${uid}`)
      .order('created_at', { ascending: true })
      .order('id', { ascending: true });
    expect(orgErr, `organizers read failed: ${orgErr?.message}`).toBeNull();
    expect((organizers || []).length, `${TEST_EMAIL} must own >1 organizer row for this regression (migration 020's random per-event assignment)`).toBeGreaterThan(1);
    primaryOrg = organizers[0];

    const orgIds = organizers.map(o => o.id);
    // Restricted to migration 020's own static demo-catalogue ids (see
    // src/data/events.js) — Dashboard.jsx's branded shelf only ever renders
    // catalogue-matched keys (a separate, pre-existing web/iOS parity gap:
    // web's Dashboard never lists a real, non-catalogue host-created event
    // at all, catalogue or not — out of scope here). Excludes any
    // ad hoc real-event fixture other test files/manual QA may have left
    // under these same organizers (e.g. `test-real-event-*`), which aren't
    // click-reachable the same way and would make this test flaky for
    // reasons unrelated to the actual regression.
    const { data: events, error: evErr } = await admin.from('events')
      .select('id, name, organizer_id, status')
      .in('organizer_id', orgIds)
      .in('status', ['live', 'ended'])
      .not('id', 'like', 'test-%')
      .not('id', 'like', 'e2e-%');
    expect(evErr, `events read failed: ${evErr?.message}`).toBeNull();

    const orgNameById = Object.fromEntries(organizers.map(o => [o.id, o.name]));
    const primaryEvent = (events || []).find(e => e.organizer_id === primaryOrg.id);
    expect(primaryEvent, `primary organizer ${primaryOrg.id} must own at least one live/ended event`).toBeTruthy();
    primaryEventId = primaryEvent.id;

    // At least one real event from a DIFFERENT one of this account's own
    // organizers — these must NOT appear on the branded dashboard above.
    const seenOrgIds = new Set();
    excludedEvents = [];
    for (const e of events || []) {
      if (e.organizer_id === primaryOrg.id || seenOrgIds.has(e.organizer_id)) continue;
      seenOrgIds.add(e.organizer_id);
      excludedEvents.push({ id: e.id, name: e.name, status: e.status, orgId: e.organizer_id, orgName: orgNameById[e.organizer_id] });
    }
    expect(excludedEvents.length, 'need at least one other-organizer event to assert exclusion').toBeGreaterThan(0);
    // MapExplore's own search (used below to reach EventDetail for one
    // excluded event) only ever surfaces `status = 'live'` rows
    // (fetchLiveEvents, MapExplore.jsx) — sort a genuinely-live one first
    // so that step doesn't depend on which of these seed events has
    // already ticked over to 'ended' as of whenever this runs.
    excludedEvents.sort((a, b) => (a.status === 'live' ? -1 : 1) - (b.status === 'live' ? -1 : 1));
  });

  test.afterAll(async () => {
    // No seed data was ever mutated (read-only above) — nothing to restore
    // except this designated test account's own password isn't reverted
    // either, matching setup.mjs's own established convention for
    // banbetestadmin@gmail.com (a fixed, known password is the point).
  });

  async function signedInPage(browser) {
    const { session } = await signIn(TEST_EMAIL, TEST_PASSWORD);
    const projectRef = new URL(process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL).hostname.split('.')[0];
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
    return { page, context };
  }

  test('Dashboard lists only the branded organizer\'s own events; excluded events show their OWN real organizer on EventDetail', async ({ browser }) => {
    test.skip(!hasServiceRole(), SKIP_REASON);

    const { page, context } = await signedInPage(browser);
    try {
      await page.getByTestId('tab-profile').click();
      await page.waitForSelector('[data-screen-label="Account"]');
      await expect(page.getByTestId('organizer-mode-toggle')).toBeVisible({ timeout: 8000 });
      await page.getByTestId('account-tab-host').click();

      const orgCard = page.getByTestId('org-profile-card');
      await expect(orgCard).toBeVisible({ timeout: 8000 });
      await orgCard.click();
      const dashboard = page.locator('[data-screen-label="Organizer dashboard"]');
      await expect(dashboard).toBeVisible({ timeout: 5000 });

      // The header brands exactly the primary organizer computed above.
      await expect(dashboard.locator('h1')).toHaveText(primaryOrg.name);

      // The primary organizer's own real event IS listed (either shelf —
      // dashboard-add-photo-<id> renders in both upcoming and past rows).
      await expect(page.getByTestId(`dashboard-add-photo-${primaryEventId}`)).toBeVisible({ timeout: 5000 });

      // Every other organizer this account owns must NOT be listed here —
      // this is the actual regression: before the fix, these all showed up
      // under the primary organizer's own branded header.
      for (const ev of excludedEvents) {
        await expect(page.getByTestId(`dashboard-add-photo-${ev.id}`), `event ${ev.id} (real organizer: ${ev.orgName}) must not appear under ${primaryOrg.name}'s dashboard`).toHaveCount(0);
      }

      // Now confirm EventDetail's OWN "Ghé <organizer>" for one excluded
      // event resolves to its real, DIFFERENT organizer — never the
      // dashboard's own primary organizer name, and never blank/wrong.
      const other = excludedEvents[0];
      // Dashboard is one of the flow screens that deliberately hides the
      // bottom tab bar (BottomTabBar.jsx's BAR_SCREENS) — back out to
      // Account first, where `tab-map` actually renders.
      await dashboard.getByText('‹').click();
      await page.waitForSelector('[data-screen-label="Account"]', { timeout: 8000 });
      await page.getByTestId('tab-map').click();
      await page.waitForSelector('[data-screen-label="MapExplore"]', { timeout: 8000 });
      const searchInput = page.getByTestId('map-search-input');
      await expect(searchInput).toBeVisible({ timeout: 8000 });
      await searchInput.fill(other.name);
      const listItem = page.getByTestId(`map-list-item-${other.id}`);
      await expect(listItem).toBeVisible({ timeout: 8000 });
      await listItem.click();
      // Clicking a list item only selects it (the bottom preview card,
      // "Xem chi tiết") — MapExplore.jsx's own openEventDetail() actually
      // navigates on that CTA, not the list row itself.
      await page.getByTestId('map-card-cta').click();
      const eventScreen = page.locator('[data-screen-label="Event"]');
      await expect(eventScreen).toBeVisible({ timeout: 8000 });
      await expect(eventScreen.getByText(other.orgName, { exact: false })).toBeVisible();
      await expect(eventScreen.getByText(primaryOrg.name, { exact: true })).toHaveCount(0);
    } finally {
      await context.close();
    }
  });
});

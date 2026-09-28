// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';
import { hasServiceRole, adminClient } from './e2e/setup.mjs';

// Account IA + Home quick search pass (2026-09-27).

test.describe('Account — grouped entry cards, role-gated', () => {
  // Serial: the third test flips the shared test account's own
  // organizer_mode_enabled/role mid-run — running in parallel with the
  // second test (which asserts those same group cards are ABSENT for a
  // plain attendee) against that same shared account is a genuine
  // cross-test race, not a real bug (confirmed: all 4 pass reliably with
  // --workers=1; only concurrent execution flakes).
  test.describe.configure({ mode: 'serial' });

  test('Cá nhân: identity card is first, group cards open their own child screen', async ({ page }) => {
    await setupToHome(page);
    await page.getByTestId('tab-profile').click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible();

    const panel = page.locator('[data-testid="account-tab-panel-personal"]');
    // Identity card renders before the group cards in DOM order.
    const cardBox = await panel.getByTestId('account-profile-card').boundingBox();
    const teamBox = await panel.getByTestId('account-group-team').boundingBox();
    expect(cardBox.y).toBeLessThan(teamBox.y);
    // Going/Saved sit between the identity card and the group cards.
    const goingBox = await panel.getByTestId('account-going-card').boundingBox();
    expect(goingBox.y).toBeGreaterThan(cardBox.y);
    expect(goingBox.y).toBeLessThan(teamBox.y);

    await page.getByTestId('account-group-payments').click();
    await expect(page.locator('[data-screen-label="AccountGroup"]')).toBeVisible();
    await expect(page.getByTestId('account-invoices')).toBeVisible();
    await expect(page.getByTestId('account-receipts')).toBeVisible();

    await page.getByTestId('account-group-back').click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible();
    // accountTab is preserved across the round trip.
    await expect(page.locator('[data-testid="account-tab-panel-personal"]')).toBeVisible();
  });

  test('hostOps/adminReview group cards never show for a plain attendee', async ({ page }) => {
    await setupToHome(page);
    await page.getByTestId('tab-profile').click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible();
    await expect(page.getByTestId('account-group-hostOps')).toHaveCount(0);
    await expect(page.getByTestId('account-group-adminReview')).toHaveCount(0);
    // Nor is Admin/Host even a reachable tab.
    await expect(page.getByTestId('account-tab-host')).toHaveCount(0);
    await expect(page.getByTestId('account-tab-admin')).toHaveCount(0);
  });

  test('organizer mode on: hostOps group card reaches the exact same host-management actions', async ({ page }) => {
    test.skip(!hasServiceRole(), 'requires service role to flip role/organizer_mode_enabled');
    const admin = adminClient();
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    await admin.from('profiles').update({ role: 'organizer', organizer_mode_enabled: true }).eq('id', data.auth_user_id);

    await setupToHome(page);
    await page.getByTestId('tab-profile').click();
    await page.getByTestId('account-tab-host').click();
    await expect(page.getByTestId('account-group-hostOps')).toBeVisible();
    await page.getByTestId('account-group-hostOps').click();
    await expect(page.getByTestId('host-verifications')).toBeVisible();
    await expect(page.getByTestId('host-payout')).toBeVisible();

    await admin.from('profiles').update({ role: 'participant', organizer_mode_enabled: false }).eq('id', data.auth_user_id);
  });
});

test.describe('Home — quick event search entry', () => {
  test('opens MapExplore with the search field focused and filters real events by name', async ({ page }) => {
    await setupToHome(page);
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();

    await page.getByTestId('home-search-fab').click();
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    const input = page.getByTestId('map-search-input');
    // Real-device follow-up (2026-09-28) — this must hold with NO second
    // tap/focus() of any kind on the input anywhere above or below this
    // line: the single `home-search-fab` click above is the only
    // interaction that's supposed to be needed. `toBeFocused()` polls
    // (Playwright's built-in retrying assertion, never a fixed sleep)
    // until the transition settles and the field is genuinely focused.
    await expect(input).toBeFocused();
    // Belt-and-suspenders: the real DOM `document.activeElement` itself
    // (not just Playwright's own focus bookkeeping) is this exact input,
    // confirmed via polling rather than a one-shot read.
    await expect.poll(() => page.evaluate(() =>
      document.activeElement?.getAttribute('data-testid')
    )).toBe('map-search-input');

    // A real, live-loaded event's own name (seeded demo data, migration
    // 020) — never an invented/fabricated result.
    await page.locator('[data-testid^="map-list-item-"]').first().waitFor({ timeout: 10000 });
    const firstName = await page.locator('[data-testid^="map-list-item-"]').first().locator('div').first().innerText();
    const term = firstName.slice(0, Math.min(4, firstName.length));

    await input.fill(term);
    await expect(page.locator(`[data-testid^="map-list-item-"]:has-text("${term}")`).first()).toBeVisible({ timeout: 5000 });

    // A nonsense query yields the honest "no results" state, not a blank
    // panel or invented rows.
    await input.fill('zzzznonexistenteventzzzz');
    await expect(page.getByTestId('map-search-no-results')).toBeVisible();
    await expect(page.locator('[data-testid^="map-list-item-"]')).toHaveCount(0);

    await input.fill('');
    await page.getByTestId('map-back').click();
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
  });

  // Real-device follow-up (2026-09-28) — the OLD top-header search icon
  // (data-testid="home-search-button", beside the wordmark) was reported
  // still visible on a real iPhone after the dock/search relocation commit.
  // Turned out the web fix itself was already correct (the icon really is
  // gone, replaced by `home-search-fab`) — the real gap was iOS, which never
  // got touched at all (see apps/ios/BanbeApp/Views/HomeView.swift). This
  // negative assertion guards the web side against ever silently
  // reintroducing that old element, and confirms the fab is a true
  // fixed-position sibling unaffected by Home's own scroll position — the
  // exact containing-block bug class (a transform-holding ancestor from an
  // animation's fill-mode) already found once in this codebase for the
  // Pulse teaser bubble (see Home.jsx's own PulseTeaserBubble doc comment).
  test('old header search icon is gone, and the floating fab is unaffected by Home scroll', async ({ page }) => {
    await setupToHome(page);
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();

    // Negative assertion — a regression can't silently reintroduce the old
    // header icon without this failing.
    await expect(page.getByTestId('home-search-button')).toHaveCount(0);

    const fab = page.getByTestId('home-search-fab');
    await expect(fab).toBeVisible();
    const scrollViewport = page.locator('[data-testid="app-scroll-viewport"]');

    // A small scroll (below the 4px hide-on-scroll-down threshold, see
    // Home.jsx's own searchFabHidden effect) must leave the fab's on-screen
    // rect completely unchanged — it is `position: fixed` against the
    // viewport, never against Home's own (scrolled) content box.
    const before = await fab.boundingBox();
    await scrollViewport.evaluate((el) => { el.scrollTop = 2; });
    const afterTinyScroll = await fab.boundingBox();
    expect(afterTinyScroll).toEqual(before);

    // A real scroll-down hides it (intentional hide/reveal-on-scroll
    // behavior, matching the dock's own shrink-on-scroll-down convention —
    // see Home.jsx's own doc comment on searchFabHidden) — but scrolling
    // back to the top must restore the EXACT same fixed rect, not a
    // position drifted by however far the content itself scrolled.
    await scrollViewport.evaluate((el) => { el.scrollTop = el.scrollHeight; });
    await expect(fab).toHaveCSS('opacity', '0');
    await scrollViewport.evaluate((el) => { el.scrollTop = 0; });
    await expect(fab).toBeVisible();
    // The reveal itself is a 0.22s CSS transition (translateY/scale/opacity
    // — see Home.jsx's own searchFabHidden style) — poll rather than a
    // single immediate read, so this doesn't race a mid-transition frame.
    await expect.poll(() => fab.boundingBox()).toEqual(before);
  });
});

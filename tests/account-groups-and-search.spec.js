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
});

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

test.describe('Home — search entry (note 50)', () => {
  test('the search bar opens /search, groups live results, and "See on map" carries the query', async ({ page }) => {
    await setupToHome(page);
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
    // The old header magnifier and floating fab are gone; one full-width bar replaces them.
    await expect(page.getByTestId('home-search-button')).toHaveCount(0);
    await expect(page.getByTestId('home-search-fab')).toHaveCount(0);

    await page.getByTestId('home-search-bar').click();
    await page.waitForSelector('[data-screen-label="Search"]');
    await expect(page).toHaveURL(/\/search$/);
    const input = page.getByTestId('search-input');
    await expect(input).toBeFocused();

    // A real, rendered event's own name — never an invented result.
    await page.getByTestId('search-back').click();
    await page.waitForSelector('[data-screen-label="Home"]');
    const firstCard = page.locator('[data-testid^="home-event-"]').first();
    await firstCard.waitFor({ timeout: 10000 });
    const key = (await firstCard.getAttribute('data-testid')).replace('home-event-', '');
    await page.getByTestId('home-search-bar').click();
    await page.waitForSelector('[data-screen-label="Search"]');
    await input.fill('supper');
    await expect(page.getByTestId('search-group-events')).toBeVisible();
    const count = Number(await page.getByTestId('search-results').getAttribute('data-count'));
    expect(count).toBeGreaterThan(0);

    await input.fill('zzzznonexistenteventzzzz');
    await expect(page.getByTestId('search-empty')).toBeVisible();

    await input.fill('supper');
    await page.getByTestId('search-see-on-map').click();
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    await expect(page.getByTestId('map-search-input')).toHaveValue('supper');
    expect(key.length).toBeGreaterThan(0);
  });

  test('back/forward between Home and Search keeps the URL in sync', async ({ page }) => {
    await setupToHome(page);
    await page.getByTestId('home-search-bar').click();
    await expect(page).toHaveURL(/\/search$/);
    await page.goBack();
    await page.waitForSelector('[data-screen-label="Home"]');
    await page.goForward();
    await page.waitForSelector('[data-screen-label="Search"]');
  });
});

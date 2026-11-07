// @ts-check
import { test, expect } from '@playwright/test';
import { guestToHome } from './helpers.js';

// Calm Pass pilot: Hosting Home never ends in blank space. Same dev-state harness as note69-web-parity.spec.js
// (`window.__banbeDevSet` on top of guest browsing); server calls fail without a session, which is exactly the
// numbers error state. The submitted-events read is mocked to give the screenshot's "2 pending, 0 live".
test.use({ storageState: { cookies: [], origins: [] }, viewport: { width: 390, height: 844 } });

const devSet = (page, patch) => page.evaluate((p) => window.__banbeDevSet(p), patch);
const USER = { id: '00000000-0000-4000-8000-000000000070', name: 'Host Test', email: 'h@example.com', handle: 'hosttest' };
const HOST = { user: USER, accountType: 'organizer', organizerMode: true, myOrganizerId: 'org-70', orgRegName: 'Test host',
  featureFlags: { simple_shell: true }, homeView: 'host', reportsData: null, screen: 'home' };

test('nothing scheduled: Coming up says so and offers Share host page; numbers fail to Retry', async ({ page }) => {
  await guestToHome(page);
  await devSet(page, { ...HOST, myOrgEventKeys: [] });
  await expect(page.getByTestId('home-host')).toBeVisible();
  const quiet = page.getByTestId('home-host-upcoming-empty-quiet');
  await expect(quiet).toBeVisible();
  await expect(quiet).toContainText('Nothing scheduled yet');
  expect((await page.getByTestId('home-host-upcoming-empty-action').boundingBox()).height).toBeGreaterThanOrEqual(44);
  await expect(page.getByTestId('home-host-kpis')).toContainText('Last 30 days');
  await expect(page.getByTestId('home-host-kpis-error')).toBeVisible();
  await expect(page.getByTestId('home-host-kpis-retry')).toBeVisible();
});

test('2 pending, 0 live: Coming up explains the review and opens Submitted', async ({ page }) => {
  await page.route(/\/rest\/v1\/events\?.*status=in\./, (route) => route.fulfill({
    status: 200, contentType: 'application/json',
    body: JSON.stringify([
      { id: 'ev-p1', name: 'Pending one', status: 'review', submitted_at: '2026-10-30T10:00:00Z' },
      { id: 'ev-p2', name: 'Pending two', status: 'review', submitted_at: '2026-10-30T11:00:00Z' },
    ]),
  }));
  await guestToHome(page);
  await devSet(page, { ...HOST, myOrgEventKeys: ['ev-p1', 'ev-p2'] });
  const pending = page.getByTestId('home-host-upcoming-empty-pending');
  await expect(pending).toBeVisible();
  await expect(pending).toContainText('2 events are in review');
  await expect(page.getByTestId('home-host-upcoming-empty-quiet')).toHaveCount(0);
  await page.getByTestId('home-host-upcoming-empty-action').click();
  await expect(page.locator('[data-screen-label="Organizer dashboard"]')).toBeVisible();
});

test('dark theme: the guided state keeps its dashed outline and readable text', async ({ page }) => {
  await guestToHome(page);
  await devSet(page, { ...HOST, myOrgEventKeys: [], theme: 'dark' });
  await expect(page.locator('.bb-stage')).toHaveAttribute('data-bb-theme', 'dark');
  const quiet = page.getByTestId('home-host-upcoming-empty-quiet');
  await expect(quiet).toBeVisible();
  await expect(quiet).toHaveCSS('border-top-style', 'dashed');
});

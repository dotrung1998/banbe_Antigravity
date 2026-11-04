// @ts-check
import { test, expect } from '@playwright/test';
import { guestToHome } from './helpers.js';

// Admin "Project hub demo" (note 76, migration 216, switch project_hub_demo). The admin identity and the switch are put
// in place with the dev-only state setter (window.__banbeDevSet) on top of guest browsing; the demo itself is opened the
// real way (Account > Review & moderation > row > picker > Open demo). While the demo is open no request may reach
// /rest/v1/rpc/ or /storage/. Run without the service-role key:
//   SUPABASE_SERVICE_ROLE_KEY= npx playwright test tests/project-demo.spec.js
test.use({ storageState: { cookies: [], origins: [] }, viewport: { width: 390, height: 844 } });

const ADMIN = '7a1b2c3d-0000-4000-8000-00000000abcd';
const TASK02 = '00000000-0000-4000-8000-000000000302';
const devSet = (page, patch) => page.evaluate((x) => window.__banbeDevSet(x), patch);

async function toAdminList(page, { accountType = 'admin', demoSwitch = true } = {}) {
  await guestToHome(page);
  await devSet(page, { lang: 'en' });
  await devSet(page, { user: { id: ADMIN, name: 'Test Admin', email: 'a@example.com', handle: 'banbeadmin' }, accountType });
  await page.waitForTimeout(1500); // a new user reloads the switches; set ours after that answer lands
  await page.evaluate((on) => window.__banbeDevSet(prev => ({
    // The project switches stay OFF outside the demo, like production today.
    featureFlags: { ...prev.featureFlags, project_hub_demo: on, event_project_hub: false, project_qr_invite: false,
      project_delegate_checkin: false, project_delegate_payments: false, project_delegate_refunds: false },
  })), demoSwitch);
  await devSet(page, { accountType, screen: 'accountGroup', accountGroupKey: 'adminReview', accountGroupBack: null });
  await expect(page.locator('[data-screen-label="AccountGroup"]')).toBeVisible();
}

/** Every request to Supabase RPC or storage from now on. */
function watchServer(page) {
  const hits = [];
  const on = (req) => { const u = req.url(); if (u.includes('/rest/v1/rpc/') || u.includes('/storage/')) hits.push(`${req.method()} ${u}`); };
  page.on('request', on);
  return { hits, stop: () => page.off('request', on) };
}

async function openDemo(page, { as = 'host', eventDay = false } = {}) {
  await page.getByTestId('admin-project-demo').click();
  await expect(page.getByTestId('project-demo-picker')).toBeVisible();
  await page.getByTestId(`project-demo-as-${as}`).click();
  await expect(page.getByTestId(`project-demo-as-${as}`)).toHaveAttribute('aria-pressed', 'true');
  if (eventDay) await page.getByTestId('project-demo-event-day').check();
  await page.getByTestId('project-demo-open').click();
  await expect(page.getByTestId('project-hub')).toBeVisible();
  await expect(page.getByTestId('project-demo-banner-title')).toHaveText('Demo · sample data · nothing is saved');
}

test.describe('Project hub demo (admin, web)', () => {
  test('admin with the switch on: row, open as Host, writes stay local, links out are stopped, Exit clears', async ({ page }) => {
    await toAdminList(page);
    await expect(page.getByTestId('admin-project-demo-title')).toHaveText('Project hub demo');
    await expect(page.getByTestId('admin-project-demo')).toContainText('Sample data. Nothing is saved.');
    const net = watchServer(page);
    await openDemo(page, { as: 'host' });
    await expect(page).toHaveURL(/\/admin\/project-demo$/);
    await expect(page.getByTestId('project-overview-readiness')).toBeVisible();

    await page.getByTestId('project-tab-tasks').click();
    await page.getByTestId(`project-task-tick-${TASK02}`).click();
    await expect(page.getByTestId(`project-task-tick-${TASK02}`)).toHaveAttribute('data-status', 'done');

    await page.getByTestId('project-tab-money').click();
    await expect(page.getByTestId('project-money-tab')).toBeVisible();
    await page.getByTestId('project-money-verify').click();
    await expect(page.getByTestId('project-notice')).toContainText('Not available in the demo.');
    await expect(page.getByTestId('project-hub')).toBeVisible();

    await page.getByTestId('project-tab-overview').click();
    await page.getByTestId('project-channel-link').first().click();
    await expect(page.getByTestId('project-notice')).toContainText('Not available in the demo.');
    expect(page.context().pages()).toHaveLength(1);

    await page.getByTestId('project-demo-exit').click();
    await expect(page.getByTestId('project-hub')).toHaveCount(0);
    await expect(page.getByTestId('admin-project-demo')).toBeVisible();
    await expect(page).toHaveURL(/\/profile\/group\/adminReview$/);
    net.stop();
    expect(net.hits, 'nothing reached RPC or storage while the demo was open').toEqual([]);

    // Exit cleared the demo: a fresh open starts from the untouched sample (the ticked task is back to its first state).
    await openDemo(page, { as: 'host' });
    await page.getByTestId('project-tab-tasks').click();
    await expect(page.getByTestId(`project-task-tick-${TASK02}`)).not.toHaveAttribute('data-status', 'done');
  });

  test('open as Finance & door: money and door work inside the demo though the switches are off; Back leaves the demo', async ({ page }) => {
    await toAdminList(page);
    const net = watchServer(page);
    await openDemo(page, { as: 'finance' });
    await page.getByTestId('project-tab-money').click();
    await expect(page.getByTestId('project-payments')).toBeVisible();
    await expect(page.getByTestId('project-door')).toBeVisible();
    await page.getByTestId('project-payments-confirm-pay-1').click();
    await expect(page.getByTestId('project-payments-confirm-pay-1')).toHaveCount(0);
    await expect(page.getByTestId('project-payments-confirmed')).toContainText('5.390.000');
    await page.getByTestId('project-back').click();
    await expect(page.getByTestId('project-hub')).toHaveCount(0);
    await expect(page.getByTestId('admin-project-demo')).toBeVisible();
    net.stop();
    expect(net.hits).toEqual([]);
  });

  test('event day: the demo clock sits on the event day (Day-of live mode)', async ({ page }) => {
    await toAdminList(page);
    const net = watchServer(page);
    await openDemo(page, { as: 'helper', eventDay: true });
    await expect(page.getByTestId('project-dayof-tab')).toBeVisible();
    await expect(page.getByTestId('project-dayof-tab')).toContainText('Live now');
    await page.waitForTimeout(500);
    await page.getByTestId('project-demo-exit').click();
    net.stop();
    expect(net.hits).toEqual([]);
  });

  test('a non-admin with the switch on sees no row', async ({ page }) => {
    await toAdminList(page, { accountType: 'participant' });
    await page.waitForTimeout(500);
    await expect(page.getByTestId('admin-project-demo')).toHaveCount(0);
  });

  test('an admin with the switch off sees no row', async ({ page }) => {
    await toAdminList(page, { demoSwitch: false });
    await expect(page.getByTestId('admin-features')).toBeVisible();
    await expect(page.getByTestId('admin-project-demo')).toHaveCount(0);
  });
});

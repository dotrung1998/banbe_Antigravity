// @ts-check
import { test, expect } from '@playwright/test';
import { guestToHome } from './helpers.js';

// Note 69 web parity. Signed-in layouts are rendered from the dev-only state setter (`window.__banbeDevSet`,
// BanBeContext.jsx) on top of guest browsing, so these specs never depend on the shared test account (held by the
// DOB gate, note 49). Server calls fail quietly without a session; only layout and wiring are checked here.
test.use({ storageState: { cookies: [], origins: [] }, viewport: { width: 390, height: 844 } });

const SHOTS = process.env.NOTE69_SHOTS || '';
const shot = async (page, name) => { if (SHOTS) await page.screenshot({ path: `${SHOTS}/${name}.png` }); };
const devSet = (page, patch) => page.evaluate((p) => window.__banbeDevSet(p), patch);
const USER = { id: '00000000-0000-4000-8000-000000000069', name: 'Nguyễn Thị Phương Thảo Long Name', email: 't@example.com', handle: 'banbetest' };

async function openAccount(page, { admin = false, hosting = false } = {}) {
  await guestToHome(page);
  await devSet(page, {
    user: USER, accountType: admin ? 'admin' : (hosting ? 'organizer' : 'participant'), organizerMode: hosting,
    myOrganizerId: hosting ? 'org-69' : null, orgRegName: 'Test host', screen: 'profile',
  });
  await expect(page.locator('[data-screen-label="Account"]')).toBeVisible();
}

test.describe('Account tabs follow Hosting mode', () => {
  test('hosting off, not admin: one page, labelled groups, no More', async ({ page }) => {
    await openAccount(page);
    await expect(page.getByTestId('account-tabs')).toHaveCount(0);
    await expect(page.getByTestId('account-group-activity')).toBeVisible();
    await expect(page.getByTestId('account-group-app')).toBeVisible();
    await expect(page.getByTestId('account-section-more')).toHaveCount(0);
    await expect(page.getByTestId('account-sign-out')).toHaveCount(1);
    await shot(page, 'account-goer');
  });

  test('hosting off, admin: Personal + Admin', async ({ page }) => {
    await openAccount(page, { admin: true });
    await expect(page.getByTestId('account-tab-personal')).toHaveAttribute('aria-selected', 'true');
    await expect(page.getByTestId('account-tab-host')).toHaveCount(0);
    await page.getByTestId('account-tab-admin').click();
    await expect(page.getByTestId('account-group-adminReview')).toBeVisible();
    await expect(page.getByTestId('account-admin-guide')).toBeVisible();
    await shot(page, 'account-admin-tab');
  });

  test('hosting on, admin: Host first and selected, then Personal, then Admin', async ({ page }) => {
    await openAccount(page, { admin: true, hosting: true });
    const tabs = page.getByTestId('account-tabs').getByRole('tab');
    await expect(tabs).toHaveText([/Host/, /Personal/, /Admin/]);
    await expect(page.getByTestId('account-tab-host')).toHaveAttribute('aria-selected', 'true');
    await expect(page.getByTestId('account-group-host-tools')).toBeVisible();
    await expect(page.getByTestId('account-sign-out')).toHaveCount(0);
    await shot(page, 'account-host-tab');
    await page.getByTestId('account-tab-personal').click();
    await expect(page.getByTestId('account-profile-card')).toBeVisible();
    await expect(page.getByTestId('account-sign-out')).toHaveCount(1);
  });

  test('profile card: long name on two lines, the whole card opens the profile, Rename still renames', async ({ page }) => {
    await openAccount(page);
    const name = page.getByTestId('account-profile-name');
    const lh = await name.evaluate(el => parseFloat(getComputedStyle(el).lineHeight));
    const h = (await name.boundingBox()).height;
    expect(h).toBeGreaterThan(lh * 1.5);   // wraps instead of being cut to one line
    await page.getByTestId('account-rename').click();
    await expect(page.locator('[data-screen-label="Account"]')).toHaveCount(0);
    await devSet(page, { screen: 'profile' });
    // Anywhere on the card, not only the ›: the @handle line.
    await page.getByTestId('account-profile-card').getByText('@banbetest').click();
    await expect(page.locator('[data-screen-label="Account"]')).toHaveCount(0);
  });
});

test.describe('Rewards can be found', () => {
  test('admin: Rewards v2 on while Rewards is off says it has no effect, and asks to turn both on', async ({ page }) => {
    await guestToHome(page);
    // The RPC needs a real admin session; answer it so only the UI is under test.
    await page.route('**/rest/v1/rpc/admin_set_feature_flag', r => r.fulfill({ status: 200, contentType: 'application/json', body: '{"success":true}' }));
    await devSet(page, { user: USER, accountType: 'admin', featureFlags: { rewards: false, rewards_v2: true }, screen: 'adminFeatures' });
    await page.getByTestId('admin-cat-rewards-toggle').click();
    await expect(page.getByTestId('admin-flag-rewards_v2-state')).toHaveAttribute('data-blocked', 'true');
    await expect(page.getByTestId('admin-flag-rewards_v2-state')).toContainText('No effect yet');
    await shot(page, 'admin-requires');
    // Off, then on again: the dialog asks first.
    await devSet(page, { featureFlags: { rewards: false, rewards_v2: false } });
    await page.getByTestId('admin-flag-rewards_v2-switch').click();
    await expect(page.getByTestId('admin-flag-requires-dialog')).toBeVisible();
    await page.getByTestId('admin-flag-requires-both').click();
    await expect(page.getByTestId('admin-flag-rewards-state')).toContainText('Visible to everyone');
    await expect(page.getByTestId('admin-flag-rewards_v2-state')).not.toHaveAttribute('data-blocked', 'true');
  });

  test('Simple Shell Home › Going out shows the streak/coins capsule beside the search bar', async ({ page }) => {
    // The app reloads the summary for the signed-in user; answer it so the capsule stays.
    await page.route('**/rest/v1/rpc/get_my_reward_summary', r => r.fulfill({ status: 200, contentType: 'application/json',
      body: JSON.stringify({ success: true, balance: 120, streak: 3, active_today: true }) }));
    await guestToHome(page);
    await devSet(page, {
      user: USER, featureFlags: { simple_shell: true, rewards: true }, homeView: 'goer',
      rewardsSummaryStatus: 'loaded', rewardsSummary: { balance: 120, streak: 3, activeToday: true }, screen: 'home',
    });
    const capsule = page.getByTestId('home-reward-shortcuts');
    await expect(capsule).toBeVisible();
    const bar = await page.getByTestId('home-search-bar').boundingBox();
    const cap = await capsule.boundingBox();
    expect(Math.abs((cap.y + cap.height / 2) - (bar.y + bar.height / 2))).toBeLessThan(8);   // same row
    await shot(page, 'home-capsule');
    await page.getByTestId('home-coins').click();
    await expect(page.locator('[data-screen-label="Rewards"]')).toBeVisible();
  });
});

test.describe('Home › Hosting', () => {
  test('shortcuts scroll in place, This month loads on Home, a Pending tile opens Submitted expanded', async ({ page }) => {
    await guestToHome(page);
    const kpis = page.waitForRequest('**/rest/v1/rpc/get_account_kpis');
    await devSet(page, {
      user: USER, accountType: 'organizer', organizerMode: true, myOrganizerId: 'org-69', featureFlags: { simple_shell: true },
      homeView: 'host', reportsData: null, screen: 'home',
    });
    await expect(page.getByTestId('home-host')).toBeVisible();
    const req = await kpis;
    expect(req.postDataJSON().p_scope).toBe('host');   // no Reports visit needed
    const row = page.getByTestId('home-host-quick');
    await expect(row).toHaveAttribute('data-hscroll');   // the root tab swipe ignores drags here
    for (const id of ['guests', 'refunds', 'story', 'surveys']) {
      const box = await page.getByTestId(`home-host-quick-${id}`).boundingBox();
      expect(box.height).toBeGreaterThanOrEqual(44);
    }
    await expect(page.getByTestId('home-host-quick-create')).toHaveCount(0);   // the plan card has Create
    await shot(page, 'home-hosting');
    await page.getByTestId('home-host-submitted-pending').click();
    await expect(page.locator('[data-screen-label="Organizer dashboard"]')).toBeVisible();
  });
});

test.describe('Create event', () => {
  async function openCreate(page, cats = ['supper']) {
    await guestToHome(page);
    await devSet(page, {
      user: USER, accountType: 'organizer', organizerMode: true, myOrganizerId: 'org-69', orgRegName: 'Test host',
      featureFlags: { event_type_profiles: true }, createCats: cats, createDetails: {}, screen: 'create',
    });
    await expect(page.getByTestId('create-step-next')).toBeVisible();
    await page.getByTestId('create-step-next').click();   // Host -> Basics, part 1
    await expect(page.getByTestId('create-substeps')).toBeVisible();
  }

  test('Basics has its own part bar; Next walks the parts, then the steps', async ({ page }) => {
    await openCreate(page);
    await expect(page.getByTestId('create-substeps').locator('button')).toHaveCount(5);
    await expect(page.getByTestId('create-substeps-0')).toHaveAttribute('aria-current', 'step');
    await expect(page.getByTestId('create-name')).toBeVisible();
    await expect(page.getByTestId('create-intro')).toHaveCount(0);   // one part at a time
    await expect(page.getByTestId('create-step-next')).toContainText('Story');
    for (let i = 0; i < 5; i++) await page.getByTestId('create-step-next').click();
    await expect(page.getByTestId('create-substeps')).toHaveCount(0);   // When & where has no parts…
    await page.getByTestId('create-step-next').click();               // …Tickets does
    await expect(page.getByTestId('create-substeps').locator('button')).toHaveCount(4);
    await expect(page.getByTestId('create-price-input')).toBeVisible();
    await page.getByTestId('create-step-back').click();
    await expect(page.getByTestId('create-substeps')).toHaveCount(0);
    await page.getByTestId('create-step-back').click();               // back into Basics lands on its last part
    await expect(page.getByTestId('create-substeps-4')).toHaveAttribute('aria-current', 'step');
  });

  test('long fields are twice a one-line box, expand to full screen, Clear all asks first; intro style', async ({ page }) => {
    await openCreate(page);
    const nameH = (await page.getByTestId('create-name').boundingBox()).height;
    await page.getByTestId('create-substeps-1').click();
    const desc = page.getByTestId('create-desc');
    expect((await desc.boundingBox()).height).toBeGreaterThanOrEqual(nameH * 2 - 2);
    expect((await page.getByTestId('create-intro').boundingBox()).height).toBeGreaterThanOrEqual(nameH * 2 - 2);
    await page.getByTestId('create-intro-font-serif').click();
    await page.getByTestId('create-intro-color-clay').click();
    await expect(page.getByTestId('create-intro-font-serif')).toHaveAttribute('aria-checked', 'true');
    const family = await page.getByTestId('create-intro').evaluate(el => getComputedStyle(el).fontFamily);
    expect(family.toLowerCase()).toContain('serif');
    await shot(page, 'create-story');
    await page.getByTestId('create-expand-intro').click();
    const editor = page.getByTestId('create-longtext-editor');
    await expect(editor).toBeFocused();
    await editor.fill('Hello there');
    await page.getByTestId('create-longtext-clear').click();
    await expect(page.getByRole('alertdialog')).toBeVisible();
    await expect(editor).toHaveValue('Hello there');   // nothing cleared before confirming
    await page.getByTestId('create-longtext-clear-confirm').click();
    await expect(editor).toHaveValue('');
    await page.getByTestId('create-longtext-done').click();
    await expect(page.getByTestId('create-intro')).toHaveValue('');
  });

  test('two categories ask both types\' facts, shared ones once', async ({ page }) => {
    await openCreate(page, ['supper', 'music']);
    await page.getByTestId('create-substeps-4').click();
    await expect(page.getByTestId('create-detail-dietary-vegan')).toBeVisible();
    await expect(page.getByTestId('create-detail-lineup-add')).toBeVisible();   // the second category's own field
    await expect(page.getByTestId('create-detail-alcohol-byo')).toHaveCount(1);
    await shot(page, 'create-details-two-types');
  });
});

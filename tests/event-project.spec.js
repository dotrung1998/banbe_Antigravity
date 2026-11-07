// @ts-check
import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { guestToHome } from './helpers.js';

// Event Project Hub, web (note 76, phase 8). Rendered from the dev-only state setter (window.__banbeDevSet) on top of
// guest browsing, with the shared demo snapshot (tests/fixtures/project-snapshot.json, the same one the iOS UI tests
// use) and the hook's dev-only demo mode, so writes change the snapshot in memory and nothing reaches Supabase.
// Run without the service-role key (SUPABASE_SERVICE_ROLE_KEY= npx playwright test tests/event-project.spec.js) so the
// global setup never touches the shared test account.
test.use({ storageState: { cookies: [], origins: [] }, viewport: { width: 390, height: 844 } });

const SHOTS = process.env.PROJECT_SHOTS || '';
const shot = async (page, name) => { if (SHOTS) await page.screenshot({ path: `${SHOTS}/${name}.png` }); };
const FX = JSON.parse(readFileSync(new URL('./fixtures/project-snapshot.json', import.meta.url), 'utf8')).snapshot;
const ME = '00000000-0000-4000-8000-00000000f1f0';
const MEMBERS = { manager: '00000000-0000-4000-8000-000000000102', lead: '00000000-0000-4000-8000-000000000103', helper: '00000000-0000-4000-8000-000000000104', finance: '00000000-0000-4000-8000-000000000106' };
const TASK02 = '00000000-0000-4000-8000-000000000302', TASK05 = '00000000-0000-4000-8000-000000000305';
const PROPOSAL = '00000000-0000-4000-8000-000000000404', UPDATE = '00000000-0000-4000-8000-000000000402', QUESTION = '00000000-0000-4000-8000-000000000403';
const REQUEST = '00000000-0000-4000-8000-000000000701', AN = '00000000-0000-4000-8000-000000000604', SETUP = '00000000-0000-4000-8000-000000000501';
const devSet = (page, patch) => page.evaluate((x) => window.__banbeDevSet(x), patch);

/** The snapshot as the Host sees it, or re-cast so the viewer is one of the members (like the iOS fixture). */
function snapshotAs(role) {
  if (!role) return FX;
  let text = JSON.stringify(FX).split(ME).join('00000000-0000-4000-8000-0000000001ff').replace('"display_name":"Bạn"', '"display_name":"Lan"');
  text = text.split(MEMBERS[role]).join(ME);
  const snap = JSON.parse(text);
  const mine = snap.members.find(m => m.user_id === ME);
  return { ...snap, is_host: false, me: { member_id: mine.member_id, role: mine.role, lane_id: mine.lane_id, cap_money: mine.cap_money, cap_checkin: mine.cap_checkin, grant_expires_at: '2026-11-21T17:00:00+00:00' } };
}

async function openHub(page, { as, tab = 'overview', now = '2026-11-03T10:00:00+07:00', flags = {}, lang, refundApproval } = {}) {
  await guestToHome(page);
  if (lang) await devSet(page, { lang });
  await devSet(page, { user: { id: ME, name: 'Test Host', email: 't@example.com', handle: 'banbetest' } });
  await page.waitForTimeout(1500); // a new user reloads the switches; set ours after that answer lands
  await devSet(page, {
    featureFlags: { event_project_hub: true, ...flags }, projectDemo: true, projectNow: now,
    projectSnapshot: refundApproval ? { ...snapshotAs(as), project: { ...snapshotAs(as).project, refund_approval: refundApproval } } : snapshotAs(as),
    projectEventId: FX.event.id, projectTab: tab, projectBack: 'home', projectNotice: '', projectError: '', projectInvites: [], projectDoor: null, projectMoney: null, projectPayments: null, projectRefunds: null, screen: 'eventProject',
  });
  await expect(page.getByTestId('project-hub')).toBeVisible();
}

test.describe('Event Project Hub (web)', () => {
  test('six tabs, five visible at rest, the sixth by scrolling, positions read out', async ({ page }) => {
    await openHub(page);
    const box = await page.getByTestId('project-tabs').boundingBox();
    for (const id of ['overview', 'tasks', 'topics', 'team', 'money']) {
      const b = await page.getByTestId(`project-tab-${id}`).boundingBox();
      expect(b.x + b.width, `${id} visible`).toBeLessThanOrEqual(box.x + box.width + 1);
    }
    const sixth = await page.getByTestId('project-tab-dayof').boundingBox();
    expect(sixth.x + sixth.width, 'Day-of is not fully visible at rest (same check as iOS)').toBeGreaterThan(box.x + box.width + 1);
    await expect(page.getByTestId('project-tabs-more')).toHaveCount(1);
    await expect(page.getByTestId('project-tab-tasks')).toHaveAttribute('aria-label', 'Tasks, tab 2 of 6, needs attention');
    await shot(page, 'project-overview-host');
    await page.getByTestId('project-tab-dayof').click();
    await expect(page.getByTestId('project-dayof-tab')).toBeVisible();
    await expect(page.getByTestId('project-tabs-at-end')).toHaveCount(1);
  });

  test('Host overview: proposals, channels, readiness, attention; a helper only opens channels', async ({ page }) => {
    await openHub(page);
    await expect(page.getByTestId('project-overview-proposals')).toBeVisible();
    await expect(page.getByTestId('project-channels-edit')).toHaveText('Edit');
    await expect(page.getByTestId('project-overview-readiness')).toBeVisible();
    await expect(page.getByTestId('project-overview-attention')).toBeVisible();
    await page.getByTestId('project-overview-review').click();
    await expect(page.getByTestId(`project-proposal-approve-${REQUEST}`)).toBeVisible();
    await page.getByTestId(`project-proposal-approve-${REQUEST}`).click();
    // The approved lane is scrolled to and highlighted (the navigator strip also lists it, so match the section).
    await expect(page.locator('[data-lane-section][data-highlight="1"]')).toContainText('TRUYỀN THÔNG');
  });

  test('a helper cannot edit channels, add tasks or tick someone else’s task', async ({ page }) => {
    await openHub(page, { as: 'helper', tab: 'tasks' });
    await expect(page.getByTestId('project-add-task')).toHaveCount(0);
    await page.getByTestId(`project-task-tick-${TASK05}`).click();
    await expect(page.getByTestId('project-notice')).toBeVisible();
    await expect(page.getByTestId(`project-task-tick-${TASK05}`)).toHaveAttribute('data-status', 'blocked');
    await page.getByTestId('project-tab-overview').click();
    await expect(page.getByTestId('project-channels-edit')).toHaveCount(0);
  });

  test('the Host ticks and adds tasks', async ({ page }) => {
    await openHub(page, { tab: 'tasks' });
    await page.getByTestId(`project-task-tick-${TASK02}`).click();
    await expect(page.getByTestId(`project-task-tick-${TASK02}`)).toHaveAttribute('data-status', 'done');
    await page.getByTestId('project-add-task').click();
    await expect(page.getByTestId('project-add-task-lane')).toBeVisible();
    await page.getByTestId('project-add-task-task').click();
    await expect(page.getByTestId('project-task-usage')).toBeVisible();
    await page.getByTestId('project-task-title').fill('Buy ice');
    await page.getByTestId('project-task-save').click();
    await expect(page.getByText('Buy ice')).toBeVisible();
    await shot(page, 'project-tasks-host');
  });

  test('Topics: waiting on you, voting, seen, decide', async ({ page }) => {
    await openHub(page, { tab: 'topics' });
    const waiting = page.getByTestId('project-topics-waiting');
    await expect(waiting.getByTestId(`project-post-${PROPOSAL}`)).toBeVisible();
    await expect(waiting.getByTestId(`project-post-${UPDATE}`)).toBeVisible();
    await expect(waiting.getByTestId(`project-post-${QUESTION}`)).toHaveCount(0);
    await shot(page, 'project-topics-host');
    await page.getByTestId(`project-post-${PROPOSAL}`).click();
    await page.getByTestId('project-post-option-1').click();
    await expect(page.getByTestId('project-post-option-1')).toHaveAttribute('aria-label', /3 votes, your vote$/);
    await page.getByTestId('project-post-option-1').click();
    await expect(page.getByTestId('project-post-option-1')).toHaveAttribute('aria-label', /2 votes$/);
    await page.getByTestId('project-post-decide').click();
    await expect(page.getByText('Cá kho', { exact: true })).toBeVisible();
    await page.getByTestId(`project-post-${UPDATE}`).click();
    await page.getByTestId('project-post-seen').click();
    await expect(page.getByTestId('project-post-seen-done')).toBeVisible();
  });

  test('Topics: compose a question; a helper cannot post proposals or decisions', async ({ page }) => {
    await openHub(page, { tab: 'topics' });
    await page.getByTestId('project-new-post').click();
    await page.getByTestId('project-compose-type-question').click();
    await expect(page.getByTestId('project-compose-post')).toBeDisabled();
    await page.getByTestId('project-compose-title').fill('Who brings the ice?');
    await page.getByTestId(`project-compose-to-${MEMBERS.helper}`).click();
    await page.getByTestId('project-compose-post').click();
    await expect(page.getByText('Who brings the ice?')).toBeVisible();

    await openHub(page, { as: 'helper', tab: 'topics' });
    await page.getByTestId('project-new-post').click();
    await expect(page.getByTestId('project-compose-type-proposal')).toBeDisabled();
    await expect(page.getByTestId('project-compose-type-decision')).toBeDisabled();
    await expect(page.getByTestId('project-compose-type-update')).toBeEnabled();
  });

  test('the Manager replies to the question addressed to them and resolves it', async ({ page }) => {
    await openHub(page, { as: 'manager', tab: 'topics' });
    await page.getByTestId(`project-post-${QUESTION}`).click();
    await page.getByTestId('project-post-reply').fill('Yes, by the back door');
    await page.getByTestId('project-post-send').click();
    await expect(page.getByText('Yes, by the back door')).toBeVisible();
    await page.getByTestId('project-post-resolve').click();
    await expect(page.getByTestId('project-post-reply')).toHaveCount(0);
  });

  test('Team: the Host invites, cancels, changes a role; a Manager invites only leads and helpers', async ({ page }) => {
    await openHub(page, { tab: 'team' });
    await expect(page.getByTestId('project-team-matrix')).toBeVisible();
    await page.getByTestId('project-team-invite').click();
    await expect(page.getByTestId('project-invite-role-manager')).toBeVisible();
    await page.getByTestId('project-invite-create').click();
    await expect(page.getByTestId('project-invite-code')).toHaveText('BB-7K2Q');
    await shot(page, 'project-invite');
    await page.getByTestId('project-sheet-close').click();
    await expect(page.getByTestId('project-team-invites')).toBeVisible();
    await page.locator('[data-testid^="project-invite-revoke-"]').first().click();
    await expect(page.getByTestId('project-team-invites')).toHaveCount(0);
    await page.getByTestId(`project-member-${AN}`).click();
    await page.getByTestId('project-member-role-lane_lead').click();
    await page.getByTestId('project-member-save').click();
    await expect(page.getByTestId(`project-member-${AN}`)).toContainText('Lane lead');

    await openHub(page, { as: 'manager', tab: 'team' });
    await page.getByTestId('project-team-invite').click();
    await expect(page.getByTestId('project-invite-role-helper')).toBeVisible();
    await expect(page.getByTestId('project-invite-role-manager')).toHaveCount(0);
    await expect(page.getByTestId('project-invite-manager-note')).toBeVisible();
  });

  test('QR invites behind project_qr_invite: ready at once, multi-use replaces the code', async ({ page }) => {
    await openHub(page, { tab: 'team', flags: { project_qr_invite: true } });
    await expect(page.getByTestId('project-team-invite')).toContainText('Invite by QR');
    await page.getByTestId('project-team-invite').click();
    await expect(page.getByTestId('project-invite-qr')).toBeVisible();
    await expect(page.getByTestId('project-invite-create')).toHaveCount(0);
    await expect(page.getByTestId('project-invite-uses')).toContainText('single use');
    await page.getByTestId('project-invite-single').click();
    await expect(page.getByTestId('project-invite-uses')).toContainText('up to 20 people');
    await expect(page.getByTestId('project-invite-code')).not.toHaveText('BB-7K2Q');
    await shot(page, 'project-invite-qr');
    await page.getByTestId('project-sheet-close').click();
    await expect(page.locator('[data-testid^="project-invite-revoke-"]')).toHaveCount(1);
  });

  test('Money & door: the Host sees the numbers; a helper sees the lock; Finance is told it is not on yet', async ({ page }) => {
    await openHub(page, { tab: 'money' });
    await expect(page.getByTestId('project-money-awaiting')).toContainText('2');
    await expect(page.getByTestId('project-money-verify')).toContainText('2 guests waiting for you');
    await expect(page.getByTestId('project-money-door')).toContainText('0/11 seats in');
    await expect(page.getByTestId('project-tab-money')).toHaveAttribute('aria-label', /needs attention$/);
    await shot(page, 'project-money-host');
    await openHub(page, { as: 'helper', tab: 'money' });
    await expect(page.getByTestId('project-money-lock')).toBeVisible();
    await expect(page.getByTestId('project-money-stats')).toHaveCount(0);
    await openHub(page, { as: 'finance', tab: 'money' });
    await expect(page.getByTestId('project-money-lock-granted')).toBeVisible();
  });

  test('delegated check-in (9a): Finance checks guests in from the names-only list; needs the access and the switch', async ({ page }) => {
    await openHub(page, { as: 'finance', tab: 'money', flags: { project_delegate_checkin: true } });
    await expect(page.getByTestId('project-door')).toBeVisible();
    await expect(page.getByTestId('project-money-stats')).toHaveCount(0);
    await expect(page.getByTestId('project-door-count')).toHaveText('2 of 5 people in');
    await shot(page, 'project-door');
    await page.getByTestId('project-door-checkin-door-1').click();
    await expect(page.getByTestId('project-door-in-door-1')).toBeVisible();
    await expect(page.getByTestId('project-door-count')).toHaveText('4 of 5 people in');
    await openHub(page, { as: 'helper', tab: 'money', flags: { project_delegate_checkin: true } });
    await expect(page.getByTestId('project-money-lock')).toBeVisible();
    await openHub(page, { tab: 'money', flags: { project_delegate_checkin: true } });
    await expect(page.getByTestId('project-money-stats')).toBeVisible();
    await expect(page.getByTestId('project-door')).toHaveCount(0);
  });

  test('delegated payments (9b): Finance confirms a payment and opens only that proof, next to the door list', async ({ page }) => {
    await openHub(page, { as: 'finance', tab: 'money', flags: { project_delegate_payments: true, project_delegate_checkin: true } });
    await expect(page.getByTestId('project-payments')).toBeVisible();
    await expect(page.getByTestId('project-door')).toBeVisible();
    await expect(page.getByTestId('project-money-verify')).toHaveCount(0);
    await expect(page.getByTestId('project-payments-proof-pay-2')).toHaveCount(0);
    await shot(page, 'project-payments');
    await page.getByTestId('project-payments-proof-pay-1').click();
    await expect(page.getByTestId('project-proof')).toBeVisible();
    await page.getByTestId('project-proof-close').click();
    await page.getByTestId('project-payments-confirm-pay-1').click();
    await expect(page.getByTestId('project-payments-confirm-pay-1')).toHaveCount(0);
    await expect(page.getByTestId('project-payments-confirmed')).toContainText('5.390.000');
  });

  test('delegated refunds (9c): Finance records a transfer for Host approval; the row waits for the Host', async ({ page }) => {
    await openHub(page, { as: 'finance', tab: 'money', flags: { project_delegate_refunds: true, project_delegate_payments: true, project_delegate_checkin: true } });
    await expect(page.getByTestId('project-refunds')).toBeVisible();
    const order = await page.locator('[data-testid="project-payments"], [data-testid="project-refunds"], [data-testid="project-door"]').evaluateAll(els => els.map(e => e.dataset.testid));
    expect(order).toEqual(['project-payments', 'project-refunds', 'project-door']);
    await expect(page.getByTestId('project-refunds-disputed-ref-2')).toHaveText('Disputed');
    await expect(page.getByTestId('project-refunds-state-ref-1')).toHaveText(/^Due \w{3} \d{1,2}$/);
    await shot(page, 'project-refunds');
    await page.getByTestId('project-refunds-row-ref-2').click();
    await expect(page.getByTestId('project-refund-no-account')).toBeVisible();
    await expect(page.getByTestId('project-refund-submit')).toBeDisabled();
    await page.getByTestId('project-sheet-close').click();
    await page.getByTestId('project-refunds-row-ref-1').click();
    await expect(page.getByTestId('project-refund-copy-number-value')).toHaveText('0071000123456');
    await expect(page.getByTestId('project-refund-submit')).toHaveText('Record transfer for Host approval');
    await expect(page.getByTestId('project-refund-footer')).toHaveText('The guest is told only after the Host approves.');
    await page.getByTestId('project-refund-note').fill('Sent at 14:05');
    await page.getByTestId('project-refund-submit').click();
    await expect(page.getByTestId('project-refund-sheet')).toHaveCount(0);
    await expect(page.getByTestId('project-refunds-state-ref-1')).toHaveText('You recorded this · waiting for the Host');
    await expect(page.locator('button[data-testid="project-refunds-row-ref-1"]')).toHaveCount(0);
  });

  test('delegated refunds (9c): under finance_alone, Mark refund sent removes the row; no access means no list', async ({ page }) => {
    await openHub(page, { as: 'finance', tab: 'money', refundApproval: 'finance_alone', flags: { project_delegate_refunds: true } });
    await page.getByTestId('project-refunds-row-ref-1').click();
    await expect(page.getByTestId('project-refund-submit')).toHaveText('Mark refund sent');
    await expect(page.getByTestId('project-refund-footer')).toHaveText('The guest is told right away.');
    await page.getByTestId('project-refund-submit').click();
    await expect(page.getByTestId('project-refunds-row-ref-1')).toHaveCount(0);
    await expect(page.getByTestId('project-refunds-row-ref-2')).toBeVisible();
    await openHub(page, { as: 'helper', tab: 'money', flags: { project_delegate_refunds: true } });
    await expect(page.getByTestId('project-money-lock')).toBeVisible();
    await openHub(page, { as: 'finance', tab: 'money' });
    await expect(page.getByTestId('project-refunds')).toHaveCount(0);
  });

  test('Host refunds (9c): approve a team record after a confirm; decline needs a reason; the approval switch asks first', async ({ page }) => {
    await openHub(page, { tab: 'money', flags: { project_delegate_refunds: true } });
    await expect(page.getByTestId('project-team-refund-ref-1')).toContainText('Hà recorded the transfer · Receipt attached');
    await shot(page, 'project-refunds-host');
    await page.getByTestId('project-team-refund-decline-ref-1').click();
    await expect(page.getByTestId('project-team-refund-decline-confirm')).toBeDisabled();
    await page.getByTestId('project-reason').fill('ok');
    await expect(page.getByTestId('project-team-refund-decline-confirm')).toBeDisabled();
    await page.getByTestId('project-reason').fill('Wrong amount');
    await page.getByTestId('project-team-refund-decline-confirm').click();
    await expect(page.getByTestId('project-team-refunds')).toHaveCount(0);

    await openHub(page, { tab: 'money', flags: { project_delegate_refunds: true } });
    await page.getByTestId('project-team-refund-approve-ref-1').click();
    await expect(page.getByTestId('project-team-refund-approve-sheet')).toContainText('The guest will be told the refund was sent.');
    await page.getByTestId('project-team-refund-approve-confirm').click();
    await expect(page.getByTestId('project-team-refunds')).toHaveCount(0);

    await expect(page.getByTestId('project-refund-approval-host')).toHaveAttribute('aria-pressed', 'true');
    await page.getByTestId('project-refund-approval-alone').click();
    await expect(page.getByTestId('project-refund-approval-sheet')).toContainText('without you');
    await page.getByTestId('project-refund-approval-confirm').click();
    await expect(page.getByTestId('project-refund-approval-alone')).toHaveAttribute('aria-pressed', 'true');
    await expect(page.getByTestId('project-dispute-grants')).toHaveCount(0);

    await openHub(page, { tab: 'money' });
    await expect(page.getByTestId('project-refund-approval')).toHaveCount(0);
  });

  test('Host refunds (9c): once team access is over, a disputed refund can go to one money member', async ({ page }) => {
    await openHub(page, { tab: 'money', now: '2026-11-25T10:00:00+07:00', flags: { project_delegate_refunds: true } });
    await page.getByTestId('project-dispute-grant-ref-2').click();
    await expect(page.getByTestId(`project-dispute-grant-who-${MEMBERS.finance}`)).toHaveAttribute('aria-pressed', 'true');
    await page.getByTestId('project-dispute-grant-days-14').click();
    await page.getByTestId('project-dispute-grant-confirm').click();
    await expect(page.getByTestId('project-dispute-grant-sheet')).toHaveCount(0);
    await expect(page.getByTestId('project-dispute-granted')).toContainText('Hà can handle the refund to Minh Khang for 14 days.');
  });

  test('Day-of: not live before the day; on the day the grid stretches the first item and a tick freezes it', async ({ page }) => {
    await openHub(page, { tab: 'dayof' });
    await expect(page.getByTestId('project-dayof-info')).toBeVisible();
    await page.getByTestId('project-dayof-day-2026-11-13').click();
    await expect(page.getByTestId('project-dayof-due')).toContainText('In thứ tự chương trình');

    await openHub(page, { tab: 'dayof', now: '2026-11-14T18:10:00+07:00' });
    await expect(page.getByTestId('project-dayof-live')).toBeVisible();
    await page.getByTestId('project-dayof-view-cal').click();
    await expect(page.getByTestId(`project-ros-block-${SETUP}`)).toHaveAttribute('aria-label', /40 minutes over/);
    await expect(page.getByTestId('project-ros-chips')).toBeVisible();
    await expect(page.getByTestId('project-ros-now-line')).toBeVisible();
    await shot(page, 'project-dayof-grid');
    await page.getByTestId(`project-ros-tick-${SETUP}`).click();
    await expect(page.getByTestId(`project-ros-block-${SETUP}`)).toHaveAttribute('aria-label', /done/);
    await expect(page.getByTestId(`project-ros-block-${SETUP}`)).not.toHaveAttribute('aria-label', /over/);
  });

  test('Day-of: delete an item to the trash and restore it', async ({ page }) => {
    await openHub(page, { tab: 'dayof' });
    await page.getByTestId(`project-ros-edit-${SETUP}`).click();
    await page.getByTestId('project-ros-delete').click();
    await page.getByTestId('project-reason-pick').first().click();
    await page.getByTestId('project-ros-confirm-delete').click();
    await expect(page.getByTestId(`project-ros-row-${SETUP}`)).toHaveCount(0);
    await page.getByTestId('project-more').click();
    await page.getByTestId('project-menu-trash').click();
    await page.getByTestId(`project-trash-restore-${SETUP}`).click();
    await page.getByTestId('project-sheet-close').click();
    await expect(page.getByTestId(`project-ros-row-${SETUP}`)).toBeVisible();
  });

  test('Join: a link shows the invite and joining opens the project; signed out asks to log in', async ({ page }) => {
    await openHub(page);
    await devSet(page, { screen: 'projectJoin', projectJoinCode: 'BB-7K2Q', projectJoinPeek: null, projectJoinError: '', projectJoinBack: 'home' });
    await expect(page.getByTestId('project-join-card')).toBeVisible();
    await shot(page, 'project-join');
    await page.getByTestId('project-join-confirm').click();
    await expect(page.getByTestId('project-hub')).toBeVisible();

    await devSet(page, { screen: 'projectJoin', projectJoinCode: 'BB-ZZZZ', projectJoinPeek: null, projectJoinError: '' });
    await expect(page.getByTestId('project-join-error')).toBeVisible();

    await devSet(page, { user: null, screen: 'projectJoin', projectJoinCode: 'BB-7K2Q', projectJoinPeek: null, projectJoinError: '' });
    await expect(page.getByTestId('project-join-sign-in')).toBeVisible();
    await expect(page.getByTestId('project-join-card')).toHaveCount(0);
  });

  test('a pasted /join/<code> link opens Join a team, also signed out', async ({ page }) => {
    await guestToHome(page); // a returning visitor: first-run language/theme screens hold deep links until done
    await page.goto('/join/BB-7K2Q');
    // A cold load starts on the splash (tap to continue); the pending deep link applies after it.
    for (let i = 0; i < 10 && !(await page.getByTestId('project-join').count()); i++) {
      await page.locator('[data-screen-label="Splash"]').click({ timeout: 1000 }).catch(() => {});
      await page.waitForTimeout(800);
    }
    await expect(page.getByTestId('project-join')).toBeVisible({ timeout: 15000 });
    await expect(page.getByTestId('project-join-code')).toHaveValue('BB-7K2Q');
  });

  test('Vietnamese and dark still render', async ({ page }) => {
    await openHub(page, { lang: 'vi' });
    await devSet(page, { theme: 'dark' });
    await expect(page.getByTestId('project-tab-overview')).toHaveAttribute('aria-label', 'Tổng quan, thẻ 1 trên 6');
    await shot(page, 'project-overview-vi-dark');
  });
});

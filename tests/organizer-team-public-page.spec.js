// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';
import { hasServiceRole, adminClient, createTestUser, signIn, cleanup } from './e2e/setup.mjs';

// Organizer Team pass (2026-09-27, Stage 2) — clickable Team + member
// cards, and real event-organizing credits. The private/RLS-side
// mechanics were already verified in organizer-team.spec.js; this covers
// the PUBLIC-facing surface: the "Bởi <org> Team ›" row, the Team page
// itself, tapping through to a member's personal profile, the "Thành
// viên của" badge, and event credits — all gated on the SAME live
// public_visible flag, verified by actually toggling it mid-test.
const TEST_ORG_ID = 'org_team_stage2_test';
const TEST_EVENT_ID = 'evt_team_stage2_test';

test.describe('Organizer Team — public page + member cards + event credits (Stage 2)', () => {
  let admin;
  let memberUser;
  let ownerUserId;
  let membershipId;

  test.beforeAll(async () => {
    if (!hasServiceRole()) return;
    admin = adminClient();
    memberUser = await createTestUser(admin, 'team-stage2', { displayName: 'Team Stage2 Member' });
    await admin.from('profiles').update({ handle: 'teamstage2member' }).eq('id', memberUser.userId);

    const { data: reg } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    ownerUserId = reg.auth_user_id;
    await admin.from('organizers').upsert({ id: TEST_ORG_ID, owner_id: ownerUserId, name: 'Team Stage2 Org', verified: false });
    await admin.from('events').upsert({
      id: TEST_EVENT_ID, organizer_id: TEST_ORG_ID, name: 'Team Stage2 Event', status: 'live',
      starts_at: new Date(Date.now() + 5 * 86400000).toISOString(), price_vnd: 0, capacity: 10, seats_remaining: 10,
      cat_key: 'other', cat_label: 'Khác', area: 'hcmc', visibility: 'public',
    });
    await admin.from('profiles').update({ role: 'organizer' }).eq('id', ownerUserId);

    const ownerClient = (await signIn('doqanh0906+banbe-fast-suite-shared@gmail.com', 'BanbeE2e!Test1234')).client;
    await ownerClient.rpc('invite_organizer_member', { p_organizer_id: TEST_ORG_ID, p_handle: 'teamstage2member', p_public_role: 'Điều phối' });
    const { data: row } = await admin.from('organizer_members').select('id').eq('organizer_id', TEST_ORG_ID).eq('user_id', memberUser.userId).single();
    membershipId = row.id;
    const { client: memberClient } = await signIn(memberUser.email, memberUser.password);
    await memberClient.rpc('respond_to_organizer_invite', { p_membership_id: membershipId, p_accept: true });
    await memberClient.rpc('set_organizer_member_visibility', { p_membership_id: membershipId, p_visible: true });
    await ownerClient.rpc('assign_event_credit', { p_event_id: TEST_EVENT_ID, p_user_id: memberUser.userId });
    const { data: creditRow } = await admin.from('event_credits').select('id').eq('event_id', TEST_EVENT_ID).eq('user_id', memberUser.userId).single();
    await memberClient.rpc('respond_to_event_credit', { p_credit_id: creditRow.id, p_accept: true });
  });

  test.afterAll(async () => {
    if (!admin) return;
    await admin.from('event_credits').delete().eq('event_id', TEST_EVENT_ID);
    await admin.from('organizer_members').delete().eq('organizer_id', TEST_ORG_ID);
    await admin.from('events').delete().eq('id', TEST_EVENT_ID);
    await admin.from('organizers').delete().eq('id', TEST_ORG_ID);
    await admin.from('profiles').update({ role: 'participant' }).eq('id', ownerUserId);
    await cleanup(admin, { userIds: [memberUser.userId] });
  });

  test('signed-out visitor: organizer profile -> Team row -> Team page -> member card -> personal profile with badge + credited event', async ({ browser }) => {
    test.skip(!hasServiceRole(), 'requires service role for real-backend setup');
    const context = await browser.newContext();
    const page = await context.newPage();

    await page.goto(`/org/${TEST_ORG_ID}`);
    await expect(page.locator('[data-screen-label="Organizer profile"]')).toBeVisible({ timeout: 8000 });
    const teamRow = page.getByTestId('organizer-profile-team-row');
    await expect(teamRow).toBeVisible();
    await expect(teamRow).toContainText('Team Stage2 Org');
    await teamRow.click();

    await expect(page.locator('[data-screen-label="Organizer team"]')).toBeVisible({ timeout: 5000 });
    await expect(page.getByText('Điều phối')).toBeVisible();
    const memberCard = page.getByTestId('team-member-card-teamstage2member');
    await expect(memberCard).toBeVisible();
    await memberCard.click();

    await expect(page.locator('[data-screen-label="Public profile"]')).toBeVisible({ timeout: 5000 });
    await expect(page.getByTestId('public-profile-display-name')).toHaveText('Team Stage2 Member');
    await expect(page.getByTestId(`public-profile-team-badge-${TEST_ORG_ID}`)).toContainText('Team Stage2 Org');
    await expect(page.getByTestId('public-profile-credited-events')).toContainText('Team Stage2 Event');

    // Never redirected to a login wall at any point in this whole chain.
    await expect(page.locator('[data-screen-label="Login"]')).toHaveCount(0);
    await context.close();
  });

  test('member hides Team association: badge, credited event and Team roster all disappear immediately', async ({ browser }) => {
    test.skip(!hasServiceRole(), 'requires service role for real-backend setup');
    const { client: memberClient } = await signIn(memberUser.email, memberUser.password);
    await memberClient.rpc('set_organizer_member_visibility', { p_membership_id: membershipId, p_visible: false });

    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto('/u/teamstage2member');
    await expect(page.locator('[data-screen-label="Public profile"]')).toBeVisible({ timeout: 8000 });
    await expect(page.getByTestId(`public-profile-team-badge-${TEST_ORG_ID}`)).toHaveCount(0);
    await expect(page.getByTestId('public-profile-credited-events')).toHaveCount(0);

    await page.goto(`/org/${TEST_ORG_ID}`);
    await expect(page.locator('[data-screen-label="Organizer profile"]')).toBeVisible({ timeout: 8000 });
    await page.getByTestId('organizer-profile-team-row').click();
    await expect(page.locator('[data-screen-label="Organizer team"]')).toBeVisible({ timeout: 5000 });
    await expect(page.getByTestId('team-member-card-teamstage2member')).toHaveCount(0);
    await context.close();

    // Restore visibility for the other test in this file (order-independent).
    await memberClient.rpc('set_organizer_member_visibility', { p_membership_id: membershipId, p_visible: true });
  });
});

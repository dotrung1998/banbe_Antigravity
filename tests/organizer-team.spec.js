// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';
import { hasServiceRole, adminClient, createTestUser, signIn, cleanup } from './e2e/setup.mjs';

// Organizer Team pass (2026-09-27, Stage 1) — real, opt-in organizer
// membership (organizer_members, migration 098). The OWNER side is driven
// through the real UI (the shared fast-suite account, already signed in
// via storageState); the MEMBER side and every RLS/authorization boundary
// are verified via direct API calls (anonClient()/signIn()) rather than a
// second browser context, since this project's `storageState` config
// leaks into any `browser.newContext()` regardless (a separate, pre-
// existing issue — see dispute-flow-e2e.spec.js's own real failures) and
// this ticket explicitly asks to "test direct API access, not only hidden
// UI" anyway.
const TEST_ORG_ID = 'org_team_stage1_test';

test.describe('Organizer Team membership (Stage 1)', () => {
  let admin;
  let memberUser;
  let ownerUserId;

  test.beforeAll(async () => {
    if (!hasServiceRole()) return;
    admin = adminClient();
    memberUser = await createTestUser(admin, 'team-member', { displayName: 'Team Stage1 Member' });
    await admin.from('profiles').update({ handle: 'teamstage1member' }).eq('id', memberUser.userId);

    const { data: reg } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    ownerUserId = reg.auth_user_id;
    await admin.from('organizers').upsert({ id: TEST_ORG_ID, owner_id: ownerUserId, name: 'Team Stage1 Org', verified: false });
    await admin.from('profiles').update({ role: 'organizer' }).eq('id', ownerUserId);
  });

  test.afterAll(async () => {
    if (!admin) return;
    await admin.from('organizer_members').delete().eq('organizer_id', TEST_ORG_ID);
    await admin.from('organizers').delete().eq('id', TEST_ORG_ID);
    await admin.from('profiles').update({ role: 'participant' }).eq('id', ownerUserId);
    await cleanup(admin, { userIds: [memberUser.userId] });
  });

  test('owner invites via the real UI; member accepts, opts in/out, owner cannot force visibility, owner removes', async ({ page }) => {
    test.skip(!hasServiceRole(), 'requires service role for real-backend setup');

    // --- Owner: invite through the real Dashboard UI ---
    await setupToHome(page);
    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]');
    await page.getByTestId('account-tab-host').click();
    await page.getByTestId('org-profile-card').click();
    await expect(page.locator('[data-screen-label="Organizer dashboard"]')).toBeVisible({ timeout: 8000 });

    await expect(page.getByTestId('dashboard-team-section')).toBeVisible({ timeout: 8000 });
    await page.getByTestId('dashboard-team-invite-handle').fill('teamstage1member');
    await page.getByTestId('dashboard-team-invite-role').fill('Điều phối');
    await page.getByTestId('dashboard-team-invite-submit').click();
    // The invite is a real network round-trip (RPC + roster reload); the
    // input clearing itself is the on-screen success signal to wait on
    // before asserting the DB side, rather than a fixed timeout.
    await expect(page.getByTestId('dashboard-team-invite-handle')).toHaveValue('', { timeout: 8000 });

    const { data: membershipRow } = await admin.from('organizer_members')
      .select('id').eq('organizer_id', TEST_ORG_ID).eq('user_id', memberUser.userId).single();
    expect(membershipRow?.id).toBeTruthy();
    await expect(page.getByTestId(`dashboard-team-member-${membershipRow.id}`)).toBeVisible({ timeout: 8000 });
    await expect(page.getByTestId(`dashboard-team-member-${membershipRow.id}`)).toContainText('Đang chờ');

    // --- Public team page: nobody yet (not even accepted) ---
    const anon1 = await import('./e2e/setup.mjs').then(m => m.anonClient());
    const { data: teamBefore } = await anon1.rpc('get_organizer_team', { p_organizer_id: TEST_ORG_ID });
    expect(teamBefore.members).toEqual([]);

    // --- Member: direct API (real RLS, real RPCs — not the hidden UI) ---
    const { client: memberClient } = await signIn(memberUser.email, memberUser.password);
    const { data: ownRows } = await memberClient.from('organizer_members').select('*').eq('organizer_id', TEST_ORG_ID);
    expect(ownRows).toHaveLength(1);
    expect(ownRows[0].status).toBe('invited');
    expect(ownRows[0].public_visible).toBe(false);

    const { data: acceptRes } = await memberClient.rpc('respond_to_organizer_invite', { p_membership_id: membershipRow.id, p_accept: true });
    expect(acceptRes.success).toBe(true);

    const { data: teamAfterAccept } = await anon1.rpc('get_organizer_team', { p_organizer_id: TEST_ORG_ID });
    expect(teamAfterAccept.members).toEqual([]); // accepted but not yet public_visible

    const { data: visRes } = await memberClient.rpc('set_organizer_member_visibility', { p_membership_id: membershipRow.id, p_visible: true });
    expect(visRes.success).toBe(true);

    const { data: teamVisible } = await anon1.rpc('get_organizer_team', { p_organizer_id: TEST_ORG_ID });
    expect(teamVisible.members).toHaveLength(1);
    expect(teamVisible.members[0].handle).toBe('teamstage1member');
    expect(teamVisible.members[0].public_role).toBe('Điều phối');

    // Owner cannot force a member's visibility (not the member's own row).
    const { client: ownerDirectClient } = await signIn('doqanh0906+banbe-fast-suite-shared@gmail.com', 'BanbeE2e!Test1234');
    const { data: ownerForceAttempt } = await ownerDirectClient.rpc('set_organizer_member_visibility', { p_membership_id: membershipRow.id, p_visible: true });
    expect(ownerForceAttempt.success).toBe(false);
    expect(ownerForceAttempt.error).toBe('NOT_FOUND');

    // Member opts back out — public team empties immediately.
    await memberClient.rpc('set_organizer_member_visibility', { p_membership_id: membershipRow.id, p_visible: false });
    const { data: teamHidden } = await anon1.rpc('get_organizer_team', { p_organizer_id: TEST_ORG_ID });
    expect(teamHidden.members).toEqual([]);

    // Re-opt in for the owner-remove assertion below.
    await memberClient.rpc('set_organizer_member_visibility', { p_membership_id: membershipRow.id, p_visible: true });

    // --- Owner removes via the real UI; forces visibility off, never on ---
    await page.reload();
    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]');
    await page.getByTestId('account-tab-host').click();
    await page.getByTestId('org-profile-card').click();
    await expect(page.locator('[data-screen-label="Organizer dashboard"]')).toBeVisible({ timeout: 8000 });
    await expect(page.getByTestId(`dashboard-team-member-${membershipRow.id}`)).toContainText('Đã tham gia');
    await page.getByTestId(`dashboard-team-remove-${membershipRow.id}`).click();
    await expect(page.getByTestId(`dashboard-team-member-${membershipRow.id}`)).toHaveCount(0);

    const { data: rowAfterRemove } = await admin.from('organizer_members').select('status, public_visible').eq('id', membershipRow.id).single();
    expect(rowAfterRemove.status).toBe('removed');
    expect(rowAfterRemove.public_visible).toBe(false);
    const { data: teamAfterRemove } = await anon1.rpc('get_organizer_team', { p_organizer_id: TEST_ORG_ID });
    expect(teamAfterRemove.members).toEqual([]);
  });

  test('anon cannot read organizer_members directly (RLS), and public role never grants owner authorization', async () => {
    test.skip(!hasServiceRole(), 'requires service role for real-backend setup');
    const anon = await import('./e2e/setup.mjs').then(m => m.anonClient());
    const { data, error } = await anon.from('organizer_members').select('*').eq('organizer_id', TEST_ORG_ID);
    expect(error).toBeFalsy();
    expect(data).toEqual([]); // RLS silently returns nothing, never a leak

    // A member (even with a fancy public_role) still can't touch the
    // organizer's own owner-only fields (bank details) — unchanged by
    // this migration; update_organizer_profile stays owner/admin-gated.
    const { client: memberClient } = await signIn(memberUser.email, memberUser.password);
    const { data: updateRes, error: updateErr } = await memberClient.rpc('update_organizer_profile', {
      p_organizer_id: TEST_ORG_ID, p_name: 'Hijacked Name',
    });
    expect(updateErr || updateRes?.error).toBeTruthy();
  });
});

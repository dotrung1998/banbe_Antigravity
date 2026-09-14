// @ts-check
/// <reference types="@playwright/test" />
//
// Real-backend check for the in-app toast fix (.claude/notes/07-notifications.md,
// Step 2): a `notifications` row that appears while the app is already open
// must surface as a toast within one poll cycle (GocContext.jsx's 5s poll),
// not sit invisible until someone opens the bell screen. Gated the same way
// as tests/dispute-flow-e2e.spec.js — real Supabase Auth user, real table
// write, no mocked routes. Both files hit the same live backend from real
// browsers; run together with `--workers=1` (default parallelism across
// both can starve the 5s poll's timing under load — each is reliable on
// its own or serialized).
import { test, expect } from '@playwright/test';
import { hasServiceRole, adminClient, createTestUser, cleanup } from './e2e/setup.mjs';
import { setupToHome } from './helpers.js';

const SKIP_REASON = 'requires SUPABASE_SERVICE_ROLE_KEY (+ VITE_SUPABASE_ANON_KEY) — see tests/e2e/setup.mjs';

test.describe('In-app toast (real backend)', () => {
  test('a new notification row surfaces as a toast without opening the bell screen', async ({ page }) => {
    test.skip(!hasServiceRole(), SKIP_REASON);
    test.setTimeout(60_000);

    const admin = adminClient();
    const user = await createTestUser(admin, 'toast');
    try {
      await setupToHome(page);
      await page.getByText('Tài khoản').first().click();
      await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 5000 });
      await page.getByText('Đăng nhập để lưu sự kiện và nhắn tin').click();
      await expect(page.locator('[data-screen-label="Login"]')).toBeVisible({ timeout: 5000 });
      await page.locator('[data-screen-label="Login"]').getByText('Mật khẩu', { exact: true }).click();
      await page.locator('[data-testid="login-email"]').fill(user.email);
      await page.locator('input[placeholder="Password"], input[placeholder="Mật khẩu"]').first().fill(user.password);
      await page.locator('[data-testid="login-submit"]').click();
      await expect(page.locator('[data-screen-label="Login"]')).toBeHidden({ timeout: 8000 });

      // No toast yet — nothing's happened. Written directly (not through an
      // RPC) since any real event type works the same way once it lands in
      // this table; the poll doesn't care which one wrote the row.
      await expect(page.locator('[data-testid="toast"]')).toHaveCount(0);

      const { error } = await admin.from('notifications').insert({
        recipient_id: user.userId, kind: 'payment_confirmed',
        title: 'E2E toast test', body: 'This should appear as a toast, not just in the bell list.',
      });
      expect(error, `notification insert failed: ${error?.message}`).toBeNull();

      // Poll is 5s (GocContext.jsx) — generous timeout for a full cycle plus
      // slack for a slower browser/test-runner startup (firefox/webkit have
      // shown a bit more jitter here than chromium).
      const toast = page.locator('[data-testid="toast"]');
      await expect(toast).toBeVisible({ timeout: 15000 });
      await expect(toast).toContainText('E2E toast test');

      // And it's ephemeral — gone on its own well before a human would
      // still be looking at it, not a modal someone has to dismiss.
      await expect(toast).toHaveCount(0, { timeout: 5000 });
    } finally {
      await cleanup(admin, { userIds: [user.userId] });
    }
  });
});

// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';
import { hasServiceRole, adminClient } from './e2e/setup.mjs';

// Account extension (2026-09-27, Stage 3) — one role-scoped KPI dashboard
// (get_account_kpis, migration 097), reached from a "Số liệu & báo cáo" row
// on each visible Account tab. Verifies real navigation, collapsible cards,
// expand/collapse-all, and that CSV/JSON export actually produce non-empty
// files (not just that the buttons exist).
const TEST_ORG_ID = 'org_reports_test';

test.describe('Account KPI reports', () => {
  test.beforeEach(async () => {
    if (!hasServiceRole()) return;
    const admin = adminClient();
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    if (!data?.auth_user_id) return;
    await admin.from('organizers').upsert({ id: TEST_ORG_ID, owner_id: data.auth_user_id, name: 'Reports Test Org', verified: false });
    await admin.from('profiles').update({ role: 'organizer' }).eq('id', data.auth_user_id);
  });
  test.afterEach(async () => {
    if (!hasServiceRole()) return;
    const admin = adminClient();
    await admin.from('organizers').delete().eq('id', TEST_ORG_ID);
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    if (data?.auth_user_id) await admin.from('profiles').update({ role: 'participant' }).eq('id', data.auth_user_id);
  });

  test('personal reports open from Cá nhân, cards collapse/expand, CSV/JSON export real files', async ({ page }) => {
    await setupToHome(page);
    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]');

    await page.getByTestId('account-reports-personal').click();
    await expect(page.locator('[data-screen-label="Reports"]')).toBeVisible({ timeout: 8000 });

    const firstCard = page.getByTestId('kpi-card-value-saved_events');
    await expect(firstCard).toBeVisible({ timeout: 8000 });

    // Collapsed by default — no table visible yet.
    await expect(page.getByTestId('kpi-export-csv-saved_events')).toHaveCount(0);
    await page.getByTestId('kpi-expand-all').click();
    await expect(page.getByTestId('kpi-export-csv-saved_events')).toBeVisible();

    const [csvDownload] = await Promise.all([
      page.waitForEvent('download'),
      page.getByTestId('kpi-export-csv-saved_events').click(),
    ]);
    const csvPath = await csvDownload.path();
    expect(csvPath).toBeTruthy();
    const fs = await import('fs');
    const csvStat = fs.statSync(csvPath);
    expect(csvStat.size).toBeGreaterThan(0);

    const [jsonDownload] = await Promise.all([
      page.waitForEvent('download'),
      page.getByTestId('kpi-export-json').click(),
    ]);
    const jsonPath = await jsonDownload.path();
    const jsonContent = fs.readFileSync(jsonPath, 'utf8');
    const parsed = JSON.parse(jsonContent);
    expect(parsed.schema_version).toBe(1);
    expect(parsed.role).toBe('personal');
    expect(Array.isArray(parsed.metrics)).toBe(true);

    const [pdfDownload] = await Promise.all([
      page.waitForEvent('download', { timeout: 10000 }),
      page.getByTestId('kpi-export-pdf').click(),
    ]);
    const pdfPath = await pdfDownload.path();
    const pdfStat = fs.statSync(pdfPath);
    expect(pdfStat.size).toBeGreaterThan(500); // a real multi-page PDF, not an empty stub

    await page.getByTestId('kpi-collapse-all').click();
    await expect(page.getByTestId('kpi-export-csv-saved_events')).toHaveCount(0);

    await page.locator('[data-screen-label="Reports"]').getByText(/Quay lại|Back/).click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 5000 });
  });

  test('host reports open from Tổ chức with real org-scoped numbers', async ({ page }) => {
    await setupToHome(page);
    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]');
    await page.getByTestId('account-tab-host').click();

    await page.getByTestId('account-reports-host').click();
    await expect(page.locator('[data-screen-label="Reports"]')).toBeVisible({ timeout: 8000 });
    await expect(page.getByTestId('kpi-card-value-published_events')).toBeVisible({ timeout: 8000 });
  });

  test('admin reports are unreachable for a non-admin account', async ({ page }) => {
    await setupToHome(page);
    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]');
    await expect(page.getByTestId('account-tab-admin')).toHaveCount(0);
    await expect(page.getByTestId('account-reports-admin')).toHaveCount(0);
  });
});

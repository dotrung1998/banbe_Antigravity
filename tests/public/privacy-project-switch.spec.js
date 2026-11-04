// @ts-check
import { test, expect } from '@playwright/test';

// Note 76: the Event Project Hub passages of the Privacy page (B3 line, B4 rows, B7 row; a DRAFT for legal review) follow
// the event_project_hub and project_delegate_* switches. /privacy is public; only get_feature_flags is answered here.
const json = (body) => ({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
const PROJECT_WORDS = /Event projects|Dự án sự kiện|team members the host|thành viên đội/;

async function open(page, flags) {
  await page.route('**/rest/v1/rpc/get_feature_flags', (r) => r.fulfill(json(flags)));
  await page.goto('/privacy');
  await expect(page.locator('[data-screen-label="Policy"]')).toBeVisible();
  await page.waitForTimeout(500); // let the switch answer land
  return page.locator('[data-screen-label="Policy"]').innerText();
}

test('all project switches off (production today): no project text at all', async ({ page }) => {
  const text = await open(page, { event_project_hub: false, project_delegate_checkin: true, project_delegate_payments: true, project_delegate_refunds: true });
  expect(text).toContain('B4. Who sees what');
  expect(text).not.toMatch(PROJECT_WORDS);
});

test('hub on: B3 line, B4 "Event projects" row and the B7 retention row, no delegated rows', async ({ page }) => {
  const text = await open(page, { event_project_hub: true });
  expect(text).toContain('help a host and the team the host invites organize one event together');
  expect(text).toContain('The host and the team members the host added to that project.');
  expect(text).toContain('Read-only 30 days after the event day. Permanently deleted 90 days after the event day.');
  expect(text).not.toContain('Check-in by the event team');
  expect(text).not.toContain('transfer proof of the booking they are confirming');
  expect(text).not.toContain('so they can send the refund');
});

test('hub + every delegated step on: check-in, payments (transfer proof) and refunds (refund account) rows', async ({ page }) => {
  const text = await open(page, { event_project_hub: true, project_delegate_checkin: true, project_delegate_payments: true, project_delegate_refunds: true });
  expect(text).toContain('guest names only, no amounts');
  expect(text).toContain('including the transfer proof of the booking they are confirming');
  expect(text).toContain("the guest's refund account (bank, account number, account holder) so they can send the refund");
  await expect(page.getByText('Phiên bản / Version 2026-10-06')).toBeVisible(); // not bumped before legal review
});

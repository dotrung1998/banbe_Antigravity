// @ts-check
import { test, expect } from '@playwright/test';
import { writeFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { setupToHome } from './helpers.js';
import { hasServiceRole, adminClient } from './e2e/setup.mjs';

// DATA FRESHNESS FIX (Task 1) — saveOrganizerProfile() used to only patch
// `myOrganizerAvatarPath` (the Account org-card's own source) on a
// successful save, never the `organizerProfile` snapshot this very screen
// (OrganizerProfile.jsx) had already fetched once via openOrganizerProfile().
// That meant the owner's own edit screen kept showing the PRE-save photo the
// instant the local preview cleared after a real, successful DB write —
// only a full re-open of the screen (a fresh RPC refetch) would show it.
// This test uploads a real photo, saves, and asserts the same still-open
// screen shows the new photo immediately, with no navigation/reload.
const TEST_ORG_ID = 'org_photo_refresh_test';

// A small standalone CRC32 (PNG's own algorithm) — same helper
// tests/chat-photo.spec.js already uses, copied rather than imported since
// that file doesn't export it.
const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function makePng(dir, name, w, h, fill) {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  function chunk(type, data) {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const typeBuf = Buffer.from(type);
    const crcBuf = Buffer.alloc(4);
    crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])));
    return Buffer.concat([len, typeBuf, data, crcBuf]);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0; // 8-bit RGB
  const rowBytes = w * 3;
  const raw = Buffer.alloc((rowBytes + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (rowBytes + 1)] = 0;
    for (let x = 0; x < rowBytes; x++) raw[y * (rowBytes + 1) + 1 + x] = fill;
  }
  const idat = zlib.deflateSync(raw);
  const png = Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]);
  mkdirSync(dir, { recursive: true });
  const file = path.join(dir, name);
  writeFileSync(file, png);
  return file;
}

test.describe('Organizer profile photo refresh (data-freshness fix)', () => {
  test.beforeEach(async () => {
    if (!hasServiceRole()) return;
    const admin = adminClient();
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    if (!data?.auth_user_id) return;
    // `avatar_path` is NOT NULL on this table (no default `null` allowed) —
    // omit it entirely so the column's own real default (empty string)
    // applies, same as organizer-profile-hierarchy.spec.js's own seed.
    await admin.from('organizers').upsert({
      id: TEST_ORG_ID, owner_id: data.auth_user_id, name: 'Photo Refresh Test Org', about: 'Before edit.', verified: false,
    });
    await admin.from('profiles').update({ role: 'organizer', display_name: 'Photo Refresh Tester' }).eq('id', data.auth_user_id);
  });
  test.afterEach(async () => {
    if (!hasServiceRole()) return;
    const admin = adminClient();
    await admin.from('organizers').delete().eq('id', TEST_ORG_ID);
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    if (data?.auth_user_id) await admin.from('profiles').update({ role: 'participant', display_name: '' }).eq('id', data.auth_user_id);
  });

  test('uploading a new organizer photo shows it immediately on the still-open screen, no reload needed', async ({ page }, testInfo) => {
    test.skip(!hasServiceRole(), 'needs service role to seed a real organizer row');
    await setupToHome(page);

    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]');
    await expect(page.getByTestId('organizer-mode-toggle')).toBeVisible({ timeout: 8000 });
    await page.getByTestId('account-tab-host').click();

    const orgCard = page.getByTestId('org-profile-card');
    await expect(orgCard).toBeVisible({ timeout: 8000 });
    await orgCard.click();
    await expect(page.locator('[data-screen-label="Organizer dashboard"]')).toBeVisible({ timeout: 5000 });

    await page.getByTestId('dashboard-organizer-public-profile').click();
    await expect(page.locator('[data-screen-label="Organizer profile"]')).toBeVisible({ timeout: 5000 });

    // No avatar set yet — starts on the monogram fallback, not a broken
    // image state (the "sensible fallback if upload fails" requirement's
    // starting condition).
    await expect(page.getByTestId('organizer-profile-avatar')).toHaveCount(0);

    await page.getByTestId('organizer-profile-edit').click();
    await expect(page.getByTestId('organizer-profile-edit-card')).toBeVisible();

    const file = makePng(testInfo.outputDir, 'org-avatar.png', 64, 64, 77);
    await page.setInputFiles('[data-testid="organizer-profile-avatar-input"]', file);

    await page.getByTestId('organizer-profile-save').click();
    // Save completes and returns to read mode WITHOUT leaving this screen —
    // still "Organizer profile", never a re-navigation/reload round trip.
    await expect(page.getByTestId('organizer-profile-edit-card')).toHaveCount(0, { timeout: 8000 });
    await expect(page.locator('[data-screen-label="Organizer profile"]')).toBeVisible();

    // The real assertion: the freshly-uploaded photo renders right now, on
    // this same still-open screen — before the fix this kept showing the
    // monogram fallback (organizerProfile.avatar_path was still the stale
    // pre-save `null`) until the screen was closed and reopened.
    const avatarImg = page.getByTestId('organizer-profile-avatar');
    await expect(avatarImg).toBeVisible({ timeout: 5000 });
    await expect(avatarImg).toHaveAttribute('src', new RegExp(`organizer-photos/${TEST_ORG_ID}/avatar-`));

    // The name field also saved and is shown fresh, same in-place patch.
    await expect(page.getByTestId('organizer-profile-name')).toHaveText('Photo Refresh Test Org');

    // THIRD STALE-AVATAR SITE (2026-09-28 fix) — the Dashboard header's own
    // round avatar next to the org name / "Bởi <org> Team" line used to
    // always render the static demo event photo (`ev.img`), completely
    // disconnected from the organizer's real avatar_path — so even though
    // organizerProfile/myOrganizerAvatarPath were already patched in place
    // by the previous fix, THIS specific render site never read either one
    // and stayed on the demo photo forever, stale or not. Navigate back to
    // Dashboard (still no reload) and assert it now shows the same fresh
    // photo.
    await page.locator('text=‹ Quay lại').first().click();
    await expect(page.locator('[data-screen-label="Organizer dashboard"]')).toBeVisible({ timeout: 5000 });
    await expect(page.getByTestId('dashboard-organizer-avatar-fallback')).toHaveCount(0);
    const dashboardAvatar = page.getByTestId('dashboard-organizer-avatar');
    await expect(dashboardAvatar).toBeVisible({ timeout: 5000 });
    await expect(dashboardAvatar).toHaveAttribute('src', new RegExp(`organizer-photos/${TEST_ORG_ID}/avatar-`));
  });
});

// @ts-check
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';
import {
  crc16ccitt, buildVietQrPayload, parseEmvco, verifyVietQrChecksum,
  sanitizeMemo, resolveBankBin,
} from '../src/lib/vietqr.js';

test.describe('VietQR payload', () => {
  // If this check value is wrong, every QR the app emits is silently
  // unscannable — a banking app just refuses it with no useful error. It is
  // the single highest-leverage assertion in this file.
  test('uses CRC-16/CCITT-FALSE, per the EMVCo spec check value', () => {
    expect(crc16ccitt('123456789')).toBe('29B1');
  });

  test('builds the NAPAS TLV structure a banking app expects', () => {
    const payload = buildVietQrPayload({
      bank: 'Vietcombank', accountNumber: '0071000123456',
      amountVnd: 500000, memo: 'ART10492',
    });
    const top = parseEmvco(payload);
    expect(top['00']).toBe('01');       // payload format
    expect(top['01']).toBe('12');       // dynamic — amount is baked in
    expect(top['53']).toBe('704');      // VND
    expect(top['54']).toBe('500000');
    expect(top['58']).toBe('VN');

    const merchant = parseEmvco(top['38']);
    expect(merchant['00']).toBe('A000000727');   // NAPAS GUID
    expect(merchant['02']).toBe('QRIBFTTA');     // transfer-to-account

    const beneficiary = parseEmvco(merchant['01']);
    expect(beneficiary['00']).toBe('970436');    // Vietcombank BIN
    expect(beneficiary['01']).toBe('0071000123456');

    // The reference the webhook matcher later greps for out of the bank memo.
    expect(parseEmvco(top['62'])['08']).toBe('ART10492');
    expect(verifyVietQrChecksum(payload)).toBe(true);
  });

  test('omits the amount tag entirely when the event is free', () => {
    // A present-but-zero 54 tag makes some banking apps reject the code.
    const payload = buildVietQrPayload({ bank: 'mbbank', accountNumber: '0000123456', amountVnd: 0 });
    expect('54' in parseEmvco(payload)).toBe(false);
    expect(verifyVietQrChecksum(payload)).toBe(true);
  });

  test('a single corrupted character fails the checksum', () => {
    const payload = buildVietQrPayload({ bank: 'acb', accountNumber: '123456789', amountVnd: 100000, memo: 'ART10001' });
    const flipped = payload.slice(0, 40) + (payload[40] === '7' ? '6' : '7') + payload.slice(41);
    expect(verifyVietQrChecksum(flipped)).toBe(false);
  });

  test('reduces a memo to what survives a Vietnamese bank', () => {
    // Banks strip diacritics and punctuation, uppercase, and truncate. The
    // reference has to still be greppable on the way back through a webhook.
    expect(sanitizeMemo('Đặt chỗ ART10492 — Bếp Nhỏ!')).toBe('DAT CHO ART10492 BEP NHO');
    expect(sanitizeMemo('a'.repeat(60)).length).toBeLessThanOrEqual(25);
  });

  test('resolves banks by name, short code or raw BIN, and refuses junk', () => {
    expect(resolveBankBin('Vietcombank')).toBe('970436');
    expect(resolveBankBin('VCB')).toBe('970436');
    expect(resolveBankBin('  techcombank ')).toBe('970407');
    expect(resolveBankBin('970436')).toBe('970436');
    expect(resolveBankBin('Definitely Not A Bank')).toBeNull();
  });

  test('refuses to build a QR that would send money nowhere', () => {
    expect(() => buildVietQrPayload({ bank: 'nope', accountNumber: '123456' })).toThrow(/Unknown bank/);
    expect(() => buildVietQrPayload({ bank: 'acb', accountNumber: 'not-a-number' })).toThrow(/account/i);
  });
});

test.describe('Payment screens wiring', () => {
  test('organizer-only and admin-only queues stay hidden from a goer', async ({ page }) => {
    await setupToHome(page);
    await page.getByText('Tài khoản').first().click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible();

    // A signed-out goer must not see the verification queue or dispute desk:
    // one implies they collect money, the other is platform staff only.
    await expect(page.getByTestId('host-verifications')).toHaveCount(0);
    await expect(page.getByTestId('admin-disputes')).toHaveCount(0);
  });

  // Reserve.jsx only renders past a sign-in wall this suite doesn't drive
  // through (no test here signs in — see e.g. account-and-preferences.spec.js,
  // which checks the same signed-out boundary rather than logging in), so
  // this checks the copy at the source instead of by rendering the screen.
  test('the reserve button promises the hold window the server actually gives', () => {
    const src = fs.readFileSync(fileURLToPath(new URL('../src/screens/Reserve.jsx', import.meta.url)), 'utf8');
    // The server holds for events.hold_minutes, which migration 031 set back
    // to 30 (a stopgap 60 briefly shipped in migration 026, alongside copy
    // that was updated to match it — leaving the actual mismatch this
    // guards against unfixed until 031). Copy promising a different number
    // than hold_seats() actually honors is exactly the kind of mismatch a
    // buyer only discovers under pressure, mid-transfer.
    expect(src).toContain('Giữ chỗ ▪︎ 30 phút');
    expect(src).toContain('Hold ▪︎ 30 minutes');
    expect(src).not.toMatch(/60 phút|60 minutes/);
  });

  // Migration 032: rejecting a payment ("Can't find it") must never put
  // banbe in the picture by itself — only a separate, explicit escalation
  // does. Guarded at the source rather than by rendering the (sign-in-gated)
  // Verifications screen, same reasoning as the test above.
  test('a plain rejection never frames itself as banbe stepping in — only escalation does', () => {
    const src = fs.readFileSync(fileURLToPath(new URL('../src/screens/Verifications.jsx', import.meta.url)), 'utf8');
    expect(src).toContain('escalateDispute');
    expect(src).toContain('verification-escalate');
    // The reject-reason disclaimer must not claim banbe reviews it — only
    // the escalate-reason disclaimer may say that.
    expect(src).toContain('banbe không tham gia ở bước này');
    expect(src).toContain('banbe is not involved at this step');
  });
});

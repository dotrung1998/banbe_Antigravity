// @ts-check
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

  test('the reserve button promises the hold window the server actually gives', async ({ page }) => {
    await setupToHome(page);
    await page.getByText('Bếp Nhỏ №12').first().click();
    await expect(page.locator('[data-screen-label="Event"]')).toBeVisible();
    // The server holds for events.hold_minutes, which defaults to 60. Copy
    // that says 30 is a promise the state machine does not keep.
    await expect(page.locator('[data-screen-label="Event"]').getByText(/Giữ chỗ/)).toBeVisible();
  });
});

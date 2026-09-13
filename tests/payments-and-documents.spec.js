// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';
import { amountInWordsVi, formatVnd, renderPaymentDocument } from '../src/lib/paymentDocument.js';

// A sample document standing in for a real payment_documents row (migration
// 024). Kept in one place so the rendering tests below all describe the same
// transaction from different angles.
const RECEIPT = {
  kind: 'receipt',
  number: 'PT-BEPNHO-2026-0001',
  issued_at: '2026-07-12T10:04:00Z',
  paid_at: '2026-07-12T10:04:00Z',
  pay_method: 'bank',
  total_vnd: 1800000,
  note: '',
  seller: {
    name: 'Bếp Nhỏ', address: '5 Hẻm 12, Bình Thạnh, TP.HCM', tax_code: '0301111222',
    bank_name: 'Vietcombank', bank_account_name: 'NGUYEN VAN MINH',
    bank_account_no: '0071000123456', momo_phone: '',
  },
  buyer: {
    name: 'Công ty TNHH Trung Do', address: '12 Nguyễn Huệ, Quận 1, TP.HCM',
    phone: '0911222333', tax_code: '0312345678',
  },
  event: { name: 'Bếp Nhỏ №12', date: '2026-07-11', time: '19:00', area: 'Bình Thạnh', booking_code: 'ABC123' },
  lines: [{ description: 'Bếp Nhỏ №12', qty: 2, unit_vnd: 900000, amount_vnd: 1800000 }],
};

test.describe('số tiền bằng chữ', () => {
  // Vietnamese payment documents carry the amount spelled out because digits
  // can be altered afterwards and words are awkward to. Reading it digit by
  // digit is wrong in ways a Vietnamese reader notices immediately, so the
  // sound changes get their own cases.
  test('reads the sound changes a digit-by-digit reading gets wrong', () => {
    expect(amountInWordsVi(21)).toBe('Hai mươi mốt đồng');   // not "hai mươi một"
    expect(amountInWordsVi(24)).toBe('Hai mươi tư đồng');    // not "hai mươi bốn"
    expect(amountInWordsVi(25)).toBe('Hai mươi lăm đồng');   // not "hai mươi năm"
    expect(amountInWordsVi(15)).toBe('Mười lăm đồng');
    expect(amountInWordsVi(101)).toBe('Một trăm lẻ một đồng');
  });

  test('keeps empty hundreds audible so the magnitude cannot be misread', () => {
    // "Một triệu năm mươi nghìn" would be ambiguous about the missing
    // hundreds — which is the exact ambiguity this line exists to remove.
    expect(amountInWordsVi(1050000)).toBe('Một triệu không trăm năm mươi nghìn đồng');
    expect(amountInWordsVi(2024000)).toBe('Hai triệu không trăm hai mươi tư nghìn đồng');
  });

  test('handles the everyday and the extreme', () => {
    expect(amountInWordsVi(0)).toBe('Không đồng');
    expect(amountInWordsVi(350000)).toBe('Ba trăm năm mươi nghìn đồng');
    expect(amountInWordsVi(1800000)).toBe('Một triệu tám trăm nghìn đồng');
    expect(amountInWordsVi(1000000000)).toBe('Một tỷ đồng');
    expect(amountInWordsVi(1234567890))
      .toBe('Một tỷ hai trăm ba mươi tư triệu năm trăm sáu mươi bảy nghìn tám trăm chín mươi đồng');
  });

  test('formats currency the Vietnamese way', () => {
    expect(formatVnd(1800000)).toBe('1.800.000₫');
    expect(formatVnd(0)).toBe('0₫');
  });
});

test.describe('document rendering', () => {
  test('a receipt carries every party and amount a Vietnamese document needs', () => {
    const html = renderPaymentDocument(RECEIPT);
    expect(html).toContain('PHIẾU THU');
    expect(html).toContain('PT-BEPNHO-2026-0001');
    // Both parties, with the fields that make it usable for reimbursement.
    expect(html).toContain('Bếp Nhỏ');
    expect(html).toContain('0301111222');
    expect(html).toContain('Công ty TNHH Trung Do');
    expect(html).toContain('12 Nguyễn Huệ, Quận 1, TP.HCM');
    expect(html).toContain('0312345678');
    // The amount, three ways: unit, total, and spelled out.
    expect(html).toContain('900.000₫');
    expect(html).toContain('1.800.000₫');
    expect(html).toContain('Một triệu tám trăm nghìn đồng');
    // The signature block a receipt is expected to carry.
    expect(html).toContain('Người nộp tiền');
    expect(html).toContain('Người nhận tiền');
  });

  test('states plainly that it is not a VAT e-invoice', () => {
    // The single most important line on the page: nothing an app generates
    // can be a hoá đơn điện tử, and a reader must not have to work that out.
    for (const kind of ['invoice', 'receipt']) {
      const html = renderPaymentDocument({ ...RECEIPT, kind });
      expect(html).toContain('không có mã của cơ quan thuế');
      expect(html).toContain('123/2020/NĐ-CP');
      // "not" is emphasised in the markup, so match either side of the tag.
      expect(html).toContain('a Vietnamese VAT e-invoice and carries no tax authority code');
      // And that banbe is not in the middle of the transaction.
      expect(html).toContain('banbe không thu hộ');
    }
  });

  test('an unpaid invoice asks for the transfer instead of acknowledging one', () => {
    const invoice = renderPaymentDocument({ ...RECEIPT, kind: 'invoice', paid_at: null, pay_method: '' });
    expect(invoice).toContain('HOÁ ĐƠN');
    // It must never claim money arrived...
    expect(invoice).not.toContain('Đã nhận đủ số tiền trên');
    // ...and it must carry the reference the organizer matches payments by.
    expect(invoice).toContain('ABC123');
    expect(invoice).toContain('Người lập phiếu');
    expect(invoice).not.toContain('Người nhận tiền');
  });

  test('escapes hostile party names instead of rendering them as markup', () => {
    const html = renderPaymentDocument({
      ...RECEIPT,
      seller: { ...RECEIPT.seller, name: '<script>alert(1)</script>' },
      buyer: { ...RECEIPT.buyer, name: '"><img src=x onerror=alert(1)>' },
    });
    expect(html).not.toContain('<script>alert(1)</script>');
    expect(html).not.toContain('<img src=x');
    expect(html).toContain('&lt;script&gt;');
  });
});

test.describe('Account wiring', () => {
  test('offers invoices and receipts as their own rows', async ({ page }) => {
    await setupToHome(page);
    await page.getByText('Tài khoản').first().click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible();

    await expect(page.getByTestId('account-invoices')).toBeVisible();
    await expect(page.getByTestId('account-receipts')).toBeVisible();
  });

  test('a document list opens from Account and comes back with one tap', async ({ page }) => {
    await setupToHome(page);
    await page.getByText('Tài khoản').first().click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible();

    await page.getByTestId('account-receipts').click();
    await expect(page.locator('[data-screen-label="Documents"]')).toBeVisible();
    await expect(page.getByTestId('documents-title')).toHaveText(/Biên nhận|Receipts/);

    // Signed out there is nothing to list, and the empty state has to say so
    // rather than leaving a blank panel.
    await expect(page.getByTestId('documents-empty')).toBeVisible();

    await page.getByTestId('documents-back').click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible();
  });

  test('hosting-only payment rows stay hidden for a goer', async ({ page }) => {
    await setupToHome(page);
    await page.getByText('Tài khoản').first().click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible();

    // "Getting paid" is meaningless until organizer mode is on, and showing
    // it to a goer implies banbe pays them.
    await expect(page.getByTestId('host-payout')).toHaveCount(0);
    await expect(page.getByTestId('host-receipts')).toHaveCount(0);
  });
});

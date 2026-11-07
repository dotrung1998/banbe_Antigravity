import test from 'node:test';
import assert from 'node:assert/strict';
import { localizeSystemMessage as L } from '../../src/lib/systemMessageLocale.js';

test('English-written bodies read in Vietnamese for a Vietnamese viewer', () => {
  assert.equal(L('Booking cancelled. Reason: Nhầm người.', 'vi'), 'Đặt chỗ đã bị huỷ. Lý do: Nhầm người.');
  assert.equal(L('Event was cancelled by host. Reason: Cancelled for safety or weather reasons.', 'vi'),
    'Sự kiện đã bị người tổ chức huỷ. Lý do: Sự kiện bị huỷ vì lý do an toàn hoặc thời tiết.');
  assert.equal(L('Host marked payment received via direct transfer.', 'vi'),
    'Người tổ chức đã xác nhận nhận thanh toán qua chuyển khoản trực tiếp.');
});

test('Vietnamese-written bodies read in English for an English viewer', () => {
  assert.equal(L('Người tổ chức không nhận yêu cầu đặt chỗ này: Hết chỗ thật sự. Chỗ đã được mở lại cho người khác.', 'en'),
    'The organizer declined this booking request: Actually out of seats. The spot has been released to others.');
  assert.equal(L('Người tổ chức chưa tìm thấy khoản chuyển khoản này. Chỗ của bạn vẫn được giữ trong lúc banbe xem xét.', 'en'),
    "The organizer couldn't find this transfer. Your spot is still held while banbe reviews it.");
  assert.equal(L('Đã xác nhận thanh toán ▪︎ người tổ chức xác nhận. Biên nhận R-1.', 'en'),
    'Payment confirmed ▪︎ confirmed by the organizer. Receipt R-1.');
});

test('bilingual bodies show only the viewer\'s half', () => {
  const b = 'Tranh chấp đã được giải quyết. / Dispute resolved.';
  assert.equal(L(b, 'vi'), 'Tranh chấp đã được giải quyết.');
  assert.equal(L(b, 'en'), 'Dispute resolved.');
  const g = 'Khách báo đã chuyển khoản ▪︎ Guest reported a transfer for booking BB1';
  assert.equal(L(g, 'en'), 'Guest reported a transfer for booking BB1');
  assert.equal(L(g, 'vi'), 'Khách báo đã chuyển khoản');
});

test('a body already in the viewer\'s language, or unknown text, is untouched', () => {
  assert.equal(L('Booking cancelled. Reason: X.', 'en'), 'Booking cancelled. Reason: X.');
  assert.equal(L('Xin chào, mình tới trễ 10 phút', 'en'), 'Xin chào, mình tới trễ 10 phút');
  assert.equal(L('', 'en'), '');
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { shapeDraftAsCurEvent, draftPriceVnd, DRAFT_PREVIEW_KEY } from '../../src/lib/draftPreview.js';

const base = {
  name: 'Test', catKey: 'supper', catLabel: 'Supper club', area: 'Khánh Hội', lat: 10.76, lng: 106.7,
  startsAt: new Date('2026-10-29T04:41:00'), priceVnd: 100000, seats: 10, description: 'Desc', intro: '',
  includedItems: [{ label: 'Tui', detail: '' }, { label: '  ', detail: 'x' }], inviteOnly: false, organizerName: 'Visit Test', coverUrl: 'blob:x',
};

test('a draft renders like a real event, with no distance', () => {
  const ev = shapeDraftAsCurEvent(base);
  assert.equal(ev.key, DRAFT_PREVIEW_KEY);
  assert.ok(!/ km/.test(ev.where), `no distance in "${ev.where}"`);
  assert.ok(ev.where.startsWith('Khánh Hội ▪︎ '));
  assert.match(ev.when, / ▪︎ 04:41$/);
  assert.equal(ev.seatsLong, '10 chỗ trống');
  assert.deepEqual(ev.includedItems, [{ label: 'Tui', detail: '' }], 'blank labels dropped');
  assert.equal(ev.img, 'blob:x');
  assert.equal(ev.cancelled, false);
  assert.equal(ev.soldOut, false);
});

test('free, unscheduled, seatless draft', () => {
  const ev = shapeDraftAsCurEvent({ ...base, priceVnd: 0, startsAt: null, seats: null });
  assert.equal(ev.price, 'Miễn phí');
  assert.equal(ev.when, '');
  assert.equal(ev.where, 'Khánh Hội');
  assert.equal(ev.seatsLong, '');
});

test('price parsing matches createSubmit', () => {
  assert.equal(draftPriceVnd('100.000đ'), 100000);
  assert.equal(draftPriceVnd(''), 0);
  assert.equal(draftPriceVnd('Miễn phí'), 0);
});

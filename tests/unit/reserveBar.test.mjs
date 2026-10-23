import test from 'node:test';
import assert from 'node:assert/strict';
import { parsePrice, totalPrice, reserveBarState, clampQty, QTY_PRESETS, MAX_QTY, eventPrice, eventTotal, currencyUnavailable, CURRENCY_UNAVAILABLE_REASON } from '../../src/lib/reserveBar.js';

// Mirrored by apps/ios/BanbeAppTests/ReserveBarTests.swift — change both together.

test('parses catalogue prices', () => {
  assert.deepEqual(parsePrice('200.000₫'), { free: false, unit: 200000 });
  assert.deepEqual(parsePrice('Miễn phí'), { free: true, unit: 0 });
  assert.deepEqual(parsePrice('Free'), { free: true, unit: 0 });
  assert.deepEqual(parsePrice(''), { free: false, unit: 0 });
});

test('total multiplies the unit price and keeps the vi-VN form', () => {
  assert.equal(totalPrice('200.000₫', 1), '200.000₫');
  assert.equal(totalPrice('200.000₫', 2), '400.000₫');
  assert.equal(totalPrice('1.250.000₫', 4), '5.000.000₫');
  assert.equal(totalPrice('Miễn phí', 4), 'Miễn phí');
  assert.equal(totalPrice('90.000₫', 0), '90.000₫');
});

test('bar state follows the old label priority', () => {
  const base = { booking: false, ticket: false, cancelled: false, ended: false, soldOut: false, blocked: false };
  assert.equal(reserveBarState(base), 'reserve');
  assert.equal(reserveBarState({ ...base, booking: true, cancelled: true }), 'pending');
  assert.equal(reserveBarState({ ...base, booking: true, ticket: true }), 'ticket');
  assert.equal(reserveBarState({ ...base, cancelled: true, ended: true, soldOut: true }), 'cancelled');
  assert.equal(reserveBarState({ ...base, ended: true, soldOut: true, blocked: true }), 'ended');
  assert.equal(reserveBarState({ ...base, soldOut: true, blocked: true }), 'soldOut');
  assert.equal(reserveBarState({ ...base, blocked: true }), 'blocked');
  // Paid booking not open for this currency yet: after the closed states, before the criteria block.
  assert.equal(reserveBarState({ ...base, currencyUnavailable: true, blocked: true }), 'currencyUnavailable');
  assert.equal(reserveBarState({ ...base, currencyUnavailable: true, soldOut: true }), 'soldOut');
  assert.equal(reserveBarState({ ...base, currencyUnavailable: true, booking: true }), 'pending');
});

test('money follows the event currency (migration 195)', () => {
  assert.deepEqual(parsePrice('$12.50', 'USD'), { free: false, unit: 1250 });
  assert.equal(totalPrice('$12.50', 2, 'USD'), '$25');
  assert.equal(totalPrice('$12.50', 3, 'USD'), '$37.50');
  assert.equal(totalPrice('Free', 3, 'USD'), 'Miễn phí');
  // The raw amount wins over the text when the event carries one.
  const usd = { price: '$12.50', priceAmount: 1250, currency: 'USD' };
  assert.deepEqual(eventPrice(usd), { free: false, unit: 1250, currency: 'USD' });
  assert.equal(eventTotal(usd, 4), '$50');
  assert.equal(eventTotal({ price: '200.000₫', priceAmount: 200000, currency: 'VND' }, 2), '400.000₫');
  // Demo catalogue events have only their VND text.
  assert.equal(eventTotal({ price: '90.000₫' }, 2), '180.000₫');
  assert.equal(eventTotal({ price: 'Miễn phí' }, 2), 'Miễn phí');
});

test('paid USD events cannot be booked yet; free USD and every VND event can', () => {
  assert.equal(currencyUnavailable({ priceAmount: 1250, currency: 'USD' }), true);
  assert.equal(currencyUnavailable({ priceAmount: 0, currency: 'USD', price: 'Miễn phí' }), false);
  assert.equal(currencyUnavailable({ priceAmount: 150000, currency: 'VND' }), false);
  assert.equal(currencyUnavailable({ price: '200.000₫' }), false);
  assert.deepEqual(CURRENCY_UNAVAILABLE_REASON, ['Đặt vé trả phí cho sự kiện tại Mỹ sẽ sớm mở', 'Paid booking for US events opens soon']);
});

test('quantity stays within 1..6 and presets fit the cap', () => {
  assert.equal(clampQty(0), 1);
  assert.equal(clampQty(3), 3);
  assert.equal(clampQty(9), MAX_QTY);
  assert.deepEqual(QTY_PRESETS, [1, 2, 3]);
  assert.ok(QTY_PRESETS.every(n => n >= 1 && n <= MAX_QTY));
});

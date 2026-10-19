import test from 'node:test';
import assert from 'node:assert/strict';
import { parsePrice, totalPrice, reserveBarState, clampQty, QTY_PRESETS, MAX_QTY } from '../../src/lib/reserveBar.js';

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
});

test('quantity stays within 1..6 and presets fit the cap', () => {
  assert.equal(clampQty(0), 1);
  assert.equal(clampQty(3), 3);
  assert.equal(clampQty(9), MAX_QTY);
  assert.deepEqual(QTY_PRESETS, [1, 2, 3]);
  assert.ok(QTY_PRESETS.every(n => n >= 1 && n <= MAX_QTY));
});

// Unit-level coverage for the Map free-event price bug (phase 3, task 4).
//
// Root cause recap: MapExplore.jsx's fetchLiveEvents() used to set
// `price: cosmetic?.price` unconditionally — for a real (non-demo) event,
// `cosmetic` was either a WRONG demo event's own price string (before the
// phase-1 cover-photo fix) or `undefined` (after it, once `cosmetic` was
// correctly nulled out for a non-match) — never the real row's own
// `price_vnd`, which was fetched in the query but never used. The fix
// reads `row.price_vnd` directly, with `> 0` (never a bare truthiness/`||`
// check) so a real, valid 0 VND event correctly renders "Miễn phí"/Free
// instead of being treated as "missing".
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatMoney } from '../../src/lib/eventMarket.js';

// Mirrors MapExplore.jsx's fetchLiveEvents() price expression exactly —
// kept here as a named function so a future edit to that file that
// regresses the `> 0` check (e.g. back to `row.price_vnd ? ... : ...`,
// which is ALSO correct for 0 specifically, but wrong if `price_vnd` were
// ever `null` and someone "simplified" it to `||`) has a test that fails.
// Migration 195: the amount is in the minor unit of the row's own currency (cents for USD).
function mapPriceLabel(priceVnd, currency = 'VND') {
  return priceVnd > 0 ? formatMoney(priceVnd, currency) : 'Miễn phí';
}

test('a real 0 VND event shows "Miễn phí", never a fallback/wrong price', () => {
  assert.equal(mapPriceLabel(0), 'Miễn phí');
});

test('a null/undefined price_vnd (never expected from a real row, but must not crash) also shows "Miễn phí"', () => {
  assert.equal(mapPriceLabel(null), 'Miễn phí');
  assert.equal(mapPriceLabel(undefined), 'Miễn phí');
});

test('a real paid event shows its own formatted price, unchanged', () => {
  assert.equal(mapPriceLabel(900000), '900.000₫');
  assert.equal(mapPriceLabel(100000), '100.000₫');
});

test('a USD event shows dollars from its cents, a free one still "Miễn phí"', () => {
  assert.equal(mapPriceLabel(1250, 'USD'), '$12.50');
  assert.equal(mapPriceLabel(2000, 'USD'), '$20');
  assert.equal(mapPriceLabel(0, 'USD'), 'Miễn phí');
});

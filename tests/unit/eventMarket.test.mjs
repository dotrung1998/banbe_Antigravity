import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  eventTimeZone, resolveEventTimeZone, eventCurrency, formatMoney, formatMoneyShort, parsePriceInput,
  priceInputText, priceQuickPicks, paidBookingAvailable, wallClockToMs, zonedParts, majorAmount, rowCurrency, rowTimeZone,
} from '../../src/lib/eventMarket.js';

const V = JSON.parse(readFileSync(new URL('../fixtures/event-market.json', import.meta.url), 'utf8'));

test('time zone per country/state (shared vectors)', () => {
  for (const v of V.timeZones) assert.equal(eventTimeZone(v.country, v.state), v.tz, JSON.stringify(v));
});

test('client zone only wins for real US zones (shared vectors)', () => {
  for (const v of V.resolvedZones) assert.equal(resolveEventTimeZone(v.country, v.state, v.clientTz), v.tz, JSON.stringify(v));
});

test('currency per country (shared vectors)', () => {
  for (const v of V.currencies) assert.equal(eventCurrency(v.country), v.currency, JSON.stringify(v));
});

test('wall clock in the venue zone -> instant (shared vectors, same as SQL AT TIME ZONE)', () => {
  for (const v of V.wallClock) assert.equal(new Date(wallClockToMs(v.date, v.time, v.tz)).toISOString(), v.utc.replace('Z', '.000Z'), JSON.stringify(v));
});

test('instant -> venue-local parts (shared vectors)', () => {
  for (const v of V.zonedParts) {
    const p = zonedParts(Date.parse(v.utc), v.tz);
    assert.deepEqual(p, { year: v.year, month: v.month, day: v.day, hour: v.hour, minute: v.minute, weekday: v.weekday }, JSON.stringify(v));
  }
});

test('money text and short text (shared vectors)', () => {
  for (const v of V.money) {
    assert.equal(formatMoney(v.amount, v.currency), v.text, JSON.stringify(v));
    assert.equal(formatMoneyShort(v.amount, v.currency), v.short, JSON.stringify(v));
  }
});

test('price input parsing and edit text (shared vectors)', () => {
  for (const v of V.parsePrice) assert.equal(parsePriceInput(v.input, v.currency), v.amount, JSON.stringify(v));
  for (const v of V.priceInput) assert.equal(priceInputText(v.amount, v.currency), v.text, JSON.stringify(v));
});

test('quick picks and paid-booking availability (shared vectors)', () => {
  assert.deepEqual(priceQuickPicks('VND'), V.quickPicks.VND);
  assert.deepEqual(priceQuickPicks('USD'), V.quickPicks.USD);
  for (const v of V.paidBooking) assert.equal(paidBookingAvailable(v.currency, v.amount), v.available, JSON.stringify(v));
});

test('row helpers default every pre-195 row to VND / derived zone', () => {
  assert.equal(rowCurrency({}), 'VND');
  assert.equal(rowCurrency({ currency: 'USD' }), 'USD');
  assert.equal(rowTimeZone({ tz: 'America/Chicago' }), 'America/Chicago');
  assert.equal(rowTimeZone({ country_code: 'US', state_province: 'CA' }), 'America/Los_Angeles');
  assert.equal(rowTimeZone({}), 'Asia/Ho_Chi_Minh');
  assert.equal(majorAmount(1250, 'USD'), 12.5);
  assert.equal(majorAmount(150000, 'VND'), 150000);
});

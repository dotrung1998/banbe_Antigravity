import test from 'node:test';
import assert from 'node:assert/strict';
import {
  fmtCount, fmtRate, fmtMedian, fmtCountRate, rangeFor, orderedMarkets, marketRows, reportError,
} from '../../src/lib/retentionReport.js';
import { validateDob, latestDobFor } from '../../src/lib/dob.js';

// Admin › Retention report (migration 196). Same vectors as apps/ios/BanbeAppTests/RetentionReportTests.swift.

test('counts: numbers grouped, "<20" verbatim, anything else hidden', () => {
  assert.equal(fmtCount(0), '0');
  assert.equal(fmtCount(1234), '1,234');
  assert.equal(fmtCount('<20'), '<20');
  assert.equal(fmtCount(null), '—');
  assert.equal(fmtCount(undefined), '—');
});

test('rates and medians: one decimal at most, null hidden', () => {
  assert.equal(fmtRate(0.4), '40%');
  assert.equal(fmtRate(0.125), '12.5%');
  assert.equal(fmtRate(0.3333), '33.3%');
  assert.equal(fmtRate(null), '—');
  assert.equal(fmtMedian(4), '4');
  assert.equal(fmtMedian(4.55), '4.6');
  assert.equal(fmtMedian(null), '—');
  assert.equal(fmtCountRate(25, 0.25), '25 · 25%');
  assert.equal(fmtCountRate('<20', null), '<20');
  assert.equal(fmtCountRate(30, null), '30');
});

test('range: the last N days including today, local dates; unknown N falls back to 90', () => {
  const now = new Date(2026, 9, 23, 15, 0);
  assert.deepEqual(rangeFor(30, now), { from: '2026-09-24', to: '2026-10-23' });
  assert.deepEqual(rangeFor(90, now), { from: '2026-07-26', to: '2026-10-23' });
  assert.deepEqual(rangeFor(365, now), { from: '2025-10-24', to: '2026-10-23' });
  assert.deepEqual(rangeFor(7, now), rangeFor(90, now));
});

test('markets: VN, US, unknown in that order, missing ones hidden', () => {
  const ms = orderedMarkets([{ market: 'unknown', people: 40 }, { market: 'US', people: '<20' }]);
  assert.deepEqual(ms.map(m => m.market), ['VN', 'US', 'unknown']);
  assert.equal(marketRows(ms[0]).find(r => r.key === 'people').value, '—');
  assert.equal(marketRows(ms[1]).find(r => r.key === 'people').value, '<20');
  const rows = marketRows({ market: 'VN', people: 120, active_people: 80, new_people: 60, d7_returned: 21, d7_rate: 0.35,
    d30_returned: '<20', d30_rate: null, first_attenders: 40, second_within_60d: 22, second_within_60d_rate: 0.55, days_to_second_median: 12.5 });
  assert.deepEqual(rows.map(r => r.value), ['120', '80', '60', '21 · 35%', '<20', '40', '22 · 55%', '12.5']);
  assert.deepEqual(orderedMarkets(null).map(m => m.market), ['VN', 'US', 'unknown']);
});

test('errors: not authorized, missing function, network', () => {
  assert.equal(reportError({ success: true }, null), null);
  assert.equal(reportError({ success: false, error: 'NOT_AUTHORIZED' }, null), 'NOT_AUTHORIZED');
  assert.equal(reportError(null, { code: 'PGRST202' }), 'NOT_DEPLOYED');
  assert.equal(reportError(null, { code: '500' }), 'NETWORK');
  assert.equal(reportError(null, null), 'NETWORK');
});

// Migration 197: a NEW date of birth must be at least 16 years ago (same rule as iOS DateOfBirthInput.latestDate).
test('date of birth: under 16 is refused only where minAge is asked for', () => {
  const now = new Date(2026, 9, 23);
  assert.deepEqual(latestDobFor(16, now), { y: 2010, m: 10, d: 23 });
  assert.deepEqual(validateDob({ day: '23', month: '10', year: '2010' }, now, { minAge: 16 }), { iso: '2010-10-23' });
  assert.deepEqual(validateDob({ day: '24', month: '10', year: '2010' }, now, { minAge: 16 }), { problem: 'tooYoung' });
  assert.deepEqual(validateDob({ day: '1', month: '1', year: '2015' }, now, { minAge: 16 }), { problem: 'tooYoung' });
  // Confirming an existing account's date never re-checks age.
  assert.deepEqual(validateDob({ day: '1', month: '1', year: '2015' }, now), { iso: '2015-01-01' });
  // 29 February: the latest date falls back to 28 February in a non-leap year.
  assert.deepEqual(latestDobFor(16, new Date(2028, 1, 29)), { y: 2012, m: 2, d: 29 });
  assert.deepEqual(latestDobFor(15, new Date(2028, 1, 29)), { y: 2013, m: 2, d: 28 });
});

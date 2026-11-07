// Port of iOS BanbeAppTests/ReportsPresentationTests.swift — same fixtures, same expectations, so the web and iOS
// dashboards stay in lockstep (notes 43 + 46).
import test from 'node:test';
import assert from 'node:assert/strict';
import * as P from '../../src/lib/reportsPresentation.js';

const vi = (v) => v;
const en = (_v, e) => e;

const hostJSON = {
  success: true, scope: 'host', organizer_id: 'org_1',
  range: { start: '2026-10-01T02:15:30.25+00:00', end: '2026-10-03T16:59:59.999+00:00' },
  metrics: [
    { key: 'published_events', label: 'Sự kiện đã công khai', unit: 'count', value: 4 },
    { key: 'upcoming_events', label: 'Sắp diễn ra', unit: 'count', value: 2 },
    { key: 'confirmed_seats', label: 'Chỗ đã xác nhận', unit: 'count', value: 5,
      series: [{ d: '2026-10-01', v: 0 }, { d: '2026-10-02', v: 3 }, { d: '2026-10-03', v: 2 }],
      rows: [{ id: 'b1', event_name: '=SUM(A1), Phở', qty: 3, at: '2026-10-02T03:04:05.123+00:00' },
        { id: 'b2', event_name: 'Supper "club"', qty: 2, at: '2026-10-03T20:00:00+00:00' }] },
    { key: 'check_ins', label: 'Đã check-in', unit: 'count', value: 0,
      series: [{ d: '2026-10-01', v: 0 }, { d: '2026-10-02', v: 0 }, { d: '2026-10-03', v: 0 }] },
    { key: 'confirmed_payment_amount', label: 'Số tiền thanh toán đã xác nhận', unit: 'vnd', value: 1250000,
      series: [{ d: '2026-10-01', v: 0 }, { d: '2026-10-02', v: 750000 }, { d: '2026-10-03', v: 500000 }] },
    { key: 'refunds_owed', label: 'Hoàn tiền còn nợ', unit: 'vnd', value: 300000,
      rows: [{ id: 'r1', event_name: 'Gallery night', amount_vnd: 300000, due_at: '2026-09-30T00:00:00+00:00', overdue: true }] },
    { key: 'refunds_overdue', label: 'Hoàn tiền quá hạn', unit: 'count', value: 1 },
  ],
};

const personalJSON = {
  success: true, scope: 'personal',
  range: { start: '2026-10-01T02:15:30.25+00:00', end: '2026-10-03T16:59:59.999+00:00' },
  metrics: [
    { key: 'saved_events', label: 'Sự kiện đã lưu', unit: 'count', value: 0, rows: [] },
    { key: 'confirmed_bookings', label: 'Đặt chỗ đã xác nhận', unit: 'count', value: 1,
      series: [{ d: '2026-10-01', v: 1 }, { d: '2026-10-02', v: 0 }, { d: '2026-10-03', v: 0 }],
      rows: [{ id: 'b9', event_name: 'Music', qty: 1, at: '2026-10-01T10:00:00+00:00' }] },
    { key: 'attended_events', label: 'Đã tham dự', unit: 'count', value: 0,
      series: [{ d: '2026-10-01', v: 0 }, { d: '2026-10-02', v: 0 }, { d: '2026-10-03', v: 0 }], rows: [] },
    { key: 'upcoming_events', label: 'Sắp diễn ra', unit: 'count', value: 1,
      rows: [{ id: 'b9', event_name: 'Music', starts_at: '2026-10-20T12:00:00+00:00' }] },
    { key: 'outstanding_refunds', label: 'Hoàn tiền đang chờ', unit: 'vnd', value: 0, rows: [] },
  ],
};

const adminJSON = {
  success: true, scope: 'admin',
  range: { start: '2026-10-01T02:15:30.25+00:00', end: '2026-10-03T16:59:59.999+00:00' },
  metrics: [
    { key: 'pending_event_reviews', label: 'Sự kiện chờ duyệt', unit: 'count', value: 2,
      rows: [{ id: 'e1', event_name: 'A', submitted_at: '2026-10-01T00:00:00+00:00', age_days: 2.5 }] },
    { key: 'unresolved_disputes', label: 'Tranh chấp chưa xử lý', unit: 'count', value: 0, rows: [] },
    { key: 'backlog_avg_age_days', label: 'Tuổi trung bình hàng chờ (ngày)', unit: 'days', value: 2.5 },
    { key: 'platform_new_events', label: 'Sự kiện mới toàn nền tảng', unit: 'count', value: 3,
      series: [{ d: '2026-10-01', v: 1 }, { d: '2026-10-02', v: 2 }, { d: '2026-10-03', v: 0 }] },
    { key: 'platform_new_bookings', label: 'Đặt chỗ mới toàn nền tảng', unit: 'count', value: 0,
      series: [{ d: '2026-10-01', v: 0 }, { d: '2026-10-02', v: 0 }, { d: '2026-10-03', v: 0 }] },
  ],
};

const dash = (json, T) => P.dashboard(json, 'personal', T);
const keys = (list) => list.map(m => m.key);

// MARK: role ordering

test('host ordering and attention', () => {
  const d = dash(hostJSON, en);
  assert.equal(d.role, 'host');
  assert.equal(d.primary.key, 'confirmed_seats');
  assert.equal(d.attentionFirst, false);
  assert.deepEqual(keys(d.attention), ['refunds_overdue', 'refunds_owed']);
  assert.equal(d.attention[0].severity, 'overdue');
  // Flagged refunds are not repeated in the overview.
  assert.deepEqual(keys(d.overview), ['confirmed_payment_amount', 'upcoming_events', 'published_events', 'check_ins']);
  assert.deepEqual(keys(d.trends), ['confirmed_payment_amount', 'check_ins']);
  assert.equal(d.all.length, 7);
});

test('personal zero refunds stay in overview, not attention', () => {
  const d = dash(personalJSON, en);
  assert.equal(d.role, 'personal');
  assert.equal(d.primary.key, 'confirmed_bookings');
  assert.equal(d.attention.length, 0, 'a zero backlog is never "needs attention"');
  assert.deepEqual(keys(d.overview), ['upcoming_events', 'attended_events', 'saved_events', 'outstanding_refunds']);
  assert.deepEqual(keys(d.trends), ['attended_events']);
});

test('admin leads with backlog', () => {
  const d = dash(adminJSON, vi);
  assert.equal(d.role, 'admin');
  assert.equal(d.attentionFirst, true);
  assert.deepEqual(keys(d.attention), ['pending_event_reviews']);
  assert.equal(d.attention[0].message, 'Sự kiện chờ lâu nhất: 2,5 ngày.');
  assert.equal(d.primary.key, 'platform_new_bookings');
  assert.deepEqual(keys(d.overview), ['unresolved_disputes', 'backlog_avg_age_days', 'platform_new_events']);
});

test('personal refund message counts host-marked-sent', () => {
  const d = dash({ success: true, scope: 'personal', metrics: [
    { key: 'outstanding_refunds', label: 'Hoàn tiền đang chờ', unit: 'vnd', value: 500000,
      rows: [{ id: 'a', status: 'owed', amount_vnd: 200000 }, { id: 'b', status: 'host_marked_sent', amount_vnd: 300000 }] }] }, en);
  assert.equal(d.attention.length, 1);
  assert.equal(d.attention[0].valueText, '500,000₫');
  assert.equal(d.attention[0].message, "1 marked as sent by the host. Confirm once you've received it.");
});

test('unknown metric is kept with its server label', () => {
  const d = dash({ success: true, scope: 'host', metrics: [{ key: 'brand_new_metric', label: 'Chỉ số mới', unit: 'count', value: 7 }] }, en);
  assert.deepEqual(d.overview.map(m => m.title), ['Chỉ số mới']);
  assert.equal(d.primary, null);
});

test('failed or empty payload is an empty dashboard', () => {
  const d = dash({ success: true, scope: 'admin', metrics: [] }, en);
  assert.equal(d.isEmpty, true);
  assert.equal(d.attention.length, 0);
});

// MARK: series honesty

test('series summary comes from real points only', () => {
  const d = dash(hostJSON, en);
  const s = d.primary.summary;
  assert.equal(s.total, 5);
  assert.equal(s.activeDays, 2);
  assert.equal(s.dayCount, 3);
  assert.equal(s.peak.dayKey, '2026-10-02');
  assert.equal(P.seriesSentence(d.primary, en), 'Total 5 over 3 days, active on 2. Peak 3 on 02/10.');
});

test('all-zero series has no peak', () => {
  const checkIns = dash(hostJSON, en).all.find(m => m.key === 'check_ins');
  assert.equal(checkIns.summary.hasActivity, false);
  assert.equal(checkIns.summary.peak, null);
  assert.equal(P.seriesSentence(checkIns, en), 'No activity across 3 days.');
});

test('point-in-time metrics are never series', () => {
  const d = dash(hostJSON, en);
  for (const key of ['published_events', 'upcoming_events', 'refunds_owed', 'refunds_overdue']) {
    const m = d.all.find(x => x.key === key);
    assert.equal(m.isTimeSeries, false, key);
    assert.equal(m.summary, null, key);
  }
});

test('peak tie goes to the earliest day', () => {
  const pts = P.seriesPoints([{ d: '2026-10-03', v: 2 }, { d: '2026-10-01', v: 2 }, { d: '2026-10-02', v: 0 }]);
  assert.deepEqual(pts.map(p => p.dayKey), ['2026-10-01', '2026-10-02', '2026-10-03']);
  assert.equal(P.summarize(pts).peak.dayKey, '2026-10-01');
});

// MARK: formatting

test('value formatting per language', () => {
  assert.equal(P.formatValue(1250000, 'money', 'x', vi), '1.250.000₫');
  assert.equal(P.formatValue(1250000, 'money', 'x', en), '1,250,000₫');
  assert.equal(P.formatValue(1250000, 'money', 'x', en, true), '1,250,000 dong');
  assert.equal(P.formatValue(12345, 'count', 'x', vi), '12.345');
  assert.equal(P.formatValue(2.5, 'days', 'x', vi), '2,5 ngày');
  assert.equal(P.formatValue(1, 'days', 'x', en), '1 day');
  assert.equal(P.formatValue(0, 'days', 'backlog_avg_age_days', en), 'No backlog');
});

test('compact axis labels', () => {
  assert.equal(P.compact(750000, 'money', vi), '750k');
  assert.equal(P.compact(1200000, 'money', vi), '1,2tr');
  assert.equal(P.compact(1200000, 'money', en), '1.2M');
  assert.equal(P.compact(42, 'count', en), '42');
});

test('range text parses fractional and plain timestamps', () => {
  assert.equal(P.rangeText({ start: '2026-10-01T02:15:30.25+00:00', end: '2026-10-03T16:59:59.999+00:00' }), '01/10/2026 – 03/10/2026');
  assert.equal(P.rangeText({ start: '2026-10-01T00:00:00+00:00', end: '2026-10-02T00:00:00+00:00' }), '01/10/2026 – 02/10/2026');
  assert.equal(P.rangeText(null), '');
});

test('day buckets are calendar days, independent of the browser timezone', () => {
  assert.equal(P.formatDay(P.parseDay('2026-10-02')), '02/10');
  assert.equal(P.parseDay('2026-10-02').toISOString(), '2026-10-02T00:00:00.000Z');
});

// MARK: rows

test('rows use localized labels and hide ids', () => {
  const rows = P.rows(hostJSON.metrics.find(m => m.key === 'refunds_owed'), en);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].title, 'Gallery night');
  assert.equal(rows[0].flagged, true);
  assert.deepEqual(rows[0].fields.map(f => f.label), ['Amount', 'Refund due', 'Overdue']);
  assert.deepEqual(rows[0].fields.map(f => f.value), ['300,000₫', '30/09/2026 07:00', 'Yes']);
  assert.ok(!rows[0].fields.some(f => f.value === 'r1'), 'internal ids stay export-only');
});

test('status labels are localized', () => {
  assert.equal(P.cell('status', 'host_marked_sent', vi), 'Host báo đã gửi');
  assert.equal(P.cell('status', 'owed', en), 'Waiting for host refund');
  assert.equal(P.cell('due_at', null, en), null);
});

// MARK: visual refinement pass (note 46)

test('meaning follows role and falls back honestly', () => {
  const host = dash(hostJSON, en), personal = dash(personalJSON, en);
  assert.equal(P.meaning(host.all.find(m => m.key === 'upcoming_events'), 'host', en), 'Live and not started yet');
  assert.equal(P.meaning(personal.all.find(m => m.key === 'upcoming_events'), 'personal', en), 'Booked events still ahead');
  // Payment amount is never called revenue (migration 097's own rule).
  assert.ok(!P.meaning(host.all.find(m => m.key === 'confirmed_payment_amount'), 'host', en).toLowerCase().includes('revenue'));
  const unknown = P.metric({ key: 'future_metric', label: 'Mới', unit: 'count', value: 2 }, en);
  assert.equal(P.meaning(unknown, 'host', en), 'Right now');
  assert.equal(P.symbolFor('future_metric'), 'chart');
});

test('daily average is the total over every day', () => {
  const host = dash(hostJSON, en);
  const seats = host.all.find(m => m.key === 'confirmed_seats'); // 0,3,2 over 3 days
  assert.equal(P.dailyAverageText(seats.summary, 'count', en), '1.7/day');
  assert.equal(P.dailyAverageText(seats.summary, 'count', vi), '1,7/ngày');
  const amount = host.all.find(m => m.key === 'confirmed_payment_amount'); // 1,250,000 over 3 days
  assert.equal(P.dailyAverageText(amount.summary, 'money', en), '417K₫/day');
});

test('overdue card opens the owed claims', () => {
  const d = dash(hostJSON, en);
  const overdue = d.attention.find(a => a.key === 'refunds_overdue');
  assert.equal(overdue.targetKey, 'refunds_owed');
  assert.equal(P.attentionAction(overdue, en), 'See overdue claims');
  assert.equal(d.attention.find(a => a.key === 'refunds_owed').targetKey, 'refunds_owed');
  const bare = dash({ success: true, scope: 'host', metrics: [{ key: 'refunds_overdue', label: 'Hoàn tiền quá hạn', unit: 'count', value: 2 }] }, en).attention[0];
  assert.equal(bare.targetKey, 'refunds_overdue');
  assert.equal(P.attentionAction(bare, en), 'Open details');
});

test('breakdowns only from real rows', () => {
  const host = dash(hostJSON, en);
  assert.equal(host.insights.length, 1);
  assert.equal(host.insights[0].type, 'share');
  assert.equal(host.insights[0].caption, '1 of 1 owed refund claim overdue');
  const admin = dash(adminJSON, en);
  assert.deepEqual(admin.insights.map(i => i.title), ['Open backlog', 'How long items have waited']);
  assert.deepEqual(admin.insights[1].segments.map(s => s.count), [0, 1, 0, 0]); // 2.5 days -> "1–3 days"
  assert.equal(dash(personalJSON, en).insights.length, 0);
});

// Note 66 follow-up: every metric Host Home's KPI tiles can show has a short tile label in both languages.
import { METRIC_SHORT_LABEL, shortMetricLabel } from '../../src/lib/reportMetricLabels.js';
import { layoutFor as hostLayoutFor } from '../../src/lib/reportsPresentation.js';
test('Host Home KPI tiles: a short label exists for every host metric', () => {
  const host = hostLayoutFor('host');
  for (const key of [host.primary, ...host.overview]) {
    const l = METRIC_SHORT_LABEL[key];
    assert.ok(l && l.vi && l.en, `missing short label for ${key}`);
    assert.ok(l.en.length <= 20 && l.vi.length <= 20, `short label too long for ${key}`);
    assert.equal(shortMetricLabel(key, (vi, en) => en), l.en);
  }
  assert.equal(shortMetricLabel('nope', (vi) => vi), null);
});

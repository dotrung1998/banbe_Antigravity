// Metrics & Reports dashboard — pure mapping from the canonical
// `get_account_kpis` payload (migration 097) to what the dashboard shows.
// Port of iOS `Lib/ReportsPresentation.swift` (notes 43 + 46), same rules and
// same wording, so both platforms say the same thing about the same numbers.
// No React, no network: unit-tested in tests/unit/reportsPresentation.test.mjs.
//
// Honesty rules (read before adding anything):
// - Only numbers the RPC returned are shown. There is no previous-period
//   query, so there are NO deltas/growth badges anywhere.
// - A metric without `series` is a point-in-time total and is never charted.
// - Derived stats (peak day, active days, daily average) come only from the
//   returned `series`, and are hidden when the series has no activity.

import { metricLabel } from './reportMetricLabels.js';

const isVI = (T) => T('vi', 'en') === 'vi';

export function reportRole(scope) {
  return ['personal', 'host', 'admin'].includes(scope) ? scope : 'personal';
}

export function roleLabel(role, T) {
  return { personal: T('Cá nhân', 'Personal'), host: T('Tổ chức', 'Host'), admin: T('Quản trị', 'Admin') }[role];
}

export function valueKind(unit) {
  return unit === 'vnd' ? 'money' : unit === 'days' ? 'days' : 'count';
}

// MARK: formatting

/** 1.250.000 (VI) · 1,250,000 (EN) — never the device locale, so tests and both platforms agree. */
export function groupedInteger(n, T) {
  const sep = isVI(T) ? '.' : ',';
  const r = Math.round(Number(n) || 0);
  const s = String(Math.abs(r)).replace(/\B(?=(\d{3})+(?!\d))/g, sep);
  return r < 0 ? `-${s}` : s;
}

function decimal1(n, T) {
  const r = Math.round(n * 10) / 10;
  const whole = Math.trunc(r);
  const frac = Math.round(Math.abs(r - whole) * 10);
  const head = groupedInteger(whole, T);
  return frac ? `${r < 0 && whole === 0 ? '-' : ''}${head}${isVI(T) ? ',' : '.'}${frac}` : head;
}

export function formatDays(n, T) {
  const s = decimal1(n, T);
  return T(`${s} ngày`, n === 1 ? `${s} day` : `${s} days`);
}

export function formatValue(n, kind, metricKey, T, spoken = false) {
  if (kind === 'money') {
    const amount = groupedInteger(n, T);
    return spoken ? T(`${amount} đồng`, `${amount} dong`) : `${amount}₫`;
  }
  if (kind === 'days') {
    // The server coalesces an empty backlog's average age to 0.
    if (metricKey === 'backlog_avg_age_days' && n === 0) return T('Không có hàng chờ', 'No backlog');
    return formatDays(n, T);
  }
  return groupedInteger(n, T);
}

/** Short axis label: 750k / 1,2tr (VI) · 750K / 1.2M (EN). */
export function compact(n, kind, T) {
  if (!(kind === 'money' || Math.abs(n) >= 10000)) return groupedInteger(n, T);
  const vi = isVI(T);
  const trim = (v) => {
    const s = v >= 10 || v === Math.round(v) ? String(Math.round(v)) : v.toFixed(1);
    return vi ? s.replace('.', ',') : s;
  };
  if (Math.abs(n) >= 1e9) return trim(n / 1e9) + (vi ? 'tỷ' : 'B');
  if (Math.abs(n) >= 1e6) return trim(n / 1e6) + (vi ? 'tr' : 'M');
  if (Math.abs(n) >= 1e3) return trim(n / 1e3) + (vi ? 'k' : 'K');
  return trim(n);
}

// MARK: dates

/** Postgres timestamptz carries fractional seconds only when non-zero; Date parses both. */
export function parseTimestamp(s) {
  if (typeof s !== 'string') return null;
  const t = Date.parse(s);
  return Number.isFinite(t) ? new Date(t) : null;
}

/** A series bucket is a calendar day, not an instant — read in UTC so no browser timezone can shift it. */
export function parseDay(s) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(s || ''));
  if (!m) return null;
  return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
}

const pad2 = (n) => String(n).padStart(2, '0');
export function formatDay(d) {
  return `${pad2(d.getUTCDate())}/${pad2(d.getUTCMonth() + 1)}`;
}

/** dd/MM/yyyy [HH:mm] in Asia/Ho_Chi_Minh (UTC+7, no DST). */
export function formatDate(d, withTime) {
  const v = new Date(d.getTime() + 7 * 3600000);
  const day = `${pad2(v.getUTCDate())}/${pad2(v.getUTCMonth() + 1)}/${v.getUTCFullYear()}`;
  return withTime ? `${day} ${pad2(v.getUTCHours())}:${pad2(v.getUTCMinutes())}` : day;
}

export function rangeText(range) {
  const s = parseTimestamp(range?.start), e = parseTimestamp(range?.end);
  if (!s || !e) return '';
  return `${formatDate(s, false)} – ${formatDate(e, false)}`;
}

// MARK: series

export function seriesPoints(raw) {
  return (raw || [])
    .map(p => ({ dayKey: p.d, date: parseDay(p.d), value: Number(p.v) || 0 }))
    .filter(p => p.date)
    .sort((a, b) => a.date - b.date);
}

export function summarize(points) {
  const total = points.reduce((a, p) => a + p.value, 0);
  // Earliest day wins a tie, so the peak is stable.
  let peak = null;
  for (const p of points) if (p.value > 0 && (!peak || p.value > peak.value)) peak = p;
  const activeDays = points.filter(p => p.value > 0).length;
  const dayCount = points.length;
  return { total, peak, activeDays, dayCount, hasActivity: activeDays > 0, dailyAverage: dayCount > 0 ? total / dayCount : 0 };
}

export function metric(m, T) {
  const kind = valueKind(m.unit);
  const number = typeof m.value === 'number' ? m.value : null;
  const series = seriesPoints(m.series);
  const raw = m.value == null ? '' : String(m.value);
  return {
    key: m.key,
    title: metricLabel(m, T),
    kind,
    number,
    valueText: number != null ? formatValue(number, kind, m.key, T) : (raw || '—'),
    accessibilityValue: number != null ? formatValue(number, kind, m.key, T, true) : '—',
    series,
    summary: series.length ? summarize(series) : null,
    rowCount: (m.rows || []).length,
    isTimeSeries: series.length > 0,
  };
}

/** One sentence for screen readers and the large-text fallback. */
export function seriesSentence(m, T) {
  const s = m.summary;
  if (!s) return T('Số liệu hiện tại.', 'Current total.');
  if (!s.hasActivity || !s.peak) return T(`Không có hoạt động trong ${s.dayCount} ngày.`, `No activity across ${s.dayCount} days.`);
  const peakValue = formatValue(s.peak.value, m.kind, m.key, T, true);
  return T(
    `Tổng ${m.accessibilityValue} trong ${s.dayCount} ngày, có hoạt động ${s.activeDays} ngày. Cao nhất ${peakValue} vào ${formatDay(s.peak.date)}.`,
    `Total ${m.accessibilityValue} over ${s.dayCount} days, active on ${s.activeDays}. Peak ${peakValue} on ${formatDay(s.peak.date)}.`,
  );
}

/** "0.4/day" · "41K₫/day" — the series total over every day in the range (zero days included). */
export function dailyAverageText(summary, kind, T) {
  const n = summary.dailyAverage;
  const value = kind === 'money' ? `${compact(n, 'money', T)}₫` : n >= 10 ? groupedInteger(n, T) : decimal1(n, T);
  return T(`${value}/ngày`, `${value}/day`);
}

// MARK: role layout

export function layoutFor(role) {
  switch (role) {
    case 'host':
      return { primary: 'confirmed_seats',
        overview: ['confirmed_payment_amount', 'upcoming_events', 'published_events', 'check_ins', 'refunds_owed', 'refunds_overdue'],
        trends: ['confirmed_payment_amount', 'check_ins'], attentionFirst: false };
    case 'admin':
      return { primary: 'platform_new_bookings',
        overview: ['pending_event_reviews', 'unresolved_disputes', 'backlog_avg_age_days', 'platform_new_events'],
        trends: ['platform_new_events'], attentionFirst: true };
    default:
      return { primary: 'confirmed_bookings',
        overview: ['upcoming_events', 'attended_events', 'saved_events', 'outstanding_refunds'],
        trends: ['attended_events'], attentionFirst: false };
  }
}

// MARK: needs attention (only actionable, non-zero backlogs)

const num = (m) => (m && typeof m.value === 'number' ? m.value : 0);

export function attentionItems(role, metrics, T) {
  const find = (key) => metrics.find(m => m.key === key);
  const items = [];
  if (role === 'personal') {
    const m = find('outstanding_refunds');
    if (m && num(m) > 0) {
      const rows = m.rows || [];
      const marked = rows.filter(r => r.status === 'host_marked_sent').length;
      const message = marked > 0
        ? T(`${marked} khoản host báo đã gửi, hãy xác nhận khi bạn nhận được.`, `${marked} marked as sent by the host. Confirm once you've received it.`)
        : T(`Đang chờ host hoàn tiền cho ${rows.length} khoản.`, `Waiting for hosts to refund ${rows.length} claim${rows.length === 1 ? '' : 's'}.`);
      items.push({ key: m.key, severity: 'pending', title: metricLabel(m, T), valueText: formatValue(num(m), 'money', m.key, T), message, symbol: 'refund' });
    }
  } else if (role === 'host') {
    const over = find('refunds_overdue');
    const owed = find('refunds_owed');
    if (over && num(over) > 0) {
      const n = Math.trunc(num(over));
      items.push({
        key: over.key, severity: 'overdue', title: metricLabel(over, T), valueText: formatValue(num(over), 'count', over.key, T),
        message: T(`${n} khoản hoàn tiền đã quá hạn. Hãy hoàn tiền cho khách sớm nhất có thể.`,
          `${n} refund${n === 1 ? ' is' : 's are'} past the deadline. Refund the guest${n === 1 ? '' : 's'} as soon as you can.`),
        symbol: 'alert',
        // Refunds overdue is a bare count; its claims (each with an overdue flag) live under refunds owed.
        opens: owed && (owed.rows || []).length ? 'refunds_owed' : null,
      });
    }
    if (owed && num(owed) > 0) {
      const claims = (owed.rows || []).length;
      items.push({
        key: owed.key, severity: 'pending', title: metricLabel(owed, T), valueText: formatValue(num(owed), 'money', owed.key, T),
        message: T(`Còn nợ khách ${claims} khoản hoàn tiền.`, `${claims} refund claim${claims === 1 ? '' : 's'} still owed to guests.`),
        symbol: 'refund',
      });
    }
  } else if (role === 'admin') {
    const avgAge = num(find('backlog_avg_age_days'));
    const reviews = find('pending_event_reviews');
    if (reviews && num(reviews) > 0) {
      const ages = (reviews.rows || []).map(r => r.age_days).filter(a => typeof a === 'number');
      const message = ages.length
        ? T(`Sự kiện chờ lâu nhất: ${formatDays(Math.max(...ages), T)}.`, `Oldest waiting: ${formatDays(Math.max(...ages), T)}.`)
        : T('Đang chờ duyệt.', 'Waiting for review.');
      items.push({ key: reviews.key, severity: 'pending', title: metricLabel(reviews, T), valueText: formatValue(num(reviews), 'count', reviews.key, T), message, symbol: 'tray' });
    }
    const disputes = find('unresolved_disputes');
    if (disputes && num(disputes) > 0) {
      items.push({
        key: disputes.key, severity: 'urgent', title: metricLabel(disputes, T), valueText: formatValue(num(disputes), 'count', disputes.key, T),
        message: T(`Tuổi trung bình hàng chờ: ${formatDays(avgAge, T)}.`, `Average backlog age: ${formatDays(avgAge, T)}.`),
        symbol: 'dispute',
      });
    }
  }
  return items.map(i => ({ opens: null, ...i, targetKey: i.opens || i.key }));
}

/** What tapping an attention card actually shows: the claims/queue rows. */
export function attentionAction(item, T) {
  switch (item.key) {
    case 'outstanding_refunds': return T('Xem các khoản hoàn tiền', 'See refund claims');
    case 'refunds_overdue': return item.opens ? T('Xem khoản quá hạn', 'See overdue claims') : T('Mở chi tiết', 'Open details');
    case 'refunds_owed': return T('Xem các khoản còn nợ', 'See claims owed');
    case 'pending_event_reviews': return T('Xem hàng chờ duyệt', 'See the review queue');
    case 'unresolved_disputes': return T('Xem tranh chấp đang mở', 'See open disputes');
    default: return T('Mở chi tiết', 'Open details');
  }
}

export function severityBadge(severity, T) {
  return { overdue: T('Quá hạn', 'Overdue'), urgent: T('Cần xử lý sớm', 'Act soon'), pending: T('Cần xử lý', 'Needs action') }[severity];
}

// MARK: breakdowns (only what the payload supports)

export function insights(role, metrics, T) {
  const find = (key) => metrics.find(m => m.key === key);
  const out = [];
  if (role === 'personal') {
    const m = find('outstanding_refunds');
    const rows = m?.rows || [];
    if (rows.length) {
      const segments = [
        { id: 'owed', label: statusLabel('owed', T), count: rows.filter(r => r.status === 'owed').length },
        { id: 'host_marked_sent', label: statusLabel('host_marked_sent', T), count: rows.filter(r => r.status === 'host_marked_sent').length },
      ].filter(s => s.count > 0);
      if (segments.length) out.push({ type: 'distribution', key: m.key, title: T('Hoàn tiền đang chờ theo trạng thái', 'Pending refunds by status'), segments });
    }
  } else if (role === 'host') {
    const m = find('refunds_owed');
    const rows = m?.rows || [];
    if (rows.length) {
      const overdue = rows.filter(r => r.overdue === true).length;
      out.push({
        type: 'share', key: m.key, title: T('Hoàn tiền đã quá hạn', 'Refunds past their deadline'),
        numerator: overdue, denominator: rows.length,
        caption: T(`${overdue}/${rows.length} khoản hoàn tiền còn nợ đã quá hạn`, `${overdue} of ${rows.length} owed refund claim${rows.length === 1 ? '' : 's'} overdue`),
      });
    }
  } else if (role === 'admin') {
    const reviews = find('pending_event_reviews'), disputes = find('unresolved_disputes');
    const r = Math.round(num(reviews)), d = Math.round(num(disputes));
    const key = r > 0 ? 'pending_event_reviews' : 'unresolved_disputes';
    if (r + d > 0) {
      out.push({
        type: 'distribution', key, title: T('Hàng chờ đang mở', 'Open backlog'),
        segments: [
          { id: 'reviews', label: T('Sự kiện chờ duyệt', 'Event reviews'), count: r },
          { id: 'disputes', label: T('Tranh chấp', 'Disputes'), count: d },
        ].filter(s => s.count > 0),
      });
    }
    const ages = [reviews, disputes].filter(Boolean).flatMap(m => (m.rows || []).map(x => x.age_days).filter(a => typeof a === 'number'));
    if (ages.length) {
      const buckets = [
        ['lt1', 'Dưới 1 ngày', 'Under 1 day', a => a < 1],
        ['1to3', '1–3 ngày', '1–3 days', a => a >= 1 && a < 3],
        ['3to7', '3–7 ngày', '3–7 days', a => a >= 3 && a < 7],
        ['7plus', 'Từ 7 ngày', '7+ days', a => a >= 7],
      ];
      out.push({
        type: 'distribution', key, title: T('Thời gian chờ của hàng chờ', 'How long items have waited'),
        segments: buckets.map(([id, vi, en, test]) => ({ id, label: T(vi, en), count: ages.filter(test).length })),
      });
    }
  }
  return out.map(i => ({ ...i, id: i.type === 'share' ? `share.${i.key}` : `dist.${i.key}.${i.title}`, total: i.segments ? i.segments.reduce((a, s) => a + s.count, 0) : undefined }));
}

export function insightSentence(i, T) {
  if (i.type === 'share') return `${i.caption}.`;
  const parts = i.segments.map(s => `${s.label}: ${s.count}`).join(', ');
  return T(`${i.title}. Tổng ${i.total}. ${parts}.`, `${i.title}. Total ${i.total}. ${parts}.`);
}

// MARK: dashboard

export function dashboard(report, fallbackScope, T) {
  const role = reportRole(report?.scope || fallbackScope);
  const metrics = report?.metrics || [];
  const all = metrics.map(m => metric(m, T));
  const byKey = new Map();
  for (const m of all) if (!byKey.has(m.key)) byKey.set(m.key, m);
  const layout = layoutFor(role);

  const attention = attentionItems(role, metrics, T);
  const attentionKeys = new Set(attention.map(a => a.key));
  // Refunds overdue is a subset of refunds owed: when either is flagged, neither shows twice.
  const hidden = new Set(attentionKeys);
  if (attentionKeys.has('refunds_overdue') || attentionKeys.has('refunds_owed')) { hidden.add('refunds_owed'); hidden.add('refunds_overdue'); }
  // The disputes card already states the average backlog age.
  if (attentionKeys.has('unresolved_disputes')) hidden.add('backlog_avg_age_days');

  const known = new Set([layout.primary, ...layout.overview]);
  const overview = [
    ...layout.overview.map(k => byKey.get(k)).filter(Boolean).filter(m => !hidden.has(m.key)),
    // A metric the client doesn't know yet still shows (server label), never dropped.
    ...all.filter(m => !known.has(m.key) && !hidden.has(m.key)),
  ];
  const trends = layout.trends.map(k => byKey.get(k)).filter(m => m && m.isTimeSeries);

  return {
    role, primary: byKey.get(layout.primary) || null, overview, attention, trends, all,
    attentionFirst: layout.attentionFirst, insights: insights(role, metrics, T), isEmpty: all.length === 0,
  };
}

// MARK: what each number means

/** One line under a value, restating the RPC's own definition — never a judgement, target or comparison. */
export function meaning(m, role, T) {
  switch (`${role}:${m.key}`) {
    case 'personal:confirmed_bookings': return T('Đã thanh toán và xác nhận, đặt trong khoảng này', 'Paid and confirmed, booked in this range');
    case 'personal:attended_events': return T('Lượt check-in của bạn trong khoảng này', 'Your check-ins in this range');
    case 'personal:upcoming_events': return T('Sự kiện bạn đã đặt, chưa diễn ra', 'Booked events still ahead');
    case 'personal:saved_events': return T('Đang có trong mục đã lưu', 'On your saved list now');
    case 'personal:outstanding_refunds': return T('Hoàn tiền bạn chưa nhận', "Refunds you haven't received yet");
    case 'host:confirmed_seats': return T('Số chỗ trong các đặt chỗ đã thanh toán trong khoảng này', 'Seats in paid bookings made in this range');
    case 'host:confirmed_payment_amount': return T('Tổng các đặt chỗ đã xác nhận trong khoảng này', 'Sum of confirmed bookings in this range');
    case 'host:check_ins': return T('Khách đã check-in trong khoảng này', 'Guests checked in during this range');
    case 'host:upcoming_events': return T('Đang mở bán, chưa bắt đầu', 'Live and not started yet');
    case 'host:published_events': return T('Đang mở hoặc đã kết thúc, từ trước đến nay', 'Live or ended, all time');
    case 'host:refunds_owed': return T('Còn phải hoàn cho khách', 'Still to refund to guests');
    case 'host:refunds_overdue': return T('Đã quá hạn hoàn tiền', 'Past the refund deadline');
    case 'admin:platform_new_bookings': return T('Đặt chỗ mới trên banbe trong khoảng này, mọi trạng thái', 'New bookings on banbe in this range, any status');
    case 'admin:platform_new_events': return T('Sự kiện tạo trong khoảng này, mọi trạng thái', 'Events created in this range, any status');
    case 'admin:pending_event_reviews': return T('Đang chờ trong hàng duyệt', 'Waiting in the review queue');
    case 'admin:unresolved_disputes': return T('Tranh chấp đặt chỗ và hoàn tiền đang mở', 'Open booking and refund disputes');
    case 'admin:backlog_avg_age_days': return T('Tính trên duyệt và tranh chấp đang mở', 'Across open reviews and disputes');
    default: return m.isTimeSeries ? T('Trong khoảng đã chọn', 'In this range') : T('Hiện tại', 'Right now');
  }
}

/** A neutral glyph name per metric, decoration only (always next to its title). */
export function symbolFor(key) {
  switch (key) {
    case 'saved_events': return 'bookmark';
    case 'confirmed_bookings': case 'platform_new_bookings': return 'ticket';
    case 'attended_events': case 'check_ins': return 'check';
    case 'upcoming_events': return 'calendar';
    case 'outstanding_refunds': case 'refunds_owed': return 'refund';
    case 'refunds_overdue': return 'alert';
    case 'published_events': return 'megaphone';
    case 'confirmed_seats': return 'people';
    case 'confirmed_payment_amount': return 'money';
    case 'pending_event_reviews': return 'tray';
    case 'unresolved_disputes': return 'dispute';
    case 'backlog_avg_age_days': return 'hourglass';
    case 'platform_new_events': return 'sparkle';
    default: return 'chart';
  }
}

// MARK: underlying rows (localized, never raw field keys)

/** Display order of known columns; `id`/`event_id` are export-only. */
export const COLUMN_ORDER = ['qty', 'amount_vnd', 'status', 'starts_at', 'at', 'since', 'due_at', 'submitted_at', 'disputed_at', 'age_days', 'overdue'];
export const HIDDEN_COLUMNS = new Set(['id', 'event_id', 'event_name']);

export function columnLabel(key, T) {
  switch (key) {
    case 'event_name': return T('Sự kiện', 'Event');
    case 'qty': return T('Số chỗ', 'Seats');
    case 'at': return T('Thời gian', 'When');
    case 'starts_at': return T('Bắt đầu', 'Starts');
    case 'amount_vnd': return T('Số tiền', 'Amount');
    case 'status': return T('Trạng thái', 'Status');
    case 'since': return T('Từ ngày', 'Since');
    case 'due_at': return T('Hạn hoàn tiền', 'Refund due');
    case 'overdue': return T('Quá hạn', 'Overdue');
    case 'submitted_at': return T('Gửi duyệt', 'Submitted');
    case 'disputed_at': return T('Mở tranh chấp', 'Disputed');
    case 'age_days': return T('Đã chờ', 'Waiting');
    default: return key.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
  }
}

export function statusLabel(raw, T) {
  switch (raw) {
    case 'owed': return T('Đang chờ host hoàn tiền', 'Waiting for host refund');
    case 'host_marked_sent': return T('Host báo đã gửi', 'Host marked as sent');
    case 'guest_confirmed': return T('Đã nhận', 'Received');
    case 'disputed': return T('Đang tranh chấp', 'Disputed');
    default: return raw;
  }
}

export function cell(key, value, T) {
  if (value == null) return null;
  if (key === 'amount_vnd' && typeof value === 'number') return formatValue(value, 'money', key, T);
  if (key === 'qty' && typeof value === 'number') return groupedInteger(value, T);
  if (key === 'age_days' && typeof value === 'number') return formatDays(value, T);
  if (key === 'status' && typeof value === 'string') return statusLabel(value, T);
  if (key === 'overdue' && typeof value === 'boolean') return value ? T('Có', 'Yes') : T('Không', 'No');
  if (typeof value === 'string' && (key === 'at' || key.endsWith('_at') || key === 'since')) {
    const d = parseTimestamp(value);
    return d ? formatDate(d, true) : value;
  }
  const s = typeof value === 'object' ? JSON.stringify(value) : String(value);
  return s === '' ? null : s;
}

export function rows(rawMetric, T) {
  return (rawMetric?.rows || []).map((row, i) => {
    const keys = [
      ...COLUMN_ORDER.filter(k => row[k] !== undefined),
      ...Object.keys(row).filter(k => !COLUMN_ORDER.includes(k) && !HIDDEN_COLUMNS.has(k)).sort(),
    ];
    const fields = keys.map(k => ({ label: columnLabel(k, T), value: cell(k, row[k], T) })).filter(f => f.value != null);
    const title = row.event_name == null ? '' : String(row.event_name);
    return { id: i, title: title || '—', fields, flagged: row.overdue === true };
  });
}

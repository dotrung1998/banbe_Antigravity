// Admin › Retention report (migration 196, admin_retention_report). Pure presentation helpers, no React.
// iOS twin: apps/ios/BanbeApp/Lib/RetentionReport.swift — same vectors in tests/unit/retentionReport.test.mjs and
// BanbeAppTests/RetentionReportTests.swift. The server already hides every group under 20 people: counts arrive as
// numbers or the string "<20" (shown verbatim), hidden rates and medians arrive as null (shown as "—").

export const RANGE_DAYS = [30, 90, 365];
export const DEFAULT_RANGE_DAYS = 90;
export const HIDDEN = '—';
const MARKET_ORDER = ['VN', 'US', 'unknown'];

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);

/** A count: a number (grouped), "<20" verbatim, anything else "—". */
export function fmtCount(v) {
  if (typeof v === 'string' && v.trim()) return v;
  if (isNum(v)) return Math.round(v).toLocaleString('en-US');
  return HIDDEN;
}

/** A 0..1 share as a percentage with one decimal ("12.5%", "40%"); null/hidden "—". */
export function fmtRate(v) {
  if (!isNum(v)) return HIDDEN;
  const pct = Math.round(v * 1000) / 10;
  return `${Number.isInteger(pct) ? pct : pct.toFixed(1)}%`;
}

/** A median (days or minutes) with at most one decimal; null/hidden "—". */
export function fmtMedian(v) {
  if (!isNum(v)) return HIDDEN;
  const r = Math.round(v * 10) / 10;
  return Number.isInteger(r) ? String(r) : r.toFixed(1);
}

/** "count · rate" for the returned rows; just the count when the rate is hidden. */
export function fmtCountRate(count, rate) {
  const c = fmtCount(count);
  return isNum(rate) ? `${c} · ${fmtRate(rate)}` : c;
}

/** Local YYYY-MM-DD. */
function ymd(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** The last `days` days up to and including today (device-local dates), as the RPC's p_from / p_to. */
export function rangeFor(days, now = new Date()) {
  const n = RANGE_DAYS.includes(days) ? days : DEFAULT_RANGE_DAYS;
  const to = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const from = new Date(to.getFullYear(), to.getMonth(), to.getDate() - (n - 1));
  return { from: ymd(from), to: ymd(to) };
}

/** VN, US, unknown — always all three, in that order (a market missing from the answer shows as hidden). */
export function orderedMarkets(markets) {
  const list = Array.isArray(markets) ? markets : [];
  return MARKET_ORDER.map(m => list.find(x => x?.market === m) || { market: m });
}

/** The labelled rows of one market's table: [{ key, vi, en, value }]. */
export function marketRows(m) {
  return [
    { key: 'people', vi: 'Người dùng', en: 'People', value: fmtCount(m.people) },
    { key: 'active', vi: 'Hoạt động trong kỳ', en: 'Active in period', value: fmtCount(m.active_people) },
    { key: 'new', vi: 'Mới trong kỳ', en: 'New in period', value: fmtCount(m.new_people) },
    { key: 'd7', vi: 'Quay lại tuần 2 (D7)', en: 'Back in week 2 (D7)', value: fmtCountRate(m.d7_returned, m.d7_rate) },
    { key: 'd30', vi: 'Quay lại tuần 5 (D30)', en: 'Back in week 5 (D30)', value: fmtCountRate(m.d30_returned, m.d30_rate) },
    { key: 'first', vi: 'Tham dự lần đầu', en: 'First attendance', value: fmtCount(m.first_attenders) },
    { key: 'second', vi: 'Tham dự lần 2 trong 60 ngày', en: 'Second within 60 days', value: fmtCountRate(m.second_within_60d, m.second_within_60d_rate) },
    { key: 'days', vi: 'Số ngày tới lần 2 (trung vị)', en: 'Median days to second', value: fmtMedian(m.days_to_second_median) },
  ];
}

export function marketLabel(market) {
  if (market === 'VN') return ['Việt Nam', 'Vietnam'];
  if (market === 'US') return ['Hoa Kỳ', 'United States'];
  return ['Chưa rõ', 'Unknown'];
}

/** Error code from the RPC answer: NOT_AUTHORIZED / NOT_DEPLOYED / NETWORK, or null when it is a real report. */
export function reportError(data, error) {
  if (error) return (error.code === 'PGRST202' || error.code === '42883') ? 'NOT_DEPLOYED' : 'NETWORK';
  if (!data || data.success !== true) return data?.error || 'NETWORK';
  return null;
}

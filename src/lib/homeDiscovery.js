// Home discovery: quick chips, filter sheet, sort, live counts, fill badges, "relax a filter" hints.
// Web twin of apps/ios/BanbeApp/Lib/HomeDiscovery.swift — keep both and their tests in sync
// (.claude/notes/50-discovery-home-host-recipe.md). Pure: no React, no network, no Date.now() inside.
//
// Item shape (already normalized by the caller, real and demo events alike):
//   { key, startsAt: number|null (ms), priceVnd: number|null (0 = free, null = unknown),
//     catKeys: string[], booked: number|null, capacity: number|null, soldOut: boolean,
//     distanceKm: number|null, popularity: number|null }
//
// Filters (all optional; DEFAULT_FILTERS = everything shown):
//   { date: 'any'|'today'|'tomorrow'|'weekend'|'week'|'on:YYYY-MM-DD',
//     priceMin: number|null, priceMax: number|null, free: boolean,
//     cats: string[] (empty = all), seatsLeft: boolean, almostFull: boolean }
//
// Day boundaries use a fixed UTC offset (minutes). Every launch market is Vietnam (UTC+7, no DST), so
// 420 is the default; pass another offset rather than reading the device zone, so tests are exact.

export const DEFAULT_OFFSET_MIN = 420;
export const DATE_OPTIONS = ['any', 'today', 'tomorrow', 'weekend', 'week'];
export const SORT_MODES = ['soonest', 'nearest', 'popular', 'price'];
export const DEFAULT_FILTERS = Object.freeze({
  date: 'any', priceMin: null, priceMax: null, free: false, cats: [], seatsLeft: false, almostFull: false,
});

const DAY = 86400000;
const HOUR = 3600000;

// ---- date windows ------------------------------------------------------------
// Local midnight (in the given offset) of the day containing `ms`.
function localMidnight(ms, offsetMin) {
  const off = offsetMin * 60000;
  return Math.floor((ms + off) / DAY) * DAY - off;
}
// 0 = Monday ... 6 = Sunday, in the given offset.
function localWeekday(ms, offsetMin) {
  const d = new Date(ms + offsetMin * 60000).getUTCDay(); // 0 = Sunday
  return (d + 6) % 7;
}

/** [start, end) in ms for a date option, or null for 'any'/unknown. The window never starts before `now`. */
export function dateWindow(option, now, offsetMin = DEFAULT_OFFSET_MIN) {
  const today = localMidnight(now, offsetMin);
  if (option === 'today') return [now, today + DAY];
  if (option === 'tomorrow') return [today + DAY, today + 2 * DAY];
  if (option === 'week') return [now, now + 7 * DAY];
  if (option === 'weekend') {
    // Friday 17:00 -> Monday 00:00 (Friday evening counts as the weekend; Mobilizon issue 773).
    // Mon-Thu: the coming weekend. Fri-Sun: the current one, from now.
    const wd = localWeekday(now, offsetMin);
    const friday = today + (4 - wd) * DAY; // wd 4 = Friday; negative offset for Sat/Sun lands on this week's Fri
    const start = friday + 17 * HOUR;
    const end = friday + 3 * DAY;
    return [Math.max(start, now), end];
  }
  if (typeof option === 'string' && option.startsWith('on:')) {
    const m = option.slice(3).match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (!m) return null;
    const start = Date.UTC(+m[1], +m[2] - 1, +m[3]) - offsetMin * 60000;
    return [Math.max(start, now), start + DAY];
  }
  return null;
}

// ---- fill --------------------------------------------------------------------
export const ALMOST_FULL_SEATS = 3;
export const ALMOST_FULL_SHARE = 0.2;
export const SOCIAL_PROOF_MIN = 5;

/** Seats-left / social-proof facts for one event. Unknown counts give nothing (never a guessed number). */
export function fillBadge(booked, capacity) {
  const out = { left: null, almostFull: false, soldOut: false, going: null };
  if (booked == null || !(capacity > 0)) return out;
  const left = Math.max(capacity - booked, 0);
  out.left = left;
  out.soldOut = left === 0;
  out.almostFull = left > 0 && (left <= ALMOST_FULL_SEATS || left / capacity <= ALMOST_FULL_SHARE);
  out.going = booked >= SOCIAL_PROOF_MIN ? booked : null;
  return out;
}

function seatsLeftOf(item) {
  const f = fillBadge(item.booked, item.capacity);
  if (f.left != null) return f.left;
  return item.soldOut ? 0 : null;
}

// ---- filtering ---------------------------------------------------------------
export function normalizeFilters(filters) {
  return { ...DEFAULT_FILTERS, ...(filters || {}), cats: [...((filters && filters.cats) || [])] };
}

function matches(item, f, now, offsetMin) {
  if (f.date && f.date !== 'any') {
    const w = dateWindow(f.date, now, offsetMin);
    if (w && (item.startsAt == null || item.startsAt < w[0] || item.startsAt >= w[1])) return false;
  }
  if (f.free && item.priceVnd !== 0) return false;
  if (f.priceMin != null && (item.priceVnd == null || item.priceVnd < f.priceMin)) return false;
  if (f.priceMax != null && (item.priceVnd == null || item.priceVnd > f.priceMax)) return false;
  if (f.cats.length && !(item.catKeys || []).some(c => f.cats.includes(c))) return false;
  if (f.seatsLeft) {
    const left = seatsLeftOf(item);
    if (left === 0 || item.soldOut) return false;
  }
  if (f.almostFull && !fillBadge(item.booked, item.capacity).almostFull) return false;
  return true;
}

export function applyDiscoveryFilters(items, filters, now, offsetMin = DEFAULT_OFFSET_MIN) {
  const f = normalizeFilters(filters);
  return (items || []).filter(it => matches(it, f, now, offsetMin));
}

/** Number of non-default filters (the badge on the Filters button). */
export function activeFilterCount(filters) {
  const f = normalizeFilters(filters);
  let n = 0;
  if (f.date !== 'any') n++;
  if (f.priceMin != null || f.priceMax != null) n++;
  if (f.free) n++;
  if (f.cats.length) n++;
  if (f.seatsLeft) n++;
  if (f.almostFull) n++;
  return n;
}

/**
 * Count for each option of one dimension, with every OTHER active filter applied — what the user
 * would get if they tapped that pill ("This weekend · 8"). Boolean dimensions report the `true` count.
 */
export function optionCounts(items, filters, dimension, options, now, offsetMin = DEFAULT_OFFSET_MIN) {
  const f = normalizeFilters(filters);
  const out = {};
  if (dimension === 'date') {
    for (const opt of options || DATE_OPTIONS) out[opt] = applyDiscoveryFilters(items, { ...f, date: opt }, now, offsetMin).length;
  } else if (dimension === 'cats') {
    const others = { ...f, cats: [] };
    for (const c of options || []) out[c] = applyDiscoveryFilters(items, { ...others, cats: [c] }, now, offsetMin).length;
  } else if (dimension === 'free' || dimension === 'seatsLeft' || dimension === 'almostFull') {
    out.true = applyDiscoveryFilters(items, { ...f, [dimension]: true }, now, offsetMin).length;
  }
  return out;
}

const RELAXATIONS = [
  { id: 'date', active: f => f.date !== 'any', relax: f => ({ ...f, date: 'any' }) },
  { id: 'price', active: f => f.priceMin != null || f.priceMax != null, relax: f => ({ ...f, priceMin: null, priceMax: null }) },
  { id: 'free', active: f => f.free, relax: f => ({ ...f, free: false }) },
  { id: 'cats', active: f => f.cats.length > 0, relax: f => ({ ...f, cats: [] }) },
  { id: 'seatsLeft', active: f => f.seatsLeft, relax: f => ({ ...f, seatsLeft: false }) },
  { id: 'almostFull', active: f => f.almostFull, relax: f => ({ ...f, almostFull: false }) },
];

/**
 * "+6 events if you drop the date" — for empty / near-empty results. Each hint removes ONE active filter;
 * sorted by events gained (desc), then by the fixed order above. Only hints that add at least one event.
 */
export function relaxationHints(items, filters, now, offsetMin = DEFAULT_OFFSET_MIN, limit = 2) {
  const f = normalizeFilters(filters);
  const base = applyDiscoveryFilters(items, f, now, offsetMin).length;
  return RELAXATIONS
    .map((r, order) => {
      if (!r.active(f)) return null;
      const filtersAfter = r.relax(f);
      const gain = applyDiscoveryFilters(items, filtersAfter, now, offsetMin).length - base;
      return gain > 0 ? { id: r.id, gain, filters: filtersAfter, order } : null;
    })
    .filter(Boolean)
    .sort((a, b) => b.gain - a.gain || a.order - b.order)
    .slice(0, limit)
    .map(({ order, ...h }) => h);
}

// ---- sorting -----------------------------------------------------------------
const nullsLast = (a, b, cmp) => (a == null && b == null ? 0 : a == null ? 1 : b == null ? -1 : cmp(a, b));

/** Stable sort; ties keep the incoming order (so the caller's own ranking survives). */
export function sortEvents(items, mode) {
  const indexed = (items || []).map((it, i) => [it, i]);
  const by = {
    soonest: (a, b) => nullsLast(a.startsAt, b.startsAt, (x, y) => x - y),
    nearest: (a, b) => nullsLast(a.distanceKm, b.distanceKm, (x, y) => x - y),
    popular: (a, b) => nullsLast(a.popularity, b.popularity, (x, y) => y - x),
    price: (a, b) => nullsLast(a.priceVnd, b.priceVnd, (x, y) => x - y),
  }[mode];
  if (!by) return indexed.map(([it]) => it);
  return indexed.sort(([a, i], [b, j]) => by(a, b) || i - j).map(([it]) => it);
}

// ---- price distribution --------------------------------------------------------
export function median(values) {
  const v = (values || []).filter(x => typeof x === 'number' && Number.isFinite(x)).sort((a, b) => a - b);
  if (!v.length) return null;
  const mid = Math.floor(v.length / 2);
  return v.length % 2 ? v[mid] : (v[mid - 1] + v[mid]) / 2;
}

/** Equal-width histogram of paid prices. Returns { min, max, counts[] } or null when there are no paid prices. */
export function priceHistogram(prices, buckets = 12) {
  const v = (prices || []).filter(p => typeof p === 'number' && p > 0);
  if (!v.length) return null;
  const min = Math.min(...v);
  const max = Math.max(...v);
  const counts = new Array(buckets).fill(0);
  for (const p of v) {
    const i = max === min ? 0 : Math.min(Math.floor(((p - min) / (max - min)) * buckets), buckets - 1);
    counts[i]++;
  }
  return { min, max, counts };
}

/** Index of the histogram bucket a price falls in (for highlighting the selected range). */
export function bucketIndex(hist, price) {
  if (!hist || price == null) return null;
  const n = hist.counts.length;
  if (hist.max === hist.min) return 0;
  return Math.max(0, Math.min(Math.floor(((price - hist.min) / (hist.max - hist.min)) * n), n - 1));
}

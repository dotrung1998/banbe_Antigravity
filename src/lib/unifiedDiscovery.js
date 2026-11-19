// Unified discovery (note 99, switch `unified_discovery`): Home and Map share ONE search, type, time, price and sort.
// Pure rules shared by Home.jsx, Search.jsx and MapExplore.jsx; iOS twin Lib/UnifiedDiscovery.swift, fixture
// tests/fixtures/unified-discovery.json.

import { applyDiscoveryFilters, normalizeFilters, sortEvents, DEFAULT_FILTERS, SORT_MODES, DEFAULT_OFFSET_MIN } from './homeDiscovery.js';

/** Home's tabs ARE the shared time: For You = any time, Tonight = today, Weekend = the weekend, All events = any time. */
export const DATE_FOR_TAB = { foryou: 'any', tonight: 'today', weekend: 'weekend', all: 'any' };

/** The tab a shared date shows as selected. Tomorrow / next 7 days have no tab of their own and read as For You. */
export function tabForDate(date) {
  if (date === 'today') return 'tonight';
  if (date === 'weekend') return 'weekend';
  return 'foryou';
}

/**
 * The tab Home shows as selected. For You and All events share the date 'any', so the date alone cannot tell them
 * apart: `allPicked` (the reader last picked All events) breaks the tie. A tab with its own date wins over the pick.
 * Without For You preferences (`hasPrefs` false) there is no For You tab: whatever would read as it is All events.
 */
export function resolveTab(date, allPicked, hasPrefs = true) {
  return effectiveTab(date === 'any' && allPicked ? 'all' : tabForDate(date), hasPrefs);
}

// ---- For You vs All events (bug 2026-11-19: both listed the same 15 events) ----------------------------------------
// For You = ONLY the events matching the viewer's For You preferences (the matcher's set); All events = every open
// event. Without preferences the two would be identical, so For You is not offered at all.

/** The Home tabs in display order (hosting is a view, not a tab; `canHost` appends it). */
export const HOME_TABS = ['foryou', 'tonight', 'weekend', 'all'];

/** Tabs the viewer sees: For You only with preferences; Hosting last, only when `canHost`. */
export function visibleTabs(hasPrefs, canHost = false) {
  return [...HOME_TABS.filter(t => t !== 'foryou' || hasPrefs), ...(canHost ? ['hosting'] : [])];
}

/** The tab Home opens on: For You with preferences, otherwise All events. */
export function defaultTab(hasPrefs) { return hasPrefs ? 'foryou' : 'all'; }

/** A stored/selected tab, resolved: For You without preferences is All events. */
export function effectiveTab(tab, hasPrefs) { return tab === 'foryou' && !hasPrefs ? 'all' : tab; }

/** Which set a tab lists: 'forYou' (the matcher's picks) for For You, else 'all' (every open event; time tabs add their time). */
export function tabSet(tab) { return tab === 'foryou' ? 'forYou' : 'all'; }

/** How many type tiles Home shows before the "All types" tile. */
export const TILE_TYPES = 5;

/**
 * The type tiles: the `n` busiest types for the current search, time and price, most events first, ties in catalogue
 * order. `counts` = { [typeKey]: number }, `keys` = the catalogue order.
 */
export function topTypes(counts, keys, n = TILE_TYPES) {
  return keys.slice().sort((a, b) => (counts[b] || 0) - (counts[a] || 0) || keys.indexOf(a) - keys.indexOf(b)).slice(0, n);
}

/** The "All types" tile turns into the picked type when that type is not one of the tiles; null otherwise. */
export function pickedTileType(selected, tiles) {
  return selected && selected !== 'all' && !tiles.includes(selected) ? selected : null;
}

/**
 * The type sheet's order: types with events first (most first, then catalogue order), then the empty ones in
 * catalogue order. `query` (already folded) keeps only names containing it.
 */
export function typeSheetOrder(counts, keys, nameOf = k => k, query = '') {
  const fold = s => String(s).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd');
  const q = fold(query.trim());
  return keys
    .filter(k => !q || fold(nameOf(k)).includes(q))
    .sort((a, b) => ((counts[b] || 0) > 0) - ((counts[a] || 0) > 0) || (counts[b] || 0) - (counts[a] || 0) || keys.indexOf(a) - keys.indexOf(b));
}

/**
 * What a map area bubble lists under its name: its types, busiest first, then catalogue order, at most `max`, plus
 * how many more there are. `cats` = { [typeKey]: count in that area }.
 */
export function areaGlyphs(cats, keys, max = 4) {
  const order = Object.keys(cats).filter(k => cats[k] > 0)
    .sort((a, b) => cats[b] - cats[a] || keyIndex(keys, a) - keyIndex(keys, b));
  return { shown: order.slice(0, max), more: Math.max(0, order.length - max) };
}
const keyIndex = (keys, k) => { const i = keys.indexOf(k); return i < 0 ? keys.length : i; };

/**
 * What the Filters button owns (and counts on its badge): type, price, seats, almost full, sort. Time has its own
 * control (the tabs / the Map's time chip) and the query has search.
 */
export function ownedFilterCount(filters, sort) {
  const f = filters || {};
  return ((f.cats || []).length ? 1 : 0) + (f.free || f.priceMin != null || f.priceMax != null ? 1 : 0)
    + (f.seatsLeft ? 1 : 0) + (f.almostFull ? 1 : 0) + ((f.typeFilters || []).length ? 1 : 0)
    + (sort && sort !== 'soonest' ? 1 : 0);
}

/**
 * Search ⇄ Map promise (note 99): the Search sheet only lists events the Map can plot. A doc matches a map row by the
 * real event id (a discovery event's `key` IS `events.id`, the map row's `id`) and the row must have lat/lng.
 * `mapRows == null` means "not loaded yet": the docs are returned unchanged (no empty flash).
 */
export function mapPlottable(docs, mapRows) {
  if (!Array.isArray(mapRows)) return docs;
  const byId = new Set();
  // A real event's key is its id; a demo-catalogue entry's key is its live row's slug.
  for (const r of mapRows) if (r && r.lat != null && r.lng != null) { byId.add(r.id); if (r.slug) byId.add(r.slug); }
  return (docs || []).filter(d => byId.has(d.key));
}

/** The {lat, lng} points of the docs' map rows, for fitting the Map camera. */
export function mapPoints(docs, mapRows) {
  const byId = new Map();
  for (const r of mapRows || []) {
    if (!r || r.lat == null || r.lng == null) continue;
    byId.set(r.id, r);
    if (r.slug && !byId.has(r.slug)) byId.set(r.slug, r);
  }
  return (docs || []).map(d => byId.get(d.key)).filter(Boolean).map(r => ({ lat: r.lat, lng: r.lng }));
}

/** True when any point lies outside `bounds` (`inBoundsFn` is mapDiscovery's inBounds). */
export function anyOutside(points, bounds, inBoundsFn) {
  return (points || []).some(p => !inBoundsFn(p, bounds));
}

// ---- Home "Near you" (bug 2026-11-19: web and iOS listed different events) -------------------------------------
// ONE rule for the list under Home's hero, the "See on the map · N" banner, the state bar and the end card, on both
// apps (iOS twin UnifiedDiscovery.nearYou, shared cases in tests/fixtures/unified-discovery.json "nearYou"):
//   * the base is every event Home lists in the area (and the shared query), still open: not cancelled, a known start,
//     and not over (`endsAt` = eventEndsAt: the host's end time, else 12 h after the start). The For You RANKING is not
//     a base: the list never shrinks to the matcher's picks just because For You is the open tab.
//   * narrowed by Home's filters (with unified discovery the tab's time is `filters.date`),
//   * soonest first by the start instant (the same instant as the venue's clock), unless a sort is picked,
//   * total = the base before the filters the Filters button owns; with unified discovery the tab's time is NOT one
//     of them (it has the tabs), so "N of M" and "Show all M" never count events of another tab.
//   * the map banner and the state bar show rows.length, exactly the list.

/** Open = Home may still offer it: not cancelled, a known start, not past its end (`endsAt`, ms, null = unknown). */
export function isOpenItem(it, now) {
  return !!it && !it.cancelled && Number.isFinite(it.startsAt) && !(it.endsAt != null && now >= it.endsAt);
}

/**
 * @param {Array} items  Home's discovery items (area + query already applied), each with optional `cancelled`, `endsAt`
 * @param {object} filters  Home's filters
 * @param {string} sort  Home's sort ('soonest' when none)
 * @param {number} now
 * @param {{ tabOwnsTime?: boolean, offsetMin?: number, tab?: string, forYouKeys?: Iterable<string>|null }} [opts]
 *   tabOwnsTime = unified discovery (the date is the tab); `tab` + `forYouKeys` (the matcher's picks, area-scoped): on the
 *   For You tab the base is only those keys (soonest first still); other tabs ignore them
 * @returns {{ rows: Array, total: number }}
 */
export function nearYou(items, filters, sort, now, { tabOwnsTime = false, offsetMin = DEFAULT_OFFSET_MIN, tab = null, forYouKeys = null } = {}) {
  const f = normalizeFilters(filters);
  const picks = tabSet(tab) === 'forYou' && forYouKeys ? new Set(forYouKeys) : null;
  const open = (items || []).filter(it => isOpenItem(it, now) && (!picks || picks.has(it.key)));
  const base = tabOwnsTime ? applyDiscoveryFilters(open, { ...DEFAULT_FILTERS, date: f.date }, now, offsetMin) : open;
  const narrowed = applyDiscoveryFilters(base, f, now, offsetMin);
  return { rows: sortEvents(narrowed, SORT_MODES.includes(sort) ? sort : 'soonest'), total: base.length };
}

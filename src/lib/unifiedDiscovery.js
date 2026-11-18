// Unified discovery (note 99, switch `unified_discovery`): Home and Map share ONE search, type, time, price and sort.
// Pure rules shared by Home.jsx, Search.jsx and MapExplore.jsx; iOS twin Lib/UnifiedDiscovery.swift, fixture
// tests/fixtures/unified-discovery.json.

/** Home's tabs ARE the shared time: For You = any time, Tonight = today, Weekend = the weekend. */
export const DATE_FOR_TAB = { foryou: 'any', tonight: 'today', weekend: 'weekend' };

/** The tab a shared date shows as selected. Tomorrow / next 7 days have no tab of their own and read as For You. */
export function tabForDate(date) {
  if (date === 'today') return 'tonight';
  if (date === 'weekend') return 'weekend';
  return 'foryou';
}

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

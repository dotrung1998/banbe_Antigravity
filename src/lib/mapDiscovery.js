// Map discovery core (Map redesign, phase 2): ONE committed geography + ONE predicate drive the pins, the list and
// the count. iOS twin: apps/ios/BanbeApp/Lib/MapDiscovery.swift; shared cases: tests/fixtures/map-discovery.json.
// Pure: no React, no network, no Date.now().
//
// Geography is the map's REFERENCE RECT: the whole map minus the top controls and minus the PEEK sheet (the most map
// the screen ever shows). It is the same at every sheet detent, so dragging the sheet never changes the results; at
// mid a few results can sit under the sheet, and selecting one reveals it with camera padding (no new search).
//
// Camera moves carry a reason. Only geographic navigation commits a new search area once the camera settles:
//   user (pan/zoom), initial (first open), destination (area pick), recenter (compass), nearest ("Show nearest"),
//   cluster (tap a cluster). Moves made only to reveal a selected pin or follow the sheet ('reveal') and a restored
//   camera ('restore') never redefine the area.

export const COMMIT_REASONS = ['user', 'initial', 'destination', 'recenter', 'nearest', 'cluster'];
export const reasonCommits = (reason) => COMMIT_REASONS.includes(reason);

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const MAX_LAT = 85.05112878;

// ---- Web Mercator (world fractions: x 0..1 west→east, y 0..1 north→south) ------------------------------------
export function mercX(lng) { return (lng + 180) / 360; }
export function mercY(lat) {
  const s = Math.sin((clamp(lat, -MAX_LAT, MAX_LAT) * Math.PI) / 180);
  return 0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI);
}
export function latFromMercY(y) { return (Math.atan(Math.sinh(Math.PI * (1 - 2 * y))) * 180) / Math.PI; }
export function lngFromMercX(x) { return x * 360 - 180; }

/** The reference rect in px of a `width` × `height` map: below the top controls, above the peek sheet. */
export function referenceRect({ width, height, topInset = 0, bottomInset = 0 }) {
  const top = clamp(topInset, 0, height);
  const bottom = Math.max(top + 1, height - Math.max(0, bottomInset));
  return { top, bottom: Math.min(height, bottom), left: 0, right: width };
}

/**
 * Bounds of a px rect inside a map whose FULL view shows `full` ({north, south, east, west}). Longitude is linear in
 * x; latitude is linear in Mercator y, so this is exact for a north-up web map at any zoom.
 */
export function boundsForRect(full, { width, height }, rect) {
  const east = full.east < full.west ? full.east + 360 : full.east; // view crossing the antimeridian
  const x0 = mercX(full.west), x1 = mercX(east);
  const y0 = mercY(full.north), y1 = mercY(full.south);
  const fx = (px) => x0 + (x1 - x0) * (px / width);
  const fy = (py) => y0 + (y1 - y0) * (py / height);
  const wrap = (lng) => (lng > 180 ? lng - 360 : lng);
  return {
    north: latFromMercY(fy(rect.top)),
    south: latFromMercY(fy(rect.bottom)),
    west: wrap(lngFromMercX(fx(rect.left))),
    east: wrap(lngFromMercX(fx(rect.right))),
  };
}

/** True when the event has coordinates inside `b` (handles a box crossing the antimeridian). */
export function inBounds(ev, b) {
  if (!b || ev?.lat == null || ev?.lng == null) return false;
  if (ev.lat > b.north || ev.lat < b.south) return false;
  return b.west <= b.east ? ev.lng >= b.west && ev.lng <= b.east : ev.lng >= b.west || ev.lng <= b.east;
}

/**
 * The Map's results: events inside the committed bounds that pass `matches` (search, category, seats, For You —
 * the caller's one filter predicate). No committed bounds yet = no results (never the whole world).
 */
export function mapResults(events, bounds, matches = () => true) {
  if (!bounds) return [];
  return (events || []).filter(e => inBounds(e, bounds) && matches(e));
}

/** Selection survives only while the event is still a result; it is never moved to another event. */
export function selectionAfter(selectedId, resultIds) {
  if (selectedId == null) return null;
  return resultIds.includes(selectedId) ? selectedId : null;
}

// ---- framing -----------------------------------------------------------------------------------------------------
const toRad = (d) => (d * Math.PI) / 180;
export function distanceKm(a, b) {
  const dLat = toRad(b.lat - a.lat), dLng = toRad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Bounding box of points (null for none). */
export function boundsOfPoints(points) {
  const pts = (points || []).filter(p => p && p.lat != null && p.lng != null);
  if (!pts.length) return null;
  return {
    north: Math.max(...pts.map(p => p.lat)), south: Math.min(...pts.map(p => p.lat)),
    east: Math.max(...pts.map(p => p.lng)), west: Math.min(...pts.map(p => p.lng)),
  };
}

/** Points within `radiusKm` of `center` — one city's worth, never the whole inventory. */
export function pointsNear(points, center, radiusKm = 25) {
  if (!center) return [];
  return (points || []).filter(p => p && p.lat != null && p.lng != null && distanceKm(center, p) <= radiusKm);
}

/** The point closest to `from` (null for none). */
export function nearestPoint(points, from) {
  let best = null, bestKm = Infinity;
  for (const p of points || []) {
    if (!p || p.lat == null || p.lng == null) continue;
    const km = distanceKm(from, p);
    if (km < bestKm) { best = p; bestKm = km; }
  }
  return best;
}

/**
 * Camera that fits `bounds` into the part of a `width` × `height` map left free by `padding` (the top controls and
 * the mid sheet). `tileSize` is the engine's zoom basis (MapLibre 512, the MapKit JS adapter 256). A single point
 * (or a tiny box) gets `maxZoom`.
 */
export function fitCamera(bounds, { width, height }, padding = {}, { tileSize = 512, maxZoom = 15, minZoom = 2 } = {}) {
  const p = { top: 0, bottom: 0, left: 0, right: 0, ...padding };
  const w = Math.max(40, width - p.left - p.right);
  const h = Math.max(40, height - p.top - p.bottom);
  const x0 = mercX(bounds.west), x1 = mercX(bounds.east < bounds.west ? bounds.east + 360 : bounds.east);
  const y0 = mercY(bounds.north), y1 = mercY(bounds.south);
  const dx = Math.abs(x1 - x0), dy = Math.abs(y1 - y0);
  const zx = dx > 0 ? Math.log2(w / (dx * tileSize)) : Infinity;
  const zy = dy > 0 ? Math.log2(h / (dy * tileSize)) : Infinity;
  const zoom = clamp(Math.min(zx, zy, maxZoom), minZoom, maxZoom);
  // The box's centre lands in the middle of the free area, not of the whole map.
  const world = tileSize * 2 ** zoom;
  const cx = (x0 + x1) / 2 - (p.left + w / 2 - width / 2) / world;
  const cy = (y0 + y1) / 2 - (p.top + h / 2 - height / 2) / world;
  const lng = lngFromMercX(cx);
  return { center: { lat: latFromMercY(cy), lng: lng > 180 ? lng - 360 : lng }, zoom };
}

// ---- clustering (phase 4) ----------------------------------------------------------------------------------------
// Display only: clusters reduce the markers drawn, never the results or the count (every result is in exactly one
// group). A screen-space grid at the camera's zoom: events in one `cellPx` cell group together. At `maxZoom` and
// above only events at the SAME place (≈1 m) group — a "stack", which zooming can never split, so tapping it selects
// the first event and the card steps through the rest.
export const CLUSTER_CELL_PX = 64;
export const CLUSTER_MAX_ZOOM = 16;
const spotKey = (p) => `${Number(p.lat).toFixed(5)},${Number(p.lng).toFixed(5)}`;

/** [{ kind: 'pin'|'cluster'|'stack', ids, lat, lng, bounds }] in first-seen order; ids keep the input order. */
export function clusterPins(points, zoom, { tileSize = 512, cellPx = CLUSTER_CELL_PX, maxZoom = CLUSTER_MAX_ZOOM } = {}) {
  const world = tileSize * 2 ** zoom;
  const groups = new Map();
  for (const p of points || []) {
    if (!p || p.lat == null || p.lng == null) continue;
    const key = zoom >= maxZoom
      ? `s:${spotKey(p)}`
      : `g:${Math.floor((mercX(p.lng) * world) / cellPx)}:${Math.floor((mercY(p.lat) * world) / cellPx)}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(p);
  }
  // A grid can split close events across a cell edge into two overlapping markers (hard to tap). Below maxZoom,
  // merge any two groups whose centres are closer than one cell on screen, until none are.
  let list = [...groups.values()];
  if (zoom < maxZoom) {
    const px = (pts) => [
      (pts.reduce((s, p) => s + mercX(p.lng), 0) / pts.length) * world,
      (pts.reduce((s, p) => s + mercY(p.lat), 0) / pts.length) * world,
    ];
    let merged = true;
    while (merged) {
      merged = false;
      outer: for (let i = 0; i < list.length; i++) {
        for (let j = i + 1; j < list.length; j++) {
          const [ax, ay] = px(list[i]), [bx, by] = px(list[j]);
          if (Math.hypot(ax - bx, ay - by) < cellPx) {
            list[i] = [...list[i], ...list[j]];
            list.splice(j, 1);
            merged = true;
            break outer;
          }
        }
      }
    }
  }
  return list.map(pts => {
    const sameSpot = new Set(pts.map(spotKey)).size === 1;
    return {
      kind: pts.length === 1 ? 'pin' : sameSpot ? 'stack' : 'cluster',
      ids: pts.map(p => p.id),
      lat: pts.reduce((s, p) => s + p.lat, 0) / pts.length,
      lng: pts.reduce((s, p) => s + p.lng, 0) / pts.length,
      bounds: boundsOfPoints(pts),
    };
  });
}

/** Events at the same place as `ev` among `list` (itself included, list order) — the card's stack switcher. */
export function sameSpot(list, ev) {
  if (!ev || ev.lat == null || ev.lng == null) return ev ? [ev] : [];
  const k = spotKey(ev);
  return (list || []).filter(e => e.lat != null && e.lng != null && spotKey(e) === k);
}

/** `b` grown by `factor` around its centre (bounded-fetch margin when the full set is too large to load). */
export function padBounds(b, factor = 1.5) {
  const dLat = ((b.north - b.south) * (factor - 1)) / 2;
  const dLng = ((b.east - b.west) * (factor - 1)) / 2;
  return { north: Math.min(85, b.north + dLat), south: Math.max(-85, b.south - dLat), east: b.east + dLng, west: b.west - dLng };
}

// ---- Map v5 (note 73): cities + the active filter summary ---------------------------------------------------------
// Cities come from src/data/cities.json (iOS bundles the same file). No database change: an event's city is the one
// its city / province column names, else the smallest city box that contains its position, else none.
export const CITY_ZOOM = 9; // below this camera zoom (512 px basis) markers group one bubble per city

/** Lowercase, accents removed (đ → d), punctuation → spaces, single spaces. */
export function foldText(s) {
  return String(s ?? '')
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/[đĐ]/g, 'd')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}
const ADMIN_PREFIX = /^(thanh pho|tp|tinh|thi xa|city of)\s+/;
/** `foldText` without an admin prefix ("Thành phố Hà Nội" → "ha noi"). Map v6: the location tree compares names with it. */
export const foldName = (s) => foldText(s).replace(ADMIN_PREFIX, '');
const boxArea = (b) => (b.north - b.south) * Math.abs(b.east - b.west);

/** The city id for `ev` ({ city, stateProvince, countryCode, lat, lng }), or null. */
export function cityFor(ev, cities) {
  if (!ev) return null;
  const list = cities || [];
  const sameCountry = (c) => !ev.countryCode || ev.countryCode === c.country;
  for (const raw of [ev.city, ev.stateProvince]) {
    const n = foldName(raw);
    if (!n) continue;
    const hit = list.find(c => sameCountry(c) && (c.names.some(x => foldName(x) === n) || c.aliases.includes(n)));
    if (hit) return hit.id;
  }
  let best = null;
  for (const c of list) {
    if (inBounds(ev, c.bounds) && (!best || boxArea(c.bounds) < boxArea(best.bounds))) best = c;
  }
  return best ? best.id : null;
}

/** Cities whose name or alias starts a word with `query` (2+ characters): [{ id, count }], most events first, max `limit`. */
export function searchCities(query, cities, counts = {}, limit = 3) {
  const q = foldText(query);
  if (q.length < 2) return [];
  const hits = [];
  for (const c of cities || []) {
    const keys = [c.vi, c.en, ...c.aliases].map(foldText);
    const exact = keys.some(k => k.startsWith(q));
    if (exact || keys.some(k => (' ' + k).includes(' ' + q))) hits.push({ id: c.id, count: counts[c.id] || 0, exact, name: foldText(c.vi) });
  }
  hits.sort((a, b) => (b.count - a.count) || (Number(b.exact) - Number(a.exact)) || a.name.localeCompare(b.name));
  return hits.slice(0, limit).map(({ id, count }) => ({ id, count }));
}

/**
 * Markers for `points` at `zoom`. Below CITY_ZOOM every point with a city joins that city's bubble (at the city
 * centre, tap = fly to its bounds); points with no city fall back to `clusterPins`. At CITY_ZOOM and above it is
 * exactly `clusterPins`. Every point with coordinates is in exactly one marker, so markers add up to the count.
 */
export function cityGroups(points, zoom, cityOf, cities, opts = {}) {
  if (zoom >= CITY_ZOOM) return clusterPins(points, zoom, opts);
  const byId = new Map((cities || []).map(c => [c.id, c]));
  const order = [];
  const groups = new Map();
  const rest = [];
  for (const p of points || []) {
    if (!p || p.lat == null || p.lng == null) continue;
    const id = cityOf(p);
    const c = id && byId.get(id);
    if (!c) { rest.push(p); continue; }
    if (!groups.has(id)) { groups.set(id, []); order.push(id); }
    groups.get(id).push(p);
  }
  const out = order.map(id => {
    const c = byId.get(id);
    return { kind: 'city', cityId: id, ids: groups.get(id).map(p => p.id), lat: c.center.lat, lng: c.center.lng, bounds: { ...c.bounds } };
  });
  return out.concat(clusterPins(rest, zoom, opts));
}

// ---- Map E+ (note 79): neighbourhood bubbles ------------------------------------------------------------------------
// Zoom levels (512 px basis): below CITY_ZOOM one bubble per city, from CITY_ZOOM up to AREA_ZOOM one bubble per
// neighbourhood, from AREA_ZOOM the price pins and clusters. No database change: the neighbourhood is the event's own
// `area` text (the geocoder's district, shown as a familiar area, never as an official unit, note 20), else its
// `neighborhood`; its centre and bounds come from the member events' own positions.
export const AREA_ZOOM = 13;
export const AREA_MERGE_PX = 56; // two neighbourhood bubbles closer than this on screen become one "N areas" bubble
export const AREA_PANEL_CLOSE_DELTA = 0.5; // zooming out this far below AREA_ZOOM closes the area panel

/** 'city' | 'area' | 'pin': which marker level the camera zoom shows. */
export const markerLevel = (zoom) => (zoom < CITY_ZOOM ? 'city' : zoom < AREA_ZOOM ? 'area' : 'pin');
/** Zooming out below this closes the open area panel (the view stays where it is). */
export const areaPanelCloses = (zoom) => zoom < AREA_ZOOM - AREA_PANEL_CLOSE_DELTA;

/** "district 1", "Q.1", "Q1" and "Quận 1" are one area; a leading "Quận / Huyện / District" before a name is dropped. */
function foldArea(raw) {
  const t = foldName(raw);
  const m = t.match(/^(?:quan|district|dist|q)\s*(\d+)$/);
  if (m) return `quan ${m[1]}`;
  return t.replace(/^(?:quan|huyen|district)\s+(?=\D)/, '');
}

/**
 * { key, label, cityId } of an event ({ area, neighborhood, city, stateProvince, countryCode, lat, lng }).
 * `key` groups the same area spelled differently inside one city; `label` is the text as written (null = no area at
 * all: the view shows "Other areas").
 */
export function areaKey(ev, cities) {
  const cityId = cityFor(ev, cities);
  const raw = String(ev?.area ?? '').trim() || String(ev?.neighborhood ?? '').trim();
  return { key: `${cityId ?? '-'}|${foldArea(raw) || '~'}`, label: raw || null, cityId };
}

/**
 * One bubble per neighbourhood for `points` (each with lat, lng, id): [{ kind: 'area', keys, labels, cityId, ids, hit,
 * lat, lng, bounds }] in first-seen order. `areaOf(point)` is `areaKey`. `hitIds` (array or Set, null = all) are the
 * ids inside the time window: `hit` counts them. Bubbles of one city whose centres are closer than AREA_MERGE_PX at
 * `zoom` merge (keys.length > 1: tap zooms in, a single key opens its panel). Every point with coordinates lands in
 * exactly one bubble, so bubbles add up to the count.
 */
export function areaGroups(points, zoom, areaOf, hitIds = null, { tileSize = 512, mergePx = AREA_MERGE_PX } = {}) {
  const hits = hitIds == null ? null : new Set(hitIds);
  const world = tileSize * 2 ** zoom;
  const byKey = new Map();
  for (const p of points || []) {
    if (!p || p.lat == null || p.lng == null) continue;
    const a = areaOf(p);
    if (!byKey.has(a.key)) byKey.set(a.key, { keys: [a.key], labels: [a.label], cityId: a.cityId, pts: [] });
    byKey.get(a.key).pts.push(p);
  }
  const list = [...byKey.values()];
  const px = (g) => [
    (g.pts.reduce((s, p) => s + mercX(p.lng), 0) / g.pts.length) * world,
    (g.pts.reduce((s, p) => s + mercY(p.lat), 0) / g.pts.length) * world,
  ];
  let merged = true;
  while (merged) {
    merged = false;
    outer: for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) {
        if (list[i].cityId !== list[j].cityId) continue;
        const [ax, ay] = px(list[i]), [bx, by] = px(list[j]);
        if (Math.hypot(ax - bx, ay - by) < mergePx) {
          list[i] = { ...list[i], keys: [...list[i].keys, ...list[j].keys], labels: [...list[i].labels, ...list[j].labels], pts: [...list[i].pts, ...list[j].pts] };
          list.splice(j, 1);
          merged = true;
          break outer;
        }
      }
    }
  }
  return list.map((g) => ({
    kind: 'area',
    keys: g.keys,
    labels: g.labels,
    cityId: g.cityId,
    ids: g.pts.map((p) => p.id),
    hit: hits ? g.pts.filter((p) => hits.has(p.id)).length : g.pts.length,
    lat: g.pts.reduce((s, p) => s + p.lat, 0) / g.pts.length,
    lng: g.pts.reduce((s, p) => s + p.lng, 0) / g.pts.length,
    bounds: boundsOfPoints(g.pts),
  }));
}

/**
 * What is filtered, in reading order, for the peek strip and the compact sticky header. Tokens, not text, so web and
 * iOS share one fixture and label them in their own language:
 *   query · cat (each) · forYou · date · free · price · seatsLeft · almostFull · types (n).
 * `count` is the badge number (each token counts 1, `types` counts n).
 */
export function activeFilterSummary(filters, { forYou = false, query = '' } = {}) {
  const f = filters || {};
  const tokens = [];
  const q = String(query || '').trim();
  if (q) tokens.push({ kind: 'query', text: q });
  for (const key of f.cats || []) tokens.push({ kind: 'cat', key });
  if (forYou) tokens.push({ kind: 'forYou' });
  if (f.date && f.date !== 'any') tokens.push({ kind: 'date', key: f.date });
  if (f.free) tokens.push({ kind: 'free' });
  if (f.priceMin != null || f.priceMax != null) {
    tokens.push({ kind: 'price', min: f.priceMin ?? null, max: f.priceMax ?? null, currency: f.priceCurrency === 'USD' ? 'USD' : 'VND' });
  }
  if (f.seatsLeft) tokens.push({ kind: 'seatsLeft' });
  if (f.almostFull) tokens.push({ kind: 'almostFull' });
  const types = (f.typeFilters || []).length;
  if (types) tokens.push({ kind: 'types', n: types });
  const count = tokens.reduce((s, t) => s + (t.kind === 'types' ? t.n : 1), 0);
  return { tokens, count };
}

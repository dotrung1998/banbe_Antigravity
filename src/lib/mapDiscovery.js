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

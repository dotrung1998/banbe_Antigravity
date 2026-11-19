// Web Map Explore basemap: provider/style configuration + a pure style transform.
// Everything provider-specific lives in MAP_PROVIDER so the basemap can be swapped
// (another OpenFreeMap style, a self-hosted style.json, a different vector provider)
// without touching src/screens/MapExplore.jsx. No API keys, no paid services.
//
// Light = OpenFreeMap "Liberty", toned down (less saturated fills, quieter secondary
// labels). Dark = the SAME Liberty style, recoloured from an explicit ink-navy palette
// below (not a generic lightness inversion, which turned roads olive and water muddy).
// Both modes therefore show identical features and labels, and the dark map reads like
// a designed night map: deep navy land, darker water, teal parks, lit road hierarchy,
// quiet building footprints and soft periwinkle labels.
// Attribution comes from the style's own sources; MapExplore renders it un-collapsed.
// Pure: no DOM, no maplibre import (unit-tested in tests/unit/mapStyle.test.mjs).

const env = (typeof import.meta !== 'undefined' && import.meta.env) ? import.meta.env : {};

export const MAP_PROVIDER = {
  id: 'openfreemap-liberty',
  // Override per environment with VITE_MAP_STYLE_URL (a MapLibre style.json URL).
  styleUrl: env.VITE_MAP_STYLE_URL || 'https://tiles.openfreemap.org/styles/liberty',
  // Required credit text if a replacement style does not carry its own attribution.
  fallbackAttribution: 'OpenFreeMap © OpenMapTiles Data from OpenStreetMap',
  // Symbol layers (secondary labels) that stay visible at every zoom; everything else is quieter.
  keepLabelLayers: [
    'water_name_point_label', 'water_name_line_label', 'highway-name-major',
    'label_state', 'label_city', 'label_city_capital', 'label_country_1', 'label_country_2', 'label_country_3',
    'label_town',
  ],
  // Secondary layers only shown when zoomed in (min zoom).
  lateLayers: { poi_r20: 16.5, poi_r7: 17, poi_r1: 17.5, poi_transit: 16, airport: 12, label_other: 14, 'highway-name-minor': 15, 'highway-name-path': 16 },
  // Layers hidden outright (noise on a discovery map).
  hiddenLayers: ['road_one_way_arrow', 'road_one_way_arrow_opposite', 'highway-shield-non-us', 'highway-shield-us-interstate', 'road_shield_us'],
};

// ---------- colour helpers ----------
const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n));

function rgbToHsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  const l = (max + min) / 2;
  let h = 0, s = 0;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60;
  }
  return { h, s, l };
}

const num = (t) => (t.endsWith('%') ? parseFloat(t) / 100 : parseFloat(t));

/** Parses #rgb/#rrggbb/#rrggbbaa, rgb()/rgba(), hsl()/hsla(); returns {h,s,l,a} (s,l in 0..1) or null. */
export function parseColor(str) {
  if (typeof str !== 'string') return null;
  const t = str.trim().toLowerCase();
  let m = /^#([0-9a-f]{3,8})$/.exec(t);
  if (m) {
    let hex = m[1];
    if (hex.length === 3 || hex.length === 4) hex = hex.split('').map(c => c + c).join('');
    if (hex.length !== 6 && hex.length !== 8) return null;
    const r = parseInt(hex.slice(0, 2), 16), g = parseInt(hex.slice(2, 4), 16), b = parseInt(hex.slice(4, 6), 16);
    const a = hex.length === 8 ? parseInt(hex.slice(6, 8), 16) / 255 : 1;
    return { ...rgbToHsl(r, g, b), a };
  }
  m = /^(rgba?|hsla?)\(([^)]+)\)$/.exec(t);
  if (!m) return null;
  const parts = m[2].split(/[\s,/]+/).filter(Boolean);
  if (parts.length < 3) return null;
  const a = parts[3] != null ? clamp(num(parts[3]), 0, 1) : 1;
  if (m[1].startsWith('rgb')) {
    const ch = parts.slice(0, 3).map(p => (p.endsWith('%') ? parseFloat(p) * 2.55 : parseFloat(p)));
    if (ch.some(Number.isNaN)) return null;
    return { ...rgbToHsl(ch[0], ch[1], ch[2]), a };
  }
  const h = parseFloat(parts[0]), s = num(parts[1]), l = num(parts[2]);
  if ([h, s, l].some(Number.isNaN)) return null;
  return { h: ((h % 360) + 360) % 360, s: clamp(s, 0, 1), l: clamp(l, 0, 1), a };
}

export const hsla = ({ h, s, l, a }) => `hsla(${Math.round(h)}, ${Math.round(clamp(s, 0, 1) * 100)}%, ${Math.round(clamp(l, 0, 1) * 100)}%, ${+clamp(a, 0, 1).toFixed(3)})`;

// Light mode: calmer palette, nudged toward the app's warm paper tone.
export function restrainLight(c) {
  return { h: c.h, s: c.s * 0.55, l: clamp(c.l + (1 - c.l) * 0.12, 0, 1), a: c.a };
}
// Generic dark fallback for any layer the curated palette below does not name.
// Fills/lines flip into a compressed dark range; text flips light; halos go dark.
export function toDark(c, role = 'fill') {
  const sat = c.s * 0.5;
  if (role === 'text') return { h: c.h, s: sat * 0.6, l: clamp(0.58 + (1 - c.l) * 0.32, 0.55, 0.92), a: c.a };
  if (role === 'halo') return { h: c.h, s: sat * 0.5, l: clamp(0.08 + (1 - c.l) * 0.06, 0.06, 0.16), a: c.a };
  return { h: c.h, s: sat, l: clamp(0.07 + (1 - c.l) * 0.3, 0.06, 0.42), a: c.a };
}

/**
 * The dark basemap palette. One place to tune the whole night map: land sits at the
 * bottom, water a step darker, parks teal, and the road hierarchy climbs in lightness
 * so arterials read first (the Partiful-style "lit city" look) without any bloom.
 */
export const PREMIUM_DARK = {
  land: '#121730',
  landBlocks: '#171d3a',
  landInset: '#1a2038',
  water: '#0a1226',
  waterLine: '#0e1830',
  park: '#16342f',
  parkLine: '#1f453c',
  wood: '#14302c',
  grass: '#17342f',
  pitch: '#1a3733',
  cemetery: '#182a2a',
  hospital: '#1d233f',
  school: '#1c2a3a',
  sand: '#2a2f4d',
  ice: '#1b2747',
  building: '#1b2140',
  buildingLine: '#262d52',
  roadCasing: '#0e1530',
  bridgeCasing: '#1b2242',
  roadMinor: '#2b3559',
  roadTunnel: '#222a49',
  roadSecondary: '#3a4675',
  roadPrimary: '#4b598f',
  roadMotorway: '#7585c4',
  roadPath: '#2a3150',
  rail: '#333b61',
  boundary: '#2f3860',
  textStrong: '#eef1ff',
  text: '#d5dcf7',
  textSoft: '#c9d3f2',
  textMinor: '#9aa6d4',
  textHalo: '#080d1e',
};

const D = PREMIUM_DARK;

// Paint keys only; widths, opacity ramps, filters and layouts stay exactly as the provider defines them.
const CURATED_DARK = {
  background: { 'background-color': D.land },

  park: { 'fill-color': D.park, 'fill-opacity': 0.95, 'fill-outline-color': D.parkLine },
  park_outline: { 'line-color': D.parkLine, 'line-opacity': 0.35 },
  landuse_residential: { 'fill-color': D.landBlocks, 'fill-opacity': 0.9 },
  landcover_wood: { 'fill-color': D.wood, 'fill-opacity': 0.75 },
  landcover_grass: { 'fill-color': D.grass, 'fill-opacity': 0.55 },
  landcover_ice: { 'fill-color': D.ice },
  landcover_wetland: { 'fill-color': D.waterLine },
  landcover_sand: { 'fill-color': D.sand },
  landuse_pitch: { 'fill-color': D.pitch },
  landuse_track: { 'fill-color': D.landInset },
  landuse_cemetery: { 'fill-color': D.cemetery },
  landuse_hospital: { 'fill-color': D.hospital },
  landuse_school: { 'fill-color': D.school },

  water: { 'fill-color': D.water },
  waterway_river: { 'line-color': D.waterLine },
  waterway_other: { 'line-color': D.waterLine },
  waterway_tunnel: { 'line-color': D.waterLine, 'line-opacity': 0.55 },

  aeroway_fill: { 'fill-color': D.landInset },
  aeroway_runway: { 'line-color': D.roadSecondary },
  aeroway_taxiway: { 'line-color': D.roadMinor },

  road_motorway_casing: { 'line-color': D.roadCasing },
  road_trunk_primary_casing: { 'line-color': D.roadCasing },
  road_secondary_tertiary_casing: { 'line-color': D.roadCasing },
  road_minor_casing: { 'line-color': D.roadCasing },
  road_link_casing: { 'line-color': D.roadCasing },
  road_service_track_casing: { 'line-color': D.roadCasing },
  road_motorway_link_casing: { 'line-color': D.roadCasing },

  road_motorway: { 'line-color': D.roadMotorway },
  road_motorway_link: { 'line-color': D.roadMotorway },
  road_trunk_primary: { 'line-color': D.roadPrimary },
  road_secondary_tertiary: { 'line-color': D.roadSecondary },
  road_link: { 'line-color': D.roadSecondary },
  road_minor: { 'line-color': D.roadMinor },
  road_service_track: { 'line-color': D.roadMinor },
  road_path_pedestrian: { 'line-color': D.roadPath },
  road_major_rail: { 'line-color': D.rail },
  road_major_rail_hatching: { 'line-color': D.roadCasing },
  road_transit_rail: { 'line-color': D.rail },
  road_transit_rail_hatching: { 'line-color': D.roadCasing },

  building: { 'fill-color': D.building, 'fill-outline-color': D.buildingLine },
  'building-3d': { 'fill-extrusion-color': D.building, 'fill-extrusion-opacity': 0.85 },

  boundary_3: { 'line-color': D.boundary, 'line-opacity': 0.45 },
  boundary_2: { 'line-color': D.boundary, 'line-opacity': 0.6 },
  boundary_disputed: { 'line-color': D.boundary, 'line-opacity': 0.35 },

  water_name_point_label: { 'text-color': D.textMinor, 'text-halo-color': D.textHalo },
  water_name_line_label: { 'text-color': D.textMinor, 'text-halo-color': D.textHalo },
  waterway_line_label: { 'text-color': D.textMinor, 'text-halo-color': D.textHalo },

  highway_name_label: { 'text-color': D.textMinor, 'text-halo-color': D.textHalo },
  'highway-name-major': { 'text-color': D.textMinor, 'text-halo-color': D.textHalo },
  'highway-name-minor': { 'text-color': D.textMinor, 'text-halo-color': D.textHalo },
  'highway-name-path': { 'text-color': D.textMinor, 'text-halo-color': D.textHalo },
  airport: { 'text-color': D.textMinor, 'text-halo-color': D.textHalo },

  label_city: { 'text-color': D.textStrong, 'text-halo-color': D.textHalo },
  label_city_capital: { 'text-color': D.textStrong, 'text-halo-color': D.textHalo },
  label_town: { 'text-color': D.text, 'text-halo-color': D.textHalo },
  label_village: { 'text-color': D.textSoft, 'text-halo-color': D.textHalo },
  label_state: { 'text-color': D.textSoft, 'text-halo-color': D.textHalo },
  label_other: { 'text-color': D.textSoft, 'text-halo-color': D.textHalo },
  label_country_1: { 'text-color': D.textSoft, 'text-halo-color': D.textHalo },
  label_country_2: { 'text-color': D.textSoft, 'text-halo-color': D.textHalo },
  label_country_3: { 'text-color': D.textSoft, 'text-halo-color': D.textHalo },

  poi_r20: { 'text-color': D.textMinor, 'text-halo-color': D.textHalo, 'icon-opacity': 0.65 },
  poi_r7: { 'text-color': D.textMinor, 'text-halo-color': D.textHalo, 'icon-opacity': 0.65 },
  poi_r1: { 'text-color': D.textMinor, 'text-halo-color': D.textHalo, 'icon-opacity': 0.65 },
  poi_transit: { 'text-color': D.textMinor, 'text-halo-color': D.textHalo, 'icon-opacity': 0.7 },
};

/** Curated dark paint for a layer, or null when it is not in the palette (generic recolour then applies). */
export function curatedDarkPaint(layer) {
  const id = layer?.id;
  if (!id) return null;
  if (CURATED_DARK[id]) return CURATED_DARK[id];
  // Tunnels: the same streets, sunk under the city.
  if (id.startsWith('tunnel_')) {
    if (/_casing$/.test(id)) return { 'line-color': D.roadCasing, 'line-opacity': 0.45 };
    if (/rail/.test(id)) return { 'line-color': D.rail, 'line-opacity': 0.4 };
    return { 'line-color': D.roadTunnel, 'line-opacity': 0.6 };
  }
  // Bridges: a touch lighter than the road they carry, so they step over the water.
  if (id.startsWith('bridge_')) {
    if (/_casing$/.test(id)) return { 'line-color': D.bridgeCasing };
    if (/motorway/.test(id)) return { 'line-color': D.roadMotorway };
    if (/trunk_primary/.test(id)) return { 'line-color': D.roadPrimary };
    if (/secondary|link|street/.test(id)) return { 'line-color': D.roadSecondary };
    if (/rail/.test(id)) return { 'line-color': D.rail };
    return { 'line-color': D.roadMinor };
  }
  return null;
}

function roleOf(prop) {
  if (prop === 'text-halo-color') return 'halo';
  if (prop === 'text-color' || prop === 'icon-color') return 'text';
  return 'fill';
}

function mapColors(value, fn) {
  if (typeof value === 'string') { const c = parseColor(value); return c ? hsla(fn(c)) : value; }
  if (Array.isArray(value)) return value.map(v => mapColors(v, fn));
  if (value && typeof value === 'object') {
    const out = {};
    for (const k of Object.keys(value)) out[k] = k === 'stops' ? value[k].map(([z, v]) => [z, mapColors(v, fn)]) : mapColors(value[k], fn);
    return out;
  }
  return value;
}

/** Returns a NEW style object (input untouched). `mode` is 'light' | 'dark'. */
export function transformStyle(style, mode = 'light', provider = MAP_PROVIDER) {
  const dark = mode === 'dark';
  // structuredClone (Modern Web Guidance): the style spec is plain JSON data, so a structured clone is equivalent
  // to the JSON round-trip here and keeps Dates/regexes/cycles intact if the spec ever carries them.
  const out = structuredClone(style);
  const keep = new Set(provider.keepLabelLayers);
  out.layers = out.layers.filter(l => !provider.hiddenLayers.includes(l.id)).map(layer => {
    const paint = { ...(layer.paint || {}) };
    const curated = dark ? curatedDarkPaint(layer) : null;
    for (const prop of Object.keys(paint)) {
      if (!prop.endsWith('-color')) continue;
      if (curated && prop in curated) continue;
      const role = roleOf(prop);
      paint[prop] = mapColors(paint[prop], c => (dark ? toDark(c, role) : (role === 'halo' ? c : restrainLight(c))));
    }
    if (curated) Object.assign(paint, curated);
    const next = { ...layer, paint };
    if (layer.type === 'raster') {
      // Natural-Earth shaded relief only shows at low zoom; keep it as a faint wash.
      next.paint = { ...paint, 'raster-saturation': -0.8, 'raster-opacity': dark ? 0.12 : 0.35, ...(dark ? { 'raster-brightness-max': 0.3 } : {}) };
    }
    if (layer.type === 'symbol') {
      const late = provider.lateLayers[layer.id];
      if (late != null) next.minzoom = Math.max(layer.minzoom || 0, late);
      if (!keep.has(layer.id)) {
        // Secondary labels: quieter than city/area names.
        next.paint = { ...next.paint, 'text-opacity': next.paint['text-opacity'] ?? 0.72, 'icon-opacity': next.paint['icon-opacity'] ?? 0.7 };
      }
    }
    return next;
  });
  return out;
}

const cache = new Map();

/** Resolves a ready-to-use style object for `mode`; falls back to the raw style URL if the fetch/transform fails. */
export async function loadMapStyle(mode = 'light', provider = MAP_PROVIDER, fetchImpl = (typeof fetch === 'function' ? fetch : null)) {
  const key = `${provider.styleUrl}|${mode}`;
  if (cache.has(key)) return cache.get(key);
  try {
    if (!fetchImpl) throw new Error('no fetch');
    const res = await fetchImpl(provider.styleUrl);
    if (!res.ok) throw new Error(`style ${res.status}`);
    const style = transformStyle(await res.json(), mode, provider);
    cache.set(key, style);
    return style;
  } catch {
    // Untransformed provider style still renders (and still carries its attribution).
    return provider.styleUrl;
  }
}

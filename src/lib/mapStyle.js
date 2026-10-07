// Web Map Explore basemap: provider/style configuration + a pure style transform.
// Everything provider-specific lives in MAP_PROVIDER so the basemap can be swapped
// (another OpenFreeMap style, a self-hosted style.json, a different vector provider)
// without touching src/screens/MapExplore.jsx. No API keys, no paid services.
//
// Light = OpenFreeMap "Liberty", toned down (less saturated fills, quieter secondary
// labels). Dark = the SAME Liberty style recoloured (so both modes show identical
// features/labels, unlike OpenFreeMap's separate near-black "dark" style).
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
// Dark mode: fills/lines flip into a compressed dark range; text flips light; halos go dark.
export function toDark(c, role = 'fill') {
  const sat = c.s * 0.5;
  if (role === 'text') return { h: c.h, s: sat * 0.6, l: clamp(0.58 + (1 - c.l) * 0.32, 0.55, 0.92), a: c.a };
  if (role === 'halo') return { h: c.h, s: sat * 0.5, l: clamp(0.08 + (1 - c.l) * 0.06, 0.06, 0.16), a: c.a };
  return { h: c.h, s: sat, l: clamp(0.07 + (1 - c.l) * 0.3, 0.06, 0.42), a: c.a };
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
  const out = JSON.parse(JSON.stringify(style));
  const keep = new Set(provider.keepLabelLayers);
  out.layers = out.layers.filter(l => !provider.hiddenLayers.includes(l.id)).map(layer => {
    const paint = { ...(layer.paint || {}) };
    for (const prop of Object.keys(paint)) {
      if (!prop.endsWith('-color')) continue;
      const role = roleOf(prop);
      paint[prop] = mapColors(paint[prop], c => (dark ? toDark(c, role) : (role === 'halo' ? c : restrainLight(c))));
    }
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

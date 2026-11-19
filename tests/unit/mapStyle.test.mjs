import test from 'node:test';
import assert from 'node:assert/strict';
import {
  parseColor, hsla, transformStyle, loadMapStyle, MAP_PROVIDER, PREMIUM_DARK, PAPER_LIGHT, curatedDarkPaint, toDark, restrainLight,
} from '../../src/lib/mapStyle.js';

const style = () => ({
  version: 8, sources: { openmaptiles: { type: 'vector', url: 'https://tiles.openfreemap.org/planet' } },
  layers: [
    { id: 'background', type: 'background', paint: { 'background-color': '#f8f4f0' } },
    { id: 'water', type: 'fill', source: 'openmaptiles', paint: { 'fill-color': 'rgb(158,189,255)' } },
    { id: 'park', type: 'fill', source: 'openmaptiles', paint: { 'fill-color': '#d8e8c8', 'fill-opacity': 0.7 } },
    { id: 'landuse_residential', type: 'fill', source: 'openmaptiles', paint: { 'fill-color': ['interpolate', ['linear'], ['zoom'], 9, 'hsla(0,3%,85%,0.84)', 12, 'hsla(35,57%,88%,0.49)'] } },
    { id: 'road_minor_casing', type: 'line', source: 'openmaptiles', paint: { 'line-color': '#cfcdca', 'line-width': 4 } },
    { id: 'road_minor', type: 'line', source: 'openmaptiles', paint: { 'line-color': '#fff', 'line-width': 2.5 } },
    { id: 'road_motorway', type: 'line', source: 'openmaptiles', paint: { 'line-color': 'hsl(26,87%,62%)', 'line-width': 8 } },
    { id: 'building', type: 'fill', source: 'openmaptiles', paint: { 'fill-color': 'hsl(35,8%,85%)', 'fill-outline-color': 'hsl(35,6%,79%)' } },
    { id: 'poi_r20', type: 'symbol', source: 'openmaptiles', paint: { 'text-color': '#666', 'text-halo-color': '#fff' } },
    { id: 'label_city', type: 'symbol', source: 'openmaptiles', paint: { 'text-color': '#333', 'text-halo-color': 'rgba(255,255,255,0.8)' } },
    { id: 'road_shield_us', type: 'symbol', source: 'openmaptiles', paint: {} },
    { id: 'ne2_shaded', type: 'raster', source: 'ne2_shaded', paint: {} },
    { id: 'tunnel_minor', type: 'line', source: 'openmaptiles', paint: { 'line-color': '#fff' } },
    { id: 'bridge_motorway', type: 'line', source: 'openmaptiles', paint: { 'line-color': '#fff' } },
  ],
});

const layer = (out, id) => out.layers.find(l => l.id === id);

test('parseColor handles hex, rgb(a), hsl(a) and rejects non-colours', () => {
  assert.ok(Math.abs(parseColor('#fff').l - 1) < 1e-9);
  assert.equal(parseColor('rgb(0,0,0)').l, 0);
  assert.equal(parseColor('hsla(35,57%,88%,0.49)').a, 0.49);
  assert.equal(parseColor('#ff000080').a.toFixed(2), '0.50');
  assert.equal(parseColor('park'), null);
  assert.equal(parseColor(['x']), null);
});

test('light transform is restrained and does not mutate the input', () => {
  const src = style(); const copy = JSON.stringify(src);
  const out = transformStyle(src, 'light');
  assert.equal(JSON.stringify(src), copy);
  const water = layer(out, 'water').paint['fill-color'];
  assert.ok(parseColor(water).s < parseColor('rgb(158,189,255)').s);
  assert.equal(layer(out, 'road_shield_us'), undefined);
  assert.ok(layer(out, 'poi_r20').minzoom >= 16);
  assert.equal(layer(out, 'label_city').paint['text-opacity'] ?? 1, 1);
  assert.ok(layer(out, 'poi_r20').paint['text-opacity'] < 1);
  assert.equal(out.sources.openmaptiles.url, src.sources.openmaptiles.url);
});

test('light transform uses the curated paper palette', () => {
  const out = transformStyle(style(), 'light');
  assert.equal(layer(out, 'background').paint['background-color'], PAPER_LIGHT.land);
  assert.equal(layer(out, 'water').paint['fill-color'], PAPER_LIGHT.water);
  assert.equal(layer(out, 'park').paint['fill-color'], PAPER_LIGHT.park);
  assert.equal(layer(out, 'road_minor_casing').paint['line-color'], PAPER_LIGHT.roadCasing);
  assert.ok(parseColor(layer(out, 'label_city').paint['text-color']).l < 0.3, 'dark ink labels on paper');
  assert.ok(parseColor(layer(out, 'water').paint['fill-color']).h > 180, 'water stays blue, not beige');
});

test('dark transform uses the curated ink palette instead of a lightness inversion', () => {
  const out = transformStyle(style(), 'dark');
  const land = parseColor(layer(out, 'background').paint['background-color']);
  const water = parseColor(layer(out, 'water').paint['fill-color']);
  const park = parseColor(layer(out, 'park').paint['fill-color']);
  assert.equal(layer(out, 'background').paint['background-color'], PREMIUM_DARK.land);
  assert.ok(land.l > 0.05 && land.l < 0.2, 'land is a deep ink, not black');
  assert.ok(water.s > land.s && water.l < 0.2, 'water is the bluer, more saturated plane');
  assert.ok(park.s > 0.2 && park.h > 120 && park.h < 200, 'parks stay green-teal');
  assert.equal(layer(out, 'park').paint['fill-opacity'], 0.95);
  assert.equal(layer(out, 'road_minor_casing').paint['line-color'], PREMIUM_DARK.roadCasing);
  assert.ok(layer(out, 'road_minor').paint['line-width'] > 0, 'widths are preserved');
});

test('dark road hierarchy climbs from street to motorway, above the land', () => {
  const out = transformStyle(style(), 'dark');
  const land = parseColor(PREMIUM_DARK.land).l;
  const minor = parseColor(PREMIUM_DARK.roadMinor).l;
  const motorway = parseColor(PREMIUM_DARK.roadMotorway).l;
  assert.ok(minor > land && motorway > minor, 'light climbs with importance');
  assert.equal(layer(out, 'road_motorway').paint['line-color'], PREMIUM_DARK.roadMotorway);
  // Tunnels sink, bridges step over the streets without becoming bright.
  assert.ok(parseColor(layer(out, 'tunnel_minor').paint['line-color']).l < minor);
  assert.equal(layer(out, 'bridge_motorway').paint['line-color'], PREMIUM_DARK.roadMotorway);
  assert.equal(curatedDarkPaint({ id: 'unknown_layer' }), null);
});

test('dark buildings and labels are readable without shouting', () => {
  const out = transformStyle(style(), 'dark');
  const land = parseColor(PREMIUM_DARK.land).l;
  const building = parseColor(layer(out, 'building').paint['fill-color']);
  assert.ok(building.l > land && building.l < 0.3, 'footprints are a quiet step above the land');
  const text = parseColor(layer(out, 'label_city').paint['text-color']);
  const halo = parseColor(layer(out, 'label_city').paint['text-halo-color']);
  assert.ok(text.l > 0.8 && halo.l < 0.1, 'light city names on a deep halo');
  assert.equal(layer(out, 'poi_r20').paint['icon-opacity'], 0.55);
});

test('loadMapStyle caches, and falls back to the raw style URL on failure', async () => {
  let calls = 0;
  const ok = async () => { calls++; return { ok: true, json: async () => style() }; };
  const a = await loadMapStyle('light', { ...MAP_PROVIDER, styleUrl: 'https://x.test/a' }, ok);
  const b = await loadMapStyle('light', { ...MAP_PROVIDER, styleUrl: 'https://x.test/a' }, ok);
  assert.equal(calls, 1); assert.equal(a, b);
  const bad = await loadMapStyle('dark', { ...MAP_PROVIDER, styleUrl: 'https://x.test/b' }, async () => { throw new Error('offline'); });
  assert.equal(bad, 'https://x.test/b');
  assert.equal(hsla(toDark(parseColor('#fff'))).startsWith('hsla('), true);
  assert.ok(restrainLight(parseColor('#00f')).s < 1);
});

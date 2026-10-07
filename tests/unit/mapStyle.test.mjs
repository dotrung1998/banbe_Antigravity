import test from 'node:test';
import assert from 'node:assert/strict';
import { parseColor, hsla, transformStyle, loadMapStyle, MAP_PROVIDER, toDark, restrainLight } from '../../src/lib/mapStyle.js';

const style = () => ({
  version: 8, sources: { openmaptiles: { type: 'vector', url: 'https://tiles.openfreemap.org/planet' } },
  layers: [
    { id: 'background', type: 'background', paint: { 'background-color': '#f8f4f0' } },
    { id: 'water', type: 'fill', source: 'openmaptiles', paint: { 'fill-color': 'rgb(158,189,255)' } },
    { id: 'landuse_residential', type: 'fill', source: 'openmaptiles', paint: { 'fill-color': ['interpolate', ['linear'], ['zoom'], 9, 'hsla(0,3%,85%,0.84)', 12, 'hsla(35,57%,88%,0.49)'] } },
    { id: 'poi_r20', type: 'symbol', source: 'openmaptiles', paint: { 'text-color': '#666', 'text-halo-color': '#fff' } },
    { id: 'label_city', type: 'symbol', source: 'openmaptiles', paint: { 'text-color': '#333', 'text-halo-color': 'rgba(255,255,255,0.8)' } },
    { id: 'road_shield_us', type: 'symbol', source: 'openmaptiles', paint: {} },
    { id: 'ne2_shaded', type: 'raster', source: 'ne2_shaded', paint: {} },
  ],
});

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
  const water = out.layers.find(l => l.id === 'water').paint['fill-color'];
  assert.ok(parseColor(water).s < parseColor('rgb(158,189,255)').s);
  assert.equal(out.layers.find(l => l.id === 'road_shield_us'), undefined);
  assert.ok(out.layers.find(l => l.id === 'poi_r20').minzoom >= 16);
  assert.equal(out.layers.find(l => l.id === 'label_city').paint['text-opacity'] ?? 1, 1);
  assert.ok(out.layers.find(l => l.id === 'poi_r20').paint['text-opacity'] < 1);
  assert.equal(out.sources.openmaptiles.url, src.sources.openmaptiles.url);
});

test('dark transform: dark fills, light text, dark halo, expressions recoloured', () => {
  const out = transformStyle(style(), 'dark');
  assert.ok(parseColor(out.layers[0].paint['background-color']).l < 0.45);
  const text = parseColor(out.layers.find(l => l.id === 'label_city').paint['text-color']);
  assert.ok(text.l > 0.55);
  assert.ok(parseColor(out.layers.find(l => l.id === 'label_city').paint['text-halo-color']).l < 0.2);
  const expr = out.layers.find(l => l.id === 'landuse_residential').paint['fill-color'];
  assert.equal(expr[0], 'interpolate');
  assert.ok(parseColor(expr[4]).l < 0.45 && parseColor(expr[6]).l < 0.45);
  assert.ok(out.layers.find(l => l.id === 'ne2_shaded').paint['raster-opacity'] < 0.3);
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

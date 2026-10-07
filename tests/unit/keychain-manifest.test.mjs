import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const src = path.join(root, 'assets/keychains');
const dirs = [path.join(root, 'public/keychains'), path.join(root, 'apps/ios/BanbeApp/Resources/Keychains')];
const m = JSON.parse(fs.readFileSync(path.join(src, 'manifest.json'), 'utf8'));
const expected = { sky: 3, love: 3, bloom: 4, cafe: 3, pals: 3, trip: 4, banbe: 4 };

test('manifest shape, ids and groups', () => {
  assert.equal(m.version, 1);
  assert.deepEqual(m.pivot, { x: 0.5, y: 0.045 });
  assert.deepEqual(m.imageSize, { width: 256, height: 384 });
  assert.equal(m.baseWidth, 64);
  assert.equal(m.designs.length, 24);
  assert.equal(new Set(m.designs.map((d) => d.id)).size, 24);
  assert.equal(m.groups.length, 7);
  for (const g of m.groups) { assert.ok(g.vi && g.en); assert.equal(m.designs.filter((d) => d.group === g.id).length, expected[g.id], g.id); }
  for (const d of m.designs) { assert.ok(d.vi && d.en); assert.equal(d.file, d.id + '.png'); }
});

test('PNGs exist in both dirs with 256x384 alpha', () => {
  for (const dir of dirs) for (const d of m.designs) {
    const b = fs.readFileSync(path.join(dir, d.file));
    assert.equal(b.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
    assert.equal(b.subarray(12, 16).toString(), 'IHDR');
    assert.equal(b.readUInt32BE(16), 256); assert.equal(b.readUInt32BE(20), 384);
    assert.ok([4, 6].includes(b[25]), d.id + ' colour type');
  }
});

test('manifest identical in both dirs and matches source', () => {
  const a = fs.readFileSync(path.join(dirs[0], 'manifest.json'), 'utf8');
  assert.equal(a, fs.readFileSync(path.join(dirs[1], 'manifest.json'), 'utf8'));
  assert.deepEqual(JSON.parse(a), m);
});

test('SVG sources are safe', () => {
  for (const d of m.designs) {
    const s = fs.readFileSync(path.join(src, 'svg', d.id + '.svg'), 'utf8');
    assert.ok(!/<script/i.test(s) && !/<foreignObject/i.test(s), d.id);
    assert.ok(!/\son\w+\s*=/i.test(s), d.id + ' on*=');
    assert.ok(!/(?:xlink:)?href\s*=\s*["']\s*(?:https?:)?\/\//i.test(s), d.id + ' remote href');
    assert.ok(s.length < 6144, d.id + ' size');
  }
});

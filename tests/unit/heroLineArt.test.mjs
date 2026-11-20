import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { HERO_LINE_ART, HERO_ART_BOX, heroArtSvg, heroArtAsset, heroArtKind } from '../../src/lib/heroLineArt.js';

const catalog = new URL('../../apps/ios/BanbeApp/Resources/Assets.xcassets/', import.meta.url).pathname;

test('every hero sketch has an identical iOS imageset (run scripts/gen-hero-line-art.mjs)', () => {
  for (const kind of ['tonight', 'weekend', 'all', 'browse', 'foryou']) {
    const name = heroArtAsset(kind);
    assert.equal(readFileSync(`${catalog}${name}.imageset/${name}.svg`, 'utf8'), heroArtSvg(kind), kind);
    const meta = JSON.parse(readFileSync(`${catalog}${name}.imageset/Contents.json`, 'utf8'));
    assert.equal(meta.properties['template-rendering-intent'], 'template');
    assert.equal(meta.properties['preserves-vector-representation'], true);
  }
});

test('sketches stay compact, in the box, and only use path commands', () => {
  for (const [kind, parts] of Object.entries(HERO_LINE_ART)) {
    assert.ok(heroArtSvg(kind).length < 6000, `${kind} under 6 KB`);
    for (const d of parts) assert.match(d, /^M[-0-9.,\sMLHVCQAZmlhvcqaz]+$/, `${kind}: ${d}`);
    assert.equal(HERO_ART_BOX.width, 228);
  }
});

test('heroArtKind falls back to the city skyline', () => {
  assert.equal(heroArtKind('tonight'), 'tonight');
  assert.equal(heroArtKind('hosting'), 'all');
});

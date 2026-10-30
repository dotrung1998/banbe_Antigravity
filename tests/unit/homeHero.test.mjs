// Simple Shell Home hero (note 66). Mirrored by apps/ios/BanbeAppTests/HomeHeroTests.swift through the same fixture.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { pickGoerHero, pickHostHero } from '../../src/lib/homeHero.js';

const fx = JSON.parse(readFileSync(new URL('../fixtures/home-hero.json', import.meta.url), 'utf8'));

for (const c of fx.goer) {
  test(`goer hero: ${c.case}`, () => {
    assert.equal(pickGoerHero({ ...c.input, nextUp: c.input.nextUp ? {} : null }), c.expect);
  });
}
for (const c of fx.host) {
  test(`host hero: ${c.case}`, () => {
    assert.equal(pickHostHero(c.events, fx.now)?.key ?? null, c.expect);
  });
}

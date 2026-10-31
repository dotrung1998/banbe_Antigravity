// Event Detail presentation (notes 68, 70) against the shared fixture; mirrored by
// apps/ios/BanbeAppTests/EventDetailPresentationTests.swift — change both together.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { seatStatus, splitFacts, aboutSection, ABOUT_CLAMP_CHARS, includedSection, distanceLabel, dateTileLabel, stripPhotos, HERO_SCRIM, scrimContrast } from '../../src/lib/eventDetailPresentation.js';
import { profileFor, detailFacts } from '../../src/lib/eventTypes.js';

const fx = JSON.parse(readFileSync(new URL('../fixtures/event-detail-presentation.json', import.meta.url)));
const round = (x) => (x == null ? null : Math.round(x * 10000) / 10000);

for (const c of fx.seatStatus) {
  test(`seatStatus: ${c.name}`, () => {
    const out = seatStatus(c.in);
    assert.deepEqual({ ...out, ratio: round(out.ratio) }, c.out);
  });
}

for (const c of fx.splitFacts) {
  test(`splitFacts: ${c.name}`, () => {
    const out = splitFacts(c.in.map(id => ({ id, label: id, value: 'x' })));
    assert.deepEqual({ minAge: out.minAge?.id ?? null, chips: out.chips.map(f => f.id), rows: out.rows.map(f => f.id) }, c.out);
  });
}

for (const c of fx.splitFactsValues) {
  test(`splitFacts values: ${c.name}`, () => {
    const facts = c.in.map(f => ({ id: f.id, label: f.id, value: (f.values || ['x']).join(', '), ...(f.values ? { values: f.values } : {}) }));
    const out = splitFacts(facts);
    assert.deepEqual(out.chips.map(f => [f.id, f.values ? f.value : null]), c.out.chips);
  });
}

for (const c of fx.includedSection) {
  test(`includedSection: ${c.name}`, () => assert.deepEqual(includedSection(c.in), c.out));
}

for (const c of fx.distanceLabel) {
  test(`distanceLabel: ${c.name}`, () => assert.equal(distanceLabel(c.km, c.en), c.out));
}

for (const c of fx.dateTileLabel) {
  test(`dateTileLabel: ${c.name}`, () => assert.equal(dateTileLabel(c.raw, c.en), c.out));
}

for (const c of fx.stripPhotos) {
  test(`stripPhotos: ${c.name}`, () => assert.deepEqual(stripPhotos(c.in.map(url => ({ url })), c.hero).map(p => p.url), c.out));
}

for (const c of fx.aboutSection) {
  test(`aboutSection: ${c.name}`, () => assert.deepEqual(aboutSection(c.in), c.out));
}

test('aboutSection: a long description clamps', () => {
  assert.equal(aboutSection({ desc: 'x'.repeat(ABOUT_CLAMP_CHARS + 1) }).clampable, true);
  assert.equal(aboutSection({ desc: 'x'.repeat(ABOUT_CLAMP_CHARS) }).clampable, false);
});

// The required fields (alcohol, minimum age) always reach the screen for every type: as the pill or a chip.
for (const key of ['supper', 'music', 'gallery', 'fashion', 'popup']) {
  test(`every type keeps alcohol + minimum age visible: ${key}`, () => {
    const profile = profileFor(key);
    const facts = detailFacts(profile, { alcohol: 'none', min_age: '18' }, 'en');
    const { minAge, chips } = splitFacts(facts);
    assert.equal(minAge?.value, '18+');
    assert.ok(chips.some(f => f.id === 'alcohol'));
  });
}

test('supper dietary with two choices reaches the screen as two chips', () => {
  const facts = detailFacts(profileFor('supper'), { alcohol: 'included', min_age: '18', dietary: ['vegetarian', 'can_accommodate'] }, 'en');
  const dietary = splitFacts(facts).chips.filter(f => f.id === 'dietary');
  assert.equal(dietary.length, 2);
  assert.ok(dietary.every(f => !f.value.includes(',')));
});

test('hero scrim: white title text keeps 4.5:1 even on a white photo', () => {
  assert.ok(scrimContrast(HERO_SCRIM.alpha) >= 4.5, String(scrimContrast(HERO_SCRIM.alpha)));
  assert.ok(HERO_SCRIM.end >= HERO_SCRIM.alpha && HERO_SCRIM.full > HERO_SCRIM.start);
});

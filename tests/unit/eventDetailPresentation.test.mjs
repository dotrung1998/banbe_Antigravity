// Event Detail presentation (note 68) against the shared fixture; mirrored by
// apps/ios/BanbeAppTests/EventDetailPresentationTests.swift — change both together.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { seatStatus, splitFacts, aboutSection, ABOUT_CLAMP_CHARS } from '../../src/lib/eventDetailPresentation.js';
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

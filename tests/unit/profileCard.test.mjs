// The personal profile identity card (note 68) against the shared fixture; mirrored by
// apps/ios/BanbeAppTests/ProfileCardTests.swift — change both together.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { roleLabel, dedupeChips, profileStats, upcomingEvents, cardSurface, CARD_TINT, CARD_GLOW } from '../../src/lib/profileCard.js';
import { PROFILE_PALETTES } from '../../src/lib/profileTheme.js';

const fx = JSON.parse(readFileSync(new URL('../fixtures/profile-card.json', import.meta.url)));
const tokens = JSON.parse(readFileSync(new URL('../fixtures/design-tokens.json', import.meta.url)));

test('palettes and surface constants match the shared fixture', () => {
  assert.deepEqual(Object.fromEntries(PROFILE_PALETTES.map(p => [p.key, p.color])), fx.palettes);
  assert.equal(CARD_TINT, fx.tint);
  assert.equal(CARD_GLOW, fx.glow);
});

for (const c of fx.roleLabel) {
  test(`roleLabel ${JSON.stringify(c.in)}`, () => {
    assert.equal(roleLabel(c.in, false), c.en);
    assert.equal(roleLabel(c.in, true), c.vi);
  });
}

for (const c of fx.dedupeChips) test(`dedupeChips: ${c.name}`, () => assert.deepEqual(dedupeChips(c.chips, c.shown), c.out));

for (const c of fx.profileStats) {
  test(`profileStats: ${c.name}`, () => assert.deepEqual(profileStats(c.in).map(x => [x.id, x.value]), c.out));
}

for (const c of fx.upcoming.cases) {
  test(`upcomingEvents: ${c.name}`, () => {
    assert.deepEqual(upcomingEvents({ events: fx.upcoming.events, ...c.in }).map(e => [e.key, e.role]), c.out);
  });
}

// WCAG: ink and ink2 text keep at least 4.5:1 over every palette's card, both on the tint and at the glow. The card's
// secondary text is ink2, never ink3 (ink3 drops to ~3.8:1 on the dark tint).
const hex = (h) => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
const lum = (rgb) => {
  const [r, g, b] = rgb.map(v => { const c = v / 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((m, n) => n - m); return (x + 0.05) / (y + 0.05); };
const over = (fg, bg, a) => fg.map((v, i) => v * a + bg[i] * (1 - a));
for (const theme of ['light', 'dark']) {
  const t = tokens[theme];
  for (const [key, color] of Object.entries(fx.palettes)) {
    test(`${theme}/${key}: card text keeps 4.5:1`, () => {
      const surf = cardSurface(color, t);
      for (const bgHex of [surf.tinted, surf.glow]) {
        const bg = hex(bgHex), ink = hex(t.ink);
        for (const [name, a] of [['ink', 1], ['ink2', t.ink2Alpha]]) {
          const r = ratio(over(ink, bg, a), bg);
          assert.ok(r >= 4.5, `${theme}/${key} ${name} on ${bgHex}: ${r.toFixed(2)}`);
        }
      }
    });
  }
}

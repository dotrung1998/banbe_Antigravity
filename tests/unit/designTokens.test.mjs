// Simple Shell tokens (note 66): src/index.css matches the shared fixture, every text token keeps WCAG AA on every
// surface in both themes, and the theme choice rules match iOS (apps/ios/BanbeAppTests/DesignTokensTests.swift).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { normalizeThemeChoice, resolveTheme } from '../../src/lib/themeChoice.js';

const fx = JSON.parse(readFileSync(new URL('../fixtures/design-tokens.json', import.meta.url)));
const css = readFileSync(new URL('../../src/index.css', import.meta.url), 'utf8');

const hex = (h) => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
const lum = (rgb) => {
  const [r, g, b] = rgb.map(v => { const c = v / 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((m, n) => n - m); return (x + 0.05) / (y + 0.05); };
const over = (fg, bg, a) => fg.map((v, i) => Math.round(v * a + bg[i] * (1 - a)));

function block(selector) {
  const start = css.indexOf(selector);
  assert.ok(start >= 0, `missing ${selector}`);
  return css.slice(start, css.indexOf('\n}\n', start));
}
const BLOCKS = { light: block(':root, [data-bb-theme="light"] {'), dark: block('[data-bb-theme="dark"] {') };
const VARS = { paper: '--bb-bg', ink: '--bb-fg', field: '--bb-field', surface1: '--bb-surface-1', surface2: '--bb-surface-2',
  surface3: '--bb-surface-3', alert: '--bb-alert', clay: '--bb-clay', honey: '--bb-honey' };

for (const theme of ['light', 'dark']) {
  const t = fx[theme];
  test(`${theme}: index.css matches the shared token fixture`, () => {
    for (const [key, name] of Object.entries(VARS)) {
      const m = BLOCKS[theme].match(new RegExp(`${name}:\\s*(#[0-9A-Fa-f]{6})`));
      assert.ok(m, `${theme} ${name} not found`);
      assert.equal(m[1].toUpperCase(), t[key].toUpperCase(), `${theme} ${name}`);
    }
  });
  test(`${theme}: text tokens keep WCAG AA on paper and every surface`, () => {
    const ink = hex(t.ink);
    for (const bgKey of ['paper', 'surface1', 'surface2', 'surface3', 'field']) {
      const bg = hex(t[bgKey]);
      assert.ok(ratio(ink, bg) >= fx.minContrast.ink, `${theme} ink on ${bgKey}`);
      assert.ok(ratio(over(ink, bg, t.ink2Alpha), bg) >= fx.minContrast.ink2, `${theme} ink2 on ${bgKey}`);
      assert.ok(ratio(over(ink, bg, t.ink3Alpha), bg) >= fx.minContrast.ink3, `${theme} ink3 on ${bgKey}`);
      assert.ok(ratio(hex(t.alert), bg) >= fx.minContrast.alert, `${theme} alert on ${bgKey}`);
    }
  });
}

test('theme choice: new installs start on system, saved choices are kept', () => {
  for (const c of fx.themeChoice) assert.equal(normalizeThemeChoice(c.stored ?? undefined, c.fresh), c.choice, JSON.stringify(c));
});

test('theme choice: system follows the device', () => {
  for (const c of fx.themeResolve) assert.equal(resolveTheme(c.choice, c.systemDark), c.theme, JSON.stringify(c));
});

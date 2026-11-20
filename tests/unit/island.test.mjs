import test from 'node:test';
import assert from 'node:assert/strict';
import {
  DEFAULT_ISLAND_PREFS, ISLAND_THEMES, ISLAND_THEME_IDS, islandTheme, islandThemeVars, normalizeIslandPrefs,
} from '../../src/lib/islandPrefs.js';
import { ISLAND_CASES, ISLAND_CASE_GROUPS } from '../../src/lib/islandCases.js';
import { islandPresentation } from '../../src/lib/islandNotifications.js';

test('every island theme is complete and uniquely named', () => {
  assert.equal(new Set(ISLAND_THEME_IDS).size, ISLAND_THEMES.length);
  assert.ok(ISLAND_THEMES.length >= 8);
  for (const t of ISLAND_THEMES) {
    for (const key of ['background', 'foreground', 'muted', 'ring', 'button', 'success', 'error', 'warning', 'info', 'loading', 'live']) {
      assert.equal(typeof t.theme[key], 'string', `${t.id}.${key}`);
      assert.ok(t.theme[key].length > 0, `${t.id}.${key} is empty`);
    }
  }
  assert.equal(islandTheme('does-not-exist').id, ISLAND_THEMES[0].id);
});

test('islandThemeVars keeps dynaura theme-key order (the adapter applies values by index)', () => {
  assert.deepEqual(Object.keys(islandThemeVars('midnight')), [
    '--dynaura-bg', '--dynaura-fg', '--dynaura-muted', '--dynaura-ring', '--dynaura-btn',
    '--dynaura-success', '--dynaura-error', '--dynaura-warning', '--dynaura-info', '--dynaura-loading', '--dynaura-live',
  ]);
});

test('unknown saved preferences fall back; valid ones survive', () => {
  assert.deepEqual(normalizeIslandPrefs(null), DEFAULT_ISLAND_PREFS);
  assert.deepEqual(normalizeIslandPrefs({ theme: 'nope', position: 'left', detail: 'all', motion: 'fast', swipe: 'yes' }), DEFAULT_ISLAND_PREFS);
  const kept = normalizeIslandPrefs({ theme: 'plum', position: 'bottom', detail: 'title', motion: 'calm', swipe: false, haptics: false });
  assert.deepEqual(kept, { theme: 'plum', position: 'bottom', detail: 'title', motion: 'calm', swipe: false, haptics: false });
  assert.equal(normalizeIslandPrefs({ ...kept, extra: 1 }).extra, undefined);
});

test('every demo case belongs to a known group and has a unique key', () => {
  const groups = new Set(ISLAND_CASE_GROUPS.map(g => g.key));
  const keys = ISLAND_CASES.map(c => c.key);
  assert.equal(new Set(keys).size, keys.length);
  for (const c of ISLAND_CASES) {
    assert.ok(groups.has(c.group), `${c.key} has an unknown group`);
    assert.ok(c.vi && c.en, `${c.key} needs a label`);
  }
  for (const g of ISLAND_CASE_GROUPS) assert.ok(ISLAND_CASES.some(c => c.group === g.key), `${g.key} is empty`);
  // The full dynaura surface the demo promises to cover.
  const modes = new Set(ISLAND_CASES.map(c => c.mode));
  for (const mode of ['toast', 'promise', 'progress', 'update', 'live', 'queue', 'card-ticket', 'card-host', 'custom-seats']) {
    assert.ok(modes.has(mode), `missing demo mode ${mode}`);
  }
});

test('real notification kinds map to a sensible island state and button', () => {
  assert.deepEqual(islandPresentation({ kind: 'payment_confirmed' }), { type: 'success', action: true });
  assert.deepEqual(islandPresentation({ kind: 'booking_cancelled' }), { type: 'error', action: true });
  assert.deepEqual(islandPresentation({ kind: 'event_reminder_soon' }), { type: 'warning', action: true });
  assert.deepEqual(islandPresentation({ kind: 'dispute_message' }), { type: 'warning', action: true });
  assert.deepEqual(islandPresentation({ kind: 'weekly_digest' }), { type: 'warning', action: false });
  assert.deepEqual(islandPresentation({ kind: 'something_new' }), { type: 'info', action: false });
  assert.deepEqual(islandPresentation(null), { type: 'info', action: false });
});

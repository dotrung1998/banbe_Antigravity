import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { FLAG_KEYS } from '../../src/lib/featureFlags.js';
import { FLAG_CATEGORIES, keysOf } from '../../src/lib/featureFlagCategories.js';

const IOS_ONLY = ['admin_event_wipe'];
const swift = readFileSync(new URL('../../apps/ios/BanbeApp/Lib/FeatureFlagCategories.swift', import.meta.url), 'utf8');

test('every web flag key is in exactly one category', () => {
  const seen = FLAG_CATEGORIES.flatMap(c => c.flags.flatMap(keysOf));
  assert.deepEqual([...seen].sort(), [...FLAG_KEYS].sort());
  assert.equal(new Set(seen).size, seen.length);
});

test('iOS categories match web (same keys, order and rows; iOS-only rows aside)', () => {
  const cats = [...swift.matchAll(/Category\(key: "([a-z]+)"[^)]*?flags: \[([^\]]*)\]/gs)].map(m => ({
    key: m[1], flags: [...m[2].matchAll(/"([a-z0-9_]+)"/g)].map(x => x[1]).filter(k => !IOS_ONLY.includes(k)),
  }));
  assert.deepEqual(cats, FLAG_CATEGORIES.map(c => ({ key: c.key, flags: c.flags })));
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { FLAG_KEYS } from '../../src/lib/featureFlags.js';
import { FLAG_CATEGORIES, CONTROL_KEYS, keysOf } from '../../src/lib/featureFlagCategories.js';

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

test('every flag key has a labelled row on both admin screens (a missing row silently hides the switch)', () => {
  const web = readFileSync(new URL('../../src/screens/AdminFeatures.jsx', import.meta.url), 'utf8');
  const ios = readFileSync(new URL('../../apps/ios/BanbeApp/Views/AdminFeaturesView.swift', import.meta.url), 'utf8');
  // Keys behind a combined control (onboarding_v2 + onboarding_v3) are drawn by that control, not their own row.
  const controlled = new Set(Object.values(CONTROL_KEYS).flat().filter(k => k !== 'onboarding_v2'));
  for (const k of FLAG_KEYS.filter(k => !controlled.has(k))) {
    assert.ok(web.includes(`key: '${k}'`), `web row for ${k}`);
    assert.ok(ios.includes(`Flag(key: "${k}"`), `iOS row for ${k}`);
  }
});

test('web and iOS know the same flag keys and the same off-unless-set list (iOS-only rows aside)', async () => {
  const { OFF_UNLESS_SET } = await import('../../src/lib/featureFlags.js');
  const flags = readFileSync(new URL('../../apps/ios/BanbeApp/Lib/FeatureFlags.swift', import.meta.url), 'utf8');
  const list = name => [...flags.match(new RegExp(`static let ${name}[^=]*=\\s*\\[([^\\]]*)\\]`, 's'))[1].matchAll(/"([a-z0-9_]+)"/g)]
    .map(m => m[1]).filter(k => !IOS_ONLY.includes(k));
  assert.deepEqual(list('keys').sort(), [...FLAG_KEYS].sort());
  assert.deepEqual(list('offUnlessSet').sort(), [...OFF_UNLESS_SET].sort());
});

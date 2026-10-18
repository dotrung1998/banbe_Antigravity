import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeFlags, flagOn, readCachedFlags, writeCachedFlags } from '../../src/lib/featureFlags.js';

// Mirrored by apps/ios/BanbeAppTests/FeatureFlagsTests.swift — change both together.
const memory = () => { const m = new Map(); return { getItem: k => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, v) }; };

test('a missing key means on; only an explicit false hides', () => {
  assert.equal(flagOn({}, 'rewards'), true);
  assert.equal(flagOn(null, 'rewards'), true);
  assert.equal(flagOn(undefined, 'rewards'), true);
  assert.equal(flagOn({ rewards: true }, 'rewards'), true);
  assert.equal(flagOn({ rewards: false }, 'rewards'), false);
});

test('normalize keeps known booleans only', () => {
  assert.deepEqual(normalizeFlags({ rewards: false }), { rewards: false });
  assert.deepEqual(normalizeFlags({ rewards: 'false' }), {});
  assert.deepEqual(normalizeFlags({ rewards: 0 }), {});
  assert.deepEqual(normalizeFlags({ somethingNew: false, rewards: true }), { rewards: true });
  assert.deepEqual(normalizeFlags([true]), {});
  assert.deepEqual(normalizeFlags(null), {});
  assert.deepEqual(normalizeFlags('x'), {});
});

test('the cache round-trips and survives garbage or a missing store', () => {
  const store = memory();
  assert.deepEqual(readCachedFlags(store), {});
  writeCachedFlags({ rewards: false }, store);
  assert.deepEqual(readCachedFlags(store), { rewards: false });
  store.setItem('banbe_feature_flags_v1', '{not json');
  assert.deepEqual(readCachedFlags(store), {});
  assert.deepEqual(readCachedFlags(null), {});
  assert.doesNotThrow(() => writeCachedFlags({ rewards: true }, null));
  assert.doesNotThrow(() => writeCachedFlags({ rewards: true }, { setItem() { throw new Error('quota'); } }));
});

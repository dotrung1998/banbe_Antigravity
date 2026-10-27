import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeFlags, flagOn, readCachedFlags, writeCachedFlags, onboardingVersion } from '../../src/lib/featureFlags.js';

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

test('rewards_v2 stays off unless the server says true (a new feature must not appear by accident)', () => {
  assert.equal(flagOn({}, 'rewards_v2'), false);
  assert.equal(flagOn(null, 'rewards_v2'), false);
  assert.equal(flagOn({ rewards_v2: false }, 'rewards_v2'), false);
  assert.equal(flagOn({ rewards_v2: true }, 'rewards_v2'), true);
  assert.deepEqual(normalizeFlags({ rewards: true, rewards_v2: true }), { rewards: true, rewards_v2: true });
});

test('onboarding_v2 (migration 201): missing or false = Version 1, only true = Version 2', () => {
  assert.equal(flagOn({}, 'onboarding_v2'), false);
  assert.equal(flagOn(null, 'onboarding_v2'), false);
  assert.equal(flagOn({ onboarding_v2: false }, 'onboarding_v2'), false);
  assert.equal(flagOn({ onboarding_v2: true }, 'onboarding_v2'), true);
  assert.deepEqual(normalizeFlags({ onboarding_v2: true, onboarding_v4: true }), { onboarding_v2: true });
});

test('onboardingVersion (migration 202): v3 > v2 > v1, missing = 1', () => {
  assert.equal(onboardingVersion({}), 1);
  assert.equal(onboardingVersion(null), 1);
  assert.equal(onboardingVersion({ onboarding_v2: false, onboarding_v3: false }), 1);
  assert.equal(onboardingVersion({ onboarding_v2: true }), 2);
  assert.equal(onboardingVersion({ onboarding_v3: true }), 3);
  assert.equal(onboardingVersion({ onboarding_v2: true, onboarding_v3: true }), 3);
  assert.equal(onboardingVersion(normalizeFlags({ onboarding_v3: 'true' })), 1);
});

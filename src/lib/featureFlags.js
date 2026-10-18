// Platform feature flags (migration 187): a platform admin can hide a feature everywhere without a release.
// iOS twin: apps/ios/BanbeApp/Lib/FeatureFlags.swift — keep both and their tests in sync (note 51).
//
// Rules (so a flag can never hide something by accident):
// - A key that is MISSING means "on". Only an explicit `false` from the server hides a feature.
// - The server answer is cached on the device, so a cold start without network keeps the last-known value instead
//   of flipping a hidden feature back on (or a visible one off). The very first run, before any answer, shows
//   everything, which is the behaviour from before flags existed.
// - Anything that is not a boolean is ignored.

export const FLAG_KEYS = ['rewards'];
const CACHE_KEY = 'banbe_feature_flags_v1';

/** Keep only known keys with real booleans. Unknown keys from a newer server are ignored, never trusted. */
export function normalizeFlags(data) {
  const out = {};
  if (!data || typeof data !== 'object' || Array.isArray(data)) return out;
  for (const k of FLAG_KEYS) if (typeof data[k] === 'boolean') out[k] = data[k];
  return out;
}

/** Missing key = on. */
export function flagOn(flags, key) {
  return !(flags && flags[key] === false);
}

export function readCachedFlags(storage = typeof localStorage !== 'undefined' ? localStorage : null) {
  try { return normalizeFlags(JSON.parse(storage?.getItem(CACHE_KEY) || 'null')); } catch { return {}; }
}

export function writeCachedFlags(flags, storage = typeof localStorage !== 'undefined' ? localStorage : null) {
  try { storage?.setItem(CACHE_KEY, JSON.stringify(normalizeFlags(flags))); } catch { /* private mode: only a convenience */ }
}

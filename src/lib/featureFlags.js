// Platform feature flags (migration 187): a platform admin can hide a feature everywhere without a release.
// iOS twin: apps/ios/BanbeApp/Lib/FeatureFlags.swift — keep both and their tests in sync (note 51).
//
// Rules (so a flag can never hide something by accident):
// - A key that is MISSING means "on". Only an explicit `false` from the server hides a feature. Exception:
//   OFF_UNLESS_SET keys are NEW features that must stay dark until an admin turns them on (same list as iOS).
// - The server answer is cached on the device, so a cold start without network keeps the last-known value instead
//   of flipping a hidden feature back on (or a visible one off). The very first run, before any answer, shows
//   everything, which is the behaviour from before flags existed.
// - Anything that is not a boolean is ignored.

export const FLAG_KEYS = ['rewards', 'rewards_v2', 'push_enabled', 'app_events', 'event_reminders', 'event_recap', 'host_recap', 'follow_alerts', 'weekly_digest', 'intent_foryou', 'live_activity', 'market_share'];
// push_enabled (migration 194): real push notifications (iPhone), dark until an admin turns it on.
// app_events (migration 196): first-party measurement; nothing is sent until an admin turns it on.
// Migrations 199/200: event_reminders is on unless an admin turns it off; the rest stay dark until set.
export const OFF_UNLESS_SET = ['rewards_v2', 'push_enabled', 'app_events', 'event_recap', 'host_recap', 'follow_alerts', 'weekly_digest', 'intent_foryou', 'live_activity', 'market_share'];
const CACHE_KEY = 'banbe_feature_flags_v1';

/** Keep only known keys with real booleans. Unknown keys from a newer server are ignored, never trusted. */
export function normalizeFlags(data) {
  const out = {};
  if (!data || typeof data !== 'object' || Array.isArray(data)) return out;
  for (const k of FLAG_KEYS) if (typeof data[k] === 'boolean') out[k] = data[k];
  return out;
}

/** Missing key = on (except OFF_UNLESS_SET keys, which need an explicit true). */
export function flagOn(flags, key) {
  if (OFF_UNLESS_SET.includes(key)) return !!(flags && flags[key] === true);
  return !(flags && flags[key] === false);
}

export function readCachedFlags(storage = typeof localStorage !== 'undefined' ? localStorage : null) {
  try { return normalizeFlags(JSON.parse(storage?.getItem(CACHE_KEY) || 'null')); } catch { return {}; }
}

export function writeCachedFlags(flags, storage = typeof localStorage !== 'undefined' ? localStorage : null) {
  try { storage?.setItem(CACHE_KEY, JSON.stringify(normalizeFlags(flags))); } catch { /* private mode: only a convenience */ }
}

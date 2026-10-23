// Feature-switched CONTENT (policy + guides + Q&A). iOS twin: apps/ios/BanbeApp/Lib/ContentFlags.swift — keep both and
// their tests in sync (note 59).
//
// A piece of text tied to a feature carries ONE marker naming a content key. The renderer drops it when that key is
// off, so with Rewards switched off the policy, the guides, their table of contents and their search never mention
// rewards. Switching the feature on shows it again without a release (flags come from get_feature_flags).
//
// Content keys (built on the platform flags in featureFlags.js, so "missing flag = on" still holds for `rewards`):
//   rewards        Rewards is on                                   (anything about coins, badges, streaks…)
//   rewards_daily  Rewards is on and Rewards v2 is off             (the daily streak the app shows today)
//   rewards_v2     Rewards is on and Rewards v2 is on              (weekly streak, grace weeks, repair, tiers, goal)
//   push_enabled   real push notifications are on (migration 194)  (APNs, quiet hours, device tokens)
//   app_events     first-party measurement is on (migration 196)   (usage events, 13-month retention)
//   event_reminders, event_recap, host_recap, follow_alerts (199); weekly_digest, live_activity (200): one key per switch
//
// Markers in the help data (src/data/help/*.js):
//   section   { id, vi, en, blocks, flag: 'rewards' }
//   block     ['flag', 'rewards', <any block>]
//   list item [vi, en, 'rewards']
import { flagOn } from './featureFlags.js';

export const CONTENT_KEYS = ['rewards', 'rewards_daily', 'rewards_v2', 'push_enabled', 'app_events', 'event_reminders',
  'event_recap', 'host_recap', 'follow_alerts', 'weekly_digest', 'live_activity'];

/** Is content tagged `key` shown under these platform flags? An unknown key is never shown. */
export function contentOn(flags, key) {
  if (!key) return true;
  const rewards = flagOn(flags, 'rewards');
  switch (key) {
    case 'rewards': return rewards;
    case 'rewards_daily': return rewards && !flagOn(flags, 'rewards_v2');
    case 'rewards_v2': return rewards && flagOn(flags, 'rewards_v2');
    // Switches that are dark until set (featureFlags.js OFF_UNLESS_SET): only an explicit true shows their text.
    case 'push_enabled':
    case 'app_events':
    case 'event_recap':
    case 'host_recap':
    case 'follow_alerts':
    case 'weekly_digest':
    case 'live_activity': return !!(flags && flags[key] === true);
    // On unless an admin turned it off (migration 199 seeds it ON).
    case 'event_reminders': return flagOn(flags, 'event_reminders');
    default: return false;
  }
}

function filterBlock(b, flags) {
  if (!Array.isArray(b)) return null;
  if (b[0] === 'flag') return contentOn(flags, b[1]) ? filterBlock(b[2], flags) : null;
  if (b[0] === 'ul' || b[0] === 'ol') {
    const items = b[1].filter(it => contentOn(flags, it[2])).map(it => [it[0], it[1]]);
    return items.length ? [b[0], items] : null;
  }
  return b;
}

/**
 * Sections with every switched-off piece removed: whole sections, blocks and list items. A section left with no
 * blocks disappears too, so the table of contents and the search never point at an empty heading.
 */
export function filterHelpSections(sections, flags) {
  const out = [];
  for (const s of Array.isArray(sections) ? sections : []) {
    if (!contentOn(flags, s.flag)) continue;
    const blocks = s.blocks.map(b => filterBlock(b, flags)).filter(Boolean);
    if (blocks.length) out.push({ ...s, blocks });
  }
  return out;
}

/**
 * Policy tables: a row is either an array of cells or { flag, cells }. Pass the platform flags, or (as the policy
 * screen does) an `on(key)` predicate that also knows whether the flags have arrived yet.
 */
export function filterPolicyRows(rows, flags, on = (key) => contentOn(flags, key)) {
  return (Array.isArray(rows) ? rows : [])
    .filter(r => Array.isArray(r) || on(r.flag))
    .map(r => (Array.isArray(r) ? r : r.cells));
}

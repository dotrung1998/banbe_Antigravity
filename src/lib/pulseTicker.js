// Pure helpers for the Home Pulse ticker (note 51). iOS twin: apps/ios/BanbeApp/Lib/PulseTicker.swift — keep both
// and their tests in sync. The component only renders what these return.

export const MAX_ITEMS = 5;
const SECONDS_PER_CHAR = 0.26; // a fixed reading-speed feel: longer lists scroll for longer, never faster
const MIN_SECONDS = 14;
const EXTRA_CHARS_PER_ITEM = 4; // the rank number and the gap between items

/** The top events to show: skips rows without a name, keeps the server's order, numbers them 1..N. */
export function tickerItems(pulse) {
  return (pulse || []).filter(p => p && typeof p.event_name === 'string' && p.event_name.trim()).slice(0, MAX_ITEMS)
    .map((p, i) => ({ id: p.event_id || `${i}`, rank: i + 1, name: p.event_name.trim() }));
}

/** Seconds for one full pass of the strip. */
export function tickerSeconds(items) {
  const chars = (items || []).reduce((n, it) => n + it.name.length + EXTRA_CHARS_PER_ITEM, 0);
  return Math.max(MIN_SECONDS, Math.round(chars * SECONDS_PER_CHAR));
}

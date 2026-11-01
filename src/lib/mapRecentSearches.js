// Map v6 (note 74): recent Map searches, kept on this device only (never sent anywhere). Shown under the search box
// while it is focused and empty ("never a blank search"). Every storage access is guarded: private windows and
// blocked storage simply mean no recents.
export const MAP_RECENT_KEY = 'banbe_map_recent_searches_v1';
export const MAP_RECENT_MAX = 5;

/** `list` with `query` first: trimmed, case-insensitive duplicates dropped, at most `max`. Blank = unchanged. */
export function addRecentSearch(list, query, max = MAP_RECENT_MAX) {
  const q = String(query ?? '').replace(/\s+/g, ' ').trim();
  const prev = Array.isArray(list) ? list.filter(x => typeof x === 'string' && x.trim()) : [];
  if (!q) return prev.slice(0, max);
  return [q, ...prev.filter(x => x.toLowerCase() !== q.toLowerCase())].slice(0, max);
}

export function loadRecentSearches() {
  try {
    const raw = window.localStorage.getItem(MAP_RECENT_KEY);
    const v = raw ? JSON.parse(raw) : [];
    return addRecentSearch(v, '');
  } catch {
    return [];
  }
}

export function saveRecentSearches(list) {
  try { window.localStorage.setItem(MAP_RECENT_KEY, JSON.stringify(list)); } catch { /* storage blocked: keep in memory only */ }
}

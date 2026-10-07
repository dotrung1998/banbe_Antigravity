// Pure helpers for the signed-in user's own `follows(user_id, organizer_id)` rows.
// RLS (migration 003) is owner-only on every operation, so this list is never readable by
// anyone else; nothing here publishes or shares it. Organizer ids are the only identity used
// (never names), and a followed host that is no longer readable stays in the list as
// "unavailable" so the user can still unfollow it.
import { normalizeSearchText, matchesSearchQuery } from './search.js';

/** Idempotent membership change; returns the same array when nothing changes. */
export function applyFollowChange(ids, organizerId, following) {
  const has = ids.includes(organizerId);
  if (following) return has ? ids : [...ids, organizerId];
  return has ? ids.filter(id => id !== organizerId) : ids;
}

/** follows rows + organizers rows -> display rows, alphabetical by name, unavailable last. */
export function buildFollowedHosts(followRows, organizerRows) {
  const byId = new Map((organizerRows || []).map(o => [o.id, o]));
  const seen = new Set();
  const rows = [];
  for (const f of followRows || []) {
    const id = f.organizer_id;
    if (!id || seen.has(id)) continue;
    seen.add(id);
    const o = byId.get(id);
    rows.push(o
      ? { organizerId: id, name: o.name || '', avatarPath: o.avatar_path || '', avatarR2Ref: o.avatar_r2_ref || '', verified: !!o.verified, available: true }
      : { organizerId: id, name: '', avatarPath: '', avatarR2Ref: '', verified: false, available: false });
  }
  return rows.sort((a, b) => {
    if (a.available !== b.available) return a.available ? -1 : 1;
    return normalizeSearchText(a.name).localeCompare(normalizeSearchText(b.name)) || (a.organizerId < b.organizerId ? -1 : 1);
  });
}

/** Search by host name only (accent/case-insensitive, same matcher as the rest of the app). */
export function filterFollowedHosts(rows, query) {
  const q = String(query || '').trim();
  if (!q) return rows;
  return rows.filter(r => r.available && matchesSearchQuery(normalizeSearchText(r.name), q));
}

/** A write result counts as success when it worked or the row was already in the wanted state. */
export function followWriteOk(error, following) {
  if (!error) return true;
  return following && (error.code === '23505' || /duplicate key/i.test(error.message || ''));
}

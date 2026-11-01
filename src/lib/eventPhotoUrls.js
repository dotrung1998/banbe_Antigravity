// Map v6 (note 74): the photos an event card can page through (src/components/PhotoPager.jsx). Pure, no network:
// BanBeContext.jsx's photoUrlsByEvent runs the ONE batched `event_photos` query and resolves the URLs; these two
// helpers decide which rows and in what order. iOS twin: AppState+Data.swift photoURLsByEvent.

/** At most this many photos per card (cover included): enough to get a feel, light on data (notes 22 / 40). */
export const MAX_CARD_PHOTOS = 6;

/**
 * `event_photos` rows (already ordered by sort_order) → { [event_id]: row[] }, at most `max` per event, keeping
 * that order. `publicOnly` drops private-bucket paths (invite-only events: a signed URL per photo is a network call
 * and discovery never shows them anyway).
 */
export function groupPhotoRows(rows, max = MAX_CARD_PHOTOS, { publicOnly = true } = {}) {
  const out = {};
  for (const r of rows || []) {
    if (!r || r.event_id == null) continue;
    if (!r.storage_path && !r.r2_ref) continue;
    if (publicOnly && String(r.storage_path || '').startsWith('event-photos-private/')) continue;
    const list = out[r.event_id] || (out[r.event_id] = []);
    if (list.length < max) list.push(r);
  }
  return out;
}

/** The card's photo list: the cover first, then the event's photos, duplicates and blanks dropped, at most `max`. */
export function cardPhotoList(cover, urls, max = MAX_CARD_PHOTOS) {
  const out = [];
  const seen = new Set();
  for (const u of [cover, ...(urls || [])]) {
    if (!u) continue;
    const k = photoFileKey(u);
    if (seen.has(k)) continue;
    seen.add(k);
    out.push(u);
    if (out.length >= max) break;
  }
  return out;
}

/**
 * The same photo can come back as different URLs (cover_image vs its event_photos row: Supabase `/object/` vs
 * `/render/image/`, query params). The last two path segments name the file in both Supabase (`<event>/<file>`) and
 * R2 (`<asset>/<variant>`). iOS twin: AppState+Data.swift `gallery(cover:photos:)`.
 */
export function photoFileKey(url) {
  const path = String(url).split(/[?#]/)[0];
  return path.split('/').filter(Boolean).slice(-2).join('/').toLowerCase();
}

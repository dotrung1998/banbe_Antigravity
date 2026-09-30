// Map search matcher (Issue 2 fix, 2026-09-30) — the ONE canonical text
// matcher shared by Map's search box and anything else that needs to
// decide "does this event match this free-text query." Mirrored on iOS by
// `Lib/Search.swift` — keep both in lockstep, same normalization rules,
// same AND-token semantics, same category-alias dictionary.
//
// Root cause this fixes: MapExplore.jsx's search box used to match only
// `name`/`area`/`keywords` — never the event's own category label/key —
// while the category chip filters by `cat_key` equality directly. Typing
// a genuine substring of a category name (e.g. "Supp" for "Supper Club")
// could therefore return FEWER events than clearing the query and tapping
// that category's chip, whenever an event's `keywords` column was empty
// (migration 108's backfill only fills a blank array; it's not guaranteed
// non-empty for every row going forward, and older/edge-case rows can
// still have '{}'). Building one search "document" per event that always
// includes the category (independent of whether keywords happen to be
// populated) closes that gap structurally, not just for today's data.

// Vietnamese diacritics + đ/Đ -> plain ASCII, case-folded, whitespace
// collapsed. `String.normalize('NFD')` decomposes accented Latin letters
// into base letter + combining marks, which the following regex strips;
// đ/Đ don't decompose that way (they're their own code points), so they're
// handled as an explicit extra replace.
export function normalizeSearchText(value) {
  if (value == null) return '';
  return String(value)
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/đ/g, 'd')
    .replace(/Đ/g, 'd')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

// Derived from Home.jsx's own `FILTER_DEFS` (the single source of truth
// for the four real category keys this app has) plus a couple of honest
// Vietnamese synonyms per category — never invented categories that don't
// exist in the schema. Bilingual on purpose: a Vietnamese-speaking user
// typing "tiệc tối" for a Supper Club event must match it exactly like an
// English speaker typing "supper."
export const CATEGORY_SEARCH_ALIASES = {
  all: [],
  supper: ['supper club', 'supper', 'tiec toi', 'tiec', 'dinner'],
  fashion: ['thoi trang', 'fashion', 'thời trang'],
  gallery: ['phong tranh', 'gallery', 'trien lam', 'triển lãm', 'art'],
  music: ['nhac', 'music', 'am nhac', 'âm nhạc', 'concert'],
};

// Builds ONE normalized search document per event. Category/name coverage
// never depends on `keywords` being populated — it's always included from
// `catKey`/`catLabel` directly; `keywords` only ever SUPPLEMENTS this, it
// never replaces it (a blank/null/whitespace-only keywords array changes
// nothing about whether name/category/area/organizer text matches).
export function buildEventSearchDoc(event) {
  if (!event) return '';
  const catAliases = CATEGORY_SEARCH_ALIASES[event.catKey] || [];
  const keywordList = Array.isArray(event.keywords) ? event.keywords : [];
  const parts = [
    event.name,
    event.catLabel,
    event.catKey,
    ...catAliases,
    event.area,
    event.city,
    event.organizerName,
    event.description,
    event.intro,
    ...keywordList,
  ].filter((p) => p != null && String(p).trim() !== '');
  return normalizeSearchText(parts.join(' '));
}

// AND semantics across whitespace-separated tokens (matches this app's
// pre-existing single-field `.includes()` behavior extended to multiple
// terms — checked against MapExplore.jsx's prior single-string `q` usage,
// which never had a documented multi-word rule of its own to preserve).
// Substring/prefix matching per token, not exact-word — "supp" must match
// inside "supper club".
export function matchesSearchQuery(doc, rawQuery) {
  const q = normalizeSearchText(rawQuery);
  if (!q) return true;
  const tokens = q.split(' ').filter(Boolean);
  if (!tokens.length) return true;
  return tokens.every((t) => doc.includes(t));
}

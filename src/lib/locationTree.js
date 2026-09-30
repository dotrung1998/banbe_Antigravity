// Location hierarchy (2026-09-30, migration 112) — the ONE data-driven
// "where is this event" model shared by Home's feed, Home's weekend strip,
// the area picker sheet (AreaSheet.jsx) and MapExplore.jsx's list/pins.
// Replaces the old hardcoded `AREAS` table (6 fixed keys with hand-rolled
// `e.meta.includes('Quận 1')` predicates) and Home's second, duplicated
// `AREA_DISTRICT_MATCH` table for the weekend strip.
//
// Built from REAL event fields only (never a hand-authored geography DB):
//   country_code  -> root        (VN / US always shown, even with 0 events)
//   state_province -> state node (only when the row actually has one)
//   VN: area       -> LEGACY "familiar area" group (the event's own raw
//                     `area` string, e.g. "Bình Thạnh" — labeled as legacy,
//                     never presented as a current official admin unit)
//   US: city       -> city node
//   neighborhood   -> leaf
// A level the row has no value for is simply skipped (no invented nesting):
// an HCMC row with no state_province hangs its legacy area directly under
// the Vietnam root.
//
// Node IDs are deterministic composite keys built from RAW values
// ("loc:VN|s:Tỉnh Lâm Đồng|a:Da Lat|n:Phường 1") — never a translated
// display label, never an array index — so a selection survives language
// switches, re-sorts and data refreshes.
//
// Counting/matching follows src/lib/badges.js's convention: dedupe by
// DISTINCT event id, never re-sum already-aggregated child counts. A parent
// node's count is the size of the Set of event ids whose own path passes
// through it, not the sum of its children's counts.
import { normalizeSearchText, matchesSearchQuery } from './search.js';

export const LOCATION_ALL = 'all';
const UNKNOWN_COUNTRY = '_';

export const COUNTRY_LABELS = {
  VN: { vi: 'Việt Nam', en: 'Vietnam' },
  US: { vi: 'Hoa Kỳ', en: 'United States' },
  [UNKNOWN_COUNTRY]: { vi: 'Chưa rõ quốc gia', en: 'Country not set' },
};
// Always shown, in this order, even when zero events exist there (honest
// empty state — never a fake seed event).
export const ALWAYS_SHOWN_COUNTRIES = ['VN', 'US'];

function clean(v) {
  if (v == null) return '';
  return String(v).replace(/\s+/g, ' ').trim();
}
// Only the two characters the ID grammar itself uses are escaped; every
// other character (Vietnamese diacritics included) stays readable.
function esc(v) {
  return v.replace(/%/g, '%25').replace(/\|/g, '%7C');
}
function unesc(v) {
  return v.replace(/%7C/g, '|').replace(/%25/g, '%');
}

/**
 * Reads the raw location fields off any of this app's event shapes:
 * shapeRealEvent() rows (`area`, `countryCode`, …), Home's discovery cards,
 * MapExplore's own rows, and the static demo catalogue (data/events.js —
 * `locationLabel` is its raw district, `countryCode: 'VN'` is set there
 * since that whole catalogue is HCMC-only by its own definition).
 */
export function eventLocationFields(e) {
  if (!e) return { countryCode: '', stateProvince: '', area: '', city: '', neighborhood: '' };
  return {
    countryCode: clean(e.countryCode).toUpperCase().slice(0, 2),
    stateProvince: clean(e.stateProvince),
    area: clean(e.locationLabel ?? e.area),
    city: clean(e.city),
    neighborhood: clean(e.neighborhood),
  };
}

/**
 * Root -> leaf path of { id, kind, value, legacy } segments for one event.
 * Deterministic from raw values; used both to BUILD the tree and to MATCH an
 * event against a selected node (a node matches an event iff it's on the
 * event's own path — which is exactly "itself + descendants").
 */
export function eventLocationPath(e) {
  const f = eventLocationFields(e);
  const cc = f.countryCode || UNKNOWN_COUNTRY;
  const segs = [];
  let id = 'loc:' + esc(cc);
  segs.push({ id, kind: 'country', value: cc, legacy: false });
  const push = (tag, kind, value, legacy = false) => {
    id = `${id}|${tag}:${esc(value)}`;
    segs.push({ id, kind, value, legacy });
  };
  if (f.stateProvince) push('s', 'state', f.stateProvince);
  if (cc === 'US') {
    if (f.city) push('c', 'city', f.city);
  } else if (f.area) {
    // VN (and the "country not set" bucket, whose area strings are this
    // app's own legacy VN district labels): the raw `area` string as a
    // legacy familiar-area group.
    push('a', 'area', f.area, true);
  }
  if (f.neighborhood) {
    const parentValue = segs[segs.length - 1].value;
    // Don't emit a leaf that just repeats its own parent's name.
    if (normalizeSearchText(f.neighborhood) !== normalizeSearchText(parentValue)) push('n', 'neighborhood', f.neighborhood);
  }
  return segs;
}

export function eventLocationIds(e) {
  return eventLocationPath(e).map(s => s.id);
}

/** THE shared "does this event match the selected node (or its descendants)" check. */
export function eventMatchesLocation(e, nodeId) {
  if (!nodeId || nodeId === LOCATION_ALL) return true;
  return eventLocationIds(e).includes(nodeId);
}

/** Parses a node id back into its segments — lets a label render even for a selection not present in the current tree. */
export function parseLocationId(nodeId) {
  if (!nodeId || nodeId === LOCATION_ALL || !nodeId.startsWith('loc:')) return [];
  const parts = nodeId.slice(4).split('|');
  const kinds = { s: 'state', a: 'area', c: 'city', n: 'neighborhood' };
  const segs = [];
  let id = 'loc:' + parts[0];
  segs.push({ id, kind: 'country', value: unesc(parts[0]), legacy: false });
  for (const p of parts.slice(1)) {
    const i = p.indexOf(':');
    if (i < 0) continue;
    const tag = p.slice(0, i);
    id = `${id}|${p}`;
    segs.push({ id, kind: kinds[tag] || 'other', value: unesc(p.slice(i + 1)), legacy: tag === 'a' });
  }
  return segs;
}

export function countryLabel(code, lang = 'vi') {
  const known = COUNTRY_LABELS[code];
  if (known) return lang === 'en' ? known.en : known.vi;
  try {
    return new Intl.DisplayNames([lang], { type: 'region' }).of(code) || code;
  } catch {
    return code;
  }
}

function segLabel(seg, lang) {
  return seg.kind === 'country' ? countryLabel(seg.value, lang) : seg.value;
}

/** Short header label: the node + its immediate parent ("Bình Thạnh, Việt Nam", "Phường 1, Da Lat") — never a full breadcrumb. */
export function locationShortLabel(nodeId, lang = 'vi') {
  const segs = parseLocationId(nodeId);
  if (!segs.length) return lang === 'en' ? 'All areas' : 'Tất cả khu vực';
  const last = segs[segs.length - 1];
  const parent = segs[segs.length - 2];
  return parent ? `${segLabel(last, lang)}, ${segLabel(parent, lang)}` : segLabel(last, lang);
}

/**
 * Builds the tree from whatever event list is currently loaded.
 * Returns { roots, byId } — `byId` maps node id -> node; each node is
 * { id, kind, value, legacy, depth, parentId, children, count, eventIds }.
 * `count` === eventIds.size (distinct event ids, never a sum of children).
 */
export function buildLocationTree(events, { alwaysShown = ALWAYS_SHOWN_COUNTRIES } = {}) {
  const byId = new Map();
  const roots = [];
  const ensure = (seg, depth, parent) => {
    let node = byId.get(seg.id);
    if (!node) {
      node = { id: seg.id, kind: seg.kind, value: seg.value, legacy: seg.legacy, depth, parentId: parent ? parent.id : null, children: [], eventIds: new Set(), count: 0 };
      byId.set(seg.id, node);
      if (parent) parent.children.push(node); else roots.push(node);
    }
    return node;
  };
  for (const cc of alwaysShown) ensure({ id: 'loc:' + esc(cc), kind: 'country', value: cc, legacy: false }, 0, null);
  for (const e of events || []) {
    const eid = e?.key ?? e?.id;
    if (eid == null) continue;
    let parent = null;
    eventLocationPath(e).forEach((seg, depth) => {
      const node = ensure(seg, depth, parent);
      node.eventIds.add(eid);
      parent = node;
    });
  }
  const pinned = new Map(alwaysShown.map((cc, i) => ['loc:' + esc(cc), i]));
  const sortRec = (list, isRoot) => {
    list.sort((a, b) => {
      if (isRoot) {
        const pa = pinned.has(a.id) ? pinned.get(a.id) : 99;
        const pb = pinned.has(b.id) ? pinned.get(b.id) : 99;
        if (pa !== pb) return pa - pb;
      }
      return (b.eventIds.size - a.eventIds.size) || a.value.localeCompare(b.value, 'vi');
    });
    for (const n of list) { n.count = n.eventIds.size; sortRec(n.children, false); }
  };
  sortRec(roots, true);
  return { roots, byId };
}

export function locationAncestorIds(tree, nodeId) {
  const out = [];
  let n = tree.byId.get(nodeId);
  while (n && n.parentId) { out.unshift(n.parentId); n = tree.byId.get(n.parentId); }
  return out;
}

/**
 * Flat search index, built ONCE per tree (not per keystroke). Each entry's
 * doc covers the raw value plus both-language labels, normalized through
 * search.js's own normalizeSearchText (accent/đ-insensitive).
 */
export function buildLocationSearchIndex(tree) {
  const entries = [];
  for (const node of tree.byId.values()) {
    const texts = [node.value];
    if (node.kind === 'country') texts.push(countryLabel(node.value, 'vi'), countryLabel(node.value, 'en'));
    entries.push({ id: node.id, doc: normalizeSearchText(texts.join(' ')) });
  }
  return entries;
}

/**
 * Query -> { matchIds, visibleIds, revealIds }:
 *   matchIds   nodes whose own text matches
 *   visibleIds matches + all their ancestors (what the filtered list shows)
 *   revealIds  ancestors that must be expanded to reveal the matches —
 *              OR-ed with the user's manual expand set at render time, never
 *              written into it, so clearing the query restores the manual
 *              state exactly.
 * Returns null for an empty query.
 */
export function searchLocationTree(tree, index, rawQuery) {
  if (!normalizeSearchText(rawQuery)) return null;
  const matchIds = new Set();
  const visibleIds = new Set();
  const revealIds = new Set();
  for (const entry of index) {
    if (!matchesSearchQuery(entry.doc, rawQuery)) continue;
    matchIds.add(entry.id);
    visibleIds.add(entry.id);
    for (const a of locationAncestorIds(tree, entry.id)) { visibleIds.add(a); revealIds.add(a); }
  }
  return { matchIds, visibleIds, revealIds };
}

/**
 * Legacy-key migration — the old hardcoded AREAS keys -> the equivalent new
 * node id. Never throws, never silently resets a real old pick to "all":
 *   q1/thaodien/binhthanh -> that district's legacy familiar-area node
 *   other ("Quận khác", everything outside those three) -> the Vietnam root
 *     (its closest honest superset — there's no "all except X" node)
 *   danang (was a "coming soon" placeholder that matched nothing) -> a
 *     legacy "Đà Nẵng" node, which honestly matches only events whose own
 *     area says Đà Nẵng (none today)
 * Already-new ids pass through unchanged; anything unrecognized -> 'all'.
 */
export const LEGACY_AREA_KEY_MAP = {
  all: LOCATION_ALL,
  q1: 'loc:VN|a:Quận 1',
  thaodien: 'loc:VN|a:Thảo Điền',
  binhthanh: 'loc:VN|a:Bình Thạnh',
  other: 'loc:VN',
  danang: 'loc:VN|a:Đà Nẵng',
};
export function migrateLegacyAreaKey(key) {
  if (key == null || key === '') return LOCATION_ALL;
  const k = String(key);
  if (k === LOCATION_ALL || k.startsWith('loc:')) return k;
  return Object.prototype.hasOwnProperty.call(LEGACY_AREA_KEY_MAP, k) ? LEGACY_AREA_KEY_MAP[k] : LOCATION_ALL;
}

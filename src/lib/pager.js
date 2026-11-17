// Paged lists (v2.3, note 81): the Home Shortlist and every Browse by type / See all list show four large rows a
// page at least, and more when the screen has room below the list (owner 2026-11-17: the empty band under the pager
// became rows instead of a gap). Pure helpers so the component, the unit tests and iOS read the same rules.

export const PAGE_SIZE = 4;
/** Tallest page: past this a page stops reading as one screen and the pager is lost below the fold. */
export const MAX_PAGE_SIZE = 8;
/** The arrows, page numbers and "5–8 of 18" line under the track (44 px numbers + padding + range), with 4 px air. */
export const PAGER_NAV_HEIGHT = 71;

/**
 * How many rows fit below the list's top edge, so the rows AND the pager are on screen without scrolling.
 * `available` is the height from the list's top to the bottom of the scrolling viewport. Never fewer than the
 * classic four and never more than MAX_PAGE_SIZE, so a short trade-show phone keeps its old pages and a very tall
 * window cannot turn the list into a wall.
 */
export function fittedPageSize({ available, rowHeight = 92, nav = PAGER_NAV_HEIGHT, min = PAGE_SIZE, max = MAX_PAGE_SIZE } = {}) {
  if (!Number.isFinite(available) || available <= 0 || !(rowHeight > 0)) return min;
  const fits = Math.floor((available - nav) / rowHeight);
  return Math.max(min, Math.min(max, fits));
}

/** Split a list into pages of `size`. An empty list has no pages. */
export function paginate(list, size = PAGE_SIZE) {
  const out = [];
  for (let i = 0; i < (list?.length || 0); i += size) out.push(list.slice(i, i + size));
  return out;
}

/** Clamp a page index into range (0 when there are no pages). */
export const clampPage = (i, pageCount) => Math.max(0, Math.min(Math.max(0, pageCount - 1), Number.isFinite(i) ? Math.round(i) : 0));

/**
 * Where you are: first and last row number on page `i` and the total. `text` is "5–8 of 18" (or "9 of 9" for a
 * single row) in the chosen language. Ranges keep their en dash (the copy rule allows ranges).
 */
export function pageRange(pages, i, lang = 'en') {
  const total = pages.reduce((n, p) => n + p.length, 0);
  if (!pages.length) return { first: 0, last: 0, total: 0, text: '' };
  const idx = clampPage(i, pages.length);
  const first = idx * (pages[0]?.length || PAGE_SIZE) + 1;
  const last = first + pages[idx].length - 1;
  const span = first === last ? `${first}` : `${first}–${last}`;
  return { first, last, total, text: lang === 'vi' ? `${span} trên ${total}` : `${span} of ${total}` };
}

/**
 * The end card fills the hole a short last page leaves, sized to the missing rows so the page never jumps.
 * room = rows missing on the last page. variant: 'slim' (one row of room: one line, one action), 'mid' (two rows),
 * 'fill' (three rows), or 'solo' when the whole list is a single short page (the card sits under the rows at its
 * natural height). null = no card (the last page is full, or the list is empty).
 */
export function endCardRoom(pages, size = PAGE_SIZE) {
  if (!pages.length) return { room: 0, variant: null };
  const room = size - pages[pages.length - 1].length;
  if (room <= 0) return { room: 0, variant: null };
  if (pages.length === 1) return { room, variant: 'solo' };
  return { room, variant: room === 1 ? 'slim' : room === 2 ? 'mid' : 'fill' };
}

/**
 * Which page numbers to draw: at most `max` consecutive numbers that always contain the current page, so long lists
 * (8 pages of For You) keep the arrows on screen at phone width. Returns 0-based page indexes.
 */
export function pageWindow(page, pageCount, max = 5) {
  if (pageCount <= max) return Array.from({ length: pageCount }, (_, i) => i);
  const start = Math.max(0, Math.min(pageCount - max, clampPage(page, pageCount) - Math.floor(max / 2)));
  return Array.from({ length: max }, (_, i) => start + i);
}

/** Page navigation shows only when there is more than one page (a one-page tab like Tonight shows none). */
export const showPageNav = pages => pages.length > 1;

/**
 * The drop under the page numbers follows the swipe. `progress` is the track's position in pages (1.5 = halfway from
 * the second page to the third), `first` the first page number shown, `count` how many are shown. Returns the drop's
 * two edges in cells from the first number: at rest both sit on the open page; between pages the leading edge eases
 * out (runs ahead) and the trailing edge eases in (lags), so the drop is longest mid-swipe. `still` (Reduced motion):
 * no stretch, the drop steps from number to number. iOS twin: PagerDropRules.edges.
 */
export function dropEdges(progress, first, count, still = false) {
  if (count <= 0) return { trail: 0, lead: 0 };
  const rel = Math.min(Math.max((Number.isFinite(progress) ? progress : 0) - first, 0), count - 1);
  if (still) { const r = Math.round(rel); return { trail: r, lead: r }; }
  const base = Math.floor(rel), f = rel - base;
  return { trail: base + f * f, lead: base + 1 - (1 - f) * (1 - f) };
}

/** The page nearest to a scroll position (the track, not our intentions, decides). */
export const pageAt = (scrollLeft, pageWidth, pageCount) => (pageWidth > 0 ? clampPage(scrollLeft / pageWidth, pageCount) : 0);

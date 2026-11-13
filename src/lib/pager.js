// Paged lists (v2.3, note 81): the Home Shortlist and every Browse by type / See all list show four large rows a
// page, swiped on their own track, with page numbers and a "1–4 of 8" line. Pure helpers so the component, the
// unit tests and (later) iOS read the same rules.

export const PAGE_SIZE = 4;

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
 * The ink under the page numbers stretches from the old number across to the new one, then settles there.
 * Given the old and new number boxes ({left, width}), returns the three keyframes [from, stretched, to].
 */
export function inkFrames(from, to) {
  const lo = Math.min(from.left, to.left);
  const hi = Math.max(from.left + from.width, to.left + to.width);
  return [{ left: from.left, width: from.width }, { left: lo, width: hi - lo }, { left: to.left, width: to.width }];
}

/** The page nearest to a scroll position (the track, not our intentions, decides). */
export const pageAt = (scrollLeft, pageWidth, pageCount) => (pageWidth > 0 ? clampPage(scrollLeft / pageWidth, pageCount) : 0);

// Pure layout math for Web Map Explore (src/screens/MapExplore.jsx). All numbers are px
// relative to the screen's own box (a fixed layer; on desktop the phone frame).
// Visible map = [topControlsBottom + gap, sheetTop - attribution strip]; the selected-event
// card sits at the bottom of that region and hides when the region is too short for it.

export const SHEET_SNAPS = { tall: 0.30, mid: 0.58, peek: 0.86 }; // fraction of height left for the map above the sheet
export const CARD_GAP = 12;
export const ATTRIB_RESERVE = 26; // strip above the sheet kept free for the required map attribution
export const PIN_ZONE = 70;       // minimum map height left for the selected pin above the card
export const SNAP_ORDER = ['tall', 'mid', 'peek'];

export function computeMapLayout({ containerH, topControlsBottom, cardHeight, stripFraction }) {
  const sheetTopPx = stripFraction * containerH;
  const visibleTop = topControlsBottom + CARD_GAP;
  const visibleBottom = sheetTopPx - ATTRIB_RESERVE;
  const cardFits = visibleBottom - visibleTop >= cardHeight + 8;
  const cardBottomPx = Math.max(0, containerH - visibleBottom);
  // Camera padding keeps the selected pin in the visible region above the card.
  const top = Math.max(0, visibleTop);
  let bottom = Math.max(0, containerH - visibleBottom + cardHeight + CARD_GAP);
  const room = containerH - 90; // never let padding swallow the viewport
  if (top + bottom > room) bottom = Math.max(0, room - top);
  return { sheetTopPx, visibleTop, visibleBottom, cardFits, cardBottomPx, cameraPadding: { top, bottom, left: 30, right: 30 } };
}

export const snapFits = (snap, { containerH, topControlsBottom, cardHeight }) =>
  SHEET_SNAPS[snap] * containerH - ATTRIB_RESERVE - (topControlsBottom + CARD_GAP) >= cardHeight + PIN_ZONE;

/** The snap to use so a selection has room: keep `current` if it fits, else step down tall -> mid -> peek. */
export function snapForSelection(current, dims) {
  if (snapFits(current, dims)) return current;
  const next = SNAP_ORDER.slice(SNAP_ORDER.indexOf(current) + 1).find(s => snapFits(s, dims));
  return next || 'peek';
}

// Pure layout math for Web Map Explore (src/screens/MapExplore.jsx). All numbers are px
// relative to the screen's own box (a fixed layer; on desktop the phone frame).
// Map E+ (note 79): the map is full screen. Visible map = [topControlsBottom + gap, top of the bottom stack - attribution
// strip], where the bottom stack is the dock and the buttons above it. The list and the area panel float over the map
// and never change this, so opening them never changes the results.
export const CARD_GAP = 12;
export const ATTRIB_RESERVE = 26; // strip above the bottom stack kept free for the required map attribution

/** The bottom stack's top edge as a fraction of the screen height (what `computeMapLayout` calls `stripFraction`). */
export function bottomStackFraction(containerH, stackPx) {
  if (!(containerH > 0)) return 0.8;
  return Math.min(0.98, Math.max(0.5, 1 - stackPx / containerH));
}

export function computeMapLayout({ containerH, topControlsBottom, stripFraction }) {
  const sheetTopPx = stripFraction * containerH;
  const visibleTop = topControlsBottom + CARD_GAP;
  const visibleBottom = sheetTopPx - ATTRIB_RESERVE;
  // Camera padding keeps a flown-to pin in the visible region between the controls and the bottom stack.
  const top = Math.max(0, visibleTop);
  let bottom = Math.max(0, containerH - visibleBottom + CARD_GAP);
  const room = containerH - 90; // never let padding swallow the viewport
  if (top + bottom > room) bottom = Math.max(0, room - top);
  return { sheetTopPx, visibleTop, visibleBottom, cameraPadding: { top, bottom, left: 30, right: 30 } };
}

// ---- Map E+ (note 79): dimming, the list pull, the dock --------------------------------------------------------------

/** How the time window dims what is outside it. Opacity / scale are 0 to 1; the same numbers on iOS (MapLayout.swift). */
export const MAP_DIM = { pinOpacity: 0.3, pinScale: 0.88, rowOpacity: 0.42, chipOpacity: 0.5, zeroBubble: 0.5, rangeOff: 0.32 };

/** Pulling the list down to return to the map. Distances in px, speed in px per ms. */
export const LIST_PULL = { closePx: 110, flickPxPerMs: 0.6, flickMinPx: 50, veilPx: 130, slopPx: 6 };

/** 'close' for a long pull (or a fast one after `flickMinPx`), else 'back' (the list springs back). */
export function pullOutcome(dy, velocityPxPerMs = 0) {
  return dy > LIST_PULL.closePx || (velocityPxPerMs > LIST_PULL.flickPxPerMs && dy > LIST_PULL.flickMinPx) ? 'close' : 'back';
}
/** Opacity of the veil over the strip above the list while it is pulled `dy` px: 1 at rest, 0 at `veilPx`. */
export const veilOpacity = (dy) => Math.max(0, 1 - dy / LIST_PULL.veilPx);

/** The dock shows except while the area panel is open (the list and the map keep a bottom clearance for it). */
export const dockVisible = (panelOpen) => !panelOpen;

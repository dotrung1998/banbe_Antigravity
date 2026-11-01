// Pure layout math for Web Map Explore (src/screens/MapExplore.jsx). All numbers are px
// relative to the screen's own box (a fixed layer; on desktop the phone frame).
// Visible map = [topControlsBottom + gap, sheetTop - attribution strip]. Map v5 (note 73): the selected event lives
// inside the sheet (no floating card over the map), so the camera only pads for the controls and the sheet.

// Fraction of the height left for the map above the sheet. Peek is tall enough for the count line, the active
// filter summary and (Map v6, note 74) the search button + quick chips row. Tall is FULL height: its real value is
// measured (`tallFraction`: just under the Close / compass row); 0.11 is only the fallback before that is known.
// Sheet TOP as a fraction of the screen. Owner 2026-11-01: mid covers about two thirds, full covers the whole screen
// (no map sliver above it; the back arrow and "Show map" move into the sheet's search row there).
export const SHEET_SNAPS = { tall: 0, mid: 0.34, peek: 0.80 };
export const TALL_GAP = 8; // px between the top controls and the full-height sheet
export const CARD_GAP = 12;
export const ATTRIB_RESERVE = 26; // strip above the sheet kept free for the required map attribution
export const SNAP_ORDER = ['tall', 'mid', 'peek'];

export function computeMapLayout({ containerH, topControlsBottom, stripFraction }) {
  const sheetTopPx = stripFraction * containerH;
  const visibleTop = topControlsBottom + CARD_GAP;
  const visibleBottom = sheetTopPx - ATTRIB_RESERVE;
  // Camera padding keeps a selected pin in the visible region between the controls and the sheet.
  const top = Math.max(0, visibleTop);
  let bottom = Math.max(0, containerH - visibleBottom + CARD_GAP);
  const room = containerH - 90; // never let padding swallow the viewport
  if (top + bottom > room) bottom = Math.max(0, room - top);
  return { sheetTopPx, visibleTop, visibleBottom, cameraPadding: { top, bottom, left: 30, right: 30 } };
}

/** Selecting an event shows it at the top of the sheet's list: always mid (room for the map AND the row). */
export const snapAfterSelect = () => 'mid';

/** The user's own pan/zoom drops the list from mid to peek (Airbnb); tall stays tall (the user chose a list). */
export const snapAfterUserPan = (current) => (current === 'mid' ? 'peek' : current);

/** The dock shows only at tall; at peek and mid the map and the sheet get the whole width (owner, 2026-11-01). */
export const dockShown = (snap) => snap === 'tall';

/** Map v6 (note 74): the full-height sheet's top, as a fraction: just under the measured top controls (+ TALL_GAP). */
export function tallFraction(containerH, topControlsBottom) {
  // Full height is the whole screen now (owner 2026-11-01), whatever the top controls measure.
  void containerH; void topControlsBottom;
  return SHEET_SNAPS.tall;
}

// The peek strip (count line + filter summary + search/chips row) needs about this many px; a short screen lowers
// the peek fraction so the strip is never cut off (iPhone SE: 0.775 instead of 0.80).
export const PEEK_MIN_PX = 150;
export function peekFraction(containerH) {
  if (!(containerH > 0)) return SHEET_SNAPS.peek;
  return Math.max(SHEET_SNAPS.mid + 0.05, Math.min(SHEET_SNAPS.peek, 1 - PEEK_MIN_PX / containerH));
}

/** Every snap's fraction for this screen (tall measured, peek fitted to the strip, mid fixed). */
export function snapFractions(containerH, topControlsBottom) {
  return { ...SHEET_SNAPS, tall: tallFraction(containerH, topControlsBottom), peek: peekFraction(containerH) };
}

export const PEEK_PULL_PX = 40; // an upward drag from peek longer than this goes straight to full height
export const FLICK_PX_PER_MS = 0.5; // an upward release faster than this is a flick

/**
 * Where the sheet lands after a handle drag of `deltaPx` (negative = up) that started at `startSnap`.
 * Map v6 (note 74): from peek, an upward pull past PEEK_PULL_PX or an upward flick goes straight to full height
 * (owner: "pulling up should go to the top, not stop at mid"). Otherwise the snap nearest to where it was released.
 * `velocityPxPerMs` is the release speed (negative = up).
 */
export function snapAfterDrag(startSnap, deltaPx, containerH, velocityPxPerMs = 0, fractions = SHEET_SNAPS) {
  if (startSnap === 'peek' && (deltaPx < -PEEK_PULL_PX || velocityPxPerMs < -FLICK_PX_PER_MS)) return 'tall';
  const released = (fractions[startSnap] ?? SHEET_SNAPS[startSnap]) + (containerH > 0 ? deltaPx / containerH : 0);
  let best = startSnap in fractions ? startSnap : 'mid';
  for (const key of SNAP_ORDER) {
    if (Math.abs(fractions[key] - released) < Math.abs(fractions[best] - released)) best = key;
  }
  return best;
}

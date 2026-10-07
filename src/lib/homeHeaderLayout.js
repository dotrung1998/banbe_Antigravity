// Width budget for Home's header row: wordmark + "Home" title on the left; on the right one
// capsule holding two separate buttons (streak, coins) next to the Search circle. Every control
// keeps a >= 44 pt touch target. iOS uses ViewThatFits (drops the title first); web measures the row with a
// ResizeObserver and applies the same rule (`titleFits`). Numbers are conservative estimates, not measurements.
export const HEADER = {
  sidePad: 20,         // page gutter, each side
  wordmark: 80,        // shrunk from 96 only while the shortcuts are shown
  wordmarkGap: 8,
  title: 78,           // "Home"/"Nhà" at 27px, generous
  btnPad: 8,           // horizontal padding inside each capsule button
  icon: 16,
  iconGap: 4,
  digit: 8.5,          // tabular 13px digit, generous
  divider: 1,
  groupGap: 6,         // capsule <-> search
  search: 44,
  minTouch: 44,
};
const btnWidth = (chars) => Math.max(HEADER.minTouch, HEADER.btnPad * 2 + HEADER.icon + HEADER.iconGap + chars * HEADER.digit);

/** Estimated total content width of the header row. */
export function estimateHeaderWidth({ streakChars = 1, coinChars = 3, showTitle = true, showShortcuts = true } = {}) {
  const left = HEADER.wordmark + (showTitle ? HEADER.wordmarkGap + HEADER.title : 0);
  const right = (showShortcuts ? btnWidth(streakChars) + HEADER.divider + btnWidth(coinChars) + HEADER.groupGap : 0) + HEADER.search;
  return HEADER.sidePad * 2 + left + right;
}

/** The title is the first thing dropped: shown only when the whole row (with it) still fits. */
export const titleFits = (viewport, opts = {}) => estimateHeaderWidth({ ...opts, showTitle: true }) <= viewport;
export const headerFits = (viewport, opts = {}) => estimateHeaderWidth({ ...opts, showTitle: titleFits(viewport, opts) }) <= viewport;
export const buttonWidth = btnWidth;

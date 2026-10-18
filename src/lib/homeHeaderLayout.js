// Width budget for Home's header row: wordmark + "Home" title on the left; on the right one
// capsule holding two separate buttons (streak, coins) next to the Notifications bell and Search circles (the bell
// moved here when Schedule took Notifications' dock slot — note 44 web parity). Every control
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
  bell: 44,
  minTouch: 44,
};
const btnWidth = (chars) => Math.max(HEADER.minTouch, HEADER.btnPad * 2 + HEADER.icon + HEADER.iconGap + chars * HEADER.digit);

/** Estimated total content width of the header row. */
export function estimateHeaderWidth({ streakChars = 1, coinChars = 3, showTitle = true, showShortcuts = true, showBell = true, wordmark = HEADER.wordmark } = {}) {
  const left = wordmark + (wordmark && showTitle ? HEADER.wordmarkGap : 0) + (showTitle ? HEADER.title : 0);
  const right = (showShortcuts ? btnWidth(streakChars) + HEADER.divider + btnWidth(coinChars) + HEADER.groupGap : 0)
    + (showBell ? HEADER.bell + HEADER.groupGap : 0) + HEADER.search;
  return HEADER.sidePad * 2 + left + right;
}

/** Wordmark sizes tried, largest first (iOS note 45 steps it down before giving anything else up). */
export const WORDMARK_STEPS = [HEADER.wordmark, 70, 58];

/**
 * { wordmark, showTitle }: keep the title with the largest wordmark that fits; else drop the title (largest wordmark
 * that fits); last resort, no wordmark. Every control always keeps its 44px target.
 */
export function headerLayout(viewport, opts = {}) {
  for (const wordmark of WORDMARK_STEPS) if (estimateHeaderWidth({ ...opts, wordmark, showTitle: true }) <= viewport) return { wordmark, showTitle: true };
  for (const wordmark of WORDMARK_STEPS) if (estimateHeaderWidth({ ...opts, wordmark, showTitle: false }) <= viewport) return { wordmark, showTitle: false };
  return { wordmark: 0, showTitle: false };
}

/** The title is dropped only after the wordmark has shrunk as far as it goes. */
export const titleFits = (viewport, opts = {}) => headerLayout(viewport, opts).showTitle;
export const headerFits = (viewport, opts = {}) => estimateHeaderWidth({ ...opts, ...headerLayout(viewport, opts) }) <= viewport;
export const buttonWidth = btnWidth;

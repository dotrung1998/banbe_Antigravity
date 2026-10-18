// Width budget for Home's header row: wordmark + "Home" title on the left; on the right one
// capsule holding two separate buttons (streak, coins) next to the Notifications bell and Search circles (the bell
// moved here when Schedule took Notifications' dock slot — note 44 web parity). Every control
// keeps a >= 44 pt touch target. iOS uses ViewThatFits (drops the title first); web measures the row with a
// ResizeObserver and applies the same rule (`titleFits`). Numbers are conservative estimates, not measurements.
// 2026-10-18: the wordmark is 96 like every other screen (Account, Notifications, Schedule); the controls were
// made smaller (36px circles, 38px capsule) to make room. Each control still has a 44px TAP area — the extra is an
// invisible hit slop (padding + equal negative margin, HEADER.hitSlop) that takes no layout width.
export const HEADER = {
  sidePad: 20,         // page gutter, each side
  wordmark: 96,        // same as the other screens; steps down only on narrow phones
  wordmarkGap: 8,
  title: 72,           // "Home"/"Nhà" at 27px
  btnPad: 6,           // horizontal padding inside each capsule button
  icon: 14,
  iconGap: 4,
  digit: 7.5,          // tabular 12.5px digit, generous
  divider: 1,
  groupGap: 5,         // between header controls
  search: 36,          // visual circle
  bell: 36,
  capsule: 38,         // visual height (and minimum width) of the streak / coins capsule buttons
  minTouch: 44,        // tap area each control keeps, via hitSlop
};
/** Invisible extra tap area around a control of visual size `size`, so the tap target is >= minTouch. */
export const hitSlop = (size) => Math.max(0, Math.ceil((HEADER.minTouch - size) / 2));
const btnWidth = (chars) => Math.max(HEADER.capsule, HEADER.btnPad * 2 + HEADER.icon + HEADER.iconGap + chars * HEADER.digit);

/** Estimated total content width of the header row. */
export function estimateHeaderWidth({ streakChars = 1, coinChars = 3, showTitle = true, showShortcuts = true, showBell = true, wordmark = HEADER.wordmark } = {}) {
  const left = wordmark + (wordmark && showTitle ? HEADER.wordmarkGap : 0) + (showTitle ? HEADER.title : 0);
  const right = (showShortcuts ? btnWidth(streakChars) + HEADER.divider + btnWidth(coinChars) + HEADER.groupGap : 0)
    + (showBell ? HEADER.bell + HEADER.groupGap : 0) + HEADER.search;
  return HEADER.sidePad * 2 + left + right;
}

/** Wordmark sizes tried, largest first (iOS note 45 steps it down before giving anything else up). */
export const WORDMARK_STEPS = [HEADER.wordmark, 80, 70];

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

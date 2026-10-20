// Keeps the field being typed in visible above the on-screen keyboard (note 53).
//
// On phones the keyboard only shrinks the VISUAL viewport; the layout viewport (and our scroll container) keeps
// its size, so a field low on the page, such as Create event's "Event introduction", can end up under the
// keyboard while the user types. Once the keyboard has settled after a field takes focus (visualViewport resize,
// or 350ms when no resize comes), this centres the field if it's not fully inside the visible area. It does
// nothing on desktop, where nothing covers the page. Same visualViewport idea as HostSetupSheet's keyboard lift,
// applied app-wide from App.jsx's Shell.
import { useEffect } from 'react';

const TEXT_LIKE = 'input:not([type="checkbox"]):not([type="radio"]):not([type="range"]):not([type="file"]):not([type="color"]):not([type="hidden"]):not([type="date"]):not([type="time"]), textarea, [contenteditable="true"]';

/** True when the box [top, bottom] isn't fully inside the visible band (with `margin` px of breathing room). */
export function isHiddenByKeyboard(rect, visibleTop, visibleHeight, margin = 12) {
  if (!rect || !(visibleHeight > 0)) return false;
  const top = visibleTop + margin;
  const bottom = visibleTop + visibleHeight - margin;
  // A field taller than the band: it's fine as long as its top part (where typing starts) shows.
  if (rect.bottom - rect.top > bottom - top) return rect.top < top || rect.top > bottom - 40;
  return rect.top < top || rect.bottom > bottom;
}

export default function useKeepFocusedVisible() {
  useEffect(() => {
    const vv = typeof window !== 'undefined' ? window.visualViewport : null;
    if (!vv) return undefined;
    let target = null;
    let timer = null;
    const ensure = () => {
      if (!target || document.activeElement !== target) return;
      const covered = window.innerHeight - vv.height > 80; // keyboard (not just a toolbar) is up
      if (!covered) return;
      if (!isHiddenByKeyboard(target.getBoundingClientRect(), vv.offsetTop, vv.height)) return;
      const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
      target.scrollIntoView({ block: 'center', behavior: reduce ? 'auto' : 'smooth' });
    };
    const onFocusIn = (e) => {
      const el = e.target;
      if (!(el instanceof Element) || !el.matches(TEXT_LIKE)) return;
      target = el;
      clearTimeout(timer);
      timer = setTimeout(ensure, 350);
    };
    const onResize = () => { clearTimeout(timer); timer = setTimeout(ensure, 60); };
    document.addEventListener('focusin', onFocusIn);
    vv.addEventListener('resize', onResize);
    return () => {
      clearTimeout(timer);
      document.removeEventListener('focusin', onFocusIn);
      vv.removeEventListener('resize', onResize);
    };
  }, []);
}

import { useLayoutEffect, useRef, useState } from 'react';

/**
 * Full-viewport overlays are mounted inside App.jsx's scrolling container (position: relative;
 * overflow-y: auto). An `absolute; inset: 0` child there is anchored to the top of the SCROLLED
 * CONTENT, so on a scrolled page the overlay sits above the visible area and only its bottom edge
 * shows. This pins the overlay to what is currently visible (top = scrollTop, height = clientHeight)
 * and freezes scrolling underneath while it is open.
 * Usage: const { ref, pin } = usePinnedOverlay(); <div ref={ref} style={{ position: 'absolute', inset: 0, ...pin }} />
 */
export function usePinnedOverlay() {
  const ref = useRef(null);
  const [pin, setPin] = useState({});
  useLayoutEffect(() => {
    const sc = ref.current?.offsetParent;
    if (!sc || sc === document.body) return undefined;
    setPin({ top: sc.scrollTop, bottom: 'auto', height: sc.clientHeight });
    const prev = sc.style.overflowY;
    sc.style.overflowY = 'hidden';
    return () => { sc.style.overflowY = prev; };
  }, []);
  return { ref, pin };
}

// The app's "screen". On a phone or a narrow window that is simply the browser
// viewport. On a desktop browser the app is drawn inside a phone-shaped frame
// (`.bb-screen`, see index.css), and anything that sizes itself from the screen
// — a map sheet, an expand-from-ring animation — must use THAT box, not the
// whole window behind it.
export function getFrameBox() {
  if (typeof document === 'undefined') return { left: 0, top: 0, width: 0, height: 0 };
  const el = document.querySelector('.bb-screen');
  // `display: contents` (the non-desktop case) has no box of its own.
  if (el && el.clientHeight > 0) {
    const r = el.getBoundingClientRect();
    return { left: r.left, top: r.top, width: r.width, height: r.height };
  }
  return { left: 0, top: 0, width: window.innerWidth, height: window.innerHeight };
}

export const screenHeight = () => getFrameBox().height;


// The iOS status-bar strip (index.css `body::before`) is drawn OVER the page, so anything placed from the very top of
// the window — a full-bleed screen's own top edge, the persistent search bar, a fixed overlay — has to add this inset
// itself, exactly as the iOS twin does (`PersistentSearchBar.swift`'s `safeAreaInsets.top + 8`). Zero on desktop, in
// the desktop phone frame and in Safari tabs.
// 2026-11-22: one variable owns the strip's height (`--bb-strip-h`, index.css), and the scroll viewport in App.jsx and
// every sticky web top band offset by the same value. That is what stopped the strip from clipping the first row of a
// web screen's band on phones whose env() inset is smaller than the strip's 12 px minimum.
export const SAFE_TOP = 'var(--bb-strip-h, env(safe-area-inset-top, 0px))';

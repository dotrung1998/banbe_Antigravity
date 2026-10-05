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

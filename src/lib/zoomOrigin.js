// Remembers which card was just tapped so Event Detail can zoom out of it (and back into it on close), like the
// iOS zoom transition. Any element carrying `data-zoom-src` is a card; the tap is recorded in the capture phase,
// before the app's own click handler swaps the screen.
let last = null;

export function installZoomOrigin() {
  if (typeof document === 'undefined' || installZoomOrigin.done) return;
  installZoomOrigin.done = true;
  document.addEventListener('click', (e) => {
    const el = e.target?.closest?.('[data-zoom-src]');
    if (!el) { last = null; return; }
    const r = el.getBoundingClientRect();
    last = { rect: { left: r.left, top: r.top, width: r.width, height: r.height }, key: el.getAttribute('data-zoom-src'), at: performance.now() };
  }, true);
}

/** The tapped card's viewport rect, if a card was tapped in the last 1.5s (not consumed: StrictMode renders twice). */
export function recentZoomOrigin() {
  if (!last || performance.now() - last.at > 1500) return null;
  return last.rect.width > 24 && last.rect.height > 24 ? last.rect : null;
}

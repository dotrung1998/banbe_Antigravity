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
    // A row zooms from its photo (`data-zoom-photo` inside it), so the cover grows out of the thumbnail, not the row.
    const r = (el.querySelector('[data-zoom-photo]') || el).getBoundingClientRect();
    last = { rect: { left: r.left, top: r.top, width: r.width, height: r.height }, key: el.getAttribute('data-zoom-src'), at: performance.now() };
  }, true);
}

/** The tapped card's viewport rect, if a card was tapped in the last 1.5s (not consumed: StrictMode renders twice). */
export function recentZoomOrigin() {
  if (!last || performance.now() - last.at > 1500) return null;
  return last.rect.width > 24 && last.rect.height > 24 ? last.rect : null;
}

// ---- Closing: the cover flies back as an overlay over the screen you return to (note 81) ----
// The previous screen is shown at once (its own entrance animations held off while `html[data-zoom-return]` is set,
// so it does not "reload" in front of you), and a copy of the cover, fixed on top of everything, travels from the
// hero to the card it came from, found again in the returned screen (the visible `[data-zoom-src=<key>]` nearest to
// where it was tapped; its `[data-zoom-photo]` when it has one). The card is hidden until the cover lands on it.
const RETURN_CSS = `html[data-zoom-return="1"] [data-screen-label], html[data-zoom-return="1"] [data-screen-label] *,
html[data-zoom-return="1"] [data-testid="browse-screen"], html[data-zoom-return="1"] [data-testid="browse-screen"] * { animation: none !important; }`;

function ensureReturnCss() {
  if (typeof document === 'undefined' || document.getElementById('bb-zoom-return-css')) return;
  const st = document.createElement('style');
  st.id = 'bb-zoom-return-css';
  st.textContent = RETURN_CSS;
  document.head.appendChild(st);
}

// The returned screen keeps its entrances off until the NEXT screen change (clearing it earlier would restart them:
// a CSS animation starts over when its name comes back). App calls noteScreenChange() on every screen change; the
// first one after flyBack is the return itself.
let armed = false;
export function noteScreenChange() {
  if (typeof document === 'undefined') return;
  if (armed) { armed = false; return; }
  delete document.documentElement.dataset.zoomReturn;
}

/** Starts the overlay flight; call it right before switching back to the previous screen. */
export function flyBack({ from, fallback, key, img, duration = 420 }) {
  if (typeof document === 'undefined' || !from) return;
  ensureReturnCss();
  const root = document.documentElement;
  root.dataset.zoomReturn = '1';
  armed = true;
  const fly = document.createElement('div');
  fly.setAttribute('data-testid', 'zoom-return-fly');
  Object.assign(fly.style, {
    position: 'fixed', left: `${from.left}px`, top: `${from.top}px`, width: `${from.width}px`, height: `${from.height}px`, zIndex: '9999',
    backgroundImage: img ? `url("${img}")` : 'none', backgroundSize: 'cover', backgroundPosition: 'center', backgroundColor: '#241E17',
    borderRadius: '0px', pointerEvents: 'none', boxShadow: '0 20px 50px rgba(0,0,0,.35)', willChange: 'left, top, width, height, border-radius',
  });
  document.body.appendChild(fly);
  let hidden = null;
  let finished = false;
  const finish = () => {
    if (finished) return;
    finished = true;
    if (hidden) hidden.style.visibility = '';
    const out = fly.animate?.([{ opacity: 1 }, { opacity: 0 }], { duration: 140 });
    if (out) out.onfinish = () => fly.remove(); else fly.remove();
  };
  const safety = setTimeout(finish, duration + 900);
  // Two frames: the previous screen has rendered and restored its scroll by then.
  requestAnimationFrame(() => requestAnimationFrame(() => {
    const vw = window.innerWidth, vh = window.innerHeight;
    const near = fallback || from;
    const cands = Array.from(document.querySelectorAll('[data-zoom-src]'))
      .filter(el => el.getAttribute('data-zoom-src') === key)
      .map(el => el.querySelector('[data-zoom-photo]') || el)
      .map(el => ({ el, r: el.getBoundingClientRect() }))
      .filter(({ r }) => r.width > 8 && r.height > 8 && r.left >= -2 && r.right <= vw + 2 && r.bottom > 0 && r.top < vh)
      .sort((a, b) => Math.hypot(a.r.left - near.left, a.r.top - near.top) - Math.hypot(b.r.left - near.left, b.r.top - near.top));
    const target = cands[0] || null;
    const to = target ? target.r : fallback;
    if (!to || !fly.animate) { clearTimeout(safety); finish(); return; }
    if (target) { hidden = target.el; hidden.style.visibility = 'hidden'; }
    const radius = target ? (getComputedStyle(target.el).borderRadius || '14px') : '14px';
    const a = fly.animate([
      { left: `${from.left}px`, top: `${from.top}px`, width: `${from.width}px`, height: `${from.height}px`, borderRadius: '0px' },
      { left: `${to.left}px`, top: `${to.top}px`, width: `${to.width}px`, height: `${to.height}px`, borderRadius: radius },
    ], { duration, easing: 'cubic-bezier(.32,.72,0,1)', fill: 'forwards' });
    a.onfinish = () => { clearTimeout(safety); finish(); };
  }));
}

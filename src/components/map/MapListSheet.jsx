// Map E+ (note 79): the list layer. A sheet that slides up to just under the shared search + chips (no handle, no
// header of its own) with a veil in its own colour over the strip above it. Pulling the list down while it is scrolled to
// its top slides it away and fades the veil with the finger, so the map shows again; a short pull springs back. The same
// pull works with a finger, a mouse drag and a trackpad wheel. The "Map" button and Esc (owned by the Map) do the same
// without a gesture.
// The pull is imperative on purpose: it writes the sheet's transform and the veil's opacity straight to the DOM (no React
// state), so a finger never re-renders the hundreds of cards that may be inside.
import { useEffect, useRef } from 'react';
import { LIST_PULL, pullOutcome, veilOpacity } from '../../lib/mapLayout.js';
import { paper, ink } from '../../theme.js';

const reduceMotion = () => typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

export default function MapListSheet({ open, onClose, top, scrollRef, mapButtonBottom, T, children }) {
  const sheetRef = useRef(null);
  const veilRef = useRef(null);
  const pillRef = useRef(null);
  const openRef = useRef(open);
  openRef.current = open;
  const closeRef = useRef(onClose);
  closeRef.current = onClose;

  useEffect(() => {
    const sheet = sheetRef.current;
    const veil = veilRef.current;
    if (!sheet || !veil) return undefined;
    let g = null;            // the gesture in progress: { x0, y0, t0, pulling, dy }
    let justPulled = false;  // a pull swallows the click that follows it, so it never opens the row under the finger
    let wheelAcc = 0, wheelTimer = 0;
    const atTop = () => (scrollRef.current?.scrollTop ?? 0) <= 0;
    // The Map button rides down with the sheet, so it fades with the veil rather than ending up behind the dock.
    const paint = (dy) => { sheet.style.transform = `translateY(${dy}px)`; veil.style.opacity = String(veilOpacity(dy)); if (pillRef.current) pillRef.current.style.opacity = String(veilOpacity(dy)); };
    const setPulling = (on) => { sheet.classList.toggle('bb-pulling', on); veil.classList.toggle('bb-pulling', on); };
    // Back to rest: dropping the inline values hands the sheet back to its React-owned style, so it eases home.
    const rest = () => { sheet.style.transform = ''; veil.style.opacity = ''; if (pillRef.current) pillRef.current.style.opacity = ''; setPulling(false); };

    const begin = (x, y, target) => {
      if (!openRef.current || target.closest?.('[data-nopull]')) return;
      g = { x0: x, y0: y, t0: performance.now(), pulling: false, dy: 0 };
    };
    // Returns true when the gesture is (now) a pull, so a touch can hold the page still.
    const move = (x, y) => {
      if (!g) return false;
      const dx = x - g.x0, d = y - g.y0;
      if (!g.pulling) {
        if (d > LIST_PULL.slopPx && Math.abs(d) > Math.abs(dx) && atTop()) {
          g.pulling = true;
          g.y0 = y - LIST_PULL.slopPx; // the first few pixels are slop: the sheet starts from where the pull began
          setPulling(true);
        } else {
          if (Math.abs(dx) > 10 || d < -LIST_PULL.slopPx) g = null; // sideways (photos) or up (scrolling): not a pull
          return false;
        }
      }
      g.dy = Math.max(0, y - g.y0);
      paint(g.dy);
      return true;
    };
    const end = () => {
      if (!g) return;
      const was = g;
      g = null;
      if (!was.pulling) return;
      justPulled = true;
      setTimeout(() => { justPulled = false; }, 80);
      const v = was.dy / Math.max(1, performance.now() - was.t0); // px per ms over the whole pull
      setPulling(false);
      if (pullOutcome(was.dy, v) === 'close') closeRef.current(); // React then eases it the rest of the way down
      else rest();
    };

    const onTouchStart = (e) => begin(e.touches[0].clientX, e.touches[0].clientY, e.target);
    const onTouchMove = (e) => { if (move(e.touches[0].clientX, e.touches[0].clientY) && e.cancelable) e.preventDefault(); };
    const onMouseDown = (e) => {
      if (e.pointerType !== 'mouse' || e.button !== 0) return;
      begin(e.clientX, e.clientY, e.target);
      if (!g) return;
      const mv = (ev) => move(ev.clientX, ev.clientY);
      const up = () => { removeEventListener('pointermove', mv); removeEventListener('pointerup', up); removeEventListener('pointercancel', up); end(); };
      addEventListener('pointermove', mv); addEventListener('pointerup', up); addEventListener('pointercancel', up);
    };
    const onWheel = (e) => {
      if (!openRef.current) return;
      if (atTop() && e.deltaY < 0) {
        wheelAcc += -e.deltaY;
        clearTimeout(wheelTimer);
        wheelTimer = setTimeout(() => { wheelAcc = 0; if (openRef.current) rest(); }, 220);
        if (wheelAcc > 180) { wheelAcc = 0; clearTimeout(wheelTimer); rest(); closeRef.current(); return; }
        setPulling(true); paint(Math.min(wheelAcc * 0.5, LIST_PULL.veilPx + 10));
      } else if (wheelAcc) { wheelAcc = 0; rest(); }
    };
    const swallow = (e) => { if (justPulled) { e.stopPropagation(); e.preventDefault(); } };
    const noDrag = (e) => e.preventDefault();

    sheet.addEventListener('touchstart', onTouchStart, { passive: true });
    sheet.addEventListener('touchmove', onTouchMove, { passive: false });
    sheet.addEventListener('touchend', end);
    sheet.addEventListener('touchcancel', end);
    sheet.addEventListener('pointerdown', onMouseDown);
    sheet.addEventListener('wheel', onWheel, { passive: true });
    sheet.addEventListener('click', swallow, true);
    sheet.addEventListener('dragstart', noDrag);
    return () => {
      clearTimeout(wheelTimer);
      sheet.removeEventListener('touchstart', onTouchStart); sheet.removeEventListener('touchmove', onTouchMove);
      sheet.removeEventListener('touchend', end); sheet.removeEventListener('touchcancel', end);
      sheet.removeEventListener('pointerdown', onMouseDown); sheet.removeEventListener('wheel', onWheel);
      sheet.removeEventListener('click', swallow, true); sheet.removeEventListener('dragstart', noDrag);
    };
  }, [scrollRef]);

  // Opening (from any route) starts from a clean sheet. Closing is left alone: React has just written the closed values,
  // and clearing them here would throw a closing sheet back open.
  useEffect(() => {
    if (!open || !sheetRef.current || !veilRef.current) return;
    sheetRef.current.style.transform = ''; veilRef.current.style.opacity = ''; if (pillRef.current) pillRef.current.style.opacity = '';
    sheetRef.current.classList.remove('bb-pulling'); veilRef.current.classList.remove('bb-pulling');
  }, [open]);

  const reduced = reduceMotion();
  return (
    <>
      {/* The veil: the list's own colour over the strip above it, behind the shared controls. It fades as the list is pulled. */}
      <div ref={veilRef} aria-hidden="true" data-testid="map-list-veil"
        style={{ position: 'absolute', left: 0, right: 0, top: 0, height: top + 2, zIndex: 4, background: paper, opacity: open ? 1 : 0, pointerEvents: open ? 'auto' : 'none',
          transition: reduced ? 'none' : 'opacity 0.3s ease' }} />
      <section ref={sheetRef} data-testid="map-list-sheet" aria-label={T('Danh sách sự kiện', 'Event list')} aria-hidden={open ? undefined : true}
        style={{ position: 'absolute', left: 0, right: 0, bottom: 0, top, zIndex: 4, background: paper, display: 'flex', flexDirection: 'column',
          transform: open ? 'none' : 'translateY(100%)', visibility: open ? 'visible' : 'hidden',
          transition: reduced ? 'none' : `transform 0.38s cubic-bezier(.2,.85,.25,1), visibility 0s linear ${open ? 0 : 0.38}s` }}>
        {children}
        {/* Back to the map (also Esc, a pull down, or the wheel). */}
        <button ref={pillRef} type="button" data-nopull onClick={() => onClose()} data-testid="map-list-map-button" aria-label={T('Xem bản đồ', 'Show map')}
          style={{ position: 'absolute', left: '50%', bottom: mapButtonBottom, transform: 'translateX(-50%)', height: 44, padding: '0 20px', borderRadius: 999, border: 'none',
            background: ink, color: paper, display: 'flex', alignItems: 'center', gap: 8, fontSize: 15, fontWeight: 600, fontFamily: 'inherit', cursor: 'pointer', boxShadow: '0 4px 14px rgba(27,25,22,0.28)' }}>
          {T('Bản đồ', 'Map')}
          <svg aria-hidden="true" width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2zM9 4v14M15 6v14" /></svg>
        </button>
      </section>
    </>
  );
}

// One pager for every v2.3 list (note 81): the Home Shortlist, Browse by type and See all. Four large rows a page at
// least, more when the screen has room (fittedPageSize): the rows and the pager fill the band under the list's top
// edge instead of leaving it empty, so a page still needs no vertical scrolling. The rows sit on their own horizontal
// track (the page around it never moves); the arrows and page numbers drive the same track, so a tap and a swipe
// always agree. The ink under the numbers is a drop that FOLLOWS the swipe: it is painted from the track's live
// scroll position, so it leaves with the finger, stretches between two numbers (leading edge ahead, trailing edge
// behind) and settles on the new one; a tap scrolls the track, so it animates the same way. The drop is a second copy
// of the numbers in the page colour on ink, cut to the drop's shape, so a number turns light exactly where the drop
// covers it. Flat ink, no gloss. "5–8 of 18" says where you are (read out politely). The numbers, arrows and range
// are the only paging signs: the edge tabs, the one-time nudge and the "Swipe to see more" line said the same thing
// three more times and are gone. A short last page ends with an end card sized to the missing rows. Reduced motion:
// the page turns without a slide, the drop steps from number to number.
// Pure rules live in src/lib/pager.js. iOS twin: V23Pager / PagerDrop in HomeV23Views.swift.
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { paginate, pageRange, endCardRoom, showPageNav, dropEdges, pageAt, clampPage, pageWindow, fittedPageSize, PAGE_SIZE } from '../../lib/pager.js';
import { useReducedMotion } from '../../lib/useReducedMotion.js';

const CHEV = (d) => (
  <svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d={d} /></svg>
);
const PAGE_TURN_MS = 440;
const STAGGER_MS = 45;
const NUM = { boxSizing: 'border-box', minWidth: 44, height: 44, padding: '0 6px', fontFamily: 'inherit', fontSize: 14, fontWeight: 600, fontVariantNumeric: 'tabular-nums' };
// The page each list was on, so coming back from an event lands on the same page (and the cover can shrink back into
// the row it came from). Per list (testId) and content (signature), for this page load only.
const savedPages = new Map();

/**
 * @param {object} p
 * @param {Array} p.items
 * @param {(it) => string} p.getKey
 * @param {(it) => import('react').ReactNode} p.renderRow
 * @param {(room: {room:number, variant:string}) => import('react').ReactNode} [p.renderEnd]  end card for a short last page
 * @param {import('react').ReactNode} [p.empty]  shown instead of pages when there are no items
 * @param {'vi'|'en'} p.lang
 * @param {(vi:string, en:string) => string} p.T
 * @param {string} p.testId  e.g. "home-shortlist"
 * @param {number} [p.rowHeight]  one row's height, so the end card fills exactly the missing rows
 */
export default function Pager({ items, getKey, renderRow, renderEnd, empty = null, lang, T, testId, rowHeight = 92 }) {
  const reduced = useReducedMotion();
  // How many rows fit under this list's own top edge (see fittedPageSize): read from the app's scrolling viewport,
  // once per mount and on resize, never per item so a new page cannot reflow mid-swipe.
  const rootRef = useRef(null);
  const [size, setSize] = useState(PAGE_SIZE);
  useLayoutEffect(() => {
    const measure = () => {
      const el = rootRef.current;
      if (!el) return;
      let sc = el.parentElement;
      while (sc && sc !== document.body && sc !== document.documentElement) {
        const oy = getComputedStyle(sc).overflowY;
        if ((oy === 'auto' || oy === 'scroll') && sc.clientHeight > 0) break;
        sc = sc.parentElement;
      }
      const scrolls = sc && sc !== document.body && sc !== document.documentElement;
      const available = scrolls
        ? sc.clientHeight - (el.getBoundingClientRect().top - sc.getBoundingClientRect().top + sc.scrollTop)
        : window.innerHeight - el.getBoundingClientRect().top;
      setSize(fittedPageSize({ available, rowHeight }));
    };
    measure();
    // One frame later: web fonts and the heading above settle their heights, and the list's top edge moves with them.
    const raf = requestAnimationFrame(measure);
    window.addEventListener('resize', measure);
    return () => { cancelAnimationFrame(raf); window.removeEventListener('resize', measure); };
  }, [rowHeight]);
  const pages = useMemo(() => paginate(items, size), [items, size]);
  const signature = useMemo(() => items.map(getKey).join('|'), [items, getKey]);
  const pageKey = `${testId}|${signature}`;
  const [page, setPage] = useState(() => clampPage(savedPages.get(pageKey) || 0, pages.length || 1));
  const settleTimer = useRef(0);
  useEffect(() => { savedPages.set(pageKey, page); }, [pageKey, page]);
  // A fitted size can change the number of pages (resize, rotation): keep the open page in range.
  useEffect(() => {
    const at = clampPage(page, pages.length || 1);
    if (at !== page) setPage(at);
  }, [pages.length]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => () => clearTimeout(settleTimer.current), []);
  const trackRef = useRef(null);
  const numsRef = useRef(null);
  const inkRef = useRef(null);
  const target = useRef(null);
  const targetTimer = useRef(0);
  const prevPage = useRef(0);
  // True while the track is moving under a finger (or a smooth scroll): the rows are already sliding with it, so a
  // page change must not also play their slide-in. `pageNow` lets the settle timer read the fresh page.
  const live = useRef(false);
  const pageNow = useRef(0);
  pageNow.current = page;

  // Paint the drop at a position in pages (fractional mid-swipe). Positions come from the number cells themselves, so
  // a two-digit number that is wider than the rest is still covered edge to edge.
  const paintAt = useCallback((f) => {
    const nums = numsRef.current, ink = inkRef.current;
    if (!nums || !ink) return;
    const cells = nums.querySelectorAll('[data-page]');
    if (!cells.length) return;
    const { trail, lead } = dropEdges(f, Number(cells[0].dataset.page), cells.length, reduced);
    const edge = (x, right) => {
      const i = Math.min(cells.length - 1, Math.floor(x)), j = Math.min(cells.length - 1, i + 1), t = x - i;
      const at = c => c.offsetLeft + (right ? c.offsetWidth : 0);
      return at(cells[i]) + (at(cells[j]) - at(cells[i])) * t;
    };
    const left = edge(trail, false) + 3, right = edge(lead, true) - 3;
    ink.style.clipPath = `inset(6px ${Math.max(0, nums.offsetWidth - right)}px 6px ${Math.max(0, left)}px round 16px)`;
  }, [reduced]);
  const paintFromTrack = useCallback(() => {
    const el = trackRef.current;
    paintAt(el && el.clientWidth ? el.scrollLeft / el.clientWidth : pageNow.current);
  }, [paintAt]);

  // A new list (another tab, other filters) starts on its saved page (page one the first time), without animation.
  useLayoutEffect(() => {
    const start = clampPage(savedPages.get(pageKey) || 0, pages.length || 1);
    setPage(start);
    prevPage.current = start;
    target.current = null;
    live.current = false;
    if (trackRef.current) trackRef.current.scrollLeft = start * trackRef.current.clientWidth;
  }, [signature]); // eslint-disable-line react-hooks/exhaustive-deps

  // Land on a page: the drop is repainted from where the track really is (the numbers shown may have changed), then
  // the rows slide in from the side you travel to — unless the track is already moving them.
  useLayoutEffect(() => {
    const from = prevPage.current;
    paintFromTrack();
    if (from !== page && !reduced && !live.current) {
      const dir = page > from ? 1 : -1;
      const rows = trackRef.current?.querySelectorAll(`[data-pager-page="${page}"] > [data-pager-row]`) || [];
      rows.forEach((el, k) => el.animate?.([
        { transform: `translateX(${dir * 28}px)`, opacity: 0.35 }, { transform: 'none', opacity: 1 },
      ], { duration: PAGE_TURN_MS, delay: k * STAGGER_MS, easing: 'cubic-bezier(.22,1,.36,1)', fill: 'backwards' }));
    }
    prevPage.current = page;
  }, [page, pages.length, signature, paintFromTrack, reduced]);

  // Keep the drop right when the numbers reflow (font load, rotation).
  useEffect(() => {
    if (typeof ResizeObserver === 'undefined' || !numsRef.current) return undefined;
    const ro = new ResizeObserver(() => paintFromTrack());
    ro.observe(numsRef.current);
    return () => ro.disconnect();
  }, [paintFromTrack, pages.length]);

  const go = (i) => {
    const el = trackRef.current;
    const next = clampPage(i, pages.length);
    if (!el) return;
    target.current = next;
    clearTimeout(targetTimer.current);
    targetTimer.current = setTimeout(() => { target.current = null; }, 800);
    el.scrollTo({ left: next * el.clientWidth, behavior: reduced ? 'auto' : 'smooth' });
    setPage(next);
  };
  useEffect(() => () => clearTimeout(targetTimer.current), []);

  // Read the track, not our intentions: whichever page is nearest wins (a swipe lands here), and the drop is painted
  // at exactly the track's position on every scroll event.
  const onScroll = () => {
    const el = trackRef.current;
    if (!el || !el.clientWidth) return;
    live.current = true;
    paintAt(el.scrollLeft / el.clientWidth);
    clearTimeout(settleTimer.current);
    settleTimer.current = setTimeout(() => { live.current = false; paintFromTrack(); }, 220);
    const at = pageAt(el.scrollLeft, el.clientWidth, pages.length);
    if (target.current !== null) {
      if (at !== target.current) return;
      target.current = null;
    }
    if (at !== page) setPage(at);
  };

  if (!pages.length) return <div data-testid={`${testId}-empty`}>{empty}</div>;

  const end = endCardRoom(pages, size);
  const range = pageRange(pages, page, lang);
  const nav = showPageNav(pages);
  const shown = pageWindow(page, pages.length);
  const navBtn = { width: 44, height: 44, borderRadius: '50%', border: 'none', background: 'none', color: 'inherit', display: 'grid', placeItems: 'center', cursor: 'pointer', flex: 'none' };

  return (
    <div ref={rootRef} data-testid={testId} data-page={page} data-pages={pages.length} data-page-size={size}>
      <div ref={trackRef} data-hscroll onScroll={onScroll} data-testid={`${testId}-track`}
        style={{ display: 'flex', overflowX: 'auto', scrollSnapType: 'x mandatory', scrollbarWidth: 'none', overscrollBehaviorX: 'contain' }}>
        {pages.map((rows, i) => {
          const last = i === pages.length - 1;
          const off = i !== page;
          return (
            <div key={i} data-pager-page={i} aria-hidden={off ? 'true' : 'false'} ref={el => { if (el) el.inert = off; }}
              style={{ flex: '0 0 100%', minWidth: 0, scrollSnapAlign: 'start', scrollSnapStop: 'always', display: 'flex', flexDirection: 'column' }}>
              {rows.map(it => <div key={getKey(it)} data-pager-row>{renderRow(it)}</div>)}
              {last && end.variant && renderEnd && (
                <div data-pager-row data-testid={`${testId}-end`} data-variant={end.variant} data-room={end.room}
                  style={{ minHeight: end.variant === 'solo' ? undefined : end.room * rowHeight, display: 'flex', flexDirection: 'column' }}>
                  {renderEnd(end)}
                </div>
              )}
            </div>
          );
        })}
      </div>
      {nav && (
        <nav aria-label={T('Các trang', 'Pages')} style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 2, padding: '6px 20px 0' }}>
          <button type="button" style={{ ...navBtn, opacity: page === 0 ? 0.3 : 1 }} disabled={page === 0} onClick={() => go(page - 1)}
            aria-label={T('Trang trước', 'Previous page')} data-testid={`${testId}-prev`}>{CHEV('m15 6-6 6 6 6')}</button>
          <div ref={numsRef} style={{ position: 'relative', display: 'flex' }}>
            {shown.map((i) => (
              <button key={i} type="button" data-page={i} data-testid={`${testId}-page-${i + 1}`} onClick={() => go(i)}
                aria-label={T(`Trang ${i + 1}`, `Page ${i + 1}`)} aria-current={i === page ? 'page' : undefined}
                style={{ ...NUM, border: 'none', background: 'none', cursor: 'pointer', color: 'inherit' }}>
                {i + 1}
              </button>
            ))}
            <div ref={inkRef} aria-hidden="true" data-testid={`${testId}-drop`}
              style={{ position: 'absolute', inset: 0, display: 'flex', background: 'var(--bb-fg)', color: 'var(--bb-bg)', pointerEvents: 'none', willChange: 'clip-path', clipPath: 'inset(6px 100% 6px 0 round 16px)' }}>
              {shown.map((i) => <span key={i} style={{ ...NUM, display: 'grid', placeItems: 'center' }}>{i + 1}</span>)}
            </div>
          </div>
          <button type="button" style={{ ...navBtn, opacity: page === pages.length - 1 ? 0.3 : 1 }} disabled={page === pages.length - 1} onClick={() => go(page + 1)}
            aria-label={T('Trang sau', 'Next page')} data-testid={`${testId}-next`}>{CHEV('m9 6 6 6-6 6')}</button>
        </nav>
      )}
      {nav && (
        <div aria-live="polite" data-testid={`${testId}-range`} style={{ textAlign: 'center', fontSize: 12.5, opacity: 0.72, marginTop: 2 }}>{range.text}</div>
      )}
    </div>
  );
}

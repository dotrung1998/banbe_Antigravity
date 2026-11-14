// One pager for every v2.3 list (note 81): the Home Shortlist now, Browse by type / See all next. Four large rows a
// page on their own horizontal track (the page around it never moves); the arrows and page numbers drive the same
// track, so a tap and a swipe always agree. One ink under the numbers stretches across to the new number and settles,
// rows slide in from the side you travel to, and "5–8 of 18" says where you are (read out politely). A short last page
// ends with an end card sized to the missing rows. Reduced motion: the page turns without a slide, the ink jumps.
// Pure rules live in src/lib/pager.js.
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { paginate, pageRange, endCardRoom, showPageNav, inkFrames, pageAt, clampPage, pageWindow, PAGE_SIZE } from '../../lib/pager.js';
import { useReducedMotion } from '../../lib/useReducedMotion.js';

const CHEV = (d) => (
  <svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d={d} /></svg>
);
const PAGE_TURN_MS = 440;
const STAGGER_MS = 45;
// Swipe signs (Browse by type / See all, note 81): slim tabs at the edges, narrow enough to stay clear of the prices.
// The right one nudges toward the next page ONCE, the first time this person ever opens a list with hints (remembered
// in this browser); after that the tabs sit still. While the list is being swiped both tabs darken, then fade back.
// No edge bounce, no peek. Reduced motion: no nudge.
const HINT_CSS = `
@keyframes bbV23TabNudge { 0%, 100% { transform: translate(0, -50%); } 20% { transform: translate(-6px, -50%); } 40% { transform: translate(0, -50%); } 60% { transform: translate(-4px, -50%); } 80% { transform: translate(0, -50%); } }
.bb-v23-tab { position: absolute; top: 50%; transform: translate(0, -50%); z-index: 2; width: 18px; height: 56px; border: none; padding: 0;
  display: grid; place-items: center; cursor: pointer; color: var(--bb-fg); background: rgba(var(--bb-fg-rgb), 0.08); font: inherit; font-size: 15px;
  transition: background-color .6s ease, opacity .6s ease; }
.bb-v23-tab.next { right: 0; border-radius: 10px 0 0 10px; }
.bb-v23-tab.next.nudge { animation: bbV23TabNudge 1.4s ease-in-out .8s 1 both; }
.bb-v23-tab.prev { left: 0; border-radius: 0 10px 10px 0; opacity: 0.6; }
[data-swiping="1"] > .bb-v23-tab { background: rgba(var(--bb-fg-rgb), 0.22); opacity: 1; transition: background-color .12s ease, opacity .12s ease; }
@media (prefers-reduced-motion: reduce) { .bb-v23-tab.next.nudge { animation: none; } }
.bb-v23-cue { transition: opacity .4s ease; }
.bb-v23-cue.gone { opacity: 0; }
`;
const NUDGE_KEY = 'banbe.v23.pagerNudgeSeen';
let nudgeSeenThisLoad = false;
const nudgeSeen = () => { if (nudgeSeenThisLoad) return true; try { return localStorage.getItem(NUDGE_KEY) === '1'; } catch { return false; } };
const markNudgeSeen = () => { nudgeSeenThisLoad = true; try { localStorage.setItem(NUDGE_KEY, '1'); } catch { /* private mode */ } };
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
export default function Pager({ items, getKey, renderRow, renderEnd, empty = null, lang, T, testId, rowHeight = 92, hints = false }) {
  const reduced = useReducedMotion();
  const pages = useMemo(() => paginate(items, PAGE_SIZE), [items]);
  const signature = useMemo(() => items.map(getKey).join('|'), [items, getKey]);
  const pageKey = `${testId}|${signature}`;
  const [page, setPage] = useState(() => clampPage(savedPages.get(pageKey) || 0, pages.length || 1));
  const swipeRef = useRef(null);
  const swipeTimer = useRef(0);
  // The one-time nudge: decided once per mount, remembered as soon as it is shown.
  const [nudge] = useState(() => hints && !nudgeSeen());
  useEffect(() => { if (nudge) markNudgeSeen(); }, [nudge]);
  useEffect(() => { savedPages.set(pageKey, page); }, [pageKey, page]);
  useEffect(() => () => clearTimeout(swipeTimer.current), []);
  const trackRef = useRef(null);
  const numsRef = useRef(null);
  const inkRef = useRef(null);
  const target = useRef(null);
  const targetTimer = useRef(0);
  const prevPage = useRef(0);
  // The cue line fades after the first page turn; the peek plays once per list.
  const [turned, setTurned] = useState(false);

  // A new list (another tab, other filters) starts on its saved page (page one the first time), without animation.
  useLayoutEffect(() => {
    const start = clampPage(savedPages.get(pageKey) || 0, pages.length || 1);
    setPage(start);
    prevPage.current = start;
    target.current = null;
    if (trackRef.current) trackRef.current.scrollLeft = start * trackRef.current.clientWidth;
  }, [signature]); // eslint-disable-line react-hooks/exhaustive-deps

  const placeInk = useCallback((from, animate) => {
    const nums = numsRef.current, ink = inkRef.current;
    if (!nums || !ink) return;
    const to = nums.querySelector(`[data-page="${page}"]`);
    if (!to) return;
    const end = { left: to.offsetLeft, width: to.offsetWidth };
    ink.getAnimations?.().forEach(a => a.cancel());
    ink.style.left = `${end.left}px`;
    ink.style.width = `${end.width}px`;
    const a = from != null ? nums.querySelector(`[data-page="${from}"]`) : null;
    if (!animate || reduced || !a || a === to || !ink.animate) return;
    const f = inkFrames({ left: a.offsetLeft, width: a.offsetWidth }, end);
    ink.animate([
      { left: `${f[0].left}px`, width: `${f[0].width}px` },
      { left: `${f[1].left}px`, width: `${f[1].width}px`, offset: 0.42 },
      { left: `${f[2].left}px`, width: `${f[2].width}px` },
    ], { duration: 460, easing: 'cubic-bezier(.3,.9,.3,1)' });
  }, [page, reduced]);

  // Land on a page: ink, then the rows slide in from the side you travel to.
  useLayoutEffect(() => {
    const from = prevPage.current;
    placeInk(from === page ? null : from, true);
    if (from !== page) setTurned(true);
    if (from !== page && !reduced) {
      const dir = page > from ? 1 : -1;
      const rows = trackRef.current?.querySelectorAll(`[data-pager-page="${page}"] > [data-pager-row]`) || [];
      rows.forEach((el, k) => el.animate?.([
        { transform: `translateX(${dir * 28}px)`, opacity: 0.35 }, { transform: 'none', opacity: 1 },
      ], { duration: PAGE_TURN_MS, delay: k * STAGGER_MS, easing: 'cubic-bezier(.22,1,.36,1)', fill: 'backwards' }));
    }
    prevPage.current = page;
  }, [page, placeInk, reduced]);

  // Keep the ink right when the numbers reflow (font load, rotation).
  useEffect(() => {
    if (typeof ResizeObserver === 'undefined' || !numsRef.current) return undefined;
    const ro = new ResizeObserver(() => placeInk(null, false));
    ro.observe(numsRef.current);
    return () => ro.disconnect();
  }, [placeInk, pages.length]);

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

  // Read the track, not our intentions: whichever page is nearest wins (a swipe lands here).
  const onScroll = () => {
    const el = trackRef.current;
    if (!el || !el.clientWidth) return;
    // Both tabs darken while the list moves, then fade back once it settles.
    if (hints && swipeRef.current) {
      swipeRef.current.dataset.swiping = '1';
      clearTimeout(swipeTimer.current);
      swipeTimer.current = setTimeout(() => { if (swipeRef.current) swipeRef.current.dataset.swiping = '0'; }, 220);
    }
    const at = pageAt(el.scrollLeft, el.clientWidth, pages.length);
    if (target.current !== null) {
      if (at !== target.current) return;
      target.current = null;
    }
    if (at !== page) setPage(at);
  };

  if (!pages.length) return <div data-testid={`${testId}-empty`}>{empty}</div>;

  const end = endCardRoom(pages, PAGE_SIZE);
  const range = pageRange(pages, page, lang);
  const nav = showPageNav(pages);
  const navBtn = { width: 44, height: 44, borderRadius: '50%', border: 'none', background: 'none', color: 'inherit', display: 'grid', placeItems: 'center', cursor: 'pointer', flex: 'none' };

  return (
    <div data-testid={testId} data-page={page} data-pages={pages.length}>
      {hints && <style>{HINT_CSS}</style>}
      <div ref={swipeRef} data-swiping="0" style={{ position: 'relative' }}>
      {hints && nav && page > 0 && (
        <button type="button" className="bb-v23-tab prev" onClick={() => go(page - 1)} aria-label={T('Trang trước', 'Previous page')} data-testid={`${testId}-hint-prev`}>‹</button>
      )}
      {hints && nav && page < pages.length - 1 && (
        <button type="button" className={`bb-v23-tab next${nudge ? ' nudge' : ''}`} onClick={() => go(page + 1)}
          aria-label={T('Trang sau', 'Next page')} data-testid={`${testId}-hint-next`} data-nudge={nudge ? 'true' : 'false'}>›</button>
      )}
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
      </div>
      {hints && nav && (
        <div aria-hidden="true" className={`bb-v23-cue${turned ? ' gone' : ''}`} data-testid={`${testId}-cue`} data-gone={turned ? 'true' : 'false'}
          style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 8, fontSize: 12.5, opacity: turned ? 0 : 0.6, marginTop: 4 }}>
          <span>{T('Vuốt để xem thêm', 'Swipe to see more')}</span><span>⟶</span>
        </div>
      )}
      {nav && (
        <nav aria-label={T('Các trang', 'Pages')} style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 2, padding: '6px 20px 0' }}>
          <button type="button" style={{ ...navBtn, opacity: page === 0 ? 0.3 : 1 }} disabled={page === 0} onClick={() => go(page - 1)}
            aria-label={T('Trang trước', 'Previous page')} data-testid={`${testId}-prev`}>{CHEV('m15 6-6 6 6 6')}</button>
          <div ref={numsRef} style={{ position: 'relative', display: 'flex', gap: 2 }}>
            <span ref={inkRef} aria-hidden="true" style={{ position: 'absolute', top: 6, height: 32, borderRadius: 999, background: 'var(--bb-fg)', pointerEvents: 'none' }} />
            {pageWindow(page, pages.length).map((i) => (
              <button key={i} type="button" data-page={i} data-testid={`${testId}-page-${i + 1}`} onClick={() => go(i)}
                aria-label={T(`Trang ${i + 1}`, `Page ${i + 1}`)} aria-current={i === page ? 'page' : undefined}
                style={{ position: 'relative', minWidth: 44, height: 44, padding: '0 6px', border: 'none', background: 'none', fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer', color: i === page ? 'var(--bb-bg)' : 'inherit', transition: reduced ? 'none' : 'color .2s' }}>
                {i + 1}
              </button>
            ))}
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

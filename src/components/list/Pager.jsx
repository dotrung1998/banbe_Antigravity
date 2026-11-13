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
// Swipe signs (Browse by type / See all, note 81), in the "How banbe works" deck's language: a soft tab at the right
// edge pulses toward the next page, a springy hop replaces the pulse when the next page is the last, a quieter tab on
// the left once you can go back. Reduced motion: the tabs stay, nothing moves.
const HINT_CSS = `
@keyframes bbV23TabPulse { 0%, 100% { transform: translate(0, -50%); } 50% { transform: translate(-5px, -50%); } }
@keyframes bbV23TabHop { 0%, 60%, 100% { transform: translate(0, -50%); } 70% { transform: translate(-9px, -50%); } 80% { transform: translate(0, -50%); } 88% { transform: translate(-4px, -50%); } }
.bb-v23-tab { position: absolute; top: 50%; transform: translate(0, -50%); z-index: 2; width: 28px; height: 64px; border: none; padding: 0;
  display: grid; place-items: center; cursor: pointer; color: var(--bb-fg); background: rgba(var(--bb-fg-rgb), 0.09); font: inherit; font-size: 18px; }
.bb-v23-tab.next { right: 0; border-radius: 14px 0 0 14px; animation: bbV23TabPulse 1.6s ease-in-out infinite; }
.bb-v23-tab.next.last { animation: bbV23TabHop 2.2s cubic-bezier(.2,1.2,.4,1) infinite; }
.bb-v23-tab.prev { left: 0; border-radius: 0 14px 14px 0; opacity: 0.6; }
@media (prefers-reduced-motion: reduce) { .bb-v23-tab.next, .bb-v23-tab.next.last { animation: none; } }
.bb-v23-cue { transition: opacity .4s ease; }
.bb-v23-cue.gone { opacity: 0; }
`;

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
  const [page, setPage] = useState(0);
  const trackRef = useRef(null);
  const numsRef = useRef(null);
  const inkRef = useRef(null);
  const target = useRef(null);
  const targetTimer = useRef(0);
  const prevPage = useRef(0);
  // The cue line fades after the first page turn; the peek plays once per list.
  const [turned, setTurned] = useState(false);
  const peeked = useRef('');

  // A new list (another tab, other filters) starts on page one, without animation.
  useEffect(() => {
    setPage(0);
    prevPage.current = 0;
    target.current = null;
    if (trackRef.current) trackRef.current.scrollLeft = 0;
  }, [signature]);

  // When a multi-page list opens, the pages lean left for a moment so the next one shows its edge. Once per list.
  useEffect(() => {
    if (!hints || reduced || turned || pages.length < 2 || peeked.current === signature) return undefined;
    peeked.current = signature;
    const t = setTimeout(() => {
      trackRef.current?.querySelectorAll('[data-pager-page]').forEach((el, i) => {
        if (i > 1) return;
        el.animate?.([{ transform: 'none' }, { transform: 'translateX(-46px)', offset: 0.45 }, { transform: 'translateX(-46px)', offset: 0.6 }, { transform: 'none' }],
          { duration: 1100, easing: 'cubic-bezier(.45,0,.2,1)' });
      });
    }, 650);
    return () => clearTimeout(t);
  }, [hints, reduced, turned, pages.length, signature]);

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
      <div style={{ position: 'relative' }}>
      {hints && nav && page > 0 && (
        <button type="button" className="bb-v23-tab prev" onClick={() => go(page - 1)} aria-label={T('Trang trước', 'Previous page')} data-testid={`${testId}-hint-prev`}>‹</button>
      )}
      {hints && nav && page < pages.length - 1 && (
        <button type="button" className={`bb-v23-tab next${page === pages.length - 2 ? ' last' : ''}`} onClick={() => go(page + 1)}
          aria-label={T('Trang sau', 'Next page')} data-testid={`${testId}-hint-next`} data-last={page === pages.length - 2 ? 'true' : 'false'}>›</button>
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

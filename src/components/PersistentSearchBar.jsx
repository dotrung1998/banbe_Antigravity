// ONE search bar for Search and Map (twin of iOS Views/PersistentSearchBar.swift), hosted once in App.jsx above both so
// it never unmounts when Search gives way to Map: the <input>, its focus and the keyboard carry over and the text shows
// instantly. Context-aware: on Search it edits the global query, on Map the map's own query (lifted into
// src/lib/searchBarStore.js, like iOS `mapSearchText`). Screens register {owner, placeholder, back, submit, cancel,
// filters, badge} and keep an empty 44px row where the field used to be; this bar draws there.
// Glide: opening from Home starts the bar exactly over Home's own bar (frame kept in the store) with back/filter
// collapsed, then it moves to the top; closing glides it back down and it lingers ~400ms, fading out as Home shows.
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { searchBarStore, useSearchBar } from '../lib/searchBarStore.js';
import { photoPill, ink, ink2, clay } from '../theme.js';

/** Top of the bar / of the empty row under it (Map's former value: the desktop phone frame's status bar + 8). */
export function searchBarTop() {
  const desk = typeof window !== 'undefined' && window.matchMedia && window.matchMedia('(min-width: 700px) and (min-height: 560px) and (hover: hover) and (pointer: fine)').matches;
  return (desk ? 50 : 0) + 8;
}

const EASE = 'cubic-bezier(.22,.9,.3,1)';
const GLIDE_MS = 420;
const reducedMotion = () => typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

export default function PersistentSearchBar() {
  const { state: s, T } = useBanBe();
  const bar = useSearchBar();
  const isMap = s.screen === 'mapExplore';
  const active = isMap || s.screen === 'search' || (!!s.searchOverlayOpen && s.screen === 'home');
  const wrapRef = useRef(null);
  const [entered, setEntered] = useState(false);
  const [lingering, setLingering] = useState(false);
  const [lastH, setLastH] = useState(null);
  const prevActive = useRef(false);
  const prevScreen = useRef(s.screen);
  const fromHome = useRef(false);
  const lingerTimer = useRef(null);

  // Remember who is asking while the bar lingers after its screen closed.
  useLayoutEffect(() => { if (bar.handlers) setLastH(bar.handlers); }, [bar.handlers]);

  useLayoutEffect(() => {
    const was = prevActive.current;
    prevActive.current = active;
    if (active && !was) {
      clearTimeout(lingerTimer.current);
      setLingering(false);
      fromHome.current = s.screen === 'home' || prevScreen.current === 'home';
      setEntered(false);
      searchBarStore.setAtHome(false);
      let a = 0; let b = 0;
      a = requestAnimationFrame(() => { b = requestAnimationFrame(() => setEntered(true)); });
      return () => { cancelAnimationFrame(a); cancelAnimationFrame(b); };
    }
    if (!active && was) {
      const glide = fromHome.current && !!searchBarStore.get().homeFrame && !reducedMotion();
      setEntered(false);
      if (glide) {
        searchBarStore.setAtHome(true);
        setLingering(true);
        clearTimeout(lingerTimer.current);
        lingerTimer.current = setTimeout(() => { setLingering(false); setLastH(null); searchBarStore.setAtHome(false); }, 400);
      } else { searchBarStore.setAtHome(false); setLastH(null); }
    }
    return undefined;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active]);
  useLayoutEffect(() => { prevScreen.current = s.screen; });
  useEffect(() => () => clearTimeout(lingerTimer.current), []);

  // Keep Home's bar frame fresh while Home is showing (the glide starts / ends exactly over it; iOS homeSearchBarFrame).
  useEffect(() => {
    if (s.screen !== 'home' || active) return undefined;
    const measure = () => {
      const el = document.querySelector('[data-testid="home-search-bar"]');
      const pill = el?.closest('.bb-searchbar') || el;
      if (pill) searchBarStore.setHomeFrame(pill.getBoundingClientRect());
    };
    const t0 = setTimeout(measure, 350);
    const sc = document.querySelector('[data-testid="app-scroll-viewport"]');
    sc?.addEventListener('scroll', measure, { passive: true });
    window.addEventListener('resize', measure);
    return () => { clearTimeout(t0); sc?.removeEventListener('scroll', measure); window.removeEventListener('resize', measure); };
  }, [s.screen, active]);

  const h = bar.handlers || lastH;
  const fns = searchBarStore.fns();
  const frame = bar.homeFrame;
  const canGlide = !!frame && frame.top >= 0 && frame.top < window.innerHeight && fromHome.current && !reducedMotion();
  const atHome = canGlide && (bar.atHome || (active && !entered) || lingering);
  const off = wrapRef.current?.getBoundingClientRect?.() || { left: 0, top: 0 };
  const top = searchBarTop();
  const x = atHome ? frame.left - off.left : 16;
  const y = atHome ? frame.top - off.top : top;
  const text = isMap ? bar.mapQuery : bar.searchQuery;
  const setText = (v) => (isMap ? searchBarStore.setMapQuery(v) : searchBarStore.setSearchQuery(v));
  const show = (active || lingering) && h;
  const hidden = !!bar.handlers?.hidden;
  const filtersBtn = isMap && !bar.focused && h?.hasFilters;
  const glideT = reducedMotion() ? 'none' : `transform ${GLIDE_MS}ms ${EASE}, width ${GLIDE_MS}ms ${EASE}, height ${GLIDE_MS}ms ${EASE}, opacity 0.3s ease-out`;
  const collapse = (open) => ({ width: open ? 44 : 0, opacity: open ? 1 : 0, overflow: 'hidden', flex: 'none', transition: reducedMotion() ? 'none' : `width ${GLIDE_MS}ms ${EASE}, opacity 0.25s ease-out, margin ${GLIDE_MS}ms ${EASE}` });
  const mapOn = isMap;

  return (
    <div ref={wrapRef} style={{ position: 'fixed', inset: 0, zIndex: 46, pointerEvents: 'none' }}>
      {show && (
        <div className="bb-mapsurf" data-testid="persistent-search-bar" data-at-home={atHome ? 'true' : 'false'} data-owner={h.owner}
          style={{
            position: 'absolute', left: 0, top: 0, display: 'flex', alignItems: 'center', color: ink,
            width: atHome ? frame.width : 'calc(100% - 32px)', height: atHome ? 46 : 44,
            transform: `translate(${x}px, ${y}px)`,
            opacity: active && !hidden ? 1 : 0, pointerEvents: active && !hidden ? 'auto' : 'none',
            transition: glideT,
          }}>
          <button type="button" onClick={() => fns.back?.()} data-testid={mapOn ? 'map-back' : 'search-back'} tabIndex={atHome ? -1 : 0}
            aria-label={mapOn ? T('Đóng bản đồ', 'Close map') : T('Quay lại', 'Back')}
            style={{ ...photoPill({ position: 'static', borderRadius: '50%' }), ...collapse(!atHome), height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 0, color: ink, marginRight: atHome ? 0 : 8 }}>
            <svg aria-hidden="true" width={17} height={17} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" style={{ flex: 'none' }}><path d="M19 12H5M11 6l-6 6 6 6" /></svg>
          </button>
          <div className="bb-focus-ring" data-testid={mapOn ? 'map-search-box' : 'search-field'}
            style={{ ...photoPill({ position: 'static', borderRadius: 23 }), flex: 1, minWidth: 0, height: '100%', display: 'flex', alignItems: 'center', gap: 8, padding: '0 14px', cursor: 'text', fontSize: 15 }}>
            <svg width={16} height={16} viewBox="0 0 24 24" fill="none" stroke={ink} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.55, flex: 'none' }} aria-hidden="true">
              <circle cx="11" cy="11" r="7" /><path d="M21 21l-4.35-4.35" />
            </svg>
            <input ref={(el) => searchBarStore.attachInput(el)} value={text} onChange={(e) => setText(e.target.value)}
              onFocus={() => searchBarStore.setFocused(true)} onBlur={() => searchBarStore.setFocused(false)}
              onKeyDown={(e) => { if (e.key === 'Enter') { fns.submit?.(text); e.currentTarget.blur(); } }}
              enterKeyHint="search" placeholder={h.placeholder} aria-label={mapOn ? T('Tìm sự kiện trên bản đồ', 'Search events on the map') : T('Tìm kiếm', 'Search')}
              data-testid={mapOn ? 'map-search-input' : 'search-input'} data-bare
              style={{ flex: 1, minWidth: 0, border: 'none', outline: 'none', background: 'transparent', fontSize: 15, color: ink, fontFamily: "'Be Vietnam Pro', sans-serif" }} />
            {text && (
              <button type="button" onMouseDown={(e) => e.preventDefault()} onClick={() => setText('')} data-testid={mapOn ? 'map-search-clear' : 'search-clear'} aria-label={T('Xoá tìm kiếm', 'Clear search')}
                style={{ width: 44, height: 44, marginInlineEnd: -14, border: 'none', background: 'none', cursor: 'pointer', color: ink2, fontSize: 18, lineHeight: 1, flex: 'none' }}>×</button>
            )}
          </div>
          {isMap && bar.focused && (
            <button type="button" onMouseDown={(e) => e.preventDefault()} onClick={() => fns.cancel?.()} data-testid="map-search-cancel"
              style={{ flex: 'none', minHeight: 44, padding: '0 4px 0 10px', border: 'none', background: 'none', color: clay, fontSize: 14.5, fontWeight: 600, cursor: 'pointer', fontFamily: 'inherit', opacity: atHome ? 0 : 1, textShadow: '0 0 6px var(--bb-bg), 0 0 6px var(--bb-bg)' }}>
              {T('Huỷ', 'Cancel')}
            </button>
          )}
          {filtersBtn && (
            <button type="button" onClick={() => fns.filters?.()} data-testid="map-chip-filters" aria-haspopup="dialog" tabIndex={atHome ? -1 : 0}
              aria-label={h.badge ? T(`Bộ lọc, ${h.badge} đang bật`, `Filters, ${h.badge} on`) : T('Bộ lọc', 'Filters')}
              style={{ ...photoPill({ position: 'relative', borderRadius: '50%' }), ...collapse(!atHome), overflow: atHome ? 'hidden' : 'visible', height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 0, color: ink, marginLeft: atHome ? 0 : 8 }}>
              <svg aria-hidden="true" width={19} height={19} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round"><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" /></svg>
              {h.badge > 0 && (
                <span aria-hidden="true" style={{ position: 'absolute', top: -2, right: -2, minWidth: 18, height: 18, padding: '0 5px', boxSizing: 'border-box', borderRadius: 9, background: clay, color: '#fff', fontSize: 11, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', fontVariantNumeric: 'tabular-nums' }}>{h.badge}</span>
              )}
            </button>
          )}
        </div>
      )}
    </div>
  );
}

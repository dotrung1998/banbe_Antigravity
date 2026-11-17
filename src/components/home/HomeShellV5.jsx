// Home from the v5 prototype (note 80), shown with the Simple Shell: one full-bleed dark hero that holds the header
// (wordmark + date, Map, avatar), the paper search bar, the tabs (For You | Tonight | Weekend, + Hosting for hosts)
// and the card rail; then Next up, Browse (types with counts + Find a type) and By type (one photo row per type).
// The header condenses on scroll into one floating bar (owner 2026-11-17): a single scroll-linked progress, written to
// CSS variables, shrinks the wordmark, drops the date and lifts the search pill beside the quick panel. The mobile
// twin is `HomeHeroPinnedHeader` in apps/ios/BanbeApp/Views/HomeShellV5Views.swift.
// Pure view over the lists Home.jsx already builds, so it adds no fetching and no filters of its own.
import { useEffect, useMemo, useRef, useState } from 'react';
import { CategoryGlyph } from './HomeDiscoveryParts.jsx';
import { setThemeColor } from '../../lib/themeColor.js';
import { useReducedMotion } from '../../lib/useReducedMotion.js';
import { categoryDefs } from '../../lib/eventTypes.js';
import SeeAllFanCard from './SeeAllFanCard.jsx';

const NIGHT = '#16140f';
const ON_DARK = 'rgba(255,255,255,.58)';
const TABS = [['foryou', 'Dành cho bạn', 'For You'], ['tonight', 'Tối nay', 'Tonight'], ['weekend', 'Cuối tuần', 'Weekend']];
const TYPE_DEFS = categoryDefs();
const BROWSE_MAX = 5;

const Icon = ({ d, size = 20, sw = 1.5 }) => (
  <svg aria-hidden="true" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">{d}</svg>
);
const MAP = <><path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2z" /><path d="M9 4v14M15 6v14" /></>;
const SEARCH = <><circle cx="11" cy="11" r="7" /><path d="M21 21l-4.35-4.35" /></>;
const PIN = <><path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z" /><circle cx="12" cy="9.5" r="2.5" /></>;
const COG = <><circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" /></>;
const SPARK = <><path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z" /><path d="M19 17v4M17 19h4" /></>;
const MOON = <path d="M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z" />;
const CAL = <><rect x="3.5" y="5" width="17" height="15" rx="2" /><path d="M3.5 10h17M8 3v4M16 3v4" /></>;
const SLIDERS = <><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" /></>;

const initials = (name) => String(name || '').trim().split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0]).join('').toUpperCase() || '·';

/**
 * @param {object} p
 * @param {'foryou'|'tonight'|'weekend'|'hosting'} p.tab
 * @param {Record<string, Array<{key,name,img,dateBadge,priceLabel,metaLine,left}>>} p.lists  hero rails
 * @param {Array} p.items  filtered discovery items [{ key, startsAt, soldOut, ev }] for By type
 * @param {boolean} p.canHost  show the Hosting tab
 */
export default function HomeShellV5({
  T, lang, tab, onTab, lists, items, canHost, user, dateLabel, areaLabel, areaActive = false, filtersActive = false, hasPrefs = true, onClearFilters,
  onOpenEvent, onSeeAll, onMap, onAccount, onSearch, onArea, onFilters, filterSummary, onFindType, onPickType, onSetPrefs, onBrowseAll,
  typeCounts, badgeDate, trStatus, children, hostBody, below, shortlist = null, seeAll = null, onBrowseType = null, browseTotal = null,
}) {
  const rail = useRef(null);
  const [idx, setIdx] = useState(0);
  const headRef = useRef(null);
  const sentinel = useRef(null);
  const [stuck, setStuck] = useState(false);
  // The status-bar band stays night through the collapse (the header is still over the hero); it turns paper only when
  // the floating bar has fully taken over. Avoids a paper strip snapping in above a dark header at the first pixel.
  const [bandNight, setBandNight] = useState(true);
  const bandNightRef = useRef(true);
  const reducedMotion = useReducedMotion();
  // The header (wordmark, Map, avatar, search) is sticky over the content. Its height never changes in layout (the
  // compact state moves inside it), so the hero stays anchored while the shell morphs around the scroll.
  // Dark, readable background only once the content has scrolled under it.
  useEffect(() => {
    const el = sentinel.current;
    if (!el || typeof IntersectionObserver === 'undefined') return undefined;
    const io = new IntersectionObserver(([e]) => setStuck(!e.isIntersecting), { threshold: 0 });
    io.observe(el);
    return () => io.disconnect();
  }, []);
  // Header morph (owner 2026-11-17): one continuous, scroll-linked progress 0 → 1 over the first 96 px. It is written
  // straight to CSS custom properties on the header (no React render per frame) and every moving part is a `calc()` on
  // it, so the wordmark shrinks, the date leaves, the search pill glides up between the wordmark and the quick panel
  // and the surface condenses into one floating bar — one motion, no jump at a threshold. Reduce Motion: two states.
  useEffect(() => {
    const el = sentinel.current;
    const head = headRef.current;
    if (!el || !head) return undefined;
    let raf = 0;
    let last = -1;
    const apply = () => {
      raf = 0;
      // Distance the feed has slid under the pinned header. Measure from the header's own top, not the viewport's,
      // so the morph also works inside the desktop phone frame (whose scroll area starts below the fake status bar).
      const gap = head.getBoundingClientRect().top - el.getBoundingClientRect().top;
      const span = reducedMotion ? 0 : 96;
      const p = span > 0 ? Math.min(1, Math.max(0, gap / span)) : (gap > 8 ? 1 : 0);
      if (Math.abs(p - last) < 0.004) return;
      last = p;
      head.style.setProperty('--hp', p.toFixed(3));
      head.dataset.compact = p > 0.8 ? '1' : '0';
      const night = p < 0.92;
      if (night !== bandNightRef.current) { bandNightRef.current = night; setBandNight(night); }
    };
    const onScroll = () => { if (!raf) raf = requestAnimationFrame(apply); };
    apply();
    window.addEventListener('scroll', onScroll, { passive: true, capture: true });
    window.addEventListener('resize', onScroll, { passive: true });
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('scroll', onScroll, { capture: true });
      window.removeEventListener('resize', onScroll);
    };
  }, [reducedMotion]);
  // Status bar / Dynamic Island tint follows the header's own edge: night while it is still the dark hero, paper once
  // the compact bar floats over the page.
  useEffect(() => { setThemeColor(bandNight); }, [bandNight]);
  useEffect(() => () => setThemeColor(false), []);
  // Same wording as the main Home/Map search bar (HomeSearchBar).
  const placeholder = areaActive ? T(`Tìm sự kiện gần ${areaLabel}`, `Find events near ${areaLabel}`) : T('Tìm sự kiện ở mọi nơi', 'Find events anywhere');
  const hosting = tab === 'hosting';
  const list = hosting ? [] : (lists[tab] || []);
  const cur = list[Math.min(idx, Math.max(list.length - 1, 0))];
  const sig = list.map(e => e.key).join('|');
  useEffect(() => { setIdx(0); if (rail.current) rail.current.scrollLeft = 0; }, [tab, sig]);
  // Rail position: one read per frame, and card width read from layout once (not per scroll event).
  const railRaf = useRef(0);
  const railStep = useRef(0);
  useEffect(() => () => { if (railRaf.current) cancelAnimationFrame(railRaf.current); }, []);
  const onScroll = () => {
    if (railRaf.current || !list.length) return;
    railRaf.current = requestAnimationFrame(() => {
      railRaf.current = 0;
      const el = rail.current;
      if (!el) return;
      if (!railStep.current) { const card = el.firstElementChild; railStep.current = card ? card.getBoundingClientRect().width + 12 : 280; }
      setIdx(Math.min(list.length - 1, Math.max(0, Math.round(el.scrollLeft / railStep.current))));
    });
  };

  const tabs = [...TABS, ...(canHost ? [['hosting', 'Tổ chức', 'Hosting']] : [])];

  // By type: one row per type, most events first; a type with no event is not shown.
  const sections = useMemo(() => {
    const by = new Map();
    for (const it of items) {
      const k = it.ev.catKey || 'other';
      if (!by.has(k)) by.set(k, []);
      by.get(k).push(it);
    }
    return [...by.entries()].sort((a, b) => b[1].length - a[1].length).map(([k, l]) => [k, l.slice(0, 12)]);
  }, [items]);
  const browse = useMemo(() => Object.entries(typeCounts).filter(([, n]) => n > 0).sort((a, b) => b[1] - a[1]).slice(0, BROWSE_MAX), [typeCounts]);
  const typeName = (k) => { const d = TYPE_DEFS.find(x => x.key === k); return d ? (lang === 'en' ? d.en : d.vi) : k; };
  const evN = (n) => (lang === 'en' ? `${n} ${n === 1 ? 'event' : 'events'}` : `${n} sự kiện`);
  const h3 = { fontSize: 19, fontWeight: 400, margin: 0, letterSpacing: '-.01em' };
  // Browse (types with counts): above By type today; with v2.3 (note 81) it closes Home, under the Shortlist.
  const pickType = onBrowseType || onPickType;
  const browseEl = (browse.length > 0 && (
            <div data-testid="home-browse" style={{ padding: '28px 20px 0', scrollMarginTop: 'var(--bb-home-head-h)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
                <h3 style={h3}>{onBrowseType ? T('Duyệt theo loại', 'Browse by type') : T('Khám phá', 'Browse')}</h3>
                {onBrowseType && (
                  <button type="button" data-testid="home-browse-all" onClick={() => onBrowseType('all')}
                    style={{ minHeight: 44, padding: '0 4px', border: 'none', background: 'none', color: 'inherit', fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer' }}>
                    {T('Xem tất cả', 'See all')} <b>{browseTotal}</b>
                  </button>
                )}
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 4 }}>
                {browse.map(([k, n]) => (
                  <button key={k} type="button" data-testid={`home-browse-${k}`} onClick={() => pickType(k)}
                    style={{ padding: '14px 0 12px', border: 'none', borderRadius: 16, background: 'none', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, fontFamily: 'inherit', fontSize: 13, color: 'inherit', cursor: 'pointer' }}>
                    <span style={{ width: 52, height: 52, display: 'grid', placeItems: 'center', marginBottom: 4 }}><CategoryGlyph cat={k} size={28} strokeWidth={1.5} /></span>
                    <span>{typeName(k)}</span><small style={{ fontSize: 11.5, opacity: 0.64 }}>{evN(n)}</small>
                  </button>
                ))}
                <button type="button" data-testid="home-browse-find" onClick={onBrowseType ? () => onBrowseType('all') : onFindType}
                  style={{ padding: '14px 0 12px', border: 'none', borderRadius: 16, background: 'none', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, fontFamily: 'inherit', fontSize: 13, color: 'inherit', cursor: 'pointer' }}>
                  <span style={{ width: 52, height: 52, display: 'grid', placeItems: 'center', marginBottom: 4 }}><Icon d={SEARCH} size={28} /></span>
                  <span>{T('Tìm một loại', 'Find a type')}</span><small style={{ fontSize: 11.5, opacity: 0.64 }}>{T(`${TYPE_DEFS.length} loại`, `${TYPE_DEFS.length} types`)}</small>
                </button>
              </div>
            </div>
          ));

  return (
    // v2.3 (note 81): an explicit theme ink. Without it the content below the hero inherits the body's light-theme ink,
    // which is unreadable in dark mode (an existing bug with the switch off, left as it is there).
    <div data-testid="home-shell-v5" data-tab={tab} style={{ position: 'relative', color: shortlist ? 'var(--bb-fg)' : undefined, '--bb-home-head-h': 'calc(152px + var(--bb-safe-top, env(safe-area-inset-top, 0px)))' }}>
      {/* Pull-to-refresh: the whole screen translates down, so the gap it opens above Home must be the hero's night
          colour, not paper. This layer hangs above the content (clipped by the scroller at rest, visible only in the
          gap while pulling/holding/springing back). */}
      <div aria-hidden data-testid="home-pull-backdrop" style={{ position: 'absolute', left: 0, right: 0, bottom: '100%', height: 320, background: 'linear-gradient(180deg,#16140f,#2b2721)', pointerEvents: 'none' }} />
      <div ref={sentinel} aria-hidden style={{ height: 1, marginBottom: -1 }} />
      <div ref={headRef} className="bb-home-head" data-testid="home-sticky-header" data-stuck={stuck || undefined}>
        <div aria-hidden className="bb-home-head__scrim" />
        <div aria-hidden className="bb-home-head__surface" />
        <div className="bb-home-head__brand">
          <img src="/banbe-wordmark.png" alt="banbe" data-testid="home-title" crossOrigin="anonymous" className="bb-home-head__wordmark" style={{ filter: 'invert(1)' }} />
          <div className="bb-home-head__date" data-testid="home-date">{dateLabel}</div>
        </div>
        <div className="bb-home-head__quick">
          <button type="button" onClick={onMap} aria-label={T('Bản đồ', 'Map')} data-testid="home-map-button" className="bb-home-head__glass"><Icon d={MAP} size={21} /></button>
          <button type="button" onClick={onAccount} aria-label={T('Tài khoản và cài đặt nhanh', 'Account and quick settings')} data-testid="home-avatar-button" className="bb-home-head__avatar">
            <span className="bb-home-head__disc">{user ? initials(user.name) : <Icon d={<><circle cx="12" cy="8" r="4" /><path d="M4 21a8 8 0 0 1 16 0" /></>} size={19} />}</span>
            <span aria-hidden className="bb-home-head__gear"><Icon d={COG} size={11} sw={1.8} /></span>
          </button>
        </div>
        <div data-testid="home-search-row" className="bb-home-head__searchrow">
          <button type="button" onClick={onSearch} data-testid="home-search-bar" aria-label={T('Tìm sự kiện', 'Search events')} className="bb-home-head__searchbtn">
            <Icon d={SEARCH} size={19} />
            <span className="bb-home-head__hint">{placeholder}</span>
          </button>
          <span aria-hidden className="bb-home-head__divider" />
          <button type="button" onClick={onArea} data-testid="home-area-toggle" aria-haspopup="menu" aria-label={T(`Khu vực: ${areaLabel}. Đổi khu vực`, `Area: ${areaLabel}. Change area`)} className="bb-home-head__areabtn">
            <Icon d={PIN} size={16} />
            {areaActive
              ? <span data-testid="home-area-label" className="bb-home-head__arealabel">{areaLabel}</span>
              : <span className="bb-home-head__arealabel bb-home-head__areafallback">{T('Mọi nơi', 'Everywhere')}</span>}
            <span aria-hidden className="bb-home-head__chev">▾</span>
          </button>
        </div>
      </div>
      <section data-testid="home-photo-hero" data-tab={tab} aria-label={T('Gợi ý nổi bật', 'Featured events')}
        style={{ position: 'relative', overflow: 'hidden', contain: 'paint', background: NIGHT, color: '#fff', marginTop: 'calc(var(--bb-home-head-h) * -1)' }}>
        <div aria-hidden style={{ position: 'absolute', inset: -30, transform: 'scale(1.1) translateZ(0)', willChange: 'transform', backfaceVisibility: 'hidden',
          background: cur?.img ? `center/cover no-repeat url("${cur.img}")` : 'linear-gradient(180deg,#2b2721,#16140f)',
          filter: cur?.img ? 'blur(30px) brightness(.58) saturate(1.08)' : 'none' }} />
        <div aria-hidden style={{ position: 'absolute', inset: 0, pointerEvents: 'none',
          background: 'linear-gradient(180deg, rgba(22,20,15,.62) 0%, rgba(22,20,15,.16) 36%, rgba(22,20,15,.5) 74%, #16140f 100%)' }} />
        <div style={{ position: 'relative', padding: 'var(--bb-home-head-h) 0 0' }}>
          <div role="tablist" data-testid="home-hero-tabs" style={{ display: 'flex', gap: 20, padding: '18px 24px 4px', overflowX: 'auto', scrollbarWidth: 'none', whiteSpace: 'nowrap' }}>
            {tabs.map(([k, vi, en]) => (
              <button key={k} type="button" role="tab" aria-selected={tab === k} data-testid={`home-hero-tab-${k}`} onClick={() => onTab(k)}
                style={{ flex: 'none', border: 'none', background: 'none', fontFamily: 'inherit', fontSize: 17, padding: '6px 0', cursor: 'pointer', color: tab === k ? '#fff' : ON_DARK,
                  fontWeight: tab === k ? 500 : 300, borderBottom: `2px solid ${tab === k ? '#fff' : 'transparent'}` }}>{T(vi, en)}</button>
            ))}
          </div>
          {!hosting && (
            <>
              <div ref={rail} onScroll={onScroll} data-hscroll data-testid="home-hero-rail"
                style={{ display: 'flex', gap: 12, overflowX: 'auto', scrollSnapType: 'x mandatory', padding: '20px 24px 0', scrollPaddingLeft: 24, scrollbarWidth: 'none' }}>
                {list.map((e, i) => (
                  <button key={e.key} type="button" data-testid={`home-hero-card-${e.key}`} onClick={() => onOpenEvent(e.key)}
                    style={{ flex: '0 0 268px', height: 360, borderRadius: 16, position: 'relative', overflow: 'hidden', scrollSnapAlign: 'start', border: 'none', padding: 0, textAlign: 'left',
                      color: '#fff', fontFamily: 'inherit', cursor: 'pointer', opacity: i === idx ? 1 : 0.6, transition: 'opacity .3s', background: e.img ? `#2a2620 center/cover no-repeat url("${e.img}")` : '#2a2620' }}>
                    <span aria-hidden style={{ position: 'absolute', inset: 0, background: 'linear-gradient(180deg,rgba(0,0,0,.25) 0%,rgba(0,0,0,0) 30%,rgba(0,0,0,.05) 50%,rgba(0,0,0,.78) 100%)' }} />
                    <span style={{ position: 'absolute', top: 12, left: 12, right: 12, display: 'flex', justifyContent: 'space-between' }}>
                      {e.dateBadge && <span style={{ height: 28, padding: '0 10px', borderRadius: 999, background: 'rgba(247,244,236,.85)', color: '#1B1916', fontSize: 11.5, fontWeight: 700, display: 'flex', alignItems: 'center', letterSpacing: '.02em', textTransform: 'uppercase' }}>{e.dateBadge}</span>}
                      <span style={{ height: 28, padding: '0 10px', borderRadius: 999, background: 'rgba(247,244,236,.85)', color: '#1B1916', fontSize: 11.5, fontWeight: 700, display: 'flex', alignItems: 'center', letterSpacing: '.02em' }}>{e.saved ? T('ĐÃ LƯU', 'SAVED') : T('LƯU', 'SAVE')}</span>
                    </span>
                    <span style={{ position: 'absolute', left: 16, right: 16, bottom: 16, display: 'block' }}>
                      {e.metaLine && <span style={{ display: 'block', fontSize: 11, letterSpacing: '.12em', textTransform: 'uppercase', opacity: 0.85, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{e.metaLine}</span>}
                      <span style={{ display: 'block', fontFamily: "var(--bb-font-title, 'Be Vietnam Pro', system-ui, sans-serif)", fontSize: 26, fontWeight: 300, lineHeight: 1.12, margin: '6px 0', letterSpacing: '-.01em' }}>{e.name}</span>
                      <span style={{ display: 'flex', justifyContent: 'space-between', gap: 8, fontSize: 13, opacity: 0.9 }}><span>{e.priceLabel}</span><span>{e.left}</span></span>
                    </span>
                  </button>
                ))}
                {list.length > 0 && seeAll && (
                  <SeeAllFanCard photos={list.map(e => e.img)} label={seeAll.label} count={seeAll.count} onOpen={() => onSeeAll(tab)} T={T} />
                )}
                {list.length > 0 && !seeAll && (
                  <button type="button" data-testid="home-hero-see-all" onClick={() => onSeeAll(tab)}
                    style={{ flex: '0 0 268px', height: 360, borderRadius: 16, scrollSnapAlign: 'start', border: '1px dashed rgba(255,255,255,.3)', background: 'rgba(255,255,255,.08)', color: '#fff', fontFamily: 'inherit', fontSize: 15, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 10, cursor: 'pointer' }}>
                    <span aria-hidden style={{ fontSize: 26 }}>→</span><span>{T('Xem tất cả', 'See all')}</span>
                  </button>
                )}
                {!list.length && (() => {
                  const areaTxt = areaLabel;
                  const narrowed = areaActive || filtersActive;
                  const changeArea = (e) => onArea?.(e);
                  const base = tab === 'foryou'
                    ? { icon: SPARK, text: T('Chưa có gợi ý. Trả lời vài câu hỏi để chúng tôi chọn sự kiện hợp với bạn.', 'No picks yet. Answer a few questions and we will pick events that fit you.'),
                        cta: T('Đặt sở thích', 'Set your preferences'), go: onSetPrefs }
                    : tab === 'tonight'
                      ? { icon: MOON, text: T('Tối nay chưa có sự kiện nào.', 'Nothing on tonight.'), cta: T('Xem cuối tuần', 'See this weekend'), go: () => onTab('weekend') }
                      : { icon: CAL, text: T('Cuối tuần này chưa có sự kiện nào.', 'Nothing on this weekend.'), cta: T('Xem tất cả sự kiện', 'Browse all events'), go: onBrowseAll };
                  let E = { ...base, area: false, clear: null, prefs: false };
                  if (narrowed && tab === 'foryou') {
                    E = { icon: SPARK, area: true, go: changeArea, cta: T('Đổi khu vực', 'Change area'), prefs: !hasPrefs,
                      text: areaActive ? T(`Chưa có gợi ý ở ${areaTxt}. Thử khu vực khác hoặc bỏ bộ lọc.`, `No picks in ${areaTxt}. Try another area or clear your filters.`)
                        : T('Chưa có gợi ý khớp bộ lọc của bạn. Thử bỏ bớt bộ lọc.', 'No picks match your filters. Try clearing some.'),
                      clear: areaActive ? T(`Xem mọi sự kiện`, 'Show all events') : T('Bỏ bộ lọc', 'Clear filters') };
                    if (!areaActive) E = { ...E, area: false, go: onClearFilters, cta: T('Bỏ bộ lọc', 'Clear filters'), clear: null };
                  } else if (narrowed && areaActive) {
                    E = { ...base, area: true, clear: T('Xem mọi sự kiện', 'Show all events'), text: tab === 'tonight' ? T(`Tối nay chưa có sự kiện nào ở ${areaTxt}.`, `Nothing on tonight in ${areaTxt}.`) : T(`Cuối tuần này chưa có sự kiện nào ở ${areaTxt}.`, `Nothing on this weekend in ${areaTxt}.`) };
                  }
                  const sec = { minHeight: 44, padding: '0 16px', borderRadius: 999, border: '1px solid rgba(255,255,255,.35)', background: 'none', color: '#fff', fontFamily: 'inherit', fontSize: 14, fontWeight: 500, cursor: 'pointer' };
                  return (
                    <div data-testid="home-hero-empty" data-empty-tab={tab} data-empty-area={areaActive || undefined}
                      style={{ flex: '0 0 268px', height: 360, boxSizing: 'border-box', borderRadius: 16, border: '1px dashed rgba(255,255,255,.3)', background: 'rgba(255,255,255,.08)', scrollSnapAlign: 'start',
                        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 10, textAlign: 'center', padding: 20, fontSize: 15, lineHeight: 1.45 }}>
                      <Icon d={E.icon} size={28} sw={1.2} />
                      <span>{E.text}</span>
                      <button type="button" data-testid={E.area && tab === 'foryou' ? 'home-hero-empty-area' : 'home-hero-empty-cta'} onClick={(e) => E.go?.(e)}
                        style={{ minHeight: 44, padding: '0 20px', borderRadius: 999, border: 'none', background: 'rgba(247,244,236,.92)', color: '#1B1916', fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer' }}>{E.cta}</button>
                      {E.area && tab !== 'foryou' && (
                        <button type="button" data-testid="home-hero-empty-area" onClick={changeArea} style={sec}>{T('Đổi khu vực', 'Change area')}</button>
                      )}
                      {E.clear && (
                        <button type="button" data-testid="home-hero-empty-clear" onClick={() => onClearFilters?.()} style={sec}>{E.clear}</button>
                      )}
                      {E.prefs && (
                        <button type="button" data-testid="home-hero-empty-prefs" onClick={() => onSetPrefs?.()}
                          style={{ minHeight: 44, padding: '0 8px', border: 'none', background: 'none', color: ON_DARK, fontFamily: 'inherit', fontSize: 13.5, textDecoration: 'underline', cursor: 'pointer' }}>{T('Đặt sở thích', 'Set your preferences')}</button>
                      )}
                    </div>
                  );
                })()}
              </div>
              <div aria-hidden style={{ display: 'flex', justifyContent: 'center', gap: 6, padding: '18px 0 22px' }}>
                {list.map((e, i) => <i key={e.key} style={{ width: i === idx ? 30 : 20, height: 3, borderRadius: 2, background: i === idx ? '#fff' : 'rgba(255,255,255,.32)', transition: 'width .2s' }} />)}
              </div>
            </>
          )}
          {hosting && <div style={{ height: 16 }} />}
        </div>
      </section>

      {hosting ? hostBody : (
        <>
          {children}
          {!shortlist && browseEl}
          {shortlist}
          {shortlist && browseEl}
          {!shortlist && (<>
          <div data-testid="home-by-type" style={{ padding: '28px 20px 0' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <h3 style={h3}>{T('Theo loại', 'By type')}</h3>
              <button type="button" onClick={onFilters} data-testid="home-filters-button" aria-label={T('Bộ lọc', 'Filters')}
                style={{ width: 38, height: 38, borderRadius: '50%', border: 'none', background: 'var(--bb-block, rgba(var(--bb-fg-rgb),.06))', color: 'inherit', display: 'grid', placeItems: 'center', cursor: 'pointer' }}><Icon d={SLIDERS} size={18} /></button>
            </div>
            <button type="button" onClick={onFilters} data-testid="home-filter-summary"
              style={{ display: 'block', width: 'fit-content', maxWidth: '100%', margin: '8px 0 0', padding: '0 0 3px', border: 'none', borderBottom: '1px solid var(--bb-rule)', background: 'none', color: 'inherit', fontFamily: 'inherit', fontSize: 13, opacity: 0.72, cursor: 'pointer', textAlign: 'left' }}>{filterSummary}</button>
          </div>
          {sections.length === 0 && (
            <div data-testid="home-by-type-empty" style={{ padding: '24px 20px 0' }}>
              <div style={{ fontSize: 17 }}>{T('Chưa có gì khớp', 'Nothing matches yet')}</div>
              <p style={{ fontSize: 14, opacity: 0.7, margin: '4px 0 0' }}>{T('Bộ lọc đang ẩn mọi sự kiện. Nới rộng để xem thêm.', 'Your filters hide every event. Widen them to see more.')}</p>
            </div>
          )}
          {sections.map(([k, l]) => (
            <div key={k} data-testid={`home-type-${k}`} style={{ marginTop: 26 }}>
              <button type="button" onClick={() => onPickType(k)} style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', padding: '0 20px', border: 'none', background: 'none', color: 'inherit', fontFamily: 'inherit', cursor: 'pointer', textAlign: 'left', marginBottom: 12 }}>
                <span style={{ display: 'grid', placeItems: 'center' }}><CategoryGlyph cat={k} size={20} strokeWidth={1.5} /></span>
                <span style={{ fontSize: 17, fontWeight: 600 }}>{typeName(k)}</span>
                <small style={{ fontSize: 14, opacity: 0.64, flex: 1 }}>{l.length}</small>
                <span aria-hidden style={{ opacity: 0.5 }}>›</span>
              </button>
              <div data-hscroll style={{ display: 'flex', gap: 12, overflowX: 'auto', padding: '0 20px', scrollbarWidth: 'none' }}>
                {l.map(it => {
                  const e = it.ev;
                  return (
                    <button key={it.key} type="button" data-testid={`home-event-${it.key}`} onClick={() => onOpenEvent(it.key)}
                      style={{ flex: '0 0 168px', textAlign: 'left', border: 'none', background: 'none', padding: 0, color: 'inherit', fontFamily: 'inherit', cursor: 'pointer' }}>
                      <div style={{ position: 'relative', height: 204, borderRadius: 14, background: e.img ? `var(--bb-block, #EEE8DA) center/cover no-repeat url("${e.img}")` : 'var(--bb-block, #EEE8DA)' }}>
                        <span style={{ position: 'absolute', top: 8, left: 8, height: 26, padding: '0 10px', borderRadius: 999, background: 'rgba(247,244,236,.9)', color: '#1B1916', fontSize: 11.5, fontWeight: 700, display: 'flex', alignItems: 'center', textTransform: 'uppercase' }}>{badgeDate(it.startsAt, e.isReal ? e.tz : null)}</span>
                        {it.soldOut && <span style={{ position: 'absolute', left: 8, bottom: 8, height: 26, padding: '0 12px', borderRadius: 999, background: 'var(--bb-alert)', color: 'var(--bb-on-alert, #fff)', fontSize: 11.5, fontWeight: 700, display: 'flex', alignItems: 'center' }}>{T('HẾT CHỖ', 'SOLD OUT')}</span>}
                      </div>
                      <div style={{ fontSize: 15, marginTop: 10, lineHeight: 1.25 }}>{e.name}</div>
                      <div style={{ fontSize: 12, opacity: 0.64, marginTop: 3 }}>{[e.isReal ? e.area : e.locationLabel, it.priceVnd === 0 ? T('Miễn phí', 'Free') : trStatus(e.price)].filter(Boolean).join(' · ')}</div>
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
          </>)}
          {below}
          {/* Clearance for the floating dock, after the last section so nothing sits below a dead gap. */}
          <div style={{ height: 120 }} />
        </>
      )}
    </div>
  );
}

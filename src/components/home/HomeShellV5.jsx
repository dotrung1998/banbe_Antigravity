// Home from the v5 prototype (note 80), shown with the Simple Shell: one full-bleed dark hero that holds the header
// (wordmark + date, Map, avatar), the glass search bar, the tabs (For You | Tonight | Weekend, + Hosting for hosts)
// and the card rail; then Next up, Browse (types with counts + Find a type) and By type (one photo row per type).
// Pure view over the lists Home.jsx already builds, so it adds no fetching and no filters of its own.
import { useEffect, useMemo, useRef, useState } from 'react';
import { CategoryGlyph } from './HomeDiscoveryParts.jsx';
import { categoryDefs } from '../../lib/eventTypes.js';

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
  T, lang, tab, onTab, lists, items, canHost, user, dateLabel, areaLabel,
  onOpenEvent, onSeeAll, onMap, onAccount, onSearch, onArea, onFilters, filterSummary, onFindType, onPickType,
  typeCounts, badgeDate, trStatus, children, hostBody, below,
}) {
  const rail = useRef(null);
  const [idx, setIdx] = useState(0);
  const hosting = tab === 'hosting';
  const list = hosting ? [] : (lists[tab] || []);
  const cur = list[Math.min(idx, Math.max(list.length - 1, 0))];
  const sig = list.map(e => e.key).join('|');
  useEffect(() => { setIdx(0); if (rail.current) rail.current.scrollLeft = 0; }, [tab, sig]);
  const onScroll = () => {
    const el = rail.current;
    if (!el || !list.length) return;
    const card = el.firstElementChild;
    const step = card ? card.getBoundingClientRect().width + 12 : 280;
    setIdx(Math.min(list.length - 1, Math.max(0, Math.round(el.scrollLeft / step))));
  };

  const tabs = [...TABS, ...(canHost ? [['hosting', 'Tổ chức', 'Hosting']] : [])];
  const glass = { border: '1px solid rgba(255,255,255,.18)', background: 'rgba(255,255,255,.14)', backdropFilter: 'blur(12px)', WebkitBackdropFilter: 'blur(12px)' };

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

  return (
    <div data-testid="home-shell-v5" data-tab={tab}>
      <section data-testid="home-photo-hero" data-tab={tab} aria-label={T('Gợi ý nổi bật', 'Featured events')}
        style={{ position: 'relative', overflow: 'hidden', background: NIGHT, color: '#fff' }}>
        <div aria-hidden style={{ position: 'absolute', inset: -30, transform: 'scale(1.1)', transition: 'background-image .5s',
          background: cur?.img ? `center/cover no-repeat url("${cur.img}")` : 'linear-gradient(180deg,#2b2721,#16140f)',
          filter: cur?.img ? 'blur(18px) brightness(.45) saturate(.9)' : 'none' }} />
        <div style={{ position: 'relative', padding: '20px 0 0' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', minHeight: 48, padding: '0 20px' }}>
            <div>
              <img src="/banbe-wordmark.png" alt="banbe" data-testid="home-title" crossOrigin="anonymous" style={{ height: 30, width: 'auto', display: 'block', filter: 'invert(1)' }} />
              <div style={{ fontSize: 14, color: 'rgba(255,255,255,.8)', marginTop: 4 }}>{dateLabel}</div>
            </div>
            <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
              <button type="button" onClick={onMap} aria-label={T('Bản đồ', 'Map')} data-testid="home-map-button"
                style={{ ...glass, width: 42, height: 42, borderRadius: '50%', display: 'grid', placeItems: 'center', color: '#fff', cursor: 'pointer', padding: 0 }}><Icon d={MAP} size={22} /></button>
              <button type="button" onClick={onAccount} aria-label={T('Tài khoản và cài đặt nhanh', 'Account and quick settings')} data-testid="home-avatar-button"
                style={{ position: 'relative', width: 42, height: 42, border: 'none', background: 'none', padding: 0, cursor: 'pointer' }}>
                <span style={{ width: 42, height: 42, borderRadius: '50%', background: 'var(--bb-clay, #9C5B3B)', color: '#fff', fontSize: 14, fontWeight: 700, display: 'grid', placeItems: 'center', border: '1.5px solid rgba(255,255,255,.9)', boxSizing: 'border-box' }}>{user ? initials(user.name) : <Icon d={<><circle cx="12" cy="8" r="4" /><path d="M4 21a8 8 0 0 1 16 0" /></>} size={20} />}</span>
                <span aria-hidden style={{ position: 'absolute', right: -3, bottom: -3, width: 18, height: 18, borderRadius: '50%', background: NIGHT, color: '#fff', display: 'grid', placeItems: 'center', border: '1px solid rgba(255,255,255,.5)' }}><Icon d={COG} size={11} sw={1.8} /></span>
              </button>
            </div>
          </div>
          <div data-testid="home-search-row" style={{ display: 'flex', margin: '10px 20px 0', height: 46, borderRadius: 999, ...glass, alignItems: 'center', color: 'rgba(255,255,255,.75)', boxSizing: 'border-box' }}>
            <button type="button" onClick={onSearch} data-testid="home-search-bar" aria-label={T('Tìm sự kiện', 'Search events')}
              style={{ flex: 1, minWidth: 0, height: '100%', display: 'flex', alignItems: 'center', gap: 10, padding: '0 8px 0 16px', border: 'none', background: 'none', color: 'inherit', fontFamily: 'inherit', fontSize: 15, cursor: 'text', textAlign: 'left' }}>
              <Icon d={SEARCH} size={19} /><span style={{ flex: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{T('Tìm sự kiện', 'Search events')}</span>
            </button>
            <button type="button" onClick={onArea} data-testid="home-area-toggle" aria-haspopup="menu" aria-label={T(`Khu vực: ${areaLabel}`, `Area: ${areaLabel}`)}
              style={{ flex: 'none', height: 26, display: 'flex', alignItems: 'center', gap: 6, color: '#fff', fontFamily: 'inherit', fontSize: 15, fontWeight: 500, background: 'none', border: 'none', borderLeft: '1px solid rgba(255,255,255,.25)', padding: '0 14px 0 12px', cursor: 'pointer' }}>
              <Icon d={PIN} size={17} /><span aria-hidden style={{ fontSize: 10 }}>▾</span>
            </button>
          </div>
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
                      <span style={{ display: 'block', fontSize: 26, fontWeight: 300, lineHeight: 1.12, margin: '6px 0', letterSpacing: '-.01em' }}>{e.name}</span>
                      <span style={{ display: 'flex', justifyContent: 'space-between', gap: 8, fontSize: 13, opacity: 0.9 }}><span>{e.priceLabel}</span><span>{e.left}</span></span>
                    </span>
                  </button>
                ))}
                {list.length > 0 && (
                  <button type="button" data-testid="home-hero-see-all" onClick={() => onSeeAll(tab)}
                    style={{ flex: '0 0 268px', height: 360, borderRadius: 16, scrollSnapAlign: 'start', border: '1px dashed rgba(255,255,255,.3)', background: 'rgba(255,255,255,.08)', color: '#fff', fontFamily: 'inherit', fontSize: 15, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 10, cursor: 'pointer' }}>
                    <span aria-hidden style={{ fontSize: 26 }}>→</span><span>{T('Xem tất cả', 'See all')}</span>
                  </button>
                )}
                {!list.length && (
                  <div data-testid="home-hero-empty" style={{ flex: '1 0 100%', minHeight: 140, borderRadius: 16, border: '1px dashed rgba(255,255,255,.3)', background: 'rgba(255,255,255,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', textAlign: 'center', padding: 20, fontSize: 14, lineHeight: 1.5 }}>
                    {tab === 'foryou' ? T('Chưa có gợi ý. Trả lời vài câu hỏi trong Tài khoản › Sở thích sự kiện.', 'No picks yet. Answer a few questions in Account › Event preferences.')
                      : tab === 'tonight' ? T('Tối nay chưa có sự kiện nào.', 'Nothing on tonight.') : T('Cuối tuần này chưa có sự kiện nào.', 'Nothing on this weekend.')}
                  </div>
                )}
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
          {browse.length > 0 && (
            <div data-testid="home-browse" style={{ padding: '28px 20px 0' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 14 }}><h3 style={h3}>{T('Khám phá', 'Browse')}</h3></div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 4 }}>
                {browse.map(([k, n]) => (
                  <button key={k} type="button" data-testid={`home-browse-${k}`} onClick={() => onPickType(k)}
                    style={{ padding: '14px 0 12px', border: 'none', borderRadius: 16, background: 'none', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, fontFamily: 'inherit', fontSize: 13, color: 'inherit', cursor: 'pointer' }}>
                    <span style={{ width: 52, height: 52, display: 'grid', placeItems: 'center', marginBottom: 4 }}><CategoryGlyph cat={k} size={28} strokeWidth={1.5} /></span>
                    <span>{typeName(k)}</span><small style={{ fontSize: 11.5, opacity: 0.64 }}>{evN(n)}</small>
                  </button>
                ))}
                <button type="button" data-testid="home-browse-find" onClick={onFindType}
                  style={{ padding: '14px 0 12px', border: 'none', borderRadius: 16, background: 'none', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, fontFamily: 'inherit', fontSize: 13, color: 'inherit', cursor: 'pointer' }}>
                  <span style={{ width: 52, height: 52, display: 'grid', placeItems: 'center', marginBottom: 4 }}><Icon d={SEARCH} size={28} /></span>
                  <span>{T('Tìm một loại', 'Find a type')}</span><small style={{ fontSize: 11.5, opacity: 0.64 }}>{T(`${TYPE_DEFS.length} loại`, `${TYPE_DEFS.length} types`)}</small>
                </button>
              </div>
            </div>
          )}
          <div data-testid="home-by-type" style={{ padding: '28px 20px 0' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <h3 style={h3}>{T('Theo loại', 'By type')}</h3>
              <button type="button" onClick={onFilters} data-testid="home-filters-button" aria-label={T('Bộ lọc', 'Filters')}
                style={{ width: 38, height: 38, borderRadius: '50%', border: 'none', background: 'var(--bb-block, rgba(var(--bb-fg-rgb),.06))', color: 'inherit', display: 'grid', placeItems: 'center', cursor: 'pointer' }}><Icon d={SLIDERS} size={18} /></button>
            </div>
            <button type="button" onClick={onFilters} data-testid="home-filter-summary"
              style={{ display: 'block', margin: '8px 0 0', padding: '0 0 3px', border: 'none', borderBottom: '1px solid var(--bb-rule)', background: 'none', color: 'inherit', fontFamily: 'inherit', fontSize: 13, opacity: 0.72, cursor: 'pointer', textAlign: 'left' }}>{filterSummary}</button>
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
          {below}
          {/* Clearance for the floating dock, after the last section so nothing sits below a dead gap. */}
          <div style={{ height: 120 }} />
        </>
      )}
    </div>
  );
}

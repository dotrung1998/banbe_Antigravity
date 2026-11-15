// Browse by type / See all (v2.3, note 81, switch home_v23). One screen for both: "Browse by type" lists the whole
// catalogue, "See all" one Home tab (For You, Tonight, Weekend) with type chips counted inside that tab. Under the title
// a deck of host faces replaces the description (a tap lists the hosts, a host opens their real profile). The magnifier
// left of Map turns the title into a search field (the native keyboard, Done keeps the query as the list's filter,
// × clears it). Its own Filters (When, Price, Seats). The list pages four rows at a time with the onboarding-style swipe
// signs and ends with an end card. Pure view: Home.jsx passes the scope's items (the same discovery items Home uses, so
// there is no second filter path) and the handlers. Rules: src/lib/browse.js, src/lib/pager.js.
import { useEffect, useMemo, useRef, useState } from 'react';
import Pager from '../components/list/Pager.jsx';
import EndCard from '../components/list/EndCard.jsx';
import EventRowV23, { ROW_HEIGHT } from '../components/list/EventRowV23.jsx';
import HostDeck from '../components/browse/HostDeck.jsx';
import HostListSheet from './sheets/HostListSheet.jsx';
import HomeFilterSheet from './sheets/HomeFilterSheet.jsx';
import { CategoryGlyph } from '../components/home/HomeDiscoveryParts.jsx';
import { browseList, typeCounts, hostsOf, browseEnd, browseFilters, browseFilterCount } from '../lib/browse.js';
import { categoryDefs } from '../lib/eventTypes.js';
import { useReducedMotion } from '../lib/useReducedMotion.js';
import { TAB_LABEL } from '../components/home/ShortlistV23.jsx';

const TYPE_DEFS = categoryDefs();
const Icon = ({ d, size = 20 }) => (
  <svg aria-hidden="true" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">{d}</svg>
);
const BACK = <path d="m15 5-7 7 7 7" />;
const SEARCH = <><circle cx="11" cy="11" r="6.5" /><path d="m16 16 4 4" /></>;
const CLOSE = <path d="M6 6l12 12M18 6 6 18" />;
const MAP = <><path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2z" /><path d="M9 4v14M15 6v14" /></>;
const SLIDERS = <><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" /></>;

/**
 * @param {object} p
 * @param {'all'|'foryou'|'tonight'|'weekend'} p.scope
 * @param {string} p.type  'all' or a type key
 * @param {Array} p.items  the scope's discovery items, in the scope's order
 * @param {(it) => object} p.shapeRow  discovery item → EventRowV23 row
 */
export default function Browse({ T, lang, scope, type, query, filters, items, now, areaLabel, shapeRow,
  onType, onQuery, onFilters, onBack, onOpenEvent, onOpenHost, onMap, onHost }) {
  const reduced = useReducedMotion();
  const tabLabel = scope !== 'all' ? (TAB_LABEL[scope] || null) : null;
  const typeDef = TYPE_DEFS.find(d => d.key === type) || null;
  const typeName = typeDef ? { vi: typeDef.vi, en: typeDef.en } : null;
  const counts = useMemo(() => typeCounts(items), [items]);
  // A type with nothing in this scope falls back to every type (a stale link, or a tab that changed).
  const effType = type !== 'all' && !counts[type] ? 'all' : type;
  const chips = useMemo(() => TYPE_DEFS.filter(d => counts[d.key] > 0).sort((a, b) => counts[b.key] - counts[a.key]), [counts]);
  const { list, hidden } = useMemo(() => browseList({ items, type: effType, query, filters, now }), [items, effType, query, filters, now]);
  const hosts = useMemo(() => hostsOf(browseList({ items, type: effType, query: '', filters: null, now }).list, lang), [items, effType, now, lang]);
  const rows = useMemo(() => list.map(shapeRow), [list, shapeRow]);
  const nFilters = browseFilterCount(filters);
  const others = chips.filter(d => d.key !== effType).map(d => ({ key: d.key, name: { vi: d.vi, en: d.en }, count: counts[d.key] }));
  const card = browseEnd({ type: effType, typeName: effType === 'all' ? null : typeName, list, hidden, query, others });

  const title = effType !== 'all' && typeName ? T(typeName.vi, typeName.en)
    : tabLabel ? T(tabLabel.vi, tabLabel.en) : T('Mọi sự kiện', 'All events');
  const kicker = tabLabel ? T(`Xem tất cả · ${tabLabel.vi}`, `See all · ${tabLabel.en}`) : T('Duyệt theo loại', 'Browse by type');
  const navTitle = query.trim() ? `“${query.trim()}” · ${title}` : tabLabel && effType !== 'all' ? `${T(tabLabel.vi, tabLabel.en)} · ${title}` : title;

  const [finding, setFinding] = useState(false);
  const [hostsOpen, setHostsOpen] = useState(false);
  const [filtersOpen, setFiltersOpen] = useState(false);
  const inputRef = useRef(null);
  const scrollRef = useRef(null);
  useEffect(() => { if (finding) inputRef.current?.focus({ preventScroll: true }); }, [finding]);
  // Pushed in over Home from the right (Reduced: no slide).
  const enter = reduced ? undefined : 'bbV23PushIn 0.42s cubic-bezier(.32,.72,0,1) both';
  const navBtn = { width: 44, height: 44, borderRadius: '50%', border: 'none', background: 'rgba(var(--bb-fg-rgb),0.07)', color: 'inherit', display: 'grid', placeItems: 'center', cursor: 'pointer', flex: 'none' };

  const onEnd = (act) => {
    if (act === 'clear-filters') onFilters(null);
    else if (act === 'clear-search') { onQuery(''); setFinding(false); }
    else if (act.startsWith('type:')) { onType(act.slice(5)); scrollRef.current?.scrollIntoView({ block: 'start', behavior: reduced ? 'auto' : 'smooth' }); }
    else if (act === 'map') onMap(effType);
    else if (act === 'host') onHost();
  };

  return (
    <div data-testid="browse-screen" data-scope={scope} data-type={effType} style={{ minHeight: '100%', background: 'var(--bb-bg)', color: 'var(--bb-fg)', animation: enter }}>
      <style>{'@keyframes bbV23PushIn { from { transform: translateX(28%); opacity: .4; } to { transform: none; opacity: 1; } }'}</style>
      <header data-testid="browse-nav" style={{ position: 'sticky', top: 0, zIndex: 5, display: 'flex', alignItems: 'center', gap: 8, padding: '8px 12px', background: 'var(--bb-bg)', borderBottom: '1px solid var(--bb-rule)' }}>
        <button type="button" onClick={onBack} aria-label={T('Về Trang chủ', 'Back to Home')} data-testid="browse-back" style={navBtn}><Icon d={BACK} /></button>
        {finding ? (
          <form role="search" onSubmit={(e) => { e.preventDefault(); inputRef.current?.blur(); setFinding(false); }} style={{ flex: 1, minWidth: 0 }}>
            <input ref={inputRef} type="search" value={query} onChange={(e) => onQuery(e.target.value)} enterKeyHint="done" autoComplete="off"
              onKeyDown={(e) => { if (e.key === 'Escape') { onQuery(''); setFinding(false); } }}
              placeholder={T('Tìm trong các sự kiện này', 'Search these events')} aria-label={T('Tìm trong các sự kiện này', 'Search these events')} data-testid="browse-search-input"
              style={{ width: '100%', boxSizing: 'border-box', minHeight: 44, padding: '0 14px', borderRadius: 999, border: '1px solid var(--bb-rule)', background: 'var(--bb-field, var(--bb-block))', color: 'inherit', fontFamily: 'inherit', fontSize: 16 }} />
          </form>
        ) : (
          <div data-testid="browse-nav-title" style={{ flex: 1, minWidth: 0, fontSize: 16, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{navTitle}</div>
        )}
        <button type="button" data-testid="browse-search" style={navBtn}
          onClick={() => { if (finding) { onQuery(''); setFinding(false); } else setFinding(true); }}
          aria-label={finding ? T('Xoá tìm kiếm', 'Clear search') : T('Tìm trong các sự kiện này', 'Search these events')}>
          <Icon d={finding ? CLOSE : SEARCH} />
        </button>
        <button type="button" onClick={() => onMap(effType)} aria-label={T('Xem trên bản đồ', 'See on the map')} data-testid="browse-map" style={navBtn}><Icon d={MAP} /></button>
      </header>

      <div style={{ padding: '18px 20px 8px' }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.1em', textTransform: 'uppercase', opacity: 0.72 }}>{kicker}</div>
        <h1 data-testid="browse-title" style={{ margin: '4px 0 10px', fontSize: 30, fontWeight: 400, letterSpacing: '-.02em', lineHeight: 1.1 }}>{title}</h1>
        <HostDeck hosts={hosts} onOpen={() => setHostsOpen(true)} T={T} />
        <div style={{ fontSize: 13, opacity: 0.72, marginTop: 6 }}>
          {[T(`${list.length} sự kiện`, `${list.length} ${list.length === 1 ? 'event' : 'events'}`), areaLabel].filter(Boolean).join(' · ')}
        </div>
      </div>

      {chips.length > 0 && (
        <div role="tablist" aria-label={T('Loại sự kiện', 'Event types')} data-hscroll data-testid="browse-type-chips"
          style={{ display: 'flex', gap: 8, overflowX: 'auto', padding: '6px 20px 10px', scrollbarWidth: 'none' }}>
          {[{ key: 'all', vi: 'Tất cả', en: 'All' }, ...chips].map(d => {
            const on = effType === d.key;
            const n = d.key === 'all' ? items.length : counts[d.key];
            return (
              <button key={d.key} type="button" role="tab" aria-selected={on} data-testid={`browse-type-${d.key}`} onClick={() => onType(d.key)}
                style={{ flex: 'none', display: 'flex', alignItems: 'center', gap: 6, minHeight: 44, padding: '0 14px', borderRadius: 999, border: on ? 'none' : '1px solid var(--bb-rule)', background: on ? 'var(--bb-fg)' : 'none', color: on ? 'var(--bb-bg)' : 'inherit', fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer' }}>
                {d.key !== 'all' && <CategoryGlyph cat={d.key} size={16} strokeWidth={1.6} />}
                <span>{T(d.vi, d.en)}</span>
                <span data-testid={`browse-type-count-${d.key}`} style={{ fontWeight: 500, opacity: 0.7, fontVariantNumeric: 'tabular-nums' }}>{n}</span>
              </button>
            );
          })}
        </div>
      )}

      <div ref={scrollRef} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '6px 20px 12px', scrollMarginTop: 72 }}>
        <span data-testid="browse-count" style={{ fontSize: 14 }}><b>{list.length}</b> {T('sự kiện', list.length === 1 ? 'event' : 'events')}</span>
        <button type="button" onClick={() => setFiltersOpen(true)} data-testid="browse-filters-button"
          aria-label={nFilters ? T(`Bộ lọc, đang bật ${nFilters}`, `Filters, ${nFilters} on`) : T('Bộ lọc', 'Filters')}
          style={{ minHeight: 44, padding: '0 14px', borderRadius: 999, border: 'none', background: 'var(--bb-block)', color: 'inherit', fontFamily: 'inherit', fontSize: 14, fontWeight: 600, display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
          <Icon d={SLIDERS} size={17} />{T('Bộ lọc', 'Filters')}
          {nFilters > 0 && <span data-testid="browse-filter-badge" style={{ minWidth: 20, height: 20, padding: '0 6px', borderRadius: 999, background: 'var(--bb-fg)', color: 'var(--bb-bg)', fontSize: 12, fontWeight: 700, display: 'grid', placeItems: 'center' }}>{nFilters}</span>}
        </button>
      </div>

      <Pager items={rows} getKey={r => r.key} lang={lang} T={T} testId="browse-list" rowHeight={ROW_HEIGHT} hints
        renderRow={r => <EventRowV23 row={r} onOpen={() => onOpenEvent(r.key)} testId={`browse-event-${r.key}`} />}
        renderEnd={end => <EndCard card={card} variant={end.variant} onAction={onEnd} T={T} />}
        empty={(
          <EndCard variant="solo" onAction={onEnd} T={T} card={query.trim() ? {
            kind: 'empty', eyebrow: { vi: 'Tìm kiếm', en: 'Search' },
            title: { vi: `Không có sự kiện nào khớp “${query.trim()}”.`, en: `No events match “${query.trim()}”.` },
            body: { vi: 'Thử tên khác, một khu vực hoặc một loại sự kiện.', en: 'Try another name, an area or a type.' },
            actions: [{ act: 'clear-search', primary: true, testId: 'browse-empty-clear', label: { vi: 'Xoá tìm kiếm', en: 'Clear search' } }],
          } : hidden > 0 ? {
            kind: 'empty', eyebrow: { vi: 'Bộ lọc', en: 'Filters' },
            title: { vi: 'Không có sự kiện nào khớp bộ lọc.', en: 'None of these match your filters.' },
            body: { vi: 'Xoá bộ lọc để xem lại mọi thứ.', en: 'Clear the filters to see everything again.' },
            actions: [{ act: 'clear-filters', primary: true, testId: 'browse-empty-clear', label: { vi: 'Xoá bộ lọc', en: 'Clear filters' } }],
          } : {
            kind: 'empty', eyebrow: { vi: 'Sắp có', en: 'Coming up' },
            title: { vi: 'Chưa có gì ở đây.', en: 'Nothing here yet.' },
            body: { vi: 'Sự kiện mới sẽ hiện ở đây khi chủ nhà đăng.', en: 'New events show up here when hosts post them.' },
            actions: [],
          }} />
        )} />
      <div style={{ height: 120 }} />

      {hostsOpen && (
        <HostListSheet hosts={hosts} title={title} T={T} onClose={() => setHostsOpen(false)} onPick={(id) => { setHostsOpen(false); onOpenHost(id); }} />
      )}
      {filtersOpen && (
        <HomeFilterSheet browseMode title={T(`Lọc ${title}`, `Filter ${title}`)} T={T} now={now}
          items={browseList({ items, type: effType, query, filters: null, now }).list} filters={browseFilters(filters)} sort="soonest"
          onApply={(draft) => { onFilters(draft); setFiltersOpen(false); }} onClose={() => setFiltersOpen(false)} />
      )}
    </div>
  );
}

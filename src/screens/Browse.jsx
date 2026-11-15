// See all / Browse by type (v2.3, notes 81 and 85). ONE route family, two screens told apart by the URL:
// · /see-all/<tab> — one Home tab (For You, Tonight, Weekend) as its list. The same three tabs sit under the nav, so the
//   reader moves between tabs without going back to Home (note 85); the type chips then narrow the open tab, and its
//   own Filters (When, Price, Seats) sit beside the count. Under the tabs a deck of host faces replaces the description
//   (a tap lists the hosts, a host opens their real profile).
// · /browse — Browse by type, TYPES ONLY (note 85): every type of the whole catalogue as one grid of counts and nothing
//   else. A tile opens that type's list (/browse/<type>), whose "All" chip leads back to the grid. A search typed on the
//   grid is the one thing that turns it into a list (every type's matches).
// The magnifier left of Map turns the title into a search field (the native keyboard, Done keeps the query as the
// list's filter, × clears it). The list pages four rows at a time with the onboarding-style swipe signs and ends with
// an end card. Pure view: Home.jsx passes the scope's items (the same discovery items Home uses, so there is no second
// filter path) and the handlers. Rules: src/lib/browse.js, src/lib/pager.js.
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

// The Home tabs, in Home's own order and words: See all carries them so a reader changes tab in place (note 85).
const SCOPES = ['foryou', 'tonight', 'weekend'];

/**
 * @param {object} p
 * @param {'all'|'foryou'|'tonight'|'weekend'} p.scope  'all' = Browse by type (the whole catalogue)
 * @param {string} p.type  'all' or a type key
 * @param {Array} p.items  the scope's discovery items, in the scope's order
 * @param {(it) => object} p.shapeRow  discovery item → EventRowV23 row
 * @param {(tab: string) => void} p.onScope  switch to another Home tab without leaving the screen
 */
export default function Browse({ T, lang, scope, type, query, filters, items, now, areaLabel, shapeRow,
  onType, onQuery, onFilters, onBack, onOpenEvent, onOpenHost, onMap, onHost, onScope = () => {} }) {
  const reduced = useReducedMotion();
  const tabLabel = scope !== 'all' ? (TAB_LABEL[scope] || null) : null;
  const typeDef = TYPE_DEFS.find(d => d.key === type) || null;
  const typeName = typeDef ? { vi: typeDef.vi, en: typeDef.en } : null;
  const counts = useMemo(() => typeCounts(items), [items]);
  const typed = String(query || '').trim();
  // A type with nothing in this scope falls back to every type (a stale link, or a tab that changed).
  const effType = type !== 'all' && !counts[type] ? 'all' : type;
  const chips = useMemo(() => TYPE_DEFS.filter(d => counts[d.key] > 0).sort((a, b) => counts[b.key] - counts[a.key]), [counts]);
  // Browse by type is the catalogue's types and nothing else; a search is the one thing that opens it into a list.
  const index = scope === 'all' && effType === 'all' && !typed;
  const { list, hidden } = useMemo(() => browseList({ items, type: effType, query, filters, now }), [items, effType, query, filters, now]);
  const hosts = useMemo(() => (index ? [] : hostsOf(browseList({ items, type: effType, query: '', filters: null, now }).list, lang)),
    [index, items, effType, now, lang]);
  const rows = useMemo(() => list.map(shapeRow), [list, shapeRow]);
  const nFilters = browseFilterCount(filters);
  const others = chips.filter(d => d.key !== effType).map(d => ({ key: d.key, name: { vi: d.vi, en: d.en }, count: counts[d.key] }));
  const card = browseEnd({ type: effType, typeName: effType === 'all' ? null : typeName, list, hidden, query, others });

  const evN = (n) => T(`${n} sự kiện`, `${n} ${n === 1 ? 'event' : 'events'}`);
  // The type chips share one chip look (ink fill when selected); the scope tabs above are text + rule, so the two rows
  // never read as the same control (note 85).
  const chipLook = (on) => ({
    flex: 'none', display: 'flex', alignItems: 'center', gap: 6, minHeight: 44, padding: '0 14px', borderRadius: 999,
    fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer',
    border: on ? 'none' : '1px solid var(--bb-rule)', background: on ? 'var(--bb-fg)' : 'none', color: on ? 'var(--bb-bg)' : 'inherit',
  });

  const titleText = effType !== 'all' && typeName ? T(typeName.vi, typeName.en)
    : tabLabel ? T(tabLabel.vi, tabLabel.en) : T('Duyệt theo loại', 'Browse by type');
  // The screen's title lives in its content: the tab row on a tab screen, the big title on the grid. The nav row only
  // carries what the content does not already say (the search, and the picked type).
  const navTitle = typed ? `“${typed}” · ${titleText}`
    : effType !== 'all' ? (tabLabel ? `${T(tabLabel.vi, tabLabel.en)} · ${titleText}` : titleText) : '';

  const [finding, setFinding] = useState(false);
  const [hostsOpen, setHostsOpen] = useState(false);
  const [filtersOpen, setFiltersOpen] = useState(false);
  const inputRef = useRef(null);
  const scrollRef = useRef(null);
  useEffect(() => { if (finding) inputRef.current?.focus({ preventScroll: true }); }, [finding]);
  // Pushed in over Home from the right (Reduced: no slide).
  const enter = reduced ? undefined : 'bbV23PushIn 0.42s cubic-bezier(.32,.72,0,1) both';
  const navBtn = { width: 44, height: 44, borderRadius: '50%', border: 'none', background: 'rgba(var(--bb-fg-rgb),0.07)', color: 'inherit', display: 'grid', placeItems: 'center', cursor: 'pointer', flex: 'none' };

  // "All" on a type list at /browse returns to the grid, where a type is chosen: it therefore starts clean instead of
  // keeping a search and filters the grid never showed (note 85).
  const pickType = (k) => {
    if (k === 'all' && scope === 'all') { onType('all'); onQuery(''); onFilters(null); return; }
    onType(k);
  };
  const onEnd = (act) => {
    if (act === 'clear-filters') onFilters(null);
    else if (act === 'clear-search') { onQuery(''); setFinding(false); }
    else if (act.startsWith('type:')) { pickType(act.slice(5)); scrollRef.current?.scrollIntoView({ block: 'start', behavior: reduced ? 'auto' : 'smooth' }); }
    else if (act === 'map') onMap(effType);
    else if (act === 'host') onHost();
  };
  // Back goes up to the grid from a type's list (the grid is its parent), Home everywhere else (note 85).
  const fromTypeList = scope === 'all' && effType !== 'all';
  const backLabel = fromTypeList ? T('Mọi loại', 'All types') : T('Về Trang chủ', 'Back to Home');
  const goBack = () => { if (fromTypeList) pickType('all'); else onBack(); };

  return (
    <div data-testid="browse-screen" data-scope={scope} data-type={effType} data-mode={index ? 'index' : 'list'}
      style={{ minHeight: '100%', background: 'var(--bb-bg)', color: 'var(--bb-fg)', animation: enter }}>
      <style>{'@keyframes bbV23PushIn { from { transform: translateX(28%); opacity: .4; } to { transform: none; opacity: 1; } }'}</style>
      <header data-testid="browse-nav" style={{ position: 'sticky', top: 0, zIndex: 5, background: 'var(--bb-bg)', borderBottom: '1px solid var(--bb-rule)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '8px 12px' }}>
          <button type="button" onClick={goBack} aria-label={backLabel} data-testid="browse-back" style={navBtn}><Icon d={BACK} /></button>
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
        </div>

        {/* The three Home tabs (note 85): text over a rule, the same rhythm as Home's hero tabs, so switching tab
            never means going back to Home first. Never drawn on /browse, which has no tab. */}
        {scope !== 'all' && (
          <div role="tablist" aria-label={T('Trang chủ', 'Home')} data-hscroll data-testid="browse-scope-tabs"
            style={{ display: 'flex', gap: 20, overflowX: 'auto', padding: '0 20px', scrollbarWidth: 'none' }}>
            {SCOPES.map(k => {
              const on = scope === k;
              const label = TAB_LABEL[k];
              return (
                <button key={k} type="button" role="tab" aria-selected={on} data-testid={`browse-scope-${k}`} onClick={() => { if (!on) onScope(k); }}
                  style={{ flex: 'none', border: 'none', background: 'none', fontFamily: 'inherit', fontSize: 17, padding: '10px 0 8px', cursor: 'pointer',
                    color: 'inherit', opacity: on ? 1 : 0.55, fontWeight: on ? 500 : 300,
                    borderBottom: `2px solid ${on ? 'var(--bb-fg)' : 'transparent'}` }}>
                  {T(label.vi, label.en)}
                </button>
              );
            })}
          </div>
        )}
      </header>

      {index ? (
        <>
          <div style={{ padding: '18px 20px 0' }}>
            <h1 data-testid="browse-title" style={{ margin: 0, fontSize: 30, fontWeight: 400, letterSpacing: '-.02em', lineHeight: 1.1 }}>{titleText}</h1>
            <div data-testid="browse-scope-count" style={{ fontSize: 13, opacity: 0.72, marginTop: 6 }}>
              {[evN(items.length), areaLabel].filter(Boolean).join(' · ')}
            </div>
            <p style={{ fontSize: 14, opacity: 0.72, margin: '10px 0 0' }}>{T('Chọn một loại để xem những buổi đang mở.', 'Pick a type to see what is on.')}</p>
          </div>
          {/* Every type with an event in the catalogue, most events first, in Home's Browse by type tiles. */}
          <div data-testid="browse-type-grid" style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 4, padding: '14px 20px 0' }}>
            {chips.map(d => (
              <button key={d.key} type="button" data-testid={`browse-grid-${d.key}`} onClick={() => pickType(d.key)}
                style={{ padding: '14px 0 12px', border: 'none', borderRadius: 16, background: 'none', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, fontFamily: 'inherit', fontSize: 13, color: 'inherit', cursor: 'pointer' }}>
                <span style={{ width: 52, height: 52, display: 'grid', placeItems: 'center', marginBottom: 4 }}><CategoryGlyph cat={d.key} size={28} strokeWidth={1.5} /></span>
                <span>{T(d.vi, d.en)}</span>
                <small data-testid={`browse-grid-count-${d.key}`} style={{ fontSize: 11.5, opacity: 0.64 }}>{evN(counts[d.key])}</small>
              </button>
            ))}
          </div>
          {chips.length === 0 && (
            <div data-testid="browse-type-grid-empty" style={{ padding: '18px 20px 0', fontSize: 14, opacity: 0.72 }}>{T('Chưa có gì ở đây.', 'Nothing here yet.')}</div>
          )}
        </>
      ) : (
        <>
          {hosts.length > 0 && (
            <div style={{ padding: '16px 20px 0' }}>
              <HostDeck hosts={hosts} onOpen={() => setHostsOpen(true)} T={T} />
            </div>
          )}

          {chips.length > 0 && (
            <div role="tablist" aria-label={T('Loại sự kiện', 'Event types')} data-hscroll data-testid="browse-type-chips"
              style={{ display: 'flex', gap: 8, overflowX: 'auto', padding: '12px 20px 10px', scrollbarWidth: 'none' }}>
              {[{ key: 'all', vi: 'Tất cả', en: 'All' }, ...chips].map(d => {
                const on = effType === d.key;
                const n = d.key === 'all' ? items.length : counts[d.key];
                return (
                  <button key={d.key} type="button" role="tab" aria-selected={on} data-testid={`browse-type-${d.key}`} onClick={() => pickType(d.key)} style={chipLook(on)}>
                    {d.key !== 'all' && <CategoryGlyph cat={d.key} size={16} strokeWidth={1.6} />}
                    <span>{T(d.vi, d.en)}</span>
                    <span data-testid={`browse-type-count-${d.key}`} style={{ fontWeight: 500, opacity: 0.7, fontVariantNumeric: 'tabular-nums' }}>{n}</span>
                  </button>
                );
              })}
            </div>
          )}

          <div ref={scrollRef} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '6px 20px 12px', scrollMarginTop: 108 }}>
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
              <EndCard variant="solo" onAction={onEnd} T={T} card={typed ? {
                kind: 'empty', eyebrow: { vi: 'Tìm kiếm', en: 'Search' },
                title: { vi: `Không có sự kiện nào khớp “${typed}”.`, en: `No events match “${typed}”.` },
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
        </>
      )}
      <div style={{ height: 120 }} />

      {hostsOpen && (
        <HostListSheet hosts={hosts} title={titleText} T={T} onClose={() => setHostsOpen(false)} onPick={(id) => { setHostsOpen(false); onOpenHost(id); }} />
      )}
      {filtersOpen && (
        <HomeFilterSheet browseMode title={T(`Lọc ${titleText}`, `Filter ${titleText}`)} T={T} now={now}
          items={browseList({ items, type: effType, query, filters: null, now }).list} filters={browseFilters(filters)} sort="soonest"
          onApply={(draft) => { onFilters(draft); setFiltersOpen(false); }} onClose={() => setFiltersOpen(false)} />
      )}
    </div>
  );
}

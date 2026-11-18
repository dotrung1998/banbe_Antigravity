// See all / Browse by type (v2.3, notes 81, 85, 86, 88 and 90). ONE route family, ONE kind of screen: a list of events.
// · /see-all/<tab> — one Home tab (For You, Tonight, Weekend) as its list. The same three tabs sit under the nav, so the
//   reader moves between tabs without going back to Home (note 85); the type chips then narrow the open tab, and its
//   own Filters (Location, When, Price, Seats) sit beside the count. Under the tabs a deck of host faces replaces the description
//   (a tap lists the hosts, a host opens their real profile).
// · /browse[/<type>] — Browse by type, the whole catalogue as a LIST, never a grid (note 88): every event at once, with
//   the type chips narrowing it in place. "All" widens it back to every event. The nav row names the screen ("Browse by
//   type"), a picked type is the content's 30px heading with its own count line, and a search reads all three.
// Browse by type is the row's FOURTH TAB (note 90), alongside For You, Tonight and Weekend: it opens the every-event
// list in place and remembers the tab it came from, so Back returns there instead of Home. The row shows on every
// Browse screen, so the destination it leads to still reads as the tab it is.
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
import AccountAvatar from '../components/AccountAvatar.jsx';
import NativeSheet from '../components/NativeSheet.jsx';
import { CategoryGlyph } from '../components/home/HomeDiscoveryParts.jsx';
import { browseList, typeCounts, hostsOf, browseEnd, browseFilters, browseFilterCount, browseDatesLabel, withAllAreasAction } from '../lib/browse.js';
import { categoryDefs } from '../lib/eventTypes.js';
import { useReducedMotion } from '../lib/useReducedMotion.js';
import { TAB_LABEL } from '../components/home/ShortlistV23.jsx';

const TYPE_DEFS = categoryDefs();
const TYPE_OPTIONS = [{ key: 'all', vi: 'Tất cả', en: 'All' }, ...TYPE_DEFS];
const Icon = ({ d, size = 20 }) => (
  <svg aria-hidden="true" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">{d}</svg>
);
const BACK = <path d="m15 5-7 7 7 7" />;
const SEARCH = <><circle cx="11" cy="11" r="6.5" /><path d="m16 16 4 4" /></>;
const CLOSE = <path d="M6 6l12 12M18 6 6 18" />;
const MAP = <><path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2z" /><path d="M9 4v14M15 6v14" /></>;
const SLIDERS = <><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" /></>;
const PIN = <><path d="M12 21s7-6.1 7-11a7 7 0 1 0-14 0c0 4.9 7 11 7 11Z" /><circle cx="12" cy="10" r="2.5" /></>;
const GRID = <><rect x="4" y="4" width="6" height="6" rx="1" /><rect x="14" y="4" width="6" height="6" rx="1" /><rect x="4" y="14" width="6" height="6" rx="1" /><rect x="14" y="14" width="6" height="6" rx="1" /></>;

// The Home tabs, in Home's own order and words: See all carries them so a reader changes tab in place (note 85).
const SCOPES = ['foryou', 'tonight', 'weekend'];
// And the fourth tab (note 90): the whole catalogue, where the quiet link under the chips used to lead.
const TYPES_TAB = { key: 'all', vi: 'Duyệt theo loại', en: 'Browse by type' };

/**
 * @param {object} p
 * @param {'all'|'foryou'|'tonight'|'weekend'} p.scope  'all' = Browse by type (the whole catalogue)
 * @param {string} p.type  'all' or a type key
 * @param {Array} p.items  the scope's discovery items, in the scope's order
 * @param {(it) => object} p.shapeRow  discovery item → EventRowV23 row
 * @param {(tab: string) => void} p.onScope  switch to another Home tab without leaving the screen
 * @param {string|null} p.from  the Home tab this Browse by type was opened out of (Back returns to it, note 86)
 * @param {() => void} p.onBrowseTypes  open Browse by type from inside a tab (note 86)
 * @param {(key: string) => void} [p.onToggleSave]  the row's heart (favorites)
 * @param {() => void} [p.onAccount]  the nav row's Account button (2026-11-17)
 * @param {string} [p.areaKey]  the active location's key; an area change returns the list to its heading
 * @param {boolean} [p.areaActive]  a location narrower than "all" is on
 * @param {() => void} [p.onChooseArea]  open the location picker (and stay on this screen)
 * @param {() => void} [p.onAllAreas]  widen the list to every location
 * @param {string} [p.accountName]  the signed-in reader's name, for the avatar's initials fallback
 * @param {string} [p.accountAvatarUrl]  the reader's profile photo, shown in the nav instead of a person glyph
 */
export default function Browse({ T, lang, scope, type, query, filters, items, now, areaLabel, shapeRow,
  onType, onQuery, onFilters, onBack, onOpenEvent, onOpenHost, onMap, onHost, onScope = () => {}, from = null,
  onBrowseTypes = () => {}, onToggleSave = null, onAccount = null,
  areaKey = '', areaActive = false, onChooseArea = () => {}, onAllAreas = () => {},
  accountName = '', accountAvatarUrl = '' }) {
  const reduced = useReducedMotion();
  const tabLabel = scope !== 'all' ? (TAB_LABEL[scope] || null) : null;
  const typeDef = TYPE_DEFS.find(d => d.key === type) || null;
  const typeName = typeDef ? { vi: typeDef.vi, en: typeDef.en } : null;
  const counts = useMemo(() => typeCounts(items), [items]);
  const typed = String(query || '').trim();
  // A type the catalogue does not have (a stale link) falls back to every type; a real type keeps its own list even while
  // nothing is on for it, so its chip opens an honest empty list instead of something else.
  const known = TYPE_DEFS.some(d => d.key === type);
  const effType = type !== 'all' && !known ? 'all' : type;
  const chips = useMemo(() => TYPE_DEFS.filter(d => counts[d.key] > 0).sort((a, b) => counts[b.key] - counts[a.key]), [counts]);
  // No grid (note 88): Browse by type IS the list of every event, and the type chips narrow it in place.
  const { list, hidden } = useMemo(() => browseList({ items, type: effType, query, filters, now }), [items, effType, query, filters, now]);
  const hosts = useMemo(() => hostsOf(browseList({ items, type: effType, query: '', filters: null, now }).list, lang),
    [items, effType, now, lang]);
  const rows = useMemo(() => list.map(shapeRow), [list, shapeRow]);
  const nFilters = browseFilterCount(filters);
  const others = chips.filter(d => d.key !== effType).map(d => ({ key: d.key, name: { vi: d.vi, en: d.en }, count: counts[d.key] }));
  const card = browseEnd({ type: effType, typeName: effType === 'all' ? null : typeName, list, hidden, query, others });

  // The type chips share one chip look (ink fill when selected); the scope tabs above are text + rule, so the two rows
  // never read as the same control (note 85).
  const chipLook = (on) => ({
    flex: 'none', display: 'flex', alignItems: 'center', gap: 6, minHeight: 44, padding: '0 14px', borderRadius: 999,
    fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer',
    border: on ? 'none' : '1px solid var(--bb-rule)', background: on ? 'var(--bb-fg)' : 'none', color: on ? 'var(--bb-bg)' : 'inherit',
  });
  // The area scope's two choices are quieter than the type chips but still a 40 pt target; the label truncates rather
  // than pushing the second choice off a narrow screen.
  const areaPill = (on) => ({
    display: 'inline-flex', alignItems: 'center', gap: 6, height: 40, maxWidth: '100%', minWidth: 0, padding: '0 12px', borderRadius: 999,
    border: on ? '1px solid transparent' : '1px solid var(--bb-rule)', background: on ? 'var(--bb-fg)' : 'none',
    color: on ? 'var(--bb-bg)' : 'inherit', fontFamily: 'inherit', fontSize: 13, fontWeight: 600, cursor: 'pointer', whiteSpace: 'nowrap',
  });
  const areaPillLabel = { overflow: 'hidden', textOverflow: 'ellipsis', minWidth: 0 };

  const titleText = effType !== 'all' && typeName ? T(typeName.vi, typeName.en)
    : tabLabel ? T(tabLabel.vi, tabLabel.en) : T('Duyệt theo loại', 'Browse by type');
  // The nav row carries the running search only: the screen's own name now lives in the heading under the tabs (note 91),
  // and a picked type is that heading too, so the nav row never repeats it.
  const navTitle = typed ? `“${typed}”` : '';

  // An empty list is never a dead end (note 91): the card offers the next real step — another area, another tab, the
  // whole catalogue, the map, hosting — the same way the end cards do. An area with nothing on gets "All areas" first.
  const emptyActions = withAllAreasAction(scope === 'all' && effType !== 'all'
    ? [
      { act: 'type:all', primary: true, testId: 'browse-empty-all-types', label: { vi: 'Xem mọi loại', en: 'See every type' } },
      { act: 'map', testId: 'browse-empty-map', label: { vi: 'Mở bản đồ', en: 'Open the map' } },
    ]
    : scope === 'all'
      ? [
        { act: 'map', primary: true, testId: 'browse-empty-map', label: { vi: 'Mở bản đồ', en: 'Open the map' } },
        { act: 'host', testId: 'browse-empty-host', label: { vi: 'Tổ chức một buổi', en: 'Host a night' } },
      ]
      : scope === 'weekend'
        ? [
          { act: 'type:all', primary: true, testId: 'browse-empty-all-types', label: { vi: 'Xem mọi loại', en: 'See every type' } },
          { act: 'map', testId: 'browse-empty-map', label: { vi: 'Mở bản đồ', en: 'Open the map' } },
        ]
        : [
          { act: 'scope:weekend', primary: true, testId: 'browse-empty-weekend', label: { vi: 'Xem cuối tuần', en: 'See this weekend' } },
          { act: 'browse-types', testId: 'browse-empty-browse-types', label: { vi: 'Duyệt theo loại', en: 'Browse by type' } },
          { act: 'map', testId: 'browse-empty-map', label: { vi: 'Mở bản đồ', en: 'Open the map' } },
        ], areaActive);

  const dates = browseDatesLabel(scope, now, lang);
  const [finding, setFinding] = useState(false);
  const [hostsOpen, setHostsOpen] = useState(false);
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [typesOpen, setTypesOpen] = useState(false);
  const inputRef = useRef(null);
  const scrollRef = useRef(null);
  useEffect(() => { if (finding) inputRef.current?.focus({ preventScroll: true }); }, [finding]);
  // A new area is a new list: go back to the heading where its count and type chips are, instead of leaving the
  // reader at a scroll position that belonged to the old area.
  const areaSeen = useRef(areaKey);
  useEffect(() => {
    if (areaSeen.current === areaKey) return;
    areaSeen.current = areaKey;
    scrollRef.current?.scrollIntoView({ block: 'start', behavior: reduced ? 'auto' : 'smooth' });
  }, [areaKey, reduced]);
  // Pushed in over Home from the right (Reduced: no slide).
  const enter = reduced ? undefined : 'bbV23PushIn 0.42s cubic-bezier(.32,.72,0,1) both';
  // Same 40 pt circle as Home's band (note 94): one control language across the two screens.
  const navBtn = { width: 40, height: 40, borderRadius: '50%', border: '1px solid var(--bb-divider)', background: 'rgba(var(--bb-fg-rgb),0.07)', color: 'inherit', display: 'grid', placeItems: 'center', cursor: 'pointer', flex: 'none' };

  // "All" is every event: the list widens in place, there is no grid in between (note 88).
  const pickType = (k) => onType(k);
  // Choosing the option already on is never a dead tap (note 96): "All areas" returns to the heading even when the
  // whole catalogue is already showing.
  const goAllAreas = () => {
    if (areaActive) { onAllAreas(); return; }
    scrollRef.current?.scrollIntoView({ block: 'start', behavior: reduced ? 'auto' : 'smooth' });
  };
  const onEnd = (act) => {
    if (act === 'clear-filters') onFilters(null);
    else if (act === 'area:all') onAllAreas();
    else if (act === 'clear-search') { onQuery(''); setFinding(false); }
    else if (act.startsWith('type:')) { pickType(act.slice(5)); scrollRef.current?.scrollIntoView({ block: 'start', behavior: reduced ? 'auto' : 'smooth' }); }
    else if (act === 'map') onMap(effType);
    else if (act === 'host') onHost();
    else if (act === 'browse-types') onBrowseTypes();
    else if (act.startsWith('scope:')) onScope(act.slice(6));
  };
  // Back leaves the screen (notes 86 and 88): Browse by type opened from a tab returns to that tab, everywhere else to
  // Home. There is no grid to step up to any more. The label says which way it goes.
  const fromTab = scope === 'all' && TAB_LABEL[from] ? from : null;
  const backLabel = fromTab ? T(`Về ${TAB_LABEL[fromTab].vi}`, `Back to ${TAB_LABEL[fromTab].en}`)
    : T('Về Trang chủ', 'Back to Home');

  return (
    <div data-testid="browse-screen" data-scope={scope} data-type={effType}
      style={{ minHeight: '100%', background: 'var(--bb-bg)', color: 'var(--bb-fg)', animation: enter }}>
      <style>{'@keyframes bbV23PushIn { from { transform: translateX(28%); opacity: .4; } to { transform: none; opacity: 1; } }'}</style>
      {/* The web top band (2026-11-22): the same recipe as Home's new app bar — one opaque paper band, a fixed row of
          controls, the tabs as its second row and a single hairline under both, so the band never paints over what is
          below it: it owns its full height in the flow (58 + 44) and the content clears it with one scroll margin. */}
      <header data-testid="browse-nav" style={{ position: 'sticky', top: 0, zIndex: 30, background: 'var(--bb-bg)', borderBottom: '1px solid var(--bb-divider)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 12px', minHeight: 58, boxSizing: 'border-box' }}>
          <button type="button" onClick={onBack} aria-label={backLabel} data-testid="browse-back" style={navBtn}><Icon d={BACK} size={18} /></button>
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
            <Icon d={finding ? CLOSE : SEARCH} size={18} />
          </button>
          <button type="button" onClick={() => onMap(effType)} aria-label={T('Xem trên bản đồ', 'See on the map')} data-testid="browse-map" style={navBtn}><Icon d={MAP} size={18} /></button>
          {/* Account sits in the corner on every screen that carries the four tabs (2026-11-17): the dock does not
              show here, so this is the one way to Account without going back to Home first. The face is the reader's
              own (photo, then initials), not the generic person glyph the two headers used to disagree on. */}
          {onAccount && (
            <button type="button" onClick={onAccount} aria-label={T('Tài khoản', 'Account')} data-testid="browse-account"
              className="bb-home-head__avatar" style={{ width: 40, height: 40 }}>
              <AccountAvatar name={accountName} avatarUrl={accountAvatarUrl} />
            </button>
          )}
        </div>

        {/* The three Home tabs and Browse by type (note 90): text over a rule, the same rhythm as Home's hero tabs, so
            switching tab — or opening the whole catalogue — never means going back to Home first. Browse by type is a
            tab like the others: it opens the every-event list in place and remembers this tab, so Back returns here. */}
        <div role="tablist" aria-label={T('Trang chủ', 'Home')} data-hscroll data-testid="browse-scope-tabs"
          style={{ display: 'flex', gap: 18, overflowX: 'auto', padding: '0 20px', scrollbarWidth: 'none' }}>
          {SCOPES.map(k => ({ key: k, ...TAB_LABEL[k] })).concat(TYPES_TAB).map(t => {
            const on = t.key === 'all' ? scope === 'all' : scope === t.key;
            return (
              <button key={t.key} type="button" role="tab" aria-selected={on} data-testid={`browse-scope-${t.key}`}
                onClick={() => {
                  // Tapping the tab you are already on returns to the top of its list (owner 2026-11-23: choosing the
                  // current option must never be a dead tap after scrolling).
                  if (on) { scrollRef.current?.scrollIntoView({ block: 'start', behavior: reduced ? 'auto' : 'smooth' }); return; }
                  if (t.key === 'all') onBrowseTypes(); else onScope(t.key);
                }}
                style={{ flex: 'none', border: 'none', background: 'none', fontFamily: 'inherit', fontSize: 15.5, minHeight: 44, padding: '0 0 2px', cursor: 'pointer',
                  color: 'inherit', opacity: on ? 1 : 0.6, fontWeight: on ? 600 : 400, whiteSpace: 'nowrap',
                  borderBottom: `2px solid ${on ? 'var(--bb-fg)' : 'transparent'}` }}>
                {T(t.vi, t.en)}
              </button>
            );
          })}
        </div>
      </header>

      <>
        {/* One heading row and one filter row (the Browse list pass). The title, under the tabs (note 91): a picked
            type wins, then the open tab, then Browse by type itself; under it one line that says what the list holds —
            the weekend's or tonight's real dates, the count, the area. The hosts' faces sit on the same row, and
            Filters closes the chip row; each used to take a row of its own and push the first event far down the
            screen. The title is where a type-chip turn scrolls back to. */}
        <div ref={scrollRef} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '18px 20px 0', scrollMarginTop: 112 }}>
          <div style={{ flex: 1, minWidth: 0 }}>
            <h1 data-testid="browse-title" style={{ margin: 0, fontSize: 30, fontWeight: 400, letterSpacing: '-.02em', lineHeight: 1.1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{titleText}</h1>
            <div data-testid="browse-scope-count" style={{ fontSize: 13, opacity: 0.72, marginTop: 6 }}>
              {dates ? <span data-testid="browse-dates">{dates} · </span> : null}
              <span data-testid="browse-count"><b>{list.length}</b> {T('sự kiện', list.length === 1 ? 'event' : 'events')}</span>
            </div>
          </div>
          {hosts.length > 0 && <HostDeck hosts={hosts} onOpen={() => setHostsOpen(true)} T={T} />}
        </div>

        {/* Area is a scope choice, not a hidden filter (owner 2026-11-30): Browse opens on the area the reader came
            from and offers "All areas" in one tap, instead of printing the area with no way to change it. The filter
            sheet keeps a Location section too, so any specific area is still reachable. */}
        <div data-testid="browse-area-scope" style={{ display: 'flex', flexWrap: 'wrap', gap: 8, padding: '10px 20px 0' }}>
          <button type="button" data-testid="browse-area-current" aria-pressed={areaActive} onClick={onChooseArea}
            style={areaPill(areaActive)}>
            <Icon d={PIN} size={13} />
            <span style={areaPillLabel}>{areaActive ? areaLabel : T('Chọn khu vực', 'Choose area')}</span>
          </button>
          <button type="button" data-testid="browse-area-all" aria-pressed={!areaActive} onClick={goAllAreas}
            style={areaPill(!areaActive)}>
            <span>{T('Tất cả khu vực', 'All areas')}</span>
          </button>
        </div>

          <div style={{ display: 'flex', alignItems: 'center', padding: '12px 0 14px' }}>
            {chips.length > 0 ? (
              <div role="tablist" aria-label={T('Loại sự kiện', 'Event types')} data-hscroll data-testid="browse-type-chips"
                style={{ flex: 1, minWidth: 0, display: 'flex', gap: 8, overflowX: 'auto', padding: '0 16px 0 20px', scrollbarWidth: 'none',
                  WebkitMaskImage: 'linear-gradient(90deg, #000 93%, transparent)', maskImage: 'linear-gradient(90deg, #000 93%, transparent)' }}>
                {[{ key: 'all', vi: 'Tất cả', en: 'All' }, ...chips].map(d => {
                  const on = effType === d.key;
                  const n = d.key === 'all' ? items.length : counts[d.key];
                  return (
                    <button key={d.key} type="button" role="tab" aria-selected={on} data-testid={`browse-type-${d.key}`}
                      onClick={() => {
                        if (on) { scrollRef.current?.scrollIntoView({ block: 'start', behavior: reduced ? 'auto' : 'smooth' }); return; }
                        pickType(d.key);
                      }} style={chipLook(on)}>
                      {d.key !== 'all' && <CategoryGlyph cat={d.key} size={16} strokeWidth={1.6} />}
                      <span>{T(d.vi, d.en)}</span>
                      <span data-testid={`browse-type-count-${d.key}`} style={{ fontWeight: 500, opacity: 0.7, fontVariantNumeric: 'tabular-nums' }}>{n}</span>
                    </button>
                  );
                })}
              </div>
            ) : <div style={{ flex: 1 }} />}
            {/* Type opens the complete list, so a type that is off-screen in the chip strip is still one tap away. */}
            <button type="button" onClick={() => setTypesOpen(true)} data-testid="browse-type-button"
              aria-haspopup="dialog" aria-label={T('Chọn loại sự kiện', 'Choose event type')}
              style={{ ...navBtn, width: 'auto', display: 'inline-flex', gap: 6, padding: '0 12px', borderRadius: 999, fontSize: 13.5, fontWeight: 600, margin: '0 0 0 8px' }}>
              <Icon d={GRID} size={15} />
              <span>{T('Loại', 'Type')}</span>
              <span aria-hidden="true" style={{ fontSize: 10, opacity: 0.55 }}>▾</span>
            </button>
            {/* Filters closes the chip row: an icon the size of the nav circles, the number of filters on as a badge. */}
            <button type="button" onClick={() => setFiltersOpen(true)} data-testid="browse-filters-button"
              aria-label={nFilters ? T(`Bộ lọc, đang bật ${nFilters}`, `Filters, ${nFilters} on`) : T('Bộ lọc', 'Filters')}
              style={{ ...navBtn, position: 'relative', margin: '0 20px 0 8px' }}>
              <Icon d={SLIDERS} size={18} />
              {nFilters > 0 && <span data-testid="browse-filter-badge" style={{ position: 'absolute', top: -4, right: -4, minWidth: 18, height: 18, padding: '0 4px', boxSizing: 'border-box', borderRadius: 999, background: 'var(--bb-fg)', color: 'var(--bb-bg)', boxShadow: '0 0 0 2px var(--bb-bg)', fontSize: 11, fontWeight: 700, display: 'grid', placeItems: 'center' }}>{nFilters}</span>}
            </button>
          </div>

          <Pager items={rows} getKey={r => r.key} lang={lang} T={T} testId="browse-list" rowHeight={ROW_HEIGHT}
            renderRow={r => <EventRowV23 row={r} T={T} onOpen={() => onOpenEvent(r.key)} onToggleSave={onToggleSave} testId={`browse-event-${r.key}`} />}
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
                body: { vi: 'Sự kiện mới sẽ hiện ở đây khi chủ nhà đăng. Trong lúc chờ, thử một chỗ khác.', en: 'New events show up here when hosts post them. Meanwhile, try somewhere else.' },
                actions: emptyActions,
              }} />
        )} />
      </>
      <div style={{ height: 120 }} />

      {hostsOpen && (
        <HostListSheet hosts={hosts} title={titleText} T={T} onClose={() => setHostsOpen(false)} onPick={(id) => { setHostsOpen(false); onOpenHost(id); }} />
      )}
      {filtersOpen && (
        <HomeFilterSheet browseMode title={T(`Lọc ${titleText}`, `Filter ${titleText}`)} T={T} now={now} areaLabel={areaLabel}
          items={browseList({ items, type: effType, query, filters: null, now }).list} filters={browseFilters(filters)} sort="soonest"
          onApply={(draft) => { onFilters(draft); setFiltersOpen(false); }} onClose={() => setFiltersOpen(false)} />
      )}
      {typesOpen && (
        <NativeSheet open onClose={() => setTypesOpen(false)} label={T('Loại sự kiện', 'Event type')}
          testId="browse-type-sheet" bodyTestId="browse-type-backdrop">
          <div style={{ background: 'var(--bb-bg)', color: 'var(--bb-fg)', width: '100%', maxHeight: '82%', display: 'flex', flexDirection: 'column', borderRadius: '22px 22px 0 0' }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr auto 1fr', alignItems: 'center', padding: '10px 14px 8px' }}>
              <span aria-hidden="true" />
              <span style={{ fontSize: 17, fontWeight: 600 }}>{T('Loại sự kiện', 'Event type')}</span>
              <button type="button" onClick={() => setTypesOpen(false)} aria-label={T('Đóng', 'Close')} data-testid="browse-type-close"
                style={{ justifySelf: 'end', width: 36, height: 36, borderRadius: '50%', border: 'none', background: 'rgba(var(--bb-fg-rgb),0.07)', color: 'inherit', fontSize: 18, cursor: 'pointer' }}>×</button>
            </div>
            <div style={{ overflowY: 'auto', paddingBottom: 20 }}>
              {TYPE_OPTIONS.map(d => {
                const on = effType === d.key;
                const n = d.key === 'all' ? items.length : (counts[d.key] || 0);
                return (
                  <button key={d.key} type="button" data-testid={`browse-type-option-${d.key}`} aria-pressed={on}
                    onClick={() => {
                      pickType(d.key);
                      setTypesOpen(false);
                      scrollRef.current?.scrollIntoView({ block: 'start', behavior: reduced ? 'auto' : 'smooth' });
                    }}
                    style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', minHeight: 52, padding: '0 20px', border: 'none', borderTop: '1px solid var(--bb-divider)', background: 'none', color: 'inherit', fontFamily: 'inherit', fontSize: 16, textAlign: 'left', cursor: 'pointer', opacity: d.key !== 'all' && n === 0 ? 0.55 : 1 }}>
                    {d.key === 'all' ? <Icon d={GRID} size={18} /> : <CategoryGlyph cat={d.key} size={18} strokeWidth={1.6} />}
                    <span style={{ flex: 1 }}>{T(d.vi, d.en)}</span>
                    <span style={{ fontSize: 13, opacity: 0.6, fontVariantNumeric: 'tabular-nums' }}>{n}</span>
                    <span aria-hidden="true" style={{ width: 16, textAlign: 'center', opacity: on ? 1 : 0 }}>✓</span>
                  </button>
                );
              })}
            </div>
          </div>
        </NativeSheet>
      )}
    </div>
  );
}

import { useEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { paper, ink, rule, dockGlass } from '../../theme.js';
import {
  LOCATION_ALL, locationNodeLabel, locationAncestorIds, buildLocationSearchIndex, searchLocationTree,
} from '../../lib/locationTree.js';
import { searchCities } from '../../lib/mapDiscovery.js';
import citiesData from '../../data/cities.json';

const CITY_BY_ID = new Map(citiesData.cities.map(c => [c.id, c]));

// Location hierarchy sheet (2026-09-30, migration 112) — replaces the old
// flat, hardcoded 6-row "Khu vực" list (AREAS in BanBeContext.jsx) with the
// data-driven tree from src/lib/locationTree.js (built once in
// BanBeContext.jsx as `locationTree`, from the same browsable discovery set
// the old counts used — static demo events that aren't cancelled/ended/
// invite-only + real live public events).
//
// Interaction contract:
//  - Map v6 (note 74), one tap: a row's NAME picks that node (itself +
//    descendants, deduped by event id — see buildLocationTree's counts);
//    only its chevron (a separate 44px button) expands/collapses, keyed by
//    stable node id, and expanding NEVER changes the active filter. The
//    extra "Tất cả tại X" / "All in X" rows are gone (owner: "double work").
//  - search filters the ALREADY-BUILT tree client-side (index built once
//    per tree, not per keystroke) and only OR-s the matches' ancestors into
//    the expanded set at render time — the manual expand state itself is
//    never written by search, so clearing the query restores it exactly.
//  - picking any node (including the empty US root) only calls pickArea —
//    it never touches the GPS/location-permission flow below.
//
// `embedded` (note 50): the Home filter sheet opens this ON TOP of itself as a bottom sheet that slides up over it.
// A pick only moves the selection (checkmark + the counts behind update); "Done" (or the backdrop / Esc) slides it
// back down and calls `onDone`, so the filter sheet and its draft are never closed or rebuilt.
export default function AreaSheet({ embedded = false, onDone }) {
  const { state, set, T, located, pickArea, allowLocation, denyLocation, locationTree, curArea } = useBanBe();
  const s = state;
  const lang = s.lang === 'en' ? 'en' : 'vi';
  const [leaving, setLeaving] = useState(false);
  const leaveTimer = useRef(null);
  useEffect(() => () => clearTimeout(leaveTimer.current), []);
  const closeArea = () => {
    if (!embedded) { set({ areaAsking: false }); return; }
    if (leaving) return;
    setLeaving(true);
    leaveTimer.current = setTimeout(() => onDone?.(), 220);
  };
  useEffect(() => {
    if (!embedded) return undefined;
    const onKey = (e) => { if (e.key === 'Escape') { e.stopPropagation(); closeArea(); } };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }); // eslint-disable-line react-hooks/exhaustive-deps
  const tree = locationTree;

  const labelOf = (node) => locationNodeLabel(node, lang);
  const countLabel = (n) => T(n + ' sự kiện', n + (n === 1 ? ' event' : ' events'));

  // Manual expand state: roots that actually have events start open, plus
  // every ancestor of the current selection so it's visible on open.
  const [expanded, setExpanded] = useState(() => {
    const init = new Set(tree.roots.filter(r => r.count > 0).map(r => r.id));
    // Map v6: a country with a single city opens that city too ("Vietnam › TP. Hồ Chí Minh › Quận 1…" at a glance).
    for (const r of tree.roots) if (r.count > 0 && r.children.length === 1 && r.children[0].children.length) init.add(r.children[0].id);
    for (const a of locationAncestorIds(tree, curArea.key)) init.add(a);
    return init;
  });
  const toggle = (id) => setExpanded(prev => {
    const next = new Set(prev);
    if (next.has(id)) next.delete(id); else next.add(id);
    return next;
  });

  const [query, setQuery] = useState('');
  const searchIndex = useMemo(() => buildLocationSearchIndex(tree), [tree]);
  const search = useMemo(() => searchLocationTree(tree, searchIndex, query), [tree, searchIndex, query]);

  const isExpanded = (id) => expanded.has(id) || !!(search && search.revealIds.has(id));
  const pathText = (node) => locationAncestorIds(tree, node.id)
    .map(id => labelOf(tree.byId.get(id))).join(' › ');

  // Flattened, in display order. A node is shown in search mode when it's a
  // match, an ancestor of one, or inside a matched node's subtree (so a
  // matched state can still be expanded to browse what's under it).
  const rows = [];
  const walk = (nodes, insideMatch) => {
    for (const node of nodes) {
      const isMatch = !!(search && search.matchIds.has(node.id));
      if (search && !insideMatch && !search.visibleIds.has(node.id)) continue;
      const expandable = node.depth === 0 || node.children.length > 0;
      rows.push({ type: 'node', node, expandable, isMatch });
      if (expandable && isExpanded(node.id)) {
        if (!node.children.length) rows.push({ type: 'empty', node });
        walk(node.children, insideMatch || isMatch);
      }
    }
  };
  walk(tree.roots, false);
  // Map v5 (note 73): opened from the Map, a "Cities" section comes first (MapExplore publishes `mapCities`: cities with
  // events, then the main ones). Picking one flies the map there; Home's area selection is not changed.
  const mapCityList = s.screen === 'mapExplore' && !embedded && Array.isArray(s.mapCities) ? s.mapCities : [];
  const cityRows = query.trim()
    ? searchCities(query, citiesData.cities, Object.fromEntries(mapCityList.map(c => [c.id, c.count])), 5)
    : mapCityList;
  const pickCity = (id) => set({ areaAsking: false, mapCityRequest: { id, t: Date.now() } });
  const noResults = !!search && search.matchIds.size === 0 && cityRows.length === 0;

  // A genuine on/off toggle — this used to always call allowLocation(), so
  // once sharing was on there was no way back to off from here.
  const locationLabel2 = located ? 'Tắt vị trí ▪︎ đang hiển thị khoảng cách' : 'Dùng vị trí của tôi để xem khoảng cách';
  const toggleLocation = located ? denyLocation : allowLocation;

  // iOS: trailing checkmark (SF "checkmark", 11pt semibold), always laid out so counts align.
  const check = (on) => (
    <svg aria-hidden width={11} height={11} viewBox="0 0 12 12" fill="none" stroke={ink} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" style={{ flex: 'none', opacity: on ? 1 : 0 }}>
      <path d="M1.5 6.5l3 3 6-7" />
    </svg>
  );
  // iOS: leaf rows keep a 12pt blank where the chevron would be.
  // Map v6: 20 + the 8 gap lines these rows' text up with the tree names (after their 28px chevron column).
  const spacer = <span aria-hidden style={{ width: 20, flex: 'none' }} />;
  // Map v6: tree rows are [chevron button | name button]; a leaf keeps the chevron's 44px as a blank.
  const CHEVRON_W = 36;
  const treeRow = { display: 'flex', alignItems: 'stretch', borderBottom: `1px solid ${rule}` };
  const nameBtn = { flex: 1, minWidth: 0, minHeight: 44, display: 'flex', alignItems: 'center', gap: 8, padding: '8px 0', border: 'none', background: 'none', cursor: 'pointer', fontFamily: 'inherit', fontSize: 14.5, color: ink, textAlign: 'left' };
  const chevron = (open) => (
    <svg aria-hidden width={12} height={12} viewBox="0 0 12 12" fill="none" stroke={ink} strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" style={{ flex: 'none', opacity: 0.6, transform: open ? 'rotate(90deg)' : 'none', transition: 'transform 0.18s ease' }}>
      <path d="M4 2l4 4-4 4" />
    </svg>
  );
  const rowBase = { display: 'flex', alignItems: 'baseline', gap: 8, padding: embedded ? '9px 0' : '13px 0', borderBottom: `1px solid ${rule}`, cursor: 'pointer', fontSize: 14.5, color: ink };
  const legacyCaption = (
    <span style={{ fontSize: 10.5, fontWeight: 400, color: ink, opacity: 0.55 }}>{T('khu vực quen thuộc', 'familiar area')}</span>
  );

  const embeddedBackdrop = { position: 'fixed', inset: 0, zIndex: 2300, background: 'rgba(12,12,12,0.4)', backdropFilter: 'blur(4px)', WebkitBackdropFilter: 'blur(4px)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: leaving ? 'banbeFade 0.22s ease reverse both' : 'banbeFade 0.2s ease both' };
  const centeredBackdrop = { position: 'absolute', inset: 0, zIndex: 21, background: 'rgba(12,12,12,0.32)', display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: '4px 16px 86px', boxSizing: 'border-box', animation: 'banbeFade 0.2s ease both' };
  const centeredCard = { ...dockGlass({ borderRadius: 26, background: 'color-mix(in srgb, var(--bb-bg) 92%, transparent)', border: '1px solid var(--bb-rule, rgba(var(--bb-fg-rgb), 0.12))' }), position: 'relative', padding: '22px 24px 16px', display: 'flex', flexDirection: 'column', maxHeight: '100%', minHeight: 0, boxSizing: 'border-box', animation: 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' };
  const embeddedCard = { background: paper, color: ink, borderRadius: '22px 22px 0 0', position: 'relative', padding: '18px 22px 26px', display: 'flex', flexDirection: 'column', maxHeight: '94%', height: '94%', minHeight: 0, boxSizing: 'border-box', animation: leaving ? 'banbeSheetOut 0.22s cubic-bezier(.4,0,1,1) both' : 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' };

  const sheet = (
    <div onClick={closeArea} data-testid={embedded ? 'filter-area-backdrop' : undefined} style={embedded ? embeddedBackdrop : centeredBackdrop}>
      <div onClick={(e) => e.stopPropagation()} data-testid={embedded ? 'filter-area-sheet' : undefined} role={embedded ? 'dialog' : undefined} aria-modal={embedded ? true : undefined} style={embedded ? embeddedCard : centeredCard}>
        {/* Absolutely positioned (not a sibling-wrapping header row) so
            "Khu vực" stays a direct child of this sheet container —
            existing tests locate the sheet via
            `page.getByText('Khu vực').locator('..')`. */}
        {embedded ? (
          <button type="button" onClick={closeArea} data-testid="filter-area-done"
            style={{ position: 'absolute', top: 10, right: 12, minHeight: 44, padding: '0 10px', border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer' }}>
            {T('Xong', 'Done')}
          </button>
        ) : (
          <span
            onClick={closeArea}
            data-testid="area-sheet-close"
            aria-label="Đóng"
            style={{ position: 'absolute', top: 20, right: 20, color: ink, opacity: 0.6, cursor: 'pointer', padding: 4, lineHeight: 0 }}
          ><svg width={13} height={13} viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth={1.4} strokeLinecap="round"><path d="M2 2l8 8M10 2l-8 8" /></svg></span>
        )}
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>Khu vực</span>
        <span data-testid="area-sheet-current" style={{ fontSize: 12, color: ink, opacity: 0.65, marginTop: 4 }}>
          {T('Đang xem: ', 'Showing: ')}{curArea.key === LOCATION_ALL ? T('Tất cả khu vực', 'All areas') : curArea.label}
        </span>
        <div className="bb-focus-ring" style={{ background: 'var(--bb-field)', borderRadius: 12, display: 'flex', alignItems: 'center', gap: 8, padding: '9px 12px', marginTop: 12 }}>
          <svg width={13} height={13} viewBox="0 0 24 24" fill="none" stroke={ink} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.55, flex: 'none' }}><circle cx="11" cy="11" r="7" /><path d="M21 21l-4.35-4.35" /></svg>
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={T('Tìm khu vực, tỉnh/thành, bang…', 'Search area, province, state…')}
            data-testid="area-sheet-search" data-bare
            style={{ flex: 1, minWidth: 0, border: 'none', outline: 'none', background: 'transparent', fontSize: 14, color: ink, fontFamily: "'Be Vietnam Pro', sans-serif" }}
          />
          {query && <span onClick={() => setQuery('')} data-testid="area-sheet-search-clear" style={{ cursor: 'pointer', color: ink, opacity: 0.5, fontSize: 16, lineHeight: 1 }}>×</span>}
        </div>
        <div data-testid="area-sheet-tree" style={{ display: 'flex', flexDirection: 'column', marginTop: 6, overflowY: 'auto', minHeight: 0, maxHeight: embedded ? '60vh' : 380 }}>
          {s.screen === 'mapExplore' && !embedded && cityRows.length > 0 && (
            <div data-testid="area-sheet-cities" style={{ display: 'flex', flexDirection: 'column' }}>
              <span style={{ fontSize: 11, fontWeight: 600, color: ink, opacity: 0.6, letterSpacing: '0.04em', textTransform: 'uppercase', padding: '10px 0 2px' }}>{T('Thành phố', 'Cities')}</span>
              {cityRows.map(({ id, count }) => {
                const c = CITY_BY_ID.get(id);
                if (!c) return null;
                return (
                  <div key={id} onClick={() => pickCity(id)} data-testid={`area-city:${id}`} role="button" tabIndex={0}
                    onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); pickCity(id); } }}
                    style={rowBase}>
                    {spacer}
                    <span style={{ flex: 1 }}>{lang === 'en' ? c.en : c.vi}</span>
                    <span style={{ fontSize: 11, color: ink }}>{count ? countLabel(count) : T('Chưa có sự kiện', 'No events yet')}</span>
                    <span aria-hidden style={{ fontSize: 13, color: ink, opacity: 0.6 }}>›</span>
                  </div>
                );
              })}
              <span style={{ fontSize: 11, fontWeight: 600, color: ink, opacity: 0.6, letterSpacing: '0.04em', textTransform: 'uppercase', padding: '14px 0 2px' }}>{T('Khu vực', 'Areas')}</span>
            </div>
          )}
          {!search && (
            <div onClick={() => pickArea(LOCATION_ALL)} data-testid="area-node-all" style={{ ...rowBase, fontWeight: curArea.key === LOCATION_ALL ? 600 : 400 }}>
              {spacer}
              <span style={{ flex: 1 }}>{T('Tất cả khu vực', 'All areas')}</span>
              {check(curArea.key === LOCATION_ALL)}
            </div>
          )}
          {noResults && (
            <div style={{ padding: '14px 2px', fontSize: 13, color: ink, opacity: 0.6 }} data-testid="area-sheet-no-results">
              {T(`Không có khu vực nào khớp với "${query.trim()}".`, `No areas match "${query.trim()}".`)}
            </div>
          )}
          {rows.map((r) => {
            if (r.type === 'empty') {
              return (
                <div key={r.node.id + '#empty'} style={{ padding: '11px 0', paddingLeft: (r.node.depth + 1) * 16 + CHEVRON_W, fontSize: 12.5, color: ink, opacity: 0.6, borderBottom: `1px solid ${rule}` }}>
                  {T('Chưa có sự kiện nào tại ' + labelOf(r.node) + '.', 'No events in ' + labelOf(r.node) + ' yet.')}
                </div>
              );
            }
            const { node, expandable, isMatch } = r;
            const on = curArea.key === node.id;
            const open = expandable && isExpanded(node.id);
            const label = labelOf(node);
            return (
              <div key={node.id} style={{ ...treeRow, paddingLeft: node.depth * 16 }}>
                {/* Only the chevron browses inside (expanding never picks). 44px tall, the row's full height. */}
                {expandable ? (
                  <button type="button" onClick={() => toggle(node.id)} data-testid={`area-chevron:${node.id}`}
                    aria-expanded={open} aria-label={T(`Xem bên trong ${label}`, `Show what's in ${label}`)}
                    style={{ width: CHEVRON_W, minHeight: 44, flex: 'none', marginLeft: -8, paddingLeft: 8, border: 'none', background: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'flex-start' }}>
                    {chevron(open)}
                  </button>
                ) : <span aria-hidden style={{ width: CHEVRON_W - 8, flex: 'none' }} />}
                {/* The name picks the whole node in one tap (Map v6). */}
                <button type="button" onClick={() => pickArea(node.id)} data-testid={`area-node:${node.id}`}
                  aria-pressed={on} aria-label={`${label}, ${countLabel(node.count)}`}
                  style={{ ...nameBtn, fontWeight: on ? 600 : 400 }}>
                  <span style={{ flex: '0 1 auto', minWidth: 0, display: 'flex', flexDirection: 'column' }}>
                    <span>{label}</span>
                    {node.legacy && legacyCaption}
                    {isMatch && node.depth > 0 && (
                      <span style={{ fontSize: 11, fontWeight: 400, color: ink, opacity: 0.55 }}>{pathText(node)}</span>
                    )}
                  </span>
                  {expandable && !on && curArea.key !== LOCATION_ALL && locationAncestorIds(tree, curArea.key).includes(node.id) && <span aria-hidden style={{ width: 5, height: 5, borderRadius: '50%', background: ink, flex: 'none', alignSelf: 'center' }} />}
                  <span style={{ fontSize: 11, color: ink, fontWeight: 400, marginLeft: 'auto' }}>{countLabel(node.count)}</span>
                  {check(on)}
                </button>
              </div>
            );
          })}
        </div>
        <div onClick={toggleLocation} style={{ marginTop: 14, color: ink, fontSize: 13, textAlign: 'center', padding: 8, cursor: 'pointer' }}>{locationLabel2}</div>
      </div>
    </div>
  );
  if (!embedded) return sheet;
  const target = typeof document !== 'undefined' ? (document.querySelector('.bb-screen') || document.body) : null;
  return target ? createPortal(sheet, target) : null;
}

import { useMemo, useState } from 'react';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { paper, ink, rule, dockGlass } from '../../theme.js';
import {
  LOCATION_ALL, countryLabel, locationAncestorIds, buildLocationSearchIndex, searchLocationTree,
} from '../../lib/locationTree.js';

// Location hierarchy sheet (2026-09-30, migration 112) — replaces the old
// flat, hardcoded 6-row "Khu vực" list (AREAS in BanBeContext.jsx) with the
// data-driven tree from src/lib/locationTree.js (built once in
// BanBeContext.jsx as `locationTree`, from the same browsable discovery set
// the old counts used — static demo events that aren't cancelled/ended/
// invite-only + real live public events).
//
// Interaction contract:
//  - chevron rows expand/collapse independently, keyed by stable node id;
//    expanding NEVER changes the active filter.
//  - every expanded node offers "Tất cả tại X" / "All in X" (itself +
//    descendants, deduped by event id — see buildLocationTree's counts).
//  - a leaf row selects itself directly.
//  - search filters the ALREADY-BUILT tree client-side (index built once
//    per tree, not per keystroke) and only OR-s the matches' ancestors into
//    the expanded set at render time — the manual expand state itself is
//    never written by search, so clearing the query restores it exactly.
//  - picking any node (including the empty US root) only calls pickArea —
//    it never touches the GPS/location-permission flow below.
export default function AreaSheet() {
  const { state, set, T, located, pickArea, allowLocation, denyLocation, locationTree, curArea } = useBanBe();
  const s = state;
  const lang = s.lang === 'en' ? 'en' : 'vi';
  const closeArea = () => set({ areaAsking: false });
  const tree = locationTree;

  const labelOf = (node) => (node.kind === 'country' ? countryLabel(node.value, lang) : node.value);
  const countLabel = (n) => T(n + ' sự kiện', n + (n === 1 ? ' event' : ' events'));

  // Manual expand state: roots that actually have events start open, plus
  // every ancestor of the current selection so it's visible on open.
  const [expanded, setExpanded] = useState(() => {
    const init = new Set(tree.roots.filter(r => r.count > 0).map(r => r.id));
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
        rows.push({ type: 'all', node });
        if (!node.children.length) rows.push({ type: 'empty', node });
        walk(node.children, insideMatch || isMatch);
      }
    }
  };
  walk(tree.roots, false);
  const noResults = !!search && search.matchIds.size === 0;

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
  const spacer = <span aria-hidden style={{ width: 12, flex: 'none' }} />;
  const chevron = (open) => (
    <svg aria-hidden width={12} height={12} viewBox="0 0 12 12" fill="none" stroke={ink} strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" style={{ flex: 'none', opacity: 0.6, transform: open ? 'rotate(90deg)' : 'none', transition: 'transform 0.18s ease' }}>
      <path d="M4 2l4 4-4 4" />
    </svg>
  );
  const rowBase = { display: 'flex', alignItems: 'baseline', gap: 8, padding: '13px 0', borderBottom: `1px solid ${rule}`, cursor: 'pointer', fontSize: 14.5, color: ink };
  const legacyCaption = (
    <span style={{ fontSize: 10.5, fontWeight: 400, color: ink, opacity: 0.55 }}>{T('khu vực quen thuộc', 'familiar area')}</span>
  );

  return (
    <div onClick={closeArea} style={{ position: 'absolute', inset: 0, zIndex: 21, background: 'rgba(12,12,12,0.32)', display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: '4px 16px 86px', boxSizing: 'border-box', animation: 'banbeFade 0.2s ease both' }}>
      <div onClick={(e) => e.stopPropagation()} style={{ ...dockGlass({ borderRadius: 26, background: 'color-mix(in srgb, var(--bb-bg) 92%, transparent)', border: '1px solid var(--bb-rule, rgba(var(--bb-fg-rgb), 0.12))' }), position: 'relative', padding: '22px 24px 16px', display: 'flex', flexDirection: 'column', maxHeight: '100%', minHeight: 0, boxSizing: 'border-box', animation: 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
        {/* Absolutely positioned (not a sibling-wrapping header row) so
            "Khu vực" stays a direct child of this sheet container —
            existing tests locate the sheet via
            `page.getByText('Khu vực').locator('..')`. */}
        <span
          onClick={closeArea}
          data-testid="area-sheet-close"
          aria-label="Đóng"
          style={{ position: 'absolute', top: 20, right: 20, color: ink, opacity: 0.6, cursor: 'pointer', padding: 4, lineHeight: 0 }}
        ><svg width={13} height={13} viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth={1.4} strokeLinecap="round"><path d="M2 2l8 8M10 2l-8 8" /></svg></span>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>Khu vực</span>
        <span data-testid="area-sheet-current" style={{ fontSize: 12, color: ink, opacity: 0.65, marginTop: 4 }}>
          {T('Đang xem: ', 'Showing: ')}{curArea.key === LOCATION_ALL ? T('Tất cả khu vực', 'All areas') : curArea.label}
        </span>
        <div style={{ background: 'var(--bb-field)', borderRadius: 12, display: 'flex', alignItems: 'center', gap: 8, padding: '9px 12px', marginTop: 12 }}>
          <svg width={13} height={13} viewBox="0 0 24 24" fill="none" stroke={ink} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.55, flex: 'none' }}><circle cx="11" cy="11" r="7" /><path d="M21 21l-4.35-4.35" /></svg>
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={T('Tìm khu vực, tỉnh/thành, bang…', 'Search area, province, state…')}
            data-testid="area-sheet-search"
            style={{ flex: 1, minWidth: 0, border: 'none', outline: 'none', background: 'transparent', fontSize: 14, color: ink, fontFamily: "'Be Vietnam Pro', sans-serif" }}
          />
          {query && <span onClick={() => setQuery('')} data-testid="area-sheet-search-clear" style={{ cursor: 'pointer', color: ink, opacity: 0.5, fontSize: 16, lineHeight: 1 }}>×</span>}
        </div>
        <div data-testid="area-sheet-tree" style={{ display: 'flex', flexDirection: 'column', marginTop: 6, overflowY: 'auto', minHeight: 0, maxHeight: 380 }}>
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
            const indent = { paddingLeft: r.node.depth * 16 };
            if (r.type === 'all') {
              const on = curArea.key === r.node.id;
              return (
                <div key={r.node.id + '#all'} onClick={() => pickArea(r.node.id)} data-testid={`area-node-all-in:${r.node.id}`} style={{ ...rowBase, paddingLeft: (r.node.depth + 1) * 16, fontWeight: on ? 600 : 400 }}>
                  {spacer}
                  <span style={{ flex: 1 }}>{T('Tất cả tại ', 'All in ')}{labelOf(r.node)}</span>
                  <span style={{ fontSize: 11, color: ink }}>{countLabel(r.node.count)}</span>
                  {check(on)}
                </div>
              );
            }
            if (r.type === 'empty') {
              return (
                <div key={r.node.id + '#empty'} style={{ padding: '11px 0', paddingLeft: (r.node.depth + 1) * 16, fontSize: 12.5, color: ink, opacity: 0.6, borderBottom: `1px solid ${rule}` }}>
                  {T('Chưa có sự kiện nào tại ' + labelOf(r.node) + '.', 'No events in ' + labelOf(r.node) + ' yet.')}
                </div>
              );
            }
            const { node, expandable, isMatch } = r;
            const on = curArea.key === node.id;
            const open = expandable && isExpanded(node.id);
            return (
              <div
                key={node.id}
                onClick={() => (expandable ? toggle(node.id) : pickArea(node.id))}
                data-testid={`area-node:${node.id}`}
                aria-expanded={expandable ? open : undefined}
                style={{ ...rowBase, ...indent, fontWeight: on ? 600 : 400 }}
              >
                {expandable ? chevron(open) : spacer}
                <span style={{ flex: '0 1 auto', minWidth: 0, display: 'flex', flexDirection: 'column' }}>
                  <span>
                    {labelOf(node)}
                  </span>
                  {node.legacy && legacyCaption}
                  {isMatch && node.depth > 0 && (
                    <span style={{ fontSize: 11, fontWeight: 400, color: ink, opacity: 0.55 }}>{pathText(node)}</span>
                  )}
                </span>
                {expandable && curArea.key !== LOCATION_ALL && (on || locationAncestorIds(tree, curArea.key).includes(node.id)) && <span aria-hidden style={{ width: 5, height: 5, borderRadius: '50%', background: ink, flex: 'none', alignSelf: 'center' }} />}
                <span style={{ fontSize: 11, color: ink, fontWeight: 400, marginLeft: 'auto' }}>{countLabel(node.count)}</span>
                {!expandable && check(on)}
              </div>
            );
          })}
        </div>
        <div onClick={toggleLocation} style={{ marginTop: 14, color: ink, fontSize: 13, textAlign: 'center', padding: 8, cursor: 'pointer' }}>{locationLabel2}</div>
      </div>
    </div>
  );
}

import { useMemo, useState } from 'react';
import { useGoc } from '../../state/GocContext.jsx';
import { paper, ink, rule, fieldGlass } from '../../theme.js';
import {
  LOCATION_ALL, countryLabel, locationAncestorIds, buildLocationSearchIndex, searchLocationTree,
} from '../../lib/locationTree.js';

// Location hierarchy sheet (2026-09-30, migration 112) — replaces the old
// flat, hardcoded 6-row "Khu vực" list (AREAS in GocContext.jsx) with the
// data-driven tree from src/lib/locationTree.js (built once in
// GocContext.jsx as `locationTree`, from the same browsable discovery set
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
  const { state, set, T, located, pickArea, allowLocation, denyLocation, locationTree, curArea } = useGoc();
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

  const check = (on) => <span aria-hidden style={{ width: 14, flex: 'none', fontSize: 12, color: ink, opacity: on ? 1 : 0 }}>✓</span>;
  const rowBase = { display: 'flex', alignItems: 'center', gap: 6, padding: '12px 2px', borderBottom: `1px solid ${rule}`, cursor: 'pointer', fontSize: 14.5, color: ink };

  return (
    <div onClick={closeArea} style={{ position: 'absolute', inset: 0, zIndex: 21, background: 'rgba(12,12,12,0.55)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'gocFade 0.2s ease both' }}>
      <div onClick={(e) => e.stopPropagation()} style={{ position: 'relative', background: paper, padding: '26px 24px 36px', display: 'flex', flexDirection: 'column', maxHeight: '86%', animation: 'gocSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
        {/* Absolutely positioned (not a sibling-wrapping header row) so
            "Khu vực" stays a direct child of this sheet container —
            existing tests locate the sheet via
            `page.getByText('Khu vực').locator('..')`. */}
        <span
          onClick={closeArea}
          data-testid="area-sheet-close"
          aria-label="Đóng"
          style={{ position: 'absolute', top: 22, right: 20, fontSize: 15, color: ink, opacity: 0.6, cursor: 'pointer', padding: 4, lineHeight: 1 }}
        >✕</span>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>Khu vực</span>
        <span data-testid="area-sheet-current" style={{ fontSize: 12, color: ink, opacity: 0.65, marginTop: 4 }}>
          {T('Đang xem: ', 'Showing: ')}{curArea.key === LOCATION_ALL ? T('Tất cả khu vực', 'All areas') : curArea.label}
        </span>
        <div style={{ ...fieldGlass({}), display: 'flex', alignItems: 'center', gap: 8, padding: '8px 12px', marginTop: 12 }}>
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={T('Tìm khu vực, tỉnh/thành, bang…', 'Search area, province, state…')}
            data-testid="area-sheet-search"
            style={{ flex: 1, minWidth: 0, border: 'none', outline: 'none', background: 'transparent', fontSize: 13.5, color: ink, fontFamily: "'Be Vietnam Pro', sans-serif" }}
          />
          {query && <span onClick={() => setQuery('')} data-testid="area-sheet-search-clear" style={{ cursor: 'pointer', color: ink, opacity: 0.5, fontSize: 16, lineHeight: 1 }}>×</span>}
        </div>
        <div data-testid="area-sheet-tree" style={{ display: 'flex', flexDirection: 'column', marginTop: 6, overflowY: 'auto', minHeight: 0 }}>
          {!search && (
            <div onClick={() => pickArea(LOCATION_ALL)} data-testid="area-node-all" style={{ ...rowBase, fontWeight: curArea.key === LOCATION_ALL ? 600 : 400 }}>
              {check(curArea.key === LOCATION_ALL)}
              <span style={{ flex: 1 }}>{T('Tất cả khu vực', 'All areas')}</span>
            </div>
          )}
          {noResults && (
            <div style={{ padding: '14px 2px', fontSize: 13, color: ink, opacity: 0.6 }} data-testid="area-sheet-no-results">
              {T(`Không có khu vực nào khớp với "${query.trim()}".`, `No areas match "${query.trim()}".`)}
            </div>
          )}
          {rows.map((r) => {
            const indent = { paddingLeft: 2 + r.node.depth * 16 };
            if (r.type === 'all') {
              const on = curArea.key === r.node.id;
              return (
                <div key={r.node.id + '#all'} onClick={() => pickArea(r.node.id)} data-testid={`area-node-all-in:${r.node.id}`} style={{ ...rowBase, paddingLeft: 2 + (r.node.depth + 1) * 16, fontSize: 13.5, fontWeight: on ? 600 : 400 }}>
                  {check(on)}
                  <span style={{ flex: 1 }}>{T('Tất cả tại ', 'All in ')}{labelOf(r.node)}</span>
                  <span style={{ fontSize: 11, color: ink }}>{countLabel(r.node.count)}</span>
                </div>
              );
            }
            if (r.type === 'empty') {
              return (
                <div key={r.node.id + '#empty'} style={{ padding: '10px 2px', paddingLeft: 2 + (r.node.depth + 1) * 16 + 20, fontSize: 12.5, color: ink, opacity: 0.6, borderBottom: `1px solid ${rule}` }}>
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
                style={{ ...rowBase, ...indent, fontWeight: on || node.depth === 0 ? 600 : 400 }}
              >
                {expandable
                  ? <span aria-hidden style={{ width: 14, flex: 'none', fontSize: 10, color: ink, opacity: 0.7 }}>{open ? '▾' : '▸'}</span>
                  : check(on)}
                <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
                  <span>
                    {labelOf(node)}
                    {node.legacy && (
                      <span style={{ marginLeft: 6, fontSize: 10.5, fontWeight: 400, color: ink, opacity: 0.55 }}>
                        {T('khu vực quen thuộc', 'familiar area')}
                      </span>
                    )}
                    {expandable && on && <span style={{ marginLeft: 6, fontSize: 11 }}>✓</span>}
                  </span>
                  {isMatch && node.depth > 0 && (
                    <span style={{ fontSize: 11, fontWeight: 400, color: ink, opacity: 0.55 }}>{pathText(node)}</span>
                  )}
                </span>
                <span style={{ fontSize: 11, color: ink, fontWeight: 400 }}>{countLabel(node.count)}</span>
              </div>
            );
          })}
        </div>
        <div onClick={toggleLocation} style={{ marginTop: 14, color: ink, fontSize: 13, textAlign: 'center', padding: 8, cursor: 'pointer' }}>{locationLabel2}</div>
      </div>
    </div>
  );
}

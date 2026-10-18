// Location filter as a compact pop-up menu (iOS parity, 2026-10-18) — the web twin of HomeView's native
// `Menu`: a frosted card anchored under the chip, "All locations" (✓ when active), one row per country that
// drills into its areas (with a back row and "All in X"), then the location toggle and "Search locations…",
// which opens the full AreaSheet. Picking anything only calls pickArea, never the GPS flow.
import { useEffect, useState } from 'react';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { ink, paper } from '../../theme.js';
import { LOCATION_ALL, countryLabel } from '../../lib/locationTree.js';

export default function AreaMenu() {
  const { state: s, set, T, located, pickArea, allowLocation, denyLocation, locationTree, curArea } = useBanBe();
  const lang = s.lang === 'en' ? 'en' : 'vi';
  const anchor = s.areaMenuAnchor || { left: 20, bottom: 120 };
  const [path, setPath] = useState([]); // drilled-into node ids
  const close = () => set({ areaMenuOpen: false });
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') close(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }); // eslint-disable-line react-hooks/exhaustive-deps

  const node = path.length ? locationTree.byId.get(path[path.length - 1]) : null;
  const items = node ? node.children : locationTree.roots;
  const labelOf = (n) => (n.kind === 'country' ? countryLabel(n.value, lang) : n.value);
  const pick = (id) => { pickArea(id); close(); };

  const row = (key, content, onClick, { selected = false, chevron = false, testId } = {}) => (
    <button key={key} type="button" onClick={onClick} data-testid={testId} role="menuitem"
      style={{ display: 'flex', alignItems: 'center', gap: 10, width: '100%', minHeight: 50, padding: '10px 20px', border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 17, textAlign: 'left', cursor: 'pointer' }}>
      <span aria-hidden style={{ width: 18, flex: 'none', fontWeight: 600 }}>{selected ? '✓' : ''}</span>
      <span style={{ flex: 1, minWidth: 0 }}>{content}</span>
      {chevron && <span aria-hidden style={{ fontSize: 20, opacity: 0.8 }}>›</span>}
    </button>
  );

  return (
    <div onClick={close} data-testid="area-menu-backdrop" style={{ position: 'fixed', inset: 0, zIndex: 2200 }}>
      <div role="menu" aria-label={T('Khu vực', 'Location')} onClick={(e) => e.stopPropagation()} data-testid="area-menu"
        style={{ position: 'absolute', top: anchor.bottom + 6, left: Math.max(12, Math.min(anchor.left, window.innerWidth - 300)), width: 280, maxHeight: '70vh', overflowY: 'auto',
          borderRadius: 26, padding: '8px 0', color: ink,
          background: 'color-mix(in srgb, var(--bb-bg) 78%, transparent)', backdropFilter: 'blur(28px) saturate(1.6)', WebkitBackdropFilter: 'blur(28px) saturate(1.6)',
          border: '1px solid rgba(255,255,255,0.45)', boxShadow: '0 18px 50px rgba(27,25,22,0.28)', transformOrigin: 'top left', animation: 'banbeFade .16s ease-out' }}>
        {node ? (
          <>
            {row('back', <span style={{ fontWeight: 600 }}>‹ {labelOf(node)}</span>, () => setPath(p => p.slice(0, -1)), { testId: 'area-menu-back' })}
            {row('all-in', T(`Tất cả tại ${labelOf(node)}`, `All in ${labelOf(node)}`), () => pick(node.id), { selected: curArea.key === node.id, testId: 'area-menu-all-in' })}
          </>
        ) : (
          row('all', T('Mọi nơi', 'All locations'), () => pick(LOCATION_ALL), { selected: curArea.key === LOCATION_ALL, testId: 'area-menu-all' })
        )}
        {items.map(n => row(n.id, labelOf(n), () => (n.children.length ? setPath(p => [...p, n.id]) : pick(n.id)),
          { selected: curArea.key === n.id, chevron: n.children.length > 0, testId: `area-menu-node-${n.id}` }))}
        {!node && (
          <>
            <div style={{ height: 1, margin: '8px 20px', background: 'rgba(var(--bb-fg-rgb),0.12)' }} />
            {row('loc', located ? T('Tắt vị trí ▪︎ đang hiện khoảng cách', 'Turn off location ▪︎ showing distance') : T('Dùng vị trí để xem khoảng cách', 'Use my location for distance'),
              () => { (located ? denyLocation : allowLocation)(); close(); }, { testId: 'area-menu-location' })}
            {row('search', T('Tìm khu vực…', 'Search locations…'), () => set({ areaMenuOpen: false, areaAsking: true }), { testId: 'area-menu-search' })}
          </>
        )}
      </div>
    </div>
  );
}

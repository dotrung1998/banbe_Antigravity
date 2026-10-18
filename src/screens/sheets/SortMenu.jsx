// Sort as a compact pop-up menu (note 50) — the web twin of HomeView's native `Menu` on the sort button, built
// like AreaMenu: a frosted card anchored under the button that lists ONLY the sort options (✓ on the current one).
// Nearest needs the device location; without it the row says so and asks for it instead of silently doing nothing.
// Portals into .bb-screen because Home's root keeps an animation transform, which would otherwise become the
// containing block for this fixed overlay.
import { useEffect } from 'react';
import { createPortal } from 'react-dom';
import { ink } from '../../theme.js';
import { SORT_LABELS } from './HomeFilterSheet.jsx';

const MODES = ['soonest', 'nearest', 'popular', 'price'];

export default function SortMenu({ anchor, value, canSortNearest, onPick, onAskLocation, onClose, T }) {
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const target = typeof document !== 'undefined' ? (document.querySelector('.bb-screen') || document.body) : null;
  if (!target) return null;
  const a = anchor || { left: 20, bottom: 120, width: 390 };
  return createPortal(
    <div onClick={onClose} data-testid="sort-menu-backdrop" style={{ position: 'fixed', inset: 0, zIndex: 2200 }}>
      <div role="menu" aria-label={T('Sắp xếp', 'Sort by')} onClick={(e) => e.stopPropagation()} data-testid="sort-menu"
        style={{ position: 'absolute', top: a.bottom + 6, left: Math.max(12, Math.min(a.left, (a.width || window.innerWidth) - 272)), width: 260,
          borderRadius: 26, padding: '8px 0', color: ink,
          background: 'color-mix(in srgb, var(--bb-bg) 78%, transparent)', backdropFilter: 'blur(28px) saturate(1.6)', WebkitBackdropFilter: 'blur(28px) saturate(1.6)',
          border: '1px solid rgba(255,255,255,0.45)', boxShadow: '0 18px 50px rgba(27,25,22,0.28)', transformOrigin: 'top left', animation: 'banbeFade .16s ease-out' }}>
        {MODES.map(m => {
          const needsLocation = m === 'nearest' && !canSortNearest;
          const label = T(...SORT_LABELS[m]);
          return (
            <button key={m} type="button" role="menuitemradio" aria-checked={value === m} data-testid={`sort-menu-${m}`}
              onClick={() => (needsLocation ? onAskLocation() : onPick(m))}
              style={{ display: 'flex', alignItems: 'center', gap: 10, width: '100%', minHeight: 50, padding: '10px 20px', border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 17, textAlign: 'left', cursor: 'pointer' }}>
              <span aria-hidden style={{ width: 18, flex: 'none', fontWeight: 600 }}>{value === m ? '✓' : ''}</span>
              <span style={{ flex: 1, minWidth: 0 }}>
                {label}
                {needsLocation && <span style={{ display: 'block', fontSize: 12.5, opacity: 0.6 }}>{T('Bật vị trí để dùng', 'Turn on location to use')}</span>}
              </span>
            </button>
          );
        })}
      </div>
    </div>,
    target,
  );
}

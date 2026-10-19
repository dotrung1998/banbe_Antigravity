// Frosted pop-up menu — the one used by the calendar pill beside an event title (EventPlanActions.jsx), shared so
// Event Detail's ⋯ button opens the same kind of menu (note 52). Web twin of iOS's native SwiftUI `Menu`.
// Closes on a tap outside, on Escape, and after any item is chosen.
import { createContext, useContext, useEffect, useRef } from 'react';
import { ink } from '../theme.js';

const CloseCtx = createContext(() => {});

export const glassMenuSurface = {
  padding: '6px 0', borderRadius: 22, color: ink,
  background: 'color-mix(in srgb, var(--bb-bg) 80%, transparent)',
  backdropFilter: 'blur(28px) saturate(1.6)', WebkitBackdropFilter: 'blur(28px) saturate(1.6)',
  border: '1px solid rgba(255,255,255,0.45)', boxShadow: '0 18px 50px rgba(27,25,22,0.28)',
  animation: 'banbeFade .16s ease-out',
};

/**
 * `trigger` is the button that toggles `open` (the caller owns the state). The menu hangs `top` px below the
 * wrapper's top edge, right-aligned. `wrapStyle` positions the wrapper itself (e.g. `position: 'fixed'`).
 */
export default function GlassMenu({ open, onOpenChange, trigger, children, width = 260, top = 42, wrapStyle, wrapTestId, menuTestId, label }) {
  const wrap = useRef(null);
  useEffect(() => {
    if (!open) return undefined;
    const onDown = (e) => { if (!wrap.current?.contains(e.target)) onOpenChange(false); };
    const onKey = (e) => { if (e.key === 'Escape') onOpenChange(false); };
    document.addEventListener('pointerdown', onDown);
    window.addEventListener('keydown', onKey);
    return () => { document.removeEventListener('pointerdown', onDown); window.removeEventListener('keydown', onKey); };
  }, [open, onOpenChange]);
  return (
    <div ref={wrap} style={{ position: 'relative', ...wrapStyle }} data-testid={wrapTestId}>
      {trigger}
      {open && (
        <div role="menu" aria-label={label} data-testid={menuTestId} style={{ position: 'absolute', right: 0, top, zIndex: 30, width, ...glassMenuSurface }}>
          <CloseCtx.Provider value={() => onOpenChange(false)}>{children}</CloseCtx.Provider>
        </div>
      )}
    </div>
  );
}

export function GlassMenuItem({ icon, children, onClick, disabled = false, danger = false, testId }) {
  const close = useContext(CloseCtx);
  return (
    <button type="button" role="menuitem" disabled={disabled} data-testid={testId}
      onClick={() => { close(); onClick?.(); }}
      style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', textAlign: 'left', minHeight: 46, padding: '10px 18px', border: 'none', background: 'none', fontFamily: 'inherit',
        fontSize: 15, color: danger ? 'var(--bb-alert)' : ink, opacity: disabled ? 0.6 : 1, cursor: disabled ? 'default' : 'pointer' }}>
      {icon && <span aria-hidden style={{ flex: 'none', width: 20, display: 'inline-flex', justifyContent: 'center' }}>{icon}</span>}
      <span style={{ flex: 1, minWidth: 0 }}>{children}</span>
    </button>
  );
}

export function GlassMenuDivider() {
  return <div aria-hidden style={{ height: 1, margin: '4px 18px', background: 'rgba(var(--bb-fg-rgb),0.12)' }} />;
}

import { useEffect, useRef, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { BAR_HEIGHT, BAR_BOTTOM_OFFSET, DOCK_MARGIN, CREATE_SIZE } from './BottomTabBar.jsx';
import { ink, paper, rule, barGlass } from '../theme.js';

// TASK C (2026-10-03 fix pass) — replaces the old floating "Tạo sự kiện"
// pill (CreateEventFab.jsx, removed) with a compact "+" that sits right
// next to the dock, only where the dock itself is showing — a screen with
// no dock (Dashboard) never had this floating button conflict with
// anything, but it also already has its own in-content "+ Tạo sự kiện
// mới" entry (Dashboard.jsx), so nothing is lost there. Visible only in
// organizer mode (current UI preference — see 18-organizer-mode's own
// fix — never eligibility), matching the old pill's own gate exactly.
//
// TASK 1 (2026-10-05 fix pass) — this used to own its own absolute
// positioning (`right: 16`) independent of the dock's own centered
// position, which is the actual overlap this ticket reports on a real
// iPhone. Now a plain flex CHILD of DockRow (App.jsx), sized to
// `CREATE_SIZE` (== BAR_HEIGHT, so it shares the dock's vertical center
// structurally) — DockRow itself owns the shared outer margin/gap. The
// popover menu this button used to open in place is gone too — replaced by
// a real bottom tray (below) that rises above the dock and dims the actual
// screen, which an absolutely-positioned popover anchored to this button
// alone could never do convincingly.
export default function DockCreateButton() {
  const { state, T, goCreate } = useGoc();
  const [open, setOpen] = useState(false);
  const [dragY, setDragY] = useState(0);
  const dragRef = useRef(null);

  if (!state.organizerMode) return null;
  // Same "never above a full-screen sheet" list the old pill used —
  // matches rule C5 exactly (never over modal sheets/story/Pulse).
  if (state.storyViewer || state.scanningQr || state.photoViewer || state.chatPhotoViewer || state.reasonPrompt || state.pulseOpen) return null;

  const close = () => { setOpen(false); setDragY(0); };
  const choose = () => { close(); goCreate(); };

  // "keyboard Escape/back where relevant" — real menu semantics on web
  // means Escape closes it, matching how the browser's own <select>/native
  // menus behave, not just an outside pointer tap.
  useEffect(() => {
    if (!open) return;
    const onKey = (e) => { if (e.key === 'Escape') close(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const onTrayPointerDown = (e) => {
    dragRef.current = { startY: e.clientY, dragging: true };
    e.currentTarget.setPointerCapture?.(e.pointerId);
  };
  const onTrayPointerMove = (e) => {
    if (!dragRef.current?.dragging) return;
    setDragY(Math.max(0, e.clientY - dragRef.current.startY));
  };
  const onTrayPointerUp = () => {
    if (!dragRef.current?.dragging) return;
    dragRef.current.dragging = false;
    if (dragY > 60) close(); else setDragY(0);
  };

  return (
    <>
      {/* BUG (2026-10-06 fix pass) — this used to be a SOLID `ink`-filled
          circle with its own independently-chosen shadow — a visually-
          similar but genuinely different style from the dock's own
          translucent `barGlass` pill, which is exactly why it read as "a
          solid black circle next to a translucent dock" on a real device.
          Now reuses the dock's own `barGlass()` recipe verbatim (same
          background/backdrop-filter as `BottomTabBar.jsx`) plus its exact
          shadow, with the glyph switched from white-on-ink to plain `ink`,
          since a translucent material needs an ink-colored glyph for
          contrast the same way every dock tab icon already is. */}
      <div
        onClick={() => setOpen((v) => !v)}
        data-testid="dock-create-button"
        aria-label={T('Tạo mới', 'Create')}
        aria-expanded={open}
        role="button"
        style={{
          ...barGlass({}),
          flex: '0 0 auto',
          width: CREATE_SIZE, height: CREATE_SIZE, borderRadius: '50%',
          color: ink,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: '0 8px 24px rgba(27,25,22,0.18)', cursor: 'pointer',
          border: `1px solid ${rule}`,
          transition: 'transform 0.15s ease',
          transform: open ? 'rotate(45deg)' : 'rotate(0deg)',
        }}
      >
        <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden>
          <path d="M12 5v14M5 12h14" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" />
        </svg>
      </div>

      {/* TASK 1 — the tray: a real bottom sheet (fixed to the viewport, not
          this button's own flex position) rising above the dock, with a
          scrim, outside-tap-to-close, and downward-drag-to-dismiss.
          Rendered via a portal-less fixed overlay — position: fixed already
          escapes DockRow's own layout, so it doesn't need to live in a
          different DOM subtree the way a true portal would. */}
      {open && (
        <div
          onClick={close}
          data-testid="dock-create-backdrop"
          style={{ position: 'fixed', inset: 0, background: 'rgba(27,25,22,0.28)', zIndex: 60 }}
        />
      )}
      {open && (
        <div
          role="menu"
          aria-label={T('Tạo mới', 'Create')}
          data-testid="dock-create-menu"
          onPointerDown={onTrayPointerDown}
          onPointerMove={onTrayPointerMove}
          onPointerUp={onTrayPointerUp}
          onPointerCancel={onTrayPointerUp}
          style={{
            position: 'fixed', left: '50%', bottom: BAR_HEIGHT + BAR_BOTTOM_OFFSET + 14,
            transform: `translate(-50%, ${dragY}px)`,
            width: `calc(100% - ${DOCK_MARGIN * 2}px)`, maxWidth: 340,
            background: paper, borderRadius: 20, boxShadow: '0 12px 32px rgba(27,25,22,0.24)',
            border: `1px solid ${rule}`, overflow: 'hidden', zIndex: 61,
            touchAction: 'none',
          }}
        >
          <div style={{ display: 'flex', justifyContent: 'center', padding: '9px 0 4px' }}>
            <div style={{ width: 36, height: 4, borderRadius: 2, background: rule }} />
          </div>
          <div
            role="menuitem"
            onClick={choose}
            data-testid="dock-create-menu-event"
            style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '13px 18px 17px', cursor: 'pointer', fontSize: 14, color: ink }}
          >
            <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden>
              <path d="M12 4v16M4 12h16" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
            </svg>
            {T('Tạo sự kiện', 'Create event')}
          </div>
        </div>
      )}
    </>
  );
}

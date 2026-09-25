import { useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { showsBottomBar, BAR_HEIGHT, BAR_BOTTOM_OFFSET } from './BottomTabBar.jsx';
import { ink, paper, rule } from '../theme.js';

// TASK C (2026-10-03 fix pass) — replaces the old floating "Tạo sự kiện"
// pill (CreateEventFab.jsx, removed) with a compact "+" that sits right
// next to the dock, only where the dock itself is showing — a screen with
// no dock (Dashboard) never had this floating button conflict with
// anything, but it also already has its own in-content "+ Tạo sự kiện
// mới" entry (Dashboard.jsx), so nothing is lost there. Visible only in
// organizer mode (current UI preference — see 18-organizer-mode's own
// fix — never eligibility), matching the old pill's own gate exactly.
const SIZE = 46;

export default function DockCreateButton() {
  const { state, T, goCreate } = useGoc();
  const [open, setOpen] = useState(false);
  const showBar = showsBottomBar(state.screen);
  if (!showBar || !state.organizerMode) return null;
  // Same "never above a full-screen sheet" list the old pill used —
  // matches rule C5 exactly (never over modal sheets/story/Pulse).
  if (state.storyViewer || state.scanningQr || state.photoViewer || state.chatPhotoViewer || state.reasonPrompt || state.pulseOpen) return null;

  const choose = () => { setOpen(false); goCreate(); };

  return (
    <>
      {open && (
        // Outside-tap-to-close backdrop (rule C6) — transparent, just for
        // hit-testing; sits under the menu itself but above everything else.
        <div onClick={() => setOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 26 }} data-testid="dock-create-backdrop" />
      )}
      <div
        style={{
          position: 'absolute', right: 16, bottom: BAR_BOTTOM_OFFSET + (BAR_HEIGHT - SIZE) / 2,
          zIndex: 27, // above the backdrop and the dock (25), same "never above a full-screen sheet" ceiling the old pill respected
        }}
      >
        {open && (
          <div
            role="menu"
            aria-label={T('Tạo mới', 'Create')}
            data-testid="dock-create-menu"
            style={{
              position: 'absolute', bottom: SIZE + 10, right: 0, minWidth: 176,
              background: paper, borderRadius: 14, boxShadow: '0 10px 28px rgba(27,25,22,0.22)',
              border: `1px solid ${rule}`, overflow: 'hidden',
            }}
          >
            <div
              role="menuitem"
              onClick={choose}
              data-testid="dock-create-menu-event"
              style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '13px 14px', cursor: 'pointer', fontSize: 13.5, color: ink }}
            >
              <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden>
                <path d="M12 4v16M4 12h16" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
              </svg>
              {T('Tạo sự kiện', 'Create event')}
            </div>
          </div>
        )}
        <div
          onClick={() => setOpen(v => !v)}
          data-testid="dock-create-button"
          aria-label={T('Tạo mới', 'Create')}
          aria-expanded={open}
          role="button"
          style={{
            width: SIZE, height: SIZE, borderRadius: '50%',
            background: ink, color: paper,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            boxShadow: '0 8px 20px rgba(27,25,22,0.28)', cursor: 'pointer',
            transition: 'transform 0.15s ease',
            transform: open ? 'rotate(45deg)' : 'rotate(0deg)',
          }}
        >
          <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden>
            <path d="M12 5v14M5 12h14" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" />
          </svg>
        </div>
      </div>
    </>
  );
}

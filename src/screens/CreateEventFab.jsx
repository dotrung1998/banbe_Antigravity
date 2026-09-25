import { useGoc } from '../state/GocContext.jsx';
import { inkButton } from '../theme.js';

// TASK C (2026-10-01 UX foundation pass) — persistent compact pill FAB for
// organizer mode, matching Reserve's own CTA visual language (inkButton:
// dark glass pill, soft drop shadow, press state) rather than inventing a
// new button style. Placement is an ALLOWLIST (Home/Dashboard/Account only,
// per this ticket's own "Placement" list), not a "hide everywhere except"
// denylist — safer by construction, since any new screen added later
// defaults to NOT showing the FAB instead of silently inheriting it.
const CREATE_FAB_SCREENS = new Set(['home', 'dashboard', 'profile']);

export function showsCreateEventFab(screen) {
  return CREATE_FAB_SCREENS.has(screen);
}

export default function CreateEventFab({ bottom }) {
  const { state, T, goCreate } = useGoc();
  if (!state.organizerMode || !showsCreateEventFab(state.screen)) return null;
  // Never over a full-screen sheet (story viewer, QR scan, photo viewers,
  // reason prompt) even on an allowlisted screen underneath it.
  if (state.storyViewer || state.scanningQr || state.photoViewer || state.chatPhotoViewer || state.reasonPrompt || state.pulseOpen) return null;

  return (
    <div
      onClick={goCreate}
      data-testid="create-event-fab"
      style={{
        ...inkButton({}),
        position: 'absolute', right: 20, bottom,
        borderRadius: 999, padding: '13px 20px 13px 16px',
        display: 'flex', alignItems: 'center', gap: 7,
        zIndex: 24, // just under BottomTabBar's 25 so the bar still wins if they ever overlap
        transition: 'transform 0.15s ease',
      }}
      onPointerDown={(e) => { e.currentTarget.style.transform = 'scale(0.95)'; }}
      onPointerUp={(e) => { e.currentTarget.style.transform = 'scale(1)'; }}
      onPointerLeave={(e) => { e.currentTarget.style.transform = 'scale(1)'; }}
    >
      <svg viewBox="0 0 24 24" width="16" height="16">
        <path d="M12 5v14M5 12h14" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" />
      </svg>
      <span>{T('Tạo sự kiện', 'Create event')}</span>
    </div>
  );
}

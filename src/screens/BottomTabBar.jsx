import { useGoc } from '../state/GocContext.jsx';
import { ink, paper, alert, barGlass } from '../theme.js';

// Custom minimal icon set, deliberately NOT the classic IG/FB/Twitter shapes
// (no filled house, no paper-plane, no magnifying-glass silhouette) — built
// from the same visual vocabulary as public/banbe-mark.png (bold, round-
// capped strokes; an open ring; small filled dots) so the tab bar reads as
// this app's own mark family, just re-composed per meaning. `notifications`
// also reuses the arc motif already drawn by Loading.jsx/Splash.jsx, rather
// than introducing an unrelated bell glyph.
const ICONS = {
  map: (c) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <circle cx="7" cy="16" r="3.2" fill="none" stroke={c} strokeWidth="2.2" />
      <path d="M9.6 13.6 L16 7" stroke={c} strokeWidth="2.2" strokeLinecap="round" fill="none" />
      <circle cx="17.3" cy="5.7" r="1.5" fill={c} />
    </svg>
  ),
  notifications: (c) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <circle cx="12" cy="16" r="1.6" fill={c} />
      <path d="M8.5 12.5a5 5 0 0 1 7 0" fill="none" stroke={c} strokeWidth="2.2" strokeLinecap="round" />
      <path d="M6 9.3a9 9 0 0 1 12 0" fill="none" stroke={c} strokeWidth="2.2" strokeLinecap="round" opacity="0.55" />
    </svg>
  ),
  inbox: (c) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <circle cx="7" cy="9" r="2" fill={c} />
      <circle cx="17" cy="15" r="2" fill={c} />
      <path d="M9 10.5 Q13 12 15 13.5" stroke={c} strokeWidth="2.2" strokeLinecap="round" fill="none" />
    </svg>
  ),
  profile: (c) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <circle cx="12" cy="8.5" r="3.4" fill="none" stroke={c} strokeWidth="2.2" />
      <path d="M5.5 19c1.2-3.6 4-5.4 6.5-5.4s5.3 1.8 6.5 5.4" stroke={c} strokeWidth="2.2" strokeLinecap="round" fill="none" />
    </svg>
  ),
};

// Top-level/primary screens only — flow screens that own the bottom of the
// viewport for their own CTA (Reserve's "Hold · 30 minutes", HostIntro's
// "Create your first event", etc.) are deliberately excluded so the two
// never collide.
const BAR_SCREENS = new Set(['home', 'mapExplore', 'notifications', 'inbox', 'profile']);

export function showsBottomBar(screen) {
  return BAR_SCREENS.has(screen);
}

export default function BottomTabBar({ collapsed }) {
  const { state, T, goProfile, goInbox, goNotifications, goMapExplore } = useGoc();
  const s = state;

  // Inbox/messages has no unread-tracking concept anywhere in the schema
  // (no read_at on `messages`, no per-thread unread flag) — confirmed via
  // grep before writing this, so no badge is fabricated for it. Only
  // Notifications has a real unread count (s.unreadNotifications, already
  // used by the old header bell).
  const items = [
    { key: 'mapExplore', icon: 'map', onClick: goMapExplore, label: T('Bản đồ', 'Map'), testId: 'tab-map', badge: 0 },
    { key: 'notifications', icon: 'notifications', onClick: goNotifications, label: T('Thông báo', 'Notifications'), testId: 'tab-notifications', badge: s.unreadNotifications || 0 },
    { key: 'inbox', icon: 'inbox', onClick: goInbox, label: T('Tin nhắn', 'Messages'), testId: 'tab-inbox', badge: 0 },
    { key: 'profile', icon: 'profile', onClick: goProfile, label: T('Tài khoản', 'Account'), testId: 'tab-profile', badge: 0 },
  ];

  const barHeight = collapsed ? 52 : 60;
  const iconSize = collapsed ? 19 : 22;

  return (
    <div
      data-testid="bottom-tab-bar"
      style={{
        ...barGlass({}),
        position: 'absolute', left: '50%', bottom: 18, transform: 'translateX(-50%)',
        width: 'calc(100% - 56px)', maxWidth: 320,
        borderRadius: 999, zIndex: 20,
        display: 'flex', justifyContent: 'space-around', alignItems: 'center',
        height: barHeight, boxShadow: '0 8px 24px rgba(27,25,22,0.18)',
        transition: 'height 0.22s cubic-bezier(.22,.61,.36,1)',
      }}
    >
      {items.map((item) => (
        <div
          key={item.key}
          onClick={item.onClick}
          data-testid={item.testId}
          aria-label={item.label}
          style={{ position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center', width: 40, height: '100%', cursor: 'pointer' }}
        >
          <div style={{ width: iconSize, height: iconSize, transition: 'width 0.22s ease, height 0.22s ease' }}>
            {ICONS[item.icon](ink)}
          </div>
          {item.badge > 0 && (
            <span
              style={{
                position: 'absolute', top: 6, right: 3, minWidth: 14, height: 14, padding: '0 3px',
                borderRadius: 7, background: alert, color: '#fff', fontSize: 9, fontWeight: 700,
                lineHeight: '14px', textAlign: 'center',
              }}
            >
              {item.badge > 9 ? '9+' : item.badge}
            </span>
          )}
        </div>
      ))}
    </div>
  );
}

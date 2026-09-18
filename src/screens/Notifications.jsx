import { useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { agoLabel, bg } from '../data/events.js';
import { avatarSourceFor, notificationAgeBucket } from '../lib/notifications.js';
import { paper, ink, display } from '../theme.js';

// Redesigned to read like Instagram/Facebook's own notification list
// (07-notifications.md's 2026-09-18 follow-up): a left avatar per row
// (derived per-kind — see avatarSourceFor), a bold title + single-line
// truncated preview, and time-based sections with unread always pinned to
// the top regardless of age. Same fonts/colors as everywhere else in the
// app (theme.js's paper/ink/display) — no new design system.
const COLLAPSE_AT = 20;

export default function Notifications() {
  const {
    state, T, trStatus, goHome, openNotification, deleteNotification,
  } = useGoc();
  const s = state;
  // Which sections have had their "Xem thêm" tapped — purely a render-time
  // slice of already-loaded data (loadNotifications() fetches up to 50 at
  // once), so a plain local Set is enough; nothing here needs a new query.
  const [expandedSections, setExpandedSections] = useState(() => new Set());
  const expandSection = (key) => setExpandedSections(prev => new Set(prev).add(key));

  const withAgo = (n) => ({
    ...n,
    ago: trStatus(agoLabel(Math.max(1, Math.round((Date.now() - new Date(n.created_at).getTime()) / 3600000)))),
  });

  const now = Date.now();
  const unread = s.notifications.filter(n => !n.read_at);
  // Instagram/Facebook's own convention: unread sits in its own section on
  // top regardless of age — a week-old unread notification still belongs in
  // "Mới", not "Cũ hơn". Everything else buckets by age.
  const buckets = { today: [], week: [], older: [] };
  for (const n of s.notifications) {
    if (!n.read_at) continue;
    buckets[notificationAgeBucket(n.created_at, now)].push(n);
  }
  const sections = [
    { key: 'new', title: T('Mới', 'New'), items: unread, unread: true },
    { key: 'today', title: T('Hôm nay', 'Today'), items: buckets.today },
    { key: 'week', title: T('7 ngày qua', 'Last 7 days'), items: buckets.week },
    { key: 'older', title: T('Cũ hơn', 'Older'), items: buckets.older },
  ].filter(sec => sec.items.length > 0);

  const avatarMaps = {
    bookingById: s.notificationBookingById,
    eventPhotoByEventId: s.notificationEventPhotoByEventId,
    avatarByUserId: s.notificationAvatarByUserId,
  };

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Notifications">
      <div style={{ padding: '70px 24px 8px', display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <span style={{ ...display(27) }}>{T('Thông báo', 'Notifications')}</span>
        <span onClick={goHome} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>{T('Xong', 'Done')}</span>
      </div>
      {sections.length > 0 ? (
        <div style={{ padding: '14px 24px 40px' }}>
          {sections.map(sec => {
            const expanded = expandedSections.has(sec.key);
            const visible = expanded ? sec.items : sec.items.slice(0, COLLAPSE_AT);
            const hiddenCount = sec.items.length - visible.length;
            return (
              <Section key={sec.key} title={sec.title}>
                {visible.map(withAgo).map(n => (
                  <Row
                    key={n.id}
                    n={n}
                    unread={sec.unread}
                    avatar={avatarSourceFor(n, avatarMaps, s.accountType)}
                    onClick={() => openNotification(n)}
                    onDelete={() => deleteNotification(n.id)}
                  />
                ))}
                {hiddenCount > 0 && (
                  <div
                    onClick={() => expandSection(sec.key)}
                    data-testid={`notifications-more-${sec.key}`}
                    style={{ padding: '12px 0', fontSize: 12.5, fontWeight: 600, color: ink, opacity: 0.65, cursor: 'pointer' }}
                  >
                    {T(`Xem thêm (${hiddenCount})`, `View more (${hiddenCount})`)}
                  </div>
                )}
              </Section>
            );
          })}
        </div>
      ) : (
        <div style={{ padding: '80px 40px', textAlign: 'center' }}>
          <p style={{ fontSize: 14, lineHeight: 1.55, color: ink }}>{T('Chưa có thông báo nào.', 'No notifications yet.')}</p>
        </div>
      )}
    </div>
  );
}

function Section({ title, children }) {
  return (
    <div style={{ marginBottom: 22 }}>
      <span style={{ fontSize: 11, fontWeight: 600, letterSpacing: '0.04em', color: ink, opacity: 0.6, textTransform: 'uppercase' }}>{title}</span>
      <div style={{ marginTop: 6 }}>{children}</div>
    </div>
  );
}

// A plain colored circle with the app's own bell mark — never a broken
// image. Used whenever avatarSourceFor() can't resolve an event photo or a
// guest avatar (neither exists, or the notification kind has no specific
// actor at all, e.g. referral_joined).
function AvatarFallback() {
  return (
    <div
      aria-hidden
      style={{
        flex: 'none', width: 40, height: 40, borderRadius: '50%',
        background: 'rgba(27,25,22,0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontSize: 16, color: ink,
      }}
    >
      🔔
    </div>
  );
}

function Row({ n, unread, avatar, onClick, onDelete }) {
  return (
    <div
      style={{
        display: 'flex', gap: 10, padding: '14px 0',
        borderBottom: '1px solid rgba(27,25,22,0.16)',
        opacity: unread ? 1 : 0.6,
      }}
    >
      {avatar.type === 'image' ? (
        <div style={bg(avatar.url, { flex: 'none', width: 40, height: 40, borderRadius: '50%' })} />
      ) : (
        <AvatarFallback />
      )}
      <div onClick={onClick} style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0, flex: 1, cursor: onClick ? 'pointer' : 'default' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
          <span style={{ ...display(15, { lineHeight: 1.3 }), fontWeight: 700, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{n.title}</span>
          <span style={{ fontSize: 11, color: ink, flex: 'none', whiteSpace: 'nowrap' }}>{n.ago}</span>
        </div>
        {/* Instagram's own "bold actor/action + secondary preview" shape —
            one truncated line, not the old full-body wrap. */}
        <span style={{ fontSize: 13, lineHeight: 1.4, color: ink, opacity: 0.75, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{n.body}</span>
      </div>
      {/* A real, permanent delete (notifications_delete_own RLS, migration
          050) — not audit-sensitive the way dispute_messages is, so no
          confirm dialog/soft-delete either. */}
      <span
        onClick={(e) => { e.stopPropagation(); onDelete(); }}
        data-testid="notification-delete"
        style={{ flex: 'none', fontSize: 15, color: ink, opacity: 0.4, cursor: 'pointer', padding: '0 2px', lineHeight: 1 }}
      >
        ×
      </span>
    </div>
  );
}

import { useEffect, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { agoLabel, bg } from '../data/events.js';
import { avatarSourceFor, notificationAgeBucket, groupNotificationsByDay, collapseDayGroups } from '../lib/notifications.js';
import { paper, ink, rule, alert, display, fieldGlass } from '../theme.js';

// Redesigned to read like Instagram/Facebook's own notification list
// (07-notifications.md's 2026-09-18 follow-up): a left avatar per row
// (derived per-kind — see avatarSourceFor), a bold title + single-line
// truncated preview, and time-based sections with unread always pinned to
// the top regardless of age. Same fonts/colors as everywhere else in the
// app (theme.js's paper/ink/display) — no new design system.
const COLLAPSE_AT = 20;

// Refund MVP task D — one semantic trailing icon per notification title,
// by kind category. Same minimal inline-SVG convention as Account.jsx's own
// RowIcon (one stroke weight, one viewBox, `ink` only, no emoji) — kept
// local here rather than importing from Account.jsx since that component
// isn't exported and this needs a different (smaller) glyph set.
const KIND_CATEGORY = {
  refund_marked_sent: 'refund', refund_confirmed: 'refund', refund_disputed: 'refund', refund_overdue: 'refund',
  dispute_message: 'dispute', dispute_resolved: 'dispute', payment_disputed: 'dispute',
  payment_awaiting_verification: 'payment', payment_confirmed: 'payment', payment_document_uploaded: 'payment',
  payment_document_replaced: 'payment', payment_verification_nudge: 'payment', payment_needs_info: 'payment',
  hold_created: 'payment', hold_expired: 'payment',
  booking_requested: 'booking', booking_cancelled: 'booking', booking_declined: 'booking',
  checked_in: 'booking', checkin_undo: 'booking', checkin_undone: 'booking', undo_check_in: 'booking',
  reject_pending_guest: 'booking', receipt_requested: 'booking',
  event_share: 'event', referral_joined: 'event',
  new_message: 'message',
};
function notificationCategory(kind) { return KIND_CATEGORY[kind] || 'system'; }

function KindIcon({ category }) {
  const common = { width: 14, height: 14, viewBox: '0 0 24 24', fill: 'none', stroke: ink, strokeWidth: 1.9, strokeLinecap: 'round', strokeLinejoin: 'round' };
  const byCategory = {
    refund: <><rect x="3" y="7.3" width="18" height="9.4" rx="1.6" /><circle cx="12" cy="12" r="2.3" /></>,
    dispute: <><path d="M12 3.2l9 15.6H3z" /><path d="M12 9.5v4M12 16v0" /></>,
    payment: <><rect x="3.5" y="5.5" width="17" height="13" rx="1.8" /><path d="M3.5 9.7h17" /></>,
    booking: <><rect x="3.5" y="5" width="17" height="15.5" rx="2.3" /><path d="M3.5 9.7h17" /><path d="M8 3v4M16 3v4" /></>,
    event: <><rect x="3.5" y="5" width="17" height="15.5" rx="2.3" /><path d="M3.5 9.7h17" /><circle cx="12" cy="14.5" r="2.1" /></>,
    message: <path d="M4 5.5h16v10.6H9.6L5 20V16.1H4z" />,
    system: <><circle cx="12" cy="12" r="8.4" /><path d="M12 8.3v4.5M12 15.7v0" /></>,
  };
  return (
    <span aria-hidden style={{ flex: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', opacity: 0.6 }}>
      <svg {...common}>{byCategory[category] || byCategory.system}</svg>
    </span>
  );
}
// TASK 1 (2026-09-22 twentieth follow-up) — must match Inbox.jsx's own
// SHEET_ANIM_MS exactly (not a separate arbitrary speed): the prior pass
// left this screen's search input with no `animation` at all, so it
// snapped open/closed instantly instead of the 600ms fade Inbox uses.
const SHEET_ANIM_MS = 600;

function classifyAtLoad(n, now) {
  return !n.read_at ? 'new' : notificationAgeBucket(n.created_at, now);
}

export default function Notifications() {
  const {
    state, T, trStatus, goHome, openNotification, deleteNotification, deleteNotifications,
    markNotificationRead, markNotificationUnread, muteNotificationKind,
  } = useGoc();
  const s = state;
  // Which sections have had their "Xem thêm" tapped — purely a render-time
  // slice of already-loaded data (loadNotifications() fetches up to 50 at
  // once), so a plain local Set is enough; nothing here needs a new query.
  const [expandedSections, setExpandedSections] = useState(() => new Set());
  const expandSection = (key) => setExpandedSections(prev => new Set(prev).add(key));
  // BUG 4: the "•••" action menu, open for at most one row's notification
  // at a time.
  const [menuFor, setMenuFor] = useState(null);
  // TASK 2 (2026-09-22 nineteenth follow-up) — search, matching Inbox's own
  // search icon+label control exactly (Inbox.jsx). Filters title/body
  // client-side against already-loaded s.notifications, same plain-
  // substring convention Inbox's own search already uses (no other text-
  // search backend exists in this app to call into).
  const [searchOpen, setSearchOpen] = useState(false);
  const [query, setQuery] = useState('');
  // TASK 2 (2026-09-22 seventeenth follow-up) — selection/edit mode: a
  // plain local Set of ids, like `expandedSections` above — nothing here
  // needs a new query, and "Select all" must only ever apply to whatever's
  // actually loaded/rendered (`s.notifications`), never a hidden/paginated
  // row the user never saw (this ticket's own explicit requirement).
  const [selectionMode, setSelectionMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState(() => new Set());
  const toggleSelected = (id) => setSelectedIds(prev => {
    const next = new Set(prev);
    if (next.has(id)) next.delete(id); else next.add(id);
    return next;
  });
  const exitSelectionMode = () => { setSelectionMode(false); setSelectedIds(new Set()); };
  const selectAll = () => setSelectedIds(new Set(s.notifications.map(n => n.id)));
  const deleteSelected = async () => {
    const ids = [...selectedIds];
    exitSelectionMode();
    await deleteNotifications(ids);
  };

  // 2026-09-18 follow-up (BUG 3): a notification's SECTION is decided once
  // — the first time this screen sees it — and frozen from then on, keyed
  // by id. Reading it only flips its own read_at (handled live below, for
  // the bold/dim weight), it never moves the row to a different section.
  // Without this, section membership was being recomputed from live
  // read_at on every render — the exact same array (s.notifications) is
  // also overwritten wholesale every 5s by the app-wide toast poll
  // (startNotificationPolling(), GocContext.jsx), so a plain
  // useMemo/derived-state approach re-shuffles a notification the instant
  // either markNotificationRead() OR that unrelated poll tick re-renders
  // this screen — which is what "reading moves it" actually was.
  const [sectionMembership, setSectionMembership] = useState(() => {
    const map = {};
    const now = Date.now();
    for (const n of s.notifications) map[n.id] = classifyAtLoad(n, now);
    return map;
  });
  useEffect(() => {
    setSectionMembership(prev => {
      let changed = false;
      const next = { ...prev };
      const now = Date.now();
      for (const n of s.notifications) {
        if (!(n.id in next)) { next[n.id] = classifyAtLoad(n, now); changed = true; }
      }
      return changed ? next : prev;
    });
  }, [s.notifications]);

  const withAgo = (n) => ({
    ...n,
    ago: trStatus(agoLabel(Math.max(1, Math.round((Date.now() - new Date(n.created_at).getTime()) / 3600000)))),
  });

  // TASK 2 (2026-09-22 nineteenth follow-up) — search filters the SOURCE
  // list before grouping, not the rendered sections — so a matching
  // notification still lands in its own frozen section (sectionMembership
  // above is keyed by id and untouched by this), just hidden when it
  // doesn't match rather than re-bucketed.
  const q = query.trim().toLowerCase();
  const searchFiltered = q
    ? s.notifications.filter(n => (n.title || '').toLowerCase().includes(q) || (n.body || '').toLowerCase().includes(q))
    : s.notifications;

  // Exactly one bucket per key, regardless of how many unread items are
  // interleaved with read ones in s.notifications — grouping by a frozen,
  // pre-computed membership id can never split "Mới" into two blocks the
  // way a live re-scan keyed on read_at (recomputed mid-list) could.
  const grouped = { new: [], today: [], week: [], older: [] };
  for (const n of searchFiltered) {
    const key = sectionMembership[n.id] ?? classifyAtLoad(n, Date.now());
    grouped[key].push(n);
  }
  // 2026-09-19 follow-up: "7 ngày qua"/"Cũ hơn" get a finer per-calendar-day
  // header on top of the existing New/Today/Last-7-days/Older buckets
  // (unchanged, still stabilized by the frozen sectionMembership above) —
  // "Mới"/"Hôm nay" stay flat exactly as before, per this ticket's own ask.
  const sections = [
    { key: 'new', title: T('Mới', 'New'), items: grouped.new, dayGrouped: false },
    { key: 'today', title: T('Hôm nay', 'Today'), items: grouped.today, dayGrouped: false },
    { key: 'week', title: T('7 ngày qua', 'Last 7 days'), items: grouped.week, dayGrouped: true },
    { key: 'older', title: T('Cũ hơn', 'Older'), items: grouped.older, dayGrouped: true },
  ].filter(sec => sec.items.length > 0);

  const avatarMaps = {
    bookingById: s.notificationBookingById,
    eventPhotoByEventId: s.notificationEventPhotoByEventId,
    avatarByUserId: s.notificationAvatarByUserId,
  };

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Notifications">
      <div style={{ padding: '70px 24px 8px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        {/* TASK 2 (2026-09-22 nineteenth follow-up) — "Done" removed
            entirely from normal mode (this screen is reached from the
            dock's own Notifications tab, same as Inbox — no separate
            "done" affordance needed there either). Search input replaces
            the title, exactly mirroring Inbox.jsx's own search-open state. */}
        {searchOpen ? (
          <input
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={T('Tìm thông báo…', 'Search notifications…')}
            data-testid="notifications-search-input"
            style={{
              ...fieldGlass({ flex: 1, padding: '10px 14px', borderRadius: 999, border: 'none', marginRight: 10 }),
              fontSize: 13.5, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none',
              animation: `gocIn ${SHEET_ANIM_MS}ms cubic-bezier(.22,.61,.36,1) both`,
            }}
          />
        ) : selectionMode ? (
          <span style={{ ...display(27) }}>{T('Đang chọn', 'Selecting')}</span>
        ) : (
          <span style={{ ...display(27) }}>{T('Thông báo', 'Notifications')}</span>
        )}
        {/* TASK 2 (2026-09-22 twentieth follow-up) — the two right-side
            header slots morph in place (same two fixed positions, content
            crossfades via key+gocFade) into Select all + Cancel rather than
            being replaced by a single plain-text "Huỷ" elsewhere in the
            header — same icon-above-label sizing as the normal Search/Select
            controls, Cancel in the shared `alert` destructive color. */}
        <div style={{ display: 'flex', gap: 14, flex: 'none' }}>
          {selectionMode ? (
            <div
              key="select-all"
              onClick={selectAll}
              data-testid="notifications-select-all"
              style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2, cursor: 'pointer', animation: `gocFade ${SHEET_ANIM_MS}ms ease both` }}
            >
              <span style={{ width: 34, height: 34, borderRadius: '50%', ...fieldGlass({}), display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, color: ink }}>☑</span>
              <span style={{ fontSize: 9.5, color: ink, opacity: 0.7 }}>{T('Chọn tất cả', 'Select all')}</span>
            </div>
          ) : (
            <div
              key="search"
              onClick={() => { if (searchOpen) setQuery(''); setSearchOpen(v => !v); }}
              data-testid="notifications-search-toggle"
              style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2, cursor: 'pointer', animation: `gocFade ${SHEET_ANIM_MS}ms ease both` }}
            >
              <span style={{ width: 34, height: 34, borderRadius: '50%', ...fieldGlass({}), display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, color: ink }}>
                {searchOpen ? '✕' : '🔍'}
              </span>
              <span style={{ fontSize: 9.5, color: ink, opacity: 0.7 }}>{searchOpen ? T('Đóng', 'Close') : T('Tìm', 'Search')}</span>
            </div>
          )}
          {selectionMode ? (
            <div
              key="cancel"
              onClick={exitSelectionMode}
              data-testid="notifications-selection-cancel"
              style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2, cursor: 'pointer', animation: `gocFade ${SHEET_ANIM_MS}ms ease both` }}
            >
              <span style={{ width: 34, height: 34, borderRadius: '50%', ...fieldGlass({}), display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, color: alert }}>✕</span>
              <span style={{ fontSize: 9.5, color: alert, opacity: 0.85 }}>{T('Huỷ', 'Cancel')}</span>
            </div>
          ) : (
            s.notifications.length > 0 && (
              <div
                key="select"
                onClick={() => setSelectionMode(true)}
                data-testid="notifications-select-mode"
                style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2, cursor: 'pointer', animation: `gocFade ${SHEET_ANIM_MS}ms ease both` }}
              >
                <span style={{ width: 34, height: 34, borderRadius: '50%', ...fieldGlass({}), display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, color: ink }}>☑</span>
                <span style={{ fontSize: 9.5, color: ink, opacity: 0.7 }}>{T('Chọn', 'Select')}</span>
              </div>
            )
          )}
        </div>
      </div>
      {selectionMode && (
        <div style={{ padding: '0 24px 12px', display: 'flex', justifyContent: 'flex-end', alignItems: 'center' }}>
          {selectedIds.size > 0 && (
            <span onClick={deleteSelected} data-testid="notifications-delete-selected" style={{ fontSize: 12.5, fontWeight: 600, color: alert, cursor: 'pointer' }}>
              {T(`Xoá (${selectedIds.size})`, `Delete (${selectedIds.size})`)}
            </span>
          )}
        </div>
      )}
      {sections.length > 0 ? (
        <div style={{ padding: '14px 24px 40px' }}>
          {sections.map(sec => {
            const expanded = expandedSections.has(sec.key);
            const row = (n) => (
              <Row
                key={n.id}
                n={n}
                // Live read_at, not the (frozen) section — marking a
                // notification read only changes its weight/dimming in
                // place, per BUG 3, never which section it's in.
                unread={!n.read_at}
                avatar={avatarSourceFor(n, avatarMaps, s.accountType)}
                // TASK 2 — in selection mode, a tap toggles the checkbox
                // instead of navigating; the "•••" menu stays disabled
                // there too (normal-mode-only behavior, per this ticket's
                // own requirement 1).
                onClick={selectionMode ? () => toggleSelected(n.id) : () => openNotification(n)}
                onOpenMenu={selectionMode ? undefined : () => setMenuFor(n)}
                selectionMode={selectionMode}
                selected={selectedIds.has(n.id)}
              />
            );
            if (!sec.dayGrouped) {
              const visible = expanded ? sec.items : sec.items.slice(0, COLLAPSE_AT);
              const hiddenCount = sec.items.length - visible.length;
              return (
                <Section key={sec.key} title={sec.title}>
                  {visible.map(withAgo).map(row)}
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
            }
            // "7 ngày qua"/"Cũ hơn": one header per calendar day underneath
            // this section's own outer title, collapsing whole days at a
            // time (collapseDayGroups() never cuts a single day's items in
            // half) instead of a flat COLLAPSE_AT slice across the range.
            const dayGroups = groupNotificationsByDay(sec.items, s.lang);
            const { visible: visibleDays, hidden: hiddenDays } = expanded
              ? { visible: dayGroups, hidden: [] }
              : collapseDayGroups(dayGroups, COLLAPSE_AT);
            const hiddenCount = hiddenDays.reduce((sum, g) => sum + g.items.length, 0);
            return (
              <Section key={sec.key} title={sec.title}>
                {visibleDays.map(day => (
                  <div key={day.key} style={{ marginBottom: 14 }}>
                    <span style={{ fontSize: 10.5, fontWeight: 600, color: ink, opacity: 0.5 }} data-testid="notification-day-header">
                      {day.label}
                    </span>
                    <div style={{ marginTop: 4 }}>{day.items.map(withAgo).map(row)}</div>
                  </div>
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
      {menuFor && (
        <NotificationActionSheet
          n={menuFor}
          T={T}
          onClose={() => setMenuFor(null)}
          onDelete={() => { deleteNotification(menuFor.id); setMenuFor(null); }}
          onToggleRead={() => {
            (menuFor.read_at ? markNotificationUnread : markNotificationRead)(menuFor.id);
            setMenuFor(null);
          }}
          onMute={() => { muteNotificationKind(menuFor.kind); setMenuFor(null); }}
        />
      )}
    </div>
  );
}

// BUG 4: replaces the old per-row "×" delete with a "•••" menu, modeled on
// Facebook's own notification action sheet — but only the actions this app
// can actually back for real (no "Show more"/"Show less": nothing ranks or
// personalizes this list; no "Report issue": no generic issue-report
// mechanism exists anywhere else in the app to call into — see
// 07-notifications.md). Reuses the same bottom-sheet visual convention as
// ReasonSheet.jsx (dim overlay + a paper panel sliding up from the bottom)
// rather than inventing a new dropdown/floating-menu pattern.
function NotificationActionSheet({ n, T, onClose, onDelete, onToggleRead, onMute }) {
  const isRead = !!n.read_at;
  return (
    <div onClick={onClose} style={{ position: 'fixed', inset: 0, zIndex: 30, background: 'rgba(12,12,12,0.55)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'gocFade 0.2s ease both' }}>
      <div onClick={(e) => e.stopPropagation()} style={{ background: paper, borderRadius: '18px 18px 0 0', padding: '10px 0 28px', animation: 'gocSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
        <div style={{ width: 36, height: 4, borderRadius: 2, background: 'rgba(27,25,22,0.16)', margin: '4px auto 10px' }} />
        <MenuRow onClick={onToggleRead} testId="notification-menu-toggle-read">
          {isRead ? T('Đánh dấu chưa đọc', 'Mark as unread') : T('Đánh dấu đã đọc', 'Mark as read')}
        </MenuRow>
        <MenuRow onClick={onMute} testId="notification-menu-mute">
          {T('Tắt loại thông báo này', 'Turn off this kind of notification')}
        </MenuRow>
        <MenuRow onClick={onDelete} destructive testId="notification-menu-delete">
          {T('Xoá thông báo này', 'Delete this notification')}
        </MenuRow>
      </div>
    </div>
  );
}

function MenuRow({ children, onClick, destructive, testId }) {
  return (
    <div
      onClick={onClick}
      data-testid={testId}
      style={{
        padding: '15px 24px', fontSize: 14.5, color: destructive ? alert : ink,
        borderBottom: `1px solid ${rule}`, cursor: 'pointer',
      }}
    >
      {children}
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

function Row({ n, unread, avatar, onClick, onOpenMenu, selectionMode, selected }) {
  return (
    <div
      data-testid="notification-row"
      data-selected={selectionMode ? (selected ? 'true' : 'false') : undefined}
      onClick={onClick}
      style={{
        display: 'flex', gap: 10, padding: '14px 10px', margin: '0 -10px', borderRadius: 12,
        cursor: onClick ? 'pointer' : 'default',
        borderBottom: '1px solid rgba(27,25,22,0.16)',
        // TASK D — unread: a clearly darker/tinted background + bold title
        // (existing `fontWeight: unread ? 700 : 400` below, unchanged);
        // read: normal (transparent) background. Replaces the old
        // whole-row `opacity: 0.6` fade, which dimmed EVERYTHING in a read
        // row (including its icon) rather than just distinguishing the two
        // states via background.
        background: unread ? 'rgba(27,25,22,0.07)' : 'transparent',
      }}
    >
      {/* TASK 2 (2026-09-22 seventeenth follow-up) — a checkbox affordance
          in place of the avatar's usual spot while selecting, existing
          banbe tokens only (ink/alert/rule — no new colors). */}
      {selectionMode && (
        <span
          data-testid="notification-row-checkbox"
          style={{
            flex: 'none', width: 22, height: 22, borderRadius: '50%', alignSelf: 'center',
            border: `1.5px solid ${selected ? alert : rule}`, background: selected ? alert : 'transparent',
            color: paper, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12, fontWeight: 700,
          }}
        >
          {selected ? '✓' : ''}
        </span>
      )}
      {avatar.type === 'image' ? (
        <div style={bg(avatar.url, { flex: 'none', width: 40, height: 40, borderRadius: '50%' })} />
      ) : (
        <AvatarFallback />
      )}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0, flex: 1 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
          {/* BUG 3: bold only while unread — reading a notification unbolds
              it in place (fontWeight only), it never moves sections. */}
          <span style={{ display: 'flex', alignItems: 'center', gap: 6, minWidth: 0 }}>
            <span style={{ ...display(15, { lineHeight: 1.3 }), fontWeight: unread ? 700 : 400, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{n.title}</span>
            <KindIcon category={notificationCategory(n.kind)} />
          </span>
          <span style={{ fontSize: 11, color: ink, flex: 'none', whiteSpace: 'nowrap' }}>{n.ago}</span>
        </div>
        {/* Instagram's own "bold actor/action + secondary preview" shape —
            one truncated line, not the old full-body wrap. */}
        <span style={{ fontSize: 13, lineHeight: 1.4, color: ink, opacity: 0.75, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{n.body}</span>
      </div>
      {/* BUG 4: "•••" opens the action menu (delete / toggle read /
          mute this kind) instead of deleting directly. TASK 2: hidden in
          selection mode (onOpenMenu is undefined there) — normal-mode-only
          per this ticket's own requirement 1. */}
      {onOpenMenu && (
        <span
          onClick={(e) => { e.stopPropagation(); onOpenMenu(); }}
          data-testid="notification-menu"
          style={{ flex: 'none', fontSize: 15, color: ink, opacity: 0.4, cursor: 'pointer', padding: '0 4px', lineHeight: 1 }}
        >
          •••
        </span>
      )}
    </div>
  );
}

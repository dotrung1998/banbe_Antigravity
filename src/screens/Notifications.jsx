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
            }}
          />
        ) : selectionMode ? (
          <span style={{ ...display(27) }}>{T('Đang chọn', 'Selecting')}</span>
        ) : (
          <span style={{ ...display(27) }}>{T('Thông báo', 'Notifications')}</span>
        )}
        {selectionMode ? (
          <span onClick={exitSelectionMode} data-testid="notifications-selection-cancel" style={{ fontSize: 12, color: ink, cursor: 'pointer', flex: 'none' }}>{T('Huỷ', 'Cancel')}</span>
        ) : (
          <div style={{ display: 'flex', gap: 14, flex: 'none' }}>
            {/* TASK 2 — icon+label controls, same visual language/sizing as
                Inbox's own search/settings buttons (34px glass circle +
                9.5px label underneath), not plain header text. */}
            <div
              onClick={() => { if (searchOpen) setQuery(''); setSearchOpen(v => !v); }}
              data-testid="notifications-search-toggle"
              style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2, cursor: 'pointer' }}
            >
              <span style={{ width: 34, height: 34, borderRadius: '50%', ...fieldGlass({}), display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, color: ink }}>
                {searchOpen ? '✕' : '🔍'}
              </span>
              <span style={{ fontSize: 9.5, color: ink, opacity: 0.7 }}>{searchOpen ? T('Đóng', 'Close') : T('Tìm', 'Search')}</span>
            </div>
            {s.notifications.length > 0 && (
              <div
                onClick={() => setSelectionMode(true)}
                data-testid="notifications-select-mode"
                style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2, cursor: 'pointer' }}
              >
                <span style={{ width: 34, height: 34, borderRadius: '50%', ...fieldGlass({}), display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, color: ink }}>☑</span>
                <span style={{ fontSize: 9.5, color: ink, opacity: 0.7 }}>{T('Chọn', 'Select')}</span>
              </div>
            )}
          </div>
        )}
      </div>
      {selectionMode && (
        <div style={{ padding: '0 24px 12px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <span onClick={selectAll} data-testid="notifications-select-all" style={{ fontSize: 12.5, fontWeight: 600, color: ink, cursor: 'pointer' }}>{T('Chọn tất cả', 'Select all')}</span>
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
        display: 'flex', gap: 10, padding: '14px 0', cursor: onClick ? 'pointer' : 'default',
        borderBottom: '1px solid rgba(27,25,22,0.16)',
        opacity: unread ? 1 : 0.6,
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
          <span style={{ ...display(15, { lineHeight: 1.3 }), fontWeight: unread ? 700 : 400, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{n.title}</span>
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

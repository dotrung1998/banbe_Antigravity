import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { bg } from '../data/events.js';
import { paper, ink, ink2, ink3, rule, alert, block, divider, display, fieldGlass, inkButton, cardGlass } from '../theme.js';
import { DOCK_HEADER } from '../components/ui/DockHeaderTitle.jsx';
import { isActiveDisputeChat } from './ConversationDispute.jsx';
import { notificationCategory as notifCategory, Row as NotificationRow } from './Notifications.jsx';
import { avatarSourceFor } from '../lib/notifications.js';
import EmptyState from '../components/ui/EmptyState.jsx';

// Same 6s poll interval the ordinary conversation list uses, for the same
// reason — nothing in this app subscribes to Supabase Realtime (03-dispute-
// chat.md), so a chat that's concluded or got a new message while you sit on
// the Inbox can otherwise stay visibly stale until you leave and come back.
const DISPUTE_POLL_MS = 6000;

// Swipe-left reveal width — three 72px actions: Star, Archive, Delete.
const ACTION_WIDTH = 72;
const REVEAL_WIDTH = ACTION_WIDTH * 3;

// Bug 1b/1c (2026-09-21 follow-up) — ONE shared, noticeably slower timing
// for both the settings sheet's entrance and the search field's reveal,
// instead of two different speeds for two different controls.
const SHEET_ANIM_MS = 600;

// One row, with its own swipe-to-reveal drag state — kept per-row (not one
// shared offset on the list) so opening one row's actions doesn't affect
// any other row, and scrolling the list vertically isn't fought by a
// horizontal drag started elsewhere.
function InboxRow({ c, onOpen, onStar, onArchive, onDelete, T, disputeActive }) {
  const [offset, setOffset] = useState(0);
  const dragRef = useRef({ active: false, startX: 0, startOffset: 0, moved: false });

  const onPointerDown = (e) => {
    dragRef.current = { active: true, startX: e.clientX, startOffset: offset, moved: false };
  };
  const onPointerMove = (e) => {
    const d = dragRef.current;
    if (!d.active) return;
    const dx = e.clientX - d.startX;
    if (Math.abs(dx) > 4) d.moved = true;
    const next = Math.min(0, Math.max(-REVEAL_WIDTH, d.startOffset + dx));
    setOffset(next);
  };
  const onPointerUp = () => {
    const d = dragRef.current;
    if (!d.active) return;
    d.active = false;
    setOffset(prev => (prev < -REVEAL_WIDTH / 2 ? -REVEAL_WIDTH : 0));
  };
  const handleRowClick = () => {
    if (dragRef.current.moved || offset !== 0) { setOffset(0); return; }
    onOpen();
  };

  // Task 3 (2026-09-21 follow-up) — unread rows get more visual weight
  // (bold name/snippet + a small accent dot), reusing the SAME `c.unread`
  // signal loadInboxThreads() computes for the dock badge, not a second
  // computation.
  const unread = !!c.unread;

  return (
    <div style={{ position: 'relative', overflow: 'hidden', borderBottom: `1px solid ${divider}`, ...(disputeActive ? { margin: '0 -10px' } : null) }}>
      <div style={{ position: 'absolute', top: 0, right: 0, bottom: 0, width: REVEAL_WIDTH, display: 'flex' }}>
        <div
          onClick={(e) => { e.stopPropagation(); onStar(); setOffset(0); }}
          data-testid="inbox-row-star"
          style={{ width: ACTION_WIDTH, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 4, background: alert, color: 'var(--bb-on-alert)', cursor: 'pointer' }}
        >
          <span style={{ fontSize: 18, lineHeight: 1 }}>{c.starred ? '★' : '☆'}</span>
          {/* Bug 1a (2026-09-21 follow-up) — was hardcoded "Star" text
              regardless of state; the icon already flips ★/☆ but the label
              never followed. */}
          <span style={{ fontSize: 10, fontWeight: 600 }}>{c.starred ? T('Bỏ đánh dấu', 'Unstar') : T('Đánh dấu', 'Star')}</span>
        </div>
        <div
          onClick={(e) => { e.stopPropagation(); onArchive(); setOffset(0); }}
          data-testid="inbox-row-archive"
          style={{ width: ACTION_WIDTH, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 4, background: ink, color: paper, cursor: 'pointer' }}
        >
          <span style={{ fontSize: 16, lineHeight: 1 }}>{c.archived ? '📤' : '🗄'}</span>
          <span style={{ fontSize: 10, fontWeight: 600 }}>{c.archived ? T('Bỏ lưu trữ', 'Unarchive') : T('Lưu trữ', 'Archive')}</span>
        </div>
        {/* Message-host pass — hide-for-me delete; confirmed by the sheet in
            Inbox() (see deleteThreadForMe in BanBeContext.jsx). */}
        <div
          onClick={(e) => { e.stopPropagation(); onDelete(); setOffset(0); }}
          data-testid="inbox-row-delete"
          style={{ width: ACTION_WIDTH, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 4, background: 'color-mix(in srgb, var(--bb-alert) 72%, #000)', color: 'var(--bb-on-alert)', cursor: 'pointer' }}
        >
          <span style={{ fontSize: 16, lineHeight: 1 }}>🗑</span>
          <span style={{ fontSize: 10, fontWeight: 600 }}>{T('Xoá', 'Delete')}</span>
        </div>
      </div>
      <div
        onClick={handleRowClick}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        data-testid="inbox-row"
        data-thread-id={c.threadId}
        data-unread={unread ? 'true' : 'false'}
        data-dispute={disputeActive ? 'true' : undefined}
        style={{
          display: 'flex', gap: 12, alignItems: 'center', padding: '14px 0', cursor: 'pointer',
          // iOS parity: a full-row rounded pale-red surface, not a left bar.
          background: disputeActive ? 'color-mix(in srgb, var(--bb-alert) 10%, var(--bb-bg))' : paper,
          // Same full-row rounded fill as an unread notification (10px side
          // bleed via the wrapper's negative margin keeps content aligned).
          borderRadius: disputeActive ? 12 : 0,
          paddingLeft: disputeActive ? 10 : 0, paddingRight: disputeActive ? 10 : 0, transform: `translateX(${offset}px)`, transition: dragRef.current.active ? 'none' : 'transform 0.2s ease',
          touchAction: 'pan-y',
        }}
      >
        <div style={{ position: 'relative', flex: 'none', width: 56, height: 56 }}>
          <div style={bg(c.img, { width: 56, height: 56, borderRadius: '50%' })} />
          {/* Task 3a — merged avatar: a small badge circle for the
              OTHER participant's own photo (host when I'm the guest,
              guest when I'm the organizer), overlapping the event
              photo's corner — mirrors the reference screenshot's
              property-photo + person-photo pattern. Falls back to an
              initial-letter circle rather than nothing when that
              person has no avatar_url on file. */}
          {c.otherAvatarUrl ? (
            <div style={{ ...bg(c.otherAvatarUrl, { width: 24, height: 24, borderRadius: '50%' }), position: 'absolute', right: -2, bottom: -2, border: `2px solid ${paper}` }} />
          ) : (
            <div style={{ width: 24, height: 24, borderRadius: '50%', position: 'absolute', right: -2, bottom: -2, border: `2px solid ${paper}`, background: ink, color: paper, fontSize: 11, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              {(c.name || '?').trim().charAt(0).toUpperCase()}
            </div>
          )}
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0, flex: 1 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            {unread && <span data-testid="inbox-row-unread-dot" style={{ width: 7, height: 7, borderRadius: '50%', background: alert, flex: 'none' }} />}
            {/* Bug 3 (2026-09-21 follow-up) — a fully-read row's name stays
                bold (still reads as the row's title, and never drops below
                the preview line's own weight beneath it) but is de-emphasized
                via opacity/color rather than a lighter font-weight, so it
                reads clearly lighter than an unread row's name without
                losing its title-vs-preview hierarchy. */}
            <span style={{ fontSize: 15, lineHeight: 1.2, fontWeight: unread ? 600 : 400, color: ink }}>{c.name}</span>
          </div>
          {disputeActive && (
            <span data-testid="inbox-row-dispute" style={{ fontSize: 11.5, fontWeight: 700, color: alert }}>{T('Tranh chấp đang diễn ra', 'Dispute in progress')}</span>
          )}
          <span style={{ fontSize: 13, color: unread ? ink : ink2, fontWeight: unread ? 600 : 400, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{c.snippet}</span>
        </div>
        {/* Bug 1 (2026-09-21 follow-up) — moved off the avatar (where it
            could collide with the merged-avatar badge) to the row's own
            far trailing edge instead. */}
        {c.starred && (
          <span data-testid="inbox-row-star-badge" style={{ fontSize: 15, color: alert, flex: 'none' }}>★</span>
        )}
        {/* TASK 3 (2026-09-22 nineteenth follow-up) — a subtle swipe-left
            affordance: nothing in this row previously hinted that Star/
            Archive live behind a swipe at all. Purely visual (no tap
            behavior of its own — requirement 2), slim/low-opacity so it
            never competes with the unread dot/timestamp/avatar/star badge,
            and fades further on an already-read row (requirement 3) since
            there's less reason to keep teaching the gesture there. Sits at
            the row's own trailing edge, self-aligned toward the bottom, so
            it doesn't interfere with the vertically-centered content above
            it (requirement 4 — this is a sibling of the row's own
            onClick/swipe handlers, not layered over them). */}
        {/* iOS parity: a tap-only "…" control at the trailing edge (iOS's
            Menu). Here it just reveals the same Star/Archive/Delete actions the
            swipe does, so no behaviour is added. Keeps the old hint testid. */}
        <span
          data-testid="inbox-row-swipe-hint"
          aria-label="more"
          onClick={(e) => { e.stopPropagation(); setOffset(prev => (prev === 0 ? -REVEAL_WIDTH : 0)); }}
          style={{ flex: 'none', width: 32, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center', color: ink, opacity: 0.55, cursor: 'pointer' }}
        >
          <svg width={18} height={18} viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="1.9" /><circle cx="12" cy="12" r="1.9" /><circle cx="19" cy="12" r="1.9" /></svg>
        </span>
      </div>
    </div>
  );
}

// Task 1b — "Give feedback": single-choice screen -> text+bug-toggle screen,
// matching the attached reference screenshots. Local, ephemeral UI state
// (not global BanBeContext state) — same convention Notifications.jsx's own
// `expandedSections` toggle already uses for a purely in-screen concern.
function FeedbackFlow({ onClose, T }) {
  const { submitFeedback } = useBanBe();
  const [step, setStep] = useState('choice'); // 'choice' | 'detail'
  const [text, setText] = useState('');
  const [isBug, setIsBug] = useState(false);
  const [sending, setSending] = useState(false);

  const send = async () => {
    setSending(true);
    await submitFeedback(text, isBug);
    setSending(false);
    onClose();
  };

  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 40, background: paper, display: 'flex', flexDirection: 'column', animation: 'banbeIn 0.28s cubic-bezier(.22,.61,.36,1) both' }} data-testid="feedback-flow">
      <div style={{ padding: '20px 22px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span
          onClick={step === 'detail' ? () => setStep('choice') : onClose}
          data-testid="feedback-back"
          style={{ fontSize: 20, color: ink, cursor: 'pointer' }}
        >
          ‹
        </span>
      </div>
      {step === 'choice' ? (
        <div style={{ padding: '18px 22px 24px', display: 'flex', flexDirection: 'column', gap: 14 }}>
          <span style={{ ...display(24) }}>{T('Gửi Phản Hồi', 'Give Feedback')}</span>
          <p style={{ fontSize: 13, lineHeight: 1.5, color: ink, opacity: 0.75, margin: 0 }}>
            {T('Hãy cho chúng tôi biết phản hồi của bạn là về điều gì. Chúng tôi đọc mọi phản hồi nhưng không thể trả lời từng người.',
              'Please let us know what your feedback is about. We review all feedback but are unable to respond individually.')}
          </p>
          <div style={{ borderTop: `1px solid ${rule}`, borderBottom: `1px solid ${rule}`, padding: '14px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span style={{ fontSize: 14, color: ink }}>{T('Phản hồi chung về hộp thư', 'General feedback about the inbox')}</span>
            <span style={{ width: 20, height: 20, borderRadius: '50%', border: `2px solid ${ink}`, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none' }}>
              <span style={{ width: 10, height: 10, borderRadius: '50%', background: ink }} />
            </span>
          </div>
          <div
            onClick={() => setStep('detail')}
            data-testid="feedback-next"
            style={{ ...inkButton({ borderRadius: 12, padding: '13px', textAlign: 'center', alignSelf: 'flex-end', minWidth: 100 }) }}
          >
            {T('Tiếp', 'Next')}
          </div>
        </div>
      ) : (
        <div style={{ padding: '18px 22px 24px', display: 'flex', flexDirection: 'column', gap: 14, flex: 1 }}>
          <span style={{ ...display(24) }}>{T('Kể Cho Chúng Tôi Nghe', 'Tell Us About It')}</span>
          <p style={{ fontSize: 13, lineHeight: 1.5, color: ink, opacity: 0.75, margin: 0 }}>
            {T('Chia sẻ trải nghiệm của bạn. Điều gì tốt? Điều gì có thể tốt hơn?', 'Share your experience with us. What went well? What could have gone better?')}
          </p>
          <textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            data-testid="feedback-text"
            style={{ ...fieldGlass({ borderRadius: 12, border: `1px solid ${rule}`, padding: 12, minHeight: 160, resize: 'none' }), fontSize: 13.5, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none' }}
          />
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span style={{ fontSize: 14, color: ink }}>{T('Tôi đang báo lỗi', "I'm reporting a bug")}</span>
            <div
              onClick={() => setIsBug(v => !v)}
              data-testid="feedback-bug-toggle"
              style={{ width: 42, height: 24, borderRadius: 999, background: isBug ? ink : rule, position: 'relative', cursor: 'pointer', transition: 'background 0.15s ease' }}
            >
              <div style={{ position: 'absolute', top: 2, left: isBug ? 20 : 2, width: 20, height: 20, borderRadius: '50%', background: paper, transition: 'left 0.15s ease' }} />
            </div>
          </div>
          <div style={{ marginTop: 'auto', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span onClick={() => setStep('choice')} style={{ fontSize: 13.5, color: ink, cursor: 'pointer' }}>{T('Quay lại', 'Back')}</span>
            <div
              onClick={(!text.trim() || sending) ? undefined : send}
              data-testid="feedback-send"
              style={{ ...inkButton({ borderRadius: 12, padding: '12px 28px' }), opacity: (!text.trim() || sending) ? 0.5 : 1, cursor: (!text.trim() || sending) ? 'default' : 'pointer' }}
            >
              {sending ? T('Đang gửi…', 'Sending…') : T('Gửi', 'Send')}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

const iconBtn = { width: 44, height: 44, border: 'none', background: 'none', color: ink, display: 'grid', placeItems: 'center', cursor: 'pointer', padding: 0 };
function Chips({ items, value, onChange }) {
  return (
    <div style={{ display: 'flex', gap: 8, overflowX: 'auto', padding: '14px 0 10px', scrollbarWidth: 'none' }}>
      {items.map(([k, label]) => (
        <button key={k} type="button" onClick={() => onChange(k)} style={{ flex: 'none', height: 34, padding: '0 14px', border: 'none', borderRadius: 999, fontFamily: 'inherit', fontSize: 13, cursor: 'pointer',
          background: value === k ? ink : block, color: value === k ? paper : ink2, fontWeight: value === k ? 600 : 400 }}>{label}</button>
      ))}
    </div>
  );
}

export default function Inbox() {
  const { state, T, set, loadNotifications, openNotification, markNotificationRead, openThread, toggleThreadStar, archiveThread, unarchiveThread, deleteThreadForMe, setInboxView, loadDisputeChats, goHome } = useBanBe();
  const s = state;

  // Keeps the dispute index fresh — it drives the "Dispute in progress" row
  // highlight (the removed yellow band used to own this poll).
  useEffect(() => {
    if (s.inboxView !== 'active') return undefined;
    loadDisputeChats();
    const id = setInterval(loadDisputeChats, DISPUTE_POLL_MS);
    return () => clearInterval(id);
  }, [loadDisputeChats, s.inboxView]);

  const [tab, setTab] = useState(s.activityTab || 'messages');
  const rootRef = useRef(null);
  const scroller = () => { let e = rootRef.current?.parentElement; while (e && e !== document.body && !(e.scrollHeight > e.clientHeight && /auto|scroll/.test(getComputedStyle(e).overflowY))) e = e.parentElement; return e; };
  useLayoutEffect(() => {
    if (s.activityScroll == null) return;
    const y = s.activityScroll;
    set({ activityScroll: null, activityReturn: false });
    requestAnimationFrame(() => { const e = scroller(); if (e) e.scrollTop = y; });
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const [msgF, setMsgF] = useState('all');
  const [ntF, setNtF] = useState('all');
  useEffect(() => { loadNotifications?.(); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const [searchOpen, setSearchOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [settingsOpen, setSettingsOpen] = useState(false);
  useEffect(() => { set({ dockSuppressed: settingsOpen }); return () => set({ dockSuppressed: false }); }, [settingsOpen]); // eslint-disable-line react-hooks/exhaustive-deps
  const [feedbackOpen, setFeedbackOpen] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState(null); // threadId awaiting confirm

  const merged = useMemo(() => s.inboxThreads.map(c => ({
    ...c,
    starred: !!s.inboxThreadPrefs[c.threadId]?.starred,
    archived: !!s.inboxThreadPrefs[c.threadId]?.archived,
  })), [s.inboxThreads, s.inboxThreadPrefs]);

  const activeDisputeThreads = useMemo(
    () => new Set(s.disputeChats.filter(isActiveDisputeChat).map(c => c.conversation_thread_id).filter(Boolean)),
    [s.disputeChats]
  );
  const visible = useMemo(() => {
    const byView = merged.filter(c => (s.inboxView === 'archived' ? c.archived : !c.archived))
      .filter(c => msgF === 'unread' ? c.unread : msgF === 'dispute' ? activeDisputeThreads.has(c.threadId) : true);
    const q = query.trim().toLowerCase();
    if (!q) return byView;
    // Task 1a — reuses a plain client-side substring filter (this app has
    // no other real text-search backend to call into, only MapExplore's
    // "Search here" location re-query, which is a different concept).
    return byView.filter(c => c.name.toLowerCase().includes(q) || c.snippet.toLowerCase().includes(q));
  }, [merged, s.inboxView, query, msgF, activeDisputeThreads]);

  const emptyArchived = T('Chưa có cuộc trò chuyện nào được lưu trữ.', 'No archived conversations yet.');

  return (
    <div style={{ position: 'relative', animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Inbox" ref={rootRef}>
      {/* Pinned like iOS: the title row stays put while the conversations scroll under it. */}
      {/* Note 53: same padding and row height as every dock header (was a 24px gutter). */}
      <div data-testid="inbox-fixed-header" style={{ padding: `${DOCK_HEADER.top} ${DOCK_HEADER.side}px 12px`, height: DOCK_HEADER.rowHeight, boxSizing: 'content-box', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, position: 'sticky', top: 0, zIndex: 6, background: paper }}>
        {searchOpen ? (
          <input
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={T('Tìm cuộc trò chuyện…', 'Search conversations…')}
            data-testid="inbox-search-input"
            style={{
              ...fieldGlass({ flex: 1, minWidth: 0, padding: '10px 14px', borderRadius: 999, border: 'none' }),
              fontSize: 13.5, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none',
              animation: `banbeIn ${SHEET_ANIM_MS}ms cubic-bezier(.22,.61,.36,1) both`,
            }}
          />
        ) : (
          <h1 data-testid="inbox-title" style={{ margin: 0, minWidth: 0, flex: 1, fontSize: 30, fontWeight: 300, letterSpacing: '-.01em', color: ink }}>
            {s.inboxView === 'archived' ? T('Đã lưu trữ', 'Archived') : T('Hoạt động', 'Activity')}
          </h1>
        )}
        <div style={{ display: 'flex', gap: 2, flex: 'none', marginLeft: searchOpen ? 12 : 0 }}>
          <button type="button" data-testid="inbox-search-toggle" aria-label={searchOpen ? T('Đóng', 'Close') : T('Tìm', 'Search')} onClick={() => { if (searchOpen) setQuery(''); setSearchOpen(v => !v); }} style={iconBtn}>
            <svg width={22} height={22} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round">{searchOpen ? <path d="M5 5l14 14M19 5L5 19" /> : <><circle cx="11" cy="11" r="7" /><path d="M21 21l-4.35-4.35" /></>}</svg>
          </button>
          {s.inboxView === 'active' && (
            <span style={{ position: 'relative', display: 'flex' }}>
              <button type="button" data-testid="inbox-settings-toggle" aria-label={T('Cài đặt', 'Settings')} aria-expanded={settingsOpen} onClick={() => setSettingsOpen(v => !v)} style={iconBtn}>
                <svg width={22} height={22} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round"><path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" /><circle cx="12" cy="12" r="3" /></svg>
              </button>
              {settingsOpen && (
                <>
                  <div onClick={() => setSettingsOpen(false)} aria-hidden style={{ position: 'fixed', inset: 0, zIndex: 29 }} />
                  <div role="menu" data-testid="inbox-settings-menu" style={{ position: 'absolute', top: '100%', right: 0, zIndex: 30, minWidth: 220, padding: '6px 0', borderRadius: 14, background: paper, boxShadow: `0 10px 30px rgba(0,0,0,.18), 0 0 0 1px ${rule}`, animation: 'banbeFade 0.15s ease both' }}>
                    <div role="menuitem" onClick={() => { setSettingsOpen(false); setInboxView('archived'); }} data-testid="inbox-menu-archived" style={{ padding: '14px 16px', fontSize: 14.5, color: ink, cursor: 'pointer', borderBottom: `1px solid ${rule}` }}>{T('Đã lưu trữ', 'Archived')}</div>
                    <div role="menuitem" onClick={() => { setSettingsOpen(false); setFeedbackOpen(true); }} data-testid="inbox-menu-feedback" style={{ padding: '14px 16px', fontSize: 14.5, color: ink, cursor: 'pointer' }}>{T('Gửi Phản Hồi', 'Give Feedback')}</div>
                  </div>
                </>
              )}
            </span>
          )}
        </div>
      </div>

      {s.inboxView === 'active' && !searchOpen && (
        <div role="tablist" data-testid="activity-tabs" style={{ display: 'flex', background: block, borderRadius: 999, padding: 3, margin: '6px 20px 0' }}>
          {[['messages', T('Tin nhắn', 'Messages'), s.unreadMessages || 0], ['notifications', T('Thông báo', 'Notifications'), s.unreadNotifications || 0]].map(([k, label, n]) => (
            <button key={k} type="button" role="tab" aria-selected={tab === k} onClick={() => { setTab(k); set({ activityTab: k }); }} data-testid={`activity-tab-${k}`}
              style={{ flex: 1, height: 38, border: 'none', borderRadius: 999, fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
                background: tab === k ? ink : 'transparent', color: tab === k ? paper : ink3 }}>
              {label}
              {n > 0 && <span style={{ minWidth: 18, height: 18, padding: '0 5px', borderRadius: 999, background: alert, color: 'var(--bb-on-alert)', fontSize: 10, fontWeight: 700, display: 'grid', placeItems: 'center' }}>{n}</span>}
            </button>
          ))}
        </div>
      )}

      {tab === 'notifications' && s.inboxView === 'active' ? (() => {
        const cat = (k) => { const c = notifCategory(k); return c === 'booking' || c === 'reminder' ? 'tickets' : ['payment', 'refund', 'dispute'].includes(c) ? 'payments' : c === 'event' || c === 'message' ? 'events' : 'rewards'; };
        const all = s.notifications || [];
        const list = all.filter(n => (ntF === 'all' || cat(n.kind) === ntF) && (!query.trim() || `${n.title} ${n.body}`.toLowerCase().includes(query.trim().toLowerCase())));
        const unreadAll = all.filter(n => !n.read_at);
        return (
          <div style={{ margin: '0 20px 40px' }} data-testid="activity-notifications">
            <Chips value={ntF} onChange={setNtF} items={[['all', T('Tất cả', 'All')], ['tickets', T('Vé', 'Tickets')], ['payments', T('Thanh toán', 'Payments')], ['events', T('Sự kiện', 'Events')], ['rewards', T('Thưởng', 'Rewards')]]} />
            {unreadAll.length > 0 && (
              <div style={{ textAlign: 'right', paddingBottom: 4 }}>
                <button type="button" data-testid="notifications-mark-all" onClick={() => unreadAll.forEach(n => markNotificationRead(n.id))} style={{ border: 'none', background: 'none', padding: 0, fontFamily: 'inherit', fontSize: 13, color: ink, borderBottom: `1px solid ${rule}`, cursor: 'pointer' }}>{T('Đánh dấu đã đọc', 'Mark all as read')}</button>
              </div>
            )}
            {list.map(n => (
              <NotificationRow key={n.id} n={n} unread={!n.read_at} avatar={avatarSourceFor(n, { bookingById: s.notificationBookingById, eventPhotoByEventId: s.notificationEventPhotoByEventId, avatarByUserId: s.notificationAvatarByUserId }, s.accountType)}
                onClick={() => { set({ activityTab: 'notifications', activityScroll: scroller()?.scrollTop || 0, activityReturn: true }); openNotification(n); }} />
            ))}
            {list.length === 0 && <p style={{ padding: '48px 20px', margin: 0, textAlign: 'center', fontSize: 14, color: ink2 }}>{T('Chưa có thông báo nào.', 'Nothing here yet.')}</p>}
          </div>
        );
      })() : (<>
      {s.inboxView === 'active' && !searchOpen && (
        <div style={{ margin: '0 20px' }}>
          <Chips value={msgF} onChange={setMsgF} items={[['all', T('Tất cả', 'All')], ['unread', T('Chưa đọc', 'Unread')], ['dispute', T('Tranh chấp', 'Disputes')]]} />
        </div>
      )}
      {s.inboxView === 'archived' && (
        <div onClick={() => setInboxView('active')} data-testid="inbox-back-to-active" style={{ padding: '0 24px 8px', fontSize: 12.5, color: ink, opacity: 0.7, cursor: 'pointer' }}>
          ‹ {T('Quay lại Tin nhắn', 'Back to Messages')}
        </div>
      )}

      {/* iOS parity: no standalone dispute band. A dispute lives inside its
          conversation; the row below is just highlighted. */}

      {visible.length > 0 ? (
        <div style={{ padding: '0 20px 40px' }}>
          {visible.map(c => (
            <InboxRow
              key={c.threadId}
              c={c}
              T={T}
              disputeActive={activeDisputeThreads.has(c.threadId)}
              onOpen={() => openThread(c.threadId, c.eventKey, 'inbox', c.name)}
              onStar={() => toggleThreadStar(c.threadId)}
              onArchive={() => (c.archived ? unarchiveThread(c.threadId) : archiveThread(c.threadId))}
              onDelete={() => setDeleteTarget(c.threadId)}
            />
          ))}
        </div>
      ) : (
        // Calm Pass phase 2: an empty inbox says how a conversation starts and offers the way there. A search with no
        // hits or an empty archive stays a plain line (nothing to do there).
        query.trim() ? (
          <p data-testid="inbox-empty-search" style={{ padding: '60px 40px', margin: 0, textAlign: 'center', fontSize: 14, lineHeight: 1.55, color: ink }}>
            {T('Không có cuộc trò chuyện nào khớp.', 'No conversations match.')}
          </p>
        ) : s.inboxView === 'archived' ? (
          <p data-testid="inbox-empty-archived" style={{ padding: '80px 40px', margin: 0, textAlign: 'center', fontSize: 14, lineHeight: 1.55, color: ink }}>{emptyArchived}</p>
        ) : (
          <div style={{ padding: '32px 0' }}>
            <EmptyState scene="explore" testId="inbox-empty"
              title={T('Chưa có cuộc trò chuyện nào', 'No conversations yet')}
              message={T('Nhắn cho người tổ chức từ trang sự kiện. Cuộc trò chuyện sẽ hiện ở đây.', 'Message a host from an event page. Your conversations show up here.')}
              actionLabel={T('Tìm sự kiện', 'Find events')} actionTestId="inbox-empty-find" onAction={goHome} />
          </div>
        )
      )}

      </>)}

      {deleteTarget && (
        <div onClick={() => setDeleteTarget(null)} data-testid="inbox-delete-confirm" style={{ position: 'absolute', inset: 0, zIndex: 30, background: 'rgba(12,12,12,0.55)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'banbeFade 0.2s ease both' }}>
          <div onClick={(e) => e.stopPropagation()} style={{ ...cardGlass({ borderRadius: '18px 18px 0 0' }), padding: '22px 22px 34px', display: 'flex', flexDirection: 'column', gap: 14, animation: 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
            <span style={{ ...display(18) }}>{T('Xoá cuộc trò chuyện này?', 'Delete this conversation?')}</span>
            <span style={{ fontSize: 13.5, lineHeight: 1.5, color: ink, opacity: 0.8 }}>
              {T('Chỉ xoá với bạn. Người kia vẫn giữ cuộc trò chuyện. Nếu họ nhắn lại cho bạn, cuộc trò chuyện sẽ hiện lại.', 'It is removed for you only. The other person keeps it. It comes back if they message you again.')}
            </span>
            <div style={{ display: 'flex', gap: 10 }}>
              <div onClick={() => setDeleteTarget(null)} data-testid="inbox-delete-cancel" style={{ ...fieldGlass({ flex: 1, padding: '13px 0', borderRadius: 999, textAlign: 'center' }), fontSize: 13.5, fontWeight: 600, color: ink, cursor: 'pointer' }}>{T('Huỷ', 'Cancel')}</div>
              <div onClick={() => { const id = deleteTarget; setDeleteTarget(null); deleteThreadForMe(id); }} data-testid="inbox-delete-confirm-button" style={{ flex: 1, padding: '13px 0', borderRadius: 999, textAlign: 'center', fontSize: 13.5, fontWeight: 600, background: alert, color: 'var(--bb-on-alert)', cursor: 'pointer' }}>{T('Xoá', 'Delete')}</div>
            </div>
          </div>
        </div>
      )}

      {feedbackOpen && <FeedbackFlow onClose={() => setFeedbackOpen(false)} T={T} />}
    </div>
  );
}

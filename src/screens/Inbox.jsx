import { useMemo, useRef, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { bg } from '../data/events.js';
import { paper, ink, rule, alert, display, fieldGlass, inkButton, cardGlass } from '../theme.js';

// Swipe-left reveal width — two 72px actions (Task 2, 2026-09-21 follow-up).
const ACTION_WIDTH = 72;
const REVEAL_WIDTH = ACTION_WIDTH * 2;

// One row, with its own swipe-to-reveal drag state — kept per-row (not one
// shared offset on the list) so opening one row's actions doesn't affect
// any other row, and scrolling the list vertically isn't fought by a
// horizontal drag started elsewhere.
function InboxRow({ c, onOpen, onStar, onArchive }) {
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
    <div style={{ position: 'relative', overflow: 'hidden', borderBottom: `1px solid ${rule}` }}>
      <div style={{ position: 'absolute', top: 0, right: 0, bottom: 0, width: REVEAL_WIDTH, display: 'flex' }}>
        <div
          onClick={(e) => { e.stopPropagation(); onStar(); setOffset(0); }}
          data-testid="inbox-row-star"
          style={{ width: ACTION_WIDTH, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 4, background: alert, color: '#fff', cursor: 'pointer' }}
        >
          <span style={{ fontSize: 18, lineHeight: 1 }}>{c.starred ? '★' : '☆'}</span>
          <span style={{ fontSize: 10, fontWeight: 600 }}>Star</span>
        </div>
        <div
          onClick={(e) => { e.stopPropagation(); onArchive(); setOffset(0); }}
          data-testid="inbox-row-archive"
          style={{ width: ACTION_WIDTH, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 4, background: ink, color: paper, cursor: 'pointer' }}
        >
          <span style={{ fontSize: 16, lineHeight: 1 }}>{c.archived ? '📤' : '🗄'}</span>
          <span style={{ fontSize: 10, fontWeight: 600 }}>{c.archived ? 'Unarchive' : 'Archive'}</span>
        </div>
      </div>
      <div
        onClick={handleRowClick}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        data-testid="inbox-row"
        style={{
          display: 'flex', gap: 16, alignItems: 'center', padding: '16px 0', cursor: 'pointer',
          background: paper, transform: `translateX(${offset}px)`, transition: dragRef.current.active ? 'none' : 'transform 0.2s ease',
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
            <span style={{ ...display(18, { lineHeight: 1.15, fontWeight: 700, opacity: unread ? 1 : 0.62 }) }}>{c.name}</span>
          </div>
          <span style={{ fontSize: 13, color: ink, opacity: unread ? 1 : 0.72, fontWeight: unread ? 600 : 400, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{c.snippet}</span>
        </div>
        {/* Bug 1 (2026-09-21 follow-up) — moved off the avatar (where it
            could collide with the merged-avatar badge) to the row's own
            far trailing edge instead. */}
        {c.starred && (
          <span data-testid="inbox-row-star-badge" style={{ fontSize: 15, color: alert, flex: 'none' }}>★</span>
        )}
      </div>
    </div>
  );
}

// Task 1b — "Give feedback": single-choice screen -> text+bug-toggle screen,
// matching the attached reference screenshots. Local, ephemeral UI state
// (not global GocContext state) — same convention Notifications.jsx's own
// `expandedSections` toggle already uses for a purely in-screen concern.
function FeedbackFlow({ onClose, T }) {
  const { submitFeedback } = useGoc();
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
    <div style={{ position: 'absolute', inset: 0, zIndex: 40, background: paper, display: 'flex', flexDirection: 'column', animation: 'gocIn 0.28s cubic-bezier(.22,.61,.36,1) both' }} data-testid="feedback-flow">
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
          <span style={{ ...display(24) }}>{T('Gửi phản hồi', 'Give feedback')}</span>
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
          <span style={{ ...display(24) }}>{T('Kể cho chúng tôi nghe', 'Tell us about it')}</span>
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

export default function Inbox() {
  const { state, T, backFromInbox, openThread, toggleThreadStar, archiveThread, unarchiveThread, setInboxView } = useGoc();
  const s = state;

  const [searchOpen, setSearchOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [feedbackOpen, setFeedbackOpen] = useState(false);

  const merged = useMemo(() => s.inboxThreads.map(c => ({
    ...c,
    starred: !!s.inboxThreadPrefs[c.threadId]?.starred,
    archived: !!s.inboxThreadPrefs[c.threadId]?.archived,
  })), [s.inboxThreads, s.inboxThreadPrefs]);

  const visible = useMemo(() => {
    const byView = merged.filter(c => (s.inboxView === 'archived' ? c.archived : !c.archived));
    const q = query.trim().toLowerCase();
    if (!q) return byView;
    // Task 1a — reuses a plain client-side substring filter (this app has
    // no other real text-search backend to call into, only MapExplore's
    // "Search here" location re-query, which is a different concept).
    return byView.filter(c => c.name.toLowerCase().includes(q) || c.snippet.toLowerCase().includes(q));
  }, [merged, s.inboxView, query]);

  const empty = T('Chưa có cuộc trò chuyện nào. Nhắn cho người tổ chức từ trang sự kiện.', 'No conversations yet. Message an organizer from an event page.');
  const emptyArchived = T('Chưa có cuộc trò chuyện nào được lưu trữ.', 'No archived conversations yet.');

  return (
    <div style={{ position: 'relative', animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Inbox">
      <div style={{ padding: '70px 24px 8px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        {searchOpen ? (
          <input
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={T('Tìm cuộc trò chuyện…', 'Search conversations…')}
            data-testid="inbox-search-input"
            style={{ ...fieldGlass({ flex: 1, padding: '10px 14px', borderRadius: 999, border: 'none', marginRight: 10 }), fontSize: 13.5, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none' }}
          />
        ) : (
          <span style={{ ...display(27) }}>{s.inboxView === 'archived' ? T('Đã lưu trữ', 'Archived') : T('Tin nhắn', 'Messages')}</span>
        )}
        {/* Task 1 — "Done" replaced with search + settings icons. Task 5 —
            each icon-only control gets a small label underneath. */}
        <div style={{ display: 'flex', gap: 14, flex: 'none' }}>
          <div
            onClick={() => { if (searchOpen) setQuery(''); setSearchOpen(v => !v); }}
            data-testid="inbox-search-toggle"
            style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2, cursor: 'pointer' }}
          >
            <span style={{ width: 34, height: 34, borderRadius: '50%', ...fieldGlass({}), display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, color: ink }}>
              {searchOpen ? '✕' : '🔍'}
            </span>
            <span style={{ fontSize: 9.5, color: ink, opacity: 0.7 }}>{searchOpen ? T('Đóng', 'Close') : T('Tìm', 'Search')}</span>
          </div>
          {s.inboxView === 'active' && (
            <div
              onClick={() => setSettingsOpen(true)}
              data-testid="inbox-settings-toggle"
              style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2, cursor: 'pointer' }}
            >
              <span style={{ width: 34, height: 34, borderRadius: '50%', ...fieldGlass({}), display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, color: ink }}>⚙</span>
              <span style={{ fontSize: 9.5, color: ink, opacity: 0.7 }}>{T('Cài đặt', 'Settings')}</span>
            </div>
          )}
        </div>
      </div>

      {s.inboxView === 'archived' && (
        <div onClick={() => setInboxView('active')} data-testid="inbox-back-to-active" style={{ padding: '0 24px 8px', fontSize: 12.5, color: ink, opacity: 0.7, cursor: 'pointer' }}>
          ‹ {T('Quay lại Tin nhắn', 'Back to Messages')}
        </div>
      )}

      {visible.length > 0 ? (
        <div style={{ padding: '6px 24px 40px' }}>
          {visible.map(c => (
            <InboxRow
              key={c.threadId}
              c={c}
              onOpen={() => openThread(c.threadId, c.eventKey, 'inbox', c.name)}
              onStar={() => toggleThreadStar(c.threadId)}
              onArchive={() => (c.archived ? unarchiveThread(c.threadId) : archiveThread(c.threadId))}
            />
          ))}
        </div>
      ) : (
        <div style={{ padding: '80px 40px', textAlign: 'center' }}>
          <p style={{ fontSize: 14, lineHeight: 1.55, color: ink }}>{s.inboxView === 'archived' ? emptyArchived : empty}</p>
        </div>
      )}

      {!searchOpen && s.inboxView === 'active' && (
        <div onClick={backFromInbox} data-testid="inbox-done" style={{ position: 'absolute', top: 22, right: 24, fontSize: 11, color: ink, opacity: 0.5, cursor: 'pointer' }}>
          {T('Xong', 'Done')}
        </div>
      )}

      {settingsOpen && (
        <div onClick={() => setSettingsOpen(false)} style={{ position: 'absolute', inset: 0, zIndex: 30, background: 'rgba(12,12,12,0.55)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'gocFade 0.2s ease both' }}>
          <div onClick={(e) => e.stopPropagation()} style={{ ...cardGlass({ borderRadius: '18px 18px 0 0' }), padding: '18px 22px 34px', display: 'flex', flexDirection: 'column', animation: 'gocSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
              <span style={{ ...display(18) }}>{T('Cài đặt tin nhắn', 'Messaging settings')}</span>
              <span onClick={() => setSettingsOpen(false)} style={{ fontSize: 18, color: ink, cursor: 'pointer' }}>✕</span>
            </div>
            <div
              onClick={() => { setSettingsOpen(false); setInboxView('archived'); }}
              data-testid="inbox-menu-archived"
              style={{ padding: '13px 2px', borderTop: `1px solid ${rule}`, fontSize: 14.5, color: ink, cursor: 'pointer' }}
            >
              {T('Đã lưu trữ', 'Archived')}
            </div>
            <div
              onClick={() => { setSettingsOpen(false); setFeedbackOpen(true); }}
              data-testid="inbox-menu-feedback"
              style={{ padding: '13px 2px', borderTop: `1px solid ${rule}`, fontSize: 14.5, color: ink, cursor: 'pointer' }}
            >
              {T('Gửi phản hồi', 'Give feedback')}
            </div>
          </div>
        </div>
      )}

      {feedbackOpen && <FeedbackFlow onClose={() => setFeedbackOpen(false)} T={T} />}
    </div>
  );
}

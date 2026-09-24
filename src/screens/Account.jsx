import { useEffect, useRef, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { EVENTS } from '../data/events.js';
import { paper, ink, rule, display, fieldGlass, cardGlass, inkButton, alert } from '../theme.js';
import { AttachMenuIcon } from './Chat.jsx';

// TASK 3C (2026-09-22 twenty-first follow-up) — no existing icon
// component/library covers this screen's semantics (only Chat.jsx's own
// attach-menu `AttachMenuIcon`, a different icon set for a different
// purpose), so per this ticket's own instruction this is a minimal local
// inline-SVG set: one stroke weight (1.8), one viewBox (24x24 at 18px),
// `ink` only — no new colors, no third-party icon set.
function RowIcon({ kind, size = 22 }) {
  const glyphSize = Math.round(size * 0.82);
  const common = { width: glyphSize, height: glyphSize, viewBox: '0 0 24 24', fill: 'none', stroke: ink, strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' };
  const byKind = {
    pencil: <path d="M15.2 4.3l4.5 4.5L8.4 20.1H4v-4.4z" />,
    calendarCheck: <><rect x="3.5" y="5" width="17" height="15.5" rx="2.3" /><path d="M3.5 9.7h17" /><path d="M8 3v4M16 3v4" /><path d="M8.7 14.7l2 2 4.3-4.3" /></>,
    sliders: <><path d="M4 6.5h6M14 6.5h6M4 12h9M17 12h3M4 17.5h11M19 17.5h1" /><circle cx="12" cy="6.5" r="2.1" /><circle cx="15" cy="12" r="2.1" /><circle cx="17" cy="17.5" r="2.1" /></>,
    receipt: <><path d="M6.5 3h11v18l-2.3-1.5L13 21l-2.2-1.5L8.5 21l-2-1.5V3z" /><path d="M9.2 8.2h5.6M9.2 12h5.6M9.2 15.8h3.6" /></>,
    document: <><path d="M7.3 3h6.4l4 4v14H7.3z" /><path d="M13.7 3v4h4" /><path d="M9.6 12.3h5M9.6 15.7h5" /></>,
    shield: <path d="M12 3.2l6.8 2.8v5.7c0 4.7-3 7.4-6.8 8.7-3.8-1.3-6.8-4-6.8-8.7V6z" />,
    banknote: <><rect x="3" y="7.3" width="18" height="9.4" rx="1.6" /><circle cx="12" cy="12" r="2.3" /><path d="M6 9.8h0M18 14.2h0" /></>,
    checklist: <><path d="M4.2 6.3h1.8M4.2 12h1.8M4.2 17.7h1.8" /><path d="M9 6.3h10.8M9 12h10.8M9 17.7h6.6" /></>,
    users: <><circle cx="9" cy="8" r="3" /><path d="M3.6 19c0-3.2 2.4-5.4 5.4-5.4S14.4 15.8 14.4 19" /><circle cx="17.3" cy="9.6" r="2.2" /><path d="M15.7 13.6c2.2.4 3.9 2.2 3.9 5" /></>,
    switch: <><rect x="3" y="9" width="18" height="6" rx="3" /><circle cx="8" cy="12" r="2.1" /></>,
    logout: <><path d="M9.2 4.3H5v15.4h4.2" /><path d="M12.3 12h8.7M21 12l-3.3-3.3M21 12l-3.3 3.3" /></>,
    login: <><path d="M9.2 4.3H5v15.4h4.2" /><path d="M12.3 12h8.7M17.7 8.7l3.3 3.3-3.3 3.3" /></>,
    alertShield: <><path d="M12 3.2l6.8 2.8v5.7c0 4.7-3 7.4-6.8 8.7-3.8-1.3-6.8-4-6.8-8.7V6z" /><path d="M12 8.5v4.3M12 15.4v0" /></>,
  };
  return (
    <span aria-hidden style={{ width: size, height: size, flex: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', opacity: 0.72 }}>
      <svg {...common}>{byKind[kind]}</svg>
    </span>
  );
}

export default function Account() {
  const {
    state, T, goHome, goEditName, openPreferences, goGoingList, goSavedList, goCompletedList, openSecurity, openDocuments, openPayout, openVerifications, openDisputes, switchToHost, goLogin, logout, canHost, toggleOrganizerMode, referralLink, shareReferral,
    openRefundAccounts, openMyRefunds,
    loadHomeStories, openStoryViewer, pickStoryFile, cancelStoryCreate, publishStory,
  } = useGoc();
  const s = state;
  const storyFileRef = useRef(null);
  const storyCameraRef = useRef(null);
  // Task 1 (2026-09-21 real-device follow-up) — "Post Story" is now a real
  // two-option menu (Photo library / Camera), matching Chat.jsx's own
  // attach-menu convention (same icon set, same popup shape) instead of a
  // single link that only ever opened the library picker.
  const [storyMenuOpen, setStoryMenuOpen] = useState(false);

  // Task 3.3 (07-notifications.md) — loads active stories (mine + followed
  // hosts') so the ring below reflects real data even when Account is
  // opened directly, without having visited Home first this session.
  useEffect(() => { if (s.user) loadHomeStories(); }, [s.user, loadHomeStories]);
  const myStoryGroup = s.myOrganizerIds.length ? s.homeStories.find(g => s.myOrganizerIds.includes(g.organizerId)) : null;
  const hasActiveStory = !!myStoryGroup;
  const storyUnviewed = hasActiveStory && !myStoryGroup.allViewed;

  const onPickStoryFile = (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (file) pickStoryFile(file);
  };
  const doPublishStory = async () => { await publishStory(); };
  const completedCount = [...new Set([...(s.favorites || []), ...s.attending])]
    .map(k => EVENTS.find(e => e.key === k))
    .filter(e => e && e.endedHoursAgo != null).length;
  // Once an event is over it belongs in "Completed", not "Going" — otherwise
  // it just sits there forever looking like something still upcoming.
  const goingCount = s.attending
    .map(k => EVENTS.find(e => e.key === k))
    .filter(e => e && e.endedHoursAgo == null).length;

  const profileName = s.user ? (s.user.name || (s.user.email ? s.user.email.split('@')[0] : T('Bạn', 'You'))) : T('Khách', 'Guest');
  const isOrganizer = canHost;
  const profileSub = s.accountType === 'admin' ? T('Quản trị viên', 'Admin') : isOrganizer ? T('Người tham gia ▪︎ Người tổ chức', 'Goer ▪︎ Host') : T('Người tham gia', 'Goer');
  const profileOrgName = (s.orgRegName && s.orgRegName.trim()) || 'Bếp Nhỏ';

  return (
    <div style={{ position: 'relative', animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Account">
      <div style={{ padding: '66px 20px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ ...display(27) }}>{T('Tài khoản', 'Account')}</span>
        <span onClick={goHome} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>Xong</span>
      </div>

      <div style={{ padding: '22px 20px 0', display: 'flex', gap: 14, alignItems: 'center' }}>
        {/* Task 3.3 (07-notifications.md) — story ring: a bright outline
            while this host has an active, not-fully-viewed story; a
            subdued one once every active story has been viewed; no ring
            at all when there's no active story. Tapping the avatar opens
            the viewer only when there's something to view. */}
        <div
          onClick={hasActiveStory ? () => openStoryViewer(myStoryGroup.organizerId) : undefined}
          data-testid="account-story-ring"
          data-story-state={hasActiveStory ? (storyUnviewed ? 'unviewed' : 'viewed') : 'none'}
          style={{
            flex: 'none', width: 64, height: 64, borderRadius: 15, display: 'flex', alignItems: 'center', justifyContent: 'center',
            border: hasActiveStory ? `2.5px solid ${storyUnviewed ? alert : 'transparent'}` : '2.5px solid transparent',
            boxShadow: hasActiveStory && !storyUnviewed ? `inset 0 0 0 2.5px ${rule}` : 'none',
            cursor: hasActiveStory ? 'pointer' : 'default',
          }}
        >
          <div style={{ ...fieldGlass({ width: 56, height: 56, borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center' }), ...display(22) }}>G</div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, minWidth: 0 }}>
            <span style={{ ...display(22, { lineHeight: 1.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{profileName}</span>
            {s.user && (
              <span onClick={goEditName} style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 11.5, color: ink, opacity: 0.65, cursor: 'pointer', flex: 'none' }}>
                <RowIcon kind="pencil" size={13} />{T('Đổi tên', 'Rename')}
              </span>
            )}
          </div>
          <span style={{ fontSize: 11, letterSpacing: '0.06em', color: ink }}>{profileSub}</span>
          {/* Task 3.2 — story creation entry point, hosts only. */}
          {isOrganizer && (
            <div style={{ position: 'relative' }}>
              <span onClick={() => setStoryMenuOpen(v => !v)} data-testid="account-post-story" style={{ fontSize: 11.5, color: ink, opacity: 0.65, cursor: 'pointer' }}>
                {T('▪︎ Đăng story', '▪︎ Post story')}
              </span>
              {storyMenuOpen && (
                <div onClick={() => setStoryMenuOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 35 }}>
                  <div
                    onClick={(e) => e.stopPropagation()}
                    style={{ ...cardGlass({ position: 'absolute', top: 20, left: 0, minWidth: 200 }), padding: 6, display: 'flex', flexDirection: 'column' }}
                  >
                    <div
                      onClick={() => { setStoryMenuOpen(false); storyFileRef.current?.click(); }}
                      data-testid="account-post-story-library"
                      style={{ padding: '12px 14px', fontSize: 13.5, color: ink, cursor: 'pointer', borderRadius: 8, display: 'flex', alignItems: 'center', gap: 10 }}
                    >
                      <AttachMenuIcon name="library" />
                      {T('Thư viện ảnh', 'Photo library')}
                    </div>
                    <div
                      onClick={() => { setStoryMenuOpen(false); storyCameraRef.current?.click(); }}
                      data-testid="account-post-story-camera"
                      style={{ padding: '12px 14px', fontSize: 13.5, color: ink, cursor: 'pointer', borderRadius: 8, display: 'flex', alignItems: 'center', gap: 10 }}
                    >
                      <AttachMenuIcon name="camera" />
                      {T('Camera', 'Camera')}
                    </div>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
        <input ref={storyFileRef} type="file" accept="image/*" style={{ display: 'none' }} onChange={onPickStoryFile} data-testid="story-file-input" />
        <input ref={storyCameraRef} type="file" accept="image/*" capture="environment" style={{ display: 'none' }} onChange={onPickStoryFile} data-testid="story-camera-input" />
      </div>

      {/* Task 3.2 — Retake / Use Photo preview before actually publishing. */}
      {s.storyCreatePreview && (
        <div style={{ position: 'absolute', inset: 0, zIndex: 50, background: '#000', display: 'flex', flexDirection: 'column' }} data-testid="story-create-preview">
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
            <img src={s.storyCreatePreview.url} alt="" style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain' }} />
          </div>
          <div style={{ padding: '16px 22px 34px', display: 'flex', gap: 10 }}>
            <div
              onClick={s.storyCreateBusy ? undefined : () => { cancelStoryCreate(); storyCameraRef.current?.click(); }}
              data-testid="story-retake"
              style={{ flex: 1, textAlign: 'center', padding: '13px', borderRadius: 12, border: '1px solid rgba(255,255,255,0.35)', color: '#fff', fontSize: 13.5, fontWeight: 600, cursor: 'pointer' }}
            >
              {T('Chụp lại', 'Retake')}
            </div>
            <div
              onClick={s.storyCreateBusy ? undefined : doPublishStory}
              data-testid="story-use-photo"
              style={{ flex: 1, textAlign: 'center', padding: '13px', borderRadius: 12, background: '#fff', color: '#000', fontSize: 13.5, fontWeight: 600, cursor: 'pointer', opacity: s.storyCreateBusy ? 0.6 : 1 }}
            >
              {s.storyCreateBusy ? T('Đang đăng…', 'Posting…') : T('Dùng ảnh', 'Use photo')}
            </div>
          </div>
        </div>
      )}

      <div style={{ display: 'flex', gap: 10, padding: '22px 20px 0' }}>
        {/* data-attending-raw-count is the unfiltered s.attending.length — not
            shown to users (goingCount below is what actually renders, and is
            deliberately narrowed to the static demo catalogue + not-yet-ended
            events). Exists purely so a test can observe the real client-side
            "going" state for a booking outside that catalogue, which no
            visible UI element can ever reflect otherwise. */}
        <div onClick={goGoingList} data-testid="account-going-card" data-attending-raw-count={s.attending.length} style={{ ...cardGlass({ flex: 1, padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 3, cursor: 'pointer' }) }}>
          <RowIcon kind="calendarCheck" size={18} />
          <span style={{ ...display(24) }}>{goingCount}</span>
          <span style={{ fontSize: 11, color: ink }}>{T('Đang tham gia', 'Going')}</span>
        </div>
        <div onClick={goSavedList} data-testid="account-saved-card" style={{ ...cardGlass({ flex: 1, padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 3, cursor: 'pointer' }) }}>
          <RowIcon kind="document" size={18} />
          <span style={{ ...display(24) }}>{(s.favorites || []).length}</span>
          <span style={{ fontSize: 11, color: ink }}>{T('Đã lưu', 'Saved')}</span>
        </div>
      </div>

      {referralLink && (
        <div style={{ ...cardGlass({ margin: '20px 20px 0', padding: '16px 18px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 14, cursor: 'pointer' }) }} onClick={shareReferral}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, minWidth: 0 }}>
          <RowIcon kind="users" />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
            <span style={{ ...display(16) }}>{T('Mời bạn bè', 'Invite friends')}</span>
            <span style={{ fontSize: 11.5, lineHeight: 1.45, color: ink, opacity: 0.7 }}>
              {s.referralShared
                ? T('Đã sao chép link mời ▪︎ gửi cho bạn bè thôi!', 'Invite link copied ▪︎ send it to a friend!')
                : T('Rủ bạn bè cùng tham gia banbe qua link riêng của bạn.', 'Bring friends onto banbe with your own link.')}
            </span>
          </div>
          </div>
          <span style={{ flex: 'none', fontSize: 12, fontWeight: 600, color: paper, background: ink, borderRadius: 999, padding: '9px 16px' }}>{T('Chia sẻ', 'Share')}</span>
        </div>
      )}

      {/* TASK 3A (2026-09-22 twenty-first follow-up) — the "Tin nhắn"/
          Messages shortcut row removed entirely from Account per this
          ticket's own ask; Inbox stays reachable exactly as before via the
          bottom dock (BottomTabBar.jsx), untouched. */}
      <div style={{ ...fieldGlass({ margin: '20px 20px 0', display: 'flex', flexDirection: 'column' }) }}>
        <div onClick={goCompletedList} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', borderBottom: `1px solid ${rule}`, cursor: 'pointer' }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}><RowIcon kind="calendarCheck" />{T('Sự kiện đã hoàn thành', 'Completed events')}</span>
          <span style={{ fontSize: 13, color: ink }}>{completedCount} ›</span>
        </div>
        {/* TASK 3B — broader, more accurate label: this screen holds more
            than language/theme (see PreferencesView/Preferences.jsx).
            Destination (`openPreferences`) and the right-side summary are
            unchanged. */}
        <div onClick={openPreferences} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', borderBottom: `1px solid ${rule}`, cursor: 'pointer' }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}><RowIcon kind="sliders" />{T('Tùy chỉnh ứng dụng', 'App preferences')}</span>
          <span style={{ fontSize: 13, color: ink }}>{s.lang === 'en' ? 'English' : 'Tiếng Việt'} ▪︎ {s.theme === 'dark' ? T('Tối', 'Dark') : T('Sáng', 'Light')}</span>
        </div>
        <div onClick={() => openDocuments('invoice', 'guest')} data-testid="account-invoices" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', borderBottom: `1px solid ${rule}`, cursor: 'pointer' }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}><RowIcon kind="document" />{T('Hoá đơn', 'Invoices')}</span>
          <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
        </div>
        <div onClick={() => openDocuments('receipt', 'guest')} data-testid="account-receipts" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', borderBottom: `1px solid ${rule}`, cursor: 'pointer' }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}><RowIcon kind="receipt" />{T('Biên nhận', 'Receipts')}</span>
          <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
        </div>
        {/* Refund MVP (product rule A) — a persistent entry point, reachable
            regardless of whether a notification was ever tapped. */}
        <div onClick={() => openRefundAccounts('profile')} data-testid="account-refund-accounts" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', borderBottom: `1px solid ${rule}`, cursor: 'pointer' }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}><RowIcon kind="banknote" />{T('Tài khoản thanh toán & nhận hoàn tiền', 'Payment & refund accounts')}</span>
          <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
        </div>
        <div onClick={() => openMyRefunds('profile')} data-testid="account-refunds" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', borderBottom: `1px solid ${rule}`, cursor: 'pointer' }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}><RowIcon kind="checklist" />{T('Hoàn tiền', 'Refunds')}</span>
          <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
        </div>
        <div onClick={openSecurity} data-testid="account-security" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', cursor: 'pointer' }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}><RowIcon kind="shield" />{T('Bảo mật', 'Security')}</span>
          <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
        </div>
      </div>

      <div style={{ padding: '22px 20px 0' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Tổ chức', 'Hosting')}</span>
        <div onClick={toggleOrganizerMode} data-testid="organizer-mode-toggle" style={{ ...fieldGlass({ marginTop: 10, padding: '15px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }) }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, minWidth: 0, paddingRight: 12 }}>
            <RowIcon kind="switch" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
              <span style={{ fontSize: 14, color: ink }}>{T('Chế độ tổ chức', 'Organizer mode')}</span>
              <span style={{ fontSize: 11.5, lineHeight: 1.45, color: ink, opacity: 0.7 }}>{T('Bật để tạo và quản lý sự kiện. Tắt lúc nào cũng được.', 'Turn on to create and manage events. Turn it off any time.')}</span>
            </div>
          </div>
          <span aria-hidden style={{ flex: 'none', width: 44, height: 26, borderRadius: 13, padding: 3, background: isOrganizer ? ink : 'rgba(27,25,22,0.18)', transition: 'background .15s' }}>
            <span style={{ display: 'block', width: 20, height: 20, borderRadius: '50%', background: paper, transform: isOrganizer ? 'translateX(18px)' : 'translateX(0)', transition: 'transform .15s' }} />
          </span>
        </div>
        {s.organizerModeError && <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '10px 0 0' }}>{s.organizerModeError}</p>}
        {isOrganizer && (
          <div style={{ ...fieldGlass({ marginTop: 10, display: 'flex', flexDirection: 'column' }) }}>
            <div onClick={openVerifications} data-testid="host-verifications" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', borderBottom: `1px solid ${rule}`, cursor: 'pointer' }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}><RowIcon kind="checklist" />{T('Chờ xác nhận thanh toán', 'Awaiting verification')}</span>
              <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
            </div>
            <div onClick={openPayout} data-testid="host-payout" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', borderBottom: `1px solid ${rule}`, cursor: 'pointer' }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}><RowIcon kind="banknote" />{T('Nhận thanh toán', 'Getting paid')}</span>
              <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
            </div>
            <div onClick={() => openDocuments('invoice', 'host')} data-testid="host-invoices" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', borderBottom: `1px solid ${rule}`, cursor: 'pointer' }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}><RowIcon kind="document" />{T('Hoá đơn đã phát hành', 'Invoices issued')}</span>
              <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
            </div>
            <div onClick={() => openDocuments('receipt', 'host')} data-testid="host-receipts" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', cursor: 'pointer' }}>
              <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}><RowIcon kind="receipt" />{T('Biên nhận đã phát hành', 'Receipts issued')}</span>
              <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
            </div>
          </div>
        )}
        {isOrganizer ? (
          <div onClick={() => switchToHost('profile')} style={{ ...cardGlass({ marginTop: 10, padding: 16, display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }) }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12, minWidth: 0 }}>
              <RowIcon kind="users" />
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
                <span style={{ ...display(17, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{profileOrgName}</span>
                <span style={{ fontSize: 12, color: ink }}>
                  {s.mode === 'host' ? T('Xem trang tổ chức của bạn', 'View your host page') : T('Chuyển sang chế độ tổ chức', 'Switch to hosting')}
                </span>
              </div>
            </div>
            <span style={{ fontSize: 17, color: ink, flex: 'none', lineHeight: 1 }}>›</span>
          </div>
        ) : (
          <div style={{ ...cardGlass({ marginTop: 10, padding: '18px 16px', display: 'flex', flexDirection: 'column', gap: 10 }) }}>
            <span style={{ ...display(19, { lineHeight: 1.3 }) }}>{T('Tổ chức sự kiện đầu tiên', 'Host your first event')}</span>
            <p style={{ fontSize: 12.5, lineHeight: 1.5, color: ink, margin: 0 }}>
              {T('Miễn phí hoàn toàn khi banbe còn mới — không phí đăng, không phí giao dịch. Tạo sự kiện đầu tiên để mở trang tổ chức.', 'Completely free while banbe is new — no listing or transaction fees. Create your first event to unlock your host page.')}
            </p>
            <div onClick={toggleOrganizerMode} style={{ ...inkButton({ marginTop: 4, borderRadius: 18, padding: 14, fontSize: 14 }) }}>{T('Bắt đầu tổ chức ▪︎ miễn phí', 'Start hosting ▪︎ free')}</div>
          </div>
        )}
      </div>

      {s.accountType === 'admin' && (
        <div style={{ padding: '22px 20px 0' }}>
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Quản trị', 'Admin')}</span>
          <div onClick={openDisputes} data-testid="admin-disputes" style={{ ...fieldGlass({ marginTop: 10, padding: '15px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }) }}>
            <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}><RowIcon kind="alertShield" />{T('Tranh chấp thanh toán', 'Payment disputes')}</span>
            <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
          </div>
        </div>
      )}

      {s.user ? (
        <div onClick={logout} style={{ padding: '24px 20px 40px', display: 'flex', alignItems: 'center', gap: 12, fontSize: 13, color: ink, cursor: 'pointer' }}><RowIcon kind="logout" size={18} />{T('Đăng xuất', 'Sign out')}</div>
      ) : (
        <div onClick={goLogin} style={{ padding: '24px 20px 40px', display: 'flex', alignItems: 'center', gap: 12, fontSize: 12.5, lineHeight: 1.5, color: ink, cursor: 'pointer' }}><RowIcon kind="login" size={18} />{T('Đăng nhập để lưu sự kiện và nhắn tin', 'Sign in to save events and message hosts')}</div>
      )}
    </div>
  );
}

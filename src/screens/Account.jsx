import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, display, fieldGlass, cardGlass, inkButton } from '../theme.js';

export default function Account() {
  const { state, T, goHome, goInbox, goEditName, openPreferences, goGoingList, goSavedList, switchToHost, goLogin, logout, canHost, toggleOrganizerMode, referralLink, shareReferral } = useGoc();
  const s = state;

  const profileName = s.user ? (s.user.name || (s.user.email ? s.user.email.split('@')[0] : T('Bạn', 'You'))) : T('Khách', 'Guest');
  const isOrganizer = canHost;
  const profileSub = s.accountType === 'admin' ? T('Quản trị viên', 'Admin') : isOrganizer ? T('Người tham gia ▪︎ Người tổ chức', 'Goer ▪︎ Host') : T('Người tham gia', 'Goer');
  const profileOrgName = (s.orgRegName && s.orgRegName.trim()) || 'Bếp Nhỏ';

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Account">
      <div style={{ padding: '66px 20px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ ...display(27) }}>{T('Tài khoản', 'Account')}</span>
        <span onClick={goHome} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>Xong</span>
      </div>

      <div style={{ padding: '22px 20px 0', display: 'flex', gap: 14, alignItems: 'center' }}>
        <div style={{ ...fieldGlass({ flex: 'none', width: 56, height: 56, borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center' }), ...display(22) }}>G</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, minWidth: 0 }}>
            <span style={{ ...display(22, { lineHeight: 1.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{profileName}</span>
            {s.user && <span onClick={goEditName} style={{ fontSize: 11.5, color: ink, opacity: 0.65, cursor: 'pointer', flex: 'none' }}>{T('Đổi tên', 'Rename')}</span>}
          </div>
          <span style={{ fontSize: 11, letterSpacing: '0.06em', color: ink }}>{profileSub}</span>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 10, padding: '22px 20px 0' }}>
        <div onClick={goGoingList} data-testid="account-going-card" style={{ ...cardGlass({ flex: 1, padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 3, cursor: 'pointer' }) }}>
          <span style={{ ...display(24) }}>{s.attending.length}</span>
          <span style={{ fontSize: 11, color: ink }}>{T('Đang tham gia', 'Going')}</span>
        </div>
        <div onClick={goSavedList} data-testid="account-saved-card" style={{ ...cardGlass({ flex: 1, padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 3, cursor: 'pointer' }) }}>
          <span style={{ ...display(24) }}>{(s.favorites || []).length}</span>
          <span style={{ fontSize: 11, color: ink }}>{T('Đã lưu', 'Saved')}</span>
        </div>
      </div>

      {referralLink && (
        <div style={{ ...cardGlass({ margin: '20px 20px 0', padding: '16px 18px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 14, cursor: 'pointer' }) }} onClick={shareReferral}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
            <span style={{ ...display(16) }}>{T('Mời bạn bè', 'Invite friends')}</span>
            <span style={{ fontSize: 11.5, lineHeight: 1.45, color: ink, opacity: 0.7 }}>
              {s.referralShared
                ? T('Đã sao chép link mời ▪︎ gửi cho bạn bè thôi!', 'Invite link copied ▪︎ send it to a friend!')
                : T('Rủ bạn bè cùng tham gia banbe qua link riêng của bạn.', 'Bring friends onto banbe with your own link.')}
            </span>
          </div>
          <span style={{ flex: 'none', fontSize: 12, fontWeight: 600, color: paper, background: ink, borderRadius: 999, padding: '9px 16px' }}>{T('Chia sẻ', 'Share')}</span>
        </div>
      )}

      <div style={{ ...fieldGlass({ margin: '20px 20px 0', display: 'flex', flexDirection: 'column' }) }}>
        <div onClick={goInbox} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', borderBottom: `1px solid ${rule}`, cursor: 'pointer' }}>
          <span style={{ fontSize: 14, color: ink }}>{T('Tin nhắn', 'Messages')}</span>
          <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
        </div>
        <div onClick={goSavedList} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', borderBottom: `1px solid ${rule}`, cursor: 'pointer' }}>
          <span style={{ fontSize: 14, color: ink }}>{T('Sự kiện đã lưu', 'Saved events')}</span>
          <span style={{ fontSize: 13, color: ink }}>{(s.favorites || []).length} ›</span>
        </div>
        <div onClick={openPreferences} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', cursor: 'pointer' }}>
          <span style={{ fontSize: 14, color: ink }}>{T('Ngôn ngữ & hiển thị', 'Language & appearance')}</span>
          <span style={{ fontSize: 13, color: ink }}>{s.lang === 'en' ? 'English' : 'Tiếng Việt'} ▪︎ {s.theme === 'dark' ? T('Tối', 'Dark') : T('Sáng', 'Light')}</span>
        </div>
      </div>

      <div style={{ padding: '22px 20px 0' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Tổ chức', 'Hosting')}</span>
        <div onClick={toggleOrganizerMode} data-testid="organizer-mode-toggle" style={{ ...fieldGlass({ marginTop: 10, padding: '15px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }) }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0, paddingRight: 12 }}>
            <span style={{ fontSize: 14, color: ink }}>{T('Chế độ tổ chức', 'Organizer mode')}</span>
            <span style={{ fontSize: 11.5, lineHeight: 1.45, color: ink, opacity: 0.7 }}>{T('Bật để tạo và quản lý sự kiện. Tắt lúc nào cũng được.', 'Turn on to create and manage events. Turn it off any time.')}</span>
          </div>
          <span aria-hidden style={{ flex: 'none', width: 44, height: 26, borderRadius: 13, padding: 3, background: isOrganizer ? ink : 'rgba(27,25,22,0.18)', transition: 'background .15s' }}>
            <span style={{ display: 'block', width: 20, height: 20, borderRadius: '50%', background: paper, transform: isOrganizer ? 'translateX(18px)' : 'translateX(0)', transition: 'transform .15s' }} />
          </span>
        </div>
        {s.organizerModeError && <p style={{ fontSize: 12, lineHeight: 1.5, color: '#9A3E2D', margin: '10px 0 0' }}>{s.organizerModeError}</p>}
        {isOrganizer ? (
          <div onClick={() => switchToHost('profile')} style={{ ...cardGlass({ marginTop: 10, padding: 16, display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }) }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
              <span style={{ ...display(17, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{profileOrgName}</span>
              <span style={{ fontSize: 12, color: ink }}>
                {s.mode === 'host' ? T('Xem trang tổ chức của bạn', 'View your host page') : T('Chuyển sang chế độ tổ chức', 'Switch to hosting')}
              </span>
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

      {s.user ? (
        <div onClick={logout} style={{ padding: '24px 20px 40px', fontSize: 13, color: ink, cursor: 'pointer' }}>{T('Đăng xuất', 'Sign out')}</div>
      ) : (
        <div onClick={goLogin} style={{ padding: '24px 20px 40px', fontSize: 12.5, lineHeight: 1.5, color: ink, cursor: 'pointer' }}>{T('Đăng nhập để lưu sự kiện và nhắn tin', 'Sign in to save events and message hosts')}</div>
      )}
    </div>
  );
}

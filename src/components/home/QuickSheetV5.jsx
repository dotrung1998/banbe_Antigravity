// Quick settings panel from the Home avatar (v5 prototype `sheet()`): profile link, hosting switch, four shortcuts,
// Appearance + Language segments, Notifications and Sign out. Guests get the sign-in card plus the two segments.
import { useEffect, useState } from 'react';
import { accountTabs, resolveAccountTab } from '../../lib/accountTabs.js';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { resolveTheme } from '../../lib/themeChoice.js';
import { notifPrefsSummary } from '../../lib/notificationPrefs.js';
import { RowIcon } from '../../screens/Account.jsx';
import { computeMyTicketsActionCount } from '../../lib/badges.js';
import NotificationPrefs from '../../screens/NotificationPrefs.jsx';
import NativeSheet from '../NativeSheet.jsx';
import AccountAvatar from '../AccountAvatar.jsx';

const line = '1px solid var(--bb-divider, rgba(var(--bb-fg-rgb),.12))';
const seg = (on) => ({ height: 30, padding: '0 11px', border: 'none', borderRadius: 999, fontFamily: 'inherit', fontSize: 12, cursor: 'pointer',
  background: on ? 'var(--bb-fg)' : 'transparent', color: on ? 'var(--bb-bg)' : 'var(--bb-fg-2)', fontWeight: on ? 600 : 400 });

export default function QuickSheetV5({ onClose }) {
  const { state: s, set, T, pickTheme, toggleLang, goProfile, goLogin, logout, openAccountGroup, goSavedList, toggleOrganizerMode, canHost, goCreate, goDashboard, openAdminEvents } = useBanBe();
  // A first-time host gets the Host setup sheet after the switch turns on; it sits under this panel, so step aside.
  useEffect(() => { if (s.hostSetupOpen) onClose(); }, [s.hostSetupOpen, onClose]);
  // The dock slides away while this sheet is open (iOS parity).
  useEffect(() => { set({ quickSheetOpen: true }); return () => set({ quickSheetOpen: false }); }, [set]);
  const go = (fn) => () => { onClose(); fn(); };
  const user = s.user;
  const name = user ? (user.name || (user.email ? user.email.split('@')[0] : T('Bạn', 'You'))) : '';
  // The same Hosting mode switch as Account (organizer mode itself, not the Home view), so the switch and the
  // Host tab below can never disagree. Turning it on selects the Host tab, like the prototype.
  const hostOn = !!s.organizerMode;
  const [tabSel, setTabSel] = useState(null);
  const [view, setView] = useState('main'); // 'main' | 'prefs' (Notification preferences stays a sheet, sized to its content)
  const onHost = () => {
    if (s.organizerModeBusy) return;
    if (!hostOn) setTabSel('host');
    toggleOrganizerMode();
  };
  const tabs = user ? accountTabs({ isAdmin: s.accountType === 'admin', hostMode: hostOn && !!canHost }) : [];
  const tab = resolveAccountTab(tabSel || s.accountTab, tabs) || 'personal';
  const toAccount = (k) => () => { set({ screen: 'profile', accountTab: k }); };
  const dark = resolveTheme(s.theme, s.systemDark) === 'dark';
  const en = s.lang === 'en';
  const shortcuts = {
    personal: [
      ['ticket', T('Vé', 'Tickets'), () => openAccountGroup('activity'), computeMyTicketsActionCount(s)],
      ['wallet', T('Ví', 'Wallet'), () => openAccountGroup('payments')],
      ['bookmark', T('Đã lưu', 'Saved'), goSavedList],
      ['help', T('Trợ giúp', 'Help'), () => openAccountGroup('helpLegal')],
    ],
    host: [
      ['plus', T('Tạo', 'Create'), goCreate],
      ['calendarCheck', T('Sự kiện', 'Events'), () => goDashboard('home')],
      ['banknote', T('Nhận tiền', 'Get paid'), () => openAccountGroup('hostOps')],
      ['sliders', T('Cài đặt', 'Settings'), toAccount('host')],
    ],
    admin: [
      ['shield', T('Duyệt', 'Review'), () => set({ screen: 'accountGroup', accountGroupKey: 'adminReview', accountGroupBack: null })],
      ['calendarCheck', T('Sự kiện', 'Events'), () => openAdminEvents()],
      ['sliders', T('Công tắc', 'Switches'), () => set({ screen: 'adminFeatures' })],
      ['shield', T('Bảng quản trị', 'Console'), toAccount('admin')],
    ],
  }[tab];
  const tabLabel = { host: T('Tổ chức', 'Host'), personal: T('Cá nhân', 'Personal'), admin: T('Quản trị', 'Admin') };
  const row = { display: 'flex', alignItems: 'center', gap: 14, padding: '14px 0', borderBottom: line, minHeight: 56, fontSize: 15 };
  return (
    <NativeSheet open onClose={onClose} label={T('Cài đặt nhanh', 'Quick settings')} testId="home-quick-sheet" zIndex={2100}>
      <div
        style={{ width: '100%', maxHeight: '90%', overflowY: 'auto', background: 'var(--bb-bg)', color: 'var(--bb-fg)', borderRadius: '26px 26px 0 0', padding: '10px 0 calc(14px + env(safe-area-inset-bottom, 0px))', animation: 'banbeIn .32s cubic-bezier(.22,.61,.36,1) both' }}>
        <div style={{ width: 38, height: 5, borderRadius: 3, background: 'var(--bb-rule)', margin: '0 auto 12px' }} />
        {view === 'prefs' && user ? <NotificationPrefs embedded onBack={() => setView('main')} /> : (<>
        {user ? (
          <>
            <button type="button" onClick={go(goProfile)} data-testid="quick-account" style={{ display: 'flex', alignItems: 'center', gap: 16, width: '100%', padding: '8px 20px 0', border: 'none', background: 'none', color: 'inherit', font: 'inherit', textAlign: 'left', cursor: 'pointer' }}>
              <span style={{ flex: 'none', width: 64, height: 64, display: 'block' }}>
                <AccountAvatar name={name} avatarUrl={user.avatarUrl} size={64} />
              </span>
              <span style={{ flex: 1 }}>
                <span style={{ display: 'block', fontSize: 20, fontWeight: 300 }}>{name}</span>
                <span style={{ display: 'inline-block', marginTop: 6, fontSize: 13, borderBottom: '1px solid var(--bb-rule)' }}>{T('Tài khoản', 'Account')} ›</span>
              </span>
            </button>
            <div style={{ margin: '18px 20px 0' }}>
              <button type="button" role="switch" aria-checked={hostOn} disabled={s.organizerModeBusy} onClick={onHost} data-testid="quick-host-switch"
                style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', textAlign: 'left', padding: '12px 14px', border: 'none', borderRadius: 16, color: 'inherit', font: 'inherit', cursor: 'pointer',
                  background: hostOn ? 'color-mix(in srgb, var(--bb-moss, #5E7A5A) 14%, var(--bb-block))' : 'var(--bb-block)' }}>
                <span style={{ flex: 'none', width: 36, height: 36, borderRadius: '50%', background: 'var(--bb-bg)', display: 'grid', placeItems: 'center' }}><RowIcon kind="store" size={19} /></span>
                <span style={{ flex: 1, fontSize: 15, fontWeight: 600 }}>{T('Chế độ tổ chức', 'Hosting mode')}
                  <small style={{ display: 'block', fontSize: 12.5, fontWeight: 400, opacity: 0.75, marginTop: 1 }}>{T('Bật để tạo và quản lý sự kiện', 'Turn on to create and manage events')}</small></span>
                <span aria-hidden style={{ flex: 'none', width: 46, height: 28, borderRadius: 14, position: 'relative', background: hostOn ? 'var(--bb-moss, #5E7A5A)' : 'var(--bb-rule)', transition: 'background .2s' }}>
                  <span style={{ position: 'absolute', top: 3, left: 3, width: 22, height: 22, borderRadius: '50%', background: '#fff', transform: hostOn ? 'translateX(18px)' : 'none', transition: 'transform .2s', boxShadow: '0 1px 2px rgba(0,0,0,.2)' }} />
                </span>
              </button>
              {s.organizerModeError && <p role="alert" style={{ fontSize: 12.5, lineHeight: 1.5, color: 'var(--bb-alert)', margin: '8px 4px 0' }}>{s.organizerModeError}</p>}
            </div>
            {tabs.length > 0 && (
              <div role="tablist" data-testid="quick-tabs" style={{ display: 'flex', gap: 2, padding: 2, margin: '12px 20px 0', borderRadius: 999, background: 'var(--bb-surface2, var(--bb-block))' }}>
                {tabs.map(k => (
                  <button key={k} type="button" role="tab" aria-selected={tab === k} data-testid={`quick-tab-${k}`} onClick={() => setTabSel(k)}
                    style={{ flex: 1, minHeight: 38, border: 'none', borderRadius: 999, fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer',
                      background: tab === k ? 'var(--bb-fg)' : 'transparent', color: tab === k ? 'var(--bb-bg)' : 'var(--bb-fg-2)' }}>{tabLabel[k]}</button>
                ))}
              </div>
            )}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', margin: '16px 20px 0', borderTop: line, borderBottom: line }}>
              {shortcuts.map(([icon, label, fn, badge], i) => (
                <button key={`${icon}${i}`} type="button" onClick={go(fn)} data-testid={`quick-${icon}`} style={{ position: 'relative', padding: '16px 0 12px', border: 'none', background: 'none', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8, fontFamily: 'inherit', fontSize: 12, color: 'inherit', cursor: 'pointer' }}>
                  <RowIcon kind={icon} size={24} /><span style={{ opacity: 0.8 }}>{label}</span>
                  {badge > 0 && <span style={{ position: 'absolute', top: 8, right: 16, minWidth: 17, height: 17, padding: '0 4px', borderRadius: 999, background: 'var(--bb-alert)', color: 'var(--bb-on-alert)', fontSize: 10, fontWeight: 700, display: 'grid', placeItems: 'center' }}>{badge}</span>}
                </button>
              ))}
            </div>
          </>
        ) : (
          <div style={{ margin: '0 20px', padding: 20, borderRadius: 16, background: 'var(--bb-block)' }}>
            <h2 style={{ margin: 0, fontSize: 20, fontWeight: 400 }}>{T('Bạn đang xem với tư cách khách', "You're browsing as a guest")}</h2>
            <p style={{ margin: '6px 0 14px', fontSize: 14, opacity: 0.75 }}>{T('Đăng nhập để đặt chỗ, lưu sự kiện và nhắn tin cho host.', 'Log in to reserve, save and message hosts.')}</p>
            <button type="button" onClick={go(goLogin)} data-testid="quick-login" style={{ height: 46, width: '100%', border: 'none', borderRadius: 999, background: 'var(--bb-fg)', color: 'var(--bb-bg)', font: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer' }}>{T('Đăng nhập', 'Log in')}</button>
          </div>
        )}
        <div style={{ margin: '0 20px' }}>
          <div style={row}><RowIcon kind="sun" size={24} /><span style={{ flex: 1 }}>{T('Giao diện', 'Appearance')}</span>
            <span style={{ display: 'flex', background: 'var(--bb-block)', borderRadius: 999, padding: 2 }}>
              <button type="button" data-testid="quick-theme-light" onClick={() => pickTheme('light')} style={seg(!dark)}>{T('Sáng', 'Light')}</button>
              <button type="button" data-testid="quick-theme-dark" onClick={() => pickTheme('dark')} style={seg(dark)}>{T('Tối', 'Dark')}</button></span></div>
          <div style={row}><RowIcon kind="globe" size={24} /><span style={{ flex: 1 }}>{T('Ngôn ngữ', 'Language')}</span>
            <span style={{ display: 'flex', background: 'var(--bb-block)', borderRadius: 999, padding: 2 }}>
              <button type="button" data-testid="quick-lang-vi" onClick={() => en && toggleLang()} style={seg(!en)}>VI</button>
              <button type="button" data-testid="quick-lang-en" onClick={() => !en && toggleLang()} style={seg(en)}>EN</button></span></div>
          {user && (
            <button type="button" onClick={() => setView('prefs')} data-testid="quick-notifications" style={{ ...row, width: '100%', border: 'none', borderBottom: line, background: 'none', color: 'inherit', fontFamily: 'inherit', textAlign: 'left', cursor: 'pointer' }}>
              <RowIcon kind="bell" size={24} /><span style={{ flex: 1 }}>{T('Tùy chọn thông báo', 'Notification preferences')}</span>
              <span style={{ fontSize: 13, opacity: 0.6 }}>{notifPrefsSummary(s.mutedNotificationKinds, T)}</span>
              <span aria-hidden style={{ opacity: 0.5 }}>›</span>
            </button>
          )}
        </div>
        {user && (
          <button type="button" onClick={go(logout)} data-testid="quick-sign-out" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, margin: '22px 20px 0', width: 'calc(100% - 40px)', height: 48, border: '1.5px solid var(--bb-alert)', borderRadius: 999, background: 'none', color: 'var(--bb-alert)', fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer' }}>
            <RowIcon kind="logout" size={18} />{T('Đăng xuất', 'Sign out')}
          </button>
        )}
        </>)}
      </div>
    </NativeSheet>
  );
}

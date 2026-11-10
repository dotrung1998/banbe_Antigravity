// Notification preferences (v5 prototype `sub:notifs`): one switch per group of notification kinds, saved as the
// existing muted_notification_kinds list. "New messages" is always on. Rewards/News have no server kinds yet, so
// they persist as the placeholder kinds 'rewards' / 'news'.
import { useBanBe } from '../state/BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { KIND_CATEGORY } from './Notifications.jsx';
import { paper, ink, ink2, ink3, block, divider } from '../theme.js';

const kindsOf = (...cats) => Object.keys(KIND_CATEGORY).filter(k => cats.includes(KIND_CATEGORY[k]));
const GROUPS = [
  ['tickets', ['Vé', 'Tickets'], ['Xác nhận, giữ chỗ, check-in', 'Confirmations, holds, check-in'], kindsOf('booking', 'reminder')],
  ['payments', ['Thanh toán', 'Payments'], ['Nhắc hạn thanh toán, hoàn tiền', 'Pay-by reminders, refunds'], kindsOf('payment', 'refund', 'dispute')],
  ['events', ['Sự kiện', 'Events'], ['Thông báo, nhắc nhở, host bạn theo dõi', 'Announcements, reminders, hosts you follow'], kindsOf('event', 'team', 'message').filter(k => k !== 'new_message' && k !== 'weekly_digest')],
  ['rewards', ['Phần thưởng', 'Rewards'], ['Huy hiệu và chuỗi ngày', 'Badges and streaks'], ['rewards']],
  ['news', ['Tin từ banbe', 'News from banbe'], ['Tắt trừ khi bạn bật', 'Off unless you turn it on'], ['weekly_digest', 'news']],
];

export default function NotificationPrefs() {
  const { state: s, T, set } = useBanBe();
  const muted = s.mutedNotificationKinds || [];
  const isOn = (kinds) => !kinds.some(k => muted.includes(k));
  const toggle = async (kinds) => {
    const next = isOn(kinds) ? [...new Set([...muted, ...kinds])] : muted.filter(k => !kinds.includes(k));
    set({ mutedNotificationKinds: next });
    if (s.user?.id) await supabase.from('profiles').update({ muted_notification_kinds: next }).eq('id', s.user.id);
  };
  const sw = (on) => (
    <span aria-hidden style={{ flex: 'none', width: 46, height: 28, borderRadius: 14, position: 'relative', background: on ? 'var(--bb-moss, #5E7A5A)' : 'rgba(var(--bb-fg-rgb),0.18)', transition: 'background .2s' }}>
      <span style={{ position: 'absolute', top: 3, left: 3, width: 22, height: 22, borderRadius: '50%', background: '#fff', transform: on ? 'translateX(18px)' : 'none', transition: 'transform .2s', boxShadow: '0 1px 2px rgba(0,0,0,.2)' }} />
    </span>
  );
  const row = { display: 'flex', alignItems: 'center', gap: 12, width: '100%', padding: '14px 0', border: 'none', borderBottom: `1px solid ${divider}`, background: 'none', color: ink, font: 'inherit', textAlign: 'left' };
  const lbl = (title, sub) => <span style={{ flex: 1, fontSize: 15 }}>{title}<small style={{ display: 'block', fontSize: 12.5, color: ink3, marginTop: 2 }}>{sub}</small></span>;
  return (
    <div data-screen-label="NotificationPrefs" style={{ minHeight: '100%', background: paper, animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
      <div style={{ padding: '56px 20px 0' }}>
        <button type="button" data-testid="notif-prefs-back" onClick={() => set({ screen: 'profile' })} style={{ border: 'none', background: 'none', padding: '8px 0', color: ink, font: 'inherit', fontSize: 15, cursor: 'pointer' }}>‹ {T('Tài khoản', 'Account')}</button>
        <h1 style={{ margin: '8px 0 4px', fontSize: 30, fontWeight: 300, letterSpacing: '-.01em', color: ink }}>{T('Tùy chọn thông báo', 'Notification preferences')}</h1>
      </div>
      <div style={{ margin: '0 20px 40px' }} data-testid="notif-prefs-list">
        {GROUPS.map(([k, [vt, et], [vs, es], kinds]) => {
          const on = isOn(kinds);
          return (
            <button key={k} type="button" role="switch" aria-checked={on} data-testid={`notif-pref-${k}`} onClick={() => toggle(kinds)} style={{ ...row, cursor: 'pointer' }}>
              {lbl(T(vt, et), T(vs, es))}{sw(on)}
            </button>
          );
        })}
        <div style={{ ...row, opacity: 0.6 }}>
          {lbl(T('Tin nhắn mới', 'New messages'), T('Thông báo đẩy và chấm chưa đọc trong Tin nhắn. Không lặp lại trong Thông báo.', 'Push alert and an unread dot in Messages. Never repeated in Notifications.'))}{sw(true)}
        </div>
      </div>
    </div>
  );
}

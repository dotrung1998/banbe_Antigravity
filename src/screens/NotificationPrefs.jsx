// Notification preferences (v5 prototype `sub:notifs`): one switch per group of notification kinds, saved as the
// existing profiles.muted_notification_kinds list (lib/notificationPrefs.js). "News from banbe" is the weekly digest
// opt-in (promotional, off by default, only while the `weekly_digest` switch is on). "New messages" is always on.
// Opened from Account (Back -> Account) and from the Home quick panel (Back -> Home), via `notifPrefsBack`.
import { useEffect, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { flagOn } from '../lib/featureFlags.js';
import { NOTIF_PREF_GROUPS, groupOn, toggleGroup } from '../lib/notificationPrefs.js';
import { paper, ink, ink3, alert, divider } from '../theme.js';

export default function NotificationPrefs() {
  const { state: s, T, set, loadNotifications } = useBanBe();
  const muted = s.mutedNotificationKinds || [];
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const digestSwitch = flagOn(s.featureFlags, 'weekly_digest');
  const [digest, setDigest] = useState(null); // null = not loaded yet
  // Reload the feed AFTER the new muted list has rendered: loadNotifications filters with the list of its own render.
  const [reload, setReload] = useState(0);
  useEffect(() => { if (reload) loadNotifications(); }, [reload]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    setDigest(null);
    if (!digestSwitch || !s.user?.id) return undefined;
    let live = true;
    supabase.rpc('get_my_notification_preferences').then(({ data, error: e }) => {
      if (live) setDigest(!e && data?.success ? data.digest_opt_in === true : false);
    }, () => { if (live) setDigest(false); });
    return () => { live = false; };
  }, [digestSwitch, s.user?.id]);

  const failed = T('Không lưu được. Thử lại nhé.', "Couldn't save. Try again.");

  const toggle = async (group) => {
    if (!s.user?.id || saving) return;
    const prev = muted;
    const next = toggleGroup(prev, group);
    const muting = next.length > prev.length;
    setSaving(true); setError('');
    // Muting hides what is already in the feed (as the per-notification "mute this kind" does); unmuting reloads it.
    set(p => {
      if (!muting) return { mutedNotificationKinds: next };
      const remaining = p.notifications.filter(n => !next.includes(n.kind));
      return { mutedNotificationKinds: next, notifications: remaining, unreadNotifications: remaining.filter(n => !n.read_at).length };
    });
    const { error: e } = await supabase.from('profiles').update({ muted_notification_kinds: next }).eq('id', s.user.id)
      .then(r => r, () => ({ error: true }));
    setSaving(false);
    if (e) { set({ mutedNotificationKinds: prev }); setError(failed); }
    if (e ? muting : !muting) setReload(n => n + 1);
  };

  const toggleDigest = async () => {
    if (digest == null || saving) return;
    const want = !digest;
    setSaving(true); setError(''); setDigest(want);
    const { data, error: e } = await supabase.rpc('set_my_digest_opt_in', { p_enabled: want }).then(r => r, () => ({ data: null, error: true }));
    setSaving(false);
    if (e || !data?.success) { setDigest(!want); setError(failed); }
  };

  const back = s.notifPrefsBack === 'home' ? 'home' : 'profile';
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
        <button type="button" data-testid="notif-prefs-back" onClick={() => set({ screen: back, notifPrefsBack: null })} style={{ border: 'none', background: 'none', padding: '8px 0', color: ink, font: 'inherit', fontSize: 15, cursor: 'pointer' }}>‹ {back === 'home' ? T('Trang chủ', 'Home') : T('Tài khoản', 'Account')}</button>
        <h1 style={{ margin: '8px 0 4px', fontSize: 30, fontWeight: 300, letterSpacing: '-.01em', color: ink }}>{T('Tùy chọn thông báo', 'Notification preferences')}</h1>
      </div>
      <div style={{ margin: '0 20px 40px' }} data-testid="notif-prefs-list">
        {NOTIF_PREF_GROUPS.map(g => {
          const on = groupOn(muted, g);
          return (
            <button key={g.key} type="button" role="switch" aria-checked={on} aria-disabled={saving} data-testid={`notif-pref-${g.key}`} onClick={() => toggle(g)} style={{ ...row, cursor: 'pointer' }}>
              {lbl(T(...g.title), T(...g.sub))}{sw(on)}
            </button>
          );
        })}
        {digestSwitch && (
          <button type="button" role="switch" aria-checked={!!digest} aria-disabled={digest == null || saving} data-testid="notif-pref-news" onClick={toggleDigest}
            style={{ ...row, cursor: digest == null ? 'default' : 'pointer', opacity: digest == null ? 0.6 : 1 }}>
            {lbl(T('Tin từ banbe', 'News from banbe'), T('Bản tin cuối tuần, tối thứ Năm. Tắt trừ khi bạn bật.', "This weekend's events, Thursday evening. Off unless you turn it on."))}{sw(!!digest)}
          </button>
        )}
        <div style={{ ...row, opacity: 0.6 }}>
          {lbl(T('Tin nhắn mới', 'New messages'), T('Thông báo đẩy và chấm chưa đọc trong Tin nhắn. Không lặp lại trong Thông báo.', 'Push alert and an unread dot in Messages. Never repeated in Notifications.'))}{sw(true)}
        </div>
        <p style={{ fontSize: 12.5, lineHeight: 1.5, color: ink3, margin: '12px 0 0' }}>
          {T('Thông báo về tranh chấp luôn được gửi.', 'Dispute updates always reach you.')}
        </p>
        {error && <p role="alert" style={{ fontSize: 12.5, color: alert, margin: '8px 0 0' }}>{error}</p>}
      </div>
    </div>
  );
}

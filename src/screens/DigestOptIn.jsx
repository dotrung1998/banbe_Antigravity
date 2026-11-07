import { useEffect, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { flagOn } from '../lib/featureFlags.js';
import { paper, ink, alert, display, fieldGlass } from '../theme.js';

// L5 weekly digest opt-in (switch `weekly_digest`, migration 200), in Account › Settings › Notifications.
// PROMOTIONAL, so it is off until the person turns it on here, says so in one line, and turning it off always works
// (set_my_digest_opt_in refuses only turning it ON while the switch is off). Every change is logged server-side.
// The whole section is hidden while the switch is off. The web has no push, so the promotional-push toggle is
// iPhone only (NotificationPrefsSection in AccountGroupView.swift).
export default function DigestOptIn() {
  const { state: s, T } = useBanBe();
  const enabled = flagOn(s.featureFlags, 'weekly_digest');
  const [on, setOn] = useState(null); // null = not loaded yet
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    setOn(null); setError('');
    if (!enabled || !s.user?.id) return undefined;
    let live = true;
    supabase.rpc('get_my_notification_preferences').then(({ data, error: e }) => {
      if (live) setOn(!e && data?.success ? data.digest_opt_in === true : false);
    }, () => { if (live) setOn(false); });
    return () => { live = false; };
  }, [enabled, s.user?.id]);

  if (!enabled || !s.user?.id) return null;

  const toggle = async () => {
    if (on == null || busy) return;
    const next = !on;
    setBusy(true); setError(''); setOn(next);
    const { data, error: e } = await supabase.rpc('set_my_digest_opt_in', { p_enabled: next }).then(r => r, () => ({ data: null, error: true }));
    setBusy(false);
    if (e || !data?.success) {
      setOn(!next);
      setError(data?.error === 'NOT_AVAILABLE'
        ? T('Bản tin cuối tuần đang tạm tắt.', 'The weekly digest is turned off for now.')
        : T('Không lưu được. Thử lại nhé.', "Couldn't save. Try again."));
    }
  };

  return (
    <div style={{ marginTop: 24 }} data-testid="account-notifications-section">
      <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Thông báo', 'Notifications')}</span>
      <div onClick={toggle} role="switch" aria-checked={!!on} aria-disabled={on == null || busy} data-testid="account-digest-toggle"
        style={{ ...fieldGlass({ marginTop: 8, padding: '14px 16px' }), display: 'flex', alignItems: 'center', gap: 12, cursor: on == null || busy ? 'default' : 'pointer' }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={display(15, { lineHeight: 1.3 })}>{T('Bản tin cuối tuần: sự kiện cuối tuần, tối thứ Năm', "Weekly digest: this weekend's events, Thursday evening")}</div>
          <div style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, opacity: 0.75, marginTop: 3 }}>{T('Tin quảng bá. Mặc định tắt. Tắt bất cứ lúc nào.', 'Promotional. Off by default. Turn off anytime.')}</div>
        </div>
        <span aria-hidden style={{ flex: 'none', width: 44, height: 26, borderRadius: 13, background: on ? ink : 'rgba(27,25,22,0.18)', position: 'relative', transition: 'background .15s', opacity: on == null ? 0.5 : 1 }}>
          <span style={{ position: 'absolute', top: 3, left: on ? 21 : 3, width: 20, height: 20, borderRadius: 10, background: paper, transition: 'left .15s' }} />
        </span>
      </div>
      {error && <p role="alert" style={{ fontSize: 12.5, color: alert, margin: '8px 2px 0' }}>{error}</p>}
    </div>
  );
}

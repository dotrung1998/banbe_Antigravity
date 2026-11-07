import { useEffect, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { rowTimeZone } from '../lib/eventMarket.js';
import { whenLabel } from '../lib/quickWins.js';
import { flagOn } from '../lib/featureFlags.js';
import { hostFeedbackView, hostRecapStats, HOST_FEEDBACK_HIDDEN } from '../lib/coreLoops.js';
import { paper, ink, rule, alert, display, fieldGlass, inkButton } from '../theme.js';

// L3 host recap (switch `host_recap`, migration 199): from the host_event_recap notification or Dashboard › Past
// events. Plain numbers from get_host_event_recap (owner/team only on the server): confirmed seats of capacity,
// check-ins, new followers since submission, returning guests, photos, and the guests' feedback only once 3 or more
// answered (counts and notes without names). "Run it again" opens Create Event pre-filled and never submits.
// iOS twin: HostRecapView.swift.
const ERRORS = {
  NOT_AUTHORIZED: ['Chỉ host của sự kiện này xem được tổng kết.', 'Only this event’s host can see its recap.'],
  NOT_AVAILABLE: ['Tính năng này đang tạm tắt.', 'This is turned off for now.'],
  NETWORK: ['Không tải được tổng kết. Thử lại nhé.', "Couldn't load the recap. Try again."],
};

export default function HostRecap() {
  const { state: s, T, backFromHostRecap, runItAgain, goEvent } = useBanBe();
  const id = s.hostRecapId;
  const ev = id ? s.realEventsById[id] : null;
  const enabled = flagOn(s.featureFlags, 'host_recap');
  const [recap, setRecap] = useState(null);
  const [error, setError] = useState('');
  const [nonce, setNonce] = useState(0);

  useEffect(() => {
    setRecap(null); setError('');
    if (!id || !enabled) return undefined;
    let live = true;
    supabase.rpc('get_host_event_recap', { p_event_id: id }).then(({ data, error: e }) => {
      if (!live) return;
      if (!e && data?.success) setRecap(data);
      else setError(data?.error && ERRORS[data.error] ? data.error : 'NETWORK');
    }, () => { if (live) setError('NETWORK'); });
    return () => { live = false; };
  }, [id, enabled, nonce]);

  const stats = recap ? hostRecapStats(recap) : null;
  const fb = recap ? hostFeedbackView(recap.feedback) : null;
  const when = ev?.startsAt ? whenLabel(ev.startsAt, ev.tz || rowTimeZone(ev), s.lang === 'en') : '';
  const msg = error ? ERRORS[error] || ERRORS.NETWORK : null;
  const statRow = (label, value, testId, i) => (
    <div key={testId} data-testid={testId} style={{ display: 'flex', justifyContent: 'space-between', gap: 12, padding: '12px 14px', fontSize: 14, borderTop: i ? `1px solid ${rule}` : 'none' }}>
      <span>{label}</span><span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{value}</span>
    </div>
  );

  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Host recap">
      <div onClick={backFromHostRecap} role="button" data-testid="host-recap-back" style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>
        ‹ {s.hostRecapBack === 'notifications' ? T('Thông báo', 'Notifications') : T('Trang tổ chức', 'Dashboard')}
      </div>
      <div style={{ padding: '14px 22px 48px' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.7 }}>{T('Tổng kết sự kiện', 'Event recap')}</span>
        <h1 onClick={id ? () => goEvent(id) : undefined} role="link" data-testid="host-recap-title" style={{ ...display(26, { margin: '6px 0 0', cursor: 'pointer' }) }}>{ev?.name || '…'}</h1>
        {when && <p style={{ fontSize: 13, color: ink, opacity: 0.7, margin: '6px 0 0' }}>{when}</p>}

        {!enabled && <p style={{ fontSize: 13.5, color: ink, opacity: 0.7, marginTop: 18 }} data-testid="host-recap-off">{T(...ERRORS.NOT_AVAILABLE)}</p>}
        {enabled && !recap && !msg && <p style={{ fontSize: 13, color: ink, opacity: 0.7, marginTop: 18 }}>{T('Đang tải…', 'Loading…')}</p>}
        {msg && (
          <p role="alert" data-testid="host-recap-error" style={{ fontSize: 12.5, color: alert, margin: '18px 0 0' }}>
            {T(msg[0], msg[1])}{error === 'NETWORK' && (
              <button type="button" onClick={() => setNonce(n => n + 1)} style={{ marginLeft: 8, background: 'none', border: 'none', padding: 0, fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600, color: ink, textDecoration: 'underline', cursor: 'pointer' }}>{T('Thử lại', 'Retry')}</button>
            )}
          </p>
        )}

        {stats && (
          <>
            <div data-testid="host-recap-stats" style={{ ...fieldGlass({ marginTop: 20, display: 'flex', flexDirection: 'column' }) }}>
              {[
                [T('Chỗ đã xác nhận', 'Confirmed seats'), stats.capacity != null ? T(`${stats.confirmedSeats}/${stats.capacity}`, `${stats.confirmedSeats} of ${stats.capacity}`) : String(stats.confirmedSeats), 'host-recap-seats'],
                [T('Đã check-in', 'Checked in'), String(stats.checkedIn), 'host-recap-checked-in'],
                [T('Người theo dõi mới', 'New followers'), String(stats.newFollowers), 'host-recap-followers'],
                [T('Khách quay lại', 'Returning guests'), String(stats.repeatGuests), 'host-recap-repeat'],
                [T('Ảnh', 'Photos'), String(stats.photos), 'host-recap-photos'],
              ].map(([label, value, testId], i) => statRow(label, value, testId, i))}
            </div>

            <section data-testid="host-recap-feedback" style={{ marginTop: 26 }}>
              <span style={display(20, { lineHeight: 1.25 })}>{T('Cảm nhận của khách', 'Guest feedback')}</span>
              {fb.hidden ? (
                <p style={{ fontSize: 13, lineHeight: 1.5, color: ink, opacity: 0.75, margin: '8px 0 0' }} data-testid="host-recap-feedback-hidden">
                  {T(HOST_FEEDBACK_HIDDEN.vi, HOST_FEEDBACK_HIDDEN.en)}
                </p>
              ) : (
                <>
                  <p style={{ fontSize: 15, fontWeight: 600, color: ink, margin: '8px 0 0' }} data-testid="host-recap-feedback-counts">👍 {fb.up} · 👎 {fb.down}</p>
                  {fb.notes.length > 0 && (
                    <div style={{ ...fieldGlass({ marginTop: 10, display: 'flex', flexDirection: 'column' }) }}>
                      {fb.notes.map((n, i) => (
                        <p key={i} data-testid={`host-recap-note-${i}`} style={{ margin: 0, padding: '11px 14px', fontSize: 13.5, lineHeight: 1.5, color: ink, whiteSpace: 'pre-wrap', borderTop: i ? `1px solid ${rule}` : 'none' }}>{n}</p>
                      ))}
                    </div>
                  )}
                  <p style={{ fontSize: 11.5, color: ink, opacity: 0.6, margin: '8px 0 0' }}>{T('Ghi chú không kèm tên, thứ tự ngẫu nhiên.', 'Notes are unnamed and in random order.')}</p>
                </>
              )}
            </section>
          </>
        )}

        {enabled && ev && (
          <>
            <button type="button" onClick={() => runItAgain(id)} data-testid="host-recap-run-again"
              style={{ ...inkButton({ width: '100%', marginTop: 28, padding: '14px 12px', border: 'none', fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer' }) }}>
              {T('Tổ chức lại', 'Run it again')}
            </button>
            <p style={{ fontSize: 12, lineHeight: 1.5, color: ink, opacity: 0.65, margin: '8px 2px 0', textAlign: 'center' }}>
              {T('Mở bản nháp mới từ sự kiện này. Bạn xem lại và gửi khi sẵn sàng.', 'Opens a new draft from this event. You review it and submit when ready.')}
            </p>
          </>
        )}
      </div>
    </div>
  );
}

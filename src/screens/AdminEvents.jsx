import { useEffect, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { formatVnd } from '../lib/paymentDocument.js';
import { paper, ink, rule, display, fieldGlass, cardGlass, alert } from '../theme.js';

// Event submission -> admin review -> publish. A SEPARATE desk from
// Disputes.jsx (payment verification) — reviewing a new event submission
// is not the same job as ruling on a payment dispute, even though both are
// gated the same way server-side (is_platform_admin(), migrations 026/085).
export default function AdminEvents() {
  const { state, T, loadPendingEvents, reviewEvent, backFromDocuments } = useGoc();
  const s = state;
  const [reasonByEvent, setReasonByEvent] = useState({});

  useEffect(() => { loadPendingEvents(); }, [loadPendingEvents]);

  const setReason = (key, value) => setReasonByEvent(prev => ({ ...prev, [key]: value }));

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Admin events">
      <div onClick={backFromDocuments} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="admin-events-back">
        ‹ {T('Tài khoản', 'Account')}
      </div>
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{ ...display(24, { margin: 0 }) }} data-testid="admin-events-title">{T('Sự kiện chờ duyệt', 'Pending events')}</h1>
        <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
          {T('Sự kiện chỉ hiển thị công khai sau khi được duyệt ở đây.', 'An event only shows publicly once approved here.')}
        </p>
      </div>

      {s.adminEventError && (
        <p style={{ fontSize: 11.5, color: alert, margin: '10px 22px 0' }} data-testid="admin-events-error">{s.adminEventError}</p>
      )}

      <div style={{ margin: '18px 22px 40px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        {s.adminEvents.map(e => {
          const reason = reasonByEvent[e.key] || '';
          const busy = s.adminEventBusy === e.key;
          return (
            <div key={e.key} style={{ ...cardGlass({ padding: '16px 18px', display: 'flex', flexDirection: 'column', gap: 10 }) }} data-testid="admin-event-row">
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'flex-start' }}>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
                  <span style={{ ...display(16) }} data-testid="admin-event-name">{e.name}</span>
                  <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>{e.organizerName || T('Không rõ người tổ chức', 'Unknown host')}</span>
                </div>
                <span style={{ ...display(19, { whiteSpace: 'nowrap' }) }}>{e.priceVnd ? formatVnd(e.priceVnd) : T('Miễn phí', 'Free')}</span>
              </div>

              {e.photoUrl ? (
                <img src={e.photoUrl} alt={e.name} style={{ width: '100%', maxHeight: 220, objectFit: 'cover', borderRadius: 10 }} />
              ) : (
                <div style={{ ...fieldGlass({ padding: '30px 12px', textAlign: 'center' }) }}>
                  <span style={{ fontSize: 11.5, color: ink, opacity: 0.55 }}>{T('Chưa có ảnh', 'No photo yet')}</span>
                </div>
              )}

              <div style={{ ...fieldGlass({ padding: '10px 12px', display: 'flex', flexDirection: 'column', gap: 4 }) }}>
                <Line label={T('Ngày', 'Date')} value={e.eventDate ? `${e.eventDate}${e.eventTime ? ' ▪︎ ' + e.eventTime.slice(0, 5) : ''}` : T('Chưa đặt', 'Not set')} />
                <Line label={T('Địa điểm', 'Location')} value={e.area || '—'} />
                <Line label={T('Sức chứa', 'Capacity')} value={e.capacity != null ? String(e.capacity) : '—'} />
                <Line label={T('Mô tả', 'Description')} value={e.description || '—'} />
              </div>

              <input
                value={reason}
                onChange={(ev) => setReason(e.key, ev.target.value)}
                placeholder={T('Lý do từ chối (bắt buộc nếu từ chối)', 'Rejection reason (required if rejecting)')}
                data-testid="admin-event-reason"
                style={{ ...fieldGlass({ padding: '11px 12px', border: 'none' }), fontSize: 13, color: ink, outline: 'none', fontFamily: 'inherit' }}
              />
              <div style={{ display: 'flex', gap: 8 }}>
                <Action
                  label={busy ? T('Đang lưu…', 'Saving…') : T('Duyệt ▪︎ đăng công khai', 'Approve ▪︎ publish')}
                  testid="admin-event-approve"
                  onClick={() => reviewEvent(e.key, true, '')}
                />
                <Action
                  label={T('Từ chối', 'Reject')}
                  ghost testid="admin-event-reject"
                  onClick={() => { if (reason.trim()) reviewEvent(e.key, false, reason); }}
                />
              </div>
            </div>
          );
        })}

        {s.adminEvents.length === 0 && (
          <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: 0 }} data-testid="admin-events-empty">
            {s.adminEventsLoading ? T('Đang tải…', 'Loading…') : T('Không có sự kiện nào đang chờ duyệt.', 'No pending events.')}
          </p>
        )}
      </div>
    </div>
  );
}

function Line({ label, value }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10 }}>
      <span style={{ fontSize: 11, color: ink, opacity: 0.65 }}>{label}</span>
      <span style={{ fontSize: 12, fontWeight: 600, color: ink, wordBreak: 'break-word', textAlign: 'right', maxWidth: '70%' }}>{value}</span>
    </div>
  );
}

function Action({ label, onClick, ghost, testid }) {
  return (
    <div onClick={onClick} data-testid={testid}
         style={{
           flex: 1, textAlign: 'center', fontSize: 12.5, fontWeight: 600, padding: '11px 10px',
           borderRadius: 12, cursor: 'pointer', lineHeight: 1.3,
           background: ghost ? 'transparent' : ink, color: ghost ? ink : paper,
           border: ghost ? `1px solid ${rule}` : 'none',
         }}>
      {label}
    </div>
  );
}

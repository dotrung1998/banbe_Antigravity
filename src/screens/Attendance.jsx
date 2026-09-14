import { useGoc } from '../state/GocContext.jsx';
import { findEvent } from '../data/events.js';
import { formatVnd } from '../lib/paymentDocument.js';
import { paper, ink, rule, display, fieldGlass, alert } from '../theme.js';

export default function Attendance() {
  const { state, T, trStatus, goDashboard, toggleCheckin, openQrScan, openCancelBooking, markGuestPaid } = useGoc();
  const s = state;

  const attKey = s.attendanceEventKey;
  const attEv = attKey ? findEvent(attKey) : null;

  if (!attEv) {
    return (
      <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Attendance">
        <div onClick={goDashboard} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Trang của bạn', 'Your dashboard')}</div>
      </div>
    );
  }

  // The guest list is whoever actually holds a real booking for this event
  // (GocContext's loadAttendanceGuests), not a generated placeholder list.
  const guests = s.attendanceGuests;
  const checkedCount = guests.filter(g => g.checkedIn).length;

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Attendance">
      <div onClick={goDashboard} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Trang của bạn', 'Your dashboard')}</div>
      <div style={{ padding: '14px 22px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
        <div style={{ minWidth: 0 }}>
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Điểm danh khách', 'Guest check-in')}</span>
          <h1 style={{ ...display(24, { margin: '8px 0 0' }) }}>{attEv.name}</h1>
          <div style={{ fontSize: 12.5, color: ink, marginTop: 4 }}>{trStatus(attEv.when)}</div>
        </div>
        <div onClick={openQrScan} style={{ flex: 'none', fontSize: 12, fontWeight: 600, color: paper, background: ink, borderRadius: 12, padding: '9px 14px', cursor: 'pointer', whiteSpace: 'nowrap' }}>{T('Quét QR', 'Scan QR')}</div>
      </div>
      <div style={{ margin: '18px 22px 0', background: ink, padding: '16px 18px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ fontSize: 12.5, color: paper }}>{T('Đã đến', 'Checked in')}</span>
        <span style={{ fontFamily: "'Be Vietnam Pro', sans-serif", fontWeight: 600, letterSpacing: '-0.02em', fontSize: 24, color: paper }}>{checkedCount} / {guests.length}</span>
      </div>
      <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, margin: '10px 22px 0' }}>{T('Chạm vào tên khách hoặc quét mã QR vé khi họ tới nơi.', "Tap a guest's name, or scan their ticket QR, when they arrive.")}</p>
      <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, opacity: 0.7, margin: '6px 22px 0' }}>{T('Đánh dấu "Đã thanh toán" khi bạn thấy tiền vào tài khoản — biên nhận sẽ tự phát hành cho khách.', 'Mark a guest paid once you see the money arrive — their receipt is issued automatically.')}</p>
      <div style={{ ...fieldGlass({ margin: '14px 22px 40px', display: 'flex', flexDirection: 'column' }) }}>
        {guests.map(g => {
          const meta = g.qty > 1 ? (g.qty + T(' vé', ' tickets')) : T('1 vé', '1 ticket');
          return (
            <div key={g.id} onClick={() => toggleCheckin(g.id, g.checkedIn)} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '13px 16px', borderBottom: `1px solid ${rule}`, cursor: 'pointer', background: g.checkedIn ? 'rgba(27,25,22,0.16)' : 'transparent' }}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                <span style={{ ...display(15) }}>{g.name}</span>
                <span style={{ fontSize: 11.5, color: ink }}>{meta} ▪︎ {formatVnd(g.totalVnd)}</span>
                {g.paid ? (
                  <span style={{ fontSize: 11, color: ink, opacity: 0.7 }} data-testid="guest-paid">
                    {T('Đã thanh toán ✓', 'Paid ✓')}
                  </span>
                ) : (
                  <span
                    onClick={(e) => { e.stopPropagation(); markGuestPaid(g.id); }}
                    style={{ fontSize: 11, fontWeight: 600, color: ink, width: 'fit-content', cursor: 'pointer', border: '1px solid rgba(27,25,22,0.16)', borderRadius: 10, padding: '4px 8px', marginTop: 2 }}
                    data-testid="guest-mark-paid"
                  >
                    {/* The screenshot the guest already sent is the strongest
                        signal there is that this is the right guest to tap. */}
                    {g.hasProof
                      ? T('Khách đã gửi biên lai ▪︎ Đánh dấu đã thanh toán', 'Guest sent proof ▪︎ Mark paid')
                      : T('Đánh dấu đã thanh toán', 'Mark as paid')}
                  </span>
                )}
                <span
                  onClick={(e) => { e.stopPropagation(); openCancelBooking(g.id); }}
                  style={{ fontSize: 11, color: alert, opacity: 0.8, width: 'fit-content', cursor: 'pointer', marginTop: 2 }}
                >
                  {T('Huỷ vé', 'Cancel booking')}
                </span>
              </div>
              <span style={{ fontSize: 11.5, fontWeight: 600, flex: 'none', padding: '5px 10px', color: g.checkedIn ? paper : ink, background: g.checkedIn ? ink : 'rgba(27,25,22,0.16)' }}>
                {g.checkedIn ? T('Đã đến ✓', 'Here ✓') : T('Chưa đến', 'Not yet')}
              </span>
            </div>
          );
        })}
        {guests.length === 0 && (
          <p style={{ fontSize: 12.5, color: ink, padding: '14px 16px', margin: 0 }}>{s.attendanceLoading ? T('Đang tải danh sách khách…', 'Loading guest list…') : T('Chưa có ai đặt chỗ cho sự kiện này.', 'No one has booked this event yet.')}</p>
        )}
      </div>
    </div>
  );
}

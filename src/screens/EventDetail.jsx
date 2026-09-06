import { useGoc } from '../state/GocContext.jsx';
import { bg } from '../data/events.js';
import { paper, ink, rule, display, photoPill, inkButton } from '../theme.js';

export default function EventDetail() {
  const { state, T, trStatus, stripKm, curEvent: ev, goHome, goOrganizer, goReserve, goChat, shareEvent } = useGoc();
  const s = state;

  const evCat = trStatus(ev.cat);
  const evWhere = trStatus(stripKm(ev.where));
  const evSeatsLong = trStatus(ev.soldOut ? 'Hết chỗ' : ev.seatsLong);
  const evOrgStats = T('Tổ chức từ ' + ev.orgSince + ' ▪︎ ' + ev.orgCount + ' sự kiện', 'Hosting since ' + ev.orgSince + ' ▪︎ ' + ev.orgCount + ' events');
  const showRefund = !ev.cancelled && ev.endedHoursAgo == null && !/Miễn phí|Free/.test(ev.price);
  const refundNote = T('Nếu sự kiện bị hủy, bạn được hoàn tiền tự động 100%.', 'If the event is cancelled, you are automatically refunded in full.');

  const reserveBarLabel = ev.soldOut
    ? T('Hết chỗ ▪︎ nhắn để vào danh sách chờ', 'Sold out ▪︎ message for waitlist')
    : (T('Giữ chỗ ▪︎ ', 'Reserve ▪︎ ') + trStatus(ev.price));
  const reserveBarTap = ev.soldOut ? goChat : goReserve;
  const reserveBarStyle = ev.soldOut
    ? { flex: 'none', margin: '0 20px 22px', fontSize: 15, fontWeight: 600, textAlign: 'center', padding: '15px 0', borderRadius: 18, cursor: 'pointer', background: 'rgba(238,232,218,0.92)', color: ink }
    : { ...inkButton({ flex: 'none', margin: '0 20px 22px', padding: '15px 0' }) };

  return (
    <div style={{ animation: 'gocFade 0.32s ease both', height: '100%', display: 'flex', flexDirection: 'column', background: paper }} data-screen-label="Event">
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>
      <div style={{ position: 'relative', height: 400 }}>
        <div style={bg(ev.img, { width: '100%', height: '100%', borderRadius: 0 })} />
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 78, pointerEvents: 'none', background: `linear-gradient(to bottom, rgba(247,244,236,0) 0%, rgba(247,244,236,0.3) 62%, ${paper} 100%)` }} />
        <div onClick={goHome} style={photoPill({ top: 66, left: 16, padding: '8px 13px' })}>‹ banbe</div>
        <div onClick={() => shareEvent(ev)} style={photoPill({ top: 66, right: 16, padding: '8px 13px' })}>
          {s.shared ? T('Đã sao chép link', 'Link copied') : T('Chia sẻ', 'Share')}
        </div>
      </div>
      <div style={{ padding: '22px 22px 30px', display: 'flex', flexDirection: 'column' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ fontSize: 11.5, color: ink }}>{evCat}</span>
          {ev.inviteOnly && (
            <span style={{ fontSize: 10, fontWeight: 600, letterSpacing: '0.04em', color: paper, background: ink, padding: '3px 8px' }}>{T('Riêng tư ▪︎ theo lời mời', 'Private ▪︎ invite only')}</span>
          )}
        </div>
        <h1 style={{ ...display(29, { lineHeight: 1.2, margin: '8px 0 10px' }) }}>{ev.name}</h1>
        <div style={{ fontSize: 13, color: ink }}>{evWhere}</div>
        <div style={{ fontSize: 13, color: ink, marginTop: 5 }}>{evSeatsLong}</div>
        {ev.inviteOnly && (
          <div style={{ fontSize: 12.5, color: ink, marginTop: 6 }}>{T('Bạn có thể mời thêm 1 người.', 'You can bring one +1.')}</div>
        )}
        <p style={{ fontSize: 14, lineHeight: 1.55, color: ink, margin: '20px 0 0' }}>{ev.desc}</p>
        <div style={{ marginTop: 22, borderTop: `1px solid ${rule}` }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', gap: 18, padding: '12px 0', borderBottom: `1px solid ${rule}`, fontSize: 13 }}>
            <span style={{ color: ink, flex: 'none' }}>{T('Bao gồm', 'Included')}</span>
            <span style={{ color: ink, textAlign: 'right' }}>{ev.included}</span>
          </div>
          <div onClick={goOrganizer} style={{ display: 'flex', justifyContent: 'space-between', padding: '12px 0', borderBottom: `1px solid ${rule}`, fontSize: 13, cursor: 'pointer' }}>
            <span style={{ color: ink }}>{T('Người tổ chức', 'Organizer')}</span>
            <span style={{ color: ink }}>{T('Ghé', 'Visit')} {ev.orgName} ›</span>
          </div>
          {ev.orgTrusted && (
            <div style={{ display: 'flex', justifyContent: 'space-between', padding: '12px 0', borderBottom: `1px solid ${rule}`, fontSize: 12 }}>
              <span style={{ color: ink }}>{T('Uy tín', 'Track record')}</span>
              <span style={{ color: ink }}>{evOrgStats}</span>
            </div>
          )}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', padding: '16px 0 0' }}>
            <span style={{ fontSize: 13, color: ink }}>{T('Giá', 'Price')}</span>
            <span style={{ ...display(23) }}>{trStatus(ev.price)}</span>
          </div>
        </div>
        {showRefund && <p style={{ margin: '14px 0 0', fontSize: 11.5, lineHeight: 1.5, color: ink, textAlign: 'center' }}>{refundNote}</p>}
        <div style={{ marginTop: 28 }}>
          <span style={{ fontSize: 11.5, color: ink }}>{T('Hình ảnh', 'Photos')}</span>
          <div style={{ display: 'flex', gap: 8, overflowX: 'auto', marginTop: 12, paddingBottom: 4 }}>
            {ev.gallery.map((u, i) => (
              <div key={i} style={bg(u, { flex: 'none', width: 148, height: 186 })} />
            ))}
          </div>
        </div>
      </div>
      </div>
      <div onClick={reserveBarTap} style={reserveBarStyle}>{reserveBarLabel}</div>
    </div>
  );
}

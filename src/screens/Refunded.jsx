import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, display, fieldGlass } from '../theme.js';

export default function Refunded() {
  const { state, T, curEvent: ev, goHome, goChat } = useGoc();
  const s = state;

  const priceNum = parseInt((ev.price.match(/[\d.]+/) || ['0'])[0].replace(/\./g, ''), 10) || 0;
  const isFree = /Miễn phí/.test(ev.price);
  const refundAmount = isFree ? T('Miễn phí', 'Free') : ((priceNum * (s.tickets[ev.key] || 1)).toLocaleString('vi-VN') + '₫');
  const refundCancelledWhen = ev.cancelledHoursAgo != null ? ev.agoLabel(ev.cancelledHoursAgo) + T(' ▪︎ người tổ chức đã hủy', ' ▪︎ cancelled by the organizer') : '';

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper, display: 'flex', flexDirection: 'column' }} data-screen-label="Refunded">
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: '60px 30px 0' }}>
        <span style={{ fontSize: 11.5, color: ink }}>{T('Sự kiện đã hủy', 'Event cancelled')}</span>
        <h2 style={{ ...display(27, { lineHeight: 1.35, margin: '12px 0 0' }) }}>{T('Đừng lo, tiền của bạn đã về túi rồi!', "No worries, you're already refunded!")}</h2>
        <p style={{ fontSize: 13.5, lineHeight: 1.55, color: ink, margin: '18px 0 0' }}>
          {T('Người tổ chức đã hủy sự kiện này. Tiền đã tự động hoàn về phương thức thanh toán ban đầu, bạn không cần làm gì thêm. Buổi sau nhé!', "The organizer cancelled this one. Your payment was automatically refunded, nothing else to do. See you at the next one!")}
        </p>
        <div style={{ ...fieldGlass({ marginTop: 24, padding: '16px 18px', display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 16 }) }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Số tiền hoàn', 'Amount refunded')}</span>
            <span style={{ fontSize: 11.5, lineHeight: 1.45, color: ink }}>{T('Về phương thức thanh toán ban đầu, 3–5 ngày làm việc', 'To your original payment method, 3–5 business days')}</span>
          </div>
          <span style={{ ...display(24, { whiteSpace: 'nowrap', flex: 'none' }) }}>{refundAmount}</span>
        </div>
        <div style={{ marginTop: 28, borderTop: `1px solid ${rule}`, paddingTop: 14, display: 'flex', flexDirection: 'column', gap: 6 }}>
          <span style={{ ...display(17) }}>{ev.name}</span>
          <span style={{ fontSize: 12, color: ink }}>{ev.where}</span>
          <span style={{ fontSize: 11.5, color: ink }}>{refundCancelledWhen}</span>
        </div>
      </div>
      <div onClick={goChat} style={{ borderTop: `1px solid ${rule}`, color: ink, fontSize: 13.5, textAlign: 'center', padding: '17px 0', cursor: 'pointer' }}>{T('Có câu hỏi? Nhắn cho ', 'Questions? Message ') + ev.hostShort}</div>
      <div onClick={goHome} style={{ borderTop: `1px solid ${rule}`, color: ink, fontSize: 13.5, textAlign: 'center', padding: '17px 0 34px', cursor: 'pointer' }}>{T('Về trang chính', 'Back to home')}</div>
    </div>
  );
}

import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, display, fieldGlass, inkButton, barGlass } from '../theme.js';

export default function HostIntro() {
  const { state, T, goProfile, goCreate } = useGoc();
  const s = state;

  const hostIntroName = (s.orgRegName || '').trim() || 'Bếp Nhỏ';
  const hostIntroIg = (s.orgRegIg || '').trim() || '@bepnho.saigon';
  const hostIntroDesc = (s.orgRegDesc || '').trim() || T('Mình nấu cho người lạ từ 2021…', 'I cook for strangers since 2021…');

  const points = [
    { title: T('Nhận thanh toán', 'Take payments'), note: T('MoMo ▪︎ VNPay ▪︎ chuyển khoản', 'MoMo ▪︎ VNPay ▪︎ bank transfer') },
    { title: T('Danh sách khách', 'Guest list'), note: T('Điểm danh ngay tại cửa', 'Check in at the door') },
    { title: T('Tin nhắn', 'Messages'), note: T('Khách nhắn trực tiếp cho bạn', 'Guests message you directly') },
    { title: T('Chi phí', 'Cost'), note: T('Không phí đăng, không phí giao dịch', 'No listing fee, no transaction fee') },
  ];

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', height: '100%', background: paper, position: 'relative' }} data-screen-label="Host intro">
      <div onClick={goProfile} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Tài khoản', 'Account')}</div>
      <div style={{ padding: '16px 22px 130px' }}>
        <span style={{ fontSize: 11.5, color: ink }}>{T('Dành cho người tổ chức', 'For organizers')}</span>
        <h1 style={{ ...display(27, { lineHeight: 1.2, margin: '8px 0 0' }) }}>{T('Trang tổ chức của bạn, trước khi bạn đăng gì', 'Your organizer page, before you post anything')}</h1>
        <p style={{ fontSize: 13.5, lineHeight: 1.55, color: ink, margin: '10px 0 0' }}>{T('Đây là trang khách sẽ thấy khi họ bấm vào tên bạn. Sự kiện, ảnh và số liệu sẽ tự điền vào sau mỗi lần bạn tổ chức.', 'This is what guests see when they tap your name. Events, photos and numbers fill in as you host.')}</p>

        <div style={{ ...fieldGlass({ marginTop: 22, padding: '18px 18px 20px' }) }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <span style={{ fontSize: 10.5, color: ink }}>{T('Khách sẽ thấy', 'Guests will see')}</span>
            <span style={{ fontSize: 10.5, color: ink }}>banbe</span>
          </div>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 9, marginTop: 12 }}>
            <span style={{ ...display(24, { lineHeight: 1.2 }) }}>{hostIntroName}</span>
            <span style={{ fontSize: 11, color: ink, background: 'rgba(27,25,22,0.10)', borderRadius: 999, padding: '3px 10px', flex: 'none' }}>{T('Mới', 'New')}</span>
          </div>
          <span style={{ display: 'block', fontSize: 12.5, color: ink, marginTop: 5 }}>{hostIntroIg}</span>
          <p style={{ fontSize: 13, lineHeight: 1.5, color: ink, margin: '12px 0 0' }}>{hostIntroDesc}</p>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginTop: 18, background: paper, borderRadius: 12, padding: 16 }}>
            <img src="/banbe-mark.png" alt="" crossOrigin="anonymous" style={{ width: 38, height: 'auto', display: 'block', flex: 'none', opacity: 0.75 }} />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
              <span style={{ fontSize: 13.5, fontWeight: 600, color: ink }}>{T('Chưa có sự kiện nào', 'No events yet')}</span>
              <span style={{ fontSize: 11.5, color: ink }}>{T('Sự kiện đầu tiên của bạn sẽ nằm ở đây.', 'Your first event will sit here.')}</span>
            </div>
          </div>
        </div>

        <div style={{ marginTop: 26, display: 'flex', flexDirection: 'column' }}>
          {points.map((p, i) => (
            <div key={p.title} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 16, padding: '13px 2px', borderBottom: i < points.length - 1 ? `1px solid ${rule}` : 'none' }}>
              <span style={{ fontSize: 13.5, fontWeight: 600, color: ink, flex: 'none' }}>{p.title}</span>
              <span style={{ fontSize: 12.5, color: ink, textAlign: 'right' }}>{p.note}</span>
            </div>
          ))}
        </div>
        <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, margin: '16px 0 0' }}>{T('banbe duyệt sự kiện đầu tiên trong 48 giờ. Sau đó bạn đăng trực tiếp.', 'banbe reviews your first event within 48 hours. After that you post directly.')}</p>
      </div>
      <div onClick={goCreate} style={{ ...barGlass({ position: 'absolute', left: 0, right: 0, bottom: 0, padding: '14px 20px 26px' }) }}>
        <div style={{ ...inkButton({ borderRadius: 999, padding: 16 }) }}>{T('Tạo sự kiện đầu tiên', 'Create your first event')}</div>
      </div>
    </div>
  );
}

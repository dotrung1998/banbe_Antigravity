import { paper, ink, display } from '../theme.js';

// Public, signed-out, context-free page at /data-deletion — the "data
// deletion instructions URL" Meta's app publish checklist requires.
const CONTACT = 'banbetestadmin@gmail.com';

export default function PublicDataDeletion() {
  const p = { fontSize: 14, lineHeight: 1.6, color: ink, margin: '0 0 10px' };
  return (
    <div style={{ minHeight: '100vh', background: paper }}>
      <div style={{ maxWidth: 640, margin: '0 auto', padding: '48px 22px 60px' }}>
        <h1 style={{ ...display(22, { margin: '0 0 4px' }) }}>Xoá dữ liệu và tài khoản banbe</h1>
        <h1 style={{ ...display(18, { margin: '0 0 20px', opacity: 0.75 }) }}>Delete your banbe data and account</h1>

        <h2 style={{ fontSize: 15, fontWeight: 600, color: ink, margin: '18px 0 6px' }}>Cách 1 / Option 1 — trong ứng dụng / in the app</h2>
        <p style={p}>Hồ sơ → Xoá Tài Khoản. Làm theo các bước xác nhận.</p>
        <p style={p}>Profile → Delete Account. Follow the confirmation steps.</p>

        <h2 style={{ fontSize: 15, fontWeight: 600, color: ink, margin: '18px 0 6px' }}>Cách 2 / Option 2 — qua email / by email</h2>
        <p style={p}>
          Gửi email tới <a href={`mailto:${CONTACT}?subject=Data%20deletion%20request`} style={{ color: ink }}>{CONTACT}</a> từ
          địa chỉ email đăng ký (hoặc email gắn với tài khoản Facebook/Google dùng để đăng nhập), tiêu đề “Data deletion request”.
        </p>
        <p style={p}>
          Email <a href={`mailto:${CONTACT}?subject=Data%20deletion%20request`} style={{ color: ink }}>{CONTACT}</a> from
          the address registered with your account (or the one linked to the Facebook/Google login you used), subject “Data deletion request”.
        </p>

        <h2 style={{ fontSize: 15, fontWeight: 600, color: ink, margin: '18px 0 6px' }}>Điều gì xảy ra / What happens</h2>
        <p style={p}>Hồ sơ, thông tin đăng nhập và dữ liệu cá nhân của bạn được xoá; dữ liệu bắt buộc giữ lại theo luật hoặc để giải quyết tranh chấp đang mở được xử lý theo <a href="/privacy" style={{ color: ink }}>Chính sách quyền riêng tư</a>.</p>
        <p style={p}>Your profile, login identity and personal data are deleted; data we must keep by law or for open disputes is handled as described in the <a href="/privacy" style={{ color: ink }}>Privacy Policy</a>.</p>
        <p style={p}>Bạn cũng có thể gỡ banbe khỏi Facebook: Cài đặt → Ứng dụng và trang web. / You can also remove banbe from Facebook: Settings → Apps and Websites.</p>
      </div>
    </div>
  );
}

import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, display } from '../theme.js';
import { POLICY_VERSION } from '../lib/policy.js';

// PLACEHOLDER CONTENT — banbe_User_Policy.md (referenced by the ticket that
// asked for this screen) does not exist anywhere in this repo. This is
// structurally where the real policy text goes (linked from the consent
// checkbox on Login.jsx, version-tracked via profiles.policy_version), but
// the copy below is a stand-in only and must be replaced with banbe's
// actual legal text before this ships. See .claude/notes/07-notifications.md
// — no, see the session report: flagged there, not silently shipped as real.
export default function Policy() {
  const { state, T, backFromPolicy } = useGoc();
  const s = state;

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Policy">
      <div style={{ padding: '66px 22px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <span onClick={backFromPolicy} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Quay lại', 'Back')}</span>
        <span style={{ fontSize: 11, color: ink, opacity: 0.5 }}>{T('Phiên bản', 'Version')} {POLICY_VERSION}</span>
      </div>
      <div style={{ padding: '18px 22px 60px' }}>
        <h1 style={{ ...display(24, { margin: '0 0 4px' }) }}>{T('Điều khoản sử dụng và Thông báo quyền riêng tư', 'Terms of Service and Privacy Notice')}</h1>
        <p style={{ fontSize: 11.5, color: ink, opacity: 0.55, margin: '0 0 20px' }}>
          {T('⚠️ NỘI DUNG TẠM THỜI — chưa phải văn bản pháp lý chính thức của banbe.',
             '⚠️ PLACEHOLDER CONTENT — not banbe\'s finalized legal text yet.')}
        </p>

        <Section title={T('1. Dữ liệu chúng tôi thu thập', '1. Data we collect')}>
          {T('Email, tên hiển thị, và thông tin đặt chỗ/thanh toán bạn cung cấp khi sử dụng banbe.',
             'Email, display name, and booking/payment details you provide while using banbe.')}
        </Section>
        <Section title={T('2. Mục đích sử dụng', '2. Why we use it')}>
          {T('Để vận hành việc đặt chỗ, xác nhận thanh toán, xử lý tranh chấp, và liên lạc liên quan tới sự kiện bạn tham gia hoặc tổ chức.',
             'To run bookings, confirm payments, resolve disputes, and communicate about events you attend or host.')}
        </Section>
        <Section title={T('3. Lưu trữ và xoá dữ liệu', '3. Retention and deletion')}>
          {T('Đoạn chat tranh chấp bị xoá 72 giờ sau khi banbe ra quyết định. Dữ liệu tài khoản khác được giữ trong thời gian bạn còn sử dụng dịch vụ.',
             'Dispute chat transcripts are deleted 72 hours after banbe rules on them. Other account data is kept while you continue using the service.')}
        </Section>
        <Section title={T('4. Quyền của bạn', '4. Your rights')}>
          {T('Bạn có thể yêu cầu xem, sửa, hoặc xoá dữ liệu cá nhân của mình bất cứ lúc nào qua Tài khoản.',
             'You can request to view, correct, or delete your personal data at any time from Account.')}
        </Section>
        <Section title={T('5. Đồng ý', '5. Consent')}>
          {T('Bằng việc đánh dấu vào ô đồng ý khi đăng nhập/đăng ký, bạn xác nhận đã đọc và đồng ý với các điều khoản này.',
             'By checking the consent box at sign-in/sign-up, you confirm you have read and agree to these terms.')}
        </Section>
      </div>
    </div>
  );
}

function Section({ title, children }) {
  return (
    <div style={{ marginTop: 18, paddingTop: 14, borderTop: `1px solid ${rule}` }}>
      <h2 style={{ fontSize: 14, fontWeight: 600, color: ink, margin: '0 0 6px' }}>{title}</h2>
      <p style={{ fontSize: 13, lineHeight: 1.55, color: ink, opacity: 0.85, margin: 0 }}>{children}</p>
    </div>
  );
}

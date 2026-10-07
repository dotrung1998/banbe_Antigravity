import { useBanBe } from '../state/BanBeContext.jsx';
import { ink, rule, fieldGlass } from '../theme.js';
import { entryMatches, markReturnToSearch } from '../lib/accountSearch.js';
import { RowIcon } from './Account.jsx';

// Web port of iOS's accountSearchEntries / accountSearchResults
// (AccountView.swift). Every destination reachable from Account, tagged with
// its tab (personal / host / admin) and the section it lives under. Host and
// Admin entries only exist for accounts that actually have those tabs.
// `keywords` adds the words people might type that the title wouldn't match
// (both languages, any diacritics — see foldText in lib/accountSearch.js).
// Same ids and keyword lists as iOS so the two platforms find the same rows.

const TABS = [
  { key: 'personal', vi: 'Cá Nhân', en: 'Personal' },
  { key: 'host', vi: 'Tổ Chức', en: 'Host' },
  { key: 'admin', vi: 'Quản Trị', en: 'Admin' },
];

export function useAccountSearchEntries() {
  const g = useBanBe();
  const { state: s, set, canHost } = g;
  const e = (id, tab, secVi, secEn, vi, en, icon, keywords, action, extra) => ({ id, tab, secVi, secEn, vi, en, icon, keywords, action, ...extra });
  const actVi = 'Hoạt Động Của Bạn', actEn = 'Your Activity';
  const setVi = 'Tài Khoản & Cài Đặt', setEn = 'Account & Settings';
  // Screens that return through documentsBack (Payout / Disputes / AdminEvents)
  // would otherwise land on 'accountGroup'; point them at Account so Back
  // returns to the search results.
  const viaDocsBack = (fn) => () => { set({ documentsBack: 'profile' }); fn(); };

  const list = [
    e('tickets', 'personal', actVi, actEn, 'Vé & Đặt Chỗ', 'Tickets & Bookings', 'calendarCheck',
      'vé ticket booking đặt chỗ giữ chỗ hold qr check-in đã hủy hết hạn cancelled expired my tickets vé của tôi', () => g.openAccountGroup('activity')),
    e('going', 'personal', actVi, actEn, 'Đang tham gia', 'Going', 'calendarCheck',
      'attending sắp tham gia sự kiện của tôi my events upcoming', () => g.goGoingList()),
    e('saved', 'personal', actVi, actEn, 'Sự Kiện Đã Lưu', 'Saved Events', 'document',
      'lưu yêu thích favorites favourite bookmark wishlist', () => g.goSavedList()),
    e('past', 'personal', actVi, actEn, 'Sự Kiện Quá Khứ', 'Past Events', 'calendarCheck',
      'đã hoàn thành completed ended lịch sử history đã qua', () => g.goCompletedList()),
    e('payments', 'personal', actVi, actEn, 'Thanh Toán & Giấy Tờ', 'Payments & Documents', 'banknote',
      'thanh toán payment tiền money giấy tờ documents', () => g.openAccountGroup('payments')),
    e('invoices', 'personal', actVi, actEn, 'Hoá đơn', 'Invoices', 'document',
      'hóa đơn invoice bill tài liệu pdf', () => g.openDocuments('invoice', 'guest', 'profile')),
    e('receipts', 'personal', actVi, actEn, 'Biên nhận', 'Receipts', 'receipt',
      'receipt biên lai chứng từ pdf', () => g.openDocuments('receipt', 'guest', 'profile')),
    e('refundAccounts', 'personal', actVi, actEn, 'Tài khoản thanh toán & nhận hoàn tiền', 'Payment & refund accounts', 'banknote',
      'ngân hàng bank tài khoản account số tài khoản momo chuyển khoản hoàn tiền refund destination', () => g.openRefundAccounts('profile')),
    e('refunds', 'personal', actVi, actEn, 'Hoàn tiền', 'Refunds', 'checklist',
      'refund hoàn trả trả lại tiền hủy sự kiện tranh chấp dispute', () => g.openMyRefunds('profile')),
    e('reportsPersonal', 'personal', actVi, actEn, 'Số Liệu & Báo Cáo', 'Metrics & Reports', 'checklist',
      'thống kê statistics analytics báo cáo report số liệu insights', () => g.openReports('personal', null, 'profile')),
    e('profile', 'personal', setVi, setEn, 'Hồ Sơ Cá Nhân', 'Personal Profile', 'pencil',
      'profile hồ sơ tên name avatar ảnh đại diện handle chỉnh sửa edit public trang cá nhân',
      () => { if (s.user?.handle) g.openPublicProfile(s.user.handle, 'profile'); }),
    e('preferences', 'personal', setVi, setEn, 'Cài Đặt', 'Settings', 'sliders',
      'settings cài đặt tùy chỉnh preferences', () => g.openAccountGroup('preferences')),
    e('language', 'personal', setVi, setEn, 'Ngôn ngữ & Hiển thị', 'Language & Appearance', 'sliders',
      'ngôn ngữ language tiếng việt english vn en theme giao diện sáng tối dark light mode hiển thị appearance kính glass độ trong suốt', () => g.openPreferences()),
    e('security', 'personal', setVi, setEn, 'Bảo mật', 'Security', 'shield',
      'security mật khẩu password face id sinh trắc biometric đăng nhập login khóa lock đổi mật khẩu', () => g.openSecurity()),
    e('eventPreferences', 'personal', setVi, setEn, 'Sở thích sự kiện', 'Event preferences', 'sliders',
      'sở thích interests gợi ý for you ngân sách budget mục tiêu goals thời gian rảnh availability ngôn ngữ sự kiện preferences', () => g.openEventPreferences(null)),
    e('help', 'personal', setVi, setEn, 'Trợ Giúp & Pháp Lý', 'Help & Legal', 'shield',
      'help trợ giúp hỗ trợ support policy chính sách điều khoản terms privacy quyền riêng tư pháp lý legal liên hệ contact hướng dẫn guide hỏi đáp faq q&a câu hỏi questions', () => g.openAccountGroup('helpLegal')),
    e('organizerMode', 'personal', 'Tổ Chức', 'Hosting', 'Chế độ tổ chức', 'Organizer mode', 'switch',
      'host tổ chức organizer bật tắt toggle tạo sự kiện create event quản lý manage', () => g.toggleOrganizerMode()),
    e('signOut', 'personal', setVi, setEn, s.user ? 'Đăng xuất' : 'Đăng nhập', s.user ? 'Sign out' : 'Sign in', s.user ? 'logout' : 'login',
      'logout log out thoát đăng xuất đăng nhập sign in login tài khoản account', () => (s.user ? g.logout() : g.goLogin()), { keepSearch: false }),
  ];
  if (s.organizerMode && canHost) {
    const hVi = 'Tổ Chức', hEn = 'Host';
    list.push(
      e('hostOps', 'host', hVi, hEn, 'Vận Hành & Thanh Toán Tổ Chức', 'Event Operations & Payments', 'checklist',
        'vận hành operations thanh toán payments tổ chức host sự kiện', () => g.openAccountGroup('hostOps')),
      e('submittedEvents', 'host', hVi, hEn, 'Sự Kiện Đã Gửi Chờ Duyệt', 'Submitted Events', 'checklist',
        'chờ duyệt đã gửi submitted review pending cần chỉnh sửa needs fixing nhắc admin remind rút lại withdraw', () => g.goDashboard('profile')),
      e('verifications', 'host', hVi, hEn, 'Chờ xác nhận thanh toán', 'Awaiting Verification', 'checklist',
        'xác nhận verify verification thanh toán chờ pending người mua guest bằng chứng proof chuyển khoản', () => g.openVerifications('profile')),
      e('hostRefunds', 'host', hVi, hEn, 'Hoàn tiền', 'Refunds', 'banknote',
        'refund hoàn trả hủy sự kiện cancel batch đã gửi mark sent tranh chấp dispute', () => g.openVerificationsRefunds('profile')),
      e('payout', 'host', hVi, hEn, 'Nhận thanh toán', 'Getting Paid', 'banknote',
        'payout nhận tiền ngân hàng bank thanh toán doanh thu revenue rút tiền', viaDocsBack(() => g.openPayout())),
      e('invoicesIssued', 'host', hVi, hEn, 'Hoá đơn đã phát hành', 'Invoices Issued', 'document',
        'hóa đơn invoice phát hành tải lên upload tài liệu', () => g.openDocuments('invoice', 'host', 'profile')),
      e('receiptsIssued', 'host', hVi, hEn, 'Biên nhận đã phát hành', 'Receipts Issued', 'receipt',
        'biên lai receipt phát hành tải lên upload tài liệu', () => g.openDocuments('receipt', 'host', 'profile')),
      e('team', 'host', hVi, hEn, 'Hồ Sơ & Team Tổ Chức', 'Organizer Profile & Team', 'users',
        'team đội nhóm thành viên member mời invite hồ sơ tổ chức organizer profile đóng góp contribution credit', () => g.openAccountGroup('team')),
      e('surveys', 'host', hVi, hEn, 'Khảo Sát & Ý Tưởng Sự Kiện', 'Surveys & Event Ideas', 'checklist',
        'survey khảo sát ý tưởng idea góp ý feedback câu hỏi form', () => g.goSurveysHosting(), { keepSearch: false }),
      e('reportsHost', 'host', hVi, hEn, 'Số Liệu & Báo Cáo', 'Metrics & Reports', 'checklist',
        'thống kê statistics analytics báo cáo report số liệu doanh thu', () => g.openReports('host', s.myOrganizerId, 'profile')),
    );
  }
  if (s.accountType === 'admin') {
    const aVi = 'Quản Trị', aEn = 'Administration';
    list.push(
      e('adminReview', 'admin', aVi, aEn, 'Duyệt & Kiểm Duyệt', 'Review & Moderation', 'alertShield',
        'duyệt review kiểm duyệt moderation approve phê duyệt', () => g.openAccountGroup('adminReview')),
      e('disputes', 'admin', aVi, aEn, 'Tranh Chấp Thanh Toán', 'Payment Disputes', 'alertShield',
        'tranh chấp dispute khiếu nại escalation thanh toán payment dashboard bảng điều khiển bảng quản trị admin panel', viaDocsBack(() => g.openDisputes())),
      e('pendingEvents', 'admin', aVi, aEn, 'Sự Kiện Chờ Duyệt', 'Pending Events', 'alertShield',
        'sự kiện chờ duyệt pending events approve từ chối reject nhắc remind', viaDocsBack(() => g.openAdminEvents())),
      e('adminTeam', 'admin', aVi, aEn, 'Đội Ngũ Quản Trị', 'Admin Team', 'users',
        'admin quản trị viên mời invite thành viên team đội ngũ', () => g.openAccountGroup('adminTeam')),
      e('reportsAdmin', 'admin', aVi, aEn, 'Số Liệu & Báo Cáo', 'Metrics & Reports', 'checklist',
        'thống kê statistics analytics báo cáo report số liệu', () => g.openReports('admin', null, 'profile')),
    );
  }
  return list;
}

/** Results grouped under Personal / Host / Admin, in the same grouped-card style as the rest of Account. */
export default function AccountSearchResults({ query }) {
  const { T, setAccountTab } = useBanBe();
  const entries = useAccountSearchEntries();
  const groups = TABS
    .map(t => ({ t, items: entries.filter(en => en.tab === t.key && entryMatches(en, query, t)) }))
    .filter(gr => gr.items.length);

  return (
    <div data-testid="account-search-results" style={{ padding: '0 20px 100px' }}>
      {groups.length === 0 && (
        <p data-testid="account-search-empty" style={{ textAlign: 'center', fontSize: 13, color: ink, opacity: 0.7, marginTop: 40 }}>
          {T('Không tìm thấy kết quả phù hợp.', 'No matching results.')}
        </p>
      )}
      {groups.map((gr, gi) => (
        <div key={gr.t.key}>
          <div data-testid="account-search-section" style={{ paddingTop: gi === 0 ? 14 : 22 }}>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T(gr.t.vi, gr.t.en)}</span>
          </div>
          <div style={{ ...fieldGlass({ marginTop: 10, display: 'flex', flexDirection: 'column', overflow: 'hidden' }) }}>
            {gr.items.map((en, i) => (
              <div
                key={en.id}
                data-testid={`account-search-${en.id}`}
                onClick={() => {
                  // Keep the search + its query so Back from the result returns here.
                  setAccountTab(en.tab);
                  if (en.keepSearch !== false) markReturnToSearch(query);
                  en.action();
                }}
                style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 16px', cursor: 'pointer', borderBottom: i < gr.items.length - 1 ? `1px solid ${rule}` : 'none' }}
              >
                <RowIcon kind={en.icon} />
                <div style={{ display: 'flex', flexDirection: 'column', gap: 2, flex: 1, minWidth: 0 }}>
                  <span style={{ fontSize: 14, color: ink }}>{T(en.vi, en.en)}</span>
                  <span style={{ fontSize: 11, color: ink, opacity: 0.55 }}>{T(en.secVi, en.secEn)}</span>
                </div>
                <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

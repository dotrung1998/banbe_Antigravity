import { useBanBe } from '../state/BanBeContext.jsx';
import { ink, rule, fieldGlass } from '../theme.js';
import { entryMatches, markReturnToSearch } from '../lib/accountSearch.js';
import { RowIcon } from './Account.jsx';

// Web port of iOS's accountSearchEntries / accountSearchResults
// (AccountView.swift). Every destination reachable from Account, tagged with
// its group (personal / host / admin) and the section it lives under. Note 66:
// Account has no tabs any more; the group is only how results are grouped.
// Host entries exist while organizer mode is on, Admin entries for admins.
// `keywords` adds the words people might type that the title wouldn't match
// (both languages, any diacritics — see foldText in lib/accountSearch.js).
// Same ids and keyword lists as iOS so the two platforms find the same rows.

const TABS = [
  { key: 'personal', vi: 'Cá nhân', en: 'Personal' },
  { key: 'host', vi: 'Tổ chức', en: 'Host' },
  { key: 'admin', vi: 'Quản trị', en: 'Admin' },
];

export function useAccountSearchEntries() {
  const g = useBanBe();
  const { state: s, set, canHost } = g;
  const e = (id, tab, secVi, secEn, vi, en, icon, keywords, action, extra) => ({ id, tab, secVi, secEn, vi, en, icon, keywords, action, ...extra });
  // Note 66: sections name where the row lives now that Account has no tabs: the top tiles / profile card
  // ("Account"), a tile's own screen ("Tickets", "Wallet", ...), the "More" list, or Settings.
  const accVi = 'Tài khoản', accEn = 'Account';
  const tixVi = 'Vé & đặt chỗ', tixEn = 'Tickets';
  const walVi = 'Ví & chứng từ', walEn = 'Wallet';
  const moreVi = 'Thêm', moreEn = 'More';
  const setVi = 'Cài đặt', setEn = 'Settings';
  // Screens that return through documentsBack (Payout / Disputes / AdminEvents)
  // would otherwise land on 'accountGroup'; point them at Account so Back
  // returns to the search results.
  const viaDocsBack = (fn) => () => { set({ documentsBack: 'profile' }); fn(); };

  const list = [
    e('tickets', 'personal', accVi, accEn, 'Vé & đặt chỗ', 'Tickets', 'ticket',
      'vé ticket booking bookings đặt chỗ giữ chỗ hold qr check-in đã hủy hết hạn cancelled expired my tickets vé của tôi', () => g.openAccountGroup('activity')),
    e('going', 'personal', tixVi, tixEn, 'Đang tham gia', 'Going', 'calendarCheck',
      'attending sắp tham gia sắp tới upcoming sự kiện của tôi my events', () => g.goGoingList()),
    e('saved', 'personal', accVi, accEn, 'Đã lưu', 'Saved', 'bookmark',
      'lưu sự kiện đã lưu saved events yêu thích favorites favourite bookmark wishlist', () => g.goSavedList()),
    e('past', 'personal', tixVi, tixEn, 'Sự kiện quá khứ', 'Past events', 'calendarCheck',
      'đã hoàn thành completed ended lịch sử history đã qua', () => g.goCompletedList()),
    e('payments', 'personal', accVi, accEn, 'Ví & chứng từ', 'Wallet', 'wallet',
      'ví wallet thanh toán payment payments tiền money giấy tờ documents chứng từ', () => g.openAccountGroup('payments')),
    e('invoices', 'personal', walVi, walEn, 'Hoá đơn', 'Invoices', 'document',
      'hóa đơn invoice bill tài liệu pdf', () => g.openDocuments('invoice', 'guest', 'profile')),
    e('receipts', 'personal', walVi, walEn, 'Biên nhận', 'Receipts', 'receipt',
      'receipt biên lai chứng từ pdf', () => g.openDocuments('receipt', 'guest', 'profile')),
    e('refundAccounts', 'personal', walVi, walEn, 'Tài khoản thanh toán & nhận hoàn tiền', 'Payment & refund accounts', 'banknote',
      'ngân hàng bank tài khoản account số tài khoản momo chuyển khoản hoàn tiền refund destination', () => g.openRefundAccounts('profile')),
    e('refunds', 'personal', walVi, walEn, 'Hoàn tiền', 'Refunds', 'checklist',
      'refund hoàn trả trả lại tiền hủy sự kiện tranh chấp dispute', () => g.openMyRefunds('profile')),
    ...(s.user ? [e('reportsPersonal', 'personal', moreVi, moreEn, 'Báo cáo', 'Reports', 'chart',
      'thống kê statistics analytics báo cáo report reports số liệu metrics insights', () => g.openReports('personal', null, 'profile'))] : []),
    e('profile', 'personal', accVi, accEn, 'Hồ sơ cá nhân', 'Personal profile', 'pencil',
      'profile hồ sơ tên name avatar ảnh đại diện handle chỉnh sửa edit public trang cá nhân',
      () => { if (s.user?.handle) g.openPublicProfile(s.user.handle, 'profile'); }),
    e('notifications', 'personal', moreVi, moreEn, 'Thông báo', 'Notifications', 'bell',
      'thông báo notifications notification alerts chưa đọc unread bell chuông', () => g.goNotifications()),
    e('following', 'personal', moreVi, moreEn, 'Đang theo dõi', 'Following', 'heart',
      'following theo dõi follow host tổ chức organizer followed unfollow bỏ theo dõi', () => set({ screen: 'following' })),
    ...(g.referralLink ? [e('inviteFriends', 'personal', moreVi, moreEn, 'Mời bạn bè', 'Invite friends', 'users',
      'mời invite bạn bè friends giới thiệu referral link chia sẻ share', () => g.shareReferral(), { keepSearch: false })] : []),
    ...(g.rewardsEnabled ? [e('rewards', 'personal', accVi, accEn, 'Phần thưởng & huy hiệu', 'Rewards & badges', 'coin',
      'rewards phần thưởng huy hiệu badges coin xu streak chuỗi ngày milestone thành tích', () => set({ screen: 'rewards', rewardsBack: 'profile' }))] : []),
    e('preferences', 'personal', moreVi, moreEn, 'Cài đặt', 'Settings', 'sliders',
      'settings cài đặt tùy chỉnh preferences', () => g.openAccountGroup('preferences')),
    e('language', 'personal', setVi, setEn, 'Ngôn ngữ & Hiển thị', 'Language & Appearance', 'sliders',
      'ngôn ngữ language tiếng việt english vn en theme giao diện sáng tối dark light mode hiển thị appearance kính glass độ trong suốt', () => g.openPreferences()),
    e('security', 'personal', setVi, setEn, 'Bảo mật', 'Security', 'shield',
      'security mật khẩu password face id sinh trắc biometric đăng nhập login khóa lock đổi mật khẩu', () => g.openSecurity()),
    e('eventPreferences', 'personal', setVi, setEn, 'Sở thích sự kiện', 'Event preferences', 'sliders',
      'sở thích interests gợi ý for you ngân sách budget mục tiêu goals thời gian rảnh availability ngôn ngữ sự kiện preferences', () => g.openEventPreferences(null)),
    e('help', 'personal', accVi, accEn, 'Trợ giúp', 'Help', 'help',
      'help trợ giúp hỗ trợ support policy chính sách điều khoản terms privacy quyền riêng tư pháp lý legal liên hệ contact hướng dẫn guide guides hỏi đáp faq q&a câu hỏi questions', () => g.openAccountGroup('helpLegal')),
    ...(s.user ? [e('organizerMode', 'personal', moreVi, moreEn, 'Chế độ tổ chức', 'Hosting mode', 'switch',
      'host hosting tổ chức organizer mode chế độ bật tắt toggle tạo sự kiện create event quản lý manage', () => g.toggleOrganizerMode())] : []),
    e('signOut', 'personal', accVi, accEn, s.user ? 'Đăng xuất' : 'Đăng nhập', s.user ? 'Sign out' : 'Sign in', s.user ? 'logout' : 'login',
      'logout log out thoát đăng xuất đăng nhập sign in login tài khoản account', () => (s.user ? g.logout() : g.goLogin()), { keepSearch: false }),
  ];
  if (s.organizerMode && canHost) {
    const paidVi = 'Nhận tiền', paidEn = 'Get paid';
    list.push(
      e('submittedEvents', 'host', accVi, accEn, 'Sự kiện', 'Events', 'calendarCheck',
        'sự kiện events chờ duyệt đã gửi submitted review pending cần chỉnh sửa needs fixing nhắc admin remind rút lại withdraw quản lý manage dashboard', () => g.goDashboard('profile')),
      e('hostOps', 'host', accVi, accEn, 'Nhận tiền', 'Get paid', 'banknote',
        'nhận tiền get paid vận hành operations thanh toán payments tổ chức host sự kiện', () => g.openAccountGroup('hostOps')),
      e('verifications', 'host', paidVi, paidEn, 'Chờ xác nhận thanh toán', 'Awaiting Verification', 'checklist',
        'xác nhận verify verification thanh toán chờ pending người mua guest bằng chứng proof chuyển khoản', () => g.openVerifications('profile')),
      e('hostRefunds', 'host', paidVi, paidEn, 'Hoàn tiền', 'Refunds', 'banknote',
        'refund hoàn trả hủy sự kiện cancel batch đã gửi mark sent tranh chấp dispute', () => g.openVerificationsRefunds('profile')),
      e('payout', 'host', paidVi, paidEn, 'Nhận thanh toán', 'Getting Paid', 'banknote',
        'payout nhận tiền ngân hàng bank thanh toán doanh thu revenue rút tiền', viaDocsBack(() => g.openPayout())),
      e('invoicesIssued', 'host', paidVi, paidEn, 'Hoá đơn đã phát hành', 'Invoices Issued', 'document',
        'hóa đơn invoice phát hành tải lên upload tài liệu', () => g.openDocuments('invoice', 'host', 'profile')),
      e('receiptsIssued', 'host', paidVi, paidEn, 'Biên nhận đã phát hành', 'Receipts Issued', 'receipt',
        'biên lai receipt phát hành tải lên upload tài liệu', () => g.openDocuments('receipt', 'host', 'profile')),
      e('team', 'host', accVi, accEn, 'Đội ngũ', 'Team', 'users',
        'team đội ngũ nhóm thành viên member mời invite hồ sơ tổ chức organizer profile đóng góp contribution credit', () => g.openAccountGroup('team')),
      e('surveys', 'host', moreVi, moreEn, 'Khảo sát & ý tưởng sự kiện', 'Surveys & event ideas', 'lightbulb',
        'survey khảo sát ý tưởng idea góp ý feedback câu hỏi form', () => g.goSurveysHosting(), { keepSearch: false }),
      ...(s.myOrganizerId ? [e('organizerProfile', 'host', moreVi, moreEn, 'Hồ sơ tổ chức', 'Organizer profile', 'store',
        'hồ sơ tổ chức organizer profile trang công khai public page host page', () => g.openOrganizerProfile(s.myOrganizerId, 'profile'))] : []),
      e('reportsHost', 'host', accVi, accEn, 'Báo cáo', 'Reports', 'chart',
        'thống kê statistics analytics báo cáo report reports số liệu metrics doanh thu',
        () => (s.myOrganizerId ? g.openReports('host', s.myOrganizerId, 'profile') : g.openHostSetup()), s.myOrganizerId ? undefined : { keepSearch: false }),
    );
  }
  if (s.accountType === 'admin') {
    const aVi = 'Công cụ quản trị', aEn = 'Admin tools';
    list.push(
      e('adminTools', 'admin', moreVi, moreEn, 'Công cụ quản trị', 'Admin tools', 'shield',
        'admin quản trị administration công cụ tools', () => g.openAccountGroup('admin')),
      e('adminReview', 'admin', aVi, aEn, 'Duyệt & Kiểm Duyệt', 'Review & Moderation', 'alertShield',
        'duyệt review kiểm duyệt moderation approve phê duyệt', () => g.openAccountGroup('adminReview')),
      e('disputes', 'admin', aVi, aEn, 'Tranh Chấp Thanh Toán', 'Payment Disputes', 'alertShield',
        'tranh chấp dispute khiếu nại escalation thanh toán payment dashboard bảng điều khiển bảng quản trị admin panel', viaDocsBack(() => g.openDisputes())),
      e('pendingEvents', 'admin', aVi, aEn, 'Sự Kiện Chờ Duyệt', 'Pending Events', 'alertShield',
        'sự kiện chờ duyệt pending events approve từ chối reject nhắc remind', viaDocsBack(() => g.openAdminEvents())),
      e('adminTeam', 'admin', aVi, aEn, 'Đội Ngũ Quản Trị', 'Admin Team', 'users',
        'admin quản trị viên mời invite thành viên team đội ngũ', () => g.openAccountGroup('adminTeam')),
      e('reportsAdmin', 'admin', aVi, aEn, 'Số Liệu & Báo Cáo', 'Metrics & Reports', 'chart',
        'thống kê statistics analytics báo cáo report số liệu', () => g.openReports('admin', null, 'profile')),
      e('adminGuide', 'admin', aVi, aEn, 'Hướng Dẫn Quản Trị', 'Admin Guide', 'checklist',
        'hướng dẫn guide quản trị admin handbook', () => set({ screen: 'guide', guideKey: 'admin' }), { keepSearch: false }),
    );
  }
  return list;
}

/** Results grouped under Personal / Host / Admin, in the same grouped-card style as the rest of Account. */
export default function AccountSearchResults({ query }) {
  const { T } = useBanBe();
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

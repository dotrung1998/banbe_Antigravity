// Concise guide for admin accounts only. Blocks: see HelpReader.jsx.
export const ADMIN_GUIDE = {
  adminOnly: true,
  vi: 'Hướng dẫn cho Quản trị viên', en: 'Admin Guide',
  introVi: 'Ngắn gọn, chỉ dành cho quản trị viên. Tab "Admin" chỉ hiện với tài khoản có vai trò admin trên máy chủ.',
  introEn: 'Concise and for admins only. The "Admin" tab only appears for accounts with the server-side admin role.',
  sections: [
    { id: 'overview', vi: 'Tổng quan', en: 'Overview', blocks: [
      ['ul', [
        ['Tab "Admin" > "Administration" gồm: Review & Moderation, Admin Team, Metrics & Reports.', 'The "Admin" tab > "Administration" has: Review & Moderation, Admin Team, Metrics & Reports.'],
        ['Quyền do máy chủ kiểm soát; ứng dụng không thể tự cấp quyền admin.', 'Permissions are enforced by the server; the app cannot grant itself admin.'],
        ['Mọi thao tác quản trị được ghi lại.', 'Admin actions are logged.'],
      ]],
    ]},
    { id: 'events', vi: 'Duyệt sự kiện', en: 'Approving events', blocks: [
      ['ol', [
        ['Review & Moderation > "Pending Events" (có huy hiệu số lượng).', 'Review & Moderation > "Pending Events" (with a count badge).'],
        ['Mở thẻ sự kiện, kiểm tra mô tả, "Included", địa chỉ, riêng tư, loại tổ chức tự khai và thông tin đăng ký kinh doanh (chưa được banbe xác minh).', 'Open the event card and check the description, "Included", address, visibility, the self-declared organizer type and business details (not verified by banbe).'],
        ['"Approve ▪︎ publish" để đăng, hoặc "Reject" kèm lý do bắt buộc.', '"Approve ▪︎ publish" to go live, or "Reject" with a required reason.'],
      ]],
      ['tip', 'Host có thể nhắc tối đa 2 lần mỗi sự kiện; không có hạn chót tự động, nên xử lý theo thứ tự cũ nhất trước.', 'Hosts can remind up to 2 times per event; there is no automatic deadline, so work oldest first.'],
    ]},
    { id: 'disputes', vi: 'Xử lý tranh chấp', en: 'Resolving disputes', blocks: [
      ['ol', [
        ['Review & Moderation > "Payment disputes".', 'Review & Moderation > "Payment disputes".'],
        ['Xem khách, Reference, Transaction ID, ảnh biên lai, lý do host từ chối và chat tranh chấp.', 'Review the guest, Reference, Transaction ID, receipt image, the host\'s rejection reason and the dispute chat.'],
        ['Tranh chấp thanh toán: "Buyer is right ▪︎ issue ticket" hoặc "Release seat"; thêm "Resolution note".', 'Payment dispute: "Buyer is right ▪︎ issue ticket" or "Release seat"; add a "Resolution note".'],
        ['Tranh chấp hoàn tiền cũng nằm trong hàng đợi này.', 'Refund disputes are in the same queue.'],
      ]],
      ['p', 'Sau quyết định, hai bên nhận thông báo và email. Nếu email lỗi, lỗi chỉ hiện trên màn hình của bạn lúc đó.', 'After a decision both parties get a notification and email. If the email fails the error shows only on your screen at that moment.'],
    ]},
    { id: 'dobfix', vi: 'Sửa ngày sinh', en: 'Birthday corrections', blocks: [
      ['ol', [
        ['Vào tab "Admin" > "Review & Moderation" > "Birthday corrections".', 'Open the "Admin" tab > "Review & Moderation" > "Birthday corrections".'],
        ['Mỗi yêu cầu cho thấy người gửi, ngày sinh hiện tại, ngày được yêu cầu và lý do.', 'Each request shows who sent it, the current date of birth, the requested date and the reason.'],
        ['"Approve" ghi đè ngày sinh đã lưu; "Decline" giữ nguyên. Bạn có thể thêm ghi chú cho người dùng.', '"Approve" overwrites the stored date of birth; "Decline" keeps it. You can add a note for the user.'],
      ]],
      ['tip', 'Chỉ duyệt khi lý do hợp lý. Bạn không thể xử lý yêu cầu của chính mình, và mọi quyết định đều được ghi lại.', 'Approve only when the reason is credible. You cannot decide your own request, and every decision is logged.'],
    ]},
    { id: 'team', vi: 'Đội ngũ quản trị', en: 'Admin Team', blocks: [
      ['ul', [
        ['"Invite Admin" gửi lời mời qua email dùng một lần; email người nhận được kiểm tra khi chấp nhận.', '"Invite Admin" sends a single-use email invite; the invitee\'s email is verified when accepting.'],
        ['Quyền quản lý admin là quyền riêng; admin mới không tự có, phải được người đang có quyền cấp.', 'Managing admins is a separate permission; a new admin does not get it automatically and must be granted it.'],
        ['Thu hồi admin sẽ hạ về người tham gia; không thể tự thu hồi mình hoặc thu hồi admin cuối cùng.', 'Revoking an admin demotes them to a participant; you cannot revoke yourself or the last admin.'],
        ['Người được mời thấy lời mời trong "Việc cần xử lý" (Trang chính và Tài khoản) và chấp nhận hoặc từ chối trong Đội ngũ quản trị; lời mời hết hạn sau 7 ngày. Khi họ phản hồi, bạn nhận thông báo và danh sách tự làm mới.', 'The invitee sees the invite under "Things to do" (Home and Account) and accepts or declines it in Admin Team; invites expire after 7 days. When they answer you get a notification and the list refreshes.'],
      ]],
    ]},
    { id: 'protected', vi: 'Tài khoản quản trị được bảo vệ', en: 'Protected admin', blocks: [
      ['p', 'Tài khoản banbetestadmin@gmail.com được bảo vệ: không ai có thể bỏ quyền quản lý đội ngũ hay gỡ vai trò quản trị của tài khoản này một cách trực tiếp.', 'The banbetestadmin@gmail.com account is protected: nobody can remove its team-management access or its admin role directly.'],
      ['ul', [
        ['Khi chỉ có dưới 3 quản trị viên (tính cả tài khoản này), việc gỡ bị chặn hoàn toàn.', 'With fewer than 3 admins in total (counting this account), removal is blocked outright.'],
        ['Từ 3 quản trị viên trở lên, một quản trị viên có quyền quản lý đội ngũ có thể mở cuộc bỏ phiếu: "Start a vote: remove team-management access" hoặc "Start a vote: remove as admin" ở dòng của tài khoản đó trong Current Admins.', 'With 3 or more admins, an admin who has team-management access can open a vote: "Start a vote: remove team-management access" or "Start a vote: remove as admin" on that account\'s row under Current Admins.'],
        ['Người bỏ phiếu là các quản trị viên có quyền quản lý đội ngũ, trừ chính tài khoản bị xét (không tự bỏ phiếu cho mình). Cần ít nhất 2 người bỏ phiếu; admin mới phải được cấp quyền quản lý đội ngũ trước.', 'Voters are the admins who have team-management access, except the account in question (it does not vote on itself). At least 2 voters are needed; a new admin must be granted team-management access first.'],
        ['Cần đa số tuyệt đối của người bỏ phiếu (hơn một nửa) đồng ý. Người mở cuộc bỏ phiếu tính là một phiếu đồng ý; mỗi người một phiếu và không đổi được.', 'A strict majority of the voters (more than half) must approve. The person who opens the vote counts as one yes; each voter has one ballot and cannot change it.'],
        ['Cuộc bỏ phiếu hết hạn sau 72 giờ; người mở có thể huỷ. Nếu số quản trị viên giảm xuống dưới 3 trước khi có kết quả thì việc gỡ bị huỷ.', 'A vote expires after 72 hours; its opener can cancel it. If the admin count drops below 3 before it is decided, the removal is cancelled.'],
        ['Thông qua: quyền được gỡ ngay. Bị từ chối hoặc không còn đủ phiếu đồng ý: không có gì thay đổi.', 'If it passes the removal happens immediately. If it is rejected or can no longer reach a majority, nothing changes.'],
      ]],
      ['tip', 'Cuộc bỏ phiếu đang mở xuất hiện trong "Open Votes" của Đội ngũ quản trị, và bạn nhận thông báo khi có cuộc bỏ phiếu mới hoặc có kết quả.', 'Open votes appear under "Open Votes" in Admin Team, and you get a notification when a vote opens or is decided.'],
    ]},
    { id: 'test', vi: 'Tài khoản thử nghiệm', en: 'Test accounts', blocks: [
      ['ol', [
        ['Review & Moderation > "Test accounts"; tìm theo email hoặc tên hiển thị.', 'Review & Moderation > "Test accounts"; search by email or display name.'],
        ['Nhập số điện thoại quốc tế (+84…), bật "Waive SMS OTP (test account)" và "Save".', 'Enter an international phone (+84…), switch on "Waive SMS OTP (test account)" and "Save".'],
        ['Có thể đặt ngày sinh nếu tài khoản chưa có; ngày sinh sẵn có không bao giờ bị ghi đè.', 'You can set a date of birth if none exists; an existing one is never overwritten.'],
      ]],
      ['tip', 'Số điện thoại vẫn KHÔNG được xác minh và không có SMS nào được gửi. Bạn không thể áp dụng cho chính mình.', 'The phone stays NOT verified and no SMS is sent. You cannot apply this to your own account.'],
    ]},
    { id: 'reports', vi: 'Số liệu & báo cáo', en: 'Metrics & reports', blocks: [
      ['p', 'Ngoài số liệu thường, admin thấy: sự kiện chờ duyệt, tranh chấp chưa giải quyết, tuổi trung bình tồn đọng, sự kiện và đặt chỗ mới toàn nền tảng. Xuất CSV/JSON/PDF.', 'Besides the usual metrics, admins see: events pending review, unresolved disputes, average backlog age, new events and bookings platform-wide. Export CSV/JSON/PDF.'],
    ]},
  ],
};

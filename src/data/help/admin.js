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
    { id: 'team', vi: 'Đội ngũ quản trị', en: 'Admin Team', blocks: [
      ['ul', [
        ['"Invite Admin" gửi lời mời qua email dùng một lần; email người nhận được kiểm tra khi chấp nhận.', '"Invite Admin" sends a single-use email invite; the invitee\'s email is verified when accepting.'],
        ['Quyền quản lý admin là quyền riêng; admin mới không tự có, phải được người đang có quyền cấp.', 'Managing admins is a separate permission; a new admin does not get it automatically and must be granted it.'],
        ['Thu hồi admin sẽ hạ về người tham gia; không thể tự thu hồi mình hoặc thu hồi admin cuối cùng.', 'Revoking an admin demotes them to a participant; you cannot revoke yourself or the last admin.'],
      ]],
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

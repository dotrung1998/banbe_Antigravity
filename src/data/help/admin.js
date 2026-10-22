// Concise guide for admin accounts only. Blocks: see HelpReader.jsx.
export const ADMIN_GUIDE = {
  adminOnly: true,
  vi: 'Hướng dẫn cho Quản trị viên', en: 'Admin Guide',
  introVi: 'Ngắn gọn, chỉ dành cho quản trị viên. Tab "Admin" chỉ hiện với tài khoản có vai trò admin trên máy chủ.',
  introEn: 'Concise and for admins only. The "Admin" tab only appears for accounts with the server-side admin role.',
  sections: [
    { id: 'overview', vi: 'Tổng quan', en: 'Overview', blocks: [
      ['ul', [
        ['Tab "Admin" trong Tài khoản gồm: Review & Moderation, Admin Team, Metrics & Reports.', 'The "Admin" tab in Account has: Review & Moderation, Admin Team, Metrics & Reports.'],
        ['Review & Moderation gồm: Tranh Chấp Thanh Toán, Sự Kiện Chờ Duyệt, Quản lý sự kiện, Tài Khoản Thử Nghiệm, Sửa ngày sinh, Công tắc tính năng.', 'Review & Moderation has: Payment Disputes, Pending Events, Manage events, Test Accounts, Birthday corrections, Feature switches.'],
        ['Quyền do máy chủ kiểm soát. Ứng dụng không thể tự cấp quyền admin.', 'Permissions are enforced by the server. The app cannot grant itself admin.'],
        ['Mọi thao tác quản trị được ghi lại (gồm gỡ, khôi phục, xoá sự kiện và bật/tắt tính năng).', 'Admin actions are logged (including removing, restoring and deleting events, and feature switches).'],
      ]],
    ]},
    { id: 'events', vi: 'Duyệt sự kiện', en: 'Approving events', blocks: [
      ['ol', [
        ['Review & Moderation > "Pending Events" (có huy hiệu số lượng), hoặc "Duyệt ngay" từ một dòng trong Quản lý sự kiện (mở sẵn đúng sự kiện đó).', 'Review & Moderation > "Pending Events" (with a count badge), or "Review now" on a row in Manage events (opens with that event expanded).'],
        ['Mở thẻ sự kiện, kiểm tra mô tả, "Included", địa chỉ, riêng tư, điều kiện đặt chỗ, loại tổ chức tự khai và thông tin đăng ký kinh doanh (chưa được banbe xác minh).', 'Open the event card and check the description, "Included", address, visibility, reservation criteria, the self-declared organizer type and business details (not verified by banbe).'],
        ['"Approve ▪︎ publish" để đăng, hoặc "Reject" kèm lý do bắt buộc.', '"Approve ▪︎ publish" to go live, or "Reject" with a required reason.'],
      ]],
      ['tip', 'Host có thể nhắc tối đa 2 lần mỗi sự kiện. Không có hạn chót tự động, nên xử lý theo thứ tự cũ nhất trước.', 'Hosts can remind up to 2 times per event. There is no automatic deadline, so work oldest first.'],
    ]},
    { id: 'manage', vi: 'Quản lý sự kiện', en: 'Manage events', blocks: [
      ['p', 'Review & Moderation > "Quản lý sự kiện": gỡ một hoặc nhiều sự kiện khỏi ứng dụng. Đặt chỗ, thanh toán, hoàn tiền và lịch sử luôn được giữ.', 'Review & Moderation > "Manage events": take one or more events off the app. Bookings, payments, refunds and history are always kept.'],
      ['ul', [
        ['Tìm theo tên. Lọc Tất cả, Đang mở, Chờ duyệt, Nháp, Đã kết thúc, Đã huỷ, Đã gỡ, "Host đã xoá" (sự kiện mà host đã xoá tài khoản, có nhãn "Host đã xoá tài khoản").', 'Search by name. Filter All, Live, In review, Draft, Ended, Cancelled, Removed, "Host deleted" (events whose host deleted their account, badged "Host account deleted").'],
        ['Chạm vòng tròn để chọn, chạm phần còn lại để mở chi tiết: host, giờ bắt đầu, giá, chỗ, khu vực, ngày tạo/gửi, đặt chỗ (đang hiệu lực · từng có), hoàn tiền/tranh chấp, ID. "Mở rộng tất cả" / "Chọn tất cả".', 'Tap the circle to select. Tap the rest of the row for details: host, start, price, seats, area, created/submitted, bookings (active · ever), refunds/disputes, ID. "Expand all" / "Select all".'],
        ['Nút trong chi tiết: "Duyệt ngay" (sự kiện chờ duyệt), "Xem trang sự kiện" (đang mở, đã kết thúc, đã huỷ), "Sao chép ID".', 'Row actions: "Review now" (in-review events), "View event page" (live, ended, cancelled), "Copy ID".'],
      ]],
      ['h', 'Gỡ, khôi phục, xoá hẳn', 'Remove, restore, delete'],
      ['ul', [
        ['"Gỡ (N)": cần lý do (ít nhất 3 ký tự, có gợi ý Spam, Trùng lặp, Vi phạm quy định cộng đồng, Sự kiện thử nghiệm). Sự kiện biến mất khỏi Trang chính, Bản đồ, Tìm kiếm và trang host. Host nhận thông báo kèm lý do. Tối đa 100 sự kiện mỗi lần.', '"Remove (N)": needs a reason (at least 3 characters, suggestions Spam, Duplicate, Breaks community guidelines, Test event). The events disappear from Home, Map, Search and host pages. The host is notified with the reason. Up to 100 events at a time.'],
        ['"Khôi phục (N)": đưa sự kiện về trạng thái trước đó. Sự kiện đang mở mà đã qua giờ sẽ về "Đã kết thúc". Host được báo.', '"Restore (N)": returns events to their previous status. A live event whose time has passed comes back as Ended. The host is notified.'],
        ['"Xoá hẳn (N)": xoá vĩnh viễn, chỉ cho sự kiện đã gỡ và chưa từng có đặt chỗ ("Chưa từng có đặt chỗ, có thể xoá vĩnh viễn"). Sự kiện từng có đặt chỗ thì chỉ gỡ, không xoá được.', '"Delete (N)": permanent, only for removed events that were never booked ("Never booked, can be deleted permanently"). An event that ever had bookings can only be removed, never deleted.'],
      ]],
      ['h', 'Khi nào không gỡ được', 'When an event can\'t be removed'],
      ['p', 'Việc gỡ bị chặn khi tiền còn đang xử lý, và dòng sự kiện ghi rõ ai phải làm gì:', 'Removal is blocked while money is still in play, and the row says who has to do what:'],
      ['ul', [
        ['"N đặt chỗ đang hiệu lực, người tổ chức cần huỷ sự kiện".', '"N active bookings, the host must cancel the event".'],
        ['"N khoản hoàn tiền chưa xong, người tổ chức cần hoàn tất hoàn tiền".', '"N refunds not settled, the host must finish refunding".'],
        ['"N tranh chấp đang mở, xử lý trong Tranh Chấp Thanh Toán".', '"N open disputes, resolve it in Payment Disputes".'],
        ['Nếu host đã xoá tài khoản, banbe là bên phải huỷ sự kiện và liên hệ khách để hoàn tiền.', 'If the host deleted their account, banbe has to cancel the event and contact the guests to settle refunds.'],
      ]],
      ['h', 'Xoá sự kiện thử nghiệm (chỉ iOS, giai đoạn thử)', 'Test event wipe (iOS only, testing phase)'],
      ['ol', [
        ['Bật "Xoá sự kiện thử nghiệm (giai đoạn thử)" trong Công tắc tính năng.', 'Turn on "Test event wipe (testing phase)" in Feature switches.'],
        ['Trong Quản lý sự kiện, chọn sự kiện rồi nhấn "Xoá vĩnh viễn, thử nghiệm (N)" và xác nhận. Cách này xoá mọi sự kiện, kể cả sự kiện có đặt chỗ, cùng mọi dữ liệu liên quan, không cần lý do.', 'In Manage events, select the events, tap "Wipe permanently, testing (N)" and confirm. This erases any event, even booked ones, with everything tied to it, no reason needed.'],
        ['Tắt công tắc ngay sau khi dùng.', 'Turn the switch off again straight after.'],
      ]],
      ['tip', 'Không thể hoàn tác và chỉ dành cho dữ liệu thử nghiệm. Tính năng này sẽ bị gỡ trước khi phát hành chính thức.', 'This cannot be undone and is for test data only. It will be removed before public release.'],
    ]},
    { id: 'disputes', vi: 'Xử lý tranh chấp', en: 'Resolving disputes', blocks: [
      ['ol', [
        ['Review & Moderation > "Tranh Chấp Thanh Toán".', 'Review & Moderation > "Payment Disputes".'],
        ['Xem khách, Reference, Transaction ID, ảnh biên lai, lý do host từ chối và chat tranh chấp.', 'Review the guest, Reference, Transaction ID, receipt image, the host\'s rejection reason and the dispute chat.'],
        ['Tranh chấp thanh toán: "Buyer is right ▪︎ issue ticket" hoặc "Release seat". Thêm "Resolution note".', 'Payment dispute: "Buyer is right ▪︎ issue ticket" or "Release seat". Add a "Resolution note".'],
        ['Tranh chấp hoàn tiền cũng nằm trong hàng đợi này.', 'Refund disputes are in the same queue.'],
      ]],
      ['p', 'Sau quyết định, hai bên nhận thông báo và email. Nếu email lỗi, lỗi chỉ hiện trên màn hình của bạn lúc đó.', 'After a decision both parties get a notification and email. If the email fails the error shows only on your screen at that moment.'],
      ['p', 'Chat "không thấy tiền" chưa chuyển lên banbe tự đóng khi host xác nhận đã nhận tiền, khi đặt chỗ bị huỷ, hoặc sau 2 ngày. Chỉ tranh chấp đã chuyển lên banbe mới cần bạn quyết định.', 'A "can\'t find it" chat that was not escalated closes by itself when the host confirms the money, when the booking is cancelled, or after 2 days. Only disputes escalated to banbe need your decision.'],
    ]},
    { id: 'dobfix', vi: 'Sửa ngày sinh', en: 'Birthday corrections', blocks: [
      ['ol', [
        ['Vào tab "Admin" > "Review & Moderation" > "Birthday corrections".', 'Open the "Admin" tab > "Review & Moderation" > "Birthday corrections".'],
        ['Mỗi yêu cầu cho thấy người gửi, ngày sinh hiện tại, ngày được yêu cầu và lý do.', 'Each request shows who sent it, the current date of birth, the requested date and the reason.'],
        ['"Approve" ghi đè ngày sinh đã lưu. "Decline" giữ nguyên. Bạn có thể thêm ghi chú cho người dùng.', '"Approve" overwrites the stored date of birth. "Decline" keeps it. You can add a note for the user.'],
      ]],
      ['tip', 'Chỉ duyệt khi lý do hợp lý. Bạn không thể xử lý yêu cầu của chính mình, và mọi quyết định đều được ghi lại.', 'Approve only when the reason is credible. You cannot decide your own request, and every decision is logged.'],
    ]},
    { id: 'team', vi: 'Đội ngũ quản trị', en: 'Admin Team', blocks: [
      ['ul', [
        ['"Invite Admin" gửi lời mời qua email dùng một lần. Email người nhận được kiểm tra khi chấp nhận.', '"Invite Admin" sends a single-use email invite. The invitee\'s email is verified when accepting.'],
        ['Quyền quản lý admin là quyền riêng. Admin mới không tự có, phải được người đang có quyền cấp.', 'Managing admins is a separate permission. A new admin does not get it automatically and must be granted it.'],
        ['Thu hồi admin sẽ hạ về người tham gia. Không thể tự thu hồi mình hoặc thu hồi admin cuối cùng.', 'Revoking an admin demotes them to a participant. You cannot revoke yourself or the last admin.'],
        ['Người được mời thấy lời mời trong "Việc cần xử lý" (Trang chính và Tài khoản) và chấp nhận hoặc từ chối trong Đội ngũ quản trị. Lời mời hết hạn sau 7 ngày. Khi họ phản hồi, bạn nhận thông báo và danh sách tự làm mới.', 'The invitee sees the invite under "Things to do" (Home and Account) and accepts or declines it in Admin Team. Invites expire after 7 days. When they answer you get a notification and the list refreshes.'],
      ]],
    ]},
    { id: 'protected', vi: 'Tài khoản quản trị được bảo vệ', en: 'Protected admin', blocks: [
      ['p', 'Tài khoản banbetestadmin@gmail.com được bảo vệ: không ai có thể bỏ quyền quản lý đội ngũ hay gỡ vai trò quản trị của tài khoản này một cách trực tiếp.', 'The banbetestadmin@gmail.com account is protected: nobody can remove its team-management access or its admin role directly.'],
      ['ul', [
        ['Khi chỉ có dưới 3 quản trị viên (tính cả tài khoản này), việc gỡ bị chặn hoàn toàn.', 'With fewer than 3 admins in total (counting this account), removal is blocked outright.'],
        ['Từ 3 quản trị viên trở lên, một quản trị viên có quyền quản lý đội ngũ có thể mở cuộc bỏ phiếu: "Start a vote: remove team-management access" hoặc "Start a vote: remove as admin" ở dòng của tài khoản đó trong Current Admins.', 'With 3 or more admins, an admin who has team-management access can open a vote: "Start a vote: remove team-management access" or "Start a vote: remove as admin" on that account\'s row under Current Admins.'],
        ['Người bỏ phiếu là các quản trị viên có quyền quản lý đội ngũ, trừ chính tài khoản bị xét (không tự bỏ phiếu cho mình). Cần ít nhất 2 người bỏ phiếu. Admin mới phải được cấp quyền quản lý đội ngũ trước.', 'Voters are the admins who have team-management access, except the account in question (it does not vote on itself). At least 2 voters are needed. A new admin must be granted team-management access first.'],
        ['Cần đa số tuyệt đối của người bỏ phiếu (hơn một nửa) đồng ý. Người mở cuộc bỏ phiếu tính là một phiếu đồng ý. Mỗi người một phiếu và không đổi được.', 'A strict majority of the voters (more than half) must approve. The person who opens the vote counts as one yes. Each voter has one ballot and cannot change it.'],
        ['Cuộc bỏ phiếu hết hạn sau 72 giờ. Người mở có thể huỷ. Nếu số quản trị viên giảm xuống dưới 3 trước khi có kết quả thì việc gỡ bị huỷ.', 'A vote expires after 72 hours. Its opener can cancel it. If the admin count drops below 3 before it is decided, the removal is cancelled.'],
        ['Thông qua: quyền được gỡ ngay. Bị từ chối hoặc không còn đủ phiếu đồng ý: không có gì thay đổi.', 'If it passes the removal happens immediately. If it is rejected or can no longer reach a majority, nothing changes.'],
      ]],
      ['tip', 'Cuộc bỏ phiếu đang mở xuất hiện trong "Open Votes" của Đội ngũ quản trị, và bạn nhận thông báo khi có cuộc bỏ phiếu mới hoặc có kết quả.', 'Open votes appear under "Open Votes" in Admin Team, and you get a notification when a vote opens or is decided.'],
    ]},
    { id: 'test', vi: 'Tài Khoản Thử Nghiệm', en: 'Test Accounts', blocks: [
      ['ol', [
        ['Review & Moderation > "Tài Khoản Thử Nghiệm". Nhập email rồi nhấn "Tìm tài khoản" ở cuối màn hình, hoặc tìm theo tên hiển thị.', 'Review & Moderation > "Test Accounts". Enter an email and tap "Find account" at the bottom of the screen, or search by display name.'],
        ['Nhập số điện thoại quốc tế (+84…), bật "Waive SMS OTP (test account)" và "Save".', 'Enter an international phone (+84…), switch on "Waive SMS OTP (test account)" and "Save".'],
        ['Có thể đặt ngày sinh nếu tài khoản chưa có. Ngày sinh sẵn có không bao giờ bị ghi đè.', 'You can set a date of birth if none exists. An existing one is never overwritten.'],
      ]],
      ['h', 'Xoá tài khoản thử nghiệm', 'Deleting a test account'],
      ['p', 'Trong giai đoạn thử, "Xoá tài khoản" trên thẻ tài khoản xoá vĩnh viễn tài khoản đó cùng mọi dữ liệu liên quan, để dùng lại email khi thử luồng đăng ký. Thao tác hỏi xác nhận trước, giống như khi người dùng tự xoá tài khoản, và được ghi vào nhật ký quản trị.', 'During testing, "Delete account" on the account card permanently deletes that account and everything tied to it, so the email can be reused to test sign-up again. It asks first, works like a user deleting their own account, and is written to the admin log.'],
      ['ul', [
        ['Không xoá được tài khoản quản trị viên hoặc chính bạn.', 'Admin accounts and your own account can\'t be deleted here.'],
        ['Tài khoản còn sự kiện đang mở (đang mở hoặc chờ duyệt) bị từ chối. Huỷ hoặc gỡ sự kiện trước.', 'An account that still owns an open event (live or in review) is refused. Cancel or remove the event first.'],
        ['Sau khi xoá, email này đăng ký lại được ngay.', 'Afterwards the email can sign up again straight away.'],
      ]],
      ['h', 'Bỏ qua SMS cho tất cả', 'Bypass SMS for everyone'],
      ['p', 'Công tắc "Bỏ qua SMS cho tất cả" ở đầu màn hình bỏ bước SMS cho mọi tài khoản trong giai đoạn thử. Bật hoặc tắt đều hỏi xác nhận trước. Chỉ bước điện thoại được bỏ qua: ngày sinh vẫn bắt buộc và số điện thoại vẫn là chưa xác minh.', 'The "Bypass SMS for everyone" switch at the top skips the SMS step for every account during testing. Turning it on or off always asks first. Only the phone step is skipped: date of birth is still required and phones stay unverified.'],
      ['tip', 'Số điện thoại vẫn KHÔNG được xác minh và không có SMS nào được gửi. Bạn không thể áp dụng cho chính mình. Nhớ tắt "Bỏ qua SMS cho tất cả" trước khi phát hành chính thức.', 'The phone stays NOT verified and no SMS is sent. You cannot apply this to your own account. Remember to turn "Bypass SMS for everyone" off before public release.'],
    ]},
    { id: 'features', vi: 'Công tắc tính năng', en: 'Feature switches', blocks: [
      ['p', 'Review & Moderation > "Công tắc tính năng" bật/tắt một tính năng cho mọi người dùng cùng lúc. Công tắc chỉ đổi sau khi máy chủ chấp nhận, và mọi thay đổi đều được ghi lại.', 'Review & Moderation > "Feature switches" turns a feature on or off for every user at once. A switch only moves after the server accepts the change, and every change is logged.'],
      ['ul', [
        ['"Phần thưởng & huy hiệu": ẩn xu, chuỗi ngày, huy hiệu và mẫu móc khoá thưởng ở mọi nơi. Không xoá dữ liệu. Dòng trạng thái: "Đang hiện cho mọi người" hoặc "Đang ẩn với mọi người". Mặc định tắt.', '"Rewards & badges": hides coins, streaks, badges and reward keychain designs everywhere. No data is deleted. Status line: "Visible to everyone" or "Hidden from everyone". Off by default.'],
        ['"Xoá sự kiện thử nghiệm (giai đoạn thử)" (chỉ iOS): cho phép xoá vĩnh viễn trong Quản lý sự kiện. Mặc định tắt. Xem mục Quản lý sự kiện.', '"Test event wipe (testing phase)" (iOS only): allows permanent wipes in Manage events. Off by default. See Manage events.'],
      ]],
    ]},
    { id: 'reports', vi: 'Số liệu & báo cáo', en: 'Metrics & reports', blocks: [
      ['p', 'Với admin, Số liệu & Báo cáo đặt "Cần chú ý" lên đầu: sự kiện chờ duyệt ("Xem hàng chờ duyệt") và tranh chấp chưa giải quyết ("See open disputes"). Thẻ chính là số đặt chỗ mới toàn nền tảng.', 'For admins, Metrics & Reports puts "Needs attention" first: events pending review ("See the review queue") and unresolved disputes ("See open disputes"). The main card is new bookings platform-wide.'],
      ['ul', [
        ['"Phân tích" cho thấy hàng chờ đang mở (duyệt sự kiện / tranh chấp) và "Thời gian chờ của hàng chờ": dưới 1 ngày, 1–3 ngày, 3–7 ngày, trên 7 ngày.', '"Breakdown" shows the open backlog (event reviews / disputes) and "How long items have waited": under 1 day, 1–3 days, 3–7 days, 7+ days.'],
        ['Xuất như host: menu "⋯" cho PDF/JSON. Mở một số liệu để xuất CSV hoặc lưu ảnh biểu đồ.', 'Exports work as for hosts: the "⋯" menu for PDF/JSON. Open a metric to export CSV or save a chart image.'],
      ]],
    ]},
  ],
};

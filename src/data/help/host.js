// Guide for hosts (organizers). Blocks: see HelpReader.jsx.
export const HOST_GUIDE = {
  vi: 'Hướng dẫn cho Host (Người tổ chức)', en: 'Guide for Hosts',
  introVi: 'Từ bật chế độ tổ chức, tạo sự kiện, nhận thanh toán, soát vé đến hủy sự kiện, hoàn tiền và xử lý tranh chấp.',
  introEn: 'From turning on organizer mode and creating events to getting paid, checking guests in, cancelling, refunds and disputes.',
  sections: [
    { id: 'start', vi: 'Trở thành host', en: 'Becoming a host', blocks: [
      ['ol', [
        ['Vào Account, bật công tắc "Organizer mode" (tab Host xuất hiện; tắt bất cứ lúc nào).', 'Go to Account and switch on "Organizer mode" (the Host tab appears; turn it off any time).'],
        ['Điền tên và phần giới thiệu trang tổ chức của bạn khi tạo sự kiện đầu tiên.', 'Fill in your organizer name and about text when you create your first event.'],
        ['Chính sách yêu cầu host từ 18 tuổi trở lên.', 'The Terms require hosts to be 18 or older.'],
      ]],
      ['p', 'banbe hiện miễn phí cho host: không phí niêm yết hay phí giao dịch. Mọi sự kiện mới đều được quản trị viên banbe duyệt trước khi công khai.', 'banbe is currently free for hosts: no listing or transaction fees. Every new event is reviewed by a banbe admin before it goes public.'],
    ]},
    { id: 'create', vi: 'Tạo sự kiện', en: 'Creating an event', blocks: [
      ['p', 'Nhấn nút tạo sự kiện (dấu +) và điền các mục sau.', 'Tap the create (+) button and fill in the following.'],
      ['ul', [
        ['Tên, mô tả (bắt buộc) và "Event introduction" (phần giới thiệu dài).', 'Name, description (required) and "Event introduction" (longer write-up).'],
        ['Địa điểm: gõ rồi chọn một địa chỉ gợi ý; bắt buộc trước khi gửi.', 'Location: type and pick a suggested address; required before submitting.'],
        ['Ngày, giờ, giá vé và số chỗ (lớn hơn 0).', 'Date, time, ticket price and seats (more than 0).'],
        ['Riêng tư: Public hoặc Invite-only (chỉ người được mời xem và đặt; vẫn cần banbe duyệt).', 'Privacy: Public or Invite-only (only invited people can see and book; still needs banbe approval).'],
        ['Danh mục (1–2) và từ khóa tìm kiếm (tùy chọn).', 'Category (1–2) and search keywords (optional).'],
        ['Ảnh: JPEG/PNG/WebP, mỗi ảnh dưới 50 MB, tối đa 8 ảnh; đặt ảnh bìa và sắp xếp.', 'Photos: JPEG/PNG/WebP, each under 50 MB, up to 8; set a cover and reorder.'],
        ['"Included": tối đa 3 mục, cần ít nhất 1.', '"Included": up to 3 items, at least 1 required.'],
        ['"Opening message": lời chào đầu tiên khách thấy khi nhắn cho bạn (tiếng Việt và English, mỗi bản tối đa 500 ký tự; để trống sẽ dùng lời chào mặc định).', '"Opening message": the first message guests see when they chat with you (Vietnamese and English, 500 characters each; blank uses a default greeting).'],
      ]],
      ['p', 'Ghi rõ giá và điều khoản hoàn tiền trên trang sự kiện; đó là trách nhiệm của host.', 'State the price and refund terms on the event page; that is the host\'s responsibility.'],
      ['p', 'Bước "Review before submitting" có tab Private (Host) và Public preview. Nhấn "Confirm & submit" để gửi duyệt.', 'The "Review before submitting" step has Private (Host) and Public preview tabs. Tap "Confirm & submit" to send it for review.'],
      ['h', 'Nhập từ Excel', 'Importing from Excel'],
      ['p', 'Chọn "Upload a completed file" (.xlsx hoặc .zip có ảnh). Tệp chỉ điền sẵn biểu mẫu (một sự kiện mỗi tệp); bạn xem lại và gửi như bình thường. Tệp sai sẽ hiện danh sách lỗi từng trường.', 'Choose "Upload a completed file" (.xlsx, or a .zip with photos). The file only pre-fills the form (one event per file); you review and submit as usual. A wrong file shows a field-by-field error list.'],
    ]},
    { id: 'review', vi: 'Chờ duyệt, chỉnh sửa & rút lại', en: 'Review, fixes & withdrawing', blocks: [
      ['ul', [
        ['"Submitted events" trên Dashboard/Account cho thấy "Waiting for Banbe to review" hoặc "Needs fixing".', '"Submitted events" shows "Waiting for Banbe to review" or "Needs fixing".'],
        ['Bị từ chối: đọc lý do rồi "Fix & resubmit".', 'Rejected: read the reason, then "Fix & resubmit".'],
        ['Chờ lâu: gửi nhắc quản trị viên (tối đa 2 lần mỗi sự kiện).', 'Waiting a long time: remind the admins (max 2 times per event).'],
        ['"Withdraw event" rút lại sự kiện đang chờ duyệt (kèm lý do).', '"Withdraw event" pulls back a pending event (with a reason).'],
      ]],
      ['tip', 'Thời gian duyệt không được cam kết; hãy gửi sớm trước ngày diễn ra.', 'Review time is not guaranteed; submit well before the event date.'],
    ]},
    { id: 'payout', vi: 'Nhận thanh toán & tài liệu', en: 'Getting paid & documents', blocks: [
      ['p', 'banbe không giữ tiền: khách chuyển thẳng cho bạn.', 'banbe does not hold money: guests pay you directly.'],
      ['ol', [
        ['Account > Event Operations & Payments > "Getting Paid": nhập Bank, tên ngân hàng, số tài khoản, tên chủ tài khoản hoặc MoMo.', 'Account > Event Operations & Payments > "Getting Paid": enter Bank, bank name, account number, account name, or MoMo.'],
        ['Thêm địa chỉ, mã số thuế (tùy chọn) và "Note to guests".', 'Add an address, tax code (optional) and a "Note to guests".'],
        ['Có thể tải một mã QR thanh toán (mỗi tổ chức một mã) để khách quét.', 'You can upload one payment QR (one per organizer) for guests to scan.'],
      ]],
      ['h', 'Hóa đơn / biên lai', 'Invoices / receipts'],
      ['p', 'Trong "Attendance", sau khi thấy tiền về, đánh dấu khách đã trả rồi "Upload receipt" (tệp của chính bạn). "Replace receipt" cần lý do khách sẽ thấy; bản cũ tự xóa sau 24 giờ. Tài liệu được lưu 12 tháng.', 'In "Attendance", once you see the money, mark the guest paid and "Upload receipt" (your own file). "Replace receipt" needs a reason the guest will see; the old copy is deleted after 24 hours. Documents are kept 12 months.'],
    ]},
    { id: 'confirm', vi: 'Xác nhận thanh toán của khách', en: 'Confirming guest payments', blocks: [
      ['p', 'Vào Account > Event Operations & Payments > "Awaiting Verification". Mỗi dòng cho thấy khách, số vé, Reference, Transaction ID và ảnh biên lai.', 'Go to Account > Event Operations & Payments > "Awaiting Verification". Each row shows the guest, ticket count, Reference, Transaction ID and receipt image.'],
      ['ul', [
        ['"Money received": xác nhận và cấp vé QR cho khách.', '"Money received": confirms and issues the guest\'s QR ticket.'],
        ['"Can\'t find it": báo không thấy tiền; khách nhận tin trong chat thường.', '"Can\'t find it": says you cannot see the money; the guest gets a message in the normal chat.'],
        ['"Escalate to banbe": nhờ quản trị viên quyết định, mở chat tranh chấp tạm thời.', '"Escalate to banbe": asks admins to decide and opens a temporary dispute chat.'],
        ['Sự kiện cần duyệt khách: "Accept" hoặc "Reject" yêu cầu; "Cancel booking" trả chỗ về và thông báo cho khách.', 'Approval-required events: "Accept" or "Reject" requests; "Cancel booking" frees the seat and notifies the guest.'],
      ]],
      ['tip', 'Bạn nên phản hồi trong khoảng 1 giờ. banbe KHÔNG tự xác nhận thay bạn: ghế của khách bị khóa cho tới khi bạn hành động. Quá hạn sẽ có nhắc nhở và leo thang.', 'Aim to respond within about 1 hour. banbe does NOT auto-confirm for you: the guest\'s seat stays locked until you act. Overdue items trigger reminders and escalation.'],
    ]},
    { id: 'checkin', vi: 'Soát vé & danh sách khách', en: 'Check-in & the guest list', blocks: [
      ['ol', [
        ['Từ Dashboard, mở sự kiện > "Check-in" (Guest check-in).', 'From the Dashboard, open the event > "Check-in" (Guest check-in).'],
        ['"Scan QR" (cho phép trình duyệt dùng camera) và quét mã của từng người; kiểm tra tuổi/ngày sinh hiển thị rồi "Confirm".', '"Scan QR" (allow camera access) and scan each person\'s code; check the age/date of birth shown, then "Confirm".'],
        ['Hoặc chạm "Here ✓" / "Not yet" thủ công; "Undo check-in" để hoàn tác.', 'Or tap "Here ✓" / "Not yet" manually; "Undo check-in" reverts it.'],
      ]],
      ['ul', [
        ['Mỗi QR chỉ cho vào đúng một người; QR của cả đơn đặt chỗ bị từ chối ("Scan each attendee\'s own QR").', 'Each QR admits one person only; a whole-booking QR is refused ("Scan each attendee\'s own QR").'],
        ['Lỗi thường gặp: mã không hợp lệ, đã check-in, mã đã bị thay do tặng vé, quét quá nhiều lần.', 'Common errors: invalid code, already checked in, code replaced because the ticket was gifted, too many attempts.'],
        ['"Email ticket holders" gửi thông báo cho người giữ vé.', '"Email ticket holders" sends a message to ticket holders.'],
      ]],
    ]},
    { id: 'cancel', vi: 'Hủy sự kiện & email xin lỗi', en: 'Cancelling an event & apology emails', blocks: [
      ['ol', [
        ['Attendance > "Cancel event".', 'Attendance > "Cancel event".'],
        ['Chọn một mẫu lời xin lỗi (ngoài ý muốn, địa điểm, ít người đăng ký, an toàn), xem trước rồi xác nhận. Tất cả đặt chỗ bị hủy và các yêu cầu hoàn tiền được tạo.', 'Pick an apology template (unforeseen, venue, low sign-ups, safety), preview, then confirm. All bookings are cancelled and refund claims are created.'],
        ['Mỗi người giữ vé có một bản nháp email cá nhân hóa mở trong ứng dụng email CỦA BẠN; banbe không tự gửi.', 'Each ticket holder gets a personalised draft that opens in YOUR mail app; banbe does not send it.'],
      ]],
    ]},
    { id: 'refunds', vi: 'Hoàn tiền cho khách', en: 'Refunding guests', blocks: [
      ['ol', [
        ['Chờ khách chọn tài khoản nhận (chỉ khi đó khoản hoàn mới đủ điều kiện).', 'Wait for the guest to choose a destination (only then is the claim eligible).'],
        ['Mở Refund Center, chuyển khoản theo thông tin khách chọn.', 'Open the Refund Center and transfer using the guest\'s chosen details.'],
        ['Chọn các khoản rồi "Confirm transfers sent" (hàng loạt) hoặc "Mark refund sent" từng khoản; có thể thêm ghi chú và chứng từ chuyển khoản.', 'Select claims and use "Confirm transfers sent" (batch) or "Mark refund sent" per claim; add a note and transfer proof if you like.'],
      ]],
      ['ul', [
        ['Hạn hoàn tiền là 3 ngày làm việc kể từ lúc hủy.', 'The refund is due 3 business days after cancellation.'],
        ['Khách có 7 ngày để xác nhận; nếu không phản hồi, hệ thống tự ghi nhận đã nhận.', 'Guests have 7 days to confirm; if they do nothing it is auto-confirmed.'],
        ['Khách báo chưa nhận: "Resend transfer info". Bạn có 48 giờ phản hồi khi có tranh chấp hoàn tiền.', 'Guest says it did not arrive: "Resend transfer info". You have 48 hours to respond to a refund dispute.'],
      ]],
    ]},
    { id: 'disputes', vi: 'Tranh chấp', en: 'Disputes', blocks: [
      ['ul', [
        ['Tranh chấp thanh toán: "Escalate to banbe" kèm mô tả; quản trị viên đọc chat và bằng chứng rồi quyết định ("Buyer is right" cấp vé, hoặc "Release seat").', 'Payment dispute: "Escalate to banbe" with a description; admins read the chat and proof, then decide ("Buyer is right" issues the ticket, or "Release seat").'],
        ['Tranh chấp hoàn tiền: mở "Open dispute chat" từ hộp thư (dòng "Dispute in progress"); đính kèm tệp; "Close dispute" khi xong.', 'Refund dispute: open "Open dispute chat" from the inbox ("Dispute in progress" row); attach files; "Close dispute" when done.'],
        ['Có thể tải transcript; bản của host được giữ đến khi dữ liệu bị xóa (7 ngày sau khi đóng).', 'You can download the transcript; the host copy is kept until the data is purged (7 days after closing).'],
      ]],
    ]},
    { id: 'invite', vi: 'Sự kiện chỉ mời & khảo sát', en: 'Invite-only events & surveys', blocks: [
      ['ul', [
        ['Invite-only: chọn khi tạo sự kiện; chỉ người được mời mới xem và đặt được. Hiện chưa có màn hình quản lý lời mời cho host.', 'Invite-only: choose it when creating; only invited people can see and book. There is no host screen to manage invites yet.'],
        ['Khảo sát (Account > Surveys & Event Ideas): "+ Create a new survey", rồi "Publish", chia sẻ link hoặc story, "Close early" / "Archive".', 'Surveys (Account > Surveys & Event Ideas): "+ Create a new survey", then "Publish", share the link or a story, "Close early" / "Archive".'],
        ['Khi khảo sát đóng, gợi ý sự kiện có thể được tạo; "Use This Idea" mở biểu mẫu tạo sự kiện đã điền sẵn.', 'When a survey closes, event suggestions may be generated; "Use This Idea" opens a pre-filled create form.'],
      ]],
    ]},
    { id: 'team', vi: 'Đội ngũ, hồ sơ host & thẻ chia sẻ', en: 'Team, host profile & share card', blocks: [
      ['ul', [
        ['Team: mời thành viên theo @handle với vai trò công khai; trạng thái Pending / Joined / Declined / Removed; có thể ẩn khỏi trang công khai.', 'Team: invite members by @handle with a public role; statuses Pending / Joined / Declined / Removed; they can be hidden from the public page.'],
        ['"Credit an event contribution" ghi nhận ai đã giúp tổ chức sự kiện ("Helped organize" trên hồ sơ họ).', '"Credit an event contribution" records who helped organize an event ("Helped organize" on their profile).'],
        ['Hồ sơ host (/org/<id>): theo dõi, sự kiện, ảnh, huy hiệu "Verified" do banbe gán thủ công; "Request" để xin xác minh.', 'Host profile (/org/<id>): followers, events, photos, a "Verified" badge set manually by banbe; "Request" to ask for verification.'],
        ['Thẻ chia sẻ: chọn màu/nền, "Save card" để công bố, tải ảnh hoặc sao chép link.', 'Share card: pick colours/background, "Save card" to publish, download the image or copy the link.'],
        ['Thành viên team có thể chạy cửa và chat; chỉ chủ hồ sơ mới sửa sự kiện, hủy sự kiện và quản lý thành viên.', 'Team members can run the door and chat; only the profile owner edits events, cancels them and manages members.'],
      ]],
    ]},
    { id: 'reports', vi: 'Số liệu & báo cáo', en: 'Metrics & reports', blocks: [
      ['p', 'Account > "Metrics & Reports": số sự kiện đã đăng, chỗ đã xác nhận, đã check-in, số tiền đã xác nhận, hoàn tiền phải trả/quá hạn. Xuất "Download CSV", JSON, PDF hoặc "Save image".', 'Account > "Metrics & Reports": published events, confirmed seats, checked in, confirmed payment amount, refunds owed/overdue. Export "Download CSV", JSON, PDF or "Save image".'],
    ]},
    { id: 'tips', vi: 'Lưu ý quan trọng', en: 'Important reminders', blocks: [
      ['ul', [
        ['Không thể xóa tài khoản khi còn sự kiện đang mở.', 'You cannot delete your account while you own an open event.'],
        ['Thời gian giữ chỗ 30 phút không tùy chỉnh được.', 'The 30-minute hold cannot be customised.'],
        ['Hãy xác nhận thanh toán nhanh: banbe không tự xác nhận.', 'Confirm payments promptly: banbe never confirms automatically.'],
        ['Không chuyển tiền hộ qua banbe; mọi giao dịch diễn ra giữa bạn và khách.', 'banbe does not move money; all payments are between you and your guests.'],
      ]],
    ]},
  ],
};

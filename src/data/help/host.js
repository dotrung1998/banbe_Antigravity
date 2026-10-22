// Guide for hosts (organizers). Blocks: see HelpReader.jsx.
export const HOST_GUIDE = {
  vi: 'Hướng dẫn cho Host (Người tổ chức)', en: 'Guide for Hosts',
  introVi: 'Từ bật chế độ tổ chức, tạo sự kiện, nhận thanh toán, soát vé, gửi thông báo đến hủy sự kiện, hoàn tiền và xử lý tranh chấp.',
  introEn: 'From turning on organizer mode and creating events to getting paid, checking guests in, announcements, cancelling, refunds and disputes.',
  sections: [
    { id: 'start', vi: 'Trở thành host', en: 'Becoming a host', blocks: [
      ['ol', [
        ['Vào Account, bật công tắc "Organizer mode". Tab Host trong Tài khoản và nút tạo sự kiện (+) xuất hiện. Tắt bất cứ lúc nào.', 'Go to Account and switch on "Organizer mode". The Host tab in Account and the create (+) button appear. Turn it off any time.'],
        ['Ngay khi bật chế độ tổ chức, banbe tự tạo trang tổ chức cho bạn với tên mặc định "<tên hiển thị> Events" (hoặc "Sự kiện của tôi" nếu chưa có tên). Bạn có thể đổi tên bất cứ lúc nào. Tên không lấy từ email hay số điện thoại và không có nghĩa là đã được xác minh. Nếu thẻ Host báo lỗi, nhấn "Retry". Thành viên nhóm của tổ chức khác không bị tạo thêm trang.', 'As soon as you switch on organizer mode, banbe creates your organizer page with a default name "<display name> Events" (or "My events" if you have no name). You can rename it any time. The name is never taken from your email or phone and does not mean you are verified. If the Host card shows an error, tap "Retry". Members of another organizer\'s team do not get a second page created.'],
        ['Các mục dành cho host (Dashboard, thanh toán, hoàn tiền, số liệu…) nằm trong tab Host của Tài khoản.', 'Host items (Dashboard, payments, refunds, metrics…) live in the Host tab of Account.'],
        ['Chính sách yêu cầu host từ 18 tuổi trở lên.', 'The Terms require hosts to be 18 or older.'],
      ]],
      ['p', 'banbe hiện miễn phí cho host: không phí niêm yết hay phí giao dịch. Mọi sự kiện mới đều được quản trị viên banbe duyệt trước khi công khai.', 'banbe is currently free for hosts: no listing or transaction fees. Every new event is reviewed by a banbe admin before it goes public.'],
    ]},
    { id: 'create', vi: 'Tạo sự kiện', en: 'Creating an event', blocks: [
      ['p', 'Nhấn nút tạo sự kiện (+). Biểu mẫu có 5 bước có tên, luôn bắt đầu ở bước Host. Vòng tiến trình cho thấy bạn đã đi được bao xa. Mỗi bước có Quay lại / Tiếp và dòng "Còn thiếu ở bước này:".', 'Tap the create (+) button. The form has 5 named steps and always opens on Host. A progress ring shows how far along you are. Each step has Back / Next and a "Still needed here:" line.'],
      ['ol', [
        ['Host: điền sẵn từ hồ sơ người tổ chức ("✓ Đã điền từ hồ sơ người tổ chức của bạn"). Kiểm tra rồi "Ổn rồi · Tiếp: Cơ bản". Lần đầu, hãy viết phần giới thiệu trang tổ chức.', 'Host: pre-filled from your organizer profile ("✓ Filled from your organizer profile"). Check it, then "Looks good · Next: Basics". On your first event, write your organizer about text.'],
        ['Cơ bản: tên, mô tả (bắt buộc), "Event introduction", danh mục (1–2), từ khóa tìm kiếm (tùy chọn), "Included" (1–3 mục) và "Opening message" (lời chào đầu tiên khi khách nhắn, mỗi ngôn ngữ tối đa 500 ký tự, để trống dùng lời chào mặc định).', 'Basics: name, description (required), "Event introduction", category (1–2), search keywords (optional), "Included" (1–3 items) and "Opening message" (the first message guests see when they chat with you, 500 characters per language, blank uses a default).'],
        ['Thời gian & nơi: ngày, giờ và địa điểm (gõ rồi chọn địa chỉ gợi ý).', 'When & where: date, time and location (type and pick a suggested address).'],
        ['Vé: giá (có ô "Miễn phí"), số chỗ (lớn hơn 0), riêng tư (Public hoặc Invite-only) và "Điều kiện đặt chỗ" (xem bên dưới).', 'Tickets: price (with a "Free" tile), seats (more than 0), privacy (Public or Invite-only) and "Reservation criteria" (see below).'],
        ['Ảnh: JPEG/PNG/WebP, mỗi ảnh dưới 50 MB, từ 3 đến 8 ảnh. Đặt ảnh bìa và sắp xếp.', 'Photos: JPEG/PNG/WebP, each under 50 MB, 3 to 8 photos. Set a cover and reorder.'],
      ]],
      ['h', 'Điền sẵn thông minh', 'Smart defaults'],
      ['ul', [
        ['Host quay lại: giờ và giá được điền sẵn từ sự kiện gần nhất của bạn. Sự kiện đầu tiên: banbe chọn tối thứ Bảy tới lúc 19:00. "Bắt đầu trống" để xoá. Số chỗ và địa điểm không bao giờ được điền sẵn.', 'Returning hosts: time and price are pre-filled from your last event. First event: banbe picks next Saturday at 19:00. "Start blank" clears it. Seats and location are never pre-filled.'],
        ['Khi có đủ dữ liệu, bước Vé cho thấy "Sự kiện tương tự: X–Y", thanh kéo giá ("‹ Kéo để chọn giá ›") trên biểu đồ giá và ước tính số khách / doanh thu (trước mọi khoản phí).', 'When there is enough data, the Tickets step shows "Similar events: X–Y", a price slider ("‹ Drag to set your price ›") over a price chart, and an estimate of guests / revenue (before any fees).'],
        ['Rời bản nháp có dữ liệu sẽ hỏi trước khi bỏ.', 'Leaving a draft with input asks before discarding it.'],
      ]],
      ['h', 'Công thức thành công', 'Recipe for success'],
      ['ul', [
        ['Mỗi bước có "Công thức x/10 · Xem gợi ý". Mười thành phần: tên, ảnh, mô tả, bao gồm, từ khoá, giá, số chỗ, thời điểm, thời gian chuẩn bị và lời chào. Gợi ý dựa trên các sự kiện tương tự khi có đủ dữ liệu, không thì là gợi ý chung.', 'Every step shows "Recipe x/10 · See tips". The ten ingredients: title, photos, description, included, keywords, price, seats, timing, lead time and greeting. Tips use similar events when there is enough data, otherwise general advice.'],
        ['"Sửa" đưa bạn thẳng tới ô cần sửa, làm nổi bật và đặt con trỏ vào đó. Công thức không bao giờ bắt buộc để gửi.', '"Fix" takes you straight to that field, highlights it and puts the cursor in it. The recipe is never required to submit.'],
        ['Mục tiêu (tùy chọn) "Điều quan trọng nhất với sự kiện này?": Kín mọi chỗ, Xây nhóm khách quen, Thử ý tưởng mới, Nhỏ & cao cấp. Chỉ bạn thấy.', 'Optional goal "What matters most for this event?": Fill every seat, Build a regular crowd, Try a new idea, Small & premium. Only you see it.'],
      ]],
      ['h', 'Điều kiện đặt chỗ', 'Reservation criteria'],
      ['p', '"Mọi người" hoặc "Người đã khai báo…" sở thích và/hoặc mục tiêu nhất định ("Một trong số này" hoặc "Tất cả những mục này"). Đây là thông tin khách tự khai, không được xác minh, và không bao giờ dùng ngân sách, lịch, ngôn ngữ hay tuổi. Đổi điều kiện không hủy các đặt chỗ đã có. Trang sự kiện hiện "Ai có thể đặt: …".', '"Everyone" or "Only people who declare…" certain interests and/or goals ("Any of these" or "All of these"). It is self-declared and unverified, and never uses budget, schedule, language or age. Changing it never cancels existing bookings. The event page shows "Who can reserve: …".'],
      ['h', 'Xem lại & gửi', 'Review & submit'],
      ['ul', [
        ['"Xem lại sự kiện của bạn": nếu còn thiếu, bạn được đưa tới ô thiếu đầu tiên ("Còn thiếu:").', '"Review your event": if anything is missing you are taken to the first missing field ("Still needed:").'],
        ['"Xem lại trước khi gửi" có tab "Nội bộ (Host)" (Tên sự kiện, Công thức thành công, Chi tiết sự kiện, Bao gồm, Thứ tự ảnh) và "Xem trước công khai", đúng trang khách sẽ thấy, các nút không bấm được.', '"Review before submitting" has a "Private (Host)" tab (Event name, Recipe for success, Event details, Included, Photo order) and a "Public preview" tab, exactly the page guests will see, with buttons inactive.'],
        ['Nhấn "Xác nhận và gửi". Màn hình "Đã gửi sự kiện!" xác nhận: banbe duyệt → sự kiện được công khai và bạn được báo.', 'Tap "Confirm & submit". "Event submitted!" confirms it: banbe reviews it → it goes live and you are notified.'],
      ]],
      ['p', 'Ghi rõ giá và điều khoản hoàn tiền trên trang sự kiện. Đó là trách nhiệm của host.', 'State the price and refund terms on the event page. That is the host\'s responsibility.'],
      ['h', 'Nhập từ Excel', 'Importing from Excel'],
      ['p', 'Chọn "Upload a completed file" (.xlsx hoặc .zip có ảnh). Tệp chỉ điền sẵn biểu mẫu (một sự kiện mỗi tệp). Bạn xem lại và gửi như bình thường. Tệp sai sẽ hiện danh sách lỗi từng trường.', 'Choose "Upload a completed file" (.xlsx, or a .zip with photos). The file only pre-fills the form (one event per file). You review and submit as usual. A wrong file shows a field-by-field error list.'],
    ]},
    { id: 'review', vi: 'Dashboard, chờ duyệt & rút lại', en: 'Dashboard, review & withdrawing', blocks: [
      ['p', 'Dashboard có "Sự kiện sắp tới", rồi các mục thu gọn có đếm số: "Sự kiện đã gửi", "Sự kiện đã qua" và "Đội ngũ". Mở "Sự kiện đã gửi" để thấy mục "Needs fixing".', 'The Dashboard shows "Upcoming events", then collapsed sections with counts: "Submitted events", "Past events" and "Team". Expand "Submitted events" to see anything that "Needs fixing".'],
      ['ul', [
        ['"Sự kiện đã gửi" cho thấy "Waiting for Banbe to review" hoặc "Needs fixing".', '"Submitted events" shows "Waiting for Banbe to review" or "Needs fixing".'],
        ['Bị từ chối: đọc lý do rồi "Fix & resubmit".', 'Rejected: read the reason, then "Fix & resubmit".'],
        ['Chờ lâu: gửi nhắc quản trị viên (tối đa 2 lần mỗi sự kiện).', 'Waiting a long time: remind the admins (max 2 times per event).'],
        ['"Withdraw event" rút lại sự kiện đang chờ duyệt (kèm lý do).', '"Withdraw event" pulls back a pending event (with a reason).'],
        ['"Sự kiện đã qua" chỉ gồm sự kiện đã thực sự diễn ra. Sự kiện đã hủy không nằm ở đây. Hoàn tiền cho sự kiện đã hủy xử lý ở Trung tâm hoàn tiền (xem mục Hoàn tiền cho khách).', '"Past events" only lists events that actually took place. Cancelled events are not there. Refunds for a cancelled event are handled in the Refund Center (see Refunding guests).'],
      ]],
      ['h', 'Bị banbe gỡ', 'Removed by banbe'],
      ['p', 'Nếu quản trị viên gỡ một sự kiện, bạn nhận thông báo kèm lý do và Dashboard hiện ô "Đã bị banbe gỡ": sự kiện không còn hiển thị với khách, nhưng mọi đặt chỗ, thanh toán và lịch sử được giữ nguyên. Bạn không tự khôi phục được. Liên hệ banbe nếu bạn nghĩ đó là nhầm lẫn. Nếu được khôi phục, bạn cũng được báo.', 'If an admin removes an event, you get a notification with the reason and the Dashboard shows a "Removed by banbe" box: guests no longer see it, but all bookings, payments and history are kept. You cannot undo it yourself. Contact banbe if you think it is a mistake. You are notified if it is restored.'],
      ['tip', 'Thời gian duyệt không được cam kết. Hãy gửi sớm trước ngày diễn ra.', 'Review time is not guaranteed. Submit well before the event date.'],
    ]},
    { id: 'payout', vi: 'Nhận thanh toán & tài liệu', en: 'Getting paid & documents', blocks: [
      ['p', 'banbe không giữ tiền: khách chuyển thẳng cho bạn.', 'banbe does not hold money: guests pay you directly.'],
      ['ol', [
        ['Account > Event Operations & Payments > "Getting Paid": nhập Bank, tên ngân hàng, số tài khoản, tên chủ tài khoản hoặc MoMo.', 'Account > Event Operations & Payments > "Getting Paid": enter Bank, bank name, account number, account name, or MoMo.'],
        ['Thêm địa chỉ, mã số thuế (tùy chọn) và "Note to guests".', 'Add an address, tax code (optional) and a "Note to guests".'],
        ['Có thể tải một mã QR thanh toán (mỗi tổ chức một mã) để khách quét.', 'You can upload one payment QR (one per organizer) for guests to scan.'],
      ]],
      ['h', 'Hóa đơn / biên lai', 'Invoices / receipts'],
      ['p', 'Trong "Attendance", sau khi thấy tiền về, đánh dấu khách đã trả rồi "Upload receipt" (tệp của chính bạn). "Replace receipt" cần lý do khách sẽ thấy. Bản cũ tự xóa sau 24 giờ. Tài liệu được lưu 12 tháng.', 'In "Attendance", once you see the money, mark the guest paid and "Upload receipt" (your own file). "Replace receipt" needs a reason the guest will see. The old copy is deleted after 24 hours. Documents are kept 12 months.'],
    ]},
    { id: 'confirm', vi: 'Xác nhận thanh toán của khách', en: 'Confirming guest payments', blocks: [
      ['p', 'Vào Account > Event Operations & Payments > "Awaiting Verification". Mỗi dòng cho thấy khách, số vé, Reference, Transaction ID và ảnh biên lai.', 'Go to Account > Event Operations & Payments > "Awaiting Verification". Each row shows the guest, ticket count, Reference, Transaction ID and receipt image.'],
      ['ul', [
        ['"Money received": xác nhận và cấp vé QR cho khách.', '"Money received": confirms and issues the guest\'s QR ticket.'],
        ['"Can\'t find it": báo không thấy tiền. Một chat tạm thời mở ra với khách và có 2 ngày để làm rõ. Nếu sau đó bạn thấy tiền và nhấn "Money received", vé được cấp và chat tự đóng. Hết 2 ngày mà không ai chuyển lên banbe, chỗ được trả lại kho.', '"Can\'t find it": says you cannot see the money. A temporary chat opens with the guest and you both have 2 days to sort it out. If you then find the money and tap "Money received", the ticket is issued and the chat closes by itself. If 2 days pass and nobody escalates to banbe, the seat goes back on sale.'],
        ['"Escalate to banbe": nhờ quản trị viên quyết định. Chat tranh chấp vẫn mở cho đến khi banbe quyết định.', '"Escalate to banbe": asks admins to decide. The dispute chat stays open until banbe decides.'],
        ['Sự kiện cần duyệt khách: "Accept" hoặc "Reject" yêu cầu. "Cancel booking" trả chỗ về và thông báo cho khách.', 'Approval-required events: "Accept" or "Reject" requests. "Cancel booking" frees the seat and notifies the guest.'],
      ]],
      ['tip', 'Bạn nên phản hồi trong khoảng 1 giờ. banbe KHÔNG tự xác nhận thay bạn: ghế của khách bị khóa cho tới khi bạn hành động. Quá hạn sẽ có nhắc nhở và leo thang.', 'Aim to respond within about 1 hour. banbe does NOT auto-confirm for you: the guest\'s seat stays locked until you act. Overdue items trigger reminders and escalation.'],
    ]},
    { id: 'checkin', vi: 'Soát vé & danh sách khách', en: 'Check-in & the guest list', blocks: [
      ['p', 'Sự kiện bắt đầu trong 24 giờ tới hoặc đang diễn ra được đưa lên đầu Dashboard với viền vàng, nhãn "Sắp diễn ra" / "Đang diễn ra" và nút "Điểm danh". Thẻ Host trong Tài khoản cũng hiện nút "Điểm danh" khi sự kiện đến gần.', 'Events starting within 24 hours or happening now move to the top of the Dashboard with a gold border, a "Starting soon" / "Happening now" tag and a "Check-in" button. The Host card in Account also shows "Check-in" when an event is near.'],
      ['ol', [
        ['Từ Dashboard, mở sự kiện > "Check-in" (Guest check-in).', 'From the Dashboard, open the event > "Check-in" (Guest check-in).'],
        ['"Scan QR" (cho phép dùng camera) và quét mã của từng người. Kiểm tra tuổi/ngày sinh hiển thị rồi "Confirm".', '"Scan QR" (allow camera access) and scan each person\'s code. Check the age/date of birth shown, then "Confirm".'],
        ['Hoặc chạm "Here ✓" / "Not yet" thủ công. "Undo check-in" để hoàn tác.', 'Or tap "Here ✓" / "Not yet" manually. "Undo check-in" reverts it.'],
      ]],
      ['ul', [
        ['Mỗi QR chỉ cho vào đúng một người. QR của cả đơn đặt chỗ bị từ chối ("Scan each attendee\'s own QR").', 'Each QR admits one person only. A whole-booking QR is refused ("Scan each attendee\'s own QR").'],
        ['Lỗi thường gặp: mã không hợp lệ, đã check-in, mã đã bị thay do tặng vé, quét quá nhiều lần.', 'Common errors: invalid code, already checked in, code replaced because the ticket was gifted, too many attempts.'],
        ['"Email ticket holders" gửi thông báo cho người giữ vé.', '"Email ticket holders" sends a message to ticket holders.'],
      ]],
    ]},
    { id: 'announce', vi: 'Gửi thông báo cho khách', en: 'Announcing to guests', blocks: [
      ['p', 'Từ 24 giờ trước đến 12 giờ sau giờ bắt đầu, trang Attendance có thẻ đỏ "Gửi thông báo cho khách" để báo nhanh mọi người giữ vé (đổi phòng, đến muộn, cửa đã mở…).', 'From 24 hours before to 12 hours after the start, Attendance shows a red "Announce to guests" card to quickly tell every ticket holder something (room change, running late, doors open…).'],
      ['ol', [
        ['Tự viết tin nhắn, hoặc chọn mẫu ở "Gửi nhanh" (có "Tìm mẫu thông báo…" và các nhóm mẫu), rồi sửa nếu cần.', 'Write your own message, or pick a template under "Quick send" (with "Search templates…" and template groups), then edit it if you like.'],
        ['Nhấn "Gửi thông báo" → "Gửi cho tất cả người giữ vé?" → "Gửi ngay".', 'Tap "Send announcement" → "Send to all ticket holders?" → "Send now".'],
      ]],
      ['ul', [
        ['Khách nhận một thông báo và một tin nhắn nổi bật màu đỏ "📣 Thông báo từ host" trong chat.', 'Guests get a notification and a red "📣 Host announcement" message in the chat.'],
        ['Tối đa 10 thông báo mỗi sự kiện trong một giờ. Bạn không nhận thông báo của chính mình.', 'Up to 10 announcements per event per hour. You do not receive your own.'],
      ]],
    ]},
    { id: 'cancel', vi: 'Hủy sự kiện & email xin lỗi', en: 'Cancelling an event & apology emails', blocks: [
      ['ol', [
        ['Attendance > "Cancel event".', 'Attendance > "Cancel event".'],
        ['Chọn một mẫu lời xin lỗi (ngoài ý muốn, địa điểm, ít người đăng ký, an toàn), xem trước rồi xác nhận. Tất cả đặt chỗ bị hủy và các yêu cầu hoàn tiền được tạo.', 'Pick an apology template (unforeseen, venue, low sign-ups, safety), preview, then confirm. All bookings are cancelled and refund claims are created.'],
        ['Mỗi người giữ vé có một bản nháp email cá nhân hóa mở trong ứng dụng email CỦA BẠN. banbe không tự gửi.', 'Each ticket holder gets a personalised draft that opens in YOUR mail app. banbe does not send it.'],
      ]],
      ['p', 'Sự kiện đã hủy rời khỏi "Sự kiện sắp tới" và không vào "Sự kiện đã qua". Mọi khoản hoàn tiền của nó nằm trong Trung tâm hoàn tiền.', 'A cancelled event leaves "Upcoming events" and does not go to "Past events". All its refunds are in the Refund Center.'],
    ]},
    { id: 'refunds', vi: 'Hoàn tiền cho khách', en: 'Refunding guests', blocks: [
      ['ol', [
        ['Chờ khách chọn tài khoản nhận (chỉ khi đó khoản hoàn mới đủ điều kiện).', 'Wait for the guest to choose a destination (only then is the claim eligible).'],
        ['Mở "Trung tâm hoàn tiền" (trong Attendance), chuyển khoản theo thông tin khách chọn.', 'Open the "Refund Center" (in Attendance) and transfer using the guest\'s chosen details.'],
        ['Chọn các khoản rồi "Confirm transfers sent" (hàng loạt) hoặc "Mark refund sent" từng khoản. Có thể thêm ghi chú và chứng từ chuyển khoản.', 'Select claims and use "Confirm transfers sent" (batch) or "Mark refund sent" per claim. Add a note and transfer proof if you like.'],
      ]],
      ['ul', [
        ['Hạn hoàn tiền là 3 ngày làm việc kể từ lúc hủy.', 'The refund is due 3 business days after cancellation.'],
        ['Khách có 7 ngày để xác nhận. Nếu không phản hồi, hệ thống tự ghi nhận đã nhận.', 'Guests have 7 days to confirm. If they do nothing it is auto-confirmed.'],
        ['Khách báo chưa nhận: "Resend transfer info". Bạn có 48 giờ phản hồi khi có tranh chấp hoàn tiền.', 'Guest says it did not arrive: "Resend transfer info". You have 48 hours to respond to a refund dispute.'],
        ['Khoản hoàn tiền quá hạn hiện trong "Cần chú ý" ở Số liệu & Báo cáo.', 'Overdue refunds show under "Needs attention" in Metrics & Reports.'],
      ]],
    ]},
    { id: 'disputes', vi: 'Tranh chấp', en: 'Disputes', blocks: [
      ['ul', [
        ['Tranh chấp thanh toán: "Escalate to banbe" kèm mô tả. Quản trị viên đọc chat và bằng chứng rồi quyết định ("Buyer is right" cấp vé, hoặc "Release seat").', 'Payment dispute: "Escalate to banbe" with a description. Admins read the chat and proof, then decide ("Buyer is right" issues the ticket, or "Release seat").'],
        ['Tranh chấp hoàn tiền: mở "Open dispute chat" từ hộp thư (dòng "Dispute in progress"). Đính kèm tệp. "Đóng tranh chấp" khi xong.', 'Refund dispute: open "Open dispute chat" from the inbox ("Dispute in progress" row). Attach files. "Close dispute" when done.'],
        ['Có thể tải transcript. Bản của host được giữ đến khi dữ liệu bị xóa (7 ngày sau khi đóng).', 'You can download the transcript. The host copy is kept until the data is purged (7 days after closing).'],
        ['Tranh chấp còn mở khiến banbe không thể gỡ sự kiện. Hãy giải quyết dứt điểm.', 'An open dispute stops banbe from removing the event, so settle it fully.'],
      ]],
    ]},
    { id: 'invite', vi: 'Sự kiện chỉ mời & khảo sát', en: 'Invite-only events & surveys', blocks: [
      ['ul', [
        ['Invite-only: chọn khi tạo sự kiện. Chỉ người được mời mới xem và đặt được. Hiện chưa có màn hình quản lý lời mời cho host.', 'Invite-only: choose it when creating. Only invited people can see and book. There is no host screen to manage invites yet.'],
        ['Khảo sát (Account > Surveys & Event Ideas): "+ Create a new survey", rồi "Publish", chia sẻ link hoặc story, "Close early" / "Archive".', 'Surveys (Account > Surveys & Event Ideas): "+ Create a new survey", then "Publish", share the link or a story, "Close early" / "Archive".'],
        ['Khi khảo sát đóng, gợi ý sự kiện có thể được tạo. "Use This Idea" mở biểu mẫu tạo sự kiện đã điền sẵn.', 'When a survey closes, event suggestions may be generated. "Use This Idea" opens a pre-filled create form.'],
      ]],
    ]},
    { id: 'team', vi: 'Đội ngũ, hồ sơ host & thẻ chia sẻ', en: 'Team, host profile & share card', blocks: [
      ['ul', [
        ['Team (cuối Dashboard): mời thành viên theo @handle với vai trò công khai. Trạng thái Pending / Joined / Declined / Removed. Có thể ẩn khỏi trang công khai.', 'Team (bottom of the Dashboard): invite members by @handle with a public role. Statuses Pending / Joined / Declined / Removed. They can be hidden from the public page.'],
        ['"Credit an event contribution" ghi nhận ai đã giúp tổ chức sự kiện ("Helped organize" trên hồ sơ họ).', '"Credit an event contribution" records who helped organize an event ("Helped organize" on their profile).'],
        ['Hồ sơ host (/org/<id>): người theo dõi, sự kiện sắp tới, "Sự kiện đã qua" (thu gọn, mới nhất trước), ảnh, huy hiệu "Verified" do banbe gán thủ công. "Request" để xin xác minh. Khách theo dõi bạn thấy "✓ Đang theo dõi".', 'Host profile (/org/<id>): followers, upcoming events, "Past events" (collapsed, newest first), photos, a "Verified" badge set manually by banbe. "Request" to ask for verification. Guests who follow you see "✓ Following".'],
        ['Thẻ chia sẻ: chọn màu/nền, "Save card" để công bố, tải ảnh hoặc sao chép link. Link sự kiện chia sẻ ra ngoài hiện ảnh bìa làm ảnh xem trước.', 'Share card: pick colours/background, "Save card" to publish, download the image or copy the link. Shared event links show the cover photo as the preview.'],
        ['Thành viên team có thể chạy cửa và chat. Chỉ chủ hồ sơ mới sửa sự kiện, hủy sự kiện và quản lý thành viên.', 'Team members can run the door and chat. Only the profile owner edits events, cancels them and manages members.'],
      ]],
    ]},
    { id: 'reports', vi: 'Số liệu & báo cáo', en: 'Metrics & reports', blocks: [
      ['p', 'Account > "Số Liệu & Báo Cáo". Chọn 7 ngày / 30 ngày / 90 ngày / "Tuỳ chọn…". Thẻ chính là số chỗ đã xác nhận theo ngày, kèm ngày cao nhất, số ngày có hoạt động và trung bình mỗi ngày.', 'Account > "Metrics & Reports". Pick 7d / 30d / 90d / "Custom…". The main card shows confirmed seats per day, with the peak day, active days and daily average.'],
      ['ul', [
        ['"Cần chú ý" chỉ hiện việc khác 0, ví dụ hoàn tiền quá hạn ("Xem khoản quá hạn") hoặc còn nợ ("See claims owed"), và mở thẳng các khoản đó.', '"Needs attention" only lists non-zero items, such as overdue refunds ("See overdue claims") or refunds owed ("See claims owed"), and opens those claims directly.'],
        ['Các phần "Tổng quan", "Phân tích", "Xu hướng" và "Tất cả số liệu". Mỗi số liệu có một dòng giải thích. Bảng không hiện so sánh tăng/giảm.', 'Sections "Overview", "Breakdown", "Trends" and "All metrics". Each metric has a one-line meaning. The dashboard shows no growth comparisons.'],
        ['Xuất: menu "⋯" ("Xuất và tuỳ chọn khác") có "Làm mới", "Báo cáo PDF", "Dữ liệu JSON". Mở một số liệu để "Xuất CSV" hoặc "Lưu ảnh biểu đồ".', 'Export: the "⋯" menu ("Export and more") has "Refresh", "PDF report" and "JSON data". Open a metric to "Export CSV" or "Save chart image".'],
      ]],
    ]},
    { id: 'tips', vi: 'Lưu ý quan trọng', en: 'Important reminders', blocks: [
      ['ul', [
        ['Không thể xóa tài khoản khi còn sự kiện đang mở.', 'You cannot delete your account while you own an open event.'],
        ['Thời gian giữ chỗ 30 phút không tùy chỉnh được.', 'The 30-minute hold cannot be customised.'],
        ['Hãy xác nhận thanh toán nhanh: banbe không tự xác nhận.', 'Confirm payments promptly: banbe never confirms automatically.'],
        ['Không chuyển tiền hộ qua banbe. Mọi giao dịch diễn ra giữa bạn và khách.', 'banbe does not move money. All payments are between you and your guests.'],
        ['Sở thích của khách là riêng tư. Bạn chỉ đặt điều kiện, không thấy câu trả lời của từng người.', 'Guest preferences are private. You set criteria but never see anyone\'s answers.'],
      ]],
    ]},
  ],
};

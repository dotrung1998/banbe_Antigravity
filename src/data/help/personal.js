// Guide for goers (everyone with an account). Blocks: see HelpReader.jsx.
export const PERSONAL_GUIDE = {
  vi: 'Hướng dẫn cho Người tham gia', en: 'Guide for Personal Users',
  introVi: 'Mọi việc bạn có thể làm với tư cách người tham gia: từ đăng ký, tìm sự kiện, giữ chỗ, thanh toán, nhận vé đến hoàn tiền và khiếu nại.',
  introEn: 'Everything you can do as a guest: from signing up and finding events to holding a seat, paying, getting tickets, refunds and disputes.',
  sections: [
    { id: 'start', vi: 'Bắt đầu: đăng ký & đăng nhập', en: 'Getting started: sign up & log in', blocks: [
      ['p', 'banbe cần đăng nhập để sử dụng; bạn không thể xem sự kiện khi chưa có tài khoản.', 'banbe needs you to be signed in; you cannot browse events without an account.'],
      ['h', 'Các cách đăng ký / đăng nhập', 'Ways to sign up / log in'],
      ['ul', [
        ['Email + mật khẩu (tối thiểu 8 ký tự): chọn "Đăng ký" rồi nhập tên hiển thị, email, mật khẩu.', 'Email + password (at least 8 characters): choose "Sign up", then enter a display name, email and password.'],
        ['Mã gửi qua email: chọn "Send sign-in code" và nhập mã 8 chữ số.', 'Emailed code: choose "Send sign-in code" and enter the 8-digit code.'],
        ['"Continue with Google" hoặc "Continue with Facebook".', '"Continue with Google" or "Continue with Facebook".'],
        ['Quên mật khẩu: nhấn "Forgot password?" để nhận email đặt lại.', 'Forgot your password: tap "Forgot password?" to get a reset email.'],
      ]],
      ['p', 'Khi đăng ký bạn phải tích đồng ý Điều khoản và Thông báo quyền riêng tư (xem mục Điều khoản). Zalo và Instagram hiện chưa dùng được.', 'When signing up you must tick agreement to the Terms and Privacy Notice (see Terms). Zalo and Instagram sign-in are not available yet.'],
      ['h', 'Xác minh số điện thoại & ngày sinh', 'Phone and date-of-birth check'],
      ['ol', [
        ['Chọn mã quốc gia, nhập số điện thoại, nhấn "Send code".', 'Pick the country code, enter your phone number and tap "Send code".'],
        ['Nhập mã 6 chữ số nhận qua tin nhắn. Gửi lại được sau 60 giây.', 'Enter the 6-digit code you receive by text. You can resend after 60 seconds.'],
        ['Nhập ngày sinh thật (ngày hợp lệ, không ở tương lai). Mỗi phiên đăng nhập có thể yêu cầu xác nhận lại ngày sinh.', 'Enter your real date of birth (a valid date, not in the future). A new sign-in session may ask you to confirm it again.'],
      ]],
      ['tip', 'Mỗi vé cần tên và ngày sinh của người tham dự, nên hãy nhập chính xác.', 'Each ticket needs the attendee\'s name and date of birth, so enter them accurately.'],
    ]},
    { id: 'browse', vi: 'Tìm sự kiện: Trang chủ, Bản đồ, Tìm kiếm', en: 'Finding events: Home, Map, Search', blocks: [
      ['p', 'Thanh dưới cùng gồm: Home, Map, Notifications, Messages, Account.', 'The bottom bar has: Home, Map, Notifications, Messages, Account.'],
      ['h', 'Trang chủ', 'Home'],
      ['ul', [
        ['Lọc theo danh mục (All, Supper club, Fashion, Gallery, Music) và trạng thái (Upcoming, Saved, Attending, Not confirmed, Sold out, Ended).', 'Filter by category (All, Supper club, Fashion, Gallery, Music) and status (Upcoming, Saved, Attending, Not confirmed, Sold out, Ended).'],
        ['Nhấn chip địa điểm để chọn khu vực; mặc định là "Everywhere".', 'Tap the location capsule to choose an area; the default is "Everywhere".'],
        ['"Your events" hiển thị các sự kiện bạn đang giữ chỗ / đã thanh toán.', '"Your events" shows events you are holding or have paid for.'],
        ['"Things to do" (Action Center) liệt kê việc cần làm: giữ chỗ sắp hết hạn, hoàn tiền cần xác nhận…', '"Things to do" (Action Center) lists what needs you: a hold about to expire, a refund to confirm…'],
        ['"Help Shape Upcoming Events" là các khảo sát công khai bạn có thể trả lời.', '"Help Shape Upcoming Events" lists public surveys you can answer.'],
        ['Hàng bộ lọc thứ hai có chip ngôi sao vàng "For You" (Dành cho bạn), luôn đứng cố định ở đầu hàng; các chip còn lại vuốt ngang riêng. Chip chỉ hiện khi có sự kiện khớp câu trả lời sở thích của bạn.', 'The second filter row has a gold-star "For You" chip pinned at the start of the row; the other chips swipe sideways on their own. It only shows when events match your preference answers.'],
        ['Khi có sự kiện mới khớp sở thích, chip "For You" lấp lánh vài giây rồi giữ nhãn "New" nhỏ cho đến khi bạn mở nó. Sự kiện cũ, sự kiện không khớp hoặc bản nháp không bao giờ gây báo. Nếu bật "Giảm chuyển động", chip chỉ hiện nhãn tĩnh.', 'When a new event matches your preferences, the "For You" chip shimmers for a few seconds, then keeps a small "New" label until you open it. Older events, non-matching events and drafts never trigger it. With Reduce Motion on, the chip just shows a static label.'],
      ]],
      ['h', 'Bản đồ', 'Map'],
      ['p', 'Tìm theo tên, khu vực, từ khóa hoặc danh mục. Dùng "Open now", "Nearby", "Search here"; chuyển giữa "Big list" và "Big map"; nhấn ghim rồi "View details".', 'Search by name, area, keyword or category. Use "Open now", "Nearby" and "Search here"; switch between "Big list" and "Big map"; tap a pin then "View details".'],
      ['h', 'Story & Pulse', 'Stories & Pulse'],
      ['p', 'Hàng vòng tròn ở Trang chủ: "Banbe Pulse" xếp hạng sự kiện công khai theo ngày/tuần; các story của host tự hết hạn sau 24 giờ.', 'The ring row on Home: "Banbe Pulse" ranks public events daily/weekly; host stories expire after 24 hours.'],
    ]},
    { id: 'event', vi: 'Trang sự kiện', en: 'The event page', blocks: [
      ['ul', [
        ['"Save" lưu sự kiện (hiện chỉ lưu trên thiết bị này); "Share" chia sẻ link; "Open in map" mở bản đồ.', '"Save" bookmarks an event (currently stored on this device only); "Share" shares the link; "Open in map" opens the map.'],
        ['"Message" nhắn trực tiếp cho host; "Visit" mở trang host (lịch sử, ảnh, người theo dõi).', '"Message" chats with the host; "Visit" opens the host page (track record, photos, followers).'],
        ['Phần "Included" cho biết giá vé đã bao gồm gì; "Track record" là số liệu thật của host.', '"Included" says what the ticket covers; "Track record" shows the host\'s real numbers.'],
        ['Trạng thái: Sold out, Event has been cancelled, Event has ended, hoặc "View payment status" nếu bạn đã giữ chỗ.', 'States: Sold out, Event has been cancelled, Event has ended, or "View payment status" if you already hold a seat.'],
      ]],
      ['h', 'Sự kiện chỉ dành cho người được mời', 'Invite-only events'],
      ['p', 'Sự kiện "Private ▪︎ invite only" chỉ người được host mời mới xem và đặt được.', 'A "Private ▪︎ invite only" event can only be seen and booked by people the host invited.'],
    ]},
    { id: 'book', vi: 'Giữ chỗ & đặt vé', en: 'Holding a seat & booking', blocks: [
      ['ol', [
        ['Mở sự kiện và nhấn nút đặt chỗ ("Reserve" / "Hold ▪︎ 30 minutes").', 'Open the event and tap the reserve button ("Reserve" / "Hold ▪︎ 30 minutes").'],
        ['Chọn số vé (tối đa 6 mỗi lần đặt; mỗi sự kiện chỉ một đặt chỗ đang hiệu lực).', 'Choose the number of tickets (up to 6 per booking; one live booking per event).'],
        ['Nhập "Full name" cho từng người tham dự. Vé 1 là của bạn: ngày sinh được lấy tự động từ hồ sơ và hiển thị để bạn kiểm tra. Với các vé còn lại, nhập "Date of birth" và có thể điền thêm "Email (optional)" của người đó.', 'Enter "Full name" for each attendee. Ticket 1 is yours: the date of birth is taken from your profile automatically and shown so you can check it. For the other tickets, enter "Date of birth" and optionally "Email (optional)" for that person.'],
        ['Sự kiện miễn phí: vé được cấp ngay. Sự kiện có phí: ghế được giữ 30 phút để bạn chuyển tiền.', 'Free event: the ticket is issued immediately. Paid event: the seat is held for 30 minutes while you pay.'],
      ]],
      ['p', 'Nếu ngày sinh lấy từ hồ sơ bị sai, nhấn "Wrong? Request a correction" dưới ngày sinh ở Vé 1, nhập ngày đúng và lý do. Quản trị viên sẽ xem xét; ngày sinh chỉ đổi khi yêu cầu được duyệt, và bạn thấy trạng thái yêu cầu ngay tại đó. Email của người tham dự chỉ được lưu cùng vé, chưa gửi thư nào đến địa chỉ đó.', 'If the date of birth taken from your profile is wrong, tap "Wrong? Request a correction" under the date of birth on Ticket 1, then enter the right date and a reason. An admin reviews it; your birthday only changes if the request is approved, and you see the request status right there. An attendee\'s email is only saved with the ticket; nothing is sent to that address yet.'],
      ['p', 'Một số sự kiện cần host chấp nhận yêu cầu của bạn trước khi thanh toán.', 'Some events need the host to accept your request before you pay.'],
      ['tip', 'Hết 30 phút mà chưa thanh toán, ghế được nhả ra. Nhấn "Reserve again" nếu còn chỗ.', 'If 30 minutes pass without payment, the seat is released. Tap "Reserve again" if there is still room.'],
    ]},
    { id: 'pay', vi: 'Thanh toán', en: 'Paying', blocks: [
      ['p', 'banbe không thu hay giữ tiền. Bạn chuyển khoản trực tiếp cho host; banbe chỉ hiển thị thông tin nhận tiền và ghi nhận trạng thái.', 'banbe does not collect or hold money. You transfer directly to the host; banbe only shows the payment details and records the status.'],
      ['ol', [
        ['Mở màn hình thanh toán: xem "Bank", "Account number", "Account name" hoặc quét mã "Scan to pay".', 'Open the payment screen: see "Bank", "Account number", "Account name" or scan the "Scan to pay" code.'],
        ['Ghi đúng "Transfer reference" (có nút "Copy") vào nội dung chuyển khoản.', 'Put the exact "Transfer reference" (there is a "Copy" button) in your transfer note.'],
        ['Sau khi chuyển, nhập "Transaction ID" và (tùy chọn) ảnh biên lai, rồi nhấn xác nhận đã chuyển.', 'After transferring, enter the "Transaction ID" and optionally a receipt image, then confirm you have transferred.'],
        ['Khi bạn xác nhận đã chuyển, đồng hồ 30 phút dừng và ghế được khóa cho đến khi host xác nhận.', 'Once you confirm the transfer, the 30-minute clock stops and your seat is locked until the host confirms.'],
      ]],
      ['h', 'Các trạng thái', 'Statuses'],
      ['ul', [
        ['Awaiting confirmation: chờ host xác nhận đã nhận tiền (host thường được kỳ vọng phản hồi trong 1 giờ).', 'Awaiting confirmation: waiting for the host to confirm receipt (hosts are expected to respond within about 1 hour).'],
        ['Under review: banbe đang xem xét tranh chấp; ghế vẫn được giữ.', 'Under review: banbe is reviewing a dispute; your seat stays held.'],
        ['Paid / Confirmed: đã xác nhận, vé có mã QR.', 'Paid / Confirmed: confirmed, your ticket has a QR code.'],
        ['Hold expired, Booking declined, Cancelled: xem mục Hỏi & Đáp để biết bước tiếp theo.', 'Hold expired, Booking declined, Cancelled: see the Q&A for what to do next.'],
      ]],
      ['p', 'Host chưa xác nhận? Dùng "Remind the organizer to confirm" (tối đa 2 lần), rồi "Message host" hoặc "Raise a dispute".', 'Host has not confirmed? Use "Remind the organizer to confirm" (max 2 times), then "Message host" or "Raise a dispute".'],
      ['p', 'Thông tin xuất hóa đơn của bạn nằm ở Account > Payments & Documents > Billing Details.', 'Your invoice details are under Account > Payments & Documents > Billing Details.'],
    ]},
    { id: 'tickets', vi: 'Vé, mã QR, PDF & lịch', en: 'Tickets, QR, PDF & calendar', blocks: [
      ['ul', [
        ['Mỗi người tham dự có mã QR và mã vào cửa riêng; mỗi người xuất trình mã của chính mình ở cửa.', 'Each attendee has their own QR and entry code; each person shows their own code at the door.'],
        ['"Download PDF" tải từng vé; có thể tick nhiều vé để tải ZIP hoặc "Download all".', '"Download PDF" saves one ticket; tick several for a ZIP, or "Download all".'],
        ['"Add to calendar" tải tệp .ics cho Apple Calendar hoặc ứng dụng khác.', '"Add to calendar" downloads an .ics file for Apple Calendar or other apps.'],
        ['"View Receipt" xem biên lai/hóa đơn do host tải lên; "Request Receipt" nhờ host gửi nếu chưa có.', '"View Receipt" opens the receipt/invoice the host uploaded; "Request Receipt" asks the host if there is none yet.'],
        ['Vé hiển thị "Checked in" sau khi được quét.', 'A ticket shows "Checked in" once scanned.'],
      ]],
      ['tip', 'Mã QR chỉ xuất hiện sau khi host xác nhận thanh toán. Tính năng Apple Wallet chưa được bật.', 'The QR appears only after the host confirms payment. Apple Wallet is not switched on yet.'],
    ]},
    { id: 'gift', vi: 'Tặng & nhập vé', en: 'Gifting & importing tickets', blocks: [
      ['ul', [
        ['Tặng vé: "Give a ticket to a friend" chuyển quyền vào cửa; bạn vẫn là người sở hữu giao dịch và quyền hoàn tiền nếu host hủy. Không áp dụng cho đặt chỗ có tên người tham dự riêng.', 'Gifting: "Give a ticket to a friend" hands over admission; you still own the transaction and any refund right if the host cancels. Not available for bookings with named attendees.'],
        ['Nhập vé: Account > Tickets & Bookings > "Import a gift or group ticket", nhập mã (ATT-… hoặc CLAIM-…) rồi "Import ticket".', 'Importing: Account > Tickets & Bookings > "Import a gift or group ticket", enter the code (ATT-… or CLAIM-…) and tap "Import ticket".'],
        ['Vé đã nhập hiện ở mục "Imported tickets" cùng QR và PDF. Sự kiện chưa thanh toán, đã hủy hoặc đã kết thúc sẽ bị từ chối.', 'Imported tickets appear under "Imported tickets" with QR and PDF. Unpaid, cancelled or ended events are refused.'],
      ]],
    ]},
    { id: 'refund', vi: 'Hoàn tiền', en: 'Refunds', blocks: [
      ['p', 'banbe không hoàn tiền thay host. Hoàn tiền theo điều khoản host công bố trên trang sự kiện; khi host hủy sự kiện hoặc hủy đặt chỗ của bạn, một yêu cầu hoàn tiền được tạo.', 'banbe does not refund on a host\'s behalf. Refunds follow the terms the host published on the event page; when a host cancels the event or your booking, a refund claim is created.'],
      ['ol', [
        ['Vào Account > Payments & Documents > Refund Accounts, thêm tài khoản nhận ("+ Add account") và đặt mặc định.', 'Go to Account > Payments & Documents > Refund Accounts, add a receiving account ("+ Add account") and set a default.'],
        ['Trong "My refunds", chọn "Choose a refund destination" cho yêu cầu của bạn.', 'In "My refunds", use "Choose a refund destination" on your claim.'],
        ['Host chuyển tiền và đánh dấu đã gửi. Khi nhận được, nhấn "Confirm received".', 'The host transfers and marks it sent. When it arrives, tap "Confirm received".'],
        ['Chưa nhận được hoặc có vấn đề: nhấn "Dispute refund" / "Raise a dispute".', 'Not received or something is wrong: tap "Dispute refund" / "Raise a dispute".'],
      ]],
      ['ul', [
        ['Hạn hoàn tiền host cam kết là 3 ngày làm việc kể từ lúc hủy.', 'The refund deadline the host owes is 3 business days after cancellation.'],
        ['Nếu bạn không phản hồi, hoàn tiền tự động được ghi nhận đã nhận sau 7 ngày kể từ khi host đánh dấu đã gửi. Hãy kiểm tra sớm.', 'If you do nothing, the refund is auto-confirmed 7 days after the host marks it sent. Check early.'],
        ['Có thể thêm nhiều tài khoản, sắp xếp lại, ẩn/hiện, sửa, đặt mặc định hoặc xóa.', 'You can add several accounts, reorder, hide/reveal, edit, set a default or delete.'],
      ]],
    ]},
    { id: 'dispute', vi: 'Khiếu nại & chat khiếu nại', en: 'Disputes & dispute chat', blocks: [
      ['p', 'Có hai loại: tranh chấp thanh toán (host báo không thấy tiền) và tranh chấp hoàn tiền (bạn báo chưa nhận được tiền).', 'There are two kinds: payment disputes (the host says they cannot find your payment) and refund disputes (you say you did not receive a refund).'],
      ['ul', [
        ['Khi một tranh chấp được chuyển lên banbe, một khung chat tạm thời mở ra giữa bạn, host và quản trị viên đọc được.', 'When a dispute is escalated to banbe, a temporary chat opens between you and the host; admins can read it.'],
        ['Có thể đính kèm ảnh JPG/PNG/WebP hoặc PDF (tối đa 20 MB). Tin nhắn không sửa hoặc xóa được.', 'You can attach JPG/PNG/WebP or PDF files (max 20 MB). Messages cannot be edited or deleted.'],
        ['"Close dispute" kết thúc tranh chấp. Sau đó có thể "Download transcript" và "Close and delete my copy" (chỉ ẩn bản của bạn).', '"Close dispute" ends it. Afterwards you can "Download transcript" and "Close and delete my copy" (hides only your copy).'],
        ['Dữ liệu tranh chấp hoàn tiền được xóa 7 ngày sau khi đóng.', 'Refund-dispute data is purged 7 days after it closes.'],
      ]],
      ['p', 'Nếu host chỉ bấm "Can\'t find it" mà chưa nâng lên banbe, bạn chỉ nhận tin trong chat thường; hãy phản hồi hoặc gửi thêm bằng chứng.', 'If the host only tapped "Can\'t find it" without escalating, you just get a message in your normal chat; reply or send more proof.'],
    ]},
    { id: 'chat', vi: 'Tin nhắn & thông báo', en: 'Messages & notifications', blocks: [
      ['ul', [
        ['Tab "Messages": các cuộc trò chuyện với host. Cuộc trò chuyện chỉ xuất hiện sau tin nhắn đầu tiên bạn gửi. Menu "..." cho phép Star, Archive, Delete (xóa chỉ với bạn).', 'The "Messages" tab holds your chats with hosts. A chat appears only after you send the first message. The "..." menu offers Star, Archive, Delete (removes it for you only).'],
        ['Gửi ảnh hoặc tài liệu bằng "Add photo or document" / "Camera".', 'Send photos or documents with "Add photo or document" / "Camera".'],
        ['Tab "Notifications": nhóm New / Today / Last 7 days / Older; đánh dấu đã đọc, tắt loại thông báo, xóa, chọn nhiều.', 'The "Notifications" tab groups New / Today / Last 7 days / Older; mark read, mute a kind, delete, multi-select.'],
        ['Thông báo trong ứng dụng và email đang hoạt động; thông báo đẩy (push) chưa bật.', 'In-app and email notifications work; push notifications are not enabled yet.'],
      ]],
    ]},
    { id: 'survey', vi: 'Khảo sát', en: 'Surveys', blocks: [
      ['p', 'Host dùng khảo sát để đo nhu cầu. Mở một khảo sát từ Trang chủ hoặc story, điền mức quan tâm, thời gian/địa điểm ưa thích, quy mô nhóm, ngân sách…, tick đồng ý để host liên hệ về sự kiện đó, rồi "Submit response".', 'Hosts use surveys to gauge demand. Open one from Home or a story, fill in interest, preferred time/place, group size, budget…, tick consent for the host to contact you about that event, then "Submit response".'],
      ['ul', [
        ['Trả lời khảo sát không giữ chỗ cho bạn.', 'Answering a survey does not reserve a place.'],
        ['Có thể chỉnh sửa câu trả lời đến khi khảo sát đóng ("Edit Response").', 'You can edit your answer until the survey closes ("Edit Response").'],
        ['Nếu chưa đăng nhập, bạn xác minh email bằng mã 8 chữ số.', 'If you are not signed in, verify your email with an 8-digit code.'],
      ]],
    ]},
    { id: 'profile', vi: 'Hồ sơ, thẻ chia sẻ & mời bạn bè', en: 'Profile, share card & inviting friends', blocks: [
      ['ul', [
        ['Account > "Personal Profile": đổi ảnh, handle, tên hiển thị, giới thiệu, thành phố, sở thích, bảng màu.', 'Account > "Personal Profile": change photo, handle, display name, bio, city, interests, palette.'],
        ['Trang công khai của bạn ở /u/<handle> ai có link cũng xem được.', 'Your public page lives at /u/<handle> and anyone with the link can view it.'],
        ['Thẻ chia sẻ: chọn màu, nền, "Save card", "Download image", "Copy link", "Share…".', 'Share card: pick colours and background, then "Save card", "Download image", "Copy link", "Share…".'],
        ['"Invite friends" tạo link mời cá nhân.', '"Invite friends" creates your personal invite link.'],
        ['Trang hồ sơ của bạn có một hàng ba nút nhỏ: "QR code" (hiện mã QR), "Edit profile" (sửa hồ sơ) và "Edit charm" (sửa móc khoá). Người khác xem hồ sơ của bạn chỉ thấy nút QR.', 'Your own profile page has one row of three small buttons: "QR code" (show the QR), "Edit profile" and "Edit charm" (edit your keychain). Visitors only see the QR button.'],
        ['"Post a story": ảnh + văn bản + link, tự hết hạn sau 24 giờ.', '"Post a story": photo + text + link, expires after 24 hours.'],
      ]],
    ]},
    { id: 'keychain', vi: 'Móc khoá trang trí hồ sơ', en: 'Profile keychain charm', blocks: [
      ['p', 'Móc khoá là một món trang trí nhỏ treo ở góc thẻ hồ sơ. Mặc định tắt; khi bật, người xem hồ sơ của bạn cũng thấy nó.', 'The keychain is a small decoration hanging from a corner of your profile card. It is off by default; when on, people who view your profile see it too.'],
      ['h', 'Bật và chỉnh móc khoá', 'Turn it on and customise it'],
      ['ol', [
        ['Mở hồ sơ của bạn rồi nhấn "Edit charm", hoặc vào Edit profile > Keychain.', 'Open your profile and tap "Edit charm", or go to Edit profile > Keychain.'],
        ['Bật công tắc, chọn một trong 24 mẫu (nhóm sao/trăng/mây, tim/nơ, hoa/trái cây, cà phê/âm nhạc, mèo/gấu, du lịch/vé, họa tiết banbe).', 'Switch it on and pick one of 24 designs (stars/moon/clouds, hearts/ribbons, flowers/fruits, coffee/music, cats/bears, travel/tickets, banbe motifs).'],
        ['Chọn một trong bốn góc, kích cỡ S/M/L và bật/tắt chuyển động. Xem trước ngay trong màn hình rồi nhấn Save; Cancel sẽ bỏ thay đổi.', 'Choose one of four corners, size S/M/L and motion on/off. Preview it on the screen, then tap Save; Cancel discards changes.'],
      ]],
      ['h', 'Tải ảnh mẫu & dùng ảnh riêng', 'Export artwork & use your own'],
      ['ul', [
        ['"Download artwork" / nút chia sẻ lưu ảnh PNG của mẫu đang chọn.', '"Download artwork" / the share button saves the PNG of the selected design.'],
        ['"Use my own art": chọn tệp PNG hoặc WebP nền trong suốt bạn đã tải ở nơi khác (tối đa 512 px, 256 KB; ảnh được thu nhỏ trên máy và xoá siêu dữ liệu như vị trí). SVG, HTML và GIF không được chấp nhận. Mỗi tài khoản giữ tối đa 3 ảnh; "Remove my art" để xoá ảnh của bạn.', '"Use my own art": pick a transparent PNG or WebP you downloaded elsewhere (up to 512 px, 256 KB; it is resized on your device and metadata such as location is removed). SVG, HTML and GIF are not accepted. Each account keeps at most 3 images; "Remove my art" deletes yours.'],
        ['Ảnh riêng chỉ được người dùng đăng nhập khác xem khi móc khoá của bạn đang bật. Hãy chỉ dùng ảnh bạn có quyền sử dụng.', 'Your own art can be seen by other signed-in users only while your keychain is on. Only use images you have the right to use.'],
      ]],
      ['h', 'Chơi với móc khoá', 'Playing with it'],
      ['ul', [
        ['Kéo móc khoá lên/xuống để kéo giãn, thả ra để nó đung đưa rồi dừng. Cuộn trang bình thường ở những chỗ khác.', 'Drag the charm up or down to stretch it, release and it swings then settles. Scroll the page as usual anywhere else.'],
        ['Trên iPhone, móc khoá nhẹ nhàng phản ứng khi bạn nghiêng hoặc lắc máy và rung nhẹ khi chạm/thả (theo cài đặt Haptic của app). Trên web, nhấn "Enable tilt" trong màn hình Keychain để cho phép cảm biến (cần HTTPS và sự đồng ý của bạn).', 'On iPhone the charm gently responds to tilting or shaking and gives a light tap on grab/release (following the app Haptic setting). On the web, tap "Enable tilt" on the Keychain screen to allow the sensor (needs HTTPS and your permission).'],
        ['Không muốn kéo? Dùng nút "Swing" hoặc, trên web, chọn móc khoá rồi nhấn Enter/Space. Khi bật "Giảm chuyển động" hoặc tắt chuyển động, móc khoá đứng yên.', 'Prefer not to drag? Use the "Swing" button or, on the web, focus the charm and press Enter/Space. With Reduce Motion on or motion off, the charm stays still.'],
      ]],
    ]},
    { id: 'settings', vi: 'Cài đặt, bảo mật & xóa tài khoản', en: 'Settings, security & deleting your account', blocks: [
      ['ul', [
        ['Account > Settings: ngôn ngữ (Tiếng Việt / English) và giao diện (Light / Dark). Ngôn ngữ cũng áp dụng cho tin nhắn tự động.', 'Account > Settings: language (Vietnamese / English) and appearance (Light / Dark). Language also applies to automated messages.'],
        ['"Security": đổi mật khẩu (8+ ký tự) và xem trạng thái xác minh điện thoại.', '"Security": change your password (8+ characters) and see your phone-verification status.'],
        ['Có tùy chọn tự động email bản sao hóa đơn/biên lai cho bạn.', 'There is an option to automatically email you copies of invoices/receipts.'],
        ['Đăng xuất bằng "Sign out" trong Account.', 'Log out with "Sign out" in Account.'],
      ]],
      ['h', 'Xóa tài khoản', 'Deleting your account'],
      ['ol', [
        ['Account > Settings > "Delete Account" > Continue.', 'Account > Settings > "Delete Account" > Continue.'],
        ['Xác minh bằng mã 8 chữ số gửi qua email.', 'Verify with the 8-digit code emailed to you.'],
        ['Gõ đúng cụm từ xác nhận và nhấn "Permanently delete account".', 'Type the exact confirmation phrase and tap "Permanently delete account".'],
      ]],
      ['tip', 'Không thể hoàn tác. Bạn không xóa được khi còn sở hữu sự kiện đang mở; hãy hủy hoặc kết thúc sự kiện trước. Yêu cầu bản sao dữ liệu: liên hệ email nêu trong Điều khoản.', 'This cannot be undone. You cannot delete while you still own an open event; cancel or end it first. To request a copy of your data, use the contact email in the Terms.'],
    ]},
    { id: 'search', vi: 'Tìm kiếm trong Tài khoản', en: 'Searching inside Account', blocks: [
      ['p', 'Ô "Search Account…" trên màn hình Account tìm mọi mục (cài đặt, vé, hoàn tiền, trợ giúp…) và mở thẳng tới đó.', 'The "Search Account…" box on the Account screen finds any entry (settings, tickets, refunds, help…) and jumps straight to it.'],
    ]},
  ],
};

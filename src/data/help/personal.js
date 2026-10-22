// Guide for goers (everyone with an account). Blocks: see HelpReader.jsx.
export const PERSONAL_GUIDE = {
  vi: 'Hướng dẫn cho Người tham gia', en: 'Guide for Personal Users',
  introVi: 'Mọi việc bạn có thể làm với tư cách người tham gia: từ xem thử, đăng ký, tìm sự kiện, giữ chỗ, thanh toán, nhận vé đến hoàn tiền và khiếu nại.',
  introEn: 'Everything you can do as a guest: from looking around and signing up to finding events, holding a seat, paying, getting tickets, refunds and disputes.',
  sections: [
    { id: 'start', vi: 'Bắt đầu: xem thử, đăng ký & đăng nhập', en: 'Getting started: look around, sign up & log in', blocks: [
      ['p', 'Bạn có thể xem banbe mà chưa cần tài khoản. Màn hình chào có ba lựa chọn: "Khám phá sự kiện", "Tạo tài khoản" và "Đã có tài khoản? Đăng nhập". Bạn cũng đổi được ngôn ngữ (EN/VN) và giao diện Sáng/Tối ngay tại đó.', 'You can look around banbe without an account. The welcome screen has three choices: "Explore events", "Create an account" and "Already have an account? Log in". You can switch language (EN/VN) and Light/Dark right there too.'],
      ['p', '"Xem banbe hoạt động thế nào" mở 4 trang ngắn: Gợi ý hợp với bạn, Giữ chỗ trong vài chạm, Tự tổ chức sự kiện và Tạo sự kiện trong 5 bước. Dùng "Tiếp" và "Bỏ qua"; trang không tự chuyển.', '"See how banbe works" opens 4 short pages: Picks that fit you, Hold a seat in a few taps, Host your own events and Create an event in 5 steps. Use "Next" and "Skip"; pages never advance on their own.'],
      ['h', 'Xem với tư cách khách', 'Browsing as a guest'],
      ['ul', [
        ['Khi chưa đăng nhập, bạn xem được Trang chính, Bản đồ, Tìm kiếm, trang sự kiện và trang host. Trang chính hiện dòng "Bạn đang xem với tư cách khách" kèm nút Đăng nhập.', 'Signed out, you can open Home, Map, Search, event pages and host pages. Home shows "You\'re browsing as a guest" with a Log in button.'],
        ['Lưu, Theo dõi, Giữ chỗ, Nhắn tin hoặc Thích ảnh sẽ mở một lời nhắc: "Tiếp tục" (tạo tài khoản), "Đăng nhập" hoặc "Để sau". Sau khi đăng nhập, bạn quay lại đúng việc đang làm (ví dụ giữ chỗ hay nhắn tin).', 'Save, Follow, Reserve, Message or Like a photo opens a prompt: "Continue" (create an account), "Log in" or "Not now". After you sign in you land back on what you were doing (for example reserving or messaging).'],
        ['Lịch, Tin nhắn và Tài khoản cần đăng nhập. Màn hình đăng nhập có nút "Quay lại" về chỗ bạn vừa xem. Đăng xuất cũng đưa bạn về màn hình chào.', 'Schedule, Messages and Account need you to sign in. The log-in screen has "Back" to return where you were. Signing out also takes you to the welcome screen.'],
      ]],
      ['h', 'Các cách đăng ký / đăng nhập', 'Ways to sign up / log in'],
      ['ul', [
        ['Email + mật khẩu (tối thiểu 8 ký tự): chọn "Đăng ký" rồi nhập tên hiển thị, email, mật khẩu.', 'Email + password (at least 8 characters): choose "Sign up", then enter a display name, email and password.'],
        ['Mã gửi qua email: chọn "Send sign-in code" và nhập mã 8 chữ số.', 'Emailed code: choose "Send sign-in code" and enter the 8-digit code.'],
        ['"Tiếp tục với Google". Đăng nhập Facebook đang được phát triển nên nút này tạm mờ.', '"Continue with Google". Facebook login is under development, so that button is greyed out for now.'],
        ['Quên mật khẩu: nhấn "Forgot password?" để nhận email đặt lại.', 'Forgot your password: tap "Forgot password?" to get a reset email.'],
      ]],
      ['p', 'Khi đăng ký bạn phải tích đồng ý Điều khoản và Thông báo quyền riêng tư (xem mục Điều khoản). Zalo và Instagram hiện chưa dùng được.', 'When signing up you must tick agreement to the Terms and Privacy Notice (see Terms). Zalo and Instagram sign-in are not available yet.'],
      ['h', 'Xác minh số điện thoại & ngày sinh', 'Phone and date-of-birth check'],
      ['ol', [
        ['Chọn mã quốc gia, nhập số điện thoại, nhấn "Send code".', 'Pick the country code, enter your phone number and tap "Send code".'],
        ['Nhập mã 6 chữ số nhận qua tin nhắn. Gửi lại được sau 60 giây.', 'Enter the 6-digit code you receive by text. You can resend after 60 seconds.'],
        ['Nhập ngày sinh thật (ngày hợp lệ, không ở tương lai). Mỗi phiên đăng nhập có thể yêu cầu xác nhận lại ngày sinh.', 'Enter your real date of birth (a valid date, not in the future). A new sign-in session may ask you to confirm it again.'],
      ]],
      ['p', 'Trong giai đoạn thử nghiệm, banbe có thể tạm bỏ qua bước SMS; khi đó số điện thoại vẫn ghi là chưa xác minh, nhưng ngày sinh vẫn bắt buộc.', 'During testing banbe may skip the SMS step; your phone then stays marked as not verified, but the date of birth is still required.'],
      ['tip', 'Mỗi vé cần tên và ngày sinh của người tham dự, nên hãy nhập chính xác. Nếu máy chủ tạm không truy cập được, bạn sẽ thấy "Dịch vụ tạm thời không khả dụng" với nút "Thử lại".', 'Each ticket needs the attendee\'s name and date of birth, so enter them accurately. If the servers can\'t be reached you\'ll see "Service temporarily unavailable" with a "Try again" button.'],
    ]},
    { id: 'onboarding', vi: 'Thiết lập ban đầu & "Dành cho bạn"', en: 'First-run setup & "For You"', blocks: [
      ['p', 'Tài khoản mới được hỏi 5 câu ngắn, mỗi màn hình một câu, để gợi ý sự kiện hợp với bạn. Màn hình đầu có "Bắt đầu" hoặc "Bỏ qua, xem tất cả sự kiện".', 'New accounts get 5 short questions, one per screen, to suggest events that fit you. The first screen offers "Get started" or "Skip, show me everything".'],
      ['ol', [
        ['Lần lượt: mục tiêu, sở thích, thời gian rảnh, ngân sách, ngôn ngữ. Câu nào cũng có "Không ưu tiên", nút Quay lại và Bỏ qua. Ngôn ngữ hiện chưa dùng để lọc.', 'In order: goals, interests, availability, budget, languages. Each has "No preference", Back and Skip. Language does not filter events yet.'],
        ['Màn hình "Câu trả lời của bạn thay đổi gì" cho thấy gợi ý thật; chọn "Xem gợi ý cho tôi" hoặc "Xem tất cả sự kiện".', 'The "What your answers change" screen shows your real picks; choose "Show my picks" or "See all events".'],
        ['"Xem nhanh cài đặt": "Gửi hoá đơn qua email" và "Tin nhắn quảng bá từ host". Tin quảng bá mặc định TẮT; chỉ bật khi bạn tự bật.', '"Quick settings review": "Email me payment documents" and "Host promotional texts". Promotional texts are OFF unless you switch them on.'],
      ]],
      ['ul', [
        ['Câu trả lời là riêng tư: host không bao giờ thấy. Sửa bất cứ lúc nào ở Tài khoản > Cài đặt > "Sở thích sự kiện".', 'Your answers are private: hosts never see them. Change them any time in Account > Settings > "Event preferences".'],
        ['Sau đó Trang chính có thẻ "Bắt đầu với banbe": "Mở một sự kiện hợp với bạn" và "Lưu một sự kiện bạn thích". Xong hết sẽ hiện "Bạn đã sẵn sàng! 🎉" rồi thẻ tự ẩn; "Ẩn danh sách" để ẩn sớm.', 'Home then shows a "Get started with banbe" card: "Open an event that fits you" and "Save an event you like". When both are done it shows "You\'re all set! 🎉" and folds away; "Hide checklist" hides it early.'],
        ['Một số sự kiện chỉ nhận người đã khai báo sở thích/mục tiêu phù hợp; xem mục Trang sự kiện.', 'Some events only accept people who declared matching interests/goals; see The event page.'],
      ]],
    ]},
    { id: 'browse', vi: 'Tìm sự kiện: Trang chính, Tìm kiếm, Bản đồ', en: 'Finding events: Home, Search, Map', blocks: [
      ['p', 'Thanh dưới cùng gồm: Trang chính, Bản đồ, Lịch, Tin nhắn, Tài khoản. Thông báo mở từ chuông ở đầu Trang chính.', 'The bottom bar has: Home, Map, Schedule, Messages, Account. Notifications open from the bell at the top of Home.'],
      ['h', 'Trang chính', 'Home'],
      ['ul', [
        ['Ô tìm kiếm "Tìm sự kiện, host, khu vực, vibe…" ở trên cùng; dưới đó là dòng Banbe Pulse chạy ngang (5 sự kiện nổi bật hôm nay, chạm để xem bảng xếp hạng).', 'The "Search events, hosts, areas, vibes…" bar sits at the top; below it, the Banbe Pulse ticker scrolls today\'s top 5 events (tap it for the full ranking).'],
        ['"Gần · Mọi nơi" để chọn khu vực. Hàng biểu tượng danh mục: Tất cả, Supper club, Thời trang, Phòng tranh, Nhạc, Pop-up.', '"Near · Everywhere" picks an area. The category icon row: All, Supper club, Fashion, Gallery, Music, Pop-up.'],
        ['Hàng lọc: "Bộ lọc", "Sắp xếp" (Sớm nhất, Gần nhất, Nổi bật, Giá thấp → cao), chip ngôi sao "Dành cho bạn" luôn đứng đầu, rồi các chip nhanh Hôm nay, Cuối tuần này, Miễn phí, Sắp hết chỗ. Chip nào sẽ cho 0 kết quả thì bị ẩn.', 'The filter row: "Filters", "Sort by" (Soonest, Nearest, Popular, Price: low to high), the gold-star "For You" chip pinned first, then quick chips Today, This weekend, Free, Almost full. A chip that would show 0 events is hidden.'],
        ['Bảng "Bộ lọc" cho thấy số sự kiện cạnh từng lựa chọn trước khi bạn chạm: Khi nào (gồm "Chọn ngày"), Giá (biểu đồ giá, thanh kéo hai đầu, "Giá cho 2 người", "Chỉ miễn phí"), Danh mục, Chỗ ngồi, Khu vực, Sắp xếp. Nhấn "Xem N sự kiện"; "Đặt lại" để xoá lọc.', 'The "Filters" sheet shows how many events each option gives before you tap it: When (including "Pick a date"), Price (price chart, two-handle slider, "Price for 2", "Free only"), Category, Seats, Location, Sort by. Tap "Show N events"; "Reset" clears it.'],
        ['Chuyển giữa "Thẻ" và "Danh sách"; lựa chọn được nhớ. Ít kết quả thì có gợi ý mở rộng một chạm.', 'Switch between "Cards" and "List"; your choice is remembered. With few results you get one-tap hints to widen the search.'],
        ['"Tiếp theo": từ 24 giờ trước đến 12 giờ sau giờ bắt đầu của sự kiện bạn có vé xác nhận, một thẻ "★ Sắp diễn ra" / "Đang diễn ra" hiện lên với lối tắt "Xem vé".', '"Next up": from 24 hours before to 12 hours after an event you have a confirmed ticket for starts, a "★ Starting soon" / "Happening now" banner appears with a "Your ticket" shortcut.'],
        ['"Việc cần làm" (Action Center) liệt kê việc cần bạn: giữ chỗ sắp hết hạn, hoàn tiền cần xác nhận…; "Xem tất cả" mở Thông báo.', '"Things to do" (Action Center) lists what needs you: a hold about to expire, a refund to confirm…; "See all" opens Notifications.'],
        ['"Help Shape Upcoming Events" là các khảo sát công khai bạn có thể trả lời.', '"Help Shape Upcoming Events" lists public surveys you can answer.'],
        ['Sự kiện đã kết thúc không còn hiện ở Trang chính; xem chúng ở mục "Sự kiện đã qua" trên trang host.', 'Ended events no longer appear on Home; find them under "Past events" on the host\'s page.'],
      ]],
      ['h', '"Dành cho bạn"', '"For You"'],
      ['ul', [
        ['Chip chỉ hiện khi có sự kiện khớp câu trả lời sở thích của bạn, và có ở cả Trang chính lẫn Bản đồ. Trên Bản đồ, bật chip không di chuyển bản đồ, và có lối "Chỉnh sở thích của bạn".', 'The chip only shows when events match your preference answers, on both Home and Map. On Map, turning it on does not move the map, and it offers "Edit preferences".'],
        ['Khi có sự kiện mới khớp sở thích, chip lấp lánh vài giây rồi giữ nhãn "Mới" nhỏ cho đến khi bạn mở nó. Sự kiện cũ, không khớp hoặc bản nháp không bao giờ gây báo. Nếu bật "Giảm chuyển động", chip chỉ hiện nhãn tĩnh.', 'When a new event matches your preferences, the chip shimmers for a few seconds, then keeps a small "New" label until you open it. Older events, non-matching events and drafts never trigger it. With Reduce Motion on, it just shows a static label.'],
      ]],
      ['h', 'Tìm kiếm', 'Search'],
      ['p', 'Chạm ô tìm kiếm để mở màn hình Tìm kiếm: "Tìm gần đây" (lưu trên máy này, "Xoá" để xoá), "Danh mục", "Đang được quan tâm". Kết quả chia nhóm Sự kiện, Host, Khu vực; "Xem trên bản đồ" mang từ khoá sang Bản đồ.', 'Tap the search bar to open Search: "Recent" (kept on this device; "Clear" removes it), "Categories" and "Trending today". Results are grouped into Events, Hosts and Areas; "See on map" carries the search over to Map.'],
      ['h', 'Bản đồ', 'Map'],
      ['p', 'Tìm theo tên, khu vực, từ khóa, danh mục hoặc host. Dùng "Còn chỗ", "Gần bạn", "Search here"; chọn khu vực ở "Tất cả khu vực"; chuyển giữa "Big list" và "Big map"; nhấn ghim rồi "View details".', 'Search by name, area, keyword, category or host. Use "Open now", "Nearby" and "Search here"; pick an area under "All areas"; switch between "Big list" and "Big map"; tap a pin then "View details".'],
      ['h', 'Story', 'Stories'],
      ['p', 'Hàng vòng tròn story chỉ hiện khi có story; story của host tự hết hạn sau 24 giờ.', 'The story ring row only appears when there are stories; host stories expire after 24 hours.'],
    ]},
    { id: 'event', vi: 'Trang sự kiện', en: 'The event page', blocks: [
      ['ul', [
        ['Trên ảnh: nút quay lại, "⋯", Chia sẻ và Lưu (trái tim). Sự kiện đã lưu được giữ trong tài khoản của bạn và hiện nhãn "Đã lưu".', 'Over the photo: back, "⋯", Share and Save (heart). Saved events are kept in your account and show a "Saved" tag.'],
        ['Menu "⋯": "Xem trên bản đồ" (hoặc "Về trang chính"), "Sao chép link"; host có thêm "Chia sẻ lên Story".', 'The "⋯" menu: "Open in map" (or "Back to home") and "Copy link"; hosts also get "Share to Story".'],
        ['Nút "Thêm lịch" cạnh tên sự kiện; xem mục Lịch & lịch hẹn.', 'The "Add to calendar" pill next to the title; see Schedule & calendars.'],
        ['Ô "Ngày", "Giờ", "Địa điểm" (chạm "Xem bản đồ" để chỉ đường), thanh "Còn N chỗ", và mô tả có "Xem thêm".', '"Date", "Time" and "Place" tiles (tap "Directions" for the map), a "N seats left" bar, and the description with "Read more".'],
        ['"Bao gồm" cho biết giá vé gồm những gì; "Xem thêm" mở "Giới thiệu & Bao gồm".', '"Included" says what the ticket covers; "More" opens "About & Included".'],
        ['Mục "Người tổ chức": "Xem hồ sơ" mở trang host (lịch sử, ảnh, người theo dõi, sự kiện đã qua); "Nhắn tin" nhắn trực tiếp cho host. Host bạn theo dõi có dấu "✓ Đang theo dõi".', 'The "Host" section: "View profile" opens the host page (track record, photos, followers, past events); "Message" chats with the host. Hosts you follow show "✓ Following".'],
        ['Trạng thái: Hết chỗ, sự kiện đã bị hủy, sự kiện đã kết thúc, hoặc xem trạng thái thanh toán nếu bạn đã giữ chỗ.', 'States: Sold out, Event has been cancelled, Event has ended, or your payment status if you already hold a seat.'],
      ]],
      ['h', 'Ai có thể đặt', 'Who can reserve'],
      ['p', 'Một số sự kiện ghi "Ai có thể đặt: …" và chỉ nhận người đã khai báo sở thích/mục tiêu phù hợp. Nếu bạn chưa đủ điều kiện, nút đặt hiện "Chưa đủ điều kiện ▪︎ xem lý do"; chọn "Cập nhật sở thích", sửa rồi "Lưu và quay lại". Đây là thông tin tự khai, không bao giờ dựa trên tuổi, ngân sách, lịch hay ngôn ngữ.', 'Some events say "Who can reserve: …" and only accept people who declared matching interests/goals. If you don\'t qualify, the button reads "Not eligible yet ▪︎ see why"; choose "Update my preferences", change them, then "Save and go back". It is self-declared and never based on age, budget, schedule or language.'],
      ['h', 'Sự kiện chỉ dành cho người được mời', 'Invite-only events'],
      ['p', 'Sự kiện "Private ▪︎ invite only" chỉ người được host mời mới xem và đặt được.', 'A "Private ▪︎ invite only" event can only be seen and booked by people the host invited.'],
    ]},
    { id: 'schedule', vi: 'Lịch & lịch hẹn', en: 'Schedule & calendars', blocks: [
      ['p', 'Tab "Lịch" (hoặc Tài khoản > "Lịch của tôi") có hai phần: "Lịch của tôi" và "Khám phá", cùng nút "Hôm nay", dải tuần và chế độ xem tháng.', 'The "Schedule" tab (or Account > "My schedule") has two parts, "My schedule" and "Discover", plus "Today", a week strip and a month view.'],
      ['ul', [
        ['Mỗi mục ghi rõ nguồn: "Đã đặt chỗ", "Chờ host xác nhận", "Đang giữ chỗ", "Bạn tổ chức" hoặc "Bạn đã thêm". Sự kiện chỉ lưu (trái tim) không tự vào lịch.', 'Each plan says where it comes from: "Booked", "Awaiting host confirmation", "Seat on hold", "You\'re hosting" or "Added by you". Events you only saved (heart) are not added.'],
        ['"＋ Thêm vào lịch banbe" ghi sự kiện vào lịch để nhớ, KHÔNG phải giữ chỗ. Chỉ mục bạn tự thêm mới có "Bỏ khỏi lịch". Mục tự thêm chỉ nằm trên máy/trình duyệt này, không đồng bộ.', '"＋ Add to banbe Schedule" puts an event in your plans as a reminder; it is NOT a reservation. Only plans you added yourself have "Remove". They stay on this device/browser and do not sync.'],
        ['Nếu hai kế hoạch cách nhau dưới 2 giờ, bạn được nhắc, nhưng vẫn thêm được.', 'If two plans start within 2 hours of each other you get a note, but adding is never blocked.'],
      ]],
      ['h', 'Thêm vào lịch điện thoại', 'Adding to your phone\'s calendar'],
      ['ul', [
        ['Trên web: nút "Thêm lịch" ở trang sự kiện có "Thêm vào lịch (.ics)" và "Google Lịch"; trang vé có "Google Calendar" và "Lịch Apple ▪︎ Ứng dụng khác".', 'On the web: the event page\'s "Add to calendar" pill offers "Add to calendar (.ics)" and "Google Calendar"; the ticket screen offers "Google Calendar" and "Apple Calendar ▪︎ Other apps".'],
        ['Trên iPhone: "Thêm vào Lịch Apple" mở trình sửa sự kiện của hệ thống, không cần cấp quyền lịch.', 'On iPhone: "Add to Apple Calendar" opens the system event editor; no calendar permission is needed.'],
        ['Sự kiện không ghi giờ kết thúc được đặt mặc định 2 giờ.', 'Events without an end time default to 2 hours.'],
      ]],
    ]},
    { id: 'book', vi: 'Giữ chỗ & đặt vé', en: 'Holding a seat & booking', blocks: [
      ['ol', [
        ['Ở thanh dưới trang sự kiện, chọn số vé ("1 vé · 2 vé · 3 vé" hoặc nút − / +, tối đa 6), rồi nhấn "Giữ chỗ ▪︎ <tổng tiền>". Dòng giữa cho biết chính sách: hoàn tiền 100% nếu sự kiện bị hủy, hoặc chỗ được giữ 30 phút.', 'In the event page\'s bottom bar, pick the number of tickets ("1 ticket · 2 tickets · 3 tickets" or − / +, up to 6), then tap "Reserve ▪︎ <total>". The middle line shows the policy: full refund if the event is cancelled, or seats held for 30 minutes.'],
        ['Mỗi sự kiện chỉ một đặt chỗ đang hiệu lực. Thanh tiến trình cho thấy các bước Sự kiện → Giữ chỗ → Thanh toán → Vé.', 'One live booking per event. A progress bar shows Event → Hold → Pay → Ticket.'],
        ['Nhập "Full name" cho từng người tham dự. Vé 1 là của bạn: ngày sinh được lấy tự động từ hồ sơ. Với các vé còn lại, nhập "Date of birth" và có thể điền "Email (optional)". Nút xác nhận ghi rõ còn thiếu gì nếu chưa bấm được.', 'Enter "Full name" for each attendee. Ticket 1 is yours: the date of birth comes from your profile. For the other tickets, enter "Date of birth" and optionally "Email (optional)". If the confirm button is disabled it says what is missing.'],
        ['Nhấn "Giữ 1 chỗ ▪︎ 30 phút" (hoặc "Giữ N chỗ"). Sự kiện miễn phí: vé được cấp ngay. Sự kiện có phí: ghế được giữ 30 phút để bạn chuyển tiền.', 'Tap "Hold 1 seat ▪︎ 30 min" (or "Hold N seats"). Free event: the ticket is issued immediately. Paid event: the seat is held for 30 minutes while you pay.'],
      ]],
      ['p', 'Nếu ngày sinh lấy từ hồ sơ bị sai, nhấn "Wrong? Request a correction" dưới ngày sinh ở Vé 1, nhập ngày đúng và lý do. Quản trị viên sẽ xem xét; ngày sinh chỉ đổi khi yêu cầu được duyệt. Email của người tham dự chỉ được lưu cùng vé, chưa gửi thư nào đến địa chỉ đó.', 'If the date of birth taken from your profile is wrong, tap "Wrong? Request a correction" under it on Ticket 1, then enter the right date and a reason. An admin reviews it; your birthday only changes if approved. An attendee\'s email is only saved with the ticket; nothing is sent to that address yet.'],
      ['p', 'Một số sự kiện cần host chấp nhận yêu cầu của bạn trước khi thanh toán. Hết chỗ: nút hiện "Hết chỗ ▪︎ nhắn để vào danh sách chờ".', 'Some events need the host to accept your request before you pay. When sold out, the button reads "Sold out ▪︎ message for waitlist".'],
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
    { id: 'tickets', vi: 'Vé, mã QR & PDF', en: 'Tickets, QR & PDF', blocks: [
      ['ul', [
        ['Mỗi người tham dự có mã QR và mã vào cửa riêng; mỗi người xuất trình mã của chính mình ở cửa.', 'Each attendee has their own QR and entry code; each person shows their own code at the door.'],
        ['"Download PDF" tải từng vé; có thể tick nhiều vé để tải ZIP hoặc "Download all".', '"Download PDF" saves one ticket; tick several for a ZIP, or "Download all".'],
        ['Thêm vào lịch điện thoại: xem mục Lịch & lịch hẹn.', 'Adding to your phone\'s calendar: see Schedule & calendars.'],
        ['"View Receipt" xem biên lai/hóa đơn do host tải lên; "Request Receipt" nhờ host gửi nếu chưa có.', '"View Receipt" opens the receipt/invoice the host uploaded; "Request Receipt" asks the host if there is none yet.'],
        ['Vé hiển thị "Checked in" sau khi được quét.', 'A ticket shows "Checked in" once scanned.'],
      ]],
      ['tip', 'Mã QR chỉ xuất hiện sau khi host xác nhận thanh toán. Nút "Thêm vào Apple Wallet" có thể hiện trên thiết bị Apple nhưng chưa hoạt động.', 'The QR appears only after the host confirms payment. An "Add to Apple Wallet" button may appear on Apple devices but does not work yet.'],
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
      ['h', 'Host báo "không thấy tiền"', 'The host says "can\'t find it"'],
      ['ul', [
        ['Một khung chat tạm thời mở ra giữa bạn và host, kèm đồng hồ "Đóng sau ~N giờ". Hai bên có 2 ngày để làm rõ; hãy gửi thêm bằng chứng chuyển khoản.', 'A temporary chat opens between you and the host, with a "Closes in ~Nh" timer. You both have 2 days to sort it out; send more proof of your transfer.'],
        ['Khi host xác nhận đã nhận tiền, vé được cấp và chat tự đóng. Nếu đặt chỗ bị hủy, chat cũng tự đóng.', 'When the host confirms the money arrived, your ticket is issued and the chat closes by itself. If the booking is cancelled, the chat also closes.'],
        ['Hết 2 ngày mà không thống nhất và không ai chuyển lên banbe: vé được trả lại kho và chat đóng.', 'If 2 days pass with no agreement and nobody escalated to banbe, the ticket goes back on sale and the chat closes.'],
        ['Nếu được chuyển lên banbe ("Raise a dispute" / host "Escalate to banbe"), quản trị viên đọc chat và quyết định; ghế vẫn được giữ trong lúc chờ.', 'If it is escalated to banbe ("Raise a dispute" / the host\'s "Escalate to banbe"), admins read the chat and decide; your seat stays held meanwhile.'],
      ]],
      ['h', 'Trong khung chat khiếu nại', 'In the dispute chat'],
      ['ul', [
        ['Quản trị viên đọc được chat. Có thể đính kèm ảnh JPG/PNG/WebP hoặc PDF (tối đa 20 MB). Tin nhắn không sửa hoặc xóa được.', 'Admins can read the chat. You can attach JPG/PNG/WebP or PDF files (max 20 MB). Messages cannot be edited or deleted.'],
        ['"Đóng tranh chấp" kết thúc tranh chấp. Sau đó có thể "Download transcript" và "Đóng và xoá bản của tôi" (chỉ ẩn bản của bạn).', '"Close dispute" ends it. Afterwards you can "Download transcript" and "Close and delete my copy" (hides only your copy).'],
        ['Dữ liệu tranh chấp hoàn tiền được xóa 7 ngày sau khi đóng.', 'Refund-dispute data is purged 7 days after it closes.'],
      ]],
    ]},
    { id: 'chat', vi: 'Tin nhắn & thông báo', en: 'Messages & notifications', blocks: [
      ['ul', [
        ['Tab "Tin nhắn": các cuộc trò chuyện với host. Cuộc trò chuyện chỉ xuất hiện sau tin nhắn đầu tiên bạn gửi. Menu "..." cho phép Star, Archive, Delete (xóa chỉ với bạn).', 'The "Messages" tab holds your chats with hosts. A chat appears only after you send the first message. The "..." menu offers Star, Archive, Delete (removes it for you only).'],
        ['Gửi ảnh hoặc tài liệu bằng "Add photo or document" / "Camera".', 'Send photos or documents with "Add photo or document" / "Camera".'],
        ['Thông báo từ host: gần giờ sự kiện, host có thể gửi một tin "📣 Thông báo từ host" (bong bóng đỏ trong chat) kèm một thông báo.', 'Host announcements: close to the event, the host may send a "📣 Host announcement" (a red bubble in the chat) plus a notification.'],
        ['Thông báo: chạm chuông ở đầu Trang chính (có số chưa đọc), hoặc Tài khoản > "Thông báo", hoặc "Xem tất cả" trong Việc cần làm. Nhóm Mới / Hôm nay / 7 ngày qua / Cũ hơn; đánh dấu đã đọc, tắt loại thông báo, xóa, chọn nhiều.', 'Notifications: tap the bell at the top of Home (it shows the unread count), or Account > "Notifications", or "See all" in Things to do. Grouped New / Today / Last 7 days / Older; mark read, mute a kind, delete, multi-select.'],
        ['Thông báo trong ứng dụng và email đang hoạt động; thông báo đẩy (push) chưa bật.', 'In-app and email notifications work; push notifications are not enabled yet.'],
      ]],
    ]},
    { id: 'survey', vi: 'Khảo sát', en: 'Surveys', blocks: [
      ['p', 'Host dùng khảo sát để đo nhu cầu. Mở một khảo sát từ Trang chính hoặc story, điền mức quan tâm, thời gian/địa điểm ưa thích, quy mô nhóm, ngân sách…, tick đồng ý để host liên hệ về sự kiện đó, rồi "Submit response".', 'Hosts use surveys to gauge demand. Open one from Home or a story, fill in interest, preferred time/place, group size, budget…, tick consent for the host to contact you about that event, then "Submit response".'],
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
      ['h', 'Theo dõi host', 'Following hosts'],
      ['ul', [
        ['Nhấn "Theo dõi" trên trang host; nút đổi thành "✓ Đang theo dõi".', 'Tap "Follow" on a host\'s page; it changes to "✓ Following".'],
        ['Tài khoản > "Đang theo dõi" liệt kê các host bạn theo dõi (có ô tìm kiếm). Danh sách này chỉ mình bạn thấy. "Bỏ theo dõi" sẽ hỏi xác nhận.', 'Account > "Following" lists the hosts you follow (with a search box). Only you can see this list. "Unfollow" asks you to confirm.'],
      ]],
    ]},
    { id: 'keychain', vi: 'Móc khoá trang trí hồ sơ', en: 'Profile keychain charm', blocks: [
      ['p', 'Móc khoá là một món trang trí nhỏ treo ở góc thẻ hồ sơ. Mặc định tắt; khi bật, người xem hồ sơ của bạn cũng thấy nó.', 'The keychain is a small decoration hanging from a corner of your profile card. It is off by default; when on, people who view your profile see it too.'],
      ['h', 'Bật và chỉnh móc khoá', 'Turn it on and customise it'],
      ['ol', [
        ['Mở hồ sơ của bạn rồi nhấn "Edit charm", hoặc vào Edit profile > Keychain.', 'Open your profile and tap "Edit charm", or go to Edit profile > Keychain.'],
        ['Bật công tắc, chọn một trong 24 mẫu miễn phí (nhóm sao/trăng/mây, tim/nơ, hoa/trái cây, cà phê/âm nhạc, mèo/gấu, du lịch/vé, họa tiết banbe).', 'Switch it on and pick one of 24 free designs (stars/moon/clouds, hearts/ribbons, flowers/fruits, coffee/music, cats/bears, travel/tickets, banbe motifs).'],
        ['Chọn một trong bốn góc, kích cỡ S/M/L và bật/tắt chuyển động. Xem trước ngay trong màn hình rồi nhấn Save; Cancel sẽ bỏ thay đổi.', 'Choose one of four corners, size S/M/L and motion on/off. Preview it on the screen, then tap Save; Cancel discards changes.'],
      ]],
      ['p', 'Khi banbe bật Phần thưởng, có thêm vài mẫu có khoá đổi bằng xu (xem mục Phần thưởng & huy hiệu).', 'When banbe turns Rewards on, a few extra locked designs can be unlocked with coins (see Rewards & badges).'],
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
    { id: 'rewards', vi: 'Phần thưởng & huy hiệu', en: 'Rewards & badges', blocks: [
      ['p', 'Phần thưởng chỉ hiện khi banbe bật tính năng này; khi tắt, xu, chuỗi ngày, huy hiệu và mẫu móc khoá thưởng bị ẩn ở mọi nơi (dữ liệu của bạn không bị xoá).', 'Rewards only appear when banbe has turned the feature on; while it is off, coins, streaks, badges and reward keychain designs are hidden everywhere (your data is not deleted).'],
      ['ul', [
        ['Mở từ Tài khoản > "Phần Thưởng & Huy Hiệu" hoặc nút 🔥/xu ở đầu Trang chính: số dư xu, chuỗi ngày, huy hiệu, đổi thưởng (móc khoá), lịch sử và "Cách kiếm xu".', 'Open it from Account > "Rewards & Badges" or the 🔥/coin buttons at the top of Home: coin balance, streak, badges, redeem (keychain designs), recent history and "How earning works".'],
        ['Xu đến từ việc hoàn tất thiết lập ban đầu có câu trả lời và từ việc được host check-in thật tại sự kiện (có giới hạn mỗi tháng). Huy hiệu là riêng tư.', 'Coins come from finishing first-run setup with answers and from being genuinely checked in by a host at an event (capped per month). Badges are private.'],
        ['Ba mẫu móc khoá thưởng đổi bằng xu; 24 mẫu thường luôn miễn phí.', 'Three reward keychain designs are unlocked with coins; the 24 regular designs stay free.'],
      ]],
    ]},
    { id: 'reports', vi: 'Số liệu của bạn', en: 'Your metrics', blocks: [
      ['p', 'Tài khoản > "Số Liệu & Báo Cáo" cho thấy số chỗ đã xác nhận của bạn theo 7/30/90 ngày hoặc khoảng tùy chọn. "Cần chú ý" chỉ hiện khi bạn còn khoản hoàn tiền đang chờ. Xuất PDF/JSON từ menu "⋯", CSV hoặc ảnh biểu đồ từ từng số liệu.', 'Account > "Metrics & Reports" shows your confirmed bookings for 7/30/90 days or a custom range. "Needs attention" only appears while you have refunds outstanding. Export PDF/JSON from the "⋯" menu, and CSV or a chart image from each metric.'],
    ]},
    { id: 'settings', vi: 'Cài đặt, bảo mật & xóa tài khoản', en: 'Settings, security & deleting your account', blocks: [
      ['ul', [
        ['Account > Settings: ngôn ngữ (Tiếng Việt / English) và giao diện (Light / Dark). Ngôn ngữ cũng áp dụng cho tin nhắn tự động.', 'Account > Settings: language (Vietnamese / English) and appearance (Light / Dark). Language also applies to automated messages.'],
        ['"Sở thích sự kiện": sửa câu trả lời dùng cho "Dành cho bạn" và điều kiện đặt chỗ.', '"Event preferences": change the answers used for "For You" and reservation criteria.'],
        ['"Security": đổi mật khẩu (8+ ký tự) và xem trạng thái xác minh điện thoại.', '"Security": change your password (8+ characters) and see your phone-verification status.'],
        ['"Gửi hoá đơn qua email" tự động email bản sao hóa đơn/biên lai cho bạn; "Tin nhắn quảng bá từ host" mặc định tắt.', '"Email me payment documents" automatically emails you copies of invoices/receipts; "Host promotional texts" is off unless you turn it on.'],
        ['Đăng xuất bằng "Sign out" trong Account.', 'Log out with "Sign out" in Account.'],
      ]],
      ['h', 'Xóa tài khoản', 'Deleting your account'],
      ['ol', [
        ['Account > Settings > Account Management > "Delete Account".', 'Account > Settings > Account Management > "Delete Account".'],
        ['Màn hình "Trước khi bạn đi…" cho thấy những gì bạn sẽ mất, hỏi lý do và có thể gợi ý một cách khắc phục (ví dụ tắt bớt thông báo hoặc chỉnh lại gợi ý). Chọn "Giữ tài khoản của tôi" hoặc "Tiếp tục xoá tài khoản".', 'A "Before you go…" screen shows what you\'d lose, asks why you\'re leaving and may offer one fix (for example quieter notifications or retuned suggestions). Choose "Keep my account" or "Continue deleting my account".'],
        ['"Bước 1 — Xác minh danh tính": nhập ngày sinh, hoặc "Dùng mã gửi qua email thay thế" (mã 8 chữ số).', '"Step 1 — Verify it\'s you": enter your date of birth, or "Use an emailed code instead" (8-digit code).'],
        ['Gõ đúng cụm từ xác nhận và nhấn "Permanently delete account".', 'Type the exact confirmation phrase and tap "Permanently delete account".'],
      ]],
      ['tip', 'Không thể hoàn tác. Bạn không xóa được khi còn sở hữu sự kiện đang mở; hãy hủy hoặc kết thúc sự kiện trước. Yêu cầu bản sao dữ liệu: liên hệ email nêu trong Điều khoản.', 'This cannot be undone. You cannot delete while you still own an open event; cancel or end it first. To request a copy of your data, use the contact email in the Terms.'],
    ]},
    { id: 'search', vi: 'Tìm kiếm trong Tài khoản', en: 'Searching inside Account', blocks: [
      ['p', 'Ô "Search Account…" trên màn hình Account tìm mọi mục (cài đặt, vé, hoàn tiền, trợ giúp…) và mở thẳng tới đó.', 'The "Search Account…" box on the Account screen finds any entry (settings, tickets, refunds, help…) and jumps straight to it.'],
    ]},
  ],
};

<!-- DRAFT. NOT the policy. banbe_User_Policy.md is unchanged. Bilingual: each clause has Vietnamese (VI) and English (EN) side by side. -->

# Bản nháp cập nhật chính sách: Phần thưởng, ưu đãi và dữ liệu
# Draft policy update: Rewards, offers and data

> **CẦN LUẬT SƯ DUYỆT · LAWYER REVIEW REQUIRED.** Đây là bản nháp nội bộ do kỹ thuật soạn từ những gì hệ thống thực sự làm (migration 165–180) và từ `docs/rewards-research.md`. Không phải tư vấn pháp lý hay thuế. Không điều khoản nào dưới đây có hiệu lực cho tới khi luật sư duyệt, `banbe_User_Policy.md` được sửa, và người dùng được thông báo (mục 6).
> **LAWYER REVIEW REQUIRED.** This is an internal engineering draft written from what the system actually does (migrations 165–180) and from `docs/rewards-research.md`. It is not legal or tax advice. Nothing below takes effect until a lawyer approves it, `banbe_User_Policy.md` is amended, and users are notified (section 6).

> **Quyết định hiện tại / Current decision (2026-10-11): Phương án A được chọn tạm thời; Phương án B chỉ khi có đối tác thật và luật sư duyệt.**
> **Option A is chosen provisionally; Option B only once there is a real partner and the lawyer has approved it.**

**Nhãn trạng thái / Status labels.** `[ĐANG CÓ · LIVE-IN-CODE]` = hệ thống đã làm đúng như vậy (đã áp dụng hoặc nằm trong nhánh `feat/rewards-phase0`). `[CHƯA CÓ · NOT BUILT]` = đề xuất, chưa có trong code. `[CẦN QUYẾT ĐỊNH · DECISION]` = cần chủ sản phẩm chọn. Migration 177–180 chưa được áp dụng lên production tại thời điểm soạn.

---

## 1. Coin và huy hiệu · Coins and badges

**1.1 Bản chất · Nature** `[ĐANG CÓ · LIVE-IN-CODE]`

VI: Xu (coin) và huy hiệu trong banbe là điểm ghi nhận hoạt động trong ứng dụng. Xu **không có giá trị tiền**, **không thể mua**, **không thể chuyển** cho người khác và **không thể đổi ra tiền mặt**. banbe không công bố, không nhận và không áp dụng tỷ giá nào giữa xu và tiền. Xu và huy hiệu không ảnh hưởng đến việc đặt chỗ, thứ tự ưu tiên hay điều kiện tham gia sự kiện của bạn.

EN: Coins and badges in banbe are points that record activity in the app. Coins have **no cash value**, **cannot be bought**, **cannot be transferred** to anyone else and **cannot be exchanged for money**. banbe publishes, accepts and applies no exchange rate between coins and money. Coins and badges do not affect your booking, priority or eligibility for events.

**1.2 Khi nào được cấp xu · When coins are granted** `[ĐANG CÓ · LIVE-IN-CODE]`

VI: Hiện nay xu chỉ được cấp khi (a) host xác nhận bạn đã có mặt tại một sự kiện (mỗi sự kiện khác nhau tính một lần), hiện là 20 xu; và (b) bạn hoàn thành bộ câu hỏi sở thích lần đầu có trả lời, một lần duy nhất, hiện là 10 xu. Chủ sự kiện, thành viên nhóm của host và việc tự điểm danh không được tính. Mỗi tháng tối đa 10 sự kiện được tính xu (200 xu); vượt mức đó bạn vẫn tiến tới huy hiệu và chuỗi ngày nhưng không có thêm xu. Không có xu cho việc mở ứng dụng, chi tiêu, thích, theo dõi, lưu lặp lại, tải lên, huỷ, hay đồng ý nhận tin. Các con số có thể thay đổi; mỗi lần thay đổi có số phiên bản quy tắc mới.

EN: Today coins are granted only when (a) a host confirms you attended an event (each different event counts once), currently 20 coins; and (b) you complete the preference questions with answers for the first time, once only, currently 10 coins. Event owners, a host's team members and self check-ins do not count. At most 10 events per month earn coins (200 coins); beyond that you still progress toward badges and your streak but earn no more coins. There are no coins for opening the app, spending, likes, follows, repeated saves, uploads, cancellations or giving consent. The numbers may change; each change gets a new rules version number.

**1.3 Huy hiệu và chuỗi ngày · Badges and streaks** `[ĐANG CÓ · LIVE-IN-CODE]`

VI: Huy hiệu được tính từ các sự kiện có thật (ví dụ số sự kiện bạn đã được xác nhận tham dự) và chỉ hiển thị riêng tư cho bạn. Chuỗi ngày đếm các ngày bạn lưu một sự kiện (máy chủ xác minh) hoặc được xác nhận tham dự; bỏ lỡ một ngày không bị trừ xu hay khoá tính năng.

EN: Badges are derived from real events (for example the number of events you were confirmed at) and are shown privately to you only. The streak counts days on which you save an event (verified by the server) or are confirmed as attending; missing a day never costs coins or blocks anything.

**1.3b Chuỗi tuần, tuần nghỉ, khôi phục và mục tiêu tháng · Week streak, grace weeks, repair and monthly goal** `[ĐÃ VIẾT, cờ TẮT · WRITTEN, flag OFF, migration 192]`

VI: Khi bật, chuỗi được tính theo **tuần** (thứ Hai–Chủ nhật, theo múi giờ ở 1.4): một tuần được tính nếu bạn có ít nhất một ngày hoạt động như ở 1.3. Cứ 4 tuần hoạt động bạn nhận một **tuần nghỉ** (giữ tối đa 2), tự động che một tuần bạn bỏ lỡ; tuần nghỉ không thể mua, không có giá trị và không đổi được. Nếu một chuỗi từ 4 tuần trở lên bị ngắt, việc được xác nhận tham dự một sự kiện trong 14 ngày sau đó sẽ khôi phục chuỗi. Bạn có thể tự đặt **mục tiêu tháng** (1, 2 hoặc 4 sự kiện) và xoá bất kỳ lúc nào; chúng tôi lưu con số bạn chọn và thời điểm đặt. Chuỗi, tuần nghỉ và mục tiêu **không bao giờ tạo ra xu**, không ảnh hưởng đến đặt chỗ, và bỏ lỡ không bị phạt. Huy hiệu có nhiều **cấp** và có huy hiệu **theo mùa** (tính theo sự kiện diễn ra trong khoảng thời gian ghi rõ); tất cả vẫn chỉ hiển thị riêng tư cho bạn.

EN: When switched on, the streak counts **weeks** (Monday–Sunday, in the time zone of 1.4): a week counts if you have at least one active day as in 1.3. Every 4 active weeks earn a **grace week** (hold up to 2) that automatically covers a week you miss; grace weeks cannot be bought, have no value and cannot be exchanged. If a streak of 4 weeks or more breaks, being confirmed at an event within the following 14 days restores it. You can set a **monthly goal** (1, 2 or 4 events) and clear it at any time; we store the number you chose and when you set it. Streaks, grace weeks and goals **never create coins**, never affect booking, and missing them carries no penalty. Badges have **tiers** and there are **seasonal** badges (counted from events taking place in a stated window); all of them remain private to you.

**1.3c Khung giờ điểm danh để được tính xu · Check-in window for coins** `[ĐÃ VIẾT · WRITTEN, migration 191]`

VI: Xu tham dự chỉ được tính khi người tổ chức điểm danh bạn trong khoảng từ 3 giờ trước đến 24 giờ sau giờ bắt đầu sự kiện. Điểm danh ngoài khoảng đó vẫn được ghi nhận là tham dự (huy hiệu, chuỗi) nhưng không có xu. Nếu một sự kiện bị huỷ hoặc bị banbe gỡ bỏ, xu từ sự kiện đó được trừ lại như khi điểm danh bị huỷ.

EN: Attendance coins are paid only when the host checks you in between 3 hours before and 24 hours after the event's start. A check-in outside that window still counts as attendance (badges, streak) but pays no coins. If an event is cancelled or removed by banbe, the coins from it are reversed in the same way as an undone check-in.

**1.4 Múi giờ của chuỗi ngày · Time zone for streak days** `[ĐANG CÓ · LIVE-IN-CODE, migration 177]`

VI: Ngày của chuỗi và tháng của mức trần xu mặc định theo giờ Việt Nam (Asia/Ho_Chi_Minh). Bạn có thể tự chọn múi giờ khác trong phần Phần thưởng; banbe không tự đoán múi giờ từ vị trí của bạn. Thay đổi có hiệu lực từ ngày kế tiếp, tối đa 2 lần trong 30 ngày. Dữ liệu cũ không bị tính lại. Khi đổi múi giờ giữa tháng, các mục đã ghi trước đó được xếp tháng theo cách đã dùng lúc ghi, nên ranh giới tháng có thể lệch tối đa vài giờ.

EN: Streak days and the month of the coin cap default to Vietnam time (Asia/Ho_Chi_Minh). You can choose another time zone in Rewards; banbe does not guess your time zone from your location. A change takes effect from the next day, at most twice in 30 days. Past data is not recalculated. If you change zone mid-month, entries already recorded keep the month they were recorded under, so a month boundary can be off by a few hours.

**1.5 Thu hồi khi gian lận · Reversal for fraud or error** `[ĐANG CÓ một phần · PARTLY LIVE; quyết định của quản trị viên · admin decision]`

VI: Xu được cấp do lỗi, do điểm danh bị huỷ, do sự kiện bị huỷ, hoặc do gian lận (ví dụ host xác nhận cho tài khoản không thực sự tham dự, hoặc một người dùng nhiều tài khoản) có thể bị thu hồi. Việc thu hồi được ghi thành một dòng điều chỉnh riêng, không sửa lịch sử. Hệ thống có thể gắn cờ rủi ro để quản trị viên xem xét; cờ **không** tự thu hồi xu, không chặn tài khoản và không tự động quyết định. Chỉ quản trị viên (con người) quyết định thu hồi; bạn có thể liên hệ chúng tôi để phản đối.

EN: Coins granted by mistake, because a check-in was undone, because an event was cancelled, or through fraud (for example a host confirming an account that did not really attend, or one person using several accounts) may be reversed. A reversal is recorded as a separate adjustment entry; history is not edited. The system may raise risk flags for an administrator to review; a flag does **not** automatically reverse coins, block an account or decide anything. Only an administrator (a person) decides on a reversal; you can contact us to object.

**1.6 Số dư âm · Negative balance** `[ĐANG CÓ · LIVE-IN-CODE]`

VI: Nếu xu bị thu hồi sau khi bạn đã dùng chúng, số dư có thể âm cho tới khi bạn kiếm lại. Phần thưởng đã mở khoá không bị thu hồi, và số dư âm không khoá tính năng nào. `[CẦN QUYẾT ĐỊNH · DECISION]` giữ nguyên, hay bù trừ bằng cách khác.

EN: If coins are reversed after you spent them, your balance can go negative until you earn it back. Already unlocked rewards are not taken away, and a negative balance blocks no feature. `[DECISION]` keep as is, or settle another way.

**1.7 Phần thưởng hiện có · What coins can be used for today** `[ĐANG CÓ · LIVE-IN-CODE]`

VI: Hiện chỉ có 3 mẫu móc khoá trang trí tuỳ chọn; 24 mẫu miễn phí luôn dùng được. Không có phiếu, tiền, quà hay rút thăm.

EN: Today there are only 3 optional decorative keychain designs; the 24 free charms always stay available. There are no vouchers, money, gifts or draws.

---

## 2. Hạn dùng xu · Coin expiry `[CHƯA CÓ · NOT BUILT] [CẦN QUYẾT ĐỊNH · DECISION]`

VI: **Đề xuất:** xu **kiếm được** hết hạn sau 12 tháng không có hoạt động nào được tính (điểm danh hoặc hoàn thành bộ câu hỏi), có thông báo trước trong ứng dụng ít nhất 30 ngày. Hết hạn được ghi thành một dòng điều chỉnh riêng, không sửa lịch sử. Hiện **không có** cơ chế hết hạn trong code; thêm nó cần một migration mới và thay đổi giao diện. Quy tắc này chỉ áp dụng cho xu kiếm được, và vì xu không có giá trị tiền nên hạn dùng không phải là mất tiền, nhưng vẫn cần nêu rõ cho người dùng.

EN: **Proposal:** **earned** coins expire after 12 months with no qualifying activity (a check-in or completing the preference questions), with in-app notice at least 30 days beforehand. Expiry is recorded as a separate adjustment entry; history is not edited. There is **no** expiry mechanism in the code today; adding one needs a new migration and UI changes. The rule applies to earned coins only; coins have no cash value so expiry is not a loss of money, but it must still be stated clearly.

VI: **Xung đột với việc bán xu (nếu sau này có).** Hiện banbe **không bán** xu và không có đường mua xu. Nếu sau này banbe bán xu bằng mua trong ứng dụng, quy định App Store Review Guidelines 3.1.1 (đã đối chiếu trong `docs/rewards-research.md` mục 6.4, ngày tra cứu 2026-10-08, có thể đã thay đổi) yêu cầu tiền tệ trong ứng dụng mua bằng IAP **không được hết hạn**. Hai quy tắc loại trừ nhau trên cùng một loại xu. Vì vậy, nếu có bán xu thì phải có **hai loại tách biệt**: *xu kiếm được* (hết hạn, không bao giờ mua được, không đổi sang xu mua) và *xu mua* (không hết hạn, theo luật về giá trị lưu trữ/phiếu quà tặng, mà chúng tôi **không khuyến nghị làm** khi chưa có luật sư; xem câu hỏi 7 và 9 ở mục 8). Không được quy đổi qua lại giữa hai loại. Đề xuất hiện tại: **không bán xu**.

EN: **Conflict with selling coins (if ever).** banbe does **not** sell coins today and has no way to buy them. If banbe later sold coins through in-app purchase, App Store Review Guideline 3.1.1 (checked in `docs/rewards-research.md` section 6.4 on 2026-10-08; may have changed) requires in-app currency bought via IAP **not to expire**. The two rules exclude each other on the same coin. So if coins are ever sold there must be **two separate kinds**: *earned coins* (expire, can never be bought, never convert into purchased coins) and *purchased coins* (never expire, and fall under stored-value/gift-card law that we **do not recommend entering** without a lawyer; see questions 7 and 9 in section 8). No conversion in either direction. Current proposal: **do not sell coins**.

---

## 3. Ưu đãi do đối tác hoặc host tài trợ · Offers sponsored by partners or hosts `[CHƯA CÓ · NOT BUILT; tồn tại bản nháp dữ liệu · data model only in supabase/drafts]`

**3.1 Hai loại ưu đãi · Two kinds of offer**

VI: (i) **Ưu đãi do host/địa điểm tự đăng:** một host hoặc quán đăng ưu đãi của chính họ cho khách của họ; banbe chỉ hiển thị. (ii) **Ưu đãi được tài trợ, có nhãn rõ:** một đối tác (thương hiệu, địa điểm) trả phí cho banbe để hiển thị ưu đãi; ưu đãi luôn có nhãn "Được tài trợ / Sponsored" và tên bên tài trợ. Hai loại phải hiển thị khác nhau; loại (ii) chỉ có nếu chọn phương án B ở mục 5.

EN: (i) **Host/venue self-posted offers:** a host or venue posts its own offer to its own guests; banbe only displays it. (ii) **Sponsored, clearly labelled offers:** a partner (brand, venue) pays banbe to display an offer; it always carries a "Sponsored" label and the sponsor's name. The two must look different; kind (ii) exists only if option B in section 5 is chosen.

**3.2 Trách nhiệm · Responsibility**

VI: Ưu đãi là của bên đăng/tài trợ. Bên đó chịu trách nhiệm về nội dung, điều kiện, tồn kho, việc thực hiện và mọi nghĩa vụ pháp lý liên quan (khuyến mại, thuế, an toàn thực phẩm, giới hạn độ tuổi, ví dụ đồ uống có cồn). banbe là trung gian hiển thị, **không bảo đảm** ưu đãi sẽ được tôn trọng và không phải bên bán hay phát hành phiếu. banbe không giữ tiền của người dùng và không phát hành mã thay đối tác: đối tác tự thực hiện và tự xác nhận ưu đãi (mã dùng một lần, hạn ngắn).

EN: The offer belongs to the posting/sponsoring party. That party is responsible for content, terms, stock, fulfilment and all related legal duties (promotion rules, tax, food safety, age limits, for example alcohol). banbe is a display intermediary, does **not guarantee** an offer will be honoured and is not the seller or issuer of a voucher. banbe holds no user money and issues no codes on a partner's behalf: the partner fulfils and confirms the offer itself (single-use, short-lived code).

**3.3 Không rút thăm · No draws**

VI: banbe không tổ chức rút thăm, xổ số hay giải thưởng ngẫu nhiên, và không cho đối tác tài trợ những hoạt động đó trong ứng dụng. Ưu đãi mở khoá theo huy hiệu hoặc điểm danh, không theo may rủi. Không dùng các từ "tiền thưởng", "cashback", hay "1 xu = X đồng" trong ứng dụng và quảng bá.

EN: banbe runs no draws, lotteries or random prizes and does not let sponsors run them in the app. Offers unlock by badge or attendance, not by chance. The words "cash reward", "cashback" or "1 coin = X dong" are not used in the app or in promotion.

**3.4 Điều kiện hiển thị · Preconditions** `[CẦN QUYẾT ĐỊNH · DECISION]`

VI: Việc dùng xu để mở khoá ưu đãi đối tác có tạo cảm giác tỷ giá xu–tiền hay không là điểm cần luật sư xem. Đề xuất thận trọng: ưu đãi đối tác mở bằng **huy hiệu/điểm danh** (giá 0 xu), không trừ xu. Hiện 179 không cho đổi ưu đãi (trả `NOT_AVAILABLE`).

EN: Whether using coins to unlock partner offers creates the impression of a coin–money rate is a point for the lawyer. Cautious proposal: partner offers unlock by **badge/attendance** (price 0 coins), not by spending coins. Today 179 does not allow redeeming offers (returns `NOT_AVAILABLE`).

---

## 4. Dữ liệu và quyền riêng tư · Data and privacy

**4.1 Dữ liệu KHÔNG BAO GIỜ chia sẻ với đối tác · Data NEVER shared with partners** `[thiết kế · by design; bản nháp có kiểm tra · tested in the draft]`

VI: banbe không chia sẻ với đối tác, host tài trợ hay bên thứ ba vì mục đích ưu đãi: tên, số điện thoại, email, ngày sinh, địa chỉ; nội dung trò chuyện; tài liệu thanh toán; thông tin hoàn tiền hay tranh chấp; danh sách các sự kiện bạn đã tham dự; danh sách theo dõi (follows); câu trả lời sở thích cá nhân; số dư hoặc lịch sử xu. Đối tác chỉ có thể xác nhận **một mã** do chính họ nhận từ khách và chỉ thấy tên ưu đãi và thời điểm xác nhận. Đối tác không có danh sách người dùng.

EN: For offer purposes banbe does not share with partners, sponsoring hosts or third parties: your name, phone number, email, date of birth or address; chat content; payment documents; refund or dispute information; the list of events you attended; your follows; your personal preference answers; your coin balance or history. A partner can only confirm **one code** it receives from a customer and sees only the offer name and the confirmation time. Partners get no user list.

**4.2 Số liệu tổng hợp về ưu đãi · Aggregate offer statistics** `[ĐÃ VIẾT, cờ TẮT · WRITTEN, flag OFF, migration 180]`

VI: Khi bật, banbe đếm tổng hợp hoạt động ưu đãi: với mỗi ưu đãi, mỗi **ngày** (theo giờ UTC), mỗi **vùng thô** (Việt Nam, Hoa Kỳ, khác, không rõ) và mỗi loại sự kiện (đã xem, đã phát hành, đã dùng), chỉ có **một con số**. Không có bản ghi cho từng lượt xem; không có mã người dùng, số điện thoại, email, thiết bị, địa chỉ IP, hay thời điểm chính xác trong các bảng này. Số liệu chỉ dành cho quản trị viên của banbe, và các ô có ít hơn một ngưỡng tối thiểu (mặc định 20) bị ẩn. Số liệu đếm **sự kiện**, không đếm **người**: một người xem nhiều lần được đếm nhiều lần, và số liệu chỉ để tham khảo, không dùng làm căn cứ thanh toán. Số "đã phát hành/đã dùng" chỉ do máy chủ ghi, không do ứng dụng tự báo.

EN: When switched on, banbe counts offer activity in aggregate: for each offer, each **day** (UTC), each **coarse region** (Vietnam, United States, other, unknown) and each event type (viewed, issued, redeemed) there is **one number**. There is no record per view; no user id, phone number, email, device, IP address or exact time in these tables. The figures are for banbe administrators only, and cells below a minimum group size (default 20) are hidden. The numbers count **events**, not **people**: one person viewing repeatedly is counted repeatedly, and the figures are indicative, not a basis for billing. "Issued/redeemed" counts are written by the server only, never reported by the app.

**4.3 Giới hạn của lời hứa "không định danh" · Limits of the "non-identifying" promise** `[bắt buộc nêu · must be stated]`

VI: Lời hứa "không định danh" chỉ áp dụng cho **cơ sở dữ liệu của banbe**. Nhà cung cấp nền tảng (Supabase, Vercel) ghi nhật ký hạ tầng cho từng yêu cầu gửi tới dịch vụ, gồm thời điểm, đường dẫn và mã người dùng trong mã đăng nhập (token); các nhật ký đó nằm ngoài cơ sở dữ liệu của banbe và thời hạn lưu do nhà cung cấp quyết định, không phải banbe. Vì vậy không thể nói rằng không có dấu vết nào về việc một tài khoản đã mở một ưu đãi. Chúng tôi chỉ cam kết rằng bảng số liệu của banbe không chứa danh tính. `[CẦN LUẬT SƯ DUYỆT: cách diễn đạt; xác minh thời hạn lưu nhật ký thực tế của nhà cung cấp, chưa được kiểm tra]`

EN: The "non-identifying" promise applies to **banbe's database**. The platform providers (Supabase, Vercel) keep infrastructure logs for each request to the service, including the time, the path and the user id inside the sign-in token; those logs sit outside banbe's database and their retention is decided by the provider, not by banbe. So it cannot be said that no trace exists of an account having opened an offer. We only promise that banbe's statistics tables contain no identity. `[LAWYER REVIEW: wording; the providers' actual log retention has not been verified]`

**4.4 Đồng ý riêng cho ưu đãi cá nhân hoá của đối tác · Separate consent for partner-personalised offers** `[CHƯA CÓ · NOT BUILT]`

VI: Ưu đãi **không** cá nhân hoá (cùng nội dung cho mọi người đủ điều kiện) không cần đồng ý quảng cáo riêng nhưng vẫn cần cập nhật chính sách. Ưu đãi **cá nhân hoá theo đối tác** (dựa trên hành vi hay sở thích của bạn) chỉ được bật khi bạn đồng ý **riêng**: mặc định **tắt**, ghi lại phiên bản chính sách và thời điểm đồng ý, rút lại dễ dàng bất kỳ lúc nào, và rút lại thì dừng ngay. Sự đồng ý này **tách biệt** với đồng ý nhận quảng bá từ host hiện có (`host_promo_consent`), vì mục đích và bên nhận khác nhau; không tái sử dụng sự đồng ý cũ. Mẫu thiết kế đề xuất: một bảng riêng (kiểu `reward_partner_consent`) với phiên bản, thời điểm đồng ý và rút lại. Chưa tồn tại trong code.

EN: **Non-personalised** offers (same content for everyone eligible) need no separate advertising consent but still require a policy update. **Partner-personalised** offers (based on your behaviour or preferences) may be switched on only with your **separate** consent: **off** by default, with the policy version and the time of consent recorded, easy to withdraw at any time, and withdrawal stops it immediately. This consent is **separate** from the existing consent to receive host promotions (`host_promo_consent`) because the purpose and the recipient differ; the old consent is not reused. Proposed design: a dedicated table (like `reward_partner_consent`) with version, consent time and withdrawal. It does not exist in the code yet.

**4.5 Cơ sở pháp lý và tín hiệu chống gian lận · Legal basis and anti-fraud signals** `[ĐÃ VIẾT, cờ TẮT · WRITTEN, flag OFF, migration 178] [CẦN LUẬT SƯ DUYỆT]`

VI: Các tín hiệu chống gian lận hiện viết là: tỷ lệ khách lặp lại bất thường theo host; cụm tài khoản mới được cùng một host điểm danh nhiều sự kiện; điểm danh ngoài khung giờ sự kiện; và nhiều tài khoản được cùng một host điểm danh có **cùng số điện thoại đã xác minh**. Chúng tạo ra **cờ rủi ro** chỉ quản trị viên xem; cờ lưu số lượng và mã các tài khoản liên quan, nghĩa là quản trị viên có thể thấy **liên kết giữa các tài khoản**. Cờ không tự thu hồi xu, không chặn host hay khách, không là quyết định tự động; quyết định cuối do con người. Cơ sở hiện dùng cho chống gian lận ở chính sách (Điều B3, mục 2) là "sự đồng ý khi đăng ký" và nêu "xác minh số điện thoại và thống kê vắng mặt"; chính sách **chưa nêu** việc đối chiếu số điện thoại giữa các tài khoản hay các tín hiệu trên. Cần luật sư xác nhận: cơ sở là hợp đồng, lợi ích chính đáng/an toàn, nghĩa vụ pháp luật hay đồng ý; cách mô tả; thời hạn lưu cờ; quyền biết và phản đối của người bị gắn cờ. Ngưỡng hiện **chưa được hiệu chỉnh** (chưa có dữ liệu điểm danh thật) nên có thể gắn cờ nhầm một nhóm bạn thật sự tham dự đều đặn.

EN: The anti-fraud signals as written are: an unusual share of repeat guests per host; a cluster of new accounts confirmed at many events of the same host; check-ins outside the event's time window; and several accounts confirmed by the same host that share the **same verified phone number**. They create **risk flags** that only administrators see; a flag stores counts and the ids of the accounts involved, meaning an administrator can see **links between accounts**. A flag does not automatically reverse coins, block a host or guest, or decide anything; the final decision is made by a person. The basis the policy currently cites for fraud prevention (Section B3, item 2) is "the consent you give at sign-up", naming "phone verification and no-show counts"; the policy **does not yet describe** matching phone numbers across accounts or the signals above. The lawyer must confirm: whether the basis is contract, legitimate interest/safety, legal obligation or consent; how to describe it; how long flags are kept; and the flagged person's right to know and to object. Thresholds are **uncalibrated** today (no real check-in data yet), so a group of friends who genuinely attend regularly could be flagged wrongly.

**4.6 Lưu giữ và xoá tài khoản · Retention and account deletion** `[ĐANG CÓ · LIVE-IN-CODE]`

VI: Sổ cái xu, huy hiệu, chuỗi ngày, lựa chọn múi giờ và mục tiêu tháng thuộc về tài khoản của bạn và bị xoá cùng tài khoản. Bộ đếm tổng hợp ở 4.2 không gắn với tài khoản nên không bị xoá theo tài khoản (không thể xác định phần nào là của bạn). **Cờ rủi ro khi xoá tài khoản (đã xử lý trong migration 178, chưa áp dụng lên production):** cờ không còn chứa mã tài khoản. Liên kết giữa một cờ và các tài khoản liên quan nằm ở bảng riêng với khoá ngoại xoá theo tầng tới hồ sơ; việc xoá tài khoản (qua `admin.auth.admin.deleteUser`) tự xoá các liên kết đó. Cờ chỉ còn số liệu đếm và mã tổ chức của host. Một cờ "cùng số điện thoại" còn dưới 2 tài khoản, hoặc cờ "cụm tài khoản mới" hết tài khoản, bị xoá theo vì không còn ý nghĩa; các cờ khác không đổi. Cờ cấp host (khách lặp lại, ngoài khung giờ) chỉ có số liệu đếm nên ở lại sau khi host xoá tài khoản (tổ chức của host vẫn tồn tại, chỉ bị gỡ liên kết chủ sở hữu, như luồng xoá tài khoản hiện có). Thời hạn lưu của cờ chưa bị xoá theo thời gian: cần luật sư/quyết định. `[CẦN LUẬT SƯ DUYỆT: thời hạn lưu của bộ đếm và của cờ rủi ro; bổ sung vào bảng ở Điều B7]`

EN: Your coin ledger, badges, streak, time-zone choice and monthly goal belong to your account and are deleted with it. The aggregate counters in 4.2 are not tied to an account so they are not deleted with it (it is impossible to tell which part is yours). **Risk flags on account deletion (handled in migration 178, not yet applied to production):** a flag no longer contains account ids. The link between a flag and its accounts lives in a separate table with a cascading foreign key to the profile; deleting an account (through `admin.auth.admin.deleteUser`) deletes those links automatically. A flag keeps only counts and the host's organizer id. A "same phone" flag left with fewer than 2 accounts, or a "cluster of new accounts" flag with none left, is removed with them because it no longer means anything; other flags are unchanged. Host-level flags (repeat guests, outside the time window) carry counts only and remain after a host deletes their account (the host's organizer row survives, only its owner link is cleared, as the existing deletion flow already does). Flags are still not deleted by age: retention needs a lawyer/decision. `[LAWYER REVIEW: retention of counters and risk flags; add to the table in Section B7]`

---

## 5. Xung đột với chính sách hiện tại và hai phương án · Conflicts with the current policy and two options `[CẦN LUẬT SƯ DUYỆT · LAWYER REVIEW REQUIRED]`

**Phương án A được chọn tạm thời; B chỉ khi có đối tác thật và luật sư duyệt. · Option A is chosen provisionally; B only with a real partner and lawyer approval.**

Số dòng theo `banbe_User_Policy.md` v1.1 hiện tại (dòng tiếng Việt; bản tiếng Anh nằm cạnh).
Line numbers refer to the current `banbe_User_Policy.md` v1.1 (Vietnamese line; the English text sits next to it).

**Phương án A / Option A:** giữ nguyên các cam kết, chỉ cho phép ưu đãi do host/địa điểm tự đăng (loại 3.1(i)). **Phương án B / Option B:** sửa cam kết để cho phép ưu đãi được tài trợ, có nhãn rõ (loại 3.1(ii)). Cả hai phương án đều cần thêm một điều khoản mô tả Phần thưởng (policy hiện **không** nhắc xu, huy hiệu hay chuỗi ngày).

### 5.1 Dòng 31 (mục 8 của bản tóm tắt; EN dòng 32) · Line 31

> "Chúng tôi không bán dữ liệu và không chạy quảng cáo." / "We do not sell data and do not run ads."

| | Cách viết · Wording | Hệ quả · Consequence |
|---|---|---|
| **A** | VI: giữ nguyên câu; thêm: "Host hoặc địa điểm có thể đăng ưu đãi của chính họ; đó là nội dung của họ, không phải quảng cáo của banbe và banbe không nhận phí để đẩy nó." EN: keep the sentence; add: "Hosts or venues may post their own offers; that is their content, not banbe advertising, and banbe takes no fee to promote it." | Cam kết giữ nguyên; không có doanh thu tài trợ; "không nhận phí" phải đúng thực tế. Ranh giới "nội dung của host" với "quảng cáo" cần luật sư xem. · The promise stays; no sponsorship revenue; "no fee" must stay true. The line between "host content" and "advertising" needs the lawyer. |
| **B** | VI: "Chúng tôi không bán dữ liệu. banbe có thể hiển thị ưu đãi được tài trợ, luôn có nhãn 'Được tài trợ' và tên bên tài trợ; chúng tôi không chia sẻ dữ liệu cá nhân của bạn với bên tài trợ." EN: "We do not sell data. banbe may show sponsored offers, always labelled 'Sponsored' with the sponsor's name; we do not share your personal data with the sponsor." | Cho phép doanh thu tài trợ; bỏ cam kết "không chạy quảng cáo" nên là thay đổi lớn về niềm tin và phải được thông báo, có thể cần đồng ý lại (mục 6). · Allows sponsorship revenue; drops the "no ads" promise, a significant change of trust that must be announced and may need re-consent (section 6). |

### 5.2 Dòng 182 (Điều B3, cuối; EN dòng 184) · Line 182

> "Chúng tôi không dùng dữ liệu cho quảng cáo của banbe (host chỉ nhắn quảng bá cho khách đã bật đồng ý riêng, mỗi lần một người nhận và có ghi nhật ký), không phân tích nội dung trò chuyện, và không ra quyết định tự động ảnh hưởng đến bạn ngoài việc đếm số lần vắng mặt như nêu tại Điều A5."
> "We do not use data for banbe's own advertising (hosts may send promotions only to guests who opted in separately, one recipient at a time, with a log), analyze chat content, or make automated decisions about you other than counting no-shows as described in Section A5."

| | Cách viết · Wording | Hệ quả · Consequence |
|---|---|---|
| **A** | VI: giữ nguyên câu; thêm: "Chúng tôi đo lượt xem ưu đãi ở dạng số liệu tổng hợp không gắn với tài khoản, chỉ để quản trị viên xem (xem mục [x]); đó không phải quảng cáo và không phải hồ sơ cá nhân." Và nêu rõ việc cờ chống gian lận chỉ để quản trị viên xem, không phải quyết định tự động. EN: keep the sentence; add that offer views are measured as aggregate figures not tied to an account, for administrators only, and that fraud flags are for administrator review, not automated decisions. | Câu giữ nguyên nhưng phải đảm bảo "không tự động" luôn đúng: nếu sau này tự động thu hồi xu thì câu sai. Việc nói "không phải quảng cáo" phải đúng với cách dùng thực tế. · The sentence stays but "not automated" must remain true: automatic reversal later would make it false. |
| **B** | VI: thay bằng: "Chúng tôi không dùng dữ liệu cá nhân của bạn cho quảng cáo của bên thứ ba. Chúng tôi có thể dùng số liệu tổng hợp, không định danh, để báo cáo hiệu quả ưu đãi được tài trợ cho đối tác. Ưu đãi cá nhân hoá theo đối tác chỉ khi bạn đồng ý riêng." EN: replace with: "We do not use your personal data for third-party advertising. We may use aggregate, non-identifying figures to report sponsored offers' performance to partners. Partner-personalised offers only with your separate consent." | Cho phép báo cáo tổng hợp cho đối tác (hiện báo cáo chỉ dành cho admin, chưa có đường cho đối tác). Đòi hỏi cơ chế đồng ý riêng ở 4.4 (chưa xây). Nhiều rủi ro pháp lý hơn A. · Allows aggregate partner reporting (today admin-only; no partner path yet). Requires the separate consent of 4.4 (not built). More legal exposure than A. |

### 5.3 Dòng 178 (Điều B3, mục 1–4; EN dòng 180) · Line 178: purposes and legal basis

> "(2) giữ nền tảng an toàn và chống gian lận, gồm xác minh số điện thoại và thống kê vắng mặt, trên cơ sở sự đồng ý bạn đưa ra khi đăng ký" / "(2) keep the platform safe and prevent fraud, including phone verification and no-show counts, on the basis of the consent you give at sign-up"

| | Cách viết · Wording | Hệ quả · Consequence |
|---|---|---|
| **A** | VI: mở rộng mục (2): "…gồm xác minh số điện thoại, thống kê vắng mặt, và phát hiện việc cấp điểm danh bất thường hoặc nhiều tài khoản cho một người; quản trị viên có thể xem liên kết giữa các tài khoản trong trường hợp này." Thêm mục (5): "cung cấp Phần thưởng (xu, huy hiệu, chuỗi ngày) bạn dùng, tức thực hiện hợp đồng." EN: extend (2) to add detecting unusual check-in confirmations or several accounts for one person, with administrators able to see links between accounts; add (5): providing the Rewards you use (coins, badges, streak) — contract performance. | Không thêm mục đích quảng cáo. Cơ sở của (2) vẫn là "đồng ý khi đăng ký": luật sư có thể muốn đổi sang lợi ích chính đáng hoặc giữ đồng ý; nếu đồng ý thì rút lại được. · No advertising purpose added. (2)'s basis stays "sign-up consent": the lawyer may prefer legitimate interest, or keep consent, which is withdrawable. |
| **B** | VI: như A, thêm mục (6): "hiển thị ưu đãi được tài trợ có nhãn rõ và báo cáo số liệu tổng hợp không định danh cho đối tác; ưu đãi cá nhân hoá theo đối tác chỉ trên cơ sở đồng ý riêng của bạn." EN: as A, plus (6): showing clearly labelled sponsored offers and reporting aggregate non-identifying figures to partners; partner-personalised offers only on your separate consent. | Thêm mục đích mới ⇒ rơi vào cam kết dòng 300 (xin lại đồng ý). Cần nêu cơ sở cho "báo cáo tổng hợp" (lợi ích chính đáng?) và cho "cá nhân hoá" (đồng ý). · A new purpose, so line 300 applies (re-consent). Needs a stated basis for "aggregate reporting" (legitimate interest?) and for "personalisation" (consent). |

### 5.4 Dòng 300 (Điều B12; EN dòng 302) · Line 300: re-asking consent

> "Khi thay đổi mục đích xử lý hoặc loại dữ liệu thu thập, chúng tôi xin lại sự đồng ý của bạn trong ứng dụng trước khi áp dụng. Các thay đổi khác được đăng kèm ngày hiệu lực."

| | Áp dụng thế nào · How it applies | Hệ quả · Consequence |
|---|---|---|
| **A** | VI: Phần thưởng và đo lượt xem tổng hợp là tính năng mới; việc thêm tín hiệu chống gian lận có thể coi là trong mục đích "an toàn và chống gian lận" nhưng thêm **loại dữ liệu được đối chiếu** (số điện thoại giữa các tài khoản). Đề xuất thận trọng: coi là thay đổi cần **thông báo** và xin xác nhận lại ở màn hình chính sách trước khi bật cờ chống gian lận. EN: Rewards and aggregate view counting are new features; adding fraud signals can be read as within "safety and fraud prevention" but it adds a **kind of data matched** (phone numbers across accounts). Cautious proposal: treat it as a change needing **notice** plus re-confirmation on the policy screen before the fraud flags are switched on. | Ít người dùng bị ảnh hưởng; không cần cơ chế đồng ý riêng cho ưu đãi. Luật sư quyết định có bắt buộc xin lại đồng ý hay chỉ thông báo. · Fewer users affected; no separate offer-consent mechanism. The lawyer decides whether re-consent is mandatory or notice suffices. |
| **B** | VI: Thêm mục đích mới (ưu đãi tài trợ, báo cáo cho đối tác, cá nhân hoá) ⇒ **bắt buộc** xin lại đồng ý trong ứng dụng trước khi áp dụng, đúng cam kết ở dòng 300; cá nhân hoá cần đồng ý riêng ở 4.4. EN: Adding new purposes (sponsored offers, partner reporting, personalisation) ⇒ re-consent in the app is **required** before applying, per the line 300 promise; personalisation needs the separate consent in 4.4. | Người không đồng ý vẫn dùng được banbe nhưng không thấy ưu đãi tài trợ/cá nhân hoá (đề xuất; luật sư xác nhận). · Users who decline still use banbe but see no sponsored/personalised offers (proposal; lawyer to confirm). |

---

## 6. Thông báo và xin đồng ý lại · Notice and re-consent `[CẦN LUẬT SƯ DUYỆT]`

VI: **Hiện trạng:** mọi người dùng hiện tại đã đồng ý phiên bản v1.1, trong đó **không** có Phần thưởng và **không** có các tín hiệu chống gian lận ở 4.5. Dòng 300 hứa xin lại đồng ý khi đổi mục đích hoặc loại dữ liệu. Không được bật gì trong mục 4–5 trước khi hoàn tất các bước dưới đây.

EN: **Where we are:** every current user agreed to v1.1, which has **no** Rewards and **none** of the fraud signals in 4.5. Line 300 promises to ask again when purposes or data types change. Nothing in sections 4–5 may be switched on before the steps below are done.

**Đề xuất các bước · Proposed steps** (thời hạn là đề xuất, luật sư quyết định · periods are proposals; the lawyer decides)

1. VI: **Thông báo trước ≥ 30 ngày** bằng thông báo trong ứng dụng (banner + hộp thư) và email, nêu: thay đổi gì, vì sao, dữ liệu nào, ai thấy gì, ngày hiệu lực, cách từ chối/rút lại, liên hệ. Bản tóm tắt dưới 150 từ, song ngữ, kèm liên kết bản đầy đủ. EN: **At least 30 days' notice** by in-app notice (banner + inbox) and email stating what changes, why, which data, who sees what, the effective date, how to decline/withdraw, and contact. Summary under 150 words, bilingual, linking the full text.
2. VI: **Màn hình xin đồng ý lại** khi người dùng mở ứng dụng sau ngày công bố: hiển thị phiên bản mới, hai nút ngang hàng "Đồng ý" và "Để sau / Không đồng ý", không đặt sẵn lựa chọn. Ghi lại phiên bản và thời điểm đồng ý. EN: **A re-consent screen** when the user opens the app after the announcement: shows the new version, two equal buttons "Agree" and "Later / Decline", nothing pre-selected. Record the version and time of consent.
3. VI: **Người không đồng ý vẫn dùng được banbe** (đặt chỗ, trò chuyện, vé). Họ chỉ không tham gia phần thay đổi cần đồng ý (ưu đãi tài trợ, ưu đãi cá nhân hoá). Chống gian lận trên cơ sở nào thì áp dụng theo cơ sở đó (luật sư quyết định, mục 4.5). EN: **Users who do not agree can still use banbe** (booking, chat, tickets). They only stay out of the parts that need consent (sponsored offers, personalised offers). Fraud prevention applies on whatever basis the lawyer settles (4.5).
4. VI: Với **Phương án A**, tối thiểu: thông báo ≥ 30 ngày + xác nhận lại trước khi bật cờ chống gian lận; với **Phương án B**: đủ cả ba bước, và cá nhân hoá chỉ bật sau đồng ý riêng ở 4.4. EN: With **Option A** at minimum: ≥ 30 days' notice + re-confirmation before the fraud flags are switched on; with **Option B**: all three steps, and personalisation only after the separate consent in 4.4.
5. VI: **Ghi vào chính sách** ngày hiệu lực và phiên bản mới (theo dòng cuối của chính sách), giữ các bản trước theo yêu cầu. `[CẦN QUYẾT ĐỊNH: có cần thay đổi cơ chế ghi nhận phiên bản đồng ý hiện có (note 09, câu hỏi nâng phiên bản) hay không]` EN: **Record in the policy** the effective date and the new version (per the policy's last line) and keep earlier versions on request. `[DECISION: whether the existing consent-version mechanism needs changes (note 09, version-bump question)]`

---

## 7. Hai thị trường · Two markets `[CẦN LUẬT SƯ DUYỆT; KHÔNG PHẢI TƯ VẤN PHÁP LÝ · NOT LEGAL ADVICE]`

VI: Các điểm dưới đây dựa trên tra cứu của `docs/rewards-research.md` ngày 2026-10-08 qua tìm kiếm, **chưa đọc văn bản gốc** và có thể đã thay đổi. Chưa phải tư vấn pháp lý hay thuế.

EN: The points below rest on the 2026-10-08 lookup in `docs/rewards-research.md` made via search, **original texts not read**, and may have changed. This is not legal or tax advice.

| Chủ đề · Topic | Việt Nam · Vietnam | Hoa Kỳ · United States |
|---|---|---|
| Dữ liệu cá nhân · Personal data | VI: Luật Bảo vệ dữ liệu cá nhân số 91/2025/QH15, hiệu lực 01/01/2026; dùng dữ liệu cho quảng cáo cần đồng ý trên cơ sở biết nội dung, phương thức, hình thức, **tần suất** và có cách từ chối. Policy đã nêu luật này (dòng 224, 256) nhưng chưa có mục đích ưu đãi. Chuyển dữ liệu ra nước ngoài: hồ sơ đánh giá và nghĩa vụ với Bộ Công an (dòng 224). EN: Law 91/2025/QH15, in force 1 Jan 2026; using data for advertising needs informed consent covering content, means, form and **frequency**, with a way to refuse. The policy cites it (lines 224, 256) but has no offer purpose. Cross-border transfer: impact assessment and duties to the Ministry of Public Security (line 224). | VI: CCPA/CPRA áp dụng nếu vượt ngưỡng; nghiên cứu ghi "doanh thu hằng năm trên 25 triệu USD, hoặc mua/bán/chia sẻ dữ liệu của ≥100.000 người/hộ/thiết bị mỗi năm, hoặc ≥50% doanh thu từ bán/chia sẻ dữ liệu". **Ngưỡng doanh thu được điều chỉnh định kỳ; phải kiểm tra con số hiện hành, chưa được xác minh ở đây.** Chương trình ưu đãi đổi lấy dữ liệu có thể cần Notice of Financial Incentive và đồng ý opt-in, thu hồi được. banbe có thể chưa đạt ngưỡng nhưng nên thiết kế sẵn. EN: CCPA/CPRA applies above thresholds; the research lists "annual revenue over USD 25 million, or buying/selling/sharing data of ≥100,000 people/households/devices a year, or ≥50% of revenue from selling/sharing data". **The revenue threshold is adjusted periodically; the current figure must be checked and is not verified here.** An incentive programme in exchange for data may need a Notice of Financial Incentive and opt-in consent, revocable. banbe may be under the thresholds but should design for it. |
| Khuyến mại / ưu đãi · Promotions | VI: Nghị định 81/2018/NĐ-CP (sửa bởi 128/2024/NĐ-CP) về hình thức, điều kiện, hạn mức khuyến mại (ví dụ trần giá trị theo tóm tắt); nghĩa vụ đăng ký/thông báo với Sở Công Thương và việc banbe là thương nhân khuyến mại hay chỉ là nền tảng: **chưa xác minh**. EN: Decree 81/2018/ND-CP (amended by 128/2024/ND-CP) on forms, conditions and limits of promotions (for example a value cap per the summary); registration/notification with the Department of Industry and Trade and whether banbe is a promoting trader or just a platform: **not verified**. | VI: Sweepstakes/contest theo từng bang (đăng ký, ký quỹ, "no purchase necessary"): tránh bằng việc **không rút thăm**. Luật bang về phiếu quà/giá trị lưu trữ, "money transmitter": **chưa xác minh**. EN: Sweepstakes/contest rules are state by state (registration, bonding, "no purchase necessary"): avoided by **no draws**. State gift-card/stored-value law and money-transmitter rules: **not verified**. |
| Nền tảng ứng dụng · App stores | VI/EN: Apple 3.1.1 (xu mua không hết hạn), 3.1.3(e) (hàng hoá dùng ngoài ứng dụng), 5.3.1–5.3.2 (rút thăm); Google Play (phần thưởng, thanh toán). Áp dụng như nhau ở hai thị trường, ghi ở đây vì ảnh hưởng đến mục 2 và 3.3. · Apply equally in both markets; listed because they shape sections 2 and 3.3. | |
| Tuổi · Age | VI: người dùng từ 16 tuổi (policy A3); ưu đãi có tuổi tối thiểu (đồ uống có cồn) cần kiểm tra theo ngày sinh đã có. EN: users are 16+ (policy A3); age-restricted offers (alcohol) must be checked against the date of birth held. | VI/EN: tuổi tối thiểu cho dữ liệu của trẻ em theo luật Mỹ (COPPA, CCPA) cần luật sư kiểm tra. · minimum ages for minors' data under US law (COPPA, CCPA) need lawyer review. |
| Thuế · Tax | VI/EN: nghĩa vụ khai báo/khấu trừ cho người nhận ưu đãi giá trị nhỏ ở cả hai nước: **chưa xác minh**. · reporting/withholding for recipients of small-value offers in both countries: **not verified**. | |
| Tách điều khoản · Separate terms | VI: cần quyết định có hai bộ điều khoản/chương trình (VN, US) hay một bộ có phụ lục theo thị trường; đề xuất: một chính sách, phụ lục theo thị trường cho ưu đãi tài trợ, đồng ý và thông báo. EN: decide whether to have two sets of terms/programmes (VN, US) or one set with a market annex; proposal: one policy with a market annex for sponsored offers, consent and notices. | |

---

## 8. Câu hỏi cho luật sư · Questions for the lawyer

**Chín câu từ `docs/rewards-research.md` mục 6.5 · The nine questions from section 6.5**

1. VI: Chương trình đổi xu lấy ưu đãi do đối tác tự phát hành có bị coi là khuyến mại thương mại ở Việt Nam không? Ai là bên thực hiện, cần đăng ký/thông báo gì? · EN: Is a programme where coins unlock partner-issued offers a commercial promotion in Vietnam? Who is the promoting party, and what registration/notification is needed?
2. VI: Ở Mỹ, xu kiếm được (không mua, không chuyển, không đổi tiền) có bị xếp vào "gift card/stored value" hay "financial incentive" theo CCPA không? Cần Notice of Financial Incentive khi nào? · EN: In the US, are earned coins (not bought, not transferable, not cashable) a "gift card/stored value" or a "financial incentive" under CCPA? When is a Notice of Financial Incentive needed?
3. VI: banbe nhận **phí tài trợ từ đối tác** (không giữ tiền người dùng) có làm banbe thành bên phân phối khuyến mại hay quảng cáo? Cần sửa điều khoản nào, kể cả câu "không chạy quảng cáo"? · EN: Does banbe receiving **sponsorship fees from partners** (holding no user money) make it a distributor of promotions or advertising? Which clauses change, including "we do not run ads"?
4. VI: Thuế cho người nhận ưu đãi giá trị nhỏ ở Việt Nam và Mỹ: có nghĩa vụ khai báo/khấu trừ không, dưới ngưỡng nào? · EN: Tax on recipients of small-value offers in Vietnam and the US: any reporting/withholding duty, and below what threshold?
5. VI: Nếu host/địa điểm tự tài trợ và banbe chỉ xác nhận điều kiện, ai chịu trách nhiệm khi ưu đãi không được tôn trọng? Điều khoản cần có với host. · EN: If hosts/venues sponsor themselves and banbe only confirms eligibility, who is responsible when an offer is not honoured? What terms are needed with hosts?
6. VI: Cơ sở xử lý dữ liệu cho báo cáo tổng hợp gửi đối tác (không định danh) và cho ưu đãi cá nhân hoá theo Luật 91/2025/QH15 và CCPA/CPRA; có cần đánh giá tác động/đăng ký chuyển dữ liệu ra nước ngoài thêm không (policy dòng 224)? · EN: The basis for processing data for aggregate partner reports (non-identifying) and for personalised offers under Law 91/2025/QH15 and CCPA/CPRA; is any additional impact assessment or cross-border registration needed (policy line 224)?
7. VI: Xu có hạn dùng và không đổi tiền có đủ để tránh bị xem là tiền điện tử/ví ở VN và Mỹ không? Ngưỡng nào làm thay đổi kết luận? · EN: Are expiring, non-cashable coins enough to avoid being treated as e-money/a wallet in VN and the US? What thresholds change the conclusion?
8. VI: Ưu đãi đồ uống có cồn hoặc đối tượng 18+ cho người dưới 18 (policy yêu cầu 18+ để tổ chức; người dùng từ 16): cần kiểm tra yêu cầu tuổi người dùng. · EN: Alcohol or 18+ offers for under-18s (the policy requires 18+ to host; users are 16+): what age rules apply to users?
9. VI: Với người dùng Mỹ và Việt Nam khác nhau, có cần hai bộ điều khoản/chương trình tách biệt không? · EN: Given different US and Vietnamese users, are two separate sets of terms/programmes needed?

**Câu hỏi mới phát sinh từ công việc Giai đoạn 0 · New questions from Phase 0 work**

10. **`shared_phone` và liên kết tài khoản · `shared_phone` and account links.** VI: Việc đối chiếu số điện thoại **đã xác minh** giữa các tài khoản được cùng một host điểm danh, và để quản trị viên xem liên kết giữa các tài khoản, dựa trên cơ sở nào (đồng ý khi đăng ký ở dòng 178, lợi ích chính đáng, hợp đồng)? Có cần mô tả rõ trong Điều B3/B4? Người bị gắn cờ có quyền được biết và phản đối thế nào? · EN: On what basis may banbe match **verified** phone numbers across accounts confirmed by the same host and let administrators see links between accounts (sign-up consent per line 178, legitimate interest, contract)? Must it be described in B3/B4? How may a flagged person learn of it and object?
11. **Cờ rủi ro khác · Other risk flags.** VI: Cờ chỉ để quản trị viên xem có phải "quyết định tự động" theo luật không? Nếu quản trị viên thu hồi xu dựa trên cờ, người dùng cần được thông báo và có quyền phản đối ra sao? Thời hạn lưu cờ? · EN: Is a flag for administrator review an "automated decision" under the law? If an administrator reverses coins based on a flag, how must the user be told and how may they object? How long are flags kept?
12. **Bộ đếm sự kiện "không định danh" · The "non-identifying" event counters.** VI: Bộ đếm tổng hợp (ngày, vùng thô, ngưỡng 20) có thực sự nằm ngoài khái niệm dữ liệu cá nhân không, khi ai đó có thể suy luận từ các ô nhỏ hoặc báo cáo chồng cửa sổ? Mức ngưỡng và độ mịn vùng nào là đủ? Có cần nêu trong policy dù không định danh? · EN: Are the aggregate counters (day, coarse region, threshold 20) genuinely outside personal data when someone could infer from small cells or overlapping reports? What threshold and region granularity is enough? Must it be in the policy even though it is non-identifying?
13. **Nhật ký nền tảng · Platform logs.** VI: Nhật ký hạ tầng của Supabase/Vercel (thời điểm, đường dẫn, mã người dùng trong token) có làm việc mở một ưu đãi thành dữ liệu cá nhân chịu điều chỉnh không? Cách diễn đạt trung thực về giới hạn của "không định danh"; thời hạn lưu thực tế của nhà cung cấp cần được xác minh. · EN: Do the infrastructure logs of Supabase/Vercel (time, path, user id in the token) make opening an offer personal data under regulation? What is an honest way to state the limits of "non-identifying"; the providers' actual retention must be verified.
14. **Hết hạn xu · Coin expiry.** VI: Quy tắc hết hạn xu kiếm được sau 12 tháng không hoạt động có hợp pháp ở VN và Mỹ không? Yêu cầu thông báo trước? Tương tác với Apple 3.1.1 nếu sau này bán xu (mục 2)? · EN: Is the rule that earned coins expire after 12 months of inactivity lawful in VN and the US? What notice is required? Interaction with Apple 3.1.1 if coins are ever sold (section 2)?
15. **Thông báo và xin đồng ý lại · Notice and re-consent.** VI: Với phương án A, chỉ thông báo có đủ hay bắt buộc xin lại đồng ý (dòng 300)? Thời hạn báo trước tối thiểu? Việc từ chối có được kéo theo hạn chế tính năng không? · EN: Under option A, is notice enough or is re-consent mandatory (line 300)? What minimum notice period? May declining carry any feature restriction?
16. **Số dư âm · Negative balances.** VI: Cho phép số dư âm sau thu hồi (không thu hồi phần thưởng đã mở khoá) có công bằng và hợp pháp không; có cần cơ chế khiếu nại? · EN: Is allowing a negative balance after reversal (without revoking unlocked rewards) fair and lawful; is an appeal mechanism needed?

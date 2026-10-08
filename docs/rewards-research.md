# Nghiên cứu Rewards & Badges: hiện trạng, so sánh Payback/WeWard, sẵn sàng cho tài trợ

Ngày tra cứu: 2026-10-08. Đây là báo cáo nghiên cứu nội bộ, **không phải tư vấn pháp lý hay thuế**. Chưa sửa code, chưa chạy migration, chưa đọc `.env`, chưa ghi dữ liệu thật.

Quy ước nhãn: **[Fact: nguồn, ngày]** = đọc trực tiếp từ nguồn/repo; **[Ước tính]** = suy luận của tôi; **[Chưa xác minh]** = chưa đọc nguồn gốc, chỉ thấy gián tiếp hoặc chưa kiểm tra. Số liệu do chính công ty công bố được ghi rõ là *số liệu marketing*. Dẫn chứng repo ghi dạng `file:dòng`.

Lưu ý nhỏ về tên file: trong repo, migration `…166_166_event_announcements.sql` là việc khác; rollback của rewards là `supabase/rollbacks/20261212000166_166_revert_rewards.sql`. Policy nằm ở `banbe_User_Policy.md` (gốc repo).

---

## 1. Tóm tắt và khuyến nghị

1. Rewards hiện là hệ thống **trang trí**: coin chỉ kiếm từ điểm danh (+20/sự kiện, tối đa 10 sự kiện/tháng) và onboarding (+10), chỉ đổi được 3 mẫu móc khoá (40/80/120 coin). Không có voucher, tiền, tài trợ hay đối tác nào trong code (không tìm thấy). Server-authoritative, sổ cái chỉ-ghi-thêm, khá chắc.
2. Điểm yếu lớn nhất không phải kỹ thuật mà là **gian lận có chủ đích khi coin bắt đầu có giá trị**: host tự cấp điểm cho bạn bè/tài khoản phụ, nhiều tài khoản (chỉ có cổng OTP điện thoại). Hiện chấp nhận được vì coin chỉ mua đồ trang trí. Streak dùng múi giờ cố định Asia/Ho_Chi_Minh nên **không hợp lý cho người dùng Mỹ** (ngày của họ đổi lúc 9–13 giờ sáng).
3. Payback và WeWard khác nhau cơ bản: Payback là điểm **có giá trị tiền (1 điểm = 1 cent), do đối tác trả**, đổi qua phiếu/chuyển khoản; WeWard tuyên bố Wards **không có giá trị tiền** nhưng vẫn có phần thưởng tiền mặt/voucher, doanh thu chủ yếu từ quảng cáo/khảo sát. banbe không nên bắt chước cách nào trong hai cách khi chưa có luật sư.
4. Cấu trúc DB hiện **hard-code cho keychain** (`reward_catalog.kind CHECK IN ('keychain_design')`, `design_id NOT NULL UNIQUE`). Cần tách loại phần thưởng trước khi có đối tác; việc này rẻ và không cần đối tác.
5. **Khuyến nghị:** làm Giai đoạn 0 ngay (tách loại phần thưởng, sửa múi giờ, ghi số liệu tối thiểu, sửa policy), chạy Hướng A song song. Khi muốn thử, làm Hướng B (một host/địa điểm tài trợ nhỏ, **đối tác tự phát hành và xác nhận ưu đãi**, banbe không giữ tiền, không phát hành mã). Hoãn Hướng C (kiểu Payback) cho đến khi có số liệu và ý kiến luật sư.

---

## 2. Hiện trạng có dẫn chứng

### 2.1 Cách kiếm coin
Quy tắc nằm trong `reward_rule_versions`, một dòng active (`supabase/migrations/20261212000165_165_rewards_badges_streaks.sql:22-40`). **[Fact: repo, 2026-10-08]**

| Hành động | Coin | Giới hạn / khoá chống trùng | Dẫn chứng |
|---|---|---|---|
| Hoàn thành câu hỏi sở thích (có trả lời, không phải bỏ qua) | +10 một lần | Khoá `onboarding:preferences`; chỉ trả ở lần chuyển 0 → hoàn thành đầu tiên | 165:508-532 |
| Được host xác nhận tham dự một sự kiện | +20 | Khoá `attend:<event>:<cycle>`; mỗi sự kiện khác nhau một lần | 165:316-335 |
| Vượt trần tháng | 0 (ghi `attendance_cap`) | Tối đa 10 sự kiện trả coin/tháng = 200 coin, tính theo tháng ở múi giờ cố định; đếm theo `created_at` của dòng sổ cái | 165:36-37, 326-331 |

- Sổ cái chỉ-ghi-thêm: trigger chặn UPDATE/DELETE (165:81-93), `UNIQUE (user_id, source_key)` (165:72), mỗi giải thưởng chỉ được hoàn lại một lần (165:78). Sai thì ghi dòng `reversal`, không sửa.
- Không có coin cho: mở app, chi tiêu, thích, theo dõi, lưu lặp lại, tải lên, huỷ, đồng ý nhận tin (165:39; `src/lib/rewards.js:66-75`).
- Điểm danh hợp lệ = dòng `check_ins` do **host** xác nhận. Loại trừ: chủ sự kiện, thành viên team đã chấp nhận, tự điểm danh (`rewards_attendee_eligible`, 165:255-263). Vé tặng: người nhận đã nhận vé mới được tính (165:398-419).

### 2.2 Huy hiệu (`reward_badge_defs`, 165:136-157)
| Mã | Điều kiện | Target |
|---|---|---|
| ready_to_explore | Hoàn thành câu hỏi sở thích | 1 |
| first_outing | 1 sự kiện được host xác nhận | 1 |
| regular | 5 sự kiện khác nhau | 5 |
| explorer | Sự kiện thuộc 3 danh mục (`cat_key`) khác nhau | 3 |
| community_regular | 10 sự kiện khác nhau | 10 |
| host_milestone | 3 sự kiện `ended`, mỗi sự kiện có ≥1 khách hợp lệ không phải chủ | 3 |

Huy hiệu suy ra từ dữ kiện và tự thu hồi nếu điểm danh bị huỷ (165:294-311). Chỉ riêng tư, không có API xem công khai (165:166).

### 2.3 Đổi thưởng
- `reward_catalog`: 3 món, đều `kind='keychain_design'`: `rwd-comet` 40, `rwd-lantern` 80, `rwd-crown` 120 coin (165:169-181). 24 mẫu có sẵn vẫn miễn phí.
- `redeem_reward(code)` (165:631-653): khoá theo user, đọc lại số dư trong khoá, khoá `redeem:<code>` nên thử lại không bị trừ hai lần, `INSUFFICIENT_BALANCE` không trừ gì. Ghi `reward_unlocks` (PK `user_id, item_code`).
- Hoàn lại sau khi đã đổi: số dư **có thể âm**, phần thưởng không bị thu hồi (note 36 mục 3; `src/lib/rewards.js:77-87`).
- Ghi chú 36 nêu đã chạy 12 lệnh đổi đồng thời → 1 lần trừ; test local `13_rewards_run.sh` ALL PASS. **Chưa** áp dụng lên project Supabase thật, chưa chạy E2E/thiết bị thật (note 36, mục "Verification").

### 2.4 Streak
- "Ngày hoạt động" = **lưu sự kiện** được máy chủ xác minh (`favorites.created_at` do trigger đóng dấu lúc INSERT, và còn trong 36 giờ) hoặc điểm danh hợp lệ (165:206-214, 658-673). Mở app/tìm kiếm không tính. Mỗi ngày một dòng (PK `user_id, local_date`, 165:125-131).
- Sống đến hết "hôm qua"; bỏ lỡ thì về 0, không phạt (165:537-558).
- **Múi giờ cố định `Asia/Ho_Chi_Minh`** cho ngày streak và trần tháng (165:34, 47-56).
- **Có hợp lý cho người dùng Mỹ không? Không.** [Ước tính, tính từ UTC+7] Nửa đêm giờ Việt Nam = 17:00 UTC, tức 10:00 PDT / 09:00 PST (Los Angeles), 13:00 EDT / 12:00 EST (New York). Người Mỹ sẽ thấy "ngày mới" bắt đầu giữa buổi sáng, hành động buổi tối có thể bị tính vào ngày sau. Trần 10 sự kiện/tháng cũng chuyển tháng lệch tương tự. Hệ quả hiện nhỏ (streak không tạo coin) nhưng trở nên đáng kể khi streak gắn phần thưởng.

### 2.5 Chống gian lận
**Điểm mạnh** [Fact: repo]: mọi giải thưởng sinh từ dữ kiện DB, client không cấp được coin/số dư (RLS bật, không cấp quyền bảng, chỉ RPC `SECURITY DEFINER`, 165:191-201, 799-825); sổ cái bất biến + idempotent; hoàn lại khi huỷ điểm danh/huỷ sự kiện (165:482-504); khoá theo user chống đổi trùng; lỗi bookkeeping không chặn check-in (165:16-17, 448-461); trần tháng giới hạn thiệt hại 200 coin/tài khoản/tháng.

**Lỗ hổng còn lại:**
| Kịch bản | Hiện trạng | Mức rủi ro |
|---|---|---|
| Lưu rồi bỏ lưu để giữ streak | Chỉ cần một dòng `favorites` mới trong 36h; bỏ lưu rồi lưu lại tạo `created_at` mới. Chỉ ảnh hưởng streak, không tạo coin (165:658-673) | Thấp hiện tại; **trung bình** nếu sau này streak gắn thưởng |
| Nhiều tài khoản | Chỉ có cổng xác minh điện thoại hiện có; note 36 mục "Known limitations" #3 thừa nhận "không xử lý thêm" | Trung bình, cao khi coin có giá trị thực |
| Tự tham dự sự kiện của mình | Chặn chủ sự kiện, thành viên team, tự điểm danh. **Không chặn** tài khoản phụ/người quen của chính chủ | Trung bình |
| Host cấp điểm cho bạn bè | `check_in_guest` chỉ cho chủ hồ sơ/admin gọi (migration 151, dòng 278-286); host toàn quyền xác nhận ai đến. Sự kiện miễn phí vẫn đủ điều kiện (đặt chỗ `confirmed`). Nên host + vài tài khoản = 200 coin/tháng/tài khoản | **Cao nhất** khi coin có giá trị |
| Ràng buộc thời gian/vị trí khi check-in | **[Chưa xác minh]** tôi chưa đọc hết `check_in_guest` để biết có kiểm tra khung giờ sự kiện/khoảng cách không | Chưa rõ |
| Số dư âm sau hoàn lại | Cố ý; có thể bị lạm dụng bằng cách đổi rồi huỷ điểm danh (người dùng giữ phần thưởng) | Thấp (chỉ đồ trang trí) |
| Vé tặng chưa nhận, vé nhiều chỗ | Ghi nhận trong note 36 #1–#2 | Thấp |

### 2.6 Policy nói gì (`banbe_User_Policy.md`)
- **Coin/phần thưởng/huy hiệu của Rewards: không tìm thấy** (grep `coin|reward|streak|xu` không ra điều khoản nào; chỉ có "huy hiệu host thường xuyên", dòng 27, 104, là việc khác). Cần bổ sung trước khi phát hành thật.
- "Chúng tôi không bán dữ liệu và không chạy quảng cáo" (dòng 31); "không dùng dữ liệu cho quảng cáo của banbe" (dòng 182). **Xung đột** với kế hoạch "vị trí được tài trợ" trong `docs/retention-monetization-roadmap.md` (mục Thử doanh thu #2) và với bất kỳ chương trình đối tác nào: phải sửa policy trước.
- Đồng ý nhận quảng bá từ host: riêng, mặc định tắt, có nhật ký (dòng 163, 182). Cơ sở xử lý: hợp đồng, an toàn/chống gian lận, nghĩa vụ pháp lý, thông báo (dòng 178). Không có cơ sở "quảng cáo cá nhân hoá".
- Dữ liệu lưu ở Supabase ngoài Việt Nam, có chuyển dữ liệu xuyên biên giới (dòng 224).

### 2.7 Có chỗ nào cho coin quy đổi thành tiền hay voucher không?
**Không tìm thấy.** Ngược lại, thiết kế chặn rõ: "Coins have no cash value, cannot be bought or transferred" (165:14-15); giao diện ghi "không đổi lại thành tiền" (`src/screens/Rewards.jsx:201`, `src/lib/rewards.js:78`); iOS tương ứng (`AppState+Rewards.swift:153-160`). `reward_catalog.kind` chỉ cho `keychain_design` (165:171).

### 2.8 Số liệu hiện repo ghi được
Có: sự kiện, đặt chỗ, `check_ins`, `favorites` (`created_at` chỉ từ migration 165), `follows`, sổ cái, `reward_active_days`, `host_promo_consent`, DOB (cổng tài khoản). **Không tìm thấy** bảng impression/lượt xem/analytics trong migrations (grep). MAU/DAU, nguồn truy cập và vị trí người dùng: **[Chưa xác minh]** (chưa thấy bảng ghi hoạt động theo ngày ngoài `reward_active_days`).

---

## 3. So sánh Payback và WeWard

Ngày tra cứu tất cả nguồn bên dưới: **2026-10-08**. Công cụ đọc trang có thể tóm tắt không đầy đủ; các trích dẫn quan trọng nên được luật sư/bạn đối chiếu bản gốc.

### 3.1 Payback (Đức)
| Mục | Nội dung |
|---|---|
| Cơ chế & giá trị | Chương trình miễn phí, ~700 đối tác; "1 Punkt entspricht 1 Cent" **[Fact: payback.de/faq/punktewert & /faq/wie-funktioniert-payback, 2026-10-08]** |
| Đổi thưởng | Từ 200 điểm (2 euro): premium, phiếu mua hàng in tại đối tác, quyên góp, **chuyển khoản ngân hàng**, đổi 1:1 sang dặm Miles & More **[Fact: payback.de/faq/wie-funktioniert-payback; AGB Ziffer 4.1–4.2, payback.de/pb/agb, 2026-10-08]**. Điểm cũ dùng trước. Chuyển khoản do PAYBACK Verein thực hiện và chịu phí |
| Hạn dùng | Hết hạn 30/09 hằng năm nhưng **sớm nhất sau 36 tháng** kể từ đăng ký **[Fact: AGB Ziffer 5, payback.de/pb/agb, 2026-10-08]**; trang số liệu ghi hiệu lực 36 tháng **[Fact: payback.group/en/group/payback/facts-and-figures, 2026-10-08]** |
| Ai tài trợ / doanh thu | Đối tác báo giao dịch cho PAYBACK (AGB Ziffer 2.5). FAQ chính thức **không nêu** phí đối tác. Nguồn thứ cấp nói đối tác trả tiền để nhận dữ liệu hành vi mua sắm **[Chưa xác minh: tóm tắt tìm kiếm, nguồn gốc không rõ]**. Mô hình thường được hiểu là đối tác trả phí cho điểm + marketing dựa trên dữ liệu **[Ước tính]** |
| Dữ liệu & cơ sở pháp lý | Thu họ tên, ngày sinh, địa chỉ, chi tiết giao dịch (hàng, giá, nơi, thời gian), thông tin ngân hàng khi đổi. Cơ sở: Điều 6(1)(b) hợp đồng; 6(1)(a) **đồng ý riêng** cho quảng cáo/nghiên cứu thị trường; 6(1)(f) lợi ích chính đáng cho phát hiện gian lận. Rút đồng ý bất kỳ lúc nào; không đồng ý thì dữ liệu chỉ dùng quản lý thành viên **[Fact: payback.de/info/hinweise-datenschutz, 2026-10-08]** |
| Phán quyết BGH | BGH 16/07/2008, VIII ZR 348/06: điều khoản opt-out cho **bưu điện và nghiên cứu thị trường** được phép (không bị kiểm soát nội dung theo §307(3) BGB); cho **SMS/email** thì **không** hợp lệ, cần opt-in riêng (§7(2) Nr.3 UWG) **[Fact: lexetius.com/2008,2208, 2026-10-08]**. Phán quyết có trước GDPR (2018) và dựa trên BDSG cũ, nên chỉ là bối cảnh lịch sử; hiện hành là GDPR (đồng ý riêng) **[Ước tính]** |
| Chống gian lận | Có thể khoá tài khoản khỏi việc đổi thưởng khi nghi ngờ lạm dụng, gồm mẫu tích/đổi bất thường (AGB Ziffer 6.4) **[Fact: payback.de/pb/agb, 2026-10-08]** |
| Giữ chân (số liệu marketing của chính công ty) | FY2025: 35 triệu khách hoạt động ở Đức, 18 triệu người dùng app, ~700 đối tác, tỷ lệ đổi điểm 95%, 46 tỷ euro doanh số được khuyến khích **[Fact, marketing: payback.group facts-and-figures, 2026-10-08]**. Không có số retention độc lập |

### 3.2 WeWard (Pháp)
| Mục | Nội dung |
|---|---|
| Cơ chế | Quy đổi bước chân (đồng bộ Apple Health/Google Fit) và nhiệm vụ, khảo sát, thử thách, mua qua đối tác, giới thiệu thành "Wards" **[Fact: wewardapp.com/eu-cgu-12-24-en; mục kiếm Wards theo tóm tắt, 2026-10-08]** |
| Giá trị điểm | Điều 7.1: "Wards … are not monetary equivalents, virtual tokens, or a form of virtual currency and have no monetary value"; Điều 7.2: không hoàn bằng tiền, không đổi được **[Fact: wewardapp.com/eu-cgu-12-24-en, 2026-10-08]**. Ngưỡng rút 3.000 Wards theo blog bên thứ ba **[Chưa xác minh]** |
| Đổi thưởng | Điều 7.3: sản phẩm ảo, hỗ trợ dự án thiện nguyện/môi trường, voucher, mã giảm giá đối tác, **giải thưởng tiền mặt**, hàng hoá/dịch vụ. Tiền mặt cần tài khoản ngân hàng/PayPal và xác minh danh tính; số tiền bị trừ thuế khấu trừ theo luật. WeWard không chịu trách nhiệm với quyền lợi do đối tác cung cấp **[Fact: cùng nguồn]**. Điểm mâu thuẫn đáng chú ý: tuyên bố "không có giá trị tiền" nhưng vẫn trả tiền mặt |
| Hạn dùng | Không thấy điều khoản hết hạn Wards; mất khi chấm dứt tài khoản (Điều 14.4) **[Fact: cùng nguồn]** |
| Ai trả / doanh thu | Quảng cáo (interstitial, rewarded ads, offerwall MyChips), khảo sát; một nguồn nói quảng cáo ~40% doanh thu **[Chưa xác minh: tóm tắt tìm kiếm, nguồn không rõ]**. Case study AdMob: +10% doanh thu quảng cáo **[Fact, marketing của Google/WeWard: admob.google.co.in case study, 2026-10-08 (qua tìm kiếm)]**. Đối tác trả cho quảng bá/offer **[Ước tính]** |
| Dữ liệu & pháp lý | Thu tên, số điện thoại, email, IP, mã thiết bị, ảnh, thanh toán; cơ sở nêu: thực hiện hợp đồng; tối thiểu 16 tuổi (15 ở Pháp) **[Fact: wewardapp.com/privacy-policy & EU terms Điều 2.1, 2026-10-08, qua tìm kiếm]**. Cách xin đồng ý quảng cáo cá nhân hoá **[Chưa xác minh]** (chưa đọc đầy đủ chính sách) |
| Chống gian lận | Điều 7.6: cấm giả lập bước chân, vị trí hoặc giả giới thiệu; vi phạm bị đình chỉ/xoá tài khoản; Điều 6: chấm dứt ngay **[Fact: wewardapp.com/eu-cgu-12-24-en, 2026-10-08]** |
| Giữ chân (số liệu marketing) | ~20 triệu người dùng, >20 triệu euro đã trả cho người đi bộ; Amplitude case study: +10,5% người dùng kích hoạt, gấp đôi doanh thu/người dùng (2025-02); MyChips: +12% hoàn thành offer **[Fact, marketing/vendor: amplitude.com/blog/weward-boosted-engagement; maf.ad MyChips; builtin, 2026-10-08, qua tìm kiếm]**. Không có số retention độc lập |

---

## 4. Khoảng cách và ba hướng phát triển

### 4.1 Bảng so sánh
| Tiêu chí | banbe hiện tại | Payback | WeWard |
|---|---|---|---|
| Nguồn điểm | Điểm danh sự kiện thật (host xác nhận), onboarding | Mua hàng ở ~700 đối tác | Bước chân, nhiệm vụ, khảo sát, quảng cáo, mua qua đối tác |
| Giá trị điểm | Không có giá trị tiền, chỉ trang trí | 1 điểm = 1 cent, đổi được tiền | Tuyên bố không có giá trị tiền nhưng có thưởng tiền |
| Bên tài trợ | Không có | Đối tác bán lẻ (cơ chế phí chưa xác minh) | Nhà quảng cáo, đối tác, khảo sát |
| Đổi thưởng | 3 mẫu móc khoá | Phiếu, premium, chuyển khoản, dặm bay | Voucher, mã giảm giá, tiền mặt, quyên góp |
| Cá nhân hoá | Có cho "For You" (sở thích, owner-only); chưa cho ưu đãi | Cao, dựa dữ liệu giao dịch + đồng ý riêng | Cao, qua quảng cáo/offerwall |
| Chi phí vận hành | Thấp (DB + UI) | Rất cao (hạ tầng, đối tác, thanh toán) | Cao (adtech, KYC, chống gian lận) |
| Rủi ro pháp lý | Thấp | Cao (dữ liệu, tài chính) | Cao (giải thưởng tiền, dữ liệu, quảng cáo) |

### 4.2 Ba hướng
| | **A. Coin trang trí + huy hiệu + streak** | **B. Ưu đãi do host/địa điểm địa phương tự tài trợ** | **C. Đối tác thương hiệu kiểu Payback** |
|---|---|---|---|
| Lợi ích retention | Thấp–vừa, tạo thói quen nhẹ; chưa có số đo [Ước tính] | Vừa, ưu đãi thật gắn với hoạt động tại chỗ; hợp với "người tham dự thật" [Ước tính] | Cao nếu có quy mô; cần lượng người dùng lớn [Ước tính] |
| Chi phí | Gần 0, đã xây xong phần lớn | Thấp–vừa: tách loại thưởng, màn hình đổi, trang cho đối tác xác nhận (xem phần 6) | Cao: hợp đồng, đối soát, báo cáo, pháp lý, hỗ trợ |
| Ai trả phần thưởng | banbe (chi phí gần 0) | Host/địa điểm tự trả phần ưu đãi của họ | Thương hiệu trả; banbe nhận phí tài trợ |
| Thay đổi DB | Không (có thể sửa múi giờ) | Có: loại thưởng mới, ưu đãi + lượt đổi (mục 5.2) | Có, đầy đủ: sponsors, campaigns, settlements, báo cáo tổng hợp |
| Dữ liệu cá nhân cần thêm | Không | Tối thiểu: chỉ "người này đã đổi ưu đãi X"; không chia sẻ danh tính cho đối tác | Nhiều: cần đồng ý riêng, nhân khẩu học tổng hợp, đo hiệu quả |
| Rủi ro chính | Ít động lực; gian lận mất ý nghĩa | Gian lận host+bạn bè, tranh chấp ưu đãi, nghĩa vụ khuyến mại | Pháp lý, mâu thuẫn policy "không quảng cáo", phụ thuộc lượng người dùng |

---

## 5. Thiết kế sẵn sàng cho tài trợ (đề xuất, chưa triển khai)

### 5.1 Khe cắm hiện có và chỗ hard-code
| Thành phần | Hỗ trợ gì hiện nay | Hard-code cho cosmetic ở đâu | Cần tách |
|---|---|---|---|
| `reward_catalog` | Chỉ `kind='keychain_design'` (165:171) | `design_id NOT NULL UNIQUE` (165:172); không có tồn kho, hạn, quốc gia | Thêm `kind` mới; đưa dữ liệu riêng từng loại vào bảng con hoặc `payload jsonb` |
| `reward_unlocks` | Mỗi (user, item) một lần (PK, 165:188) | Thiết kế "mở khoá vĩnh viễn" | Ưu đãi cần nhiều lượt, trạng thái, hạn: dùng bảng **lượt đổi** riêng (`reward_redemptions`) |
| `redeem_reward` | Trừ coin + mở khoá, trả `design_id` (165:631-653) | Trả `design_id`; không kiểm tồn kho/hạn/quốc gia | Điều phối theo `kind`: cosmetic giữ nguyên, `partner_offer` đi nhánh mới |
| `profile_keychains_require_unlock` & `save_my_keychain` | Dùng `reward_catalog.design_id` (165:688-701, 772-776) | Gắn chặt keychain | Giữ nguyên cho cosmetic; chỉ lọc theo `kind='keychain_design'` |
| `get_my_rewards` | Trả catalog + `unlocked` (165:601-604) | Giả định 1 loại | Trả thêm `kind`, mô tả, trạng thái |
| UI web/iOS | Tiêu đề "Đổi thưởng (móc khoá)", hộp xác nhận (`Rewards.jsx:116, 201`), điều khoản (`rewards.js:77-87`, `AppState+Rewards.swift:153-160`) | Câu chữ nói chỉ mở khoá móc khoá | Tách mục "Trang trí" / "Ưu đãi" và câu chữ theo `kind` |

### 5.2 Mô hình dữ liệu mở rộng (CHỈ ĐỀ XUẤT, không tạo migration)
- `sponsors`: id, tên pháp lý, quốc gia (`US`/`VN`), loại (`host`/`venue`/`brand`), trạng thái, liên hệ, tham chiếu hợp đồng, ngày bắt đầu/kết thúc.
- `sponsor_campaigns`: id, `sponsor_id`, tên, `starts_at`/`ends_at`, trần ngân sách (số lượt hoặc giá trị), tổng số lượt, giới hạn mỗi người, `country_codes[]`, điều kiện (huy hiệu cần có, số lần điểm danh tối thiểu, loại sự kiện), trạng thái (nháp/chạy/tạm dừng/kết thúc).
- `reward_offers`: id, `campaign_id`, tiêu đề/mô tả (vi/en), điều khoản, `price_coins` (có thể 0 nếu mở khoá bằng huy hiệu), tồn kho, cách xác nhận (`partner_scan` / `partner_code` / `show_screen`), thời hạn đổi, khu vực.
- `reward_redemptions`: id, `user_id`, `offer_id`, `ledger_id` (nếu trừ coin), trạng thái (`issued`/`redeemed`/`expired`/`void`), mã hoặc token, `issued_at`, `expires_at`, `redeemed_at`, tham chiếu người xác nhận bên đối tác, `settlement_id`.
- `reward_settlements`: id, `campaign_id`, kỳ, số lượt đã đổi, tham chiếu hoá đơn/thanh toán **từ đối tác sang banbe** (nếu có phí tài trợ).
- `reward_events` (log hoạt động tối thiểu, tuỳ chọn, không chứa danh tính cho báo cáo): loại (`offer_viewed`/`offer_issued`/`offer_redeemed`), `offer_id`, ngày, khu vực thô.
- `reward_partner_consent` (riêng, mặc định tắt): xem 5.6.
Mọi bảng: RLS bật, không cấp quyền bảng cho client, chỉ qua RPC (cùng mẫu 165:191-201). Nếu có thêm quyền cho đối tác, tạo vai trò riêng và RPC "xác nhận một mã" chứ không cho đọc danh sách.

### 5.3 Ai phát hành voucher
| | **(1) Đối tác tự phát hành và xác nhận** | **(2) banbe phát hành mã thay đối tác** |
|---|---|---|
| Cách chạy | Đối tác (host/quán) cam kết ưu đãi; banbe chỉ tạo token ngắn hạn cho người dùng; đối tác xác nhận khi dùng (quét QR hoặc nhập mã trên trang nhẹ) | banbe tạo/giữ kho mã, có thể bán hoặc cấp mã đại diện đối tác |
| "Không giữ tiền" | Giữ nguyên: banbe không nhận tiền của người dùng, không giữ giá trị lưu trữ | Rủi ro: có thể thành người phát hành phiếu/giá trị lưu trữ, phải đối soát với đối tác khi có tranh chấp |
| Rủi ro pháp lý [Ước tính, hỏi luật sư] | Thấp; trách nhiệm ưu đãi thuộc đối tác (giống WeWard Điều 7.3 miễn trách nhiệm với quyền lợi của bên thứ ba) | Cao hơn: nghĩa vụ hoàn tiền, hạn dùng của phiếu, thuế/hoá đơn, có thể rơi vào quy định phiếu/tiền điện tử |
| Gian lận | Cần mã dùng một lần + hạn ngắn + xác nhận phía đối tác | Kiểm soát tập trung nhưng banbe gánh trách nhiệm |
| Khuyến nghị | **Chọn (1)** | Không làm cho đến khi có luật sư |

### 5.4 Quy tắc để coin không thành giá trị quy đổi tiền
Giữ đúng các điều đã có và thêm: coin không mua được, không chuyển nhượng (165:14-15); **không bao giờ đổi ra tiền mặt**; không dùng coin cho giải thưởng ngẫu nhiên/rút thăm (Apple 5.3.1 cũng yêu cầu sweepstakes do chính nhà phát triển tài trợ, nên không để đối tác tài trợ rút thăm); **thêm hạn dùng coin** (ví dụ coin hết hạn sau 12 tháng không hoạt động, giống logic Payback Ziffer 5 nhưng không có giá trị tiền); không cho đối tác chỉ định "giá" bằng tiền của coin; ưu đãi đối tác nên **mở khoá bằng huy hiệu/điểm danh** thay vì "trả coin", để tránh tạo cảm giác tỷ giá coin–tiền; mỗi ưu đãi có hạn và không cộng dồn thành số dư. Không dùng từ "tiền thưởng", "cashback", "1 coin = X đồng" trong UI và quảng bá.

### 5.5 Điều kiện thu hút đối tác
- Số liệu cần có: MAU (cần bảng hoạt động theo ngày, hiện **chưa có**); số đặt chỗ → điểm danh → quay lại (có sẵn trong `bookings`/`check_ins`); khu vực sự kiện/người dùng ở mức thô; nhân khẩu học tổng hợp (khoảng tuổi từ DOB; **[Chưa xác minh]** mức sẵn dữ liệu và chính sách dùng).
- Báo cáo tối thiểu cho đối tác, **chỉ số tổng hợp**: số ưu đãi hiển thị/phát hành/đã dùng theo tuần, tỷ lệ dùng, khu vực thô, khoảng tuổi gộp. **Ngưỡng nhóm tối thiểu** (ví dụ ẩn bất kỳ ô nào dưới 20 người) [Ước tính]; không có danh sách người dùng, không có tên/số điện thoại/email.
- Đo hiệu quả ngoài đời: mã dùng một lần hoặc QR do banbe ký, đối tác quét/nhập trên trang xác nhận; ghi `redeemed_at` và đối tác nào xác nhận; so sánh số phát hành với số đã dùng và với số người điểm danh tại sự kiện của chính đối tác.

### 5.6 Quyền riêng tư
- **KHÔNG BAO GIỜ chia sẻ với đối tác:** tên, số điện thoại, email, ngày sinh, địa chỉ, nội dung chat, tài liệu thanh toán, thông tin hoàn tiền/tranh chấp, danh sách sự kiện mà một người đã đi, `follows`, câu trả lời sở thích cá nhân (note 34: lưu trong bảng owner-only), số dư/lịch sử coin.
- **Consent riêng** cho ưu đãi cá nhân hoá của đối tác (mặc định tắt, ghi phiên bản và thời điểm, rút lại dễ). **Có tái dùng `host_promo_consent` không? Không nên.** Bảng này (`20261104000123…sql:335-342`) và policy (dòng 163) gắn với việc **host** soạn tin cho **một người nhận mỗi lần**, có nhật ký; mục đích và bên nhận khác với ưu đãi của đối tác trong app, nên tái dùng sẽ vi phạm nguyên tắc đồng ý theo mục đích (policy dòng 300 cũng hứa xin lại đồng ý khi đổi mục đích). Có thể **sao chép mẫu thiết kế** (bảng riêng, `consent_version`, `consented_at`, `withdrawn_at`, RPC get/set) thành `reward_partner_consent`.
- Ưu đãi không cá nhân hoá (cùng nội dung cho mọi người đủ điều kiện) không cần đồng ý quảng cáo riêng nhưng vẫn cần cập nhật policy.

---

## 6. Pháp lý và nền tảng (tổng quan, không phải tư vấn)

### 6.1 Việt Nam
- Khuyến mại: Nghị định 81/2018/NĐ-CP (sửa bởi Nghị định 128/2024/NĐ-CP) quy định hình thức, điều kiện, hạn mức (ví dụ giá trị vật chất khuyến mại cho một đơn vị hàng hoá/dịch vụ không quá 50% giá bán ngay trước đợt khuyến mại, theo tóm tắt) **[Fact: nguồn pháp luật qua tìm kiếm, luatminhkhue.vn / accgroup.vn, 2026-10-08; chưa đọc văn bản gốc]**. Nghĩa vụ đăng ký/thông báo với Sở Công Thương cho từng hình thức, vai trò của banbe (thương nhân khuyến mại hay chỉ nền tảng) **[Chưa xác minh]**.
- Dữ liệu cá nhân: Luật Bảo vệ dữ liệu cá nhân số 91/2025/QH15, hiệu lực từ 01/01/2026; dùng dữ liệu cho quảng cáo phải có đồng ý trên cơ sở khách hàng biết nội dung, phương thức, hình thức, **tần suất**, và có cách từ chối **[Fact: tổng hợp trên lsvn.vn/voh.com.vn/hethongphapluat.com qua tìm kiếm, 2026-10-08; chưa đọc văn bản gốc]**. Policy hiện đã nêu luật này (dòng 224, 256) nhưng chưa có mục đích "ưu đãi đối tác".
- Thuế người nhận ưu đãi, ví điện tử/trung gian thanh toán cần giấy phép NHNN: **[Chưa xác minh]**, để hỏi luật sư.

### 6.2 Hoa Kỳ
- Sweepstakes/contest: quy định theo từng bang (đăng ký, ký quỹ, "no purchase necessary"); **[Chưa xác minh]** chi tiết. Hướng đề xuất "không rút thăm" tránh toàn bộ nhóm rủi ro này.
- CCPA/CPRA: áp dụng nếu doanh thu hằng năm trên 25 triệu USD, hoặc mua/bán/chia sẻ dữ liệu của ≥100.000 người/hộ/thiết bị mỗi năm, hoặc ≥50% doanh thu từ bán/chia sẻ dữ liệu. Chương trình ưu đãi đổi lấy dữ liệu cần **Notice of Financial Incentive** và đồng ý opt-in, thu hồi được **[Fact: termsfeed.com, stradlinglaw.com qua tìm kiếm, 2026-10-08; kiểm lại ngưỡng hiện hành]**. banbe có thể chưa đạt ngưỡng nhưng nên thiết kế sẵn.
- Thuế (khai báo giải thưởng), luật bang về phiếu quà/giá trị lưu trữ, "money transmitter": **[Chưa xác minh]**.

### 6.3 Điểm nào khiến coin bị xem là ví/tiền/ngân phiếu cần giấy phép [Ước tính, hỏi luật sư]
Coin có thể mua bằng tiền; coin chuyển được giữa người dùng; coin đổi được ra tiền hoặc phiếu có giá trị tiền cố định; có tỷ giá công bố; có giữ tiền của người dùng hộ đối tác; hạn dùng quá dài hoặc không hết hạn như số dư; cho đối tác thanh toán bằng coin. Tránh tất cả các điểm này để không thành tiền điện tử/phiếu giá trị lưu trữ/ví. Lưu ý WeWard tuyên bố "không có giá trị tiền" nhưng vẫn trả tiền mặt (Điều 7.3), tức là cách gắn nhãn không thay thế được bản chất kinh tế; banbe nên **không** có đường đổi tiền mặt.

### 6.4 Nền tảng ứng dụng
- **Apple App Store** **[Fact: developer.apple.com/app-store/review/guidelines/, 2026-10-08; công cụ đọc có thể bỏ sót phần cuối trang]**:
  - 3.1.1: tiền tệ trong app mua bằng IAP không được hết hạn; phiếu/voucher/coupon đổi lấy **hàng hoá số** chỉ được **bán** trong app qua IAP. Coin của banbe **không bán** và chỉ kiếm được, nên ít bị ảnh hưởng, **nhưng** nếu sau này bán coin hoặc voucher số trong app thì phải dùng IAP (và cân nhắc quy định không hết hạn đối với coin đã mua).
  - 3.1.3(e): hàng hoá/dịch vụ tiêu dùng **ngoài app** (ví dụ ưu đãi tại quán) phải dùng cách thanh toán khác IAP. Ưu đãi đối tác dùng ngoài đời nằm ngoài IAP.
  - 5.3.1–5.3.2: sweepstakes/contest phải do chính nhà phát triển tài trợ và có luật chơi trong app; không để đối tác tài trợ rút thăm trong app.
- **Google Play** **[Fact: support.google.com/googleplay/android-developer/answer/9877032 và /10281818, qua tìm kiếm, 2026-10-08]**: ứng dụng không phải game có thể có loyalty gamification/phần thưởng biến thiên nếu công bố tỷ lệ trúng; game thì phần thưởng phải theo tỷ lệ và lịch cố định. Hàng hoá số như tiền ảo cần dùng Play Billing. Với banbe, tương đương: không bán coin, không rút thăm, không đổi tiền.

### 6.5 Danh sách câu hỏi cho luật sư
1. Chương trình đổi coin lấy ưu đãi do đối tác tự phát hành có bị coi là khuyến mại thương mại ở Việt Nam không? Ai là bên thực hiện, cần đăng ký/thông báo gì?
2. Ở Mỹ, coin kiếm được (không mua, không chuyển, không đổi tiền) có bị xếp vào "gift card/stored value" hay "financial incentive" theo CCPA không? Cần Notice of Financial Incentive khi nào?
3. banbe nhận **phí tài trợ từ đối tác** (không giữ tiền người dùng) có làm banbe thành bên phân phối khuyến mại hay quảng cáo? Cần sửa điều khoản nào, kể cả câu "không chạy quảng cáo"?
4. Thuế cho người nhận ưu đãi giá trị nhỏ ở Việt Nam và Mỹ: có nghĩa vụ khai báo/khấu trừ không, dưới ngưỡng nào?
5. Nếu host/địa điểm tự tài trợ và banbe chỉ xác nhận điều kiện, ai chịu trách nhiệm khi ưu đãi không được tôn trọng? Điều khoản cần có với host.
6. Cơ sở xử lý dữ liệu cho báo cáo tổng hợp gửi đối tác (không định danh) và cho ưu đãi cá nhân hoá theo Luật 91/2025/QH15 và CCPA/CPRA; có cần đánh giá tác động/đăng ký chuyển dữ liệu ra nước ngoài thêm không (policy dòng 224)?
7. Coin có hạn dùng và không đổi tiền có đủ để tránh bị xem là tiền điện tử/ví ở VN và Mỹ không? Ngưỡng nào làm thay đổi kết luận?
8. Tuổi người dùng: ưu đãi đồ uống có cồn/đối tượng 18+ cho người dưới 18 (policy yêu cầu 18+ cho host, cần kiểm tra yêu cầu tuổi người dùng).
9. Đối với người dùng Mỹ và Việt Nam khác nhau, có cần hai bộ điều khoản/chương trình tách biệt không?

---

## 7. Lộ trình, rủi ro, câu hỏi mở

Công sức tính theo người-ngày của một dev; [Ước tính].

| Giai đoạn | Việc | Nhãn | Công sức | Điều kiện kích hoạt | Rủi ro | Rollback |
|---|---|---|---|---|---|---|
| **0** | Tách `kind` trong catalog và UI; giữ cosmetic y nguyên | **NGAY** | 3–5 ngày | Không cần đối tác | Hỏng luồng đổi móc khoá hiện có (đã có test local) | Migration lùi bằng rollback mới (mẫu `…166_revert_rewards.sql`) |
| 0 | Múi giờ theo người dùng/thị trường (VN/US) cho streak và trần tháng, thay vì cố định VN | **NGAY** | 2–4 ngày | Quyết định #1 | Streak người dùng cũ thay đổi | Quay về khoá VN qua `rewards_tz()` |
| 0 | Bảng nháp sponsors/campaigns/offers/redemptions (migration chưa áp dụng) và RPC xác nhận | **NGAY** (chỉ viết) | 3–5 ngày | Không cần đối tác | Bảng trống không rủi ro | Không áp dụng = không có gì để lùi |
| 0 | Log hoạt động tối thiểu (xem/được phát hành/đã dùng) không gắn danh tính cho báo cáo | **NGAY** | 3–4 ngày | Cập nhật policy | Policy hiện nói không dùng dữ liệu cho quảng cáo | Tắt log, giữ dữ liệu cũ |
| 0 | Cập nhật policy: coin/rewards, mục đích ưu đãi, thay câu "không chạy quảng cáo" nếu cần | **NGAY** (cần luật sư duyệt) | 1–2 ngày + luật sư | Hỏi luật sư mục 6.5 | Sai pháp lý | Rút bản mới, giữ bản cũ |
| 0 | Chống gian lận host–bạn bè: ngưỡng bất thường (số khách điểm danh trên mỗi host, tài khoản mới), duyệt thủ công khi coin có giá trị | **NGAY** (nhẹ) | 3–6 ngày | Trước khi có ưu đãi thật | Tăng ma sát với host thật | Tắt cờ cảnh báo |
| **1** | Thử 1 host/địa điểm tài trợ nhỏ, phát hành bởi đối tác (5.3 phương án 1), chỉ ở một quốc gia | **CHỜ** | 5–10 ngày + thoả thuận nhẹ bằng văn bản | Có 1 đối tác sẵn lòng, Giai đoạn 0 xong, luật sư xem trước | Gian lận, tranh chấp ưu đãi | Tạm dừng chiến dịch (`status=paused`), void các lượt chưa dùng |
| **2** | Chương trình đối tác chính thức: hợp đồng, báo cáo tổng hợp, đối soát, consent cá nhân hoá | **CHỜ** | 20–40 ngày + pháp lý | Số liệu Giai đoạn 1 cho thấy hiệu quả, có ≥2–3 đối tác | Pháp lý, phụ thuộc đối tác, mâu thuẫn policy | Kết thúc chiến dịch, giữ dữ liệu theo hạn lưu trữ, tắt nhánh `partner_offer` |

### Rủi ro chính
Gian lận khi coin có giá trị; mâu thuẫn policy "không quảng cáo"; số liệu retention của Payback/WeWard đều là marketing, không dùng làm căn cứ cho kỳ vọng; ghi chú 36 nói rõ các con số coin/streak hiện là đề xuất sản phẩm, không dựa thị trường; migration 165 và các migration trước chưa áp dụng lên production nên mọi kết luận về hành vi thật còn là suy ra từ code/test local.

### Câu hỏi còn mở
1. `check_in_guest` có ràng buộc khung giờ/vị trí không?
2. Dữ liệu vị trí/nhân khẩu học người dùng hiện lưu ở đâu, đủ để báo cáo tổng hợp chưa?
3. WeWard xin đồng ý quảng cáo như thế nào, đối tác Payback trả phí thế nào (cần đọc nguồn gốc)?
4. Văn bản gốc Nghị định 81/2018 (và 128/2024) về trần giá trị, đăng ký khuyến mại.
5. Ngưỡng nhóm tối thiểu cho báo cáo đối tác (đề xuất 20) có phù hợp quy mô người dùng không.

### Quyết định cần bạn chọn (tối đa 5)
1. **Múi giờ streak/trần tháng:** theo thị trường người dùng (VN/US) hay theo múi giờ lưu trong hồ sơ? *(Khuyến nghị: theo hồ sơ, mặc định theo thị trường.)*
2. **Hướng đi trước mắt:** chỉ A, hay A + thử B ở Giai đoạn 1? *(Khuyến nghị: A + B nhỏ, hoãn C.)*
3. **Ai phát hành voucher:** đối tác tự phát hành/xác nhận hay banbe phát hành mã? *(Khuyến nghị: đối tác.)*
4. **Policy:** chấp nhận sửa câu "không chạy quảng cáo" để cho phép "ưu đãi được tài trợ có nhãn rõ", hay giữ nguyên và chỉ làm ưu đãi do host/địa điểm tự đăng? *(Khuyến nghị: phân biệt rõ hai loại, nhờ luật sư soạn câu.)*
5. **Cách mở ưu đãi đối tác:** trừ coin hay mở bằng huy hiệu/điểm danh (không trừ coin)? *(Khuyến nghị: huy hiệu/điểm danh, để tránh coin giống tiền.)*

---

## Nguồn (tra cứu 2026-10-08)
- Payback: https://www.payback.de/faq/punktewert · https://www.payback.de/faq/wie-funktioniert-payback · https://www.payback.de/pb/agb · https://www.payback.de/info/hinweise-datenschutz · https://www.payback.group/en/group/payback/facts-and-figures
- BGH VIII ZR 348/06 (16/07/2008): https://lexetius.com/2008,2208
- WeWard: https://wewardapp.com/eu-cgu-12-24-en · https://wewardapp.com/privacy-policy · https://amplitude.com/blog/weward-boosted-engagement · https://maf.ad/en/project/weward-steps-up-engagement-by-12-with-mychips/ · https://admob.google.co.in/home/resources/weward-achieves-10-percentage-revenue-uplift-with-admob/
- Apple: https://developer.apple.com/app-store/review/guidelines/ · Google Play: https://support.google.com/googleplay/android-developer/answer/9877032 · https://support.google.com/googleplay/android-developer/answer/10281818
- VN: https://luatminhkhue.vn/van-ban/nghi-dinh-81-2018-nd-cp.aspx · https://accgroup.vn/nghi-dinh-128-2024-nd-cp-sua-doi-nghi-dinh-81-2018-nd-cp-huong-dan-luat-thuong-mai-ve-hoat-dong-xuc-tien-thuong-mai · https://lsvn.vn/quy-dinh-ve-bao-ve-du-lieu-ca-nhan-trong-mot-so-hoat-dong-tu-nam-2026-a161847.html
- US/CCPA: https://www.termsfeed.com/blog/ccpa-notice-financial-incentive/ · https://www.stradlinglaw.com/news-insights/navigating-the-financial-incentive-requirement-of-the-california-consumer-privacy-act.html
- Repo: `.claude/notes/36-rewards-badges-following-map-foryou.md`, `supabase/migrations/20261212000165_165_rewards_badges_streaks.sql`, `supabase/rollbacks/20261212000166_166_revert_rewards.sql`, `supabase/migrations/20261201000151_151_per_attendee_tickets.sql`, `supabase/migrations/20261104000123_123_phone_dob_gate_and_promo_consent.sql`, `src/lib/rewards.js`, `src/screens/Rewards.jsx`, `apps/ios/BanbeApp/State/AppState+Rewards.swift`, `banbe_User_Policy.md`, `docs/retention-monetization-roadmap.md`

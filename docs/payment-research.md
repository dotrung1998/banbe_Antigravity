# Nghiên cứu thanh toán goer → host (banbe)

Ngày tra cứu: 2026-10-07. Đây là báo cáo nghiên cứu, **không phải tư vấn pháp lý/thuế**. Chưa sửa code, chưa chạy migration, chưa gọi API thật.

Quy ước nhãn:
- **[Fact: nguồn, ngày]**: đọc từ tài liệu/mã nguồn.
- **[Ước tính]**: suy luận của người nghiên cứu hoặc số liệu chưa xác minh trên nguồn chính thức.
- **[Chưa xác minh]**: nguồn bị chặn/không tải được, cần kiểm tra lại.

Giới hạn tra cứu cần biết trước:
- Trang giá Stripe trả về bản EUR, nên mọi số USD của Stripe đều là [Ước tính].
- Bảng giá SePay (403), tài liệu payOS (không truy cập được), trang API vietqr.io (404): phần phí SePay/payOS/VietQR là [Chưa xác minh].
- VNPAY, ZaloPay, API ngân hàng trực tiếp: chưa tra được tài liệu chính thức.
- Phần pháp lý dựa chủ yếu vào báo và trang tổng hợp luật, chưa đọc văn bản gốc (FinCEN, NHNN, Bộ Tài chính, Apple).

---

## 1. Tóm tắt và khuyến nghị

1. **Hiện trạng đã gần đúng mục tiêu "banbe không giữ tiền"**: goer chuyển khoản thẳng cho host, banbe chỉ ghi trạng thái. Cái thiếu là **xác nhận tự động tin cậy** và **refund tự động**.
2. **Mỹ (USD)**: Stripe Connect, tài khoản host kiểu Standard (tương đương cấu hình "host trả phí, host chịu dispute"), **direct charge qua Checkout**. Đây là cấu hình duy nhất thỏa cùng lúc: tiền vào tài khoản host, webhook tự xác nhận, refund qua API, host cá nhân onboard được, Stripe lo KYC/1099-K.
3. **Việt Nam (VND)**: banbe hiển thị VietQR của host (đã có) và **đối soát qua webhook ngân hàng** (SePay/payOS/Casso, host tự liên kết tài khoản của mình). Webhook đã có sẵn trong repo (`api/payment-webhook.js`). **Refund không tự động hóa được** (không có refund API ở mô hình này): banbe chỉ tạo lệnh hoàn kèm VietQR sinh sẵn, host quét chuyển tay. MoMo Partner không dùng được cho host cá nhân (cần giấy phép kinh doanh).
4. **Bỏ escrow**: thay "chờ host xác nhận 1h" bằng xác nhận webhook + giữ chỗ ngắn (10–15 phút, giữ **chỗ** không giữ **tiền**) + chính sách hoàn tiền theo thời hạn. Đánh đổi: banbe không còn đòn bẩy tiền với host xấu; chỉ còn biện pháp uy tín/khóa tài khoản/điều khoản.
5. **Việc phải làm trước khi build**: luật sư Mỹ (money transmitter, sales/admission tax theo bang) và luật sư/kế toán VN (có là sàn TMĐT phải đăng ký không, nghĩa vụ thuế nền tảng theo văn bản mới). Chọn 1 trong 3 kịch bản phí ở mục 7.

---

## 2. Hiện trạng (có dẫn chứng)

Nguồn: phân tích repo chỉ đọc. Đường dẫn tính từ gốc repo. Bỏ qua bản sao trong `.kilo/worktrees/`.

### 2.1 Luồng tiền hiện tại
- banbe không thu, giữ hay chuyển tiền: `banbe_User_Policy.md:18`, `:76-78` (A4). Host tự thu, tự hoàn, tự chịu thuế/hóa đơn.
- Migration `supabase/migrations/20260913000024_024_payments_and_documents.sql:3-7`: "banbe never touches the money".
- Chuỗi bước:
  1. `hold_seats()` (`…026_payment_state_machine.sql:282`): event miễn phí → `confirmed` ngay (`:342`), có phí → `holding` (`:343`). Giữ chỗ 30 phút (`events.hold_minutes`, notes/01).
  2. Goer thấy VietQR động + bank/MoMo của host (`src/screens/PaymentDetails.jsx:235,243,670`, `src/lib/vietqr.js`).
  3. Goer bấm "Tôi đã chuyển khoản" → `submit_payment_proof()` (`026:459`) → `pending_verification`, đồng hồ đóng băng, `verify_due_at = now()+60'`.
  4. Host bấm "Money received" → `verify_payment()` (`026:608`), hoặc qua bot Telegram (`027:92`, `api/telegram-webhook.js`). → `confirmed`, phát QR vé.
  5. Hóa đơn/biên nhận do host upload (migration 056, notes/08).
- Tiền nằm ở tài khoản ngân hàng/ví của host. Không có ví, escrow hay bảng số dư nào của banbe.

### 2.2 Nhà cung cấp thanh toán
- `package.json:12-25`: không có SDK thanh toán nào. `.env.example`: không có biến thanh toán.
- Không tìm thấy: Stripe, PayPal, MoMo API, VNPay, ZaloPay, SePay. Chỉ có nhãn UI (`HostIntro.jsx:14`) và ảnh QR host tự upload (VietQR/MoMo/Zelle/Venmo/Cash App, `src/screens/sheets/PaymentQrManager.jsx:199`, migration 122).
- **Có webhook đối soát**: `api/payment-webhook.js:56-88` chuẩn hóa Casso/PayOS/generic; xác thực `:104-117` (Casso `secure-token`, PayOS HMAC-SHA256, generic `x-webhook-secret`); gọi RPC `record_bank_transaction` (`:140`, định nghĩa `026:1011`); chỉ xử lý tiền vào (`:135`). Biến `CASSO_WEBHOOK_SECRET`, `PAYOS_CHECKSUM_KEY`, `BANK_WEBHOOK_SECRET` chỉ có trong code, **chưa có trong `.env.example`**. Chưa thấy bằng chứng host nào đã kết nối.

### 2.3 Bảng lưu trạng thái
- `bookings`: `payment_state` (holding, pending_verification, confirmed, expired, disputed, cancelled), `total_vnd`, `payment_ref`, `paid_marked_at`, `verified_via`, `proof_path`… (`002`, `026:73-96`, `024:51-54`).
- `payment_audit_log` (`026:140`), `payment_webhook_events` (`026:217-232`, unique theo provider+external_id, chỉ service-role), `payment_documents` (`024`, `056`), `alert_outbox` (`026:922`).
- Refund: `refund_claims` (`002:41-54`, mở rộng ở 072/074/127), `refund_destinations` (071/074/122), `refund_batches`/`refund_batch_items` (073). Trạng thái: owed → host_marked_sent → guest_confirmed / disputed / waived.
- Host: `organizers` có bank/MoMo/QR (`001:47-53`, `024`, `122`), **không có country/currency/provider**. Không có KYC.
- Dispute: `dispute_threads`, `dispute_messages` (migration 033); quyết định admin chỉ đổi trạng thái booking, "no money moved" (notes/03).

### 2.4 Policy
- banbe là trung gian; hợp đồng giữa goer và host (`banbe_User_Policy.md:58`). Hiện không có phí/hoa hồng; chỉ hứa báo trước nếu sau này thu phí (`:58`).
- Hoàn tiền: banbe "không thể hoàn tiền hay đòi tiền giúp" (`:19-20`, `:86`, `:88`); host báo đã hoàn → goer 7 ngày xác nhận, im lặng = tự xác nhận; quá hạn → tranh chấp → admin.
- Nghĩa vụ host: công bố giá/điều kiện hoàn, tự thu/hoàn ngoài banbe, tự chịu thuế/giấy phép (`:102`). Admin có quyền gỡ sự kiện, tạm ngưng hồ sơ (`:104,106`).
- Luật áp dụng/tòa: Việt Nam (`:126`). **Policy chưa nói gì về Mỹ.**
- `docs/retention-monetization-roadmap.md:16-17,24`: "không tự giữ/thu/chuyển tiền thay host"; phí theo vé chỉ nghiên cứu khi có đối soát + đối tác thanh toán phù hợp.

### 2.5 Doanh thu/phí của banbe
- Không giữ tiền. Không có doanh thu banbe. `grep commission|platform_fee|service_fee` trong migrations: không tìm thấy.

### 2.6 Web hay native
- **Cả hai**: web Vite/React 19 deploy Vercel; iOS SwiftUI native (`apps/ios/BanbeApp`, bundle `com.banbe.ios`). Không có Capacitor/StoreKit/IAP.
- iOS hiện build bằng Apple ID miễn phí (`PersonalTeamDebug`, notes/18), `DEVELOPMENT_TEAM = ""`: **chưa lên App Store**. Quy tắc Apple chưa phát sinh nhưng sẽ khi phát hành.

### 2.7 Tiền tệ/vị trí
- Giá/booking/refund đều đặt tên VND: `events.price_vnd`, `bookings.total_vnd`, `refund_claims.amount_vnd`, `record_bank_transaction(p_amount_vnd)`. Có `events.price_cents` (`001:77-78`) nhưng chưa RPC thanh toán nào dùng. `payment_documents.currency` mặc định 'VND'.
- Vị trí: `events.country_code` (2 ký tự, **nullable**, event cũ có thể thiếu; migration 112:51), `state_province`. Dùng được để route VN/US, nhưng cần quy tắc dự phòng.

### 2.8 Lệch giữa ghi chú và code
- notes/02 nói auto-confirm 1h; **code không có**: `sweep_verification_slas` (`026:939`) chỉ nhắc/escalate. Host im lặng → booking kẹt `pending_verification`.
- "Payment window" = chính hold 30 phút (notes/01), không phải khoảng riêng.
- "Escrow" trong CLAUDE.md chỉ là tên luồng trạng thái; **không có giữ tiền thật**.

---

## 3. Bảng so sánh phương án

Giả định host: cá nhân, tài khoản ngân hàng cá nhân, chưa có đăng ký kinh doanh.

### 3.1 Mỹ (USD)

| Tiêu chí | A. Stripe Connect Standard + direct charge | Stripe Express/Custom | B. PayPal Multiparty | Square OAuth | Cash App Pay | Venmo | Zelle | Hiển thị handle + xác nhận tay |
|---|---|---|---|---|---|---|---|---|
| banbe chạm tiền? | Không. Charge nằm trên tài khoản host, số dư banbe chỉ tăng đúng application fee | Có thể (destination) | Không (payee nhận trực tiếp) | Không | Qua PSP | Không có API | Không | Không |
| Host cá nhân, chưa có công ty | Được (`business_type=individual`) | Được | Cần tài khoản Business, cần banbe được PayPal duyệt làm Partner [Ước tính] | Có thể [Ước tính] | Qua Stripe/Square | Cấm dùng thương mại | Không tích hợp | Được, nhưng vi phạm ToS |
| Xác nhận tự động | Webhook `checkout.session.completed` | Có | Có [Ước tính] | Có | Có | Không | Không | Không |
| Refund tự động | Có: Create Refund + header `Stripe-Account` | Có | Có | Có | Có (90 ngày) | Không | Không | Không |
| Ai chịu phí xử lý | Host (trực tiếp với Stripe) | Platform nếu `fees.payer=application` | Seller | Seller | PSP | n/a | Miễn phí | 0 |
| Phí | 2.9% + 30¢, dispute $15 [Ước tính] | + phí Connect ($2/tháng/tài khoản active + 0.25%+$0.25/payout [Ước tính]) | 3.49% + $0.49 [Fact: paypal.com/us/webapps/mpp/merchant-fees, 2026-10-07] | Theo Square | ~2.9%+30¢ [Chưa xác minh] | n/a | 0 | 0 |
| Chargeback | Host chịu (Standard direct) [Fact: docs.stripe.com/connect/accounts, 2026-10-07] | Platform chịu | Seller/PayPal | Seller [Ước tính] | Qua PSP | n/a | n/a | Không có bảo vệ |
| 1099-K | Stripe phát hành khi host trả phí trực tiếp [Fact: docs.stripe.com/connect/tax-reporting, 2026-10-07] | Platform có thể phải tự lo | PayPal [Ước tính] | Square [Ước tính] | PSP | Venmo/PayPal | Không | Không |
| Công sức tích hợp | Trung bình | Cao | Cao + cần duyệt | Trung bình | Thấp nếu qua Stripe | – | – | Thấp |

Ghi chú:
- Stripe docs đã gọi Standard/Express/Custom là "legacy", khuyên dùng Accounts v2/controller properties [Fact: docs.stripe.com/connect/accounts-v2, 2026-10-07]. Khi build chọn cấu hình tương đương Standard: host tự trả phí, host chịu dispute, Dashboard đầy đủ.
- Direct charge: `application_fee_amount` tùy chọn, Stripe không tính phí thêm trên khoản này [Fact: docs.stripe.com/connect/direct-charges, 2026-10-07]. Refund không tự hoàn application fee; phải truyền `refund_application_fee=true`.
- Host âm số dư sau refund: Stripe có thể tự ghi nợ ngân hàng host để bù (`debit_negative_balances`, mặc định bật với tài khoản Stripe thu thập thông tin, gồm Standard) [Fact: docs.stripe.com/connect/risk-management/best-practices, 2026-10-07]. Chưa thấy tài liệu nói rõ refund có bị từ chối khi thiếu số dư: **cần test sandbox**.
- Venmo Developer/Payouts API đã đóng với đối tác mới [Fact: fintechfutures.com, "Venmo closes API to new developers"]. Venmo/Cash App/Apple Pay chỉ nên bật qua Stripe Checkout, không tích hợp riêng.
- Zelle: không có API checkout công khai, không webhook, không refund API [Chưa xác minh: apiture.com/zelle-for-business].

### 3.2 Việt Nam (VND)

| Giải pháp | Host cá nhân không GPKD | banbe chạm tiền? | Xác nhận tự động | Refund API | Phí | Multi-tenant |
|---|---|---|---|---|---|---|
| **C1. VietQR host + SePay (đối soát)** | Có (SePay phục vụ cá nhân) [Fact: itviec.com/nha-tuyen-dung/sepay, 2026-10-07] | Không | Webhook HMAC-SHA256, retry 7 lần, ~5–10 giây [Fact: developer.sepay.vn/en/sepay-webhooks] | Không (chỉ đọc biến động số dư) | [Chưa xác minh] (trang giá 403) | Mỗi host tự đăng ký SePay + liên kết ngân hàng (OTP chính chủ). banbe nhận webhook; có OAuth2 API quản lý webhook [Fact: docs.sepay.vn/oauth2/api-webhooks.html] |
| **C2. VietQR host + payOS** | Có, chỉ cần CCCD, không cần GPKD [Fact: payos.vn, 2026-10-07] | Không [Ước tính: qua NAPAS thẳng vào TK host] | Webhook có chữ ký, payment link, SDK [Fact: payos.vn] | Không refund. Có API "Chi hộ" mới; dùng được với TK cá nhân hay không: chưa xác minh | Không phí trung gian; gói theo ngân hàng, BIDV-1K miễn phí 1.000 GD/năm đến 31/12/2026 [Fact: payos.vn]; bảng đầy đủ chưa lấy được | Mỗi host 1 tài khoản + 1 kênh + bộ khóa riêng; banbe phải lưu khóa mã hóa theo host. Chưa thấy API partner tạo kênh thay host |
| **C3. VietQR host + Casso** | Có [Ước tính] | Không | Webhook V2 [Fact: developer.casso.vn] | Không | Theo năm theo GD + TK (14 ngày/100 GD dùng thử) [Fact: casso.vn/bang-gia, 2026-10-07]; không hợp host ít sự kiện [Ước tính] | Mỗi host 1 tài khoản |
| **C0. Chỉ hiển thị QR host, không webhook** | Có | Không | Không (host bấm xác nhận tay) | Không | 0 | Không cần. **Đây là hiện trạng** |
| D. MoMo Partner/gateway | **Không**: chỉ dành cho doanh nghiệp/hộ kinh doanh, định danh theo GPKD [Fact: momo.vn thông cáo 2026-03-20] | Có (ví) | Có | Có nhưng cần hồ sơ doanh nghiệp | Có phí | Không có sub-merchant cho cá nhân [Ước tính]. Loại |
| VNPAY, ZaloPay | Thường cần merchant (MST/GPKD) [Ước tính, chưa tra] | Có | Có | Có (merchant) | Có phí | Không phù hợp giai đoạn đầu |
| API ngân hàng trực tiếp | Thường không [Ước tính] | Không | Có | Tùy ngân hàng | Hợp đồng riêng | Khó mở rộng; SePay/Casso gom lại |
| VietQR API (chỉ tạo QR) | Có | Không | **Không có xác nhận** | Không | Miễn phí [Ước tính] | – |

**Câu hỏi mở quyết định khả năng mở rộng (chưa có đáp án công khai)**: SePay/payOS/Casso có chương trình đối tác/API cho phép marketplace onboard nhiều host (sub-account/VA theo host) không? Nếu không, mỗi host phải tự đăng ký (ma sát onboarding cao).

### 3.3 Phương án E (lai) = chọn theo nước

| | Mỹ | Việt Nam |
|---|---|---|
| Cổng | Stripe Connect Standard, direct charge | VietQR host + webhook SePay/payOS |
| Xác nhận | Webhook Stripe, tức thì | Webhook ngân hàng, giây–phút, có ca "chưa khớp" cần gán tay |
| Refund | Tự động qua API | Bán tự động: host quét VietQR hoàn tiền, theo dõi tiền ra qua webhook (SePay theo dõi giao dịch ra) |
| Phí xử lý | Host (~2.9%+30¢ [Ước tính]) | Host (phí SePay/payOS nếu có) |
| Chargeback | Host (thẻ) | Không có chargeback (chuyển khoản NAPAS) |

---

## 4. Kiến trúc đề xuất

### 4.1 Định tuyến theo location
- Quy tắc: `payment_rail` của event = suy ra từ `events.country_code` (`US` → `stripe`, `VN` → `vietqr`). Nếu `country_code` NULL: dùng quốc gia của organizer; nếu vẫn NULL thì chặn publish sự kiện có phí (hoặc bắt chọn). Lưu `payment_rail` và `currency` **chốt lúc publish** để không đổi giữa chừng.
- Host cần hồ sơ nhận tiền theo rail: US = tài khoản Stripe connected; VN = ngân hàng + (tùy chọn) liên kết SePay/payOS.
- Host ở VN tạo sự kiện ở Mỹ (hoặc ngược lại) = ca biên, mục 7.

### 4.2 Luồng Mỹ (Stripe direct charge)
```
Goer ──bấm "Pay"──▶ banbe API (Vercel) ──Checkout Session (Stripe-Account: acct_host,
                                          application_fee_amount tùy chọn, metadata: booking_id)
Goer ──trả tiền──▶ Stripe ──▶ số dư của host (banbe không chạm tiền)
Stripe ──webhook checkout.session.completed──▶ banbe /api/stripe-webhook
        verify chữ ký → idempotent theo event.id → set payment_state=confirmed → phát QR vé
```
- Giữ chỗ 10–15 phút = `expires_at` của Checkout Session; hết hạn → `expire_stale_holds`.
- Hoàn tiền: banbe gọi Create Refund (`Stripe-Account`, `refund_application_fee=true`) khi (a) host hủy sự kiện, (b) goer hủy trong hạn chính sách, (c) quyết định admin. Webhook `charge.refunded` cập nhật `refund_claims`.
- Onboarding host: Account Link, nghe `account.updated`, chỉ cho bán vé khi `charges_enabled`.
- Webhook phải đăng ký là **Connect endpoint** (sự kiện của tài khoản kết nối).

### 4.3 Luồng Việt Nam (VietQR + đối soát)
```
Goer ──xem VietQR (đúng số tiền + nội dung "BB<mã ngắn>")──▶ quét bằng app ngân hàng
Tiền ──NAPAS──▶ tài khoản ngân hàng host (banbe không chạm tiền)
SePay/payOS (host tự liên kết) ──webhook──▶ banbe /api/payment-webhook (đã có)
        verify chữ ký → dedupe theo mã giao dịch ngân hàng → khớp mã + đủ tiền → confirmed
        không khớp/thiếu/thừa → hàng đợi "cần xử lý" cho host/admin
```
- Các rủi ro đã nêu của kiểu đối soát: khách sửa/xóa nội dung, chuyển thiếu/thừa, webhook trùng/muộn, ngân hàng cắt nội dung, host ngắt liên kết. Cần: mã chỉ chữ+số ngắn, trạng thái liên kết host kiểm tra trước khi mở bán, nút "tôi đã chuyển khoản" giữ lại làm đường dự phòng (đã có) nhưng host xác nhận tay chỉ là **dự phòng**, không phải đường chính.
- Hoàn tiền: banbe tạo lệnh hoàn kèm VietQR (số tiền + tài khoản `refund_destinations` của goer, đã có), host quét chuyển tay; theo dõi tiền ra qua webhook của chính tài khoản host để tự đóng lệnh (nếu provider hỗ trợ giao dịch ra; SePay có [Ước tính cần xác minh]); nếu không thì giữ cơ chế goer xác nhận/7 ngày tự xác nhận đang có.
- Không có API tự động hoàn tiền ở rail này. Nói thẳng với người dùng/host.

### 4.4 Thiết kế không escrow: bỏ gì, giữ gì
Bỏ: bước "chờ host xác nhận trong 1h" cho host đã kết nối đối soát/Stripe. Thay bằng:
- **Giữ chỗ (reservation hold)**: `hold_seats` giữ ghế 10–15 phút trong lúc thanh toán. Hết hạn mà chưa có tiền → nhả ghế. Đây là giữ **ghế**, không giữ **tiền**. Đủ cho cả hai rail.
- **Xác nhận bằng webhook**, không bằng người.
- **Chính sách hoàn theo thời hạn** do host công bố trước khi goer thanh toán (đã bắt buộc trong policy `:102`); mẫu gợi ý: hoàn 100% nếu hủy ≥ X ngày trước, 0% sau đó; host hủy sự kiện = hoàn 100% bắt buộc.
- Host chịu trách nhiệm hoàn tiền; banbe ra quyết định/điều phối.

Đánh đổi (nói rõ):
- (+) banbe không giữ tiền, giảm rủi ro money transmitter/trung gian thanh toán; bỏ SLA host 1h; bớt trạng thái kẹt `pending_verification`.
- (−) goer đã trả mà host biến mất: banbe không có tiền để hoàn. Chỉ còn biện pháp mục 4.5.
- (−) Mỹ: tiền về host ngay (theo lịch payout Stripe), không "treo" đến sau sự kiện. Muốn trì hoãn payout là thao tác banbe tác động vào dòng tiền → tăng rủi ro pháp lý, cần hỏi luật sư.
- (−) VN: không refund tự động; trải nghiệm hoàn tiền kém hơn Mỹ.

**Phương án phụ (nếu cần an toàn hơn mà vẫn không giữ tiền)**: giữ nguyên bước xác nhận thủ công của host cho host *mới/chưa xác minh*, và chỉ bật auto-confirm cho host đủ điều kiện (đã liên kết đối soát hoặc `charges_enabled`). Đây vẫn là giữ chỗ, không giữ tiền.

### 4.5 Tranh chấp khi banbe không giữ tiền
Quy trình giữ nguyên (notes/03, 04: chat tạm, admin quyết). Phần tiền đổi thành: **banbe ra quyết định, host hoàn tiền**.

| Tình huống | Hậu quả | Biện pháp | Giới hạn |
|---|---|---|---|
| Host không còn số dư | Mỹ: Stripe có thể ghi nợ ngân hàng host; nếu không đủ thì số dư âm. VN: host phải tự chuyển | Mỹ: nhờ Stripe bù; kiểm tra số dư trước khi hoàn | banbe không đảm bảo bồi hoàn; ghi rõ trong policy |
| Host không phản hồi | Lệnh hoàn quá hạn (`host_response_due_at` đã có) | Nhắc → leo thang admin → khóa tạo sự kiện mới, hạ điểm uy tín, tạm ngưng hồ sơ (admin đã có quyền, policy `:104,106`) | Không buộc được chuyển tiền |
| Host cố tình không hoàn | Goer mất tiền | Khóa/ngưng tài khoản, gỡ sự kiện, giữ bằng chứng (export PDF/ZIP đã có) để goer khiếu nại ngân hàng/cảnh sát/tòa; điều khoản host chấp nhận nghĩa vụ hoàn tiền + cho phép banbe công bố trạng thái vi phạm | Pháp lý nằm ngoài banbe; khóa tài khoản không đòi được tiền; host dùng tài khoản khác. Mỹ: goer có thể chargeback thẻ (host chịu) |
| Giới hạn rủi ro từ đầu | – | Hạn mức vé cho host mới, giá trần theo mức uy tín, xác minh host (Stripe KYC / liên kết đối soát) trước khi bán vé trả phí | Giảm chứ không loại bỏ rủi ro |

Tại rail Mỹ, **chargeback thẻ** là lưới an toàn mà rail VN không có.

### 4.6 iOS / Apple
- Vé sự kiện ngoài đời thuộc Guideline 3.1.3(e) (hàng hóa/dịch vụ dùng bên ngoài app, không dùng IAP) [Fact: Apple App Review Guidelines, bản UK PDF; văn bản hiện hành cần đọc lại trực tiếp tại developer.apple.com/app-store/review/guidelines]. 3.1.3(d) (person-to-person) **không** phù hợp vì sự kiện là một-với-nhiều.
- Stripe Checkout trên iOS: mở bằng `ASWebAuthenticationSession`/`SFSafariViewController`, quay lại bằng universal link (app đã có AASA). Apple Pay qua Stripe là phương thức hợp lệ cho 3.1.3(e) [Fact: kết quả tìm kiếm trích guideline].
- **Phí nền tảng của banbe**: nếu thu bằng % trên giao dịch vé (application fee) thì rủi ro thấp [Ước tính]. Rủi ro tăng nếu bán cho host "gói tính năng"/Host Pro trong app (nội dung số, có thể cần IAP; roadmap hiện có Host Pro, `docs/retention-monetization-roadmap.md`). Đánh giá riêng khi thiết kế Host Pro.
- Epic v. Apple (anti-steering Mỹ): trạng thái sau 2026-08-13 là [Chưa xác minh]; không ảnh hưởng vé thực tế theo 3.1.3(e) nhưng liên quan Host Pro. Kiểm tra lại docket trước khi phát hành.
- Ghi chú review: mô tả rõ vé dùng ngoài app. Guideline 1.2 (nội dung người dùng) liên quan chat/tranh chấp.
- App chưa lên App Store (build free Apple ID); mọi việc này sẽ thành hiện thực khi có tài khoản Developer trả phí.

---

## 5. Thay đổi DB (ĐỀ XUẤT, chưa áp dụng)

| Đối tượng | Đề xuất | Lý do |
|---|---|---|
| `events` | thêm `currency text` (`'USD'`/`'VND'`), `payment_rail text` (`stripe`/`vietqr`/`manual`/`free`), chốt lúc publish; dùng `price_cents` cho USD | Hiện toàn bộ cột tiền là VND; `price_cents` chưa dùng |
| `bookings` | thêm `currency`, `amount_minor bigint` (số tiền theo đơn vị nhỏ nhất), `payment_rail`, `provider_payment_id`, `provider_charge_id`; giữ `total_vnd` để tương thích | Đa tiền tệ |
| `organizer_payment_accounts` (mới) | `organizer_id`, `rail`, `country_code`, `stripe_account_id`, `charges_enabled`, `details_submitted`, `reconcile_provider` (`sepay`/`payos`/`casso`), `reconcile_status`, `reconcile_secret_ref`, `linked_at`, `last_event_at` | Hiện `organizers` không có country/provider/KYC. **Khóa API/secret của host phải mã hóa hoặc để ở secret store, không để rõ trong bảng** |
| `payment_webhook_events` | thêm `provider` giá trị `stripe`, cột `account_id`, `event_type`; giữ unique (provider, external_id) | Dùng lại bảng idempotency sẵn có; Stripe dùng `event.id` |
| `refund_claims` | thêm `rail`, `provider_refund_id`, `refund_application_fee boolean`, `amount_minor`, `currency`; trạng thái `provider_refunded` | Refund Stripe tự động |
| `platform_fee_ledger` (mới, chỉ khi bật phí) | `booking_id`, `fee_type`, `amount_minor`, `currency`, `collected_via` (`application_fee`/`invoice`), `status`, `refund_id` | Tách phí nền tảng khỏi doanh thu host; phục vụ kế toán |
| `host_trust` (mới, tùy chọn) | điểm uy tín, số tranh chấp, hạn mức vé, trạng thái khóa | Biện pháp thay escrow |
| `payment_unmatched_queue` hoặc cột trong `payment_webhook_events` | trạng thái `unmatched`/`underpaid`/`overpaid` + người xử lý | Ca đối soát VN không khớp |
| `.env.example` | thêm `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` (Connect), `CASSO_WEBHOOK_SECRET`, `PAYOS_CHECKSUM_KEY`, `BANK_WEBHOOK_SECRET` | Biến dùng trong code nhưng chưa khai báo |

Lưu ý: RPC `record_bank_transaction`, `hold_seats`, `verify_payment`, `claim_seats` hiện nhận/ghi VND; cần bản đa tiền tệ. Một số migration (134, 141, 142, 151, 153…) đang ghi là chưa apply (CLAUDE.md): kiểm tra trạng thái DB thật trước khi đặt số migration mới.

---

## 6. Kế hoạch triển khai và công sức

Công sức là [Ước tính] cho 1 dev quen codebase, chưa gồm thời gian chờ pháp lý/duyệt.

| Giai đoạn | Nội dung | Công sức |
|---|---|---|
| 0. Pháp lý + kế toán | Hỏi luật sư Mỹ/VN, kế toán (mục 8); chốt kịch bản phí | song song, 2–4 tuần lịch |
| 1. Củng cố rail VN hiện có | Khai báo env, sửa SLA/auto-confirm lệch notes, hàng đợi "chưa khớp", dedupe theo mã GD ngân hàng, UI host liên kết SePay/payOS + kiểm tra trạng thái liên kết, mã nội dung ngắn | 1,5–2,5 tuần |
| 2. Thử nghiệm SePay vs payOS | Đăng ký thử cả hai với TK thật, đo ngân hàng hỗ trợ, bảng giá, điều khoản chuyển tiếp dữ liệu, hỏi chương trình đối tác multi-host | 3–5 ngày |
| 3. Refund VN | Lệnh hoàn + VietQR sinh sẵn, theo dõi tiền ra, tự đóng lệnh | 1 tuần |
| 4. Stripe Connect (Mỹ) | Onboarding Standard/Account Link, Checkout direct charge, Connect webhook, refund API, đa tiền tệ trong schema/RPC, UI web | 3–4 tuần |
| 5. iOS | Checkout qua web session + universal link, hiển thị trạng thái, host onboarding Stripe | 1,5–2,5 tuần |
| 6. Chính sách + điều khoản host | Cập nhật `banbe_User_Policy.md` (hiện chỉ luật VN, A4/A8 cam kết không giữ tiền, cần điều khoản US, ủy quyền thu tiền, trách nhiệm hoàn tiền, ngưỡng tranh chấp) + màn consent | 3–5 ngày + thời gian luật sư |
| 7. Trust & hạn mức | Điểm uy tín, hạn mức host mới, khóa khi vi phạm | 1–1,5 tuần |
| 8. Kiểm thử | Sandbox Stripe (đặc biệt refund khi thiếu số dư), webhook trùng/muộn, e2e | 1–1,5 tuần |

Tổng [Ước tính]: ~10–15 tuần-dev cho cả hai rail + iOS; rail VN sớm có giá trị (giai đoạn 1–3, ~3–4 tuần).

---

## 7. Phí nền tảng: 3 kịch bản (không chốt con số)

Ai chịu phí xử lý: host ở cả hai rail. goer chỉ trả thêm nếu host/banbe chủ động cộng vào giá (cần công bố rõ trước khi trả).

| Kịch bản | Thu thế nào | Ghi nhận doanh thu [Ước tính, hỏi kế toán] | Rủi ro pháp lý |
|---|---|---|---|
| **(a) 0%** | Không thu | Không có doanh thu trên giao dịch vé; tiền host không phải doanh thu banbe | Thấp nhất. banbe không thu gì từ dòng tiền |
| **(b) Phí cố định nhỏ/vé** | Mỹ: `application_fee_amount` cố định. VN: không có split → hóa đơn gộp theo kỳ cho host, hoặc QR phí riêng (goer quét 2 lần, UX kém) | Net: chỉ khoản phí là doanh thu (banbe là agent). Phải xuất hóa đơn/chứng từ cho phí | Mỹ: thấp–trung bình (qua Stripe). VN: thu hóa đơn kỳ không đụng dòng tiền vé, nhưng rủi ro không thu được. Tránh để tiền vé đi qua tài khoản banbe rồi chia lại: đó là thu hộ/chi hộ (cần giấy phép) |
| **(c) 3–5%** | Mỹ: application fee theo %. VN: như (b) nhưng cộng dồn theo doanh thu host | Net. Tỷ lệ cao làm tăng dấu hiệu banbe "kiểm soát giá/giao dịch", dễ bị xem là principal nếu banbe định giá, cam kết hoàn tiền hoặc chịu trách nhiệm cung ứng; cần ý kiến kế toán (ASC 606) | Tăng nghĩa vụ: Mỹ có thể phát sinh marketplace facilitator/sales tax tùy bang; VN tăng khả năng phải đăng ký sàn TMĐT và nghĩa vụ thuế nền tảng |

Nhận xét:
- Ở VN nên bắt đầu (a) hoặc (b) theo kỳ; **không có cách thu % tự động an toàn** mà không để tiền đi qua banbe.
- Mỹ có sẵn cơ chế thu phí sạch (application fee); phí đó mới là doanh thu banbe, tiền vé không phải.
- Cam kết hiện tại trong policy (`:58`): sẽ báo trước nếu thu phí. Cần cập nhật khi chọn.

---

## 8. Pháp lý và kế toán (tổng quan, không phải tư vấn)

### 8.1 Mỹ
- **Money transmitter (liên bang)**: FinCEN, 31 CFR 1010.100(ff)(5)(ii)(B), ngoại lệ "payment processor" có 4 điều kiện (hỗ trợ mua hàng/dịch vụ, qua hệ thống bù trừ chỉ nhận tổ chức tài chính chịu BSA, có thỏa thuận chính thức, thỏa thuận tối thiểu với bên nhận tiền) [Fact tóm tắt từ nguồn thứ cấp, Mayer Brown/CA DFPI; chưa đọc văn bản gốc]. Hướng dẫn FIN-2019-G001 về tiền ảo, không phải riêng payment processor [Fact: fincen.gov].
- **Agent of the payee**: liên bang không có; có ở luật tiểu bang. California: DFPI 2018 từng nói một dịch vụ cụ thể không được miễn; quy định làm rõ 2020 đòi hợp đồng bằng văn bản với payee, được ủy quyền thu, goer trả cho nền tảng = đã trả cho payee [Fact: dfpi.ca.gov, 2018-11-14 và 2020-02-19]. NY, TX, FL: chưa tra [Ước tính: mỗi bang riêng, có Model Money Transmission Modernization Act].
- Cấu trúc thực tế: dùng Stripe làm bên giữ giấy phép; banbe chỉ thu application fee; **không** tự quyết hoặc trì hoãn dòng tiền. Admin quyết tranh chấp rồi **host** hoàn (không phải banbe chuyển) là cố ý nhằm giữ banbe ngoài chuỗi tiền.
- **1099-K**: ngưỡng $20.000 **và** >200 giao dịch cho 2026 (OBBBA, ký 2025-07-04) [Fact: cpapracticeadvisor.com 2025-07-30 và 2025-10-23; irs.gov newsroom]. Stripe phát hành 1099-K cho host khi host trả phí trực tiếp (Standard + direct) [Fact: docs.stripe.com/connect/tax-reporting]. Nếu banbe tự thu rồi trả host, banbe có thể thành TPSO và phải nộp 1099-K, thu W-9 [Ước tính]. Host vẫn phải khai thu nhập dù dưới ngưỡng.
- **Sales/admission tax**: mọi bang có sales tax đều có luật marketplace facilitator (từ 2023) [Fact: runsignup/ticketsignup/Eventbrite help]. Vé sự kiện chịu sales tax hay admission/amusement tax tùy bang/địa phương/loại sự kiện [Ước tính, chưa tra từng bang]. **Rủi ro**: banbe có thể bị coi là facilitator phải thu thuế ngay cả khi không giữ tiền. Cần luật sư thuế bang theo bang.
- **Doanh thu gross/net (ASC 606)**: agent (net) nếu chỉ kết nối, không kiểm soát vé/giá, không chịu rủi ro tồn kho; principal (gross) nếu tự định giá, tự cam kết hoàn tiền, chịu trách nhiệm cung ứng [Ước tính, ASC 606-10-55-36 đến 55-40]. Vai trò admin quyết tranh chấp là yếu tố cần cân nhắc.

### 8.2 Việt Nam
- **Trung gian thanh toán**: Nghị định 52/2024/NĐ-CP (hiệu lực 2024-07-01) thay 101/2012; gồm cổng thanh toán, hỗ trợ thu hộ chi hộ, ví điện tử; tổ chức không phải ngân hàng cần giấy phép NHNN, vốn tối thiểu 50 tỷ đồng cho các loại này [Fact tóm tắt từ thuvienphapluat.vn/luatvietnam.vn; chưa đọc điều khoản gốc, cần đối chiếu số điều/vốn]. Thông tư 40/2024/TT-NHNN sửa bởi 41/2025/TT-NHNN (eKYC sinh trắc học khi mở ví từ 2026-01-01) [Fact: sbv.gov.vn].
- Mô hình "hiển thị QR ngân hàng của host + webhook đối soát": theo cách đọc của người nghiên cứu, banbe không nhận/giữ/chuyển tiền nên **khó bị coi là trung gian thanh toán** [Ước tính; chưa có công văn NHNN xác nhận]. Rủi ro tăng nếu: (a) tiền qua tài khoản banbe rồi chuyển host; (b) dùng QR/tài khoản ảo tập trung thu hộ nhiều host; (c) banbe "xử lý và tính toán kết quả thu hộ". Escrow kiểu giữ tiền đến sau sự kiện chính là hoạt động cần giấy phép hoặc hợp tác đơn vị có phép.
- **Sàn TMĐT**: Nghị định 52/2013 (sửa 85/2021): sàn giao dịch TMĐT phải **đăng ký** với Bộ Công Thương; banbe cho nhiều host bán vé nên rất có thể là sàn [Ước tính]. Luật TMĐT 2025 (122/2025/QH15, hiệu lực 2026-07-01) và Nghị định 248/2026/NĐ-CP: chưa đọc, **không chắc 52/2013 còn hiệu lực đến đâu** [Chưa xác minh].
- **Thuế nền tảng**: Nghị định 117/2025/NĐ-CP (sàn/nền tảng **có chức năng thanh toán** khấu trừ, nộp thay GTGT/TNCN của cá nhân); một nguồn nói Nghị định 252/2026/NĐ-CP thay thế từ 2026-07-01 [Fact: thuvienphapluat.vn công văn; chưa đọc]. Nghĩa vụ gắn với "chức năng thanh toán": nếu banbe không thanh toán thì khả năng không phải khấu trừ, nhưng có thể vẫn phải cung cấp thông tin người bán cho cơ quan thuế [Ước tính].
- **Thuế host cá nhân/hộ kinh doanh**: Nghị định 68/2026/NĐ-CP (2026-03-05) bỏ thuế khoán, tự khai theo doanh thu thực; ≤500 triệu/năm không nộp GTGT/TNCN; 500 triệu–3 tỷ chọn % doanh thu hoặc lợi nhuận; từ 1 tỷ dùng hóa đơn điện tử; phải thông báo cơ quan thuế các tài khoản dùng kinh doanh (ngân hàng, ví) [Fact: diendandoanhnghiep.vn, luatminhkhue.vn, baolaocai.vn; nguồn báo/kế toán, cần đối chiếu văn bản gốc]. Hóa đơn điện tử: NĐ 123/2020, 70/2025 [Chưa xác minh nội dung].
- Nếu banbe là pháp nhân nước ngoài: đăng ký/đại diện tại VN, thuế nhà thầu [Ước tính].

### 8.3 Câu hỏi cho luật sư / Steuerberater-tương đương
**Mỹ, luật sư**: (1) banbe có là money transmitter ở liên bang và NY/CA/TX/FL khi dùng Stripe Connect Standard direct charge + application fee? (2) Quyết định tranh chấp của admin và việc banbe điều phối hoàn tiền có làm mất ngoại lệ không? (3) Điều khoản host cần gì để có quan hệ payee-agent hợp lệ? (4) Cần chương trình AML/sanctions riêng không?
**Mỹ, thuế/kế toán**: (5) banbe có là TPSO phải nộp 1099-K không? (6) Vé host cá nhân chịu sales/admission tax ở những bang nào, banbe có là marketplace facilitator không, ngưỡng nexus? (7) Gross hay net cho phí nền tảng? (8) Chargeback/phí dispute hạch toán thế nào?
**VN, luật sư**: (9) QR host + webhook đối soát có thuộc "hỗ trợ thu hộ, chi hộ" theo NĐ 52/2024 không, có công văn NHNN? (10) Giữ/hoàn tiền thay host cần giấy phép nào, hay hợp tác bên có phép? (11) banbe có phải đăng ký sàn TMĐT theo Luật TMĐT 2025/NĐ 248/2026? (12) Pháp nhân nước ngoài có nghĩa vụ gì? (13) Chat/nội dung người dùng có chịu NĐ 147/2024 không?
**VN, thuế/kế toán**: (14) NĐ 252/2026 có bắt banbe khấu trừ/cung cấp thông tin khi không có chức năng thanh toán? (15) Ngưỡng NĐ 68/2026 áp dụng thế nào cho thu nhập vé, ai xuất hóa đơn, hóa đơn cho phí nền tảng? (16) Thuế nhà thầu/GTGT trên phí nếu banbe là pháp nhân nước ngoài?
**Apple**: (17) Cách thu phí/Host Pro để không cần IAP, đặc biệt ở storefront VN? (18) Đọc lại 3.1.3(e) hiện hành và trạng thái Epic v. Apple.

---

## 9. Rủi ro và câu hỏi còn mở

Rủi ro:
- **Xác nhận bằng chuyển khoản VN không tuyệt đối**: không khớp/thiếu/thừa/trùng; vẫn cần đường dự phòng xác nhận tay và hàng đợi xử lý.
- **Onboarding host VN**: mỗi host tự đăng ký SePay/payOS + liên kết ngân hàng (OTP chính chủ). Ma sát cao; chưa rõ có API partner onboarding hộ. Một số ngân hàng chỉ hỗ trợ cá nhân ở chế độ hạn chế [Ước tính].
- **Phụ thuộc bên thứ ba**: gói/phí theo ngân hàng của payOS/SePay có thể đổi; host ngừng gói = mất xác nhận tự động. Điều khoản về chuyển tiếp dữ liệu giao dịch cho bên thứ ba chưa đọc được.
- **Host xấu**: không escrow nên banbe không đòi được tiền; chỉ biện pháp mục 4.5.
- **Refund Stripe khi host thiếu số dư**: chưa xác minh hành vi; test sandbox.
- **UX Stripe Standard**: host phải có tài khoản Stripe (Dashboard riêng), ma sát với host nhóm bạn/CLB nhỏ; host Mỹ không có SSN/ITIN không onboard được [Ước tính].
- **Dữ liệu cũ**: `events.country_code` nullable, lệch HCMC `state_province` iOS vs web (notes/20) có thể làm route sai rail.
- **Policy lệch**: chỉ luật/tòa VN, cam kết "không giữ tiền", không có điều khoản Mỹ.
- **Dữ liệu thanh toán nhạy cảm**: `payment_webhook_events.raw` chưa có thời hạn xóa (policy `:157,204,244`); khóa API host cần bảo vệ.
- **Luật VN thay đổi nhanh** (NĐ 252/2026, 248/2026, Luật TMĐT 2025): kết luận có thể lỗi thời.

Câu hỏi còn mở:
- Có bao nhiêu host/sự kiện thực tế ở Mỹ? (Hiện code và policy đều VN-first; US mới ở mức bộ lọc vị trí/ngân sách.)
- SePay/payOS/Casso có chương trình marketplace/đối tác onboard nhiều host không?
- Stripe: giá US chính thức, danh sách thông tin KYC bắt buộc cho cá nhân Mỹ (`docs.stripe.com/connect/required-verification-information`), hành vi refund khi thiếu số dư.
- payOS "Chi hộ" dùng được với tài khoản cá nhân không (có thể mở đường refund tự động VN, nhưng sẽ khiến luồng tiền ra đi qua bên thứ ba và cần xem lại pháp lý)?
- Host Pro và các tính năng trả phí trong iOS có cần IAP không?

---

## 10. Quyết định cần bạn chọn

1. **Phạm vi giai đoạn đầu**: (i) chỉ củng cố VN (giai đoạn 1–3, nhanh nhất, ~3–4 tuần) rồi mới làm Mỹ; hoặc (ii) làm song song cả hai rail. *Khuyến nghị: (i)*, trừ khi đã có host Mỹ thật.
2. **Rail VN: SePay hay payOS làm mặc định** (hoặc hỗ trợ cả hai qua webhook generic sẵn có). Nên quyết sau thử nghiệm 3–5 ngày ở giai đoạn 2.
3. **Phí nền tảng**: (a) 0%, (b) cố định nhỏ/vé, (c) 3–5%. *Khuyến nghị tạm: (a) cho VN, (b) hoặc (a) cho Mỹ* cho đến khi luật sư/kế toán trả lời.
4. **Escrow**: bỏ hoàn toàn (chỉ giữ chỗ 10–15 phút + hoàn theo thời hạn + host hoàn), hay giữ bước host xác nhận cho host mới/chưa xác minh như phương án phụ. *Khuyến nghị: bỏ, kèm hạn mức vé cho host mới.*
5. **Host Mỹ không có SSN/ITIN hoặc không muốn tạo tài khoản Stripe**: không hỗ trợ bán vé trả phí (chỉ miễn phí) hay cho phép fallback "handle + xác nhận tay" (vi phạm ToS Venmo/Cash App cá nhân, không có refund API). *Khuyến nghị: chỉ miễn phí hoặc chặn bán vé trả phí cho đến khi có Stripe.*

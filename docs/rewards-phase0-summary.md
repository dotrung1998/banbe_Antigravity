# Rewards Phase 0 — summary (IN PROGRESS: sections are added as steps finish)

## Điểm cần luật sư xem (đã biết đến bước 2)

- **`shared_phone` và việc admin xem liên kết giữa các tài khoản.** Tín hiệu `shared_phone` (migration 178) so sánh số điện thoại **đã xác minh** (`auth.users.phone`) của các tài khoản được cùng một host điểm danh, và `reward_risk_flags.metrics` lưu danh sách `user_ids` liên quan để admin xem. Nghĩa là admin nhìn thấy liên kết giữa các tài khoản (cùng số điện thoại; cụm tài khoản mới quanh một host). Cần luật sư xác nhận cơ sở "chống gian lận / an toàn" trong `banbe_User_Policy.md` dòng 178 đủ bao phủ việc này (mục đích, thời hạn lưu cờ, quyền của người bị gắn cờ được biết/phản đối, không ra quyết định tự động: cờ chỉ để admin xem, không tự thu hồi coin hay chặn host). Policy hiện **không** nêu rõ việc đối chiếu số điện thoại giữa các tài khoản.
- Tín hiệu còn lại (`repeat_guests`, `new_accounts`, `off_window`) dùng dữ liệu điểm danh và tuổi tài khoản đã có; cùng câu hỏi về mục đích và thời hạn lưu.
- Ngưỡng chưa hiệu chỉnh (production có 0 check-in tại 2026-10-10): bật flag là một quyết định riêng, sau khi đã chạy `admin_reward_risk_preview()` trên dữ liệu thật.

## Quyết định còn mở

- **RPC bật/tắt cờ `partner_offers`** (và các cờ `reward_feature_flags` khác): chưa có. Hiện chỉ đổi cờ bằng SQL trên DB. Cần quyết định: RPC admin riêng (kiểu `admin_set_reward_risk_config`), hay chỉ qua migration/SQL có kiểm soát; ai được bật; có cần nhật ký thay đổi và điều kiện (policy đã cập nhật, luật sư duyệt) trước khi cho bật không. Ngay cả khi cờ bật, 179 vẫn không cho đổi ưu đãi (`NOT_AVAILABLE`): đường đổi ưu đãi là việc của Giai đoạn 1.

- **`sponsor_staff` (bảng thứ 6 ngoài mục 5.2 của nghiên cứu)** trong bản nháp Bước 4: cần để cấp quyền cho RPC "xác nhận một mã" của đối tác. Giữ, hay đối tác xác nhận qua cơ chế khác (admin nhập hộ, mã QR do banbe ký)?
- **Điều kiện kích hoạt bản nháp sponsors/offers/redemptions**: luật sư duyệt; có đối tác thật với thoả thuận bằng văn bản; giới hạn thử mã (chống đoán mã) và RPC phát hành (giới hạn mỗi người, khoá tồn kho, sinh mã) — chưa có; công cụ admin tạo/vô hiệu. Cờ `partner_confirm` và `partner_offers` giữ TẮT.

## Rủi ro quyền riêng tư: bộ đếm hoạt động ưu đãi (migration 180, cờ `reward_events` TẮT)

**Cần cập nhật policy và luật sư xem TRƯỚC KHI bật cờ**, dù dữ liệu không định danh. `banbe_User_Policy.md` hiện nói "không dùng dữ liệu cho quảng cáo của banbe" (dòng 182) và không mô tả việc đo lượt xem ưu đãi; việc đo này phải được mô tả (mục đích: báo cáo tổng hợp cho admin/đối tác, không phải hồ sơ cá nhân).

**Vì sao bộ đếm tổng hợp thay vì log từng sự kiện**
- Một dòng cho mỗi (ưu đãi, ngày UTC, vùng thô, loại sự kiện) chỉ chứa một con số. Không có dòng nào ứng với một lượt xem cụ thể, nên không có gì để nối ngược về một người, và không có thời điểm chính xác (chỉ ngày; không có `created_at`/`updated_at`).
- Log từng sự kiện, dù bỏ `user_id`, vẫn có thể bị tái định danh bằng đối chiếu (thời điểm + ưu đãi + vùng) và dễ bị "thêm cột sau". Bảng bộ đếm không thể biến thành log mà không đổi schema một cách lộ liễu. Test 18 kiểm schema: đúng 5 cột, không cột uuid/IP/json/timestamp, không tên cột định danh, không trigger, không khoá ngoại tới `profiles`.
- Có giới hạn đã biết: không loại trùng được (một người bấm nhiều lần thì cộng nhiều lần; đếm SỰ KIỆN, không phải NGƯỜI; giảm nhẹ bằng việc client chỉ gửi một lần mỗi ưu đãi mỗi phiên, chưa xây). Ai có tài khoản đều có thể thổi phồng `offer_viewed`: số liệu chỉ để tham khảo, không dùng làm bằng chứng thanh toán. `offer_issued`/`offer_redeemed` client KHÔNG tự báo được (chỉ hàm phía máy chủ tăng, sau này gọi từ RPC phát hành/xác nhận). Chênh lệch giữa các báo cáo chồng cửa sổ có thể lộ delta nhỏ; ngưỡng nhóm tối thiểu (mặc định 20, sàn 5, nằm ở `reward_event_config`) giảm chứ không loại bỏ, kiểm soát chính là báo cáo chỉ dành cho admin.
- **Giới hạn của tuyên bố "không định danh"**: chỉ đúng với các đối tượng trong cơ sở dữ liệu của mình. Nhật ký API của nền tảng Supabase (thời điểm, đường dẫn, JWT subject của yêu cầu) nằm ngoài schema và do cài đặt nền tảng quyết định thời hạn lưu; policy phải nói rõ điều này.
- Vùng: `VN`/`US`/`OTHER`/`UNKNOWN` (cấp quốc gia, chủ ý không mịn hơn để tránh ô nhỏ định danh); client tự khai, giá trị ngoài danh sách bị lưu thành `UNKNOWN`.
- `offer_id` hiện là mã của dòng `reward_catalog` kiểu `partner_offer` (bảng `reward_offers` mới chỉ là bản nháp). Khi bản nháp được đưa vào chuỗi, cần quyết định có đổi khoá hay không.


# Rewards Phase 0 — summary (IN PROGRESS: sections are added as steps finish)

## Điểm cần luật sư xem (đã biết đến bước 2)

- **`shared_phone` và việc admin xem liên kết giữa các tài khoản.** Tín hiệu `shared_phone` (migration 178) so sánh số điện thoại **đã xác minh** (`auth.users.phone`) của các tài khoản được cùng một host điểm danh, và `reward_risk_flags.metrics` lưu danh sách `user_ids` liên quan để admin xem. Nghĩa là admin nhìn thấy liên kết giữa các tài khoản (cùng số điện thoại; cụm tài khoản mới quanh một host). Cần luật sư xác nhận cơ sở "chống gian lận / an toàn" trong `banbe_User_Policy.md` dòng 178 đủ bao phủ việc này (mục đích, thời hạn lưu cờ, quyền của người bị gắn cờ được biết/phản đối, không ra quyết định tự động: cờ chỉ để admin xem, không tự thu hồi coin hay chặn host). Policy hiện **không** nêu rõ việc đối chiếu số điện thoại giữa các tài khoản.
- Tín hiệu còn lại (`repeat_guests`, `new_accounts`, `off_window`) dùng dữ liệu điểm danh và tuổi tài khoản đã có; cùng câu hỏi về mục đích và thời hạn lưu.
- Ngưỡng chưa hiệu chỉnh (production có 0 check-in tại 2026-10-10): bật flag là một quyết định riêng, sau khi đã chạy `admin_reward_risk_preview()` trên dữ liệu thật.

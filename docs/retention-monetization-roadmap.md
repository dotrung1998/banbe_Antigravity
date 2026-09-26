# Banbe: giữ chân người dùng và doanh thu khi tạo sự kiện miễn phí

Trạng thái: kế hoạch sản phẩm, chưa triển khai tính năng. Cơ sở: code main ở commit 67195e9 (2026-09-25). Mọi số liệu mục tiêu/giá thử nghiệm bên dưới là giả thuyết, không phải kết quả đo.

## Nguyên tắc
- Miễn phí tạo/đăng sự kiện và sự kiện miễn phí. Không tự giữ/thu/chuyển tiền thay host trong giai đoạn này.
- Ưu tiên event thật, ngày/chỗ/ảnh thật; không lấy catalogue demo làm nguồn sự thật. Không bán thứ hạng hữu cơ của Pulse. Vị trí trả phí phải ghi rõ 'Được tài trợ'.
- Mục tiêu là người dùng quay lại để lên kế hoạch, tham dự và theo dõi cộng đồng; không ép mở app mỗi ngày. Thông báo có lựa chọn và có thể tắt.

## P0 — Làm dữ liệu lưu thành dữ liệu thật
- Hiện tại s.favorites/toggleFav trên web và toggleFavorite trên iOS chỉ là state local, trong khi public.favorites đã tồn tại. Kết nối cả hai nền tảng với Supabase, RLS owner-only, tải theo user, optimistic rollback, dọn cache khi logout/chuyển user. Không ghi nhầm lượt lưu ảnh thành lượt lưu event.
- Dùng đúng dữ liệu lưu thật cho filter Đã lưu, danh sách Account và tín hiệu save của goc_pulse_ranked(); kiểm tra đồng bộ giữa hai thiết bị và không có flash sai trạng thái.
- Ưu tiên sửa các khoảng trống dữ liệu sự kiện/ảnh thật và quyền truy cập ended events đã được xử lý ở migration 084 trước khi quảng bá feed.

## P1 — Khám phá cuối tuần và quay lại
- Một danh sách Cuối tuần này theo múi giờ Asia/Ho_Chi_Minh: live/public, starts_at trong tuần/cuối tuần sắp tới, còn chỗ nếu có capacity; loại ended/cancelled/draft/invite khỏi danh sách công khai. Dùng event và ảnh thật, không copy catalogue; hiển thị trạng thái rõ khi không có sự kiện.
- Cho người dùng lọc theo khu vực/chủ đề/giá và lưu sự kiện; ưu tiên host đang theo dõi nhưng không ẩn sự kiện từ host mới. Mỗi card dẫn tới EventDetail. Không tạo ranking giả hay gợi ý dựa trên dữ liệu chưa có.
- Gửi một bản tổng hợp tự nguyện tối đa mỗi tuần, chỉ cho người đã opt-in; ưu tiên notification trong app trước, vì PersonalTeamDebug không có APNs. Deep link tới danh sách hoặc event; không lặp notification cho cùng event.

## P2 — Vòng lặp cộng đồng
- Từ event detail: share link có event id thật, ngày/giá chính xác; không tiết lộ danh sách goer nếu họ chưa đồng ý. Ghi nhận share hoàn tất, không tính việc chỉ mở share sheet.
- Sau sự kiện: hiển thị ảnh thật từ event_photos kể cả khi event ended cho người có quyền xem; kêu gọi theo dõi host và xem buổi kế tiếp. Không dùng lượt tim ảnh như tín hiệu duy nhất của chất lượng event.

## Thử doanh thu, chưa bật thu tiền
1. Host Pro tự nguyện: export khách, mẫu nhắc việc, quyền cộng tác check-in, báo cáo khách quay lại. Tạo sự kiện và công cụ cốt lõi vẫn miễn phí. Phỏng vấn host lặp lại trước khi chốt giá.
2. Vị trí tài trợ rõ nhãn, có ngân sách/cửa sổ thời gian và báo cáo impression -> event open -> booking. Không chen vào Pulse hữu cơ; không hứa lượt đặt. Chỉ thử sau khi có traffic thật và thống kê đáng tin.
3. Phí theo vé trả tiền chỉ nghiên cứu khi có cơ chế đối soát và đối tác thanh toán phù hợp; mô hình host nhận chuyển khoản trực tiếp hiện tại không đủ chắc để tự động thu phí theo doanh số. Rà soát pháp lý VN trước khi đổi vai trò thanh toán.

## Chỉ số và điều kiện dừng
- Ghi nhận ẩn danh hoặc có đồng ý phù hợp: impression -> open -> save -> booking confirmed -> attended -> repeat attendance, theo nguồn/campaign; không log tài khoản ngân hàng hoặc nội dung chat.
- Cohort 7/30 ngày, người tham dự lần 2 trong 60–90 ngày, host tạo event thứ 2, tỷ lệ tắt thông báo, refund/dispute quá hạn; phân tách dữ liệu test với người dùng thật.
- Nếu tuần đó không có event phù hợp, không gửi bản tin rỗng. Nếu sponsored làm giảm tương tác hữu cơ hoặc tăng báo cáo spam, dừng thử nghiệm.

## Triển khai
P0 trước P1, P1 trước thông báo, P2 sau khi event/photo data ổn định; Host Pro thử bằng phỏng vấn/phần mềm quản trị trước khi xây thanh toán trong app. Mọi migration dùng forward migration, không chỉnh dữ liệu test/production bằng tay. Kiểm thử iOS PersonalTeamDebug và web; thiết bị do chủ dự án tự test.

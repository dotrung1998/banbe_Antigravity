# Prototype audit — chọn 3 màn ưu tiên (2026-11-21)

Chưa sửa app. Tiêu chí lấy từ `docs/prompts/daily-hermes.md` §D: mỗi màn chấm **0–2** ở bốn tiêu chí, lấy tổng; hòa thì đường tiền trước, rồi effort nhỏ hơn. Mỗi màn một prototype canonical.

## Kết quả

| Màn | Prototype canonical | Tiền/niềm tin | Lệch | Điểm vào | Rủi ro TM | Tổng | Kết quả |
|---|---|---:|---:|---:|---:|---:|---|
| Event Detail | `docs/prototypes/homescreen-event-detail-motion-v2-4.html` | 2 | 1 | 2 | 2 | **7** | **Chọn** |
| Confirmed / Vé | `docs/prototypes/banbe_ticket_A_whatsnext_v2.html` | 2 | 1 | 2 | 2 | **7** | **Chọn** |
| Home | `docs/prototypes/banbe-home-v3.2-standalone.html` | 1 | 2 | 2 | 2 | **7** | **Chọn** |
| Map | `docs/prototypes/map-options-v5.html` | 1 | 1 | 2 | 2 | 6 | Backlog |
| Payment / Refund | `docs/prototypes/payment-refund-v2-pay-now-refunds.html` | 2 | 1 | 1 | 1 | 5 | Backlog |
| Account / Activity | `docs/prototypes/home-account-activity-v3.2.html` | 1 | 1 | 1 | 2 | 5 | Backlog |
| Schedule | `docs/prototypes/schedule-stages_v5.html` | 0 | 1 | 1 | 2 | 4 | Backlog |
| Onboarding | `docs/prototypes/banbe-onboarding-v5-standalone.html` | 0 | 1 | 1 | 1 | 3 | Backlog |

Ba màn đầu đều 7 điểm, không cần hòa; có hai màn trên đường tiền (Event Detail, Confirmed), đạt điều kiện “ít nhất một màn đường tiền”. Payment/Refund và Account cùng 5 điểm, xếp Refund trước vì đường tiền.

## Vì sao 3 màn này

- **Event Detail — 7.** Cửa ngõ trước khi giữ chỗ; prototype v2.4 là bản canonical, app đã theo v2.3 nhưng vẫn một cột hẹp và chưa có bố cục 768/1280. Lệch 1 vì phần chức năng đã có, thiếu là bố cục thương mại.
- **Confirmed / Vé — 7.** Niềm tin sau thanh toán; vé và QR là thứ khách mang đi. App đã theo ticket A nhưng vẫn bó trong khung điện thoại, chưa có layout 768/1280.
- **Home — 7.** Cửa ngõ discovery, tần suất cao nhất. App đã đổi sau prototype (note 93–100), bản v2.3 còn sau switch `home_v23`, nên prototype v3.2 lệch rõ; 768/1280 vẫn là một cột.

## Backlog (theo thứ tự mở lại)

1. **Map — 6.** Discovery quan trọng nhưng Map E+ (note 79) mới hơn `map-options-v5`; xác nhận lại canonical trước khi audit. Không nằm trên đường tiền.
2. **Payment / Refund — 5.** Đường tiền nhưng tần suất thấp; lifecycle đã có (note 16), chủ yếu là form/sheet nên rủi ro layout thấp hơn 3 màn đầu.
3. **Account / Activity — 5.** Điểm vào thường xuyên nhưng không tiền; tabs/rows đã đổi (note 69), audit sau Home.
4. **Schedule — 4.** Không tiền, tần suất vừa; app đã có Schedule (note 44/49), prototype v5 cần đối chiếu lại.
5. **Onboarding — 3.** Chỉ chạy lần đầu; v5 đã áp dụng (note 80), ưu tiên thấp nhất.

## Phạm vi bước tiếp theo

- Audit đúng 3 màn trên: một prototype canonical mỗi màn, gap list + ảnh before/after trong ngân sách 12 ảnh.
- Không mở thêm màn, không sửa app trong bước audit; kết quả thành gap list cho APPLY.
- Mở lại backlog sau khi 3 màn xong, bắt đầu từ Map.

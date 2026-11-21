# Prototype priority — bộ 4 hiện tại (2026-11-21)

Bộ đang dùng chỉ còn **4 prototype**: Home v3.2, Event Detail v2.4, Ticket A v2, Onboarding v5. Các bản Map/Payment/Account/Schedule và các vòng cũ đã xoá khỏi máy; điểm cũ không còn hiệu lực. Chưa sửa app.

Tiêu chí lấy từ `docs/prompts/daily-hermes.md` §D: mỗi màn chấm **0–2** ở bốn tiêu chí, lấy tổng; hòa thì đường tiền trước, rồi effort nhỏ hơn. Mỗi màn một prototype canonical.

## Kết quả

| Màn | Prototype canonical | Tiền/niềm tin | Lệch | Điểm vào | Rủi ro TM | Tổng | Kết quả |
|---|---|---:|---:|---:|---:|---:|---|
| Event Detail | `docs/prototypes/homescreen-event-detail-motion-v2-4.html` | 2 | 1 | 2 | 2 | **7** | **Chọn** |
| Confirmed / Vé | `docs/prototypes/banbe_ticket_A_whatsnext_v2.html` | 2 | 1 | 2 | 2 | **7** | **Chọn** |
| Home | `docs/prototypes/banbe-home-v3.2-standalone.html` | 1 | 2 | 2 | 2 | **7** | **Chọn** |
| Onboarding | `docs/prototypes/banbe-onboarding-v5-standalone.html` | 0 | 1 | 1 | 1 | 3 | Backlog |

Ba màn đầu đều 7 điểm; có hai màn trên đường tiền (Event Detail, Confirmed), đạt điều kiện “ít nhất một màn đường tiền”.

## Vì sao 3 màn này

- **Event Detail — 7.** Cửa ngõ trước khi giữ chỗ; prototype v2.4 có hướng 768/1280 (body 640, 2 cột ở 1280) nhưng app vẫn 393. Lệch 1 vì phần chức năng đã có; thiếu là bố cục thương mại.
- **Confirmed / Vé — 7.** Niềm tin sau thanh toán; vé và QR là thứ khách mang đi. App đã theo ticket A nhưng vẫn bó trong khung điện thoại, chưa có layout 768/1280.
- **Home — 7.** Cửa ngõ discovery, tần suất cao nhất. App đã đổi sau prototype (note 93–100); prototype v3.2 chỉ là phone 390, nên lệch rõ và **không có thiết kế desktop** để áp dụng.

## Backlog

- **Onboarding — 3.** Chỉ chạy lần đầu; v5 đã áp dụng (note 80), ưu tiên thấp nhất.
- Không còn prototype cho Map, Payment/Refund, Account, Schedule. Muốn audit các màn đó thì phải thiết kế/cập nhật prototype trước.

## Audit 2026-11-21

- Đã audit 3 màn đã chọn; **chưa sửa app**. Report local: `docs/audits/2026-11-21/PROTOTYPE-AUDIT.md` (gitignored).
- Kết luận: app vẫn 393px ở 768/1280; **Event** có prototype 2 cột nhưng chưa áp dụng; **Home/Ticket** không có desktop prototype, cần thiết kế trước khi apply.
- 3 gap P1 (một cho mỗi màn) + 2 P2 (Home prototype lệch app; Ticket prototype 425 khác 393). Ảnh: 12 trong `docs/audits/2026-11-21/shots/`.

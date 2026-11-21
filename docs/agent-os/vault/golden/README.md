# Golden set — năm màn chuẩn

Ảnh tham chiếu để một lần audit trả lời được "màn này trông thế nào khi đúng", thay vì mỗi lần chấm theo cảm giác.

## Năm màn

| # | Màn | Route | Dữ liệu cần | Ảnh |
|---|---|---|---|---|
| 1 | Home | `/` | feed công khai, không cần đăng nhập | `home-390-light.png`, `home-1440-light.png` |
| 2 | Event Detail | `/event/<key>` | một event công khai còn vé | `event-390-light.png`, `event-1440-light.png` |
| 3 | Giữ chỗ | `/event/<key>/reserve` | mở từ Event Detail, có draft | `reserve-390-light.png`, `reserve-1440-light.png` |
| 4 | Vé | `/ticket` | một booking vừa xác nhận | `ticket-390-light.png`, `ticket-1440-light.png` |
| 5 | Tài khoản | `/profile` | đã đăng nhập | `account-390-light.png`, `account-1440-light.png` |

Mười ảnh, **chỉ light**. Dark mode kiểm trực tiếp trong lúc chấm, không cần ảnh tham chiếu.

## Chụp

```bash
npm run dev   # ghi lại PID, chờ HTTP 200
npx playwright screenshot --viewport-size="390,844" --wait-for-timeout=1500 \
  http://localhost:5173/ docs/agent-os/vault/golden/shots/home-390-light.png
```

Thiếu browser thì `npx playwright install chromium` (cache ngoài repo). Vẫn không chạy được thì ghi `golden: blocked — <lý do>`, **không** lấy ảnh cũ thay ảnh mới.

## Luật dùng ảnh

- Ảnh trong `shots/` là **chuẩn**, không phải ảnh đẹp nhất từng chụp. Chỉ thay khi sản phẩm cố ý đổi.
- Mỗi lần chạy chụp lại cùng route/size rồi so cạnh nhau; lệch ngoài ý muốn là một phát hiện P1/P2.
- Ảnh của lần chạy nằm ở `docs/audits/<ngày>/`, không ghi đè golden.
- Tối đa 10 ảnh golden; thêm màn thứ sáu thì bỏ một màn.

## Trạng thái

`shots/` **chưa có ảnh** — lần chạy đầu tiên trên máy có dữ liệu thật chụp đủ 10 ảnh và commit. Cho tới lúc đó, báo cáo ghi `golden: not captured`, không được coi là đã có chuẩn.

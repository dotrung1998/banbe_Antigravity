# Golden set — năm màn chuẩn

Ảnh tham chiếu để một lần audit trả lời được "màn này trông thế nào khi đúng", thay vì mỗi lần chấm theo cảm giác.

## Vì sao không chụp thẳng URL

Ba trong năm màn **không mở được bằng một URL trần**. `src/lib/routes.js` nói rõ:

| Màn | URL | Cold load thực tế |
|---|---|---|
| Event | `/event/<key>` | đúng màn |
| Giữ chỗ | `/event/<key>/reserve` | cần `attendeeDrafts` trong state, không có thì rơi về Event |
| Vé | `/ticket` | `confirmed` luôn có `parent: '/'`, nên mở link lạnh là về Home |
| Tài khoản | `/profile` | cần session; khách bị đưa về Welcome/Login |

Vì vậy ảnh golden của Reserve, Vé và Account được dựng bằng **state fixture trong dev server**, không phải bằng cách mở URL. Script dùng `window.__banbeDevSet` — setter chỉ tồn tại khi `import.meta.env.DEV` — rồi **assert `data-screen-label`** trước khi ghi ảnh.

Script **không đăng nhập** và **không ghi DB**. Nó cũng **không chặn mạng**: dev app vẫn đọc Supabase production như mọi lần `npm run dev` (feed, event, ảnh), chỉ có state của ba màn kia là fixture cục bộ.

Hệ quả: Home và Event có thể đổi số vé, số event hay thứ tự carousel giữa hai lần chụp dù layout y nguyên. Khi so, **bỏ qua khác biệt dữ liệu**; chỉ báo lệch khi bố cục, typography, màu hoặc trạng thái UI đổi.

## Chạy

```bash
npm run dev                                   # shell 1
npx playwright install chromium               # lần đầu
node scripts/golden-shots.mjs                 # shell 2 — chỉ khi UI cố ý đổi, ghi đè bộ chuẩn
node scripts/golden-shots.mjs --out docs/audits/2026-11-21/golden   # audit: chụp ra chỗ khác, golden không đổi
node scripts/golden-shots.mjs --only ticket   # một màn, cả hai width
```

- Ghi **10 ảnh** vào `shots/`: 5 màn × 390 và 1440, light.
- Sai màn → script exit 1 và **không** ghi ảnh sai.
- Máy Linux tối giản thiếu thư viện hệ thống: `npx playwright install-deps chromium` (cần root). Không cài được thì ghi `golden: blocked — <lỗi>`; **không** chụp URL trần thay cho màn state.

## Năm màn

| # | key | Màn | Fixture |
|---|---|---|---|
| 1 | `home` | Home | khách, feed thật từ catalogue |
| 2 | `event` | Event Detail | event `bepnho`, bắt đầu 26/11 19:00 ICT |
| 3 | `reserve` | Giữ chỗ | 1 vé, người nhận "Linh", DOB 12/04/1995 |
| 4 | `ticket` | Vé | booking `confirmed`, mã `1B159C`, user "Trung" |
| 5 | `account` | Tài khoản | user "Trung", goer |

Ảnh: `home-390-light.png`, `home-1440-light.png`, … (10 file).

## Luật dùng ảnh

- Ảnh trong `shots/` là **chuẩn đã commit**. Chỉ thay khi UI cố ý đổi, và thay trong cùng commit với thay đổi đó.
- Mỗi lần audit chạy `--out docs/audits/<ngày>/golden` rồi so cạnh; **không** ghi đè `shots/`. Lệch ngoài ý muốn là P1/P2.
- Ảnh của lần audit nằm ở `docs/audits/<ngày>/shots/`, **không** ghi đè golden.
- Fixture không phải dữ liệu production, dù trang vẫn đọc dữ liệu production: golden kiểm **layout**, không kiểm logic booking, giá hay RLS. Hành vi vẫn cần một lượt tài khoản thật.
- Mọi ảnh chỉ được ghi sau khi **Be Vietnam Pro** tải đủ 300–800 + italic; thiếu một weight là script exit 1, không bao giờ commit ảnh bằng font fallback.
- Tối đa 10 ảnh; thêm màn thứ sáu thì bỏ một màn.

## Trạng thái

10 ảnh đã có trong `shots/` (chụp lần đầu 2026-11-21 bằng `scripts/golden-shots.mjs`). Lần chạy nào cũng phải so với bộ này trước khi kết luận "không đổi".

# shared/ — vỏ dùng chung cho mọi cụm prototype

Mỗi cụm **copy** thư mục `template/` rồi thay phần màn hình. Không dựng lại stage, rail 4 khung,
nút Làm lại hay script chụp — đó là việc của bốn file trong thư mục này.

| File | Việc |
| --- | --- |
| `stage.css` | khung ngoài: thanh trên, rail 390/834/1194/1440, "Cả 4", nút Làm lại, chế độ `?embed=1` |
| `stage.js` | điều khiển: đổi khung, scale vừa cửa sổ, deep link `#bN`, reset, overview, fallback "app thật" |
| `template/` | một cụm mẫu 3 bước, đã nối đúng hợp đồng — copy nguyên thư mục |
| `capture-stage.mjs` | chụp cụm ở 4 khung + 1 ảnh overview, ghi `capture.md` |

## Copy một cụm

```bash
mkdir -p docs/prototypes/day-01-baseline/onboarding
cp -R docs/prototypes/shared/template/. docs/prototypes/day-01-baseline/onboarding/
```

Cụm đã có bản cũ: đổi tên `index.html` thành `index.before.html` trước khi copy, để giữ bản cũ mà so.
Ngày N > 1: copy nguyên thư mục cụm của ngày N-1 sang ngày N rồi sửa tiếp, đừng dựng lại từ template.
Sau khi copy, sửa trong `index.html`:

1. `data-cluster="template"` → `data-cluster="onboarding"` (đúng id trong `missions/plan.json`).
2. `data-steps="3"` → số bước thật.
3. `bb-crumb` → `Ngày 1/8 · Cụm 1/5`.
4. Năm link trong `.bb-clusters` đã trỏ đúng `../<cụm>/index.html`; giữ `data-app` để link chưa có
   tự rơi về app thật.
5. Thay các `<section data-step>` và `screen.css`/`screen.js` bằng màn thật.

## Hợp đồng với `screen.js`

```js
window.bbScreen = {
  steps: 5,                 // hoặc data-steps trong HTML
  render(step) { ... },     // bắt buộc
  reset() { ... }           // tuỳ chọn; stage tự xoá sessionStorage `bb:<cluster>:*` rồi render(1)
};
```

- Đổi bước bằng `window.BBStage.go(n)`; stage cập nhật `#bN` và gọi `render(n)`.
- Nút Làm lại gọi `reset()` rồi `render(1)`, xoá mọi key `sessionStorage` bắt đầu bằng
  `bb:<cluster>:`; đừng giữ lựa chọn trong biến toàn cục mà không reset.
- Mở thẳng `#b3` hoặc `?step=3` phải ra đúng bước.
- `?embed=1` ẩn thanh stage và cho màn hình đúng 100% khung — dùng cho iframe "Cả 4" và cho
  `capture-stage.mjs`; đừng dựa vào thanh stage trong chế độ này.

## Ba cái bẫy

1. **Container queries, không media query theo viewport.** `.bb-device` là container
   (`container-type: inline-size`). Trong `screen.css` dùng `@container screen (min-width: 834px)`;
   `@media (min-width: 834px)` sẽ đọc cửa sổ trình duyệt, không đọc khung đang xem.
2. **Không `position: fixed`.** Khung được scale bằng transform; `fixed` sẽ bám vào cửa sổ, không bám
   vào màn. Dùng `position: absolute` bên trong `.bb-screen`. Chiều cao dùng `100%`, không `100vh`.
3. **Ảnh và font phải tải xong trước khi chụp.** Script đã chờ `document.fonts.ready` và mọi `<img>`;
   nếu ảnh là background-image, thêm `loading` thật hoặc chờ trong `screen.js`.

## Chụp ảnh

```bash
npx --yes serve docs/prototypes -l 4173
node docs/prototypes/shared/capture-stage.mjs \
  --url http://127.0.0.1:4173/day-01-baseline/onboarding/index.html \
  --out docs/prototypes/day-01-baseline/frames \
  --cluster onboarding --steps 1,3,5
```

- Mặc định chụp 390, 834, 1194, 1440 (ảnh đúng px, không phải ảnh app).
- `--steps` nên là 3 bước quan trọng nhất, không phải mọi bước.
- Script ghi thêm một mục vào `capture.md` (URL, bước, khung, ngày); không xoá mục cũ.
- Ảnh app thật (production) vẫn cần cho phần "nguồn", nhưng không thay thế ảnh stage: ảnh app
  thường chỉ là khung điện thoại, còn ảnh stage mới cho thấy bản iPad/desktop.

## Xem tại chỗ

```bash
npx --yes serve docs/prototypes -l 4173
# http://127.0.0.1:4173/day-01-baseline/onboarding/index.html
```

- `390 / 834 / 1194 / 1440`: một khung, tự scale vừa cửa sổ.
- `Cả 4`: bốn iframe cạnh nhau; bấm một khung để mở khung đó.
- `Làm lại`: về bước 1, xoá lựa chọn.
- `?embed=1`: 1:1, không thanh stage (dùng khi cần nhìn pixel thật).

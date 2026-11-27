# STANDARD — hợp đồng cho mỗi cụm prototype

Prototype là **công cụ nghiên cứu thiết kế**, không phải bản app thu nhỏ và không phải bộ sưu tập ảnh chụp.
Mỗi cụm phải trả lời được ba câu:

1. Màn này trông thế nào ở **390, iPad dọc, iPad ngang và browser** — và bố cục có thật sự đổi theo khung không?
2. Nó **đẹp/ấn tượng ở đâu**, và cái đẹp đó có phục vụ việc dùng (đọc, chọn, mua, quay lại) không?
3. Bấm qua lại có hiểu không, **Làm lại** được không, dữ liệu có thật không?

> “Chưa cần hoàn thiện” **không** có nghĩa là “chưa cần đẹp”. Mỗi màn phải có ít nhất một điểm thị giác
> có chủ đích: một ảnh lớn, một dòng serif, một nhịp giấy, một khoảng trống được tính. Không có màn nào
> chỉ là form mặc định của trình duyệt.

## 0. Nghiên cứu trước khi vẽ (5 phút, bắt buộc)

Prototype chỉ có giá trị nếu nó **học từ đâu đó**, không chỉ chụp lại app hiện tại. Trước khi copy template:

1. Mở `../RESEARCH-SOURCES.md`, đọc đúng mục của cụm mình.
2. Chọn **2 nguồn ngoài** (app thật, pattern library, bài viết) + **1 nguồn trong** (`archive/`,
   `Samples Onboarding/`, ảnh app thật, note cũ).
3. Ghi vào `notes.md` mục `## Nguồn`: nguồn · URL · ngày · **học gì** (bố cục / nhịp / chữ / màu) · giữ gì · bỏ gì.
4. Ảnh nguồn (nếu có) → `research/<nguồn>-<cái>.png` + một dòng trong `research/sources.md`.

Không có mục này thì bản nộp **chưa xong**, kể cả khi màn đã đẹp. Không copy pixel, không dán màn của app
khác vào làm màn của banbe: chỉ học cách họ giải quyết **cùng một việc**. Nguồn ngoài phải áp được cho cả
834/1194/1440, không chỉ 390.

## 1. Bắt buộc

- **Copy vỏ dùng chung**, không dựng lại:
  ```bash
  mkdir -p docs/prototypes/day-0N-<slug>/<cụm>
  cp -R docs/prototypes/shared/template/. docs/prototypes/day-0N-<slug>/<cụm>/
  ```
  Cụm đã có bản cũ: `mv .../index.html .../index.before.html` trước khi copy, giữ bản cũ để so.
  Sau đó đổi `data-cluster`, `data-steps`, crumb và nội dung.
- **Ngày N > 1**: copy nguyên thư mục cụm của ngày N-1 sang ngày N rồi sửa tiếp, không dựng lại:
  ```bash
  mkdir -p docs/prototypes/day-0N-<slug>/<cụm>
  cp -R docs/prototypes/day-0(N-1)-<slug-cũ>/<cụm>/. docs/prototypes/day-0N-<slug>/<cụm>/
  ```
  Giữ `screen.css`/`screen.js`/`frames/` cũ; chỉ thêm phần của lăng kính hôm nay.
- **Bốn khung trong một stage**: 390×844 · 834×1194 · 1194×834 · 1440×900, cộng nút **Cả 4**.
  Đây là bản thiết kế ở từng khung, không phải ảnh app phóng to.
- **Container queries** (`@container screen (min-width: …)`), không `@media (min-width)` cho màn hình.
- **Không `position: fixed`**; dùng `absolute` trong `.bb-screen`; chiều cao `100%`, không `100vh`.
- **Nút Làm lại**: xoá lựa chọn (key `sessionStorage` dạng `bb:<cụm>:*`), về bước 1.
- **Deep link**: `#b1`, `#b2`… mở thẳng đúng bước; Back của trình duyệt đi lại được.
- **Thanh chuyển 5 cụm** ở mọi trang; cụm đích chưa có thì rơi về app thật kèm nhãn `app thật`.
- **Chữ Việt thật**, dữ liệu thật (id + ngày), không Lorem, không màn hình bịa.
- **Không sửa** `src/`, `ios/`, migration; **không deploy**.
- **20 phút** cho phần dựng (sau khi đọc và chọn nguồn); **tối đa 2 câu grill**, chỉ khi lựa chọn làm đổi bố cục.

## 2. Bốn khung phải khác nhau thật

| Khung | Bố cục tối thiểu | Điều phải kiểm |
| --- | --- | --- |
| 390×844 | một cột, ngón tay cái, không hover | không tràn ngang; CTA trong tầm với; bàn phím không che ô nhập |
| 834×1194 | hai cột hoặc cột nội dung + panel | không phải màn 390 kéo giãn; chữ không quá dài dòng |
| 1194×834 | ba vùng hoặc master–detail | không mất ngữ cảnh khi mở chi tiết; cột phụ có dữ liệu thật |
| 1440×900 | cột đọc tối đa ~1200, không kéo card | không có khoảng trống chết; bàn phím dùng được |

Nếu cụm **cố ý** chỉ một cột ở mọi khung (ví dụ một tờ giấy onboarding), phải nói rõ trong `notes.md`
và vẫn phải cho thấy nó **được đặt** trên màn lớn: lề, cột bằng chứng, hoặc khung đọc — không phải
một cột 390 nằm giữa khoảng trắng.

## 3. Hợp đồng stage

`shared/stage.js` gọi `window.bbScreen.render(step)`; `screen.js` phải có:

```js
window.bbScreen = {
  steps: 5,
  render(step) { ... },
  reset() { ... }   // tuỳ chọn
};
```

- `BBStage.go(n)` đổi bước và cập nhật `#bN`.
- `Làm lại` xoá `sessionStorage` prefix `bb:<cụm>:` rồi gọi `reset()` và `render(1)`.
- `?embed=1` là chế độ 1:1 không thanh stage, dùng cho iframe và capture.
- Đọc `shared/README.md` trước khi sửa `screen.css`/`screen.js`.

## 4. Dữ liệu

- Mỗi cụm nêu **ít nhất 3 điểm dữ liệu thật**: event id + tên + ngày, hoặc thread/account thật.
- Giá đúng đơn vị: VND (đồng) hoặc USD; `price_vnd` là minor units — không tự đổi.
- Giờ theo múi giờ địa điểm (`Asia/Ho_Chi_Minh`, `America/Los_Angeles`…), không theo máy.
- Ảnh app thật chỉ là **nguồn**; ảnh stage mới là bản thiết kế.
- Dữ liệu cũ ghi ngày chụp; không cập nhật lén để trông mới.

## 5. Nộp

```
day-0N-<slug>/<cụm>/
  index.html          # stage + màn thật
  screen.css
  screen.js
  notes.md            # giữ gì, đổi gì, vì sao, dữ liệu nào, đã/chưa kiểm
day-0N-<slug>/frames/
  <cụm>-<bước>-390.png
  <cụm>-<bước>-834.png
  <cụm>-<bước>-1194.png
  <cụm>-<bước>-1440.png
  <cụm>-overview-1440.png
  capture.md          # URL, bước, khung, ngày
```

Chụp **3 bước quan trọng nhất** ở cả 4 khung + 1 overview; không cần mọi bước. Ảnh app thật
(`app-*`) chỉ thêm khi cụm chưa có ảnh hoặc app vừa đổi.

## 6. Definition of done — 8 mục

1. Mở được ở cả 4 khung, không tràn ngang (`scrollWidth === clientWidth`).
2. `Làm lại` về bước 1 và xoá lựa chọn; `#b1`/`#b2` mở thẳng; Back đi lại được.
3. Thanh 5 cụm có ít nhất 1 link sống; link chưa có hiện `app thật`, không 404.
4. Ít nhất 3 dữ liệu thật kèm id/ngày trong `notes.md`.
5. Không lỗi console; không ảnh 404.
6. Mục tiêu chạm ≥44 px; focus thấy được; Tab/Enter/Esc dùng được ở màn chính.
7. `prefers-reduced-motion`: bản tĩnh vẫn hiểu và vẫn đẹp.
8. `notes.md` ghi rõ **giữ gì / đổi gì / vì sao** + mục **Nguồn** (≥2 ngoài + 1 trong, URL + ngày) + danh sách **chưa kiểm**.

## 7. Chụp

```bash
npx --yes serve docs/prototypes -l 4173
node docs/prototypes/shared/capture-stage.mjs \
  --url http://127.0.0.1:4173/day-0N-<slug>/<cụm>/index.html \
  --out docs/prototypes/day-0N-<slug>/frames \
  --cluster <cụm> --steps 1,3,5
```

## 8. Ngân sách 20 phút

| Phút | Việc |
| --- | --- |
| 0–2 | đọc STANDARD, decisions, code, bản trước |
| 2–5 | `RESEARCH-SOURCES.md` → 2 nguồn ngoài + 1 trong, ghi `research/sources.md` |
| 5–14 | copy template + dựng màn thật ở 4 khung |
| 14–17 | Làm lại, deep link, link cụm, kiểm 4 khung |
| 17–19 | chạy capture-stage.mjs |
| 19–20 | notes.md + danh sách chưa kiểm |

Hết 20 phút mà chưa xong: **nộp bản đang có**, ghi phần thiếu vào `notes.md`. Không kéo dài im lặng.

## 9. Ngày 8

Ngày 8 là **một** mission review (không phải 5): đọc `done/`, review từng cụm theo 4 câu, chọn cụm
owner đã trả lời và viết APPLY prompt. Nó kiểm luôn 4 khung, Làm lại và link cụm của từng bản.

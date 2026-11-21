# banbe apply — biến audit thành PR

> Đây là khuôn để audit sinh `docs/audits/<date>/APPLY.md`. File APPLY phải **tự chứa**: session mới không thấy workspace cũ, nên mọi finding phải kèm `path:line`, hành vi sai và tiêu chí nghiệm thu ngay trong prompt.
> Không gửi khuôn trống. Thay hết `<...>` bằng nội dung thật; bỏ mục không áp dụng.

## 0. Vai trò

Bạn là kỹ sư triển khai cho banbe. Đây là mission **cấu hình tối đa**: đọc đủ context, không bỏ bước kiểm, không hạ scope để chạy nhanh. Sửa đúng các phát hiện dưới đây, mở **một PR** để Preview và review. Không deploy, không merge, không chạy migration.

## 1. Trước khi sửa

- Đọc `AGENTS.md`, `docs/second-brain/START-HERE.md` rồi `graph/Code map.md`; chỉ grep khi map không trả lời.
- `git rev-parse --short HEAD` và `git status`; đối chiếu từng finding với HEAD.
- Finding không còn đúng / đã được sửa → ghi `stale: <lý do>`, bỏ qua, không sửa mò.
- Không còn finding nào đúng → dừng, báo `nothing to apply`; không tạo PR rỗng.

## 2. Phạm vi

- Chỉ làm các mục P0/P1 và P2 được liệt kê; tối đa **7 mục**.
- Không đổi schema, migration, DB, deploy, secret. Không thêm dependency trừ khi finding bắt buộc.
- Giữ floor **Safari 16.2 / iOS 16.2** (Baseline Widely available của app).
- Branch `fix/audit-<date>`; commit nhỏ theo từng finding; không rewrite ngoài phạm vi.
- **Không secret, không PII — tuyệt đối:** không đưa vào APPLY.md, PR, commit, log, ảnh hay test fixture: `.env`, API key/token/webhook, service-role key, JWT, mật khẩu, connection string, email, số điện thoại, tên khách, địa chỉ nhà, mã booking/payment, ảnh có mặt người. Cần dữ liệu thật → `<redacted>` + mô tả hình dạng, hoặc fixture giả. Finding về secret chỉ ghi `path:line` + loại, che giá trị, báo owner riêng — không mở PR chứa secret.
- **Bố cục thương mại:** bản thử đang bọc app trong khung iPhone (`.bb-device` / `.bb-screen`, `src/App.jsx:864`, `src/styles.css:600`); mục tiêu thương mại là **từng màn hình có bố cục riêng** (390 / 768 / 1280+), không dùng một khung điện thoại. Prototype ở `docs/prototypes/` là nguồn thiết kế nhưng **chưa được audit lại và chưa áp dụng**.
  - **APPLY phải kèm gap list đã audit:** màn → prototype canonical (path) → lệch → việc cần làm → nghiệm thu. Thiếu gap list hoặc không rõ prototype canonical → **dừng mục đó**, ghi `blocked: commercial gap list missing`, **không tự audit lại prototype**, không tự chọn màn.
  - Có gap list: giữ khung thử sau một điều kiện/flag để không phá bản thử, không trộn thay đổi bố cục thương mại với fix P0/P1 khác trong cùng commit. APPLY không có mục này → **không** tự refactor khung.

## 3. Kiểm

- `npm run build`, `npm run test:unit`; chạy Playwright cho đúng luồng bị sửa.
- Nếu đụng UI: `node scripts/golden-shots.mjs --out docs/audits/<date>/golden`, so với `docs/agent-os/vault/golden/shots/`; bỏ qua khác biệt số liệu, chỉ báo lệch bố cục/typography/màu.
- Mỗi finding cần bằng chứng trước/sau: `path:line`, tên test, ảnh hoặc route.

## 4. PR

- Mở PR vào `main`, **không merge**: `fix(audit): <date> — <tóm tắt>`.
- Body gồm: findings đã sửa, cách sửa, bằng chứng, test đã chạy, rủi ro/rollback, checklist Preview (route + viewport + theme).
- Không commit `.env`, ảnh chụp tạm, `dist/`, `graphify-out/`.
- Không dán secret/PII vào body PR, ảnh, log hay test fixture; che email/số điện thoại/địa chỉ/mã đơn trước khi chụp. Nếu phát hiện secret: chỉ nêu `path:line` + loại, không chép giá trị.

## 5. Trả lời

- PR link · commit sha · file đã đổi · test đã chạy · route Preview · phần **chưa kiểm**.

---

## Findings cần sửa

<!-- Audit điền: mỗi mục một block ngắn, đủ để session mới không cần đọc lại repo cũ. -->

### P1 — <tiêu đề>

- **Ở đâu:** `path:line` (route/screen nếu là UI).
- **Sai thế nào:** hành vi thực tế + bằng chứng (log/ảnh/test).
- **Sửa nhỏ nhất:** mô tả fix, không rewrite.
- **Nghiệm thu:** điều kiện kiểm được, gồm test/route.
- **Effort:** S/M/L.

### P2 — <tiêu đề>

- **Ở đâu:** ...
- **Sai thế nào:** ...
- **Sửa nhỏ nhất:** ...
- **Nghiệm thu:** ...

### Commercial layout — <màn> (chỉ khi audit yêu cầu)

- **Prototype:** `docs/prototypes/<file>.html` (hoặc `missing`).
- **Hiện tại:** route + ảnh 390/768/1280; ghi `trial shell` nếu đang trong khung iPhone.
- **Lệch:** bố cục / state / copy / flow so với prototype.
- **Việc cần làm:** màn này cần bố cục gì ở 390/768/1280+; giữ khung thử đến khi có điều kiện chuyển.
- **Nghiệm thu:** route + viewport + ảnh before/after.

## Không làm

- <việc ngoài phạm vi, để tránh session mới mở rộng>

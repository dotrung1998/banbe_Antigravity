# Nguồn nghiên cứu — 2 ngoài + 1 trong, trước khi vẽ

Prototype là **công cụ nghiên cứu**, không phải ảnh chụp app. Một cụm chỉ đáng nộp khi nó học được
điều gì đó từ bên ngoài banbe **và** giữ được ngữ pháp đã có trong nhà. Mỗi cụm lấy tối thiểu:

- **2 nguồn ngoài** — app thật, pattern library, bài viết: học *cách họ giải quyết cùng một việc*.
- **1 nguồn trong** — `archive/`, `Samples Onboarding/`, ảnh app thật, note cũ, code đang chạy.

Không có 3 dòng này trong `notes.md` thì bản nộp **chưa xong**, kể cả khi màn đã đẹp.

## 0. Luật ghi nguồn

| Phải ghi | Ở đâu |
| --- | --- |
| Nguồn · URL · ngày đọc · **học gì** (bố cục / nhịp / chữ / màu) · giữ gì · bỏ gì | `notes.md`, mục `## Nguồn` |
| Ảnh nguồn đã tải (nếu có) | `research/<nguồn>-<cái>.png` + một dòng trong `research/sources.md` |
| Ảnh app thật | `frames/app-<màn>-<khung>.png` + `capture.md` (URL, id, ngày) |

- **Không copy pixel**, không dán màn của app khác vào làm màn của banbe, không bịa màn hình.
- Chỉ dùng nguồn công khai. Không tải asset trả phí (Mobbin, Godly, Figma community có bản quyền) vào repo.
- Nguồn ngoài chỉ để **học lý do**, không phải để trang trí. Ghi rõ "học gì" bằng một câu cụ thể.

## 1. Trong nhà (đúng ngữ pháp, miễn phí)

| Nguồn | Dùng cho | Cách dùng |
| --- | --- | --- |
| `archive/` — 15 bản đã chốt (Home v3.2, onboarding v5, map v5, schedule v5, ticket v2, refund…) | ngữ pháp cũ, thứ owner đã thấy và chốt | đọc trước, ghi 3 điều giữ / 3 điều đổi; **không copy pixel** |
| `Samples Onboarding/` — 12 ảnh owner (XING carousel, openGym pre-permission…) | nhịp onboarding, cách hỏi quyền, cách khoe giá trị | nêu đúng tên ảnh đã học, không coi là màn của banbe |
| `frames/app-*.png` — ảnh chụp production/simulator | dữ liệu thật, chỗ app đang dở | chụp mới khi app đổi; ghi ngày |
| `RESEARCH-video-repos.md` — 10 repo motion + nguồn ảnh miễn phí | nhịp, shot, caption, asset | chỉ dùng repo đã đánh giá "dùng được" |
| `rig/` — Remotion | chốt nhịp onboarding trước khi viết CSS | `npm run still` để soi từng frame |
| `docs/second-brain/` + `.claude/notes/` | quyết định cũ, lý do, note 65/66/76 | trích note, không đoán lại |
| `src/` (chỉ đọc) | field nào có thật, giá/giờ/trạng thái nào tồn tại | không sửa, không deploy |

## 2. Ngoài (học cách làm, không copy)

### `onboarding` — Welcome · 3 câu · reveal · consent · Login
| Nguồn | Học gì |
| --- | --- |
| [Partiful](https://partiful.com) | invite → RSVP trong 2 màn; chữ to, ít field |
| [Luma](https://lu.ma) | onboarding host/guest tách rõ; calendar là đích đến |
| [Duolingo](https://duolingo.com) | một câu hỏi một màn, tiến độ thấy được, trả lời xong mới đi tiếp |
| [Headspace](https://headspace.com) | khoảng trắng, nhịp thở, không nhồi chữ |
| Apple Fitness / openGym (ảnh trong `Samples Onboarding/`) | quyền + mục tiêu: hỏi sau khi đã cho thấy giá trị |
| [NN/g — onboarding](https://www.nngroup.com/articles/onboarding-tutorials/) | khi nào nên skip, khi nào nên bắt buộc |

### `discover` — Home · Browse/Search · Map
| Nguồn | Học gì |
| --- | --- |
| [Luma Discover](https://lu.ma/discover) | hàng sự kiện trên màn rộng: ảnh bìa, thời gian, không kéo card |
| [Airbnb](https://airbnb.com) | map + list cùng một tập kết quả; panel thay vì chuyển trang |
| [Resident Advisor](https://ra.co) | editorial + danh sách dày, typography làm thương hiệu |
| [Eventbrite](https://eventbrite.com) | search/filter nhiều tầng, nhưng đừng bắt chước mật độ |
| [Dice](https://dice.fm) | ticket-forward: vé là thứ đáng xem, không phải card |
| [Apple Music](https://music.apple.com) | hàng ngang có lý do, tiêu đề mục rõ, không carousel vô tận |

### `event` — Event Detail · Reserve/Hold · Ticket + QR
| Nguồn | Học gì |
| --- | --- |
| [Luma event page](https://lu.ma) | một cột đọc + cột hành động; giá và chỗ cạnh CTA |
| [Partiful event page](https://partiful.com) | không khí, ảnh lớn, RSVP nhẹ |
| [Dice event](https://dice.fm) | vé như vật thể; QR không bị giấu |
| [Stripe Checkout](https://stripe.com/payments/checkout) | giá, phí, tổng tiền: một đường đọc, không mơ hồ |
| Apple Wallet pass | cấu trúc một tấm vé: chủ, chỗ, giờ, mã — không trang trí thêm |
| [Eventbrite checkout](https://eventbrite.com) | giữ chỗ có hạn: đồng hồ, số chỗ, lỗi rõ |

### `me` — Schedule · Inbox/Chat · Account
| Nguồn | Học gì |
| --- | --- |
| [Notion Calendar](https://www.notion.com/product/calendar) | tuần/tháng trên màn rộng, cột ngày, sự kiện nhiều múi giờ |
| [Google Calendar](https://calendar.google.com) | master–detail: lưới + panel chi tiết, không mất ngữ cảnh |
| [Luma calendar](https://lu.ma/home) | "sắp tới" vs "đã qua", một danh sách, không badge bịa |
| [Threads](https://threads.net) / Instagram DM | inbox một cột trên điện thoại, hai cột trên lớn |
| [Linear Inbox](https://linear.app) | mật độ cao vẫn đọc được: nhóm, trạng thái, phím tắt |

### `host` — Create · Hub · Money & door · Admin
| Nguồn | Học gì |
| --- | --- |
| [Luma host](https://lu.ma) | tạo event nhiều bước nhưng luôn thấy trước kết quả |
| [Partiful host tools](https://partiful.com) | mời + theo dõi khách, chữ thân thiện |
| [Eventbrite organizer](https://eventbrite.com) | bảng đơn, check-in, hoàn tiền |
| [Stripe Dashboard](https://dashboard.stripe.com) | bảng tiền: số, đơn vị, trạng thái, không làm tròn mất nghĩa |
| [Linear Projects](https://linear.app) | hub: overview / tasks / team trên một màn rộng |
| [Vercel](https://vercel.com) | trạng thái và hành động phá huỷ phải khác nút thường |

## 3. Đã cài — dùng đúng việc

| Công cụ | Dùng ở đâu | Cách gọi |
| --- | --- | --- |
| `impeccable` | thiết kế/soi UI: `onboard`, `critique`, `animate`, `adapt` | trước khi nộp: critique một lượt, sửa, rồi capture |
| `prototype` | khung làm nhanh: một câu hỏi → một bản | đầu phiên, để không dựng lan man |
| `modern-web-guidance` | **bắt buộc** trước khi dùng API nền tảng (dialog, container query, view transition, scroll-driven) | Baseline repo là Safari 16.2 — kiểm trước khi viết |
| `web-browsing-cli` | đọc trang thật (Luma/Partiful/Airbnb) không cần browser | lưu text + 1 ảnh vào `research/` |
| `grill-me` | 2 câu khó nhất khi lựa chọn đổi bố cục | chỉ khi câu trả lời làm đổi layout |
| Hermes MCP `context7` / `deepwiki` | docs thư viện, đọc repo | khi cần API cụ thể, không đoán |
| Hermes MCP `vault` | đọc `docs/second-brain/` | tìm quyết định cũ trước khi hỏi lại owner |
| `code-review`, `security-audit`, `using-git-worktrees`, `pr-manager` | **không** dùng cho thiết kế | chỉ ở ngày 8 / phiên áp dụng code |

## 4. Quy trình 5 phút

1. Chọn cụm → mở đúng mục ở trên, chọn 2 nguồn ngoài (một về **bố cục**, một về **nhịp/chi tiết**).
2. `web-browsing-cli` đọc 1 trang; lưu 1 ảnh + 3 ghi chú vào `research/`.
3. Mở `archive/` bản gần nhất + 1 ảnh app thật; ghi 3 điều giữ / 3 điều đổi.
4. Viết `research/sources.md` 4 dòng (nguồn · URL · ngày · học gì). Xong mới copy template.

## 5. Tự kiểm trước khi nộp

- Nguồn này dạy mình điều gì mà ảnh app hiện tại **không** dạy?
- Điều đó có áp được cho **834 / 1194 / 1440**, hay chỉ đúng 390?
- Có chỗ nào mình copy pixel, hoặc dán màn của app khác? Bỏ.
- `notes.md` có đủ 2 ngoài + 1 trong kèm URL/ngày chưa?

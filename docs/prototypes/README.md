# Prototypes — 8 ngày, 5 cụm màn hình, nối liền nhau

Thư mục này là nơi prototype sống và lớn lên. Hai mục tiêu, không lẫn nhau:

1. **Onboarding** ngắn, to, rõ, cinematic — nhưng bằng **ảnh thật trong app**, không bịa màn hình để tạo niềm tin.
2. **Prototype cho mọi nhóm màn hình** ở kích thước lớn (iPad, browser) và **nối được với nhau**: từ Home bấm sang
   Event, sang Ticket, sang Schedule… như một app thật, không phải 8 file rời.

Cấu trúc là một **ma trận**: 7 ngày × 5 cụm. Mỗi **ngày** là một *lăng kính* (nền → vỏ → trạng thái → chuyển động →
vai → thiết bị → nối liền); mỗi **cụm** là một *nhóm màn hình*. Ngày N không làm lại cụm nào cả — nó làm **sâu thêm**
đúng bản của ngày N-1.

Mỗi ngày bạn nhận **5 mission Discord riêng, mỗi cụm một tin** (lăng kính của ngày + việc riêng của cụm + nộp + kiểm).
Chi tiết nằm trong `missions/plan.json`, luật chung ở `missions/STANDARD.md`; `--cluster <id>` chỉ in đúng tin của một cụm.
Trên bảng Glance thì mỗi cụm vẫn có câu hỏi riêng.

| # | Cụm (`id`) | Màn hình | Folder |
| --- | --- | --- | --- |
| 1 | `onboarding` | Welcome · consent · 3 câu hỏi · For You reveal · Login | `<ngày>/onboarding/` |
| 2 | `discover` | Home (For You/Tonight/Weekend) · Browse/Search · Map | `<ngày>/discover/` |
| 3 | `event` | Event Detail · Reserve/Hold · Ticket + QR | `<ngày>/event/` |
| 4 | `me` | Schedule · Inbox/Chat · Account | `<ngày>/me/` |
| 5 | `host` | Create event · Project Hub · Money & door · Admin | `<ngày>/host/` |

## Thang 8 ngày

| Ngày | Folder | Lăng kính | Điều phải trả lời được |
| --- | --- | --- | --- |
| 1 | `day-01-baseline/` | Bản lớn đầu tiên cho cả 5 cụm, dựng từ `archive/` + ảnh thật | Cụm này có mở được một mình trên màn lớn không? |
| 2 | `day-02-shell/` | Một vỏ chung: rail/sidebar, dock, header, khoảng cách | Cụm này sống trong vỏ, hay cố ý đứng ngoài — vì sao? |
| 3 | `day-03-states/` | Dữ liệu thật, trạng thái xấu (trống, hết vé, huỷ, hết hạn, guest) | Màn này có đứng được khi mọi thứ không như ý? |
| 4 | `day-04-motion/` | Nhịp: vào, phản hồi bấm, chuyển màn; rig cho onboarding | Nhịp này nhanh hay chậm, và tại sao đúng con số đó? |
| 5 | `day-05-roles/` | Guest / member / host / team / admin trên cùng một màn | Khác quyền có **nhìn thấy được** không? |
| 6 | `day-06-devices/` | 834×1194, 1194×834, 1440×900, split view, bàn phím | Vỡ ở khung nào, sửa thế nào? |
| 7 | `day-07-continuity/` | Nối 5 cụm: link chéo, Back, một từ cho một khái niệm | Bấm 12 bước ngẫu nhiên có gặp ngõ cụt? |
| 8 | `day-08-review/` | Review `done/` + viết APPLY prompt cho cụm owner chọn | Dựng thật cái gì, theo thứ tự nào, rollback ra sao? |

Mỗi ngày có 5 folder cụm (`onboarding/ discover/ event/ me/ host/`) + `research/` + `frames/`, và một file tổng hợp
(`shell.md`, `states.md`, `motion.md`, `roles.md`, `devices.md`, `continuity.md`) để ngày sau đọc nhanh. Mỗi cụm
copy `shared/template/` — stage, rail 4 khung, nút Làm lại, deep link, thanh chuyển cụm — và chỉ viết phần màn hình.

## 6 luật

1. **Ảnh thật, không bịa.** Mọi màn hình phải là UI dựng lại đúng dữ liệu thật (tên sự kiện, giá, giờ, host có thật)
   hoặc ảnh chụp thật của banbe; stock chỉ làm texture nền, ghi rõ. Ảnh nộp là **ảnh stage ở 4 khung**, không phải
   ảnh app trong khung điện thoại.
2. **Mỗi phần một folder.** Ảnh, PDF, ghi chú, nguồn web đã tải → `day-0N-*/research/`; ảnh stage + ảnh app → `day-0N-*/frames/` kèm `capture.md` (URL, event id, ngày chụp). Không để rác ở gốc.
3. **Nhìn lại trước khi vẽ.** `decisions/day-0N.json` (câu trả lời của owner) + bản cùng cụm của ngày N-1 +
   `done/` (bản đã chốt). `notes.md` phải ghi: giữ gì, đổi gì, vì sao.
4. **Nối, không cụt.** Mỗi `index.html` có thanh chuyển cụm ở trên cùng (từ `shared/stage.js`), và mọi nút chính
   dẫn sang cụm tương ứng (Home → Event → Ticket → Schedule…); cụm chưa có thì rơi về app thật kèm nhãn, không 404.
5. **Không đụng app.** Session prototype **không sửa** `src/`, `ios/`, migration, và không deploy. Chỉ ghi trong
   `docs/prototypes/`. Áp dụng vào code là việc của ngày 8 (APPLY prompt) và một phiên riêng.
6. **Hỏi ít, hỏi đúng.** 5 câu/ngày — mỗi cụm một câu, trên bảng Glance (`questions/day-0N.json`). Trong mission,
   dùng skill `grill-me` tối đa **2 câu**, chỉ khi lựa chọn làm đổi bố cục; câu nào đã trả lời trên bảng thì không hỏi lại.

## Kích thước phải đứng được

| Khung | px | Ghi chú |
| --- | --- | --- |
| Điện thoại (chuẩn cũ, để so) | 390×844 | Không được coi là đủ |
| iPad dọc | 834×1194 | Cột nội dung + panel, không kéo giãn điện thoại |
| iPad ngang | 1194×834 | Split view, sidebar |
| Browser | 1440×900 | Bàn làm việc thật: nhiều cột, bàn phím |

Mỗi cụm có **một stage** với rail 390 / 834 / 1194 / 1440 + "Cả 4"; ảnh nộp là ảnh stage ở từng khung. Không được
giả vờ: phóng to một màn 390 px lên 1194 px là lỗi, không phải bản iPad.

## Chuẩn chung

- `missions/STANDARD.md` — hợp đồng: nghiên cứu (2 ngoài + 1 trong), 4 khung, reset, deep link, link cụm, dữ liệu, 8 mục definition of done, 20 phút.
- `RESEARCH-SOURCES.md` — nguồn ngoài theo cụm (Luma, Partiful, Airbnb, Linear…), nguồn trong (`archive/`, ảnh mẫu, app thật) và cách dùng 8 skill đã cài; mọi prompt đều trỏ vào đây.
- `shared/template/` — copy cho mỗi cụm; `shared/stage.*` — vỏ; `shared/capture-stage.mjs` — chụp 4 khung + overview.
- `shared/README.md` — cách copy, hợp đồng `window.bbScreen`, ba cái bẫy (container queries, `position: fixed`, ảnh/font).

## Một ngày chạy thế nào

```bash
# đọc thứ tự này trước khi làm
docs/second-brain/START-HERE.md                     # code map, đừng grep trước
docs/prototypes/README.md                           # file này
docs/prototypes/missions/plan.json                  # ma trận ngày × cụm (nguồn của mọi mission)
docs/prototypes/RESEARCH-SOURCES.md                 # 2 nguồn ngoài + 1 trong cho cụm đang làm
docs/prototypes/questions/day-0N.json               # 5 câu đang chờ owner trả lời
docs/prototypes/decisions/day-0N.json               # câu trả lời đã có (bảng Glance ghi vào)
docs/prototypes/day-0(N-1)-*/<cụm>/index.html       # bản hôm qua của đúng cụm đó
docs/prototypes/done/                               # bản đã chốt — quan trọng hơn bản nháp

# xem prototype (mở trên máy, và trên iPad nếu muốn)
npx --yes serve docs/prototypes -l 4173
# owner muốn xem trên iPad: mở thêm cổng ra tailnet (owner tự chạy, một lần)
#   tailscale serve --bg --http=8086 http://127.0.0.1:8086
#   npx --yes serve docs/prototypes -l 8086
```

Mission được **đẩy lên Discord** lúc 06:00 (ICT) mỗi ngày, kênh `#banbe-reports`: **5 message/ngày, mỗi cụm một
message** (ngày 8: một message review). Ngày 1 = `PROTOTYPE_START`, mặc định **2026-11-27** (ngày 1 đăng tối 27/11, nên 06:00 28/11 là ngày 2); lịch chỉ chạy sau khi
workflow được merge vào nhánh mặc định. Xem trước, hoặc lấy riêng một cụm:

```bash
node scripts/cloud-notify.mjs prototype --dry-run                     # 5 tin của hôm nay, mỗi cụm một tin
node scripts/cloud-notify.mjs prototype --day 3 --cluster event --dry-run  # chỉ tin của cụm event
```

Skill dùng trong mission: `prototype` (mattpocock), `impeccable` (onboard / critique / animate / adapt),
`grill-me`, `web-browsing-cli`, và `modern-web-guidance` khi cần một tính năng nền tảng (Baseline của repo là
Safari 16.2 — xem `.claude/notes/90-modern-web-guidance-pass.md`).

## Bảng câu hỏi hằng ngày (Glance)

Mỗi ngày một bộ câu hỏi trong `questions/day-0N.json`, **mỗi cụm một câu** (ngày 8: 3 câu review). Bảng hiện ở
Glance → tab **Prototype** (`http://macbook-air-von-the.tail8ab714.ts.net:8080/prototype`, cùng mật khẩu dashboard).
Câu đã trả lời có nút **↺ Hỏi lại**: bấm là câu đó về hàng chờ (ghi chú của ngày giữ nguyên), để phiên sau
hỏi lại thay vì đọc một quyết định đã cũ.

Bấm một lựa chọn là:

1. `POST` sang `ops-data` (banbe-ops, cổng 8085, chỉ trong tailnet),
2. ghi `decisions/day-0N.json` trong repo này,
3. ghi/ghi đè một note trong vault: `docs/second-brain/raw/inbox/prototype-day-0N.md`.

Không có bước "copy tay". Note trong inbox là thứ agent đọc ở đầu mỗi ngày; `raw/` bị gitignore nên note không vào
git, còn `decisions/*.json` thì có (quyết định là lịch sử).

## Nội dung thư mục

| Path | Là gì |
| --- | --- |
| `missions/plan.json` | **Ma trận** 7 lăng kính × 5 cụm — nguồn duy nhất của mission; sửa ở đây, không sửa script |
| `missions/STANDARD.md` | Hợp đồng của mỗi cụm: nghiên cứu trước, 4 khung, Làm lại, deep link, dữ liệu, 8 mục definition of done, 20 phút |
| `RESEARCH-SOURCES.md` | **Nguồn nghiên cứu**: 2 nguồn ngoài + 1 nguồn trong cho mỗi cụm, và skill/MCP đã cài dùng vào việc gì |
| `shared/` | Vỏ dùng chung: stage 4 khung + Làm lại + capture; `template/` để copy cho mỗi cụm |
| `missions/day-08.md` | Mission review + áp dụng của ngày 8 (một message duy nhất) |
| `questions/day-01…08.json` | Câu hỏi cho owner (5 câu/ngày, mỗi cụm một câu), schema ở `questions/README.md` |
| `decisions/` | Câu trả lời do bảng Glance ghi vào — **không sửa tay**, chỉ đọc |
| `done/` | Bản đã được chấp nhận (xem `done/README.md`) — ngày sau đọc **trước** bản nháp; ngày 8 review đúng thư mục này |
| `day-0N-*/` | 5 cụm + `research/` + `frames/` của ngày N |
| `rig/` | Remotion motion rig (onboarding cinematic, ảnh thật) — xem `rig/README.md` |
| `archive/` | Prototype cũ (trước 2026-11-27: Home v3.2, onboarding v5, map v5, ticket v2…). **Không dùng nữa** — chỉ đọc để giữ ngữ pháp, không trích dẫn như bản hiện tại |
| `Samples Onboarding/` | 12 ảnh mẫu của owner (XING carousel, openGym pre-permission…) — **chỉ là ví dụ**, không copy pixel |
| `RESEARCH-video-repos.md` | Video 10 repo motion graphics: cái nào dùng được, đã cài gì, nguồn ảnh miễn phí |

## Lịch sử

| Ngày | Việc |
| --- | --- |
| 2026-11-27 | Dựng thang 8 ngày, bảng câu hỏi Glance, mission Discord, rig Remotion, nghiên cứu video |
| 2026-11-27 | Đổi `Done/` → `archive/`, thêm `done/`; thang thành 7 lăng kính × 5 cụm (một mission tổng hợp/ngày), ngày 8 review + APPLY |
| 2026-11-27 | Tách thành **5 mission/ngày** (mỗi cụm một tin), thêm `STANDARD.md` + `shared/` (stage 4 khung, Làm lại, deep link, capture); mỗi tin có việc riêng của cụm |
| 2026-11-27 | Thêm `RESEARCH-SOURCES.md`: mỗi cụm 2 nguồn ngoài + 1 trong, và 8 skill đã cài dùng đúng việc; STANDARD §0 bắt buộc ghi nguồn. Glance: nút **↺ Hỏi lại**, tab “Đã cài” mở file local (không 404). Bản ngày 1 cũ bị bỏ, ngày 1 làm lại từ mission mới |

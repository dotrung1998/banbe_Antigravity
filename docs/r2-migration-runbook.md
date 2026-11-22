# Chuyển media công khai từ Supabase sang Cloudflare R2

Runbook cho việc **thật**: copy ảnh event công khai + avatar organizer sang R2, rồi
để web đọc từ R2. Bản Supabase **không bị xoá hay sửa** trong suốt quá trình, nên
mọi bước đều quay lại được.

Thiết kế gốc: [.claude/notes/28-r2-hybrid-media.md](../.claude/notes/28-r2-hybrid-media.md).

## Trạng thái đã kiểm tra (2026-11-21)

| Hạng mục | Thực tế |
|---|---|
| Migration `153_r2_public_media` | **Đã áp dụng** trên production; `media_assets` có **141 asset published** (125 event photo + 16 organizer avatar), 3 cột `*_r2_ref` đã dùng; thêm **2 user avatar** copy riêng qua `migrate-user-avatars-to-r2.mjs` |
| `POST /api/media` | **Đã deploy**, trả `401 AUTH_REQUIRED` khi không có token |
| DNS `banbe.app` | Nameserver Cloudflare (`hazel/andy.ns.cloudflare.com`) → gắn được custom domain R2 |
| `media.banbe.app` | **Active**: preflight 15/15, object thật trả `HTTP 200 image/png, immutable` |
| Đối tượng đủ điều kiện | **126** ảnh event public + **16** avatar organizer; **4** ảnh invite-only (`banrieng`) cố ý ở lại |
| Cờ hiện tại | R2_* đã set local; web production `VITE_MEDIA_R2_READS=1`; iOS plist R2 bật; `MEDIA_R2_UPLOADS=off` |

### Kết quả cuối 2026-11-21

- **141 media_assets published**: 125 event photo + 16 organizer avatar; thêm **2 user avatar**
  copy riêng sang `v1/user-avatars/...` và đổi `profiles.avatar_url` (bản gốc Supabase giữ nguyên).
- **126/126** ảnh event public, **35/35** cover, **16/16** avatar organizer có `r2_ref`; **2/2** user
  avatar trên R2; 0 thiếu.
- `npm run r2:verify`: audit đủ 13 bucket, **11/11** URL thật trả `200 image/jpeg immutable`;
  **11/11** bản gốc Supabase khớp sha256; 0 public event/organizer + 0 user avatar còn Supabase.
- Origin local `http://127.0.0.1:5173`: sweep 9 route (Home/feed, browse, search, map, event,
  organizer, 2 public profile, profile guest) có **0** request `supabase.co/storage`.
- Production (bundle cũ, chưa redeploy) còn **5 request avatar Supabase** (3 browse, 1 event,
  1 organizer); code local đã fix cả `openOrganizerProfile`, `loadEventOrgStats` và Home discovery.
- Còn lại: 4 ảnh invite-only, 3 object gốc avatar trong bucket `avatars` (2 giữ rollback + 1 mồ côi),
  object mồ côi không hàng nào tham chiếu. Không phải ảnh public event/organizer.

## Nguyên tắc: không có key nào đi qua chat

- Không dán key vào chat, không `export` trong terminal (sẽ vào shell history).
- Key local nằm trong **`.r2-secrets.local`** — đã gitignore, `chmod 600`, chỉ script đọc.
- Key trên Vercel nhập **trực tiếp trong dashboard**, không qua file repo.
- Script chỉ in *tên* biến và mã lỗi (`R2_PUT_403`), không in giá trị, không in presigned URL.
- Hai token tách quyền, không dùng token chung:
  - **R2 API token**: Object Read & Write, giới hạn đúng 2 bucket.
  - **Cloudflare API token**: Zone → Cache Purge, giới hạn đúng zone `banbe.app`.

Điền file xong, bạn có thể tự chạy hoặc bảo tôi chạy — script đọc file nên tôi vẫn
không nhìn thấy giá trị.

## Bước 1 — Cloudflare (làm một lần)

1. **Tạo 2 bucket**: mở <https://dash.cloudflare.com/?to=/:account/r2/overview>
   (menu trái **R2 Object Storage**) → nút **Create bucket** (góc phải):
   - `banbe-media-public` — chứa ảnh đã publish.
   - `banbe-media-staging` — bucket tạm, **không** bật public access.
   - Location: **Automatic** là đủ (ảnh đi qua CDN, không phụ thuộc vị trí bucket).
   - Nếu R2 chưa bật: bấm **Enable R2** và thêm phương thức thanh toán (free tier 10 GB).

2. **Staging → Settings → Object lifecycle rules**: thêm rule, prefix `staging/`,
   *Delete objects after* **1 day** (dọn file upload dở).

3. **Staging → Settings → CORS Policy → Add CORS policy → tab JSON**, dán:

   ```json
   [
     {
       "AllowedOrigins": ["https://www.banbe.app", "https://banbe.app"],
       "AllowedMethods": ["PUT"],
       "AllowedHeaders": ["Content-Type"],
       "ExposeHeaders": ["ETag"],
       "MaxAgeSeconds": 3600
     }
   ]
   ```

   (Chỉ cần `content-type`: `content-length` là header trình duyệt tự gửi, JS không set được.)

4. **Public bucket → Settings → Public access**:
   - **R2.dev subdomain**: để **Disabled** (bucket này chỉ phục vụ qua domain riêng).
   - **Custom Domains → Connect Domain** → nhập `media.banbe.app` → **Continue**.
   - Nếu Cloudflare báo đã có DNS record cho host này: mở zone `banbe.app` → **DNS → Records**,
     tìm record `media` (hiện đang trả 525), **Delete**, rồi quay lại **Connect Domain**.
     Cloudflare tự thêm bản ghi proxied — không tự tạo CNAME tay.
   - Review record → **Connect Domain**. Status đi từ **Initializing** → **Active** (vài phút).
   - Kiểm tra: `curl -I https://media.banbe.app/` phải trả **404** (hết 525).
   - Domain phải nằm trong **cùng account** với bucket R2.

5. *(Tuỳ chọn nhưng nên)* **Caching → Cache Rules**: hostname `media.banbe.app` →
   *Cache everything*, Edge TTL *respect origin*. Object đã có
   `Cache-Control: public, max-age=31536000, immutable` nên CDN giữ rất lâu.

6. **R2 → Overview → Account Details → API Tokens → Manage**: *Create Account API token*,
   name `banbe-media-migrate`, permission **Object Read & Write**,
   **Only specific buckets** = đúng 2 bucket trên, không hết hạn (xoay tay khi cần).
   Màn hình kết quả hiện **Access Key ID**, **Secret Access Key** (chỉ hiện một lần) và
   **Account ID** — copy thẳng vào file local, không qua chat.

7. **My Profile (avatar góc phải) → API Tokens → Create Token → Create Custom Token**:
   name `banbe-cache-purge`, **Zone → Cache Purge → Purge**,
   **Zone Resources: Include → Specific zone → banbe.app**. Zone ID nằm ở
   **banbe.app → Overview → sidebar phải**.

## Bước 2 — Điền file local

```bash
cp .r2-secrets.local.example .r2-secrets.local
chmod 600 .r2-secrets.local
# mở file, điền R2_ACCOUNT_ID / R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY /
# R2_PUBLIC_BUCKET / R2_STAGING_BUCKET / MEDIA_PUBLIC_BASE_URL
# (SUPABASE_* đã có trong .env.local, để trống cũng được)
```

Kiểm tra tổng thể — **không ghi gì vào DB hay R2 ngoài 2 object probe tự xoá**:

```bash
npm run r2:preflight
```

Script chứng minh, theo thứ tự: file khoá đúng quyền → Supabase có migration 153 →
token R2 ghi/đọc/xoá được ở **cả hai** bucket → **presigned PUT** (đúng đường trình duyệt dùng)
được chấp nhận → domain riêng phục vụ object với header `immutable` → staging **không**
truy cập được từ domain công khai → CORS trả đúng origin web → purge token chạy.
Chỉ khi mọi dòng là ✓ mới đi tiếp.

## Bước 3 — Copy dữ liệu

```bash
# 1) xem trước, không tải, không ghi
node scripts/migrate-media-to-r2.mjs

# 2) copy thử MỘT event, kiểm tra ảnh trên web
node scripts/migrate-media-to-r2.mjs --apply --event-ids <event-id>

# 3) copy toàn bộ phần đủ điều kiện
node scripts/migrate-media-to-r2.mjs --apply --all
```

Mỗi object được: tạo 3 biến thể (`thumb` ≤320px, `card` ≤800px, `full` ≤1600px) →
PUT lên bucket public → **đọc lại và so sha256** → chỉ khi khớp mới set `r2_ref` →
đánh dấu `published`. Ảnh lỗi được ghi vào `.migration-state/media-r2.jsonl` và bỏ qua,
chạy lại sẽ tiếp tục từ chỗ dở (resumable).

Bất biến của script:

- **Không** xoá, không ghi đè object Supabase; **không** sửa `storage_path`/`cover_image`/`avatar_path`.
- Chỉ copy event `status ∈ (live, ended, cancelled)` **và** `visibility = 'public'`, cùng avatar organizer.
- Không bao giờ copy draft/review/invite-only, stories, chat, dispute, payment/refund, QR, avatar user
  (user avatar có script copy riêng, mục 3b).
- Ghi `r2_ref` bằng compare-and-set trên `storage_path` cũ: row đổi giữa chừng thì bỏ qua.

### Bước 3b — Copy user avatar (bucket `avatars`)

```bash
node scripts/migrate-user-avatars-to-r2.mjs             # dry-run
node scripts/migrate-user-avatars-to-r2.mjs --apply     # copy + đổi profiles.avatar_url
export APP_ORIGIN=http://127.0.0.1:5173
node scripts/sweep-app-media.mjs                         # 0 request supabase.co/storage
```

Script chỉ đụng `profiles.avatar_url` (data-only), giữ nguyên object Supabase; key R2 chứa sha256 nên
chạy lại idempotent. Rollback: `node scripts/migrate-user-avatars-to-r2.mjs --rollback --apply`.
Không thêm cột/migration, không đổi iOS.

Sau khi chạy, kiểm tra lại:

```bash
npm run r2:preflight        # mục "already published on R2" phải bằng số vừa copy
npm run r2:verify           # coverage 126/126 + 35/35 + 16/16 + 2/2 user avatar
npm run r2:sweep            # sweep 9 route, 0 Supabase Storage
```

## Bước 4 — Bật đọc trên web

Vercel → Project → Settings → Environment Variables (Production):

| Biến | Giá trị |
|---|---|
| `VITE_MEDIA_PUBLIC_BASE_URL` | `https://media.banbe.app` |
| `VITE_MEDIA_R2_READS` | `1` |

`VITE_*` là **build-time** → phải **Redeploy**. Trong lúc chưa deploy lại, web vẫn đọc Supabase.

Tắt lại (rollback đọc): đặt `VITE_MEDIA_R2_READS=0` rồi redeploy — client bỏ qua `r2_ref`
ngay, ảnh event/organizer quay về bản Supabase (vẫn còn nguyên). **User avatar là ngoại lệ**:
`profiles.avatar_url` đã là URL R2 trực tiếp, nên flag đọc không đổi nó; muốn quay lại phải chạy
`node scripts/migrate-user-avatars-to-r2.mjs --rollback --apply` (script giữ nguyên object R2).

## Bước 5 — Bật upload qua R2 (sau cùng, tuỳ chọn)

Chỉ làm khi bản web hiện tại (và bản iOS đã phát hành) đọc được `r2_ref`. Ảnh upload
qua R2 có `storage_path = r2_ref`, build cũ hơn sẽ không hiển thị ảnh đó.

Thêm vào Vercel (server-side):

```
R2_ACCOUNT_ID=…
R2_ACCESS_KEY_ID=…
R2_SECRET_ACCESS_KEY=…
R2_PUBLIC_BUCKET=banbe-media-public
R2_STAGING_BUCKET=banbe-media-staging
MEDIA_PUBLIC_BASE_URL=https://media.banbe.app
CLOUDFLARE_ZONE_ID=…
CLOUDFLARE_PURGE_TOKEN=…
MEDIA_R2_UPLOADS=allowlist
MEDIA_R2_UPLOAD_USER_IDS=<uuid tài khoản của bạn>
MEDIA_UPLOADS_PER_HOUR=60
MEDIA_MAX_PENDING=24
```

Rồi **Redeploy**. `allowlist` = chỉ tài khoản trong danh sách được upload R2; mọi người
khác vẫn đi đường Supabase cũ. Khi ổn mới đổi sang `percent` rồi `on`.

`CRON_SECRET` phải đang set (job `media-sweep` fail-closed nếu thiếu): job chạy 10:45 hằng ngày,
tự unpublish ảnh R2 của event không còn public (chuyển sang invite-only, withdraw, xoá) và dọn
upload dở.

**iOS** (khi muốn iOS đọc R2): điền `MEDIA_PUBLIC_BASE_URL` + `MEDIA_R2_READS = 1` trong
`apps/ios/project.yml`, chạy `xcodegen generate`, build bản mới. Không cần migration.

## Bước 6 — Rollback

| Mức | Cách | Kết quả |
|---|---|---|
| Đọc | `VITE_MEDIA_R2_READS=0` + redeploy | Web dùng lại Supabase cho event/organizer; user avatar cần script rollback riêng |
| Upload | `MEDIA_R2_UPLOADS=off` + redeploy | Upload mới về Supabase |
| Tham chiếu | `node scripts/migrate-media-to-r2.mjs --rollback --apply` | Null `*_r2_ref` cho asset đã migrate; object R2 vẫn nằm đó, Supabase không đổi |
| User avatar | `node scripts/migrate-user-avatars-to-r2.mjs --rollback --apply` | Trả `profiles.avatar_url` về URL Supabase gốc; object R2 vẫn còn |

Chỉ sau khi chắc chắn (vài tuần, egress Supabase giảm) mới cân nhắc xoá bản Supabase —
việc đó **không** nằm trong runbook này.

## Ghi chú vận hành

- Upload đi thẳng từ browser/iOS → R2 bằng presigned PUT 5 phút, bytes **không** qua Vercel
  lẫn Supabase; finalize chỉ đọc lại ≤3 ảnh nhỏ để xác thực magic bytes/kích thước và bóc EXIF/GPS.
- Ảnh đã publish dùng URL bất biến (`/v1/<scope>/<uuid>/<variant>.<ext>`) nên cache 1 năm;
  sửa ảnh = object mới, không ghi đè.
- Lỗi thường gặp ở preflight:
  - `R2_PUT_403` → token không đúng bucket, sai bucket name, hoặc thiếu Object Read & Write.
  - presigned PUT 403 → đồng hồ máy lệch (SigV4 ký theo giờ) hoặc secret sai.
  - `public domain serves` fail → domain chưa **Active**, record `media` cũ chưa xoá, hoặc đang để `r2.dev`.
  - domain trả 525/522 → record `media` cũ chưa xoá hoặc chưa Connect domain.
  - CORS fail → `AllowedOrigins` thiếu đúng origin (có/không `www`), hoặc chưa bấm **Save**.
  - purge warning → token thiếu quyền **Cache Purge** (không phải Cache Rules).

## Event nhân bản dùng chung một ảnh

`media_assets_legacy_uq` chỉ cho **một** asset cho mỗi `(legacy_bucket, legacy_path)`, và
trigger `guard_r2_ref` bắt `r2_ref` mang đúng scope `ev-<event_id>` của chính hàng đó.

Script xử lý bằng **legacy_path có scope**: khi object đã có asset của một event khác, bản
clone được ghi với `legacy_path = "<path>#<scope>"` (ví dụ
`event-photos/vuonsau/DSCF4212.jpg#ev-canhchua`) trong khi bytes vẫn tải từ `path` thật.
Nhờ vậy mỗi event có asset và ref riêng, **không cần đổi schema**, và chuyển private/xoá
asset của event này không ảnh hưởng event kia. `legacy_path` chỉ dùng cho dedupe/audit của
script — không chỗ nào trong `api/` đọc nó.

Tính đến 2026-11-21: **141 media_assets published** (125 event photo + 16 organizer avatar),
phủ **126/126** ảnh event public, **35/35** cover, **16/16** avatar organizer, cộng **2/2 user avatar**
copy riêng. Những gì còn trong backlog **không phải clone**:

- 4 ảnh của event `banrieng` (`visibility: invite`) — không public nên ngoài phạm vi chuyển.
- 3 object gốc avatar trong bucket `avatars` (2 bản giữ rollback + 1 mồ côi) — object Supabase không bị xoá.
- Object mồ côi trong bucket (54 event-photos, 27 organizer-photos, 1 avatar; cùng các bucket private)
  — không hàng nào tham chiếu, không trang public nào phục vụ.

Chạy lại `--apply --all` phải báo `migrated: 0`; `to copy: 4` là đúng, không phải lỗi.
Dùng `npm run r2:verify` để kiểm tra coverage + HTTP + sha256 bản gốc.

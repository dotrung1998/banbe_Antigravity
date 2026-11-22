# Cloudflare / SePay / Supabase-as-backup — trạng thái thực tế

Cập nhật 2026-11-21. Tài liệu này không còn là kế hoạch: nó ghi việc đã chạy thật, số đo thật,
bằng chứng khôi phục, và đúng những gì còn thiếu.

## 0. Kết luận ngắn

| Việc | Trạng thái |
|---|---|
| SePay trong code | Xong (`api/payment-webhook.js`, `?provider=sepay`) |
| SePay trên một origin HTTPS công khai | **Đã kiểm chứng**: HMAC đã ký → HTTP 200 `{"success":true}` → row `payment_webhook_events` có `signature_ok=true` |
| Job backup Supabase → R2 | **Đã chạy thật**, archive 237.1 MB, đọc lại từ R2 khớp sha256 |
| Restore file backup vào Postgres tạm | **Đã chạy thật**, số row khớp nguồn (kể cả `auth.users`) |
| Ảnh public event/organizer | **Đã sang R2**: 126/126 ảnh event, 35/35 cover, 16/16 organizer; **0** ảnh public event/organizer còn từ Supabase trên origin đã build R2 |
| Ảnh user avatar (bucket `avatars`) | **Đã copy sang R2**: 2/2 avatar còn Supabase đã đổi `profiles.avatar_url`; bản gốc Supabase giữ nguyên; 1 object mồ côi |
| Production web | Bundle production cũ còn **5 request ảnh Supabase** (3 browse + 1 event + 1 organizer); bản local đã **0**; cần redeploy web để production về 0 |
| DB / Storage so với gói Free | 96 MB / 500 MB và 247 MB / 1 GB → **đạt** |
| Egress so với gói Free | Chưa đọc được số tháng này; ảnh public + user avatar đã rời Supabase, ước tính **dưới 5 GB** (xem 2b) |
| Hạ gói Free ngay? | **Được, sau 2 việc bắt buộc**: redeploy web fix avatar + tạo bucket backup riêng. Ảnh public không còn chặn. |
| Cloudflare làm hệ thống chính (D1/Better Auth) | **Spike local đã pass; production chưa migrate.** Không nên làm chỉ để tiết kiệm tiền (xem mục 6 và `docs/cloudflare-d1-better-auth-migration.md`) |

## 1. Bằng chứng chạy thật (2026-11-21)

### 1a. Backup

Lệnh:

```bash
node scripts/backup-supabase-to-r2.mjs --keep 30
```

Kết quả:

| Trường | Giá trị |
|---|---|
| Thời điểm | 2026-11-21T10:40:39Z |
| Object | `backups/2026-11-21T10-40-39-072Z/banbe-backup.tar.gz` |
| Bucket | `banbe-media-staging` (private) — xem cảnh báo ở mục 5 |
| Dung lượng archive | 248.662.304 bytes (237.1 MiB) |
| sha256 | `d4f9a1e01bb065c5cb97a978489222cbd0e366e7a480bac4e44369b78ce2f4ec` |
| Đọc lại từ R2 | 248.662.304 bytes, **sha256 khớp manifest** |
| Manifest | `backups/2026-11-21T10-40-39-072Z/manifest.json` |
| Index | `backups/index.json`, 1 entry |
| Storage | 552 object / 13 bucket / 258.955.505 bytes (247.0 MiB) |
| Database | 120 bảng public, 27 bảng auth |

Số row trong manifest lúc backup:

```json
{"profiles":14,"bookings":41,"payment_audit_log":90,"payment_webhook_events":1,
 "payment_documents":0,"events":36,"event_photos":130,"auth_users":14}
```

### 1b. Restore drill

File dump lấy từ chính archive trên, restore vào Postgres 17.11 trong Docker
(`public.ecr.aws/supabase/postgres:17.11.0.002`), database mới `banbe_restore`.

| Bảng | Nguồn lúc backup | Bản restore | Khớp |
|---|---:|---:|---|
| `profiles` | 14 | 14 | ✓ |
| `bookings` | 41 | 41 | ✓ |
| `payment_audit_log` | 90 | 90 | ✓ |
| `payment_webhook_events` | 1 | 1 | ✓ |
| `payment_documents` | 0 | 0 | ✓ |
| `events` | 36 | 36 | ✓ |
| `event_photos` | 130 | 130 | ✓ |
| `auth.users` | 14 | 14 | ✓ |

Row SePay trong bản restore:

```text
provider=sepay  external_id=preview-1795257571703  signature_ok=t  match_status=no_match  amount_vnd=1000
```

Không có lỗi restore ở public schema hay data. Auth schema có đúng 3 lỗi có chủ đích:
các trigger `on_auth_phone_confirmed`, `on_auth_user_created`, `on_auth_user_deleted`
gọi hàm `public.*` được tạo sau đó; drill tạo lại 3 trigger này sau khi restore public schema
(xem mục 4).

### 1c. SePay trên origin HTTPS công khai

- Chạy đúng handler `api/payment-webhook.js` trong một HTTP server local, expose bằng
  Cloudflare Quick Tunnel (`https://port-constitution-recreation-strategic.trycloudflare.com`).
- Gửi payload dạng SePay, ký HMAC-SHA256 trên `${timestamp}.${rawBody}`, headers
  `X-SePay-Signature`, `X-SePay-Timestamp`.
- Phản hồi: **HTTP 200** `{"success":true,"ok":true,"processed":1,"matched":0,...}`
- Row thật trong production:

```text
id=ada1c53c-ba42-4c94-9a97-c9ff02446784
provider=sepay  external_id=preview-1795257571703
signature_ok=true  match_status=no_match  amount_vnd=1000
```

`no_match` là đúng: memo cố ý không chứa mã `ART####`, nên không có booking nào bị xác nhận.
Đây là row test; có thể xoá bằng tay nếu muốn, nhưng nó cũng là bằng chứng trong backup.

Lưu ý: đây là **preview qua tunnel**, không phải domain Vercel production. Muốn kiểm chứng
trên production: đặt `SEPAY_WEBHOOK_SECRET` (hoặc `SEPAY_API_KEY`) trong Vercel, trỏ webhook
SePay tới `https://<domain>/api/payment-webhook?provider=sepay`, bấm **Gửi thử** trên SePay,
rồi kiểm tra `payment_webhook_events`.

## 2. Số đo dung lượng so với gói Free

Đo ngày 2026-11-21:

| Hạng mục | Thực tế | Giới hạn Free | Kết luận |
|---|---:|---:|---|
| Database | **96 MB** | 500 MB | Đạt (19%) |
| Storage | **247.0 MiB** (552 object) | 1 GB | Đạt (~25%) |
| — public media buckets (event-photos, organizer-photos, avatars) | 146.2 MiB | — | **141 media_assets + 2 user avatar đã copy sang R2**; còn 4 ảnh invite + 3 object gốc avatar (2 giữ rollback + 1 mồ côi) + object mồ côi khác |
| — private media (proof, chat, stories, documents…) | 100.8 MiB | — | Ở lại Supabase |
| Egress | **chưa đọc được số tháng này** | 5 GB + 5 GB cached | **Đã xử lý phần lớn**; ước tính dưới 5 GB |
| Auth | 14 user | 50.000 MAU | Đạt |

Ảnh public đã rời Supabase: **126/126** ảnh của event public, **35/35** cover, **16/16** avatar
organizer có `r2_ref`, và **2/2** user avatar đã đổi `profiles.avatar_url` sang R2; `npm run r2:verify`
trả **0 public event/organizer media** và **0 user avatar** còn served from Supabase. R2 HTTP sample
**11/11** trả `200 image/jpeg` với `Cache-Control: immutable`; **11/11** bản gốc Supabase vẫn còn
và khớp sha256 (gồm 2 avatar user).

Note 22 từng đo **~16 GB trong một chu kỳ** trước tối ưu; note 28 xác định ảnh public là nguồn tải
chính. Nay các lượt xem Home/Event/Profile lấy ảnh từ R2 (egress R2 miễn phí), nên phần egress còn lại
của Supabase là private media, API/DB và 4 ảnh invite.

Ước tính có căn cứ, dùng byte size đo thật ở mục 2b:

- Home cold: ~14 card × 0,13 MB + 3 full × 0,5 MB + avatar 0,02 MB ≈ **3,3 MB/lượt**, tất cả R2.
- Event detail: 3 full × 0,5 MB + 3 card × 0,13 MB + avatar 0,02 MB ≈ **1,9 MB/lượt**, tất cả R2.
- 1.000 lượt event/chu kỳ ≈ **1,9 GB R2, 0 GB Supabase**. 5 GB Free còn nguyên cho private media/API.
- 16 GB cũ tương đương ~100 lượt tải toàn bộ 146 MiB public; nay phần đó về 0. Nếu 4 ảnh invite
  bị tải 30 lần toàn bộ mới ~4,4 GB, nhưng thực tế chỉ là phần nhỏ.

R2 object có `Cache-Control: public, max-age=31536000, immutable`, nên lượt xem lại gần như không
tốn egress; Supabase không còn phục vụ ảnh public event/organizer. Đây vẫn là **ước tính**, chưa phải
số Dashboard vì máy không có `SUPABASE_ACCESS_TOKEN`.

**Kết luận:** DB/Storage đạt; egress do ảnh public đã được cắt. Hạ Free được sau khi redeploy bản web
có fix avatar và tạo bucket backup riêng.

### 2b. Ảnh public trên R2 — bằng chứng 2026-11-21

**Preflight** (`npm run r2:preflight`): 15/15 pass. `media.banbe.app` trả object probe
`HTTP 200, image/png, immutable`; staging không public; presigned PUT 200; CORS đúng origin;
purge token chạy. Có **141 media_asset published** (125 event photo + 16 organizer avatar), cộng
**2 user avatar** copy riêng sang `v1/user-avatars/...`.

**Coverage** (`npm run r2:verify`):

| Nhóm | Có `r2_ref` | Thiếu | Ghi chú |
|---|---:|---:|---|
| Ảnh event public | 126/126 | 0 | 125 asset; một asset dùng cho 2 hàng |
| Cover event public | 35/35 | 0 | tất cả event public có cover |
| Avatar organizer | 16/16 | 0 | toàn bộ organizer có avatar |
| User avatar | 2/2 | 0 | `profiles.avatar_url` đã là URL R2; bản gốc Supabase giữ rollback |
| Media public event/organizer còn từ Supabase | — | **0** | điều kiện Done |

**HTTP thật**, sample 11 URL trải trên event photo (full), cover (card), organizer avatar (thumb)
và user avatar: 11/11 `HTTP 200`, `image/jpeg`, `Cache-Control: public, max-age=31536000, immutable`;
byte size 0,33–0,69 MB cho `full`, 0,12–0,14 MB cho `card`, 0,02 MB cho `thumb`, 0,70–0,99 MB cho
user avatar. 11/11 bản gốc Supabase download lại được và **sha256 khớp** — đây là copy, không phải move.

**Origin app đã chạy (local, build R2)**: Vite `http://127.0.0.1:5173` với
`VITE_MEDIA_PUBLIC_BASE_URL=https://media.banbe.app` + `VITE_MEDIA_R2_READS=1`. Sweep
`scripts/sweep-app-media.mjs` ghi **toàn bộ request ảnh** trên 9 route, sau khi Home được mở ở chế
độ khách và trang cuộn để tải ảnh lazy:

| Route | Ảnh | R2 | Supabase | Local (bundle) | External |
|---|---:|---:|---:|---:|---:|
| `/` Home/feed | 24 | 11 | **0** | 13 | 0 |
| `/browse` | 26 | 14 | **0** | 12 | 0 |
| `/search` | 42 | 14 | **0** | 28 | 0 |
| `/map` | 28 | 16 | **0** | 11 | 1 (map sprite) |
| `/event/dembass` | 28 | 15 | **0** | 13 | 0 |
| `/org/org_a96236c5` | 32 | 31 | **0** | 1 | 0 |
| `/u/tdk404` | 2 | 1 | **0** | 1 | 0 |
| `/u/banbetestadmin` | 2 | 1 | **0** | 1 | 0 |
| `/profile` (khách) | 11 | 0 | **0** | 11 | 0 |

Không còn request nào tới `*.supabase.co/storage`. Các file `local` là ảnh demo đóng gói trong
bundle (`public/photos`, wordmark), không phải Supabase; `map sprite` là tile style của OpenFreeMap.
Chi tiết trong `tmp/app-media-sweep.json`.

**Production `https://www.banbe.app`** (bundle cũ, chưa redeploy): sweep vẫn thấy **5 request
Supabase**, tất cả là avatar organizer cũ:

- `/browse`: `organizers/org_a96236c5/...`, `org_bepnho/v23-avatar-20261113.jpg`,
  `org_sonmai/v23-avatar-20261113.jpg` — 3 request.
- `/event/dembass`: `org_a96236c5/...` — 1 request.
- `/org/org_a96236c5`: `org_a96236c5/...` — 1 request.
- `/u/tdk404`, `/u/banbetestadmin`: **0** Supabase (URL `profiles.avatar_url` đã đổi sang R2, bundle
  cũ đọc thẳng URL này); `/` Home của bundle cũ cũng 0.

Đây là **bundle cũ**, không phải code hiện tại: local đã có fix cho cả `openOrganizerProfile`
(merge `avatar_r2_ref` sau `get_organizer_profile`), `loadEventOrgStats`, Home discovery và
`loadOrganizerProfileExtras`. Cần **redeploy web** để production hết 5 request này.

**Ngoại lệ đã liệt kê, không phải ảnh public event/organizer**:

- **4 ảnh của `banrieng`** (event `live` nhưng `visibility='invite'`) — cố ý không đưa lên R2 public;
  đây là bucket public từ trước, không phải ảnh public của app.
- **3 object gốc trong `avatars`**: 2 object của 2 user avatar đã copy sang R2 và **giữ nguyên** để
  rollback; 1 object `12fea83f-.../1790516849241.jpeg` mồ côi (profile `tdk202` có `avatar_url` rỗng).
  Upload avatar **mới** vẫn đi Supabase vì `MEDIA_R2_UPLOADS=off`.
- **4 profile avatar external** (Unsplash/seed) hoặc rỗng — không nằm trong Supabase Storage, không tạo
  egress Supabase; không phải ảnh event/organizer/user avatar đã chuyển.
- **54 object mồ côi** trong `event-photos`, **27** trong `organizer-photos`, **1** trong `avatars`
  — không hàng nào tham chiếu, không trang public nào phục vụ.

**Audit 13 bucket (referenced vs orphan, 2026-11-21)**: `npm run r2:verify` liệt kê đủ 13 bucket,
không chỉ event/organizer. `dbRefs` là số path **distinct** lấy từ đúng cột DB; `missing` là path DB
không còn object; `orphan` là object không còn path DB (đã trừ `kept` = bản gốc avatar giữ rollback).

| Bucket | Access | Object | Dung lượng | DB refs | Missing | Orphan | Kept | Route render |
|---|---|---:|---:|---:|---:|---:|---:|---|
| `event-photos` | public | 139 | 123.0 MiB | 85 | 0 | 54 | 0 | Home/feed, Event gallery + cover, Search/Map, organizer profile, photo-share |
| `pay-qr` | private | 1 | 0.4 MiB | 3 | 2 | 0 | 0 | Reserve/Payment host QR (signed) |
| `pay-proof` | private | 134 | 41.6 MiB | 13 | 0 | 121 | 0 | Payment details/host verification/dispute email |
| `payment-documents` | private | 29 | 6.0 MiB | 0 | 0 | 29 | 0 | Documents (owner/admin) |
| `chat-attachments` | private | 194 | 32.3 MiB | 0 | 0 | 194 | 0 | Chat thread attachments |
| `stories` | private | 2 | 8.1 MiB | 1 | 1 | 2 | 0 | Story viewer (signed) |
| `avatars` | public | 3 | 1.8 MiB | 0 | 0 | 1 | 2 | Profile/Public profile/Account/Inbox/Team avatar |
| `organizer-photos` | public | 43 | 21.4 MiB | 16 | 0 | 27 | 0 | Home host avatar, Event host, Organizer profile |
| `event-photos-private` | private | 0 | 0 | 0 | 0 | 0 | 0 | Event host/invite-only (signed) |
| `refund-qr` | private | 0 | 0 | 0 | 0 | 0 | 0 | Refund destination QR |
| `refund-proof` | private | 2 | 3.9 MiB | 1 | 0 | 1 | 0 | Disputes/refund proof |
| `dispute-attachments` | private | 5 | 8.5 MiB | 2 | 0 | 3 | 0 | Dispute chat/export |
| `keychain-art` | private | 0 | 0 | 0 | 0 | 0 | 0 | Profile keychain custom art (signed) |

Tổng: **552 object / 247.0 MiB**, trong đó 432 object mồ côi (chủ yếu proof/chat cũ) và 3 missing
ref. `event-photos` có 85 path distinct vì 130 hàng ảnh của event bị clone dùng lại cùng object;
126/126 ảnh public vẫn có `r2_ref`. Hai missing đáng chú ý (không phải egress public):
`pay-qr/org_001/qr.jpg`, `pay-qr/org_002/qr.jpg` (DB còn path cũ, bucket chỉ có
`org_a96236c5/qr-1791023345.jpg`); `stories` còn `org_phong302/e2e-dock-test.jpg` nhưng bucket chỉ
có 2 object `org_jazzgac/...` — story cũ, không route public nào phục vụ.

**Upload mới:** `MEDIA_R2_UPLOADS=off`, nên ảnh public upload **mới** vẫn đi đường Supabase cũ.
Muốn không tái phát egress, bật `allowlist` → `percent` → `on` trong Vercel sau khi bản web/iOS tối
thiểu đều đọc được `r2_ref` (xem checklist).

## 3. Job backup: cách chạy và lịch

### Thủ công

```bash
npm run backup:supabase
# hoặc
node scripts/backup-supabase-to-r2.mjs --keep 30
```

### Theo lịch

`.github/workflows/backup-supabase.yml`: chạy 02:17 UTC mỗi ngày và có `workflow_dispatch`.
Dùng GitHub Actions vì repo đã có workflow; không thêm dịch vụ mới.

Secrets cần đặt trong GitHub → Settings → Secrets and variables → Actions:

| Secret | Dùng để |
|---|---|
| `SUPABASE_URL` | project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | đọc Storage + đếm row |
| `SUPABASE_DB_URL` | `supabase db dump --db-url` (bắt buộc trên CI) |
| `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | ghi R2 |
| `R2_PUBLIC_BUCKET`, `R2_STAGING_BUCKET` | cấu hình R2 hiện có |
| `R2_BACKUP_BUCKET` | bucket backup riêng (khuyến nghị `banbe-backups`) |

Job giữ 30 bản gần nhất qua `backups/index.json`; mỗi lần chạy ghi manifest có
timestamp, kích thước, sha256, số bảng, số row, số object/byte Storage và đường dẫn object.

## 4. Restore từ R2 (runbook)

### 4a. Tải và giải nén

```bash
node scripts/backup-supabase-to-r2.mjs \
  --download backups/2026-11-21T10-40-39-072Z/banbe-backup.tar.gz \
  --out tmp/restore
cd tmp/restore && tar -xzf banbe-backup.tar.gz
# database/schema-public.sql, database/data-public.sql,
# database/schema-auth.sql,   database/data-auth.sql,
# storage/<bucket>/..., storage-manifest.json, manifest.json
```

Đối chiếu `sha256` trong `manifest.json` với file vừa tải trước khi dùng.

### 4b. Dựng Postgres tạm

```bash
docker run -d --name banbe-restore \
  -e POSTGRES_PASSWORD=restoreonly -p 55432:5432 \
  public.ecr.aws/supabase/postgres:17.11.0.002

docker exec banbe-restore createdb -U supabase_admin banbe_restore
docker exec -i banbe-restore psql -U supabase_admin -d banbe_restore -v ON_ERROR_STOP=1 <<'SQL'
create schema if not exists extensions;
create extension if not exists pgcrypto schema extensions;
create extension if not exists "uuid-ossp" schema extensions;
create extension if not exists pg_trgm schema extensions;
SQL
docker exec banbe-restore mkdir -p /tmp/backup
docker cp database/. banbe-restore:/tmp/backup
```

`supabase_admin` là superuser của image này; `postgres` không phải owner của schema `auth`.

### 4c. Thứ tự restore (quan trọng)

```bash
# 1. auth schema: 3 trigger sẽ lỗi vì hàm public chưa tồn tại — tiếp tục
docker exec banbe-restore psql -U supabase_admin -d banbe_restore \
  -v ON_ERROR_STOP=0 -f /tmp/backup/schema-auth.sql

# 2. public schema (tạo hàm public.* và toàn bộ bảng/policy)
docker exec banbe-restore psql -U supabase_admin -d banbe_restore \
  -v ON_ERROR_STOP=1 -f /tmp/backup/schema-public.sql

# 3. tạo lại 3 trigger auth
docker exec -i banbe-restore psql -U supabase_admin -d banbe_restore -v ON_ERROR_STOP=1 <<'SQL'
CREATE OR REPLACE TRIGGER "on_auth_phone_confirmed" AFTER UPDATE OF "phone_confirmed_at"
  ON "auth"."users" FOR EACH ROW WHEN (("new"."phone_confirmed_at" IS NOT NULL))
  EXECUTE FUNCTION "public"."sync_phone_verification"();
CREATE OR REPLACE TRIGGER "on_auth_user_created" AFTER INSERT ON "auth"."users"
  FOR EACH ROW EXECUTE FUNCTION "public"."handle_new_user"();
CREATE OR REPLACE TRIGGER "on_auth_user_deleted" AFTER DELETE ON "auth"."users"
  FOR EACH ROW EXECUTE FUNCTION "public"."handle_deleted_user"();
SQL

# 4. data
docker exec banbe-restore psql -U supabase_admin -d banbe_restore \
  -v ON_ERROR_STOP=1 -f /tmp/backup/data-auth.sql
docker exec banbe-restore psql -U supabase_admin -d banbe_restore \
  -v ON_ERROR_STOP=1 -f /tmp/backup/data-public.sql
```

### 4d. Kiểm tra

```bash
docker exec banbe-restore psql -U supabase_admin -d banbe_restore -Atc "
select 'profiles',count(*) from public.profiles
union all select 'bookings',count(*) from public.bookings
union all select 'payment_audit_log',count(*) from public.payment_audit_log
union all select 'payment_webhook_events',count(*) from public.payment_webhook_events
union all select 'events',count(*) from public.events
union all select 'auth_users',count(*) from auth.users;"
```

So với `manifest.json` của đúng lần backup đó. Nếu khớp, file backup dùng được.

### 4e. File Storage

`storage/` chứa nguyên bytes theo `bucket/path`; `storage-manifest.json` có sha256 từng file.
Đưa lại vào Supabase Storage bằng dashboard/API (bucket private phải tạo lại policy), hoặc
đối chiếu từng file. Không có bước này thì DB restore xong vẫn thiếu ảnh/tài liệu.

### 4f. Khôi phục vào một Supabase project mới

- Tạo project mới, chạy `schema-public.sql` + `data-public.sql` qua SQL editor/`psql`.
- `auth` schema là schema hệ thống: restore `auth.users`/`identities` cần quyền cao;
  thử trên project staging trước, không thử trực tiếp trên project đang chạy.
- Cập nhật `VITE_SUPABASE_URL`, anon key, service role ở web/API/iOS sau khi đổi project.
- Đây là lý do **không** nên coi “Supabase chỉ để backup” là chuyện một nút bấm: một project
  Supabase mới vẫn cần auth schema, storage policy và URL mới.

## 5. Việc còn thiếu để backup bền vững

Job đã ghi được object thật, nhưng đang dùng **bucket staging private** vì token R2 hiện tại
chỉ có quyền object trên `banbe-media-public` và `banbe-media-staging`:

- `CreateBucket` → 403 AccessDenied
- `GetBucketLifecycle` / `PutBucketLifecycle` → 403 AccessDenied
- ghi vào `event-photos-private` → 403

Vì không đọc được lifecycle, **không thể chứng minh** object `backups/` sống quá 1 ngày.
Note 28 dự định bucket staging có lifecycle 1 ngày. Đây là rủi ro duy nhất của backup hiện tại.

Cách sửa (cần quyền của bạn, không phải secret trong chat):

1. Cloudflare Dashboard → R2 → **Create bucket** `banbe-backups` (private, không custom domain).
2. R2 → Manage API tokens → tạo token **Object Read & Write**, scope đúng `banbe-backups`
   (hoặc sửa token hiện tại để thêm bucket này).
3. Đặt trong `.r2-secrets.local` (và GitHub Secrets):
   `R2_BACKUP_BUCKET=banbe-backups`, cùng cặp access key mới nếu tạo token mới.
4. Chạy lại `npm run backup:supabase`; kiểm tra `manifest.json` có
   `"r2": {"bucket":"banbe-backups","fallback":false}`.
5. (Tuỳ chọn) đặt `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` với quyền
   **Workers R2 Storage: Edit** để quản lý lifecycle bằng script.

Cho đến bước 4, backup vẫn là **private** nhưng không được coi là bền vững.

## 6. Vì sao chưa chuyển Cloudflare làm hệ thống chính

Giữ nguyên kết luận trước, vì nó vẫn đúng và giờ có thêm số đo:

- 224 migration Postgres, hơn 140 điểm gọi RPC ở web, RLS, PL/pgSQL, `pg_cron`,
  `pg_net`, Vault, Storage, Realtime; iOS dùng chung Supabase Auth.
- D1 là SQLite: không RLS, không PL/pgSQL, không extension. Viết lại từng RPC + phân quyền
  là dự án 2–3 tháng, không phải một buổi.
- **D1 và Supabase Free đều $0**, nên viết lại không tiết kiệm thêm so với việc bật R2 +
  hạ Supabase Free. Nó chỉ mua sự độc lập khỏi Supabase, đổi bằng rủi ro thanh toán/hoàn tiền.
- Supabase Free **không có backup tự động** và **pause sau 1 tuần ít hoạt động**; vì vậy
  job backup này là điều kiện bắt buộc, không phải tuỳ chọn.

## 7. Checklist hạ gói Free

- [x] Ảnh public event/organizer + 2 user avatar đã copy sang R2; `npm run r2:verify` trả 0 public
      event/organizer và 0 user avatar còn Supabase.
- [x] Audit đủ 13 bucket (referenced vs orphan) và route sweep local 9 route: 0 request
      `*.supabase.co/storage`.
- [ ] Redeploy web có fix `openOrganizerProfile` + `loadEventOrgStats` + Home discovery; production
      phải hết 5 request avatar Supabase (3 browse, 1 event, 1 organizer).
- [ ] Bật R2 uploads (`MEDIA_R2_UPLOADS=allowlist` → `percent` → `on`) để ảnh mới không quay lại
      Supabase; chỉ làm khi bản web/iOS tối thiểu đều đọc được `r2_ref`.
- [ ] Tạo `banbe-backups` + token, đặt `R2_BACKUP_BUCKET`, chạy lại job, đọc lại sha256 khớp.
- [ ] Theo dõi egress một chu kỳ; mục tiêu < 5 GB (cached + uncached), xem Dashboard → Reports.
- [ ] Chạy lại backup sau khi đổi ảnh; archive mới phải restore được.
- [ ] Restore drill từ archive mới nhất; số row khớp.
- [ ] Xác nhận DB < 500 MB, Storage < 1 GB trên Dashboard → Usage.
- [ ] Hạ organization xuống Free (lưu ý cả 2 project đang active đều bị ảnh hưởng).
- [ ] Giữ lịch GitHub Actions; bật cảnh báo khi job fail (GitHub notifications).
- [ ] Ghi lại cách unpause: Dashboard → project → **Resume project**; dữ liệu được giữ,
      project pause sau 1 tuần ít hoạt động. Đừng để job backup là hoạt động duy nhất.

**Kết luận hạ gói:** DB 96/500 MB và Storage 247/1000 MiB đạt; ảnh public event/organizer và user
avatar đã sang R2 nên egress không còn do các ảnh đó. **Hạ được sau 2 việc bắt buộc**: redeploy web
(để production hết 5 request avatar Supabase) và tạo bucket backup riêng. Bật R2 uploads là để không
tái phát, không chặn việc hạ gói.

### Nếu project Supabase bị pause (Free)

1. Vào Supabase Dashboard → chọn project → nút **Resume project** (project paused vẫn giữ dữ liệu).
2. Chờ project chuyển sang Active, rồi kiểm tra một request thật (mở web hoặc chạy
   `npm run backup:supabase`).
3. Nếu không thấy nút Resume, kiểm tra organization còn ở Free và project chưa bị xoá;
   project Free pause sau 1 tuần ít hoạt động, không phải mất dữ liệu ngay.
4. Sau khi resume, chạy lại backup và kiểm tra `payment_webhook_events`/login trước khi mở bán vé.

## 8. Việc đã/ chưa làm trong lượt này

Đã làm:
- `scripts/verify-r2-public-media.mjs` + `npm run r2:verify`: audit read-only **đủ 13 bucket**
  (object/bytes, DB refs, missing, orphan, retained originals, route render), HTTP sample và sha256
  bản gốc; kết quả 126/126 + 35/35 + 16/16 + **2/2 user avatar**, **0** public event/organizer và
  **0** user avatar còn Supabase; HTTP **11/11**, sha256 **11/11**.
- `scripts/migrate-user-avatars-to-r2.mjs`: copy 2 avatar Supabase sang R2 immutable key
  `v1/user-avatars/<profile>/<sha256>.jpg`, verify sha, compare-and-set `profiles.avatar_url`;
  dry-run mặc định, `--apply`, `--rollback`; chạy lại `--apply` = 0 target. Bản gốc Supabase giữ nguyên.
- Fix `src/state/BanBeContext.jsx`: `loadEventOrgStats`, `openOrganizerProfile`, hai shared-link
  effect và Home discovery cùng đọc/merge `organizers.avatar_r2_ref`; không đổi RPC/RLS/auth.
- `scripts/sweep-app-media.mjs` + `npm run r2:sweep`: Playwright sweep 9 route (Home/feed, browse,
  search, map, event, organizer, 2 public profile, profile guest), ghi `tmp/app-media-sweep.json`;
  local **0** request `*.supabase.co/storage` (47 URL R2 unique).
- `npm run r2:preflight`: 15/15 pass; `npm run build` (R2 flags): pass; `npm run test:unit`:
  **1062/1062 pass**; `git diff --check`: pass.
- Backup/restore/SePay: giữ nguyên bằng chứng đã có ở mục 1; không chạy lại migration phá huỷ.
- Cập nhật tài liệu này + `docs/r2-migration-runbook.md` + `.claude/notes/28-r2-hybrid-media.md`.

Chưa làm:
- Chưa redeploy production web; bundle cũ còn **5 request avatar Supabase** (3 browse, 1 event,
  1 organizer). Không cần env mới: production đã có `VITE_MEDIA_R2_READS=1` và base URL.
- `MEDIA_R2_UPLOADS` vẫn `off`: ảnh public/user avatar upload **mới** còn đi Supabase.
- Chưa tạo được bucket `banbe-backups` (token R2 hiện tại 403; xem mục 5).
- 4 ảnh invite-only (`banrieng`) vẫn ở Supabase có chủ đích; 2 object gốc avatar được giữ để rollback,
  1 object avatar mồ côi; không xoá gì.
- Chưa deploy web/API lên Cloudflare Workers; API vẫn là các hàm Node trên Vercel.
- Chưa kiểm chứng SePay trên domain production (chỉ preview tunnel).

### File đã thay đổi trong lượt này

- `src/state/BanBeContext.jsx` — đọc/merge `avatar_r2_ref` cho Event Detail, Organizer profile,
  shared `/org` + `?org=`, và Home discovery.
- `scripts/verify-r2-public-media.mjs` — verifier 13 bucket + user avatar.
- `scripts/migrate-user-avatars-to-r2.mjs` — copy/rollback user avatar.
- `scripts/sweep-app-media.mjs` — Playwright route/media sweep.
- `package.json` — thêm `r2:verify`, `r2:avatars`, `r2:sweep`.
- `docs/cloudflare-sepay-migration.md`, `docs/r2-migration-runbook.md`,
  `.claude/notes/28-r2-hybrid-media.md` — trạng thái/số đo/bằng chứng.
- Không sửa file iOS, không đổi auth/RLS/RPC, không commit secret.

### Credential / cấu hình còn thiếu

| Tên | Dán ở đâu | Chặn bước nào |
|---|---|---|
| `R2_BACKUP_BUCKET=banbe-backups` + R2 token scope đúng bucket | `.r2-secrets.local` và GitHub Secrets | backup bền vững (hiện dùng staging) |
| `SUPABASE_DB_URL` + các `R2_*` | GitHub → Settings → Secrets → Actions | chạy lịch backup trên GitHub |
| `SUPABASE_ACCESS_TOKEN` | chỉ local env, không commit | đọc egress thật qua Management API (hiện chỉ có service role) |
| `MEDIA_R2_UPLOADS=allowlist` + `MEDIA_R2_UPLOAD_USER_IDS=<uuid>` | Vercel → Production → Environment Variables, rồi redeploy | ảnh public upload mới không quay lại Supabase |
| `SEPAY_WEBHOOK_SECRET` (hoặc `SEPAY_API_KEY`) | Vercel → Production → Environment Variables | SePay trên domain production |
| Quyền deploy Vercel | tài khoản Vercel của bạn | redeploy fix avatar (production đang còn 5 request avatar Supabase) |
| Bucket `banbe-backups` + token trong R2 dashboard | Cloudflare → R2 → Create bucket / Manage API tokens | thay bucket staging có thể hết hạn |

Không có giá trị secret nào được ghi vào repo hay tài liệu này.

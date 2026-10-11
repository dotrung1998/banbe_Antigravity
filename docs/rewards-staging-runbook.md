# Rewards Giai đoạn 0 — runbook dựng và dùng Supabase staging RIÊNG

Mục đích: kiểm tra chuỗi migration 177 → 180 và client mới trên **một project Supabase riêng (staging)**, có PostgREST và GoTrue thật, trước khi được phép đụng production. Đây là việc harness Postgres local (`supabase/_localtest/`) **không** làm được. Đọc cùng [rewards-phase0-summary.md](rewards-phase0-summary.md) (mục 8) và [rewards-phase0-manual-checks.md](rewards-phase0-manual-checks.md).

> Tài liệu này chỉ **mô tả**. Người soạn không tạo project, không chạy lệnh nào ở đây, không chạm production, không đọc `.env` thật.

## Chú giải độ tin cậy

- **[ĐÃ KIỂM CHỨNG]** = đã xác nhận trong phiên soạn: đọc repo, hoặc đọc `--help` của Supabase CLI **2.120.0** cài trên máy này (`/opt/homebrew/bin/supabase`). Chỉ kiểm chứng sự tồn tại của cờ/tệp, **không** phải hành vi khi chạy thật.
- **[CHƯA KIỂM CHỨNG]** = cần một project staging thật mới biết (hành vi khi chạy, giao diện Dashboard, giới hạn gói miễn phí, thông báo lỗi). Khi làm, hãy ghi kết quả thật vào bằng chứng (mục 6) và sửa tài liệu này nếu khác.

---

## 0. Rào chắn an toàn (đọc trước, bắt buộc)

**[ĐÃ KIỂM CHỨNG] Thư mục repo này đang được `supabase link` vào PRODUCTION.** `supabase/.temp/project-ref` chứa mã dự án production, nên mọi lệnh dùng liên kết mặc định đều nhắm vào production: `supabase db push --linked`, `migration up --linked`, `db reset --linked`, `supabase functions deploy`, `supabase secrets set` không kèm `--project-ref`. Quy tắc cho runbook này:

1. **Không bao giờ dùng `--linked`.** Mọi lệnh DB dùng `--db-url "$STG_DB_URL"` (cờ có thật trong `db push`, `migration up`, `migration list`, `migration repair`; **[ĐÃ KIỂM CHỨNG]**).
2. Mọi lệnh functions/secrets dùng `--project-ref "$STG_REF"` **tường minh** (cờ có thật; **[ĐÃ KIỂM CHỨNG]**).
3. Chạy các lệnh DB từ **thư mục làm việc tạm** (`--workdir`, mục 2.3), không phải từ repo: thư mục tạm không có `.temp/project-ref` nên không thể vô tình dùng liên kết production. (`--workdir` có thật: "path to the directory containing your supabase/ folder"; **[ĐÃ KIỂM CHỨNG]**.)
4. **Chạy bộ kiểm tra bảo vệ trước MỌI phiên làm việc** (đặt trong shell, không commit):

```bash
# stg-guard.sh  — source this file; it aborts the shell step if anything points at production
: "${STG_REF:?set STG_REF to the STAGING project ref}"
: "${STG_URL:?set STG_URL=https://\$STG_REF.supabase.co}"
: "${STG_DB_URL:?set STG_DB_URL to the STAGING connection string (percent-encoded)}"
PROD_REF="$(cat "$(git rev-parse --show-toplevel)/supabase/.temp/project-ref" 2>/dev/null)"
if [ -n "$PROD_REF" ]; then
  [ "$STG_REF" != "$PROD_REF" ]            || { echo "STOP: STG_REF equals the linked PRODUCTION ref"; return 1 2>/dev/null || exit 1; }
  case "$STG_URL$STG_DB_URL" in *"$PROD_REF"*) echo "STOP: a staging value contains the PRODUCTION ref"; return 1 2>/dev/null || exit 1;; esac
fi
case "$STG_URL" in "https://$STG_REF.supabase.co") ;; *) echo "STOP: STG_URL is not https://\$STG_REF.supabase.co"; return 1 2>/dev/null || exit 1;; esac
echo "OK: staging = $STG_REF (not the linked production project)"
```

5. **Không bao giờ dùng khoá hay URL của production.** Khoá của staging (anon, service_role) lấy ở *Settings → API* của **project staging**. Khoá `service_role` của staging chỉ dùng ở máy bạn, không dán vào repo, `.env*` được commit, Vercel hay app. Không đổi gì ở Vercel (production) trong runbook này.
6. **Không sao chép dữ liệu production vào staging** (dữ liệu cá nhân). Staging chỉ có dữ liệu giả `@banbe-staging.test`.
7. `src/lib/supabase.js` và `apps/ios/.../SupabaseService.swift` có **URL và anon key production làm giá trị dự phòng cứng**: nếu biến môi trường thiếu thì app im lặng nói chuyện với production. Mục 4 có kiểm tra bắt buộc trước khi đăng nhập.

---

## 1. Tạo project staging

1. Dashboard Supabase → **New project**, **tổ chức/tài khoản của bạn**, **không phải** project production.
   - Tên rõ ràng: `banbe-staging-rewards-p0`. Chọn vùng gần production (xem vùng của production ở Dashboard).
   - Gói miễn phí. **[CHƯA KIỂM CHỨNG]** giới hạn gói miễn phí (số project hoạt động tối đa, tự tạm dừng khi không dùng, dung lượng, nhật ký): kiểm tra trên Dashboard; nếu project bị tạm dừng giữa chừng, khôi phục trước khi tiếp tục.
   - Mật khẩu DB: sinh ngẫu nhiên, **chỉ chữ và số** (tránh phải mã hoá phần trăm trong `--db-url`). Lưu trong trình quản lý mật khẩu, không để trong repo.
   - (Tuỳ chọn) bằng CLI: `supabase projects create "banbe-staging-rewards-p0" --org-id <ORG> --db-password <PW> --region <REGION>` (cờ **[ĐÃ KIỂM CHỨNG]**; lệnh **[CHƯA KIỂM CHỨNG]**; cần đăng nhập CLI).
2. **Ghi lại project ref** (chuỗi 20 ký tự trong URL Dashboard `.../project/<ref>`), đặt `STG_REF`. Xác nhận **khác** mã trong `supabase/.temp/project-ref` (script ở mục 0 làm việc này).
3. Lấy từ *Settings → API* của **staging**: `Project URL` (`https://<STG_REF>.supabase.co`), `anon` key, `service_role` key. Lấy chuỗi kết nối ở nút **Connect** (Dashboard): dùng chuỗi **pooler (session mode)** nếu mạng của bạn không có IPv6 cho kết nối trực tiếp. **[CHƯA KIỂM CHỨNG]** chuỗi chính xác; chép từ Dashboard, đừng tự ghép.
4. Đặt biến (trong shell, không ghi vào file trong repo):
   ```bash
   export STG_REF=<ref-staging>
   export STG_URL="https://$STG_REF.supabase.co"
   export STG_ANON="<anon key staging>"
   export STG_DB_URL="<connection string staging, percent-encoded>"
   source /path/to/stg-guard.sh      # phải in: OK: staging = <ref> (not the linked production project)
   ```
   `STG_SERVICE` (khoá service_role staging) chỉ đặt khi thật cần (mục 5.2, tạo người dùng); đặt xong thì `unset STG_SERVICE`.

---

## 2. Đưa staging về đúng trạng thái production (migration 1 → 176)

### 2.1 Cơ sở
Production đã áp dụng toàn bộ migration đến **176** (bạn xác nhận 169/169 trước Giai đoạn 0; repo hiện có 173 file: 169 file đến 176 + 177–180). Staging phải ở đúng 176 **trước** khi thử 177.

### 2.2 Những điểm cần lưu ý (đã đọc trong repo)
- **[ĐÃ KIỂM CHỨNG] `seed.sql` ở gốc repo bị hỏng** (`profiles.handle` NOT NULL; đồng thời `DELETE` bảng `profiles`) và `config.toml` bật nó cho `db reset`/`start`. Với staging **đừng chạy `db reset`** và **đừng dùng `--include-seed`**: `db push` mặc định **không** chạy seed (cờ `--include-seed` có thật và mặc định tắt; **[ĐÃ KIỂM CHỨNG]**). Nếu buộc phải `db reset --linked`-kiểu thao tác, dùng `--no-seed` (cờ có thật) và **chỉ trên staging** (nguy hiểm nhất: xoá sạch dữ liệu của project bị trỏ tới).
- **[ĐÃ KIỂM CHỨNG] Extension:** migration tự tạo `pg_cron` và `pgcrypto` (`CREATE EXTENSION IF NOT EXISTS`). **[CHƯA KIỂM CHỨNG]** `pg_cron` có tạo được trên project mới ngay không; nếu migration báo lỗi quyền, bật `pg_cron` ở *Database → Extensions* rồi chạy lại.
- **[ĐÃ KIỂM CHỨNG] Cron:** migration tạo ít nhất các job `bb_expire_not_found_bookings`, `bb_expire_stale_holds`, `bb_sweep_verification_slas`, `expire-stale-admin-invites`, `goc_stamp_refund_dispute_chat_conclusions` (và job kết thúc sự kiện hằng giờ ở migration 167). Sau khi áp dụng, kiểm tra `select jobname, schedule from cron.job order by 1;`. **[CHƯA KIỂM CHỨNG]** danh sách đầy đủ; so với production bằng mắt (hai danh sách phải khớp tên).
- **[ĐÃ KIỂM CHỨNG] Storage buckets:** migration tạo 12 lần `INSERT INTO storage.buckets`. Kiểm tra `select id, public from storage.buckets order by 1;` và so với production (chỉ tên và cờ `public`, không đọc object).
- **[ĐÃ KIỂM CHỨNG] `ALTER ROLE authenticator SET pgrst.db_pre_request = 'public.gate_pre_request'`** (migration 126): **mọi yêu cầu PostgREST đi qua một cổng kiểm tra tài khoản** (điện thoại đã xác minh + ngày sinh). Đây là lý do staging có giá trị: harness không có PostgREST nên cổng này chưa từng được chạy cùng RPC rewards. Sau khi áp dụng kiểm tra `select rolconfig from pg_roles where rolname = 'authenticator';`. **[CHƯA KIỂM CHỨNG]** `postgres` trên project mới đủ quyền `ALTER ROLE authenticator`.
- **Không nằm trong migration, staging cần cấu hình thêm** (**[CHƯA KIỂM CHỨNG]** cách làm trên Dashboard hiện tại):
  - *Authentication → URL Configuration:* `Site URL` và `Redirect URLs` (dùng `http://localhost:5173` cho web dev).
  - *Authentication → Providers → Email:* cho phép đăng nhập bằng mật khẩu; tắt "Confirm email" hoặc tạo người dùng đã xác nhận qua API admin (mục 5.2).
  - *Phone/SMS:* app dùng edge function `send-otp` (eSMS, **[ĐÃ KIỂM CHỨNG]** từ chú thích đầu file), không phải nhà cung cấp SMS của Supabase. Các kiểm tra rewards **không cần OTP**: tạo người dùng đã xác minh số điện thoại bằng API admin. Nếu muốn thử OTP: `supabase secrets set SMS_SANDBOX=1 --project-ref "$STG_REF"` rồi `supabase functions deploy send-otp --project-ref "$STG_REF"` (cờ **[ĐÃ KIỂM CHỨNG]**); không đặt khoá SMS thật.
  - *Edge functions* `send-otp`, `signed-qr`: chỉ triển khai nếu cần; rewards không cần.
  - *Vercel `/api/*`* (email, PDF, media, xoá tài khoản): **không** có ở staging. Web dev sẽ nhận 404 cho `/api/*` (không đi vào production). iOS: trỏ `apiBaseURL` vào chỗ không ai nghe (mục 4.2).
  - Không có Vault/pg_net trong migration (**[ĐÃ KIỂM CHỨNG]** bằng grep).
  - SMTP/mẫu email: không cần.

### 2.3 Áp dụng 1 → 176 bằng CLI, an toàn
Cách làm: tạo **thư mục làm việc tạm** chỉ chứa `config.toml` và các migration cần áp dụng; chạy CLI từ đó với `--workdir` và `--db-url`.

```bash
source /path/to/stg-guard.sh
REPO="$(git rev-parse --show-toplevel)"
make_workdir() {                       # make_workdir <max-version>  e.g. 20261218000176
  W=/tmp/banbe-stg-workdir; rm -rf "$W"; mkdir -p "$W/supabase/migrations"
  cp "$REPO/supabase/config.toml" "$W/supabase/"
  for f in "$REPO"/supabase/migrations/*.sql; do
    v="$(basename "$f")"; v="${v%%_*}"
    [ "$v" -le "$1" ] && cp "$f" "$W/supabase/migrations/"
  done
  ls "$W/supabase/migrations" | wc -l
}
make_workdir 20261218000176            # kỳ vọng: 169
supabase migration list --db-url "$STG_DB_URL"                       # staging trống: không có gì đã áp dụng
supabase db push --workdir /tmp/banbe-stg-workdir --db-url "$STG_DB_URL" --dry-run
```
- `--dry-run` "in ra các migration sẽ áp dụng mà không áp dụng" (**[ĐÃ KIỂM CHỨNG]** từ `--help`; hành vi **[CHƯA KIỂM CHỨNG]**). Xem danh sách: phải là 169 file, kết thúc ở `…176_ticket_list_hidden`.
- Nếu danh sách đúng: chạy lại **không có `--dry-run`** (và không có `--include-seed`).
- Kiểm tra sau: `supabase migration list --db-url "$STG_DB_URL"` (cột Remote kết thúc ở `20261218000176`); chạy các truy vấn kiểm tra ở mục 2.2 (cron, buckets, `authenticator`).
- Chênh lệch số thứ tự cũ đã biết (**[ĐÃ KIỂM CHỨNG]**): hai file `014`, số 034–039, 154, 160 bị bỏ trống; không phải lỗi, CLI theo timestamp.
- Nếu một migration cũ thất bại trên project mới (khác biệt môi trường, ví dụ quyền extension): **dừng**, ghi lại lỗi nguyên văn; không sửa migration cũ. Staging là nơi phát hiện đúng loại vấn đề này.

**Cách thay thế không dùng thư mục tạm (không khuyến nghị):** `supabase db push --db-url "$STG_DB_URL" --include-all` từ gốc repo sẽ áp dụng **cả 177–180 cùng lúc** (mất ý nghĩa kiểm tra từng cái) và gần với lệnh nguy hiểm `--linked`. Tránh.

---

## 3. Áp dụng 177 → 178 → 179 → 180 từng cái một vào staging

### 3.1 Cách chỉ áp một migration mỗi lần
- **[ĐÃ KIỂM CHỨNG] Không có cờ "dừng ở phiên bản N" cho `db push`/`migration up` từ xa.** Các cờ có thật là `--include-all`, `--dry-run`, `--db-url`, `--linked`, `--project-ref`; riêng `db reset` có `--version`/`--last` nhưng áp dụng cho DB local hoặc reset (huỷ dữ liệu), **không** dùng cho việc này.
- **Cách dùng:** dùng `make_workdir <N>` ở mục 2.3 với N lần lượt là `20261218000177`, `20261219000178`, `20261220000179`, `20261221000180`. Mỗi lần thư mục tạm chỉ có các migration ≤ N, nên đúng **một** migration đang chờ.
  ```bash
  apply_one() {   # apply_one 20261218000177
    source /path/to/stg-guard.sh && make_workdir "$1" \
    && supabase db push --workdir /tmp/banbe-stg-workdir --db-url "$STG_DB_URL" --dry-run
    # đọc kết quả: phải liệt kê ĐÚNG MỘT file. Nếu đúng:
    #   supabase db push --workdir /tmp/banbe-stg-workdir --db-url "$STG_DB_URL"
  }
  ```
- Phụ thuộc (đã đọc): **179 dựa vào bản `get_my_rewards` của 177; 180 dựa vào bảng cờ và catalog của 179.** Thứ tự bắt buộc 177 → 178 → 179 → 180; `--dry-run` sẽ lộ ra nếu sai.
- Phương án khác: dán nội dung một file migration vào *SQL Editor* của staging rồi `supabase migration repair --status applied <version> --db-url "$STG_DB_URL"` (**[ĐÃ KIỂM CHỨNG]** cờ `repair`; cách làm **[CHƯA KIỂM CHỨNG]**). Chậm hơn và dễ lệch lịch sử; chỉ dùng nếu `db push --workdir` không chạy được.
- **Sau MỖI migration**, trước khi sang cái kế tiếp: chạy bảng kiểm tra ở 3.3, lưu bằng chứng (mục 6), xem Dashboard → *Logs* (API, Postgres) 10–15 phút.

### 3.2 Chuẩn bị trước khi áp dụng 177 (bản chụp "trước")
Khi staging ở 176 và đã có dữ liệu test (mục 5.2): với mỗi tài khoản test, lưu kết quả các RPC cũ vào file (xem 3.4). Đây là "bản chụp trước" để so sau từng migration.

### 3.3 Bảng kiểm tra sau mỗi migration (giống mục 8.1 của summary)

| Sau khi áp dụng | Kiểm tra bắt buộc (RPC CŨ vẫn chạy) |
|---|---|
| **177** | `get_my_reward_summary`, `get_my_rewards`, `record_active_day('save', …)`, `redeem_reward` (mã đã mở khoá → `already_unlocked`) cho tài khoản test: kết quả khớp bản chụp trước (số dư, chuỗi, lịch sử); `get_my_rewards` có thêm `timezone_settings`; tài khoản chưa chọn múi giờ: `streak.timezone = Asia/Ho_Chi_Minh`; một check-in thử ở sự kiện test không bị chặn |
| **178** | Bảng `reward_risk_*` (3 bảng gồm `reward_risk_flag_accounts`) tồn tại; `reward_risk_config.enabled = false`; `admin_reward_risk_preview()` (admin) trả `written: 0`; `check_in_guest` và đặt chỗ vẫn chạy |
| **179** | `get_my_rewards`: `catalog` còn đúng 3 mục, `offers = []`; `redeem_reward` trả như cũ cho mã keychain; mở Rewards bằng **bản iOS đã phát hành** và bản web cũ: không lỗi; `save_my_keychain` vẫn `DESIGN_LOCKED` cho thiết kế chưa mở khoá |
| **180** | `reward_feature_flags('reward_events') = false`; `record_reward_event` (đăng nhập) trả `recorded:false`; bảng đếm rỗng |

### 3.4 Gọi RPC bằng PostgREST thật và so sánh trước/sau
Lấy JWT bằng GoTrue thật (đăng nhập mật khẩu), rồi gọi RPC qua REST bằng **khoá anon của staging**:

```bash
source /path/to/stg-guard.sh
login() {   # login <email> <password>  -> prints access_token  (không in ra màn hình chia sẻ, không ghi vào repo)
  curl -s "$STG_URL/auth/v1/token?grant_type=password" -H "apikey: $STG_ANON" -H "Content-Type: application/json" \
       -d "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r .access_token
}
rpc() {     # rpc <name> <jwt|-> [json-body]
  local auth=() body="${3-}"; [ -z "$body" ] && body='{}'
  [ "$2" != "-" ] && auth=(-H "Authorization: Bearer $2")
  curl -s "$STG_URL/rest/v1/rpc/$1" -H "apikey: $STG_ANON" "${auth[@]}" -H "Content-Type: application/json" -d "$body"
}
JWT_MAIN="$(login rw.main@banbe-staging.test '<mật khẩu test>')"
mkdir -p ~/stg-evidence
snap() {    # snap <label>   — các trường mà client CŨ đọc; bỏ trường mới
  rpc get_my_reward_summary "$JWT_MAIN" | jq -S . > ~/stg-evidence/$1.summary.json
  rpc get_my_rewards "$JWT_MAIN" | jq -S '{success, balance, rules, streak: {current: .streak.current, longest: .streak.longest, active_today: .streak.active_today},
      badges: [.badges[] | del(.earned_at)], history: [.history[] | {type, amount, reason}],
      catalog: [.catalog[] | {code, kind, design_id, price, unlocked}], paid: .attendance_paid_this_month}' > ~/stg-evidence/$1.rewards.json
}
snap before-177        # chạy ở 176
# …áp dụng 177… rồi:
snap after-177 && diff ~/stg-evidence/before-177.rewards.json ~/stg-evidence/after-177.rewards.json && echo "UNCHANGED"
```
**[CHƯA KIỂM CHỨNG]** toàn bộ đoạn trên (chưa chạy với staging thật). Lưu ý: `streak.timezone` đổi nghĩa ở 177 nhưng vẫn là `Asia/Ho_Chi_Minh` cho người chưa chọn nên không nằm trong `diff` ở trên; `timezone_settings` (177) và `offers` (179) là trường mới, **không** đưa vào so sánh; khi so sánh sau 179, mọi dòng `catalog` phải giống hệt dòng cũ cho các trường cũ.

Cổng tài khoản (migration 126) có thể từ chối RPC với tài khoản chưa qua cổng. Cách xử lý cho kiểm tra API: tạo tài khoản qua API admin **có `phone` và `phone_confirm: true`** (mục 5.2); nếu cổng vẫn đòi ngày sinh theo phiên, dùng phương án `account_phone_grandfathered` ở 5.2. **[CHƯA KIỂM CHỨNG]** phương án nào chạy.

---

## 4. Cấu hình app (web và iOS) trỏ về staging, chắc chắn không dính production

### 4.1 Web
Dùng lại ý tưởng của mode `rewardslocal` (`supabase/_localtest/rewards-manual/make_web_env.sh`, `check_web_local.sh`; thư mục này bị `.gitignore`, chỉ nằm trên máy bạn), đổi sang mode **`rewardsstaging`**:

```bash
source /path/to/stg-guard.sh
cat > .env.rewardsstaging.local <<EOF
# STAGING ONLY. Gitignored by the "*.local" rule. Never copy to Vercel.
VITE_SUPABASE_URL=$STG_URL
VITE_SUPABASE_ANON_KEY=$STG_ANON
EOF
npm run dev -- --mode rewardsstaging
```
- File mode ghi đè `.env`/`.env.local` mà không đọc hay sửa chúng (**[ĐÃ KIỂM CHỨNG]** là cơ chế đang dùng cho `rewardslocal`; **[CHƯA KIỂM CHỨNG]** với URL https).
- **Kiểm tra bắt buộc TRƯỚC khi đăng nhập** (biến thể của `check_web_local.sh`):
  ```bash
  source /path/to/stg-guard.sh
  BODY="$(curl -s -m 10 http://localhost:5173/src/lib/supabase.js)"
  URL="$(printf '%s' "$BODY" | head -1 | sed -n 's/.*"VITE_SUPABASE_URL": "\([^"]*\)".*/\1/p')"
  KEYLEN="$(printf '%s' "$BODY" | head -1 | sed -n 's/.*"VITE_SUPABASE_ANON_KEY": "\([^"]*\)".*/\1/p' | wc -c)"
  [ "$URL" = "$STG_URL" ] && [ "$KEYLEN" -gt 100 ] && echo "PASS: web uses $URL" || { echo "FAIL: URL='${URL:-<unset -> falls back to PRODUCTION>}'"; exit 1; }
  ```
  Cần **cả hai** biến: nếu chỉ có URL staging mà thiếu anon key thì `supabase.js` dùng anon key production với URL staging (lỗi 401 chứ không chạm production, nhưng vẫn là cấu hình sai). **[CHƯA KIỂM CHỨNG]** script (biến thể chưa chạy).
- Sau khi đăng nhập, trong DevTools Console: `Object.keys(localStorage).filter(k => k.startsWith('sb-'))` phải ra `['sb-<STG_REF>-auth-token']`. Nếu thấy khoá chứa mã production → đăng xuất, dừng. Tab Network chỉ được thấy `<STG_REF>.supabase.co` (không `supabase.co` khác, không `banbe.app`).
- `/api/*` sẽ 404 trên dev server (không có Vercel): bình thường.

### 4.2 iOS (simulator)
`AppConfig` trong `apps/ios/BanbeApp/Services/SupabaseService.swift` **cứng URL và anon key production** (**[ĐÃ KIỂM CHỨNG]**, không có xcconfig/Info.plist override). Dùng lại cách của `ios-point-local.sh` (sửa tạm + khôi phục), điều chỉnh cho https và staging:

```bash
source /path/to/stg-guard.sh
F=apps/ios/BanbeApp/Services/SupabaseService.swift
STG_URL="$STG_URL" STG_ANON="$STG_ANON" perl -0pi -e '
  s{static let supabaseURL = "[^"]*"}{static let supabaseURL = "$ENV{STG_URL}"};
  s{static let supabaseAnonKey = "[^"]*"}{static let supabaseAnonKey = "$ENV{STG_ANON}"};
  s{static let apiBaseURL = "[^"]*"}{static let apiBaseURL = "http://127.0.0.1:9"};' "$F"
grep -nE 'static let (supabaseURL|apiBaseURL)' "$F"
PROD_REF="$(cat supabase/.temp/project-ref)"; grep -c "$PROD_REF\|banbe.app" "$F"   # kỳ vọng: chỉ còn trong chú thích (ví dụ 1)
```
- `apiBaseURL` trỏ `127.0.0.1:9` (không ai nghe) để mọi `/api/*` thất bại thay vì chạm production; `publicWebOrigin` suy ra từ nó (**[ĐÃ KIỂM CHỨNG]**).
- Build & chạy simulator như mục 6.2 của `rewards-phase0-local-setup.md`. **Khôi phục khi xong:** `git checkout -- apps/ios/BanbeApp/Services/SupabaseService.swift` (hoặc `ios-restore.sh`), **không bao giờ commit file đã sửa**; kiểm `git status` sạch trước khi commit bất cứ gì.
- Điện thoại thật: staging dùng https nên không vướng ATS như local; **[CHƯA KIỂM CHỨNG]** (cần ký số/Personal Team, xem note 18).
- **Client cũ (E1–E3, B7, B8):** dựng bản cũ từ worktree riêng rồi áp dụng cùng cách sửa tạm ở đó:
  ```bash
  git worktree add /tmp/banbe-old-pre177 e399694     # trước toàn bộ Giai đoạn 0
  git worktree add /tmp/banbe-old-pre3b  e5b5a0c     # có 177-179 phía server nhưng chưa có UI 3b
  ```
  (`ios-point-local.sh` nhận tham số `repo-root` để làm việc này; biến thể staging tương tự đoạn perl ở trên, trỏ vào `$ROOT` của worktree.) Dọn worktree ở mục 7.

---

## 5. Lặp lại kiểm tra A–E trên staging (+ kiểm tra chỉ staging làm được)

### 5.1 Chuỗi thực hiện đề xuất
1. Staging ở 176 + dữ liệu test (5.2) → `snap before-177`.
2. **E3** (server 176, client mới): mở Rewards bằng web + iOS mới: không có mục múi giờ, không có mục Ưu đãi, không lỗi.
3. Áp dụng **177** → bảng 3.3 → `snap after-177` → nhóm **A** (A1–A10) và **B** (B1–B8, gồm B7/B8 client cũ với server 177). Dùng SQL Editor staging thay cho `10_tz_fastforward.sql` (A6): `update reward_user_settings set pending_from_ts = now() - interval '1 minute' where user_id = (select id from auth.users where email = 'rw.main@banbe-staging.test') and pending_tz is not null;`.
4. Áp dụng **178** → bảng 3.3 (kèm 5.3 mục P6).
5. **E1** (server 178, client mới): Rewards mở bình thường, có mục múi giờ, không có Ưu đãi.
6. Áp dụng **179** → bảng 3.3 → nhóm **D** (D1–D8; tạo offer và bật/tắt cờ bằng SQL Editor, cú pháp trong `rewards-phase0-local-setup.md` mục "Bước 3b", đổi `supabase_db_banbe` thành SQL Editor staging) và **E2** (client cũ `/tmp/banbe-old-*` với server 179, cờ bật và có offer: Rewards mở được, thấy 3 thiết kế, không thấy offer).
7. Áp dụng **180** → bảng 3.3 → P-checks.
8. Nhóm **C** (giao diện thật, máy nhỏ, dark mode, Dynamic Type, VoiceOver): làm bằng tay trên simulator/iPhone, ghi ảnh chụp.

### 5.2 Dữ liệu test trên staging (tài khoản đăng nhập thật qua GoTrue)
Tài khoản mật khẩu, đã xác nhận email và số điện thoại, tạo bằng API admin của **staging** (khoá `service_role` của staging; **[CHƯA KIỂM CHỨNG]** các trường được chấp nhận):

```bash
source /path/to/stg-guard.sh; : "${STG_SERVICE:?export STG_SERVICE only for this step}"
mk() {   # mk <email> <phone> <display_name>
  curl -s "$STG_URL/auth/v1/admin/users" -H "apikey: $STG_SERVICE" -H "Authorization: Bearer $STG_SERVICE" -H "Content-Type: application/json" \
   -d "{\"email\":\"$1\",\"password\":\"<mật khẩu test>\",\"email_confirm\":true,\"phone\":\"$2\",\"phone_confirm\":true,\"user_metadata\":{\"display_name\":\"$3\"}}" | jq '{id, email}'
}
mk rw.main@banbe-staging.test  +84900200001 "RW Main"
mk rw.fresh@banbe-staging.test +84900200002 "RW Fresh"
mk rw.limit@banbe-staging.test +84900200003 "RW Limit"
mk rw.host@banbe-staging.test  +84900200009 "RW Host"
mk rw.admin@banbe-staging.test +84900200010 "RW Admin"
unset STG_SERVICE
```
Sau đó trong **SQL Editor của staging** (không phải production; mỗi đoạn bắt đầu bằng chốt chặn):

```sql
DO $guard$ BEGIN
  IF (SELECT count(*) FROM auth.users WHERE email NOT LIKE '%@banbe-staging.test') > 25 THEN
    RAISE EXCEPTION 'REFUSING: too many non-test users, this does not look like staging';
  END IF;
END $guard$;

-- cổng tài khoản (giống 01_seed_local.sql): số điện thoại đã xác minh + ngày sinh + đã đồng ý chính sách
UPDATE public.profiles SET phone_verified = true, policy_accepted_at = now(), policy_version = '2026-10-06'
 WHERE id IN (SELECT id FROM auth.users WHERE email LIKE '%@banbe-staging.test');
INSERT INTO public.user_private_dob (user_id, date_of_birth)
  SELECT id, DATE '1995-05-05' FROM auth.users WHERE email LIKE '%@banbe-staging.test' ON CONFLICT (user_id) DO NOTHING;
UPDATE public.profiles SET role = 'organizer' WHERE id = (SELECT id FROM auth.users WHERE email = 'rw.host@banbe-staging.test');
UPDATE public.profiles SET role = 'admin'     WHERE id = (SELECT id FROM auth.users WHERE email = 'rw.admin@banbe-staging.test');

-- tổ chức + 3 sự kiện tương lai để thả tim (cùng cột như 01_seed_local.sql)
INSERT INTO public.organizers (id, name, owner_id, user_id)
SELECT 'rws_org', 'RW Staging Host', u.id, u.id FROM auth.users u WHERE u.email = 'rw.host@banbe-staging.test' ON CONFLICT (id) DO NOTHING;
INSERT INTO public.events (id, key, name, organizer_id, status, visibility, approval, area, category, price_vnd, capacity, seats_remaining, starts_at) VALUES
  ('rws_evt_1','rws_evt_1','RW Staging Event 1','rws_org','live','public','instant','Ho Chi Minh City','Food & Travel',0,50,50, now() + interval '10 days'),
  ('rws_evt_2','rws_evt_2','RW Staging Event 2','rws_org','live','public','instant','Ho Chi Minh City','Music',0,50,50, now() + interval '20 days'),
  ('rws_evt_3','rws_evt_3','RW Staging Event 3','rws_org','live','public','instant','Ho Chi Minh City','Workshop',0,50,50, now() + interval '30 days')
ON CONFLICT (id) DO NOTHING;

-- rw.main: 90 xu kiểu hàng CŨ (không period_month/tz_used) + chuỗi 3 ngày kết thúc hôm qua, đúng như seed local
INSERT INTO public.reward_ledger (user_id, entry_type, amount, source_key, rules_version, reason, ref)
SELECT id, 'award', 90, 'onboarding', (public.rewards_rules() ->> 'version')::int, 'onboarding', '{}'::jsonb FROM auth.users WHERE email = 'rw.main@banbe-staging.test';
INSERT INTO public.reward_active_days (user_id, local_date, source)
SELECT u.id, (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date - n, 'save' FROM auth.users u, generate_series(1, 3) n WHERE u.email = 'rw.main@banbe-staging.test';
```
- **[CHƯA KIỂM CHỨNG]** các câu lệnh trên chạy được nguyên văn trên staging (copy từ `01_seed_local.sql`, vốn mới chạy trên DB local). **`rw.limit`** (A7): chỉ sau khi 177 được áp dụng: `INSERT INTO public.reward_user_settings (user_id, tz, tz_changed_at) SELECT id, 'America/Chicago', ARRAY[now() - interval '10 days', now() - interval '3 days'] FROM auth.users WHERE email = 'rw.limit@banbe-staging.test';`.
- **Phương án dự phòng** nếu cổng tài khoản vẫn chặn RPC qua REST: `INSERT INTO public.account_phone_grandfathered (user_id, cohort) SELECT id, 't' FROM auth.users WHERE email LIKE '%@banbe-staging.test' ON CONFLICT DO NOTHING;` (đã dùng trong harness; bỏ qua yêu cầu điện thoại/ngày sinh nên **không** thử được cổng thật; ghi chú rõ khi dùng).
- Để quan sát A–E đúng như mô tả, đối chiếu số xu/chuỗi bằng truy vấn đọc trong SQL Editor trước và sau (như `13_numbers.sql`).

### 5.3 Kiểm tra chỉ staging làm được (harness không có PostgREST/GoTrue)
Mỗi dòng ghi kết quả thật vào bằng chứng. Kỳ vọng là **dự đoán** từ code; nếu khác, đó là phát hiện cần điều tra, không phải lỗi của runbook.

| # | Kiểm tra | Cách làm | Kỳ vọng (CHƯA KIỂM CHỨNG) |
|---|---|---|---|
| P1 | **Quyền EXECUTE qua khoá anon (không đăng nhập)** | `rpc get_my_rewards -`, `rpc redeem_reward - '{"p_item_code":"rwd-comet"}'`, `rpc set_my_reward_timezone -  '{"p_tz":"America/Chicago"}'`, `rpc record_reward_event - '{"p_offer_id":"x"}'`, `rpc admin_reward_event_report -`, `rpc admin_reward_risk_preview -` (đều với khoá anon, không `Authorization`) | Bị từ chối (HTTP 401/403, mã `42501` hoặc tương đương); không có dữ liệu trả về |
| P2 | **RLS/quyền bảng qua REST** (JWT người dùng thường **và** anon) | `GET $STG_URL/rest/v1/<bảng>?select=*` cho từng bảng: `reward_ledger`, `reward_unlocks`, `reward_active_days`, `reward_user_badges`, `reward_catalog`, `reward_user_settings`, `reward_risk_flags`, `reward_risk_flag_accounts`, `reward_risk_config`, `reward_event_counters`, `reward_event_config`, `reward_feature_flags` | Bị từ chối (không trả hàng nào, kể cả của chính người dùng); không bảng nào lộ qua REST |
| P3 | **Đăng nhập GoTrue thật** | `login` ở 3.4 với từng tài khoản; thử sai mật khẩu; đăng xuất; làm mới token | Token hợp lệ; sai mật khẩu bị từ chối |
| P4 | **RPC của người dùng thường qua REST** | Với JWT `rw.main`: `get_my_reward_summary`, `get_my_rewards`, `record_active_day`, `redeem_reward`, `set_my_reward_timezone`, `record_reward_event` (cờ tắt) | Thành công; `record_reward_event` trả `recorded:false`; `admin_*` trả `NOT_ADMIN` |
| P5 | **Cổng tài khoản (126) với RPC mới** | Tài khoản chưa qua cổng (tạo thêm một tài khoản không có DOB/điện thoại) gọi RPC rewards | Bị cổng chặn theo cách các RPC cũ vẫn bị chặn (không khác biệt giữa RPC cũ và mới) |
| P6 | **Admin qua REST** | JWT `rw.admin`: `admin_reward_risk_preview` (written 0), `admin_get_reward_risk_config`, `admin_reward_event_report`; bật cờ rủi ro bằng SQL, `admin_run_reward_risk_scan` rồi `admin_list_reward_risk_flags` | Chạy đúng; người thường nhận `NOT_ADMIN`; cờ tắt thì scan không ghi |
| P7 | **Xoá tài khoản thật (cascade qua GoTrue)** | Với cờ rủi ro bật và có cờ liên kết tài khoản test, xoá một người dùng test ở *Authentication → Users → Delete user* (Dashboard), rồi truy vấn `reward_risk_flag_accounts`, `reward_ledger`, `profiles` | Liên kết biến mất; cờ khác không đổi; sổ cái của người xoá đi theo (khác luồng `api/auth` của Vercel, vốn gọi cùng `deleteUser`) |
| P8 | **Đồng thời qua PostgREST** | Chạy 12 lệnh `redeem_reward` song song (`for i in $(seq 12); do rpc redeem_reward "$JWT" '{"p_item_code":"rwd-comet"}' & done; wait`) | Đúng một lần trừ xu, không âm (tương tự `13b`, nhưng qua lớp API thật) |
| P9 | **Schema cache PostgREST sau migration** | Sau mỗi migration gọi RPC mới ngay | Không có lỗi `PGRST202`; nếu có, `NOTIFY pgrst, 'reload schema'` rồi ghi lại |
| P10 | **Cron và bucket** | `select jobname from cron.job`; `select id from storage.buckets` | Khớp production |
| P11 | **Rollback diễn tập** | Với một migration (đề xuất 180, rồi 179), chạy file rollback trong `supabase/rollbacks/` bằng SQL Editor; chạy lại bảng 3.3; rồi áp dụng lại bằng `make_workdir` nếu cần | Rollback chạy sạch; RPC cũ vẫn như bản chụp |
| P12 | **Nhật ký** | Dashboard → *Logs* (API/Postgres) trong lúc làm A–E và P1–P11 | Không có lỗi 5xx bất thường, không có lỗi quyền ngoài ý muốn |

---

## 6. Tiêu chí "staging đạt" và bằng chứng

### 6.1 Điều kiện để được phép áp dụng lên production (tất cả phải đúng)
1. Staging đạt đúng 176 trước khi bắt đầu; mọi migration cũ chạy không lỗi trên project mới (hoặc mọi lỗi đã được phân tích và không liên quan).
2. 177, 178, 179, 180 áp dụng **từng cái một** không lỗi; sau mỗi cái bảng 3.3 đạt và `diff` bản chụp RPC cũ là **không đổi**.
3. Nhóm **A, B, D, E** đạt (kể cả E1, E2, E3, B7, B8); nhóm **C** đã làm tay và không có lỗi chặn.
4. P1–P12 đạt (đặc biệt P1, P2, P5, P8: quyền và RLS qua lớp API thật).
5. Rollback diễn tập (P11) đạt ít nhất cho 179 và 180.
6. Nhật ký staging không có lỗi bất thường trong cả phiên.
7. iOS `RewardsTests` chạy lại trên **đúng commit** sẽ phát hành: kỳ vọng 17 test, 0 fail.
8. Bản sao lưu production đã xác nhận (mục 8.0 của summary), khung giờ phát hành và người trực đã chốt.
9. Mọi điều kiện pháp lý/policy để **bật cờ** là việc riêng (mục 8.4 của summary); staging đạt **không** cho phép bật cờ nào trên production.

Staging đạt là **điều kiện cần, không đủ**: staging có dữ liệu rất ít, gói miễn phí, và không có dữ liệu thật; nó chứng minh tương thích và quyền, không chứng minh hiệu năng trên dữ liệu thật.

### 6.2 Bằng chứng cần ghi lại (lưu ngoài repo hoặc trong tài liệu riêng tư; **che mọi khoá, JWT, mật khẩu**)
- Mã commit đã kiểm (`git rev-parse HEAD`), ngày giờ, người thực hiện, `STG_REF` (không ghi khoá).
- Đầu ra `supabase migration list --db-url …` (trước và sau mỗi migration) và đầu ra `--dry-run` từng lần.
- Các file bản chụp JSON `before-*`/`after-*` và kết quả `diff` (3.4).
- Kết quả bảng 3.3 sau từng migration (đạt/không, ghi chú).
- Bảng A–E (từng mục đạt/không, ảnh chụp màn hình web và iOS, kể cả E1–E3 và các mục client cũ, ghi rõ commit của client cũ).
- Kết quả P1–P12 (mã HTTP và thân phản hồi đã che dữ liệu).
- Ảnh chụp Dashboard Logs trong phiên và phát hiện bất thường (nếu có).
- Kết quả truy vấn `cron.job`, `storage.buckets`, `rolconfig` của `authenticator` và so sánh với production (chỉ tên, không dữ liệu).
- Kết quả chạy iOS `RewardsTests` (số test, thời điểm, commit).
- Danh sách sai khác giữa tài liệu này và thực tế (mục [CHƯA KIỂM CHỨNG] nào đã đúng/sai) để cập nhật runbook.

---

## 7. Dọn dẹp / xoá staging

1. **Client:** khôi phục iOS: `git checkout -- apps/ios/BanbeApp/Services/SupabaseService.swift`; xoá `.env.rewardsstaging.local`; dừng dev server; xoá app khỏi simulator; `git worktree remove /tmp/banbe-old-pre177 /tmp/banbe-old-pre3b`.
2. **Máy:** `rm -rf /tmp/banbe-stg-workdir ~/stg-evidence` (sau khi đã lưu bằng chứng cần giữ, đã che khoá); `unset STG_REF STG_URL STG_ANON STG_DB_URL STG_SERVICE`; xoá dòng chứa khoá khỏi lịch sử shell nếu có (`history`); kiểm tra `git status` sạch (không có thay đổi trong `apps/ios` hay file `.env*`).
3. **Dashboard staging:** *Project Settings → General → Delete project* (xoá hẳn) hoặc *Pause project* nếu muốn giữ để dùng lại. **[CHƯA KIỂM CHỨNG]** tên mục chính xác. Xoá project huỷ luôn các khoá của nó; nếu giữ lại, **xoay khoá** (*Settings → API*) sau khi dùng xong.
4. **Xác nhận không đụng production:** `supabase migration list --db-url "<production>"` **không** thuộc runbook này (không truy vấn production). Thay vào đó xác nhận bằng chứng 6.2 cho thấy chỉ có `STG_REF` và không có mã production nào trong đầu ra.
5. Nếu staging được giữ cho vòng phát hành kế tiếp: đưa nó về lại 176 là **không** thể bằng rollback (các file rollback chỉ lùi chức năng, không xoá bảng khi có dữ liệu). Tạo project mới (mục 1) thay vì tái sử dụng.

---

## 8. Tóm tắt đã/chưa kiểm chứng

**Đã kiểm chứng (trong phiên soạn):** repo đang `link` vào production (`supabase/.temp/project-ref`); CLI 2.120.0 có `db push` (`--dry-run`, `--db-url`, `--include-all`, `--include-seed`, `--workdir` toàn cục), `db reset` (`--no-seed`, `--version`, `--last`), `migration up/list/repair`, `projects create`, `functions deploy`, `secrets set`, `unlink`; không có cờ "dừng ở phiên bản N" cho áp dụng từ xa; cấu trúc migration (extension, cron, bucket, `authenticator`, gate 126); `seed.sql` gốc hỏng; iOS/web có giá trị dự phòng production; script local `make_web_env.sh`, `check_web_local.sh`, `ios-point-local.sh` tồn tại và cách chúng hoạt động.

**Chưa kiểm chứng (cần staging thật):** mọi lệnh ở mục 2.3, 3, 4, 5 khi chạy thật; hành vi `--dry-run` và `--workdir` với `--db-url`; quyền `ALTER ROLE authenticator`/`pg_cron` trên project mới; giới hạn gói miễn phí; giao diện Dashboard; API admin tạo người dùng với `phone_confirm`; cổng tài khoản với tài khoản tạo bằng API; toàn bộ kỳ vọng P1–P12; iOS trên thiết bị thật.

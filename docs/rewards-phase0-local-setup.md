# Rewards Phase 0 — dựng môi trường thử thủ công (LOCAL)

Mục tiêu: chạy được toàn bộ [rewards-phase0-manual-checks.md](rewards-phase0-manual-checks.md) (A1–A10, B1–B8) trên một
backend Supabase **chạy trong Docker trên máy bạn**. Không bước nào ở đây chạm production, không đọc `.env` thật, không
sửa code ứng dụng.

Script và SQL nằm ở `supabase/_localtest/rewards-manual/` (thư mục này bị `.gitignore` chủ đích — chỉ để dùng local,
mật khẩu test nằm trong đó). Mọi lệnh bên dưới chạy từ **thư mục gốc repo** trừ khi ghi khác.

---

## 0. Bốn điều phải biết trước (đã kiểm tra trong repo)

1. **`npm run dev` bình thường KHÔNG trỏ về local.** `src/lib/supabase.js` đọc `VITE_SUPABASE_URL`; nếu thiếu thì tự rơi về
   URL production (hardcode). Trên máy này `.env.local` hiện có đã làm Vite tiêm URL production (đã kiểm bằng
   `check_web_local.sh` ở chế độ thường → FAIL). Vì vậy tài liệu dùng **Vite mode riêng** `rewardslocal`
   (file `.env.rewardslocal.local`), mode này ghi đè `.env`/`.env.local` mà **không đọc hay sửa chúng**.
2. **iOS hardcode URL + anon key production** trong `AppConfig` (`apps/ios/BanbeApp/Services/SupabaseService.swift`),
   không có xcconfig/Info.plist nào override. Muốn simulator trỏ local thì bắt buộc phải sửa file đó. Không được sửa code ứng
   dụng, nên mình cung cấp script **sửa tạm + khôi phục** (`ios-point-local.sh` / `ios-restore.sh`). Bạn chủ động chạy; file đó
   **không bao giờ được commit** ở trạng thái đã sửa.
3. **`supabase/config.toml` bật seed `./seed.sql` (ở gốc repo) và seed đó hỏng** với schema hiện tại
   (`profiles.handle` NOT NULL — đã chạy thử trên DB harness: lỗi `null value in column "handle"`). Nó cũng `DELETE` bảng
   `profiles`. Hãy dùng `--no-seed` cho mọi lần reset (xem bước 2.3).
4. **Cổng 54322 đang bị container `banbe-pg` (harness test cũ) chiếm**, cùng cổng với DB của `supabase start`. Phải dừng nó
   trước (bước 2.1). Các container `banbe-ld-*` đang ở trạng thái Exited, không ảnh hưởng.

---

## 1. Cài công cụ

### 1.1 Kiểm tra
```bash
supabase --version ; docker --version ; docker info >/dev/null && echo "docker OK"
```
Trên máy này lúc soạn tài liệu: **`supabase` chưa cài** (`command not found`), Docker có (29.6.2).

### 1.2 Cài Supabase CLI
- **macOS:** `brew install supabase/tap/supabase`
- **Windows:** `scoop bucket add supabase https://github.com/supabase/scoop-bucket.git` rồi `scoop install supabase`
  (các script `.sh` ở đây cần Git Bash/WSL; phần iOS chỉ chạy được trên macOS).

Mong đợi: `supabase --version` in ra một số phiên bản (ví dụ `2.x.y`). Docker Desktop phải đang chạy.

---

## 2. Dựng stack Supabase local (API, Auth, Studio) với migration đến 177

### 2.1 Giải phóng cổng 54322
```bash
docker stop banbe-pg
```
Mong đợi: in `banbe-pg`. (Muốn dùng lại harness cũ sau này: `docker start banbe-pg`.)

### 2.2 Khởi động
```bash
supabase start
```
Lần đầu tải image khá lâu. CLI áp dụng **toàn bộ** `supabase/migrations/*.sql` theo thứ tự (hiện 178 file, kết thúc ở
`20261219000178_178_reward_risk_flags.sql`; 177 nằm trong đó, 178 là cờ gian lận mặc định TẮT nên vô hại).
Mong đợi cuối lệnh in khối giống:
```
API URL: http://127.0.0.1:54321
Studio URL: http://127.0.0.1:54323
Mailpit URL: http://127.0.0.1:54324     (hộp thư giả; không cần vì ta đăng nhập bằng mật khẩu)
DB URL: postgresql://postgres:postgres@127.0.0.1:54322/postgres
```
**Nếu `supabase start` báo lỗi ở bước seed** (xem cảnh báo 3): chạy `supabase db reset --no-seed`, và từ giờ luôn dùng `--no-seed`.

> Chưa chạy được trong lúc soạn (CLI chưa cài). Hành vi seed của `start` so với `db reset` có thể khác nhau tùy bản CLI —
> nếu thấy lỗi lạ ở bước này, hãy dán nguyên văn lỗi để xử lý.

### 2.3 Xác nhận migration 177 đã có
```bash
supabase migration list --local | tail -4
docker exec supabase_db_banbe psql -U postgres -Atc \
  "select to_regclass('public.reward_user_settings'), to_regprocedure('public.set_my_reward_timezone(text)')"
```
Mong đợi dòng cuối của `migration list` có `20261218000177` ở cả cột Local và (nếu có) 178; lệnh thứ hai in
`reward_user_settings|set_my_reward_timezone(text)`.

### 2.4 URL API local và anon key lấy ở đâu
- URL API local luôn là **`http://127.0.0.1:54321`**.
- Anon key: `supabase status -o env` → dòng `ANON_KEY=...` (key local mặc định, chỉ dùng được với stack local).
- `SERVICE_ROLE_KEY` cũng nằm ở đó: **không dán vào `.env*`, không đưa vào app.**

---

## 3. Trỏ web về local và chắc chắn KHÔNG dính production

Biến môi trường cần (theo `.env.example`): chỉ **`VITE_SUPABASE_URL`** và **`VITE_SUPABASE_ANON_KEY`**. Các biến
`RESEND_*`, `GMAIL_*`, `SUPABASE_SERVICE_ROLE_KEY`, R2… là của Vercel functions (`/api/*`), không cần và không được đặt.

### 3.1 Tạo file env của mode `rewardslocal`
```bash
supabase/_localtest/rewards-manual/make_web_env.sh
```
Mong đợi: `wrote .../.env.rewardslocal.local (URL http://127.0.0.1:54321). Start the app with: npm run dev -- --mode rewardslocal`.
File này bị `.gitignore` (`*.local`). Không đụng tới `.env.local` hiện có.

### 3.2 Chạy web
```bash
npm run dev -- --mode rewardslocal
```
Mong đợi: `VITE v6.x ... Local: http://localhost:5173/`. Mở http://localhost:5173. (Không có `/api/*` ở local: các lời gọi
`/api/...` sẽ 404 chứ **không** đi vào production — đăng nhập bằng mật khẩu không cần chúng.)

### 3.3 Kiểm tra chắc chắn (bắt buộc, TRƯỚC khi đăng nhập)
Terminal khác:
```bash
supabase/_localtest/rewards-manual/check_web_local.sh 5173
```
Mong đợi: `PASS: web app uses http://127.0.0.1:54321 (local)`. Nếu `FAIL` → dừng, bạn đang chạy sai mode
(`npm run dev` thường sẽ FAIL — đã thử). Script hỏi chính dev server module tạo Supabase client và đọc giá trị Vite tiêm vào.

Kiểm tra thứ hai, sau khi đăng nhập, trong DevTools → Console:
```js
Object.keys(localStorage).filter(k => k.startsWith('sb-'))
```
Mong đợi `['sb-127-auth-token']`. Nếu thấy `sb-ukchdgdnwytretvqjjqu-auth-token` thì phiên đang ở production → đăng xuất, dừng.
Tab Network cũng chỉ được thấy request tới `127.0.0.1:54321` (không có `supabase.co`).

> Không có màn hình dev nào hiện URL cho mọi người dùng. Có một bảng chẩn đoán ("supabase host") nhưng chỉ hiện cho tài khoản host
> sau khi chạm 5 lần vào tiêu đề "Hoàn tiền" ở màn Verifications — không cần dùng, hai cách trên đã đủ.

---

## 4. Seed dữ liệu test (CHỈ LOCAL)

```bash
cd supabase/_localtest/rewards-manual
./sql.sh 01_seed_local.sql
./sql.sh 02_seed_limit_account.sql
cd ../../..
```
`sql.sh` chỉ chạy qua `docker exec supabase_db_banbe` (container local), từ chối nếu container không chạy. File seed còn có
chốt chặn: dừng nếu DB có hơn 25 user không phải `@banbe-local.test`. Chạy lại được bất cứ lúc nào (đưa các tài khoản về trạng
thái ban đầu).

Mong đợi: `seed OK. Log in with e.g. rw.main@banbe-local.test / Banbe-Local-123 ...` và `rw.limit: tz=America/Chicago, changes_left=0 ...`.

| Tài khoản (mật khẩu `Banbe-Local-123`) | Trạng thái | Dùng cho |
|---|---|---|
| `rw.main@banbe-local.test` | qua cổng (SĐT xác minh + DOB **1995-05-05**, app hỏi lại DOB mỗi phiên) · đã đồng ý policy · **90 xu** (hàng ledger kiểu cũ) · chuỗi **3 ngày** kết thúc hôm qua · chưa có dòng múi giờ | A3–A6, A8–A10, B1–B4, B6 |
| `rw.fresh@banbe-local.test` | qua cổng · 0 xu · không streak · không có dòng `reward_user_settings` | A1, A2, A10, B5 |
| `rw.limit@banbe-local.test` | qua cổng · đã dùng đủ 2 lần đổi múi giờ trong 30 ngày (đang ở America/Chicago) | A7 |
| `rw.host@banbe-local.test` | organizer, sở hữu 3 sự kiện tương lai | chủ của sự kiện để thả tim |

Sự kiện để thả tim (`live`, công khai, 10/20/30 ngày nữa): **RW Local Event 1/2/3**. Nếu không thấy trên Home, tìm theo tên
"RW Local" ở Map/Search. (Sự kiện demo từ migration 010 đều ở năm 2024 nên đã qua.)

Gói công cụ SQL kèm theo (đều chạy bằng `./sql.sh <file> [email]` trong thư mục `rewards-manual`):

| File | Việc |
|---|---|
| `10_tz_fastforward.sql <email>` | làm yêu cầu đổi múi giờ **có hiệu lực ngay** (A6) |
| `11_tz_inspect.sql <email>` | xem zone đã lưu / đang chờ / hiệu lực / số lần đổi |
| `12_tz_reset_user.sql <email>` | xóa lựa chọn múi giờ của 1 tài khoản (về "chưa từng chọn") |
| `13_numbers.sql <email>` | số xu, số ngày active, ngày active cuối, số tim — để đối chiếu với app (chạy được cả khi chưa có 177) |

> Đã kiểm chứng: toàn bộ SQL ở đây chạy đúng trên DB harness `banbe-pg` (đã áp 177) trong một transaction rollback —
> `get_my_rewards` của rw.main trả balance 90, streak 3; đổi múi giờ → fast-forward → có hiệu lực; rw.limit bị từ chối
> `TZ_CHANGE_LIMIT`; đổi thử comet trừ 90→50. **Chưa kiểm chứng:** harness chỉ có `auth.users` giả, nên phần tạo
> `auth.users`/`auth.identities` đúng cột của GoTrue và việc đăng nhập mật khẩu thật chưa chạy được. Nếu đăng nhập báo sai
> thông tin dù đúng mật khẩu, đó là chỗ cần xem (xem bước 9).

---

## 5. Đăng nhập thử (web)

1. Mở http://localhost:5173, đăng nhập bằng **mật khẩu**: `rw.main@banbe-local.test` / `Banbe-Local-123`.
2. Nếu hỏi DOB: `1995-05-05`. Nếu hiện onboarding/câu hỏi sở thích: bỏ qua/điền nhanh.
3. Vào **Account → Rewards & badges** (hoặc http://localhost:5173/profile/rewards).

Mong đợi: số dư **90**, chuỗi **3**, có mục "Múi giờ cho chuỗi ngày" ở trên "How earning works".

---

## 6. iOS Simulator trỏ về backend local

Simulator dùng chung mạng với Mac nên dùng **`127.0.0.1`** (đúng với địa chỉ literal, ATS không chặn http cho IP). Chỉ máy thật
mới cần IP LAN của Mac (ngoài phạm vi, nằm ở mục C của checklist).

### 6.1 Trỏ app về local (sửa tạm)
```bash
supabase/_localtest/rewards-manual/ios-point-local.sh
git diff --stat apps/ios      # chỉ SupabaseService.swift đổi
```
Script thay 3 dòng trong `AppConfig`: `supabaseURL` → `http://127.0.0.1:54321`, `supabaseAnonKey` → key local
(lấy từ `supabase status -o env`), `apiBaseURL` → `http://127.0.0.1:9` (không ai lắng nghe → mọi lời gọi `/api/*`
thất bại thay vì chạm production). Mong đợi in ra hai dòng `static let ...` mới và "REMINDER: run ./ios-restore.sh".

### 6.2 Build và chạy
```bash
cd apps/ios
xcodegen generate
xcodebuild -project BanbeApp.xcodeproj -scheme BanbeApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/dd build
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null; open -a Simulator
APP=$(find build/dd -name BanbeApp.app -path '*Debug-iphonesimulator*' | head -1)
xcrun simctl install booted "$APP"
xcrun simctl launch booted "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
cd ../..
```
(Hoặc mở `BanbeApp.xcodeproj` trong Xcode, chọn simulator, Run.) Mong đợi: app mở màn splash rồi đăng nhập.

### 6.3 Chắc chắn đang ở local
- Đăng nhập được bằng `rw.main@banbe-local.test` — tài khoản này chỉ tồn tại trong DB local.
- `docker logs --tail 20 supabase_kong_banbe` có dòng `POST /auth/v1/token?grant_type=password` vừa xảy ra.

### 6.4 Xong thì khôi phục
```bash
supabase/_localtest/rewards-manual/ios-restore.sh      # git checkout file đó → khớp HEAD
git status --short apps/ios                            # phải trống
```

---

## 7. Chuẩn bị cho từng mục A1–A10 và B1–B8

Trước khi bắt đầu mỗi nhóm: `./sql.sh 01_seed_local.sql` (+ `02_seed_limit_account.sql` cho A7) để về trạng thái gốc.
Dưới đây `E` = email tài khoản; `SQL` nghĩa là chạy trong `supabase/_localtest/rewards-manual`.

### A. Múi giờ (cần 177 — stack mặc định của bước 2 đã có)

| # | Tài khoản | Chuẩn bị / thao tác | Kiểm bằng DB (`./sql.sh 11_tz_inspect.sql E`) |
|---|---|---|---|
| A1 | rw.fresh | không cần gì; đăng nhập, mở Rewards | `stored_tz` rỗng, `changes_recorded` rỗng (không có dòng settings), `effective_tz_now = Asia/Ho_Chi_Minh` |
| A2 | rw.fresh | **Web:** DevTools → ⋮ → More tools → **Sensors** → Location = Other… → *Timezone ID* `America/Chicago`, tải lại trang. Hoặc mở Chrome riêng: `TZ=America/Chicago "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --user-data-dir=/tmp/chrome-chicago http://localhost:5173`. **iOS:** simulator theo múi giờ của Mac — ghi lại bằng `sudo systemsetup -gettimezone`, đổi `sudo systemsetup -settimezone America/Chicago`, khởi động lại app; **nhớ đặt lại** sau đó. | vẫn không có dòng settings (không tự gán) |
| A3 | rw.main | chọn **US – Eastern** | `pending_tz = America/New_York`, `pending_from_ts` = nửa đêm VN kế tiếp, `changes_recorded = 1`, `effective_tz_now` vẫn Asia/Ho_Chi_Minh |
| A4 | rw.main (tiếp A3) | chọn lại **Việt Nam** | `pending_tz` rỗng, `changes_recorded = 0` (hủy miễn phí) |
| A5 | rw.main | chọn Eastern rồi Pacific | `pending_tz = America/Los_Angeles`, `changes_recorded = 1` (thay thế, không tính thêm) |
| A6 | rw.main | từ A5 chọn lại **Eastern**, rồi **fast-forward**: `./sql.sh 10_tz_fastforward.sql rw.main@banbe-local.test` → tải lại trang Rewards (hoặc kéo để làm mới) | `effective_tz_now = America/New_York`. Lưu ý: 3 ngày seed là **ngày theo giờ VN**; khi sang múi giờ phía tây, cùng ngày đó đọc theo giờ mới nên "Today's counted" có thể bật. Streak vẫn **3**, không bị reset — đó là điều A6 cần |
| A7 | rw.limit | seed `02_...` đã tạo sẵn 2 lần đổi hiệu lực (10 và 3 ngày trước). Đăng nhập → picker phải bị vô hiệu | `changes_recorded = 2`; việc server từ chối `TZ_CHANGE_LIMIT` được phủ bởi `14_rewards_timezone_run.sh` (không gọi trực tiếp từ psql được vì cổng DOB theo phiên). **Cách B (thuần UI):** rw.fresh → chọn Eastern → fast-forward → chọn Pacific → fast-forward → picker phải bị vô hiệu |
| A8 | bất kỳ | đổi ngôn ngữ VI ↔ EN | — |
| A9 | rw.main | **Web:** DevTools → Network → *Offline*. **iOS:** `docker stop supabase_kong_banbe` (cổng API), đổi múi giờ, rồi `docker start supabase_kong_banbe`. Mong đợi "Network error. Nothing was changed." | `changes_recorded` không tăng; tải lại → picker về giá trị cũ |
| A10 | rw.main ↔ rw.fresh | đăng xuất/đăng nhập qua lại | mỗi tài khoản tự hiện zone của mình, không nháy zone tài khoản trước |

Đưa 1 tài khoản về "chưa từng chọn" giữa các mục: `./sql.sh 12_tz_reset_user.sql rw.main@banbe-local.test`.

### B. Rewards "cũ" không được hỏng

| # | Chuẩn bị / thao tác | Kiểm bằng DB |
|---|---|---|
| B1 | **Đưa DB về migration 176** — xem bước 8. Sau đó seed lại, chạy web, đăng nhập rw.main | `to_regclass('public.reward_user_settings')` rỗng; mục múi giờ vắng; số dư 90, chuỗi 3, huy hiệu/lịch sử/catalog/luật đều hiện |
| B2 | rw.main: so sánh nút 🔥 và xu ở header Home với trang Rewards | `./sql.sh 13_numbers.sql rw.main@banbe-local.test` → `coin_balance 90`, `active_days 3` |
| B3 | rw.main (90 xu): đổi **comet (40)** — hộp xác nhận → "Unlocked!"; thử bấm đúp | số dư 50, chỉ **1** dòng redemption: `docker exec supabase_db_banbe psql -U postgres -Atc "select count(*) from reward_ledger l join auth.users u on u.id=l.user_id where u.email='rw.main@banbe-local.test' and l.entry_type='redemption'"` → `1`. Làm lại B3: chạy lại seed 01 |
| B4 | rw.main: **crown (120)** khi còn 90 xu → "30 more needed"; sau B3 (còn 50) thì lantern(80) "30 more needed", crown "70 more needed" | — |
| B5 | rw.fresh: thả tim "RW Local Event 1" → streak **1** / "Today's counted"; bỏ tim rồi thả lại cùng ngày → vẫn 1 | `13_numbers.sql` → `favorites 1`, `active_days 1` |
| B6 | rw.main, trong luồng ở bước 8: ghi `13_numbers.sql` ở 176, nâng lên 177, ghi lại | hai lần giống hệt (`coin_balance 90`, `active_days 3`); app cũng hiện cùng số. Hàng ledger seed có `period_month` rỗng = đúng dạng "legacy". Số "attendance cap" là 0/10 ở cả hai lần (seed không tạo attendance) |
| B7 | iOS **bản cũ** (trước 177) chạy với server có 177 — xem bước 9 | Rewards hiển thị bình thường, không có mục múi giờ |
| B8 | web **bản cũ** chạy với server có 177 — xem bước 9 | như B7 |

---

## 8. B1 — đưa DB local về đúng migration 176 rồi nâng lại 177

### Cách 1 (đúng thực tế nhất, khuyên dùng)
```bash
supabase db reset --version 20261218000176 --no-seed     # dựng lại DB, chỉ áp dụng đến 176
docker exec supabase_db_banbe psql -U postgres -Atc "select to_regclass('public.reward_user_settings')"   # in dòng rỗng
supabase/_localtest/rewards-manual/sql.sh 01_seed_local.sql      # sql.sh chạy được từ mọi thư mục; đường dẫn file tính từ thư mục rewards-manual
```
Reset xóa mọi user nên **phải seed lại** và
đăng nhập lại. `01_seed_local.sql` không dùng bảng 177 nên chạy được ở 176. Đừng chạy `02_seed_limit_account.sql` ở trạng thái này.
Đo số B6 (`13_numbers.sql`), kiểm B1, rồi nâng lại:
```bash
supabase migration up            # áp dụng 177 (+178), GIỮ nguyên dữ liệu
docker exec supabase_db_banbe psql -U postgres -Atc "select to_regclass('public.reward_user_settings')"   # reward_user_settings
```
Hoặc dựng lại sạch: `supabase db reset --no-seed` + seed 01, 02.

### Cách 2 (nhanh, giữ dữ liệu; chỉ mô phỏng "server không có 177")
Dùng rollback an toàn dữ liệu của chính repo (khôi phục thân hàm 165, bỏ RPC `set_my_reward_timezone`, giữ bảng/cột trơ):
```bash
cd supabase/_localtest/rewards-manual
./sql.sh ../../rollbacks/20261218000177_177_revert_user_timezone_functions.sql   # server "không có 177": get_my_rewards hết khóa timezone_settings
# ... thử B1 ...
./sql.sh ../../migrations/20261218000177_177_user_reward_timezone.sql            # đưa lại 177 (idempotent)
```
Đã chạy thử trên harness: sau rollback `get_my_rewards` không còn khóa `timezone_settings`; áp lại 177 đưa khóa về và giữ nguyên zone
của user. Cách 2 không tái hiện việc bảng chưa tồn tại, nên B1 "chính thức" nên dùng Cách 1.

---

## 9. B7/B8 — chạy bản cũ (trước 177) với server có 177

Commit ngay trước 177 là `e399694` (177 là `7068900`). Dùng một git worktree riêng, không đụng nhánh hiện tại:
```bash
git worktree add ../banbe-pre177 e399694
ln -s "$PWD/node_modules" ../banbe-pre177/node_modules
```
Đảm bảo DB đang ở 177 (bước 2.3).

### B8 — web cũ
```bash
supabase/_localtest/rewards-manual/make_web_env.sh ../banbe-pre177
cd ../banbe-pre177 && npm run dev -- --mode rewardslocal --port 5174
```
Ở terminal khác: `supabase/_localtest/rewards-manual/check_web_local.sh 5174` → PASS rồi mới đăng nhập (http://localhost:5174).
Mong đợi: trang Rewards chạy bình thường, **không** có mục múi giờ, không báo lỗi. (Nếu worktree thiếu file sinh tự động nào đó,
chạy `npm run build:keychains` trong worktree.)

### B7 — iOS cũ
```bash
supabase/_localtest/rewards-manual/ios-point-local.sh "$(cd ../banbe-pre177 && pwd)"
cd ../banbe-pre177/apps/ios && xcodegen generate
xcodebuild -project BanbeApp.xcodeproj -scheme BanbeApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/dd build
APP=$(find build/dd -name BanbeApp.app -path '*Debug-iphonesimulator*' | head -1)
xcrun simctl install booted "$APP" && xcrun simctl launch booted "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
```
Bản này ghi đè bản mới trên simulator (cùng bundle id). Đăng nhập rw.main → Rewards: hiển thị bình thường, không có mục múi giờ.
Muốn quay lại bản mới: build lại từ repo chính (bước 6.2).

---

## 10. Dọn dẹp

```bash
supabase/_localtest/rewards-manual/ios-restore.sh                 # iOS về production values (repo chính)
git worktree remove --force ../banbe-pre177                       # nếu đã tạo ở bước 9
rm -f .env.rewardslocal.local
supabase stop                                                     # giữ dữ liệu; thêm --no-backup để xóa hẳn
docker start banbe-pg                                             # nếu muốn dùng lại harness 13/14/15
sudo systemsetup -settimezone <múi giờ gốc của bạn>               # nếu đã đổi ở A2
git status --short                                                # không được còn thay đổi ngoài docs/ mới
```

---

## 11. Xử lý sự cố nhanh

| Triệu chứng | Nguyên nhân thường gặp |
|---|---|
| `supabase start`: port 54322 already allocated | `banbe-pg` chưa dừng (bước 2.1) |
| `db reset`/`start` lỗi `handle ... not-null` | seed gốc hỏng; dùng `--no-seed` |
| `check_web_local.sh` FAIL | chạy `npm run dev` thường; dùng `-- --mode rewardslocal` và `make_web_env.sh` |
| Đăng nhập: "Invalid login credentials" dù đúng mật khẩu | phần tạo user trong seed là phần chưa chạy thử với GoTrue thật; kiểm `docker exec supabase_db_banbe psql -U postgres -c "select email, encrypted_password is not null, email_confirmed_at from auth.users where email like 'rw.%'"`; hoặc tạo user bằng Studio (http://127.0.0.1:54323 → Authentication → Add user, *Auto Confirm*) rồi chạy lại seed (nó cập nhật mật khẩu theo id cố định nên cần dùng đúng email — nếu lệch, báo lại để chỉnh script) |
| Mọi RPC trả `GATE_REQUIRED` | chưa xác nhận DOB trong phiên (`1995-05-05`) |
| Không thấy sự kiện "RW Local" trên Home | tìm bằng Search/Map; sự kiện có `status=live`, `visibility=public`, bắt đầu trong tương lai |
| Lời gọi `/api/...` lỗi 404 trên web | bình thường: Vite không phục vụ `/api`; các thử nghiệm này không cần |

---

## 12. Những gì CHƯA được kiểm chứng (nói thẳng)

- `supabase` CLI chưa cài trên máy lúc soạn, nên **các lệnh `supabase start / db reset --version / migration up / status`
  chưa được chạy**; chúng viết theo cách dùng chuẩn của CLI. Riêng cờ `--version` của `db reset` và việc `start` có tự chạy seed
  hay không cần xác nhận khi chạy thật.
- Đã chạy thật: `check_web_local.sh` (PASS ở mode `rewardslocal`, FAIL ở mode thường), `ios-point-local.sh` (trên bản sao
  file), và toàn bộ SQL (seed, đổi múi giờ, fast-forward, giới hạn A7, rollback/áp lại 177) trên DB harness `banbe-pg`.
- Chưa chạy: build iOS và đăng nhập mật khẩu qua GoTrue thật; hiển thị "RW Local Event" trên Home.
- Mục C của checklist (bố cục picker trên máy nhỏ, dark mode, VoiceOver, Dynamic Type, nửa đêm thật ở múi giờ khác Việt Nam)
  vẫn phải thử trên thiết bị thật.

---

## Bước 3b: đưa DB local về 178 rồi nâng lên 179 (bổ sung)

Mục đích: kiểm tra cả hai chế độ (server cũ chưa có 179 và server mới) bằng cùng một DB local. **Chưa kiểm chứng trên máy này:** `supabase` CLI chưa
cài khi soạn bổ sung này; hãy xác nhận cờ `--version` bằng `supabase db reset --help` trước khi chạy. Mọi lệnh chỉ chạm DB local (`supabase_db_banbe`).

1. **Về đúng 178 (chưa có 179):**
   ```bash
   supabase db reset --no-seed --version 20261219000178
   docker exec supabase_db_banbe psql -U postgres -Atc "select to_regclass('public.reward_feature_flags')"
   ```
   Mong đợi: câu thứ hai in dòng rỗng (bảng cờ chưa tồn tại). Seed lại tài khoản: `cd supabase/_localtest/rewards-manual && ./sql.sh 01_seed_local.sql && ./sql.sh 02_seed_limit_account.sql`.
   Làm các kiểm tra **E1** (và **E3** nếu muốn về 176: `--version 20261218000176`).
2. **Nâng lên 179:**
   ```bash
   supabase migration up
   docker exec supabase_db_banbe psql -U postgres -Atc "select flag, enabled from reward_feature_flags"
   ```
   Mong đợi: `partner_offers|f`. Chạy lại seed tài khoản nếu `migration up` không giữ dữ liệu như bạn cần (nó giữ dữ liệu; chỉ `db reset` mới xoá).
3. **Tạo dữ liệu ưu đãi và bật/tắt cờ (thủ công, chỉ local; chưa có RPC bật/tắt cờ):**
   ```bash
   docker exec supabase_db_banbe psql -U postgres -c "insert into reward_catalog(code,kind,design_id,price,sort,title_vi,title_en,desc_vi,desc_en) values ('offer-x','partner_offer',null,50,40,'Ưu đãi X','Offer X','mô tả','description') on conflict do nothing"
   docker exec supabase_db_banbe psql -U postgres -c "update reward_feature_flags set enabled=true  where flag='partner_offers'"   # bật  (D2)
   docker exec supabase_db_banbe psql -U postgres -c "update reward_feature_flags set enabled=false where flag='partner_offers'"  # tắt  (D1, D7)
   ```
   Làm các kiểm tra **D1–D8** trong `rewards-phase0-manual-checks.md`.
4. **Client cũ với server 179 (E2):** build web/iOS từ commit trước 3b (`git stash` hoặc worktree ở commit `e5b5a0c`) và trỏ vào cùng DB 179 có cờ bật.

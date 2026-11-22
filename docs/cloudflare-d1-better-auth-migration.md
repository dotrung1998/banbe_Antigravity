# Cloudflare D1 + Better Auth — đánh giá và spike

Cập nhật 2026-11-21. Tài liệu này tách rõ **đã chứng minh** với **đã migrate**.
Production vẫn là Supabase (Postgres + Auth + RLS + Realtime + Storage); chưa có
bảng nào, user nào hay request production nào được chuyển sang D1/Better Auth.

## 0. Kết luận ngắn

| Câu hỏi | Trả lời |
|---|---|
| Video 200Lab có đề xuất D1, Workers, Better Auth, R2, Email Sending, SePay, security-audit skill? | **Có.** Transcript đã lấy được; xem mục 1. |
| Đã cài skill security review của Cloudflare? | **Có**, tại `.agents/skills/security-audit`, pin trong `skills-lock.json`. |
| Đã dựng D1 + Better Auth chạy thật? | **Có**, spike local trong `cloudflare/auth-spike`: 2 migration D1, Better Auth 1.7.27, 8/8 check pass. |
| Đã chuyển app production sang D1/Better Auth? | **Chưa.** Không thể làm đúng và verify trong một lượt; xem mục 3–4. |
| Có nên chuyển chỉ để giảm chi phí? | **Không.** Ở quy mô hiện tại chênh lệch khoảng **$15/tháng**; đổi lại là rewrite nhiều tuần/tháng và rủi ro auth/iOS. |
| Khi nào nên chuyển? | Khi cần độc lập khỏi Supabase, hoặc Supabase Free/Pro không còn đáp ứng; đi theo phase, không big-bang. |

## 1. Video nói gì (fact-check)

Video: “Hướng dẫn Build & Deploy một App lên Cloudflare | 200Lab”, 9:12,
đăng 2026-11-19. Transcript lấy từ YouTubeToTranscript ngày 2026-11-21.

Các khuyến nghị chính, đúng như bạn nhớ:

- **Workers Paid $5/tháng** cho app production; Cloudflare cho phép dùng thương mại,
  khác Vercel Hobby (chỉ phi thương mại).
- **D1** (SQLite trên edge) làm database; đọc tính theo **row bị scan**, nên cột
  dùng để lọc phải có index. Video nhấn mạnh “indexing là bắt buộc”.
- **Better Auth** thay Supabase Auth/Clerk; lưu user/session trong D1, không có
  giới hạn session 7 ngày kiểu gói free của Clerk. Video nói cần cập nhật thường
  xuyên vì bản 3/11 đã vá 12 lỗ hổng.
- **R2** cho file/ảnh: 10 GB free, egress $0.
- **Cloudflare Email Sending** cho email giao dịch: 3.000 email/tháng trong gói $5.
- **SePay** cho VietQR/webhook ngân hàng tại Việt Nam (video nói “Stripe” ở một
  đoạn là lỗi transcript/dịch; SePay mới là phần được demo).
- **Cloudflare security-audit skill**: cài từ repo Cloudflare, cho agent audit toàn
  bộ codebase, và **audit nhiều lần** vì một lần chỉ tìm được khoảng một nửa số lỗi
  so với nhiều lần cộng lại.
- **Turnstile** cho form đăng ký và **rate limit** để chống spam/abuse.

Lưu ý về transcript tự động: đoạn “Vercel là tool của Cloudflare dựa trên Vite,
hỗ trợ 94% Next.js 16 API, thay OpenNext” thực tế nói về **Vinext**, không phải
Vercel. Đừng dùng câu đó để kết luận “Vercel là của Cloudflare”.

## 2. Vì sao video không phải hướng dẫn migrate app đang chạy

Video dựng một app mới trong 30–40 phút. banbe không phải app mới:

| Hạng mục | Hiện tại |
|---|---:|
| Migration Postgres | **224 file** |
| Bảng public / auth | **120 / 27** |
| Hàm/RPC được gọi từ web/iOS | **hơn 140 điểm gọi** |
| Vercel functions | **12** |
| Cron / job nền | 3 cron Vercel + `push-drain` do DB gọi |
| RLS policy, trigger, PL/pgSQL | Có, là nguồn phân quyền chính |
| Realtime | Supabase Realtime |
| Storage private | Supabase Storage + signed URL/policy |
| Client | Web Vite React + **iOS dùng chung Supabase Auth/PostgREST** |
| Dữ liệu production lúc backup | 14 auth user, 36 event, 41 booking |

D1 là SQLite: **không có RLS, PL/pgSQL, extension, `pg_cron`, `pg_net`, Vault**.
Mỗi policy/RPC phải viết lại thành kiểm tra tường minh trong Worker. Better Auth
thay được phần auth, nhưng không thay được RLS/RPC/Realtime. iOS đang giữ session
Supabase và gọi thẳng PostgREST; đổi auth/DB mà không phát hành iOS mới sẽ làm app
iOS hỏng.

Vì vậy “chuyển phần còn lại” là một chương trình nhiều phase, không phải một PR.
Bất kỳ tuyên bố “đã chuyển xong” nào trong lúc này đều là sai.

## 3. Đã làm thật trong lượt này

### 3.1. Spike D1 + Better Auth

Thư mục `cloudflare/auth-spike/` (không nối vào app, không deploy):

- `wrangler.jsonc`: Workers, `compatibility_date` 2026-11-21, `nodejs_compat`,
  D1 binding `DB` (database id local placeholder).
- `migrations/0001_better_auth.sql`: 4 bảng core `user`, `session`, `account`,
  `verification` + index.
- `migrations/0002_notes.sql`: bảng `notes` có `user_id`, index trên `user_id`.
- `src/worker.js`: Better Auth với `database: env.DB`, `baseURL`/`trustedOrigins`
  lấy từ env, `cf-connecting-ip` cho rate limit; API notes đọc session bằng
  `auth.api.getSession({ headers })` và **chỉ** dùng `session.user.id` trong SQL.
- `scripts/verify-cloudflare-auth-spike.mjs`: tự chạy Wrangler local, tạo hai tài
  khoản, kiểm tra cách ly và SQL injection, rồi tắt server.

Bằng chứng chạy:

```text
npm run cf:auth:migrate
  0001_better_auth.sql  ✅
  0002_notes.sql        ✅

npm run cf:auth:verify
  PASS health: local D1 reachable on workerd
  PASS no session: notes request is 401
  PASS account A: sign-up + session
  PASS account B: sign-up + session
  PASS B sees zero notes before creating one
  PASS B cannot list A's note
  PASS B cannot delete A's note
  PASS SQL-injection text stays text: bind(), table intact
  PASS sign-out invalidates A; B's session is unaffected

8/8 checks passed
```

Đây là bằng chứng cho **phần khó nhất của auth**: Better Auth 1.7.27 chạy trên
`workerd`, D1 là database, session cookie hoạt động, sign-out có hiệu lực, và
không có RLS thì vẫn cách ly được nếu mọi query bind `session.user.id`.

### 3.2. Security skill

Đã cài:

```bash
npx skills add https://github.com/cloudflare/security-audit-skill \
  --skill security-audit --copy
```

- Skill: `.agents/skills/security-audit/`
- Pin: `skills-lock.json`, commit `c1c8a8c1471069fb0e188eeaff69b8e8db6564a8`
- Cách gọi: nói với agent “security audit this codebase” hoặc “find security
  vulnerabilities in ./src”; skill tự kích hoạt.
- Full audit cần sub-agent độc lập + sandbox OS cho build/test; lượt này **chưa
  chạy full 6-phase audit**, chỉ chạy baseline dependency + review các bề mặt đã
  sửa. Không ghi nhận là đã audit toàn bộ.

Xem `docs/security/2026-11-21-security-baseline.md` để biết kết quả dependency và
các hardening đã làm.

## 4. Lộ trình nếu tiếp tục migrate (không big-bang)

Mỗi phase có gate và rollback riêng. Không phase nào được coi là xong nếu chưa có
test hai tài khoản + test quyền + đo D1 rows scanned.

### Phase 0 — Spike (đã xong)

Gate: Better Auth + D1 chạy local, session, sign-out, cách ly tenant, SQL injection.
Trạng thái: **đạt 8/8**.

### Phase 1 — Inventory và hợp đồng dữ liệu

- Liệt kê từng bảng/RPC/RLS/trigger/cron/Realtime/Storage và client nào gọi.
- Phân loại: public read, tenant read, tenant write, money, private media,
  admin, realtime.
- Chốt “hợp đồng” API web/iOS trước khi đổi backend.
- Gate: không còn module “chưa biết”; có bảng mapping Postgres → D1 và mapping
  RPC → Worker handler.
- Rollback: không đổi production.

### Phase 2 — Auth parity

- Better Auth: email/password, OAuth Google/Facebook, phone OTP, DOB gate,
  account deletion, admin role, session refresh.
- Migrate 14 user (password hash phải re-hash hoặc reset; Better Auth không đọc
  trực tiếp hash Supabase).
- Viết client iOS mới hoặc adapter session; đây là phần không thể bỏ qua.
- Gate: login/reset/OAuth/phone trên web + iOS; hai tài khoản không thấy nhau;
  token refresh; sign-out mọi thiết bị.
- Rollback: giữ Supabase Auth chạy song song, feature flag chọn provider.

### Phase 3 — Read-only discovery trên D1

- Chỉ port các read path public (Home/Browse/Search/Map/Event public) sang D1
  replica; đồng bộ một chiều từ Postgres.
- Tạo index theo đúng cột filter/sort; đo rows scanned, p95, cache hit.
- Gate: kết quả khớp Postgres theo fixture; D1 rows read trong ngân sách; có
  fallback Supabase khi D1 lỗi.
- Rollback: tắt read flag, quay lại PostgREST.

### Phase 4 — Workers API (bounded)

- Port từng endpoint ít rủi ro: public share, media read, health, feature flags.
- Email: thay SMTP `nodemailer` bằng HTTP API (Resend) hoặc Cloudflare Email
  Sending; không port SMTP vào Workers.
- Wallet pass / APNs / PDF: giữ dịch vụ riêng nếu thư viện không chạy Workerd.
- Gate: parity response/status/header; rate limit; Turnstile cho form public.
- Rollback: route theo path về Vercel cũ.

### Phase 5 — Writes, booking, tiền

- Port `hold_seats`/`claim_seats`/`verify_payment`/refund/dispute theo thứ tự.
- D1 không có transaction tương tác; dùng `batch()` và idempotency key; kiểm tra
  double-book, hold hết hạn, webhook trùng.
- Mọi query tenant phải có `WHERE user_id = ?`/`organizer_id = ?`; test cross-tenant.
- Gate: concurrency test, replay webhook, refund/rollback, audit log.
- Rollback: dual-write hoặc tắt write flag; không xoá dữ liệu Supabase.

### Phase 6 — Private media, Realtime, jobs

- R2 private + signed URL; policy thay bằng kiểm tra Worker.
- Realtime thay bằng Durable Objects (WebSocket) hoặc poll có kiểm soát.
- Cron/queue thay `pg_cron`/`pg_net`.
- Gate: hai client realtime, reconnect, unauthorized room; signed URL hết hạn.
- Rollback: giữ Supabase Storage/Realtime song song.

### Phase 7 — Cutover

- Dual-run, so sánh số liệu, backup D1 + Postgres, DNS/domain.
- Gate: rollback đã diễn tập; on-call; không có chức năng nào chỉ có một bản.
- Rollback: đổi DNS/flag về Vercel + Supabase; dữ liệu D1 giữ nguyên để điều tra.

## 5. Chi phí: con số và cái bẫy

Theo video (cần đối chiếu trang giá Cloudflare tại thời điểm mua):

| Hạng mục | Cloudflare Workers Paid | Hiện tại |
|---|---:|---:|
| Compute/hosting | $5/tháng | Vercel Pro $20/seat (bắt buộc cho thương mại) |
| DB | D1 nằm trong $5 (25B row read, 50M row write, 5 GB) | Supabase Free $0 hoặc Pro $25 |
| Ảnh public | R2 10 GB free, egress $0 | R2 đã dùng |
| Email | 3.000/tháng trong $5 | Resend/Gmail |
| Auth | Better Auth $0 | Supabase Auth nằm trong DB |

Ở quy mô hiện tại (14 user, 36 event), chi phí thật đang là **Vercel Pro ~$20 +
Supabase Free $0 + R2 ~$0**. Cloudflare ~$5 + domain. Chênh lệch khoảng
**$15/tháng**, tức ~$180/năm. Đổi lại là Phase 1–7 ở trên, cộng rủi ro mất
booking/hoàn tiền nếu cutover sai.

Kết luận chi phí: **không chuyển chỉ vì tiền**. Chuyển vì muốn độc lập khỏi
Supabase, muốn edge latency, hoặc Supabase không còn đáp ứng. Nếu chỉ muốn giảm
chi phí ngay, hạ Supabase Free + giữ R2 + redeploy web (xem
`docs/cloudflare-sepay-migration.md`) rẻ hơn nhiều.

## 6. Security gates cho app thương mại

- **D1 không có RLS**: một helper `requireUser(request)` duy nhất; không nhận
  `userId` từ body/query/path; mọi query tenant có `WHERE user_id = ?`; test hai
  tài khoản cho từng endpoint.
- **Index**: mọi cột filter/sort/join phải có index; D1 tính row scan, không phải
  query. Đo trước/sau khi port.
- **Better Auth**: pin version, đọc changelog bảo mật, cập nhật ngay khi có bản vá;
  bật rate limit; dùng `cf-connecting-ip`; `trustedOrigins` đúng origin.
- **Turnstile** cho đăng ký/form public; rate limit ở Worker + Cloudflare.
- **Secret**: `wrangler secret put`; `.dev.vars`/`.env` không commit; không log
  cookie/token/URL signed.
- **Email**: escape href, chặn CR/LF ở subject, không đưa token vào URL nếu không
  cần; nếu buộc phải có, `Referrer-Policy: no-referrer`.
- **Audit nhiều lần**: cài skill, chạy full audit ít nhất 3 lần trên các mốc khác
  nhau (sau auth, sau money, trước cutover), mỗi lần lưu report và đối chiếu.
- **Backup**: D1 export + R2 backup; diễn tập restore trước cutover.

Hiện trạng bảo mật: xem `docs/security/2026-11-21-security-baseline.md`. Audit
2026-11-19 đã đóng phần lớn lỗ hổng P0/P1; còn 2 việc owner (rotate mật khẩu test
đã lộ trong git history, xác nhận migration 183/ACL trên production) và 2 cảnh báo
dependency `high` chưa xử lý.

## 7. Rollback của lượt này

- Không có thay đổi production, không deploy, không `supabase db push`, không
  `wrangler deploy`, không ghi D1 remote.
- Spike nằm trong `cloudflare/auth-spike/`, có thể xoá bằng `rm -rf` mà không ảnh
  hưởng app.
- `npm audit fix` chỉ đổi lockfile trong phạm vi semver; nếu cần rollback:
  `git checkout -- package-lock.json package.json` (nhưng sẽ mất bản vá dependency).
- Các hardening API là thay đổi nhỏ, có test; rollback bằng revert file tương ứng.

## 8. Việc còn thiếu (owner / phase sau)

- [ ] Chốt có làm Phase 1–7 hay không; nếu không, giữ Supabase và chỉ tối ưu chi phí.
- [ ] Nếu làm: lập inventory đầy đủ và chọn vertical đầu tiên (đề xuất: public
      discovery read-only) trước khi chạm auth.
- [ ] Tạo D1 remote + Worker staging; chạy `wrangler d1 migrations apply --remote`
      trên môi trường test, không phải production.
- [ ] Đo D1 rows scanned/p95 trên dữ liệu thật (36 event hiện tại quá nhỏ; cần
      fixture lớn hơn).
- [ ] Viết adapter iOS hoặc client mới; không phát hành iOS hỏng.
- [ ] Chạy full security audit 6 phase trước cutover.
- [ ] Xử lý 2 dependency `high` còn lại (xem baseline).
- [ ] Rotate mật khẩu test account đã lộ trong git history (audit 2026-11-19 row 5).

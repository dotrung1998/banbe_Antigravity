# Security baseline — Cloudflare skill + dependency audit

Ngày 2026-11-21. Đây là **baseline**, không phải full 6-phase security audit.
Không có endpoint production nào bị probe, không có credential nào bị đọc/in.

> **Cập nhật cùng ngày:** đợt audit thật, có fix và proof, nằm ở
> [`2026-11-21-audit.md`](./2026-11-21-audit.md). Tài liệu đó thay thế các kết
> luận còn treo dưới đây về `joi`, Host header và RLS direct-write; baseline
> này giữ lại lịch sử trước fix.

## 1. Skill đã cài

```bash
npx skills add https://github.com/cloudflare/security-audit-skill \
  --skill security-audit --copy
```

| Trường | Giá trị |
|---|---|
| Nguồn | `cloudflare/security-audit-skill` (MIT) |
| Commit pin | `c1c8a8c1471069fb0e188eeaff69b8e8db6564a8` |
| Đường dẫn local | `.agents/skills/security-audit/` |
| Lock | `skills-lock.json` → `security-audit` |
| Kích hoạt | “security audit this codebase”, “find security vulnerabilities in ./src” |
| Full audit cần | Agent có sub-agent song song + sandbox OS cho build/test; chưa chạy trong lượt này |

Skill này là bản single-repo của vulnerability harness Cloudflare. Nó có 6 phase:
recon → coverage-led hunting → candidate validation → structured findings →
independent verification → report. Điểm quan trọng: **một lần audit không đủ**;
Cloudflare nói một lần chỉ tìm được khoảng một nửa so với nhiều lần cộng lại.

## 2. Dependency audit

Trước:

```text
npm audit (full): 11 vulnerabilities (high)
```

Sau `npm audit fix` (không dùng `--force`):

```text
npm audit (full): 2 vulnerabilities
  2 high
  - joi <=17.13.8 (qua passkit-generator)
  - passkit-generator >=3.1.3
```

Đã cập nhật trong phạm vi semver: `nodemailer 10.0.1 → 10.6.1`,
`passkit-generator 3.6.1 → 3.7.0`, `puppeteer-core 25.11.0 → 25.18.1`,
`node-forge 1.4.0 → 1.4.3`, `vite`, `zod`, `follow-redirects`, `source-map-js`.

Còn lại:

| Package | Vì sao | Đánh giá |
|---|---|---|
| `joi@17.13.4` | `passkit-generator@3.7.0` pin đúng version này | Advisory gồm prototype pollution khi **schema/messages do kẻ tấn công kiểm soát**, ReDoS ở `isoDate()` và `email({multiple:true})`. Trong repo, Joi chỉ dùng để validate schema pass nội bộ; chưa chứng minh được input người dùng đi vào các đường đó. **Không coi là đã sạch.** |
| `passkit-generator` | Kéo `joi` lỗi | `npm audit fix --force` sẽ **hạ** passkit xuống 3.1.2 (breaking, rủi ro Wallet pass). Không áp dụng. Cần owner quyết định: thay thư viện, tự ký pass, hoặc chấp nhận có ghi chú. |

`npm audit` chỉ là một lớp; nó không thay RLS test, auth test hay code audit.

> **Đã đóng ngày 2026-11-21:** `package.json` override `joi@17.13.9` (không
> downgrade `passkit-generator`); `npm audit` hiện `found 0 vulnerabilities`.
> Reachability của hai advisory được ghi ở mục H-10 của audit report.

## 3. Hardening đã làm trong lượt này

| File | Thay đổi | Test |
|---|---|---|
| `api/_lib/authLookup.js` | `getRedirectUrl` chỉ nhận `http(s)`, bắt buộc HTTPS ngoài localhost, bỏ credential, giữ path; không còn nhận `javascript:`/plain-http external | `tests/unit/security-hardening.test.mjs` |
| `api/_lib/emailTemplate.js` | Escape `cta.href` trước khi đưa vào `href=""` | cùng file test |
| `api/_lib/email.js` | `headerSafe()` bỏ CR/LF khỏi subject trước khi gửi | cùng file test |
| `api/payment-document.js` | `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` (token có thể ở `?token=`) | build |
| `api/photo-share.js` | `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` | build |
| `.gitignore` | `.dev.vars*`, `.wrangler/`, skill install generated | — |
| `api/_lib/origin.js` + các call site | Allowlist Host cho auth redirect, MapKit, Wallet, payment document, photo share | `security-hardening.test.mjs` 10/10 |
| migration 233 + rollback | Pin `profiles`/`organizers` server-owned columns; chỉ cho message `read_at`; chặn client fake system message | SQL test 14/14 trên stack throwaway |

Kết quả test focused: **10/10 pass** (6 test cũ + 4 test origin/HTML mới). Spike D1/Better Auth: **8/8 pass** (gồm 401 khi không có session, cách ly hai tài khoản, SQL injection, sign-out).

## 4. Audit 2026-11-19 đã có

`docs/audits/2026-11-19-cc/APPLIED.md` ghi 41 dòng; phần lớn đã applied, gồm các
lỗ hổng P0/P1:

- direct `bookings` INSERT bypass hold_seats (222),
- organizer bank/tax columns lộ cho user đăng nhập (223/231),
- host sửa `events` status/price sau khi có booking (224),
- check-in vé chưa thanh toán (227),
- `verify_payment` confirm hold hết hạn (230),
- cron fail-open khi thiếu `CRON_SECRET`,
- admin delete account không có switch,
- storage photo insert scope (229).

Còn lại cần owner:

- **Rotate mật khẩu** của test account từng nằm trong `ScreenshotCatalogTests.swift`
  (đã xoá khỏi code nhưng còn trong git history). Không tự đổi được.
- Xác nhận migration 183/ACL trên production (đã kiểm tra 2026-11-19: ACL đã đóng,
  nhưng migration chưa được ghi trong `supabase_migrations`).
- Smoke-test payment/payout/QR/admin tax code trên production sau 223/231.

## 5. Chưa làm / rủi ro còn lại

- **Chưa chạy full 6-phase audit.** Skill đã cài nhưng cần một lượt riêng có
  sub-agent và sandbox. Không ghi nhận “không còn lỗ hổng”.
- **Chưa audit iOS** trong lượt này; iOS vẫn dùng Supabase Auth và có các luồng
  upload ảnh riêng.
- **Chưa kiểm tra production headers/CSP/HSTS**; baseline chỉ sửa hai endpoint
  và một email helper.
- **2 dependency high** ở trên: **đã đóng** bằng override `joi@17.13.9`;
  `npm audit` 0.
- **Host header**: `getRedirectUrl` và các origin sink khác giờ đi qua
  `api/_lib/origin.js` allowlist; production nên đặt `PUBLIC_SITE_URL` (và
  `ORIGIN_ALLOWLIST` cho custom domain). Không còn reflect Host lạ.
- **Migration 233 chưa apply production**; cần owner review/backup rồi
  `supabase db push`. Test SQL chỉ chạy trên throwaway stack.
- **Token trong query** của `payment-document` vẫn tồn tại vì iOS webview cần;
  đã thêm `no-referrer`, nhưng token vẫn có thể vào log của proxy. Cân nhắc
  chuyển sang header/cookie ngắn hạn ở phase sau.

## 6. Cách chạy lại

```bash
node --test tests/unit/security-hardening.test.mjs
bash supabase/tests/233_server_owned_columns/run.sh   # cần Docker stack throwaway
npm audit
npm run test:unit
npm run build
```

Full audit (khi có đủ thời gian/sandbox):

```text
security audit this codebase
```

và lặp lại ít nhất 3 lần trên các mốc: sau auth, sau money, trước cutover.

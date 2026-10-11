# Rewards Giai đoạn 0 — tổng kết

Nhánh: `feat/rewards-phase0` (từ `main` tại `e399694`). Chưa push, chưa PR, **chưa áp dụng migration nào lên production**. Tạo ngày 2026-10-11. Tài liệu nền: [rewards-research.md](rewards-research.md), `.claude/notes/36-rewards-badges-following-map-foryou.md`.

> Nhãn: **[Đã chạy]** = đã chạy và có kết quả; **[Chưa chạy]** = chưa chạy được, kèm lý do; **[Suy luận]** = kết luận từ code/tài liệu, chưa kiểm chứng.

---

**Quyết định policy (2026-10-11): Phương án A được chọn tạm thời; B chỉ khi có đối tác thật và luật sư duyệt.** Phương án A: giữ nguyên cam kết "không chạy quảng cáo", chỉ cho ưu đãi do host/địa điểm tự đăng (xem [policy-rewards-draft.md](policy-rewards-draft.md) mục 5).

## 1. Kết quả theo bước

| Bước | Nội dung | Migration | Trạng thái |
|---|---|---|---|
| 1 | Múi giờ theo người dùng cho chuỗi ngày và trần tháng | 177 | Xong (web + iOS + DB). Cờ: không cần (NULL = hành vi cũ) |
| 2 | Cờ gian lận host–bạn bè, chỉ phát hiện + gắn cờ | 178 | Xong. Cờ `reward_risk_config.enabled` TẮT. Đã sửa khoảng trống xoá tài khoản (mục 5.1) |
| 3a/3b | Tách `kind` trong catalog (DB), rồi UI "Trang trí" / "Ưu đãi" (web + iOS) | 179 | Xong. Cờ `partner_offers` TẮT; không có đường đổi ưu đãi |
| 4 | Bản nháp sponsors/campaigns/offers/redemptions/settlements | không (nháp) | Xong, **ngoài chuỗi**, `supabase/drafts/` |
| 5 | Bộ đếm tổng hợp không định danh cho ưu đãi | 180 | Xong. Cờ `reward_events` TẮT |
| 6 | Bản nháp policy song ngữ | không | Xong, [policy-rewards-draft.md](policy-rewards-draft.md); `banbe_User_Policy.md` KHÔNG sửa |

## 2. Danh sách commit (từ cũ đến mới)

| Commit | Nội dung |
|---|---|
| `7068900` | Migration 177: múi giờ theo người dùng (web + iOS + DB) |
| `b1cccac` | Cho phép track harness test rewards (13, 13b, 14, README) |
| `992935c` | Test ngày cầu nối, siết quy tắc cầu nối, checklist kiểm tay |
| `e9cfb02` | Migration 178: cờ gian lận (cờ tắt) |
| `9475eaa` | Track `00_bootstrap_storage.sql` + `01_seed.sql` (dữ liệu giả) |
| `2b8604f` | Sửa 178: `shared_phone` đọc `auth.users.phone` đã xác minh thay vì `profiles.phone` |
| `e5b5a0c` | Migration 179: tách `kind` (chỉ DB) |
| `2a1cb41` | UI "Trang trí" / "Ưu đãi" web + iOS (3b) |
| `09877a5` | Harness: bootstrap định nghĩa `auth.jwt()` để container mới chạy được |
| `874a617` | Hướng dẫn dựng môi trường thử local |
| `0edad26` | Bản nháp sponsors/offers/redemptions (ngoài chuỗi) |
| `92307f8` | Migration 180: bộ đếm tổng hợp không định danh (cờ tắt) |
| `4bfcf34` | Bản nháp policy song ngữ |
| `87bc34f` | Tổng kết Giai đoạn 0 |
| (commit này) | Sửa 178: liên kết cờ–tài khoản ở bảng con (xoá tài khoản tự xoá liên kết); chọn phương án A |

## 3. File đã đổi

- **Migration mới (trong chuỗi):** `supabase/migrations/20261218000177_177_user_reward_timezone.sql`, `…178_178_reward_risk_flags.sql`, `…179_179_reward_kinds.sql`, `…180_180_reward_event_counters.sql`. Không sửa, đổi tên hay xoá migration cũ nào (kể cả 165).
- **Rollback (ngoài chuỗi):** `supabase/rollbacks/…177_177_revert_user_timezone_functions.sql`, `…178_178_revert_reward_risk.sql`, `…179_179_revert_reward_kinds.sql`, `…180_180_revert_reward_event_counters.sql`. Không dùng `…166_revert_rewards.sql` (xoá toàn bộ sổ cái).
- **Bản nháp (ngoài chuỗi):** `supabase/drafts/DRAFT_NOT_IN_CHAIN_sponsors_offers_redemptions.sql`, `…_rollback.sql`, `README.md`.
- **Web:** `src/lib/rewards.js`, `src/screens/Rewards.jsx`, `src/state/BanBeContext.jsx`.
- **iOS:** `apps/ios/BanbeApp/State/AppState+Rewards.swift`, `apps/ios/BanbeApp/Views/RewardsView.swift`, `apps/ios/BanbeAppTests/RewardsTests.swift`.
- **Test:** `tests/unit/rewards.test.mjs`; harness `supabase/_localtest/` (00, 01, 13, 13b, 14, 15, 16 + a/b, 17, 18 + a/b, README). `.gitignore` chỉ cho phép đúng các file này.
- **Tài liệu:** `docs/rewards-phase0-summary.md` (file này), `docs/rewards-phase0-manual-checks.md`, `docs/rewards-phase0-local-setup.md`, `docs/policy-rewards-draft.md`; cập nhật `docs/rewards-research.md`, `CLAUDE.md`, note 36 (ghi 165 đã áp dụng, xác nhận 2026-10-10).
- **Không đổi:** `banbe_User_Policy.md`, `check_in_guest`, bất kỳ file `.env*`.

## 4. Test: kết quả so với cơ sở

Cơ sở = đo trước khi sửa gì (đầu phiên). Tất cả test SQL chạy trên container local `banbe-pg3` (image `supabase/postgres:17.6.1.166`), không chạm production.

| Test | Cơ sở | Cuối cùng |
|---|---|---|
| `13_rewards_run.sh` (165, 76 kiểm tra) | ALL PASS, 169 migration | ALL PASS, 173 migration, cùng 76 kiểm tra |
| `13b_concurrent_redeem.sh` (12 lệnh đổi đồng thời) | ALL PASS | ALL PASS |
| `14_rewards_timezone_run.sh` | không có | ALL PASS (63) |
| `15_rewards_risk_run.sh` | không có | ALL PASS (46; gồm 11 kiểm tra xoá tài khoản) |
| `16_rewards_kinds_run.sh` (dữ liệu cũ + 179) | không có | ALL PASS (37) |
| `17_rewards_partner_draft_run.sh` (bản nháp, rollback transaction) | không có | ALL PASS (40) |
| `18_rewards_events_run.sh` (180 + race + rollback) | không có | ALL PASS (50) |
| `npm run test:unit` | 191 pass | 198 pass, 0 fail |
| `vite build` | không chạy | thành công (lần chạy cuối ở 3b) |
| iOS `RewardsTests` (iPhone 17 Pro, simulator) | 10 test | 17 test, 0 fail (lần chạy cuối ở 3b; không đổi iOS sau đó) |
| Rollback 177, 178, 179, 180 áp lên DB local rồi chạy lại bộ 13 | không có | ALL PASS |

Đặc biệt đã chứng minh trên dữ liệu kiểu cũ (migrate đến bản trước, tạo dữ liệu, áp migration mới, so sánh): kết quả `get_my_rewards`, `redeem_reward`, unlock, số dư, và định nghĩa 8 RPC rewards cũ **giống hệt từng byte** (179 và 180).

### Test chưa chạy được và lý do

- **Playwright / E2E:** không chạy (phụ thuộc môi trường đầy đủ; không nằm trong phạm vi).
- **Giao diện thật:** repo không có test render UI cho màn Rewards; chỉ test quy tắc ẩn/hiện. Bố cục thẻ Ưu đãi, ô chọn múi giờ, dark mode, Dynamic Type, VoiceOver **chưa kiểm** (nhóm C trong checklist).
- **iOS bản cũ đã phát hành chạy với server mới:** chỉ chứng minh qua cấu trúc JSON và test Decodable; **chưa chạy trên thiết bị/simulator bằng bản cũ thật** (E2 trong checklist).
- **PostgREST/GoTrue thật:** harness dùng Postgres + `SET ROLE`, không có PostgREST, không có GoTrue; quyền `EXECUTE`/RLS được kiểm ở mức Postgres, chưa qua lớp API.
- **`supabase db push`:** không chạy (cần liên kết dự án từ xa). Việc `drafts/` không bị quét là kết luận từ `config.toml` và cách CLI đọc thư mục. **[Suy luận]**
- **Dữ liệu và tải production:** không truy vấn production; hiệu năng trên dữ liệu thật chưa đo (dữ liệu rất ít: sổ cái 2 dòng, 0 check-in tại 2026-10-10).
- **Ngưỡng cờ gian lận:** chưa hiệu chỉnh được (0 điểm danh thật).
- **Hướng dẫn local:** `supabase db reset --version` và `supabase migration up` chưa kiểm chứng (CLI chưa cài khi soạn).

## 5. Rủi ro còn lại

- **Dữ liệu cũ.** Dòng sổ cái cũ có `period_month` NULL và được tính tháng theo giờ Việt Nam; `reward_active_days.local_date` không bị tính lại. Người đổi múi giờ giữa tháng có thể có một dòng lệch tháng vài giờ ở ranh giới (đã chấp nhận, đã ghi). Ngày cầu nối (đổi múi giờ sang hướng đông) chỉ giữ chuỗi liền mạch, không thành ngày hoạt động, không tạo xu, tối đa 2 lần mỗi 30 ngày.
- **Client cũ.** Thiết kế giữ `catalog` chỉ gồm keychain và `get_my_rewards` chỉ thêm trường; test cấu trúc đạt. Nhưng bản iOS đã cài không tự cập nhật và chưa được chạy thật với server mới (xem trên). Bản web cũ đang cache cũng chưa được thử bằng trình duyệt thật.
- **Chưa từng chạy migration trên một Supabase thật.** Cả bốn migration (177–180) chỉ chạy trên Postgres của harness. Bạn có thể đã thử trên stack local `supabase start` (theo `rewards-phase0-local-setup.md`), tôi không có kết quả đó.
- **Cờ rủi ro khi xoá tài khoản: ĐÃ XỬ LÝ** (178, mục 5.1). Còn lại: thời hạn lưu cờ theo tuổi chưa có (cờ chỉ mất khi tài khoản bị xoá hoặc bị gỡ bằng tay); stack local của bạn đã chạy 178 bản cũ nên phải `supabase db reset` (mục 5.1).
- **`shared_phone`:** nhiều khả năng không bao giờ kích hoạt vì số điện thoại trong `auth.users` thường duy nhất **[Suy luận]**; admin vẫn thấy liên kết tài khoản nên cần luật sư.
- **Bộ đếm sự kiện:** đếm sự kiện không đếm người; ai đăng nhập cũng thổi phồng được `offer_viewed`; chênh lệch giữa báo cáo chồng cửa sổ có thể lộ delta nhỏ; nhật ký nền tảng (Supabase/Vercel) nằm ngoài DB và không được kiểm soát.
- **Bản nháp đối tác:** không có giới hạn thử mã; chưa có RPC phát hành; chưa có công cụ admin.
- **Số dư âm** vẫn có thể xảy ra sau thu hồi (hành vi 165, không đổi).

### 5.1 Cờ rủi ro khi xoá tài khoản (đã xử lý, migration 178 chưa áp dụng lên production)

- **Luồng xoá hiện có:** không có hàm xoá trong DB. `api/auth/index.js` tạo dòng theo dõi `account_deletion_requests`, dọn Storage rồi gọi `admin.auth.admin.deleteUser`, tức `DELETE` trên `auth.users`; `profiles.id → auth.users ON DELETE CASCADE`, rồi mọi bảng `… → profiles ON DELETE CASCADE` bị xoá theo (mọi bảng `reward_*` của người dùng, kể cả sổ cái); `organizers.owner_id/user_id` bị `SET NULL` (tổ chức còn lại, chỉ gỡ chủ sở hữu).
- **Trước khi sửa:** `reward_risk_flags` không có khoá ngoại tới người dùng; mã tài khoản nằm trong `metrics.user_ids` (jsonb) nên **không** bị xoá, để lại mã mồ côi và liên kết giữa các tài khoản.
- **Cách chọn:** bảng con `reward_risk_flag_accounts(flag_id → cờ ON DELETE CASCADE, user_id → profiles ON DELETE CASCADE)`; cờ không còn chứa mã người dùng; `rewards_risk_compute` trả mã dưới dạng cột riêng, `admin_run_reward_risk_scan` đồng bộ liên kết, `admin_list_reward_risk_flags` ghép lại `user_ids` cho admin. Trigger xoá cờ danh tính hết ý nghĩa (`shared_phone` còn < 2 tài khoản, `new_accounts` hết tài khoản). Dùng `profiles` thay vì `auth.users` cho nhất quán với các bảng reward (profile xoá theo tầng từ `auth.users`, kết quả như nhau). Cờ cấp host chỉ có số đếm nên ở lại.
- **Vì sao không chọn cách khác:** sửa luồng xoá trong API (`api/auth`) để dọn cờ thì phụ thuộc vào một đường mã duy nhất và sẽ sót nếu tài khoản bị xoá bằng đường khác (Dashboard, script); ẩn danh (thay mã bằng NULL) giữ lại dòng vô nghĩa. Đánh đổi của bảng con: thêm một bảng và một trigger; `preview` không đổi (chỉ đếm).
- **Giữ nguyên:** cờ chỉ để admin xem, không thu hồi xu, không chặn ai, cờ `enabled` TẮT mặc định.
- **Vì sao sửa trực tiếp 178 là chấp nhận được:** theo bạn và kế hoạch, 178 chưa áp dụng lên production (tôi không truy vấn production). **Stack Supabase local của bạn (`supabase_db_banbe`) đã áp dụng 177, 178 và 179** (tôi chỉ đọc danh sách `schema_migrations` local); 178 trên đó là bản cũ, nên cần `supabase db reset` (chỉ local) để khớp file; không dùng được `migration up` vì phiên bản đã ghi là đã chạy. Nếu một môi trường dùng chung đã chạy 178, phải chuyển sang migration 181 bổ sung thay vì sửa file.
- **Test:** `15_rewards_risk_run.sh` có thêm DEL0–DEL10: xoá thật một dòng `auth.users` (như API) → liên kết biến mất, cờ còn lại giữ nguyên từng byte, cờ `shared_phone` còn < 2 tài khoản bị xoá, xoá host giữ cờ cấp host, quét lại không tạo liên kết tới tài khoản đã xoá, sổ cái người xoá đi theo và không ai bị thu hồi xu.

## 6. Quyết định còn mở

1. **RPC bật/tắt cờ `partner_offers`** (và `reward_events`, `partner_confirm`): hiện chỉ đổi bằng SQL. Cần: RPC admin riêng hay chỉ qua SQL có kiểm soát; ai được bật; nhật ký thay đổi; điều kiện (policy cập nhật, luật sư duyệt). Kể cả khi `partner_offers` bật, 179 vẫn không cho đổi ưu đãi (`NOT_AVAILABLE`).
2. **`sponsor_staff`** (bảng thứ 6 ngoài mục 5.2): giữ, hay đối tác xác nhận bằng cơ chế khác (admin nhập hộ, mã QR do banbe ký).
3. **Đổi khoá `offer_id`**: bộ đếm hiện dùng mã dòng `reward_catalog` (`partner_offer`); khi `reward_offers` vào chuỗi, có đổi khoá không.
4. **Giới hạn thử mã** cho `partner_confirm_redemption` và RPC phát hành (giới hạn mỗi người, khoá tồn kho, sinh mã): chưa có, bắt buộc trước khi bật.
5. **Client chỉ ghi `offer_viewed`** (180): giữ thiết kế này (issued/redeemed chỉ do máy chủ) hay cho client ghi cả ba loại; và client gửi tối đa một lần mỗi ưu đãi mỗi phiên (chưa xây).
6. **Thời hạn lưu cờ rủi ro và bộ đếm** (xoá theo tuổi). Việc xoá cờ khi xoá tài khoản đã làm (mục 5.1).
7. **Hết hạn xu** (12 tháng không hoạt động, chỉ xu kiếm được): xây hay không; **không bán xu** (đề xuất).
8. **Admin UI** cho cờ rủi ro và báo cáo bộ đếm (hiện chỉ có RPC).
9. **Số dư âm:** giữ nguyên hay đổi cách xử lý.
10. **Phương án A hay B** cho policy (mục 5 của bản nháp policy) và có cần cơ chế đồng ý riêng cho ưu đãi cá nhân hoá không.
11. **Sau này:** `get_my_rewards().offers` phải nối `reward_offers` (hạn, tồn kho) trước khi ưu đãi nào được coi là đổi được.

## 7. Điểm cần luật sư xem

Xem đầy đủ [policy-rewards-draft.md](policy-rewards-draft.md), mục 5 và 8. Tóm tắt:

- **`shared_phone` và việc admin xem liên kết giữa các tài khoản.** Tín hiệu so sánh số điện thoại **đã xác minh** (`auth.users.phone`) của các tài khoản được cùng một host điểm danh; cờ lưu danh sách tài khoản liên quan nên admin thấy liên kết giữa các tài khoản. Cần xác nhận cơ sở "chống gian lận / an toàn" ở `banbe_User_Policy.md` dòng 178 có đủ bao phủ không (mục đích, thời hạn lưu, quyền biết/phản đối, không quyết định tự động). Policy hiện không nêu việc đối chiếu số điện thoại giữa các tài khoản.
- Các tín hiệu còn lại (`repeat_guests`, `new_accounts`, `off_window`) và việc thu hồi xu do admin quyết định.
- **Xung đột với câu "không chạy quảng cáo" (dòng 31) và "không dùng dữ liệu cho quảng cáo của banbe" (dòng 182)**, và cam kết xin lại đồng ý khi đổi mục đích (dòng 300): hai phương án A/B trong bản nháp.
- **Bộ đếm "không định danh" (180):** dù không định danh, vẫn cần cập nhật policy và luật sư xem **trước khi bật cờ `reward_events`**. Lý do chọn bộ đếm tổng hợp thay cho log từng sự kiện: không có dòng nào ứng với một lượt xem nên không có gì để nối ngược về một người, không có thời điểm chính xác, và bảng không thể biến thành log mà không đổi schema lộ liễu. Giới hạn: không loại trùng, đếm sự kiện không đếm người, dễ bị thổi phồng, và lời hứa "không định danh" chỉ đúng cho cơ sở dữ liệu của banbe, không cho nhật ký hạ tầng của nhà cung cấp.
- Hết hạn xu, thông báo và xin đồng ý lại, hai thị trường (VN/US), và 9 câu ở nghiên cứu mục 6.5 cùng 7 câu mới.

---

## 8. Kế hoạch phát hành an toàn (tài liệu, KHÔNG thực hiện)

### 8.0 Trước khi bắt đầu
0. **Dựng staging là một project Supabase riêng, áp dụng chuỗi migration thật (177 → 180) và kiểm tra bằng app thật (có PostgREST và GoTrue) trước khi đụng production.** Harness hiện chỉ có Postgres, không có PostgREST/GoTrue: quyền `EXECUTE`, RLS qua API và đăng nhập thật chưa được kiểm. Làm trên staging: toàn bộ mục 8.1 và nhóm A–E, kể cả E2 (bản iOS/web cũ với server mới).
1. **Xác nhận bản sao lưu Supabase** (Dashboard → Database → Backups): xem có bản sao lưu gần nhất, và gói hiện tại có PITR hay chỉ sao lưu hằng ngày. Ghi lại thời điểm bản sao lưu. Nếu không có sao lưu dùng được, dừng. **[Tôi không kiểm tra được; việc của bạn]**
2. **Chụp trạng thái trước** (đọc, qua tài khoản test hoặc SQL editor): kết quả `get_my_rewards` và `get_my_reward_summary` của 2 tài khoản có dữ liệu thật; số dòng `reward_ledger`, `reward_unlocks`, `reward_user_badges`, `reward_active_days`; `select version from supabase_migrations.schema_migrations order by version desc limit 5` (kỳ vọng dừng ở 176).
3. **Kiểm tra tay trên stack local/staging** nhóm A–E trong [rewards-phase0-manual-checks.md](rewards-phase0-manual-checks.md); kể cả server dừng ở 176/178 (E1, E3) và client cũ với server 179 (E2).
4. Chọn **khung giờ ít người dùng** (theo dõi giờ thấp của app ở VN và US; lưu ý hai múi giờ).
5. Chuẩn bị sẵn các lệnh rollback (mục 8.3) và người trực.

### 8.1 Áp dụng migration, từng cái một
Thứ tự bắt buộc: **177 → 178 → 179 → 180** (179 dựa vào bản `get_my_rewards` của 177; 180 dựa vào bảng cờ và catalog của 179). Mỗi migration là một lần áp dụng riêng, dừng và kiểm tra rồi mới sang cái sau. Cách áp dụng từng cái: mỗi lần chỉ để **một** file đang chờ (ví dụ tách thành từng commit/nhánh phát hành, hoặc áp qua SQL editor rồi ghi lịch sử migration). **Cờ CLI cụ thể chưa kiểm chứng**; xác nhận bằng `supabase db push --help` và thử trên staging trước.

| Sau khi áp dụng | Kiểm tra bắt buộc (RPC CŨ vẫn chạy) |
|---|---|
| **177** | `get_my_reward_summary`, `get_my_rewards`, `record_active_day('save', …)`, `redeem_reward` (mã đã mở khoá → `already_unlocked`) cho tài khoản test: kết quả khớp bản chụp trước (số dư, chuỗi, lịch sử); `get_my_rewards` có thêm `timezone_settings`; tài khoản chưa chọn múi giờ: `streak.timezone = Asia/Ho_Chi_Minh`; một lần check-in thử ở sự kiện test không bị chặn |
| **178** | Bảng `reward_risk_*` tồn tại; `reward_risk_config.enabled = false`; `admin_reward_risk_preview()` (admin) trả `written: 0`; `check_in_guest` và đặt chỗ vẫn chạy |
| **179** | `get_my_rewards`: `catalog` còn đúng 3 mục, `offers = []`; `redeem_reward` trả như cũ cho mã keychain; mở Rewards bằng **bản iOS đã phát hành** và bản web cũ: không lỗi; `save_my_keychain` vẫn `DESIGN_LOCKED` cho thiết kế chưa mở khoá |
| **180** | `reward_feature_flags('reward_events') = false`; `record_reward_event` (đăng nhập) trả `recorded:false`; bảng đếm rỗng |

Sau mỗi bước: theo dõi nhật ký API/Postgres trong 15–30 phút (lỗi 4xx/5xx trên `get_my_rewards`, `redeem_reward`, `check_in_guest`; khoá; CPU). Chỉ sang migration kế tiếp khi sạch.

### 8.2 Phát hành client mới (sau khi cả 4 migration đã áp dụng và đã kiểm)
1. Web: triển khai bản mới. 2. iOS: **chạy lại iOS `RewardsTests`** trên commit phát hành (kỳ vọng 17 test, 0 fail), rồi gửi bản mới qua TestFlight/App Store (bản cài sẵn không cập nhật ngay; server đã tương thích với bản cũ). 3. **Làm lại kiểm tra E2 bằng tay** (client cũ với server 179 có cờ bật và có offer): bản iOS đã phát hành trước đây và bản web cũ phải mở được Rewards. 4. Sau khi client mới phát hành: kiểm lại nhóm A, D, E bằng bản thật.
**Tất cả cờ vẫn TẮT** (`partner_offers`, `reward_events`, `reward_risk_config.enabled`, và `partner_confirm` không tồn tại vì bản nháp chưa vào chuỗi).

### 8.3 Tiêu chí dừng và cách tắt/lùi
**Dừng ngay** nếu: kết quả RPC cũ khác bản chụp; số dư hoặc chuỗi của bất kỳ người dùng đổi; lỗi mới ở `check_in_guest`/đặt chỗ; tăng đột biến lỗi API hoặc khoá DB; client cũ không mở được Rewards.

| Migration | Cách tắt/lùi | Lùi an toàn? |
|---|---|---|
| **177** | Chạy `…177_revert_user_timezone_functions.sql`: khôi phục thân hàm 165, giữ bảng/cột (không mất dữ liệu). Người đã chọn múi giờ quay về ranh giới theo giờ Việt Nam | **Có** (không mất dữ liệu; mất hiệu lực lựa chọn múi giờ) |
| **178** | Đặt `reward_risk_config.enabled = false`; có thể chạy `…178_revert_reward_risk.sql` (mất chỉ các cờ/cấu hình) | **Có** |
| **179** | Đặt cờ `partner_offers = false`; chạy `…179_revert_reward_kinds.sql` khôi phục hàm và chỉ siết lại schema khi không có dòng `partner_offer`/thiếu `design_id` | **Có** (nếu đã có dòng `partner_offer`, chỉ tắt cờ, không xoá) |
| **180** | Đặt `reward_events = false`; chạy `…180_revert_reward_event_counters.sql` (tắt cờ; chỉ xoá đối tượng khi bảng đếm rỗng) | **Có** (bộ đếm có dữ liệu thì chỉ tắt cờ, không xoá) |

**Không migration nào trong bốn cái cần mất dữ liệu để lùi.** Tuyệt đối **không** dùng `supabase/rollbacks/…166_revert_rewards.sql` trên production: nó xoá toàn bộ sổ cái, huy hiệu, streak và unlock. Nếu mọi cách lùi đều không đủ: khôi phục từ bản sao lưu (mục 8.0) là phương án cuối và làm mất mọi thay đổi sau thời điểm sao lưu.

Cách tắt cờ (SQL, bởi người có quyền): `update reward_feature_flags set enabled=false where flag in ('partner_offers','reward_events'); update reward_risk_config set enabled=false where id=1;`

### 8.4 Điều kiện trước khi bật từng cờ (đều cần quyết định riêng của bạn)

| Cờ | Điều kiện tối thiểu |
|---|---|
| `reward_risk_config.enabled` (178) | Chạy `admin_reward_risk_preview()` trên dữ liệu thật và xem `by_type`; chỉnh ngưỡng; **luật sư xem `shared_phone`/liên kết tài khoản và policy dòng 178**; thông báo ≥ 30 ngày và xác nhận lại (phương án A tối thiểu); quyết định thời hạn lưu cờ (xoá khi xoá tài khoản đã làm); người xem cờ là admin được chỉ định |
| `reward_events` (180) | **Cập nhật policy và luật sư xem** (dù không định danh; kể cả nhật ký nền tảng); client gửi tối đa một lần mỗi ưu đãi mỗi phiên; quyết định ngưỡng nhóm và thời hạn lưu |
| `partner_offers` (179) | Luật sư (câu 1–3, 5, 6 trong mục 8 bản nháp policy); đã chọn phương án A/B và đã thông báo/xin lại đồng ý nếu B; có đối tác thật với thoả thuận bằng văn bản; `get_my_rewards().offers` nối `reward_offers`; RPC phát hành với giới hạn mỗi người, khoá tồn kho, giới hạn thử mã; công cụ admin. Nếu không, bật cờ chỉ hiện thẻ "chưa khả dụng" |
| (bản nháp) `partner_confirm` | Chưa nằm trong chuỗi. Đưa vào chuỗi chỉ sau khi toàn bộ điều kiện của `partner_offers` đạt |

## 9. Việc người dùng phải tự làm

1. **Xác nhận backup Supabase** (mục 8.0.1) và ghi lại.
2. **Chụp trạng thái trước** (8.0.2).
3. **Dựng staging (project Supabase riêng) và kiểm tay nhóm A–E** theo [rewards-phase0-manual-checks.md](rewards-phase0-manual-checks.md) trên local/staging; nhóm C (giao diện thật, iPhone thật) chỉ làm được bằng tay.
4. **Kiểm chứng hướng dẫn local** (`supabase db reset --version`, `migration up`) và cách áp từng migration một.
5. **Duyệt hoặc sửa** các quyết định mở ở mục 6.
6. **Gửi luật sư** [policy-rewards-draft.md](policy-rewards-draft.md) và mục 7; chọn phương án A/B; soạn thông báo; quyết định cách xin đồng ý lại.
7. **Áp dụng migration lên production** từng cái một theo mục 8.1, kiểm tra sau mỗi cái, rồi phát hành client; theo dõi.
8. **Dọn dẹp máy dev:** container thử `banbe-pg3` (không mở cổng; `docker rm -f banbe-pg3` khi xong); `banbe-pg2` đã dừng; `banbe-pg` đang dừng vì bạn chạy stack Supabase local.
9. **Đặt lại stack Supabase local** (`supabase db reset`, chỉ local) để 178 khớp bản đã sửa.
10. Sau khi duyệt: **push và tạo PR** (tôi chưa làm).

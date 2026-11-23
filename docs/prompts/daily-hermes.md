# banbe daily — toàn bộ việc Hermes trong một phiên Freebuff

> Dán nguyên file này (hoặc câu "đọc `docs/prompts/daily-hermes.md` và làm đủ các mục") vào một **Mission**.
> Mục tiêu: gộp các job Hermes hằng ngày vào một lần chạy, trừ những việc chỉ Mac làm được.
> Việc gì không kiểm được thì ghi `blocked:` — không được giả vờ PASS.

## 0. Luật cứng

- **Chỉ đọc source.** Không sửa `src/`, `api/`, `supabase/`, `apps/ios/`, config, test, migration. Không commit, push, deploy, ghi DB, gửi email thật.
- **Được ghi đúng những đường dẫn này** (và phải liệt kê lại trong report):

  | Đường dẫn | Khi nào | Tính chất |
  |---|---|---|
  | `docs/audits/<YYYY-MM-DD>/` (AUDIT.md + tối đa 12 ảnh) | luôn | report |
  | `docs/second-brain/audits/index.md` | luôn | **một dòng** |
  | `docs/second-brain/kanban/audit.canvas` | mỗi lần chạy | một card `audit-<date>`, qua `scripts/kanban.mjs` |
  | `docs/second-brain/raw/compiled/<date>-digest.md` | mục H | digest, không promote `wiki/` |
  | `docs/second-brain/graph/*.md`, `graphify-out/` | mục G | generated; graph notes là file tracked, đổi thì báo |
  | `docs/agent-os/vault/golden/shots/` | chỉ khi UI cố ý đổi | 10 ảnh chuẩn, commit cùng thay đổi |
  | `dist/` | mục C (`npm run build`) | generated, gitignored |
  | `.claude/skills/modern-web-guidance/`, `~/.cache/ms-playwright/` | D/E | tool + browser cache, gitignored hoặc ngoài repo |

  Ngoài bảng này: không ghi. Mọi thay đổi ngoài `docs/audits/` ghi vào mục **"Thay đổi ngoài audit dir"** — người duyệt commit, agent không commit.
- **Không in / không ghi** secret, token, webhook URL, service-role key, JWT, mật khẩu, connection string, email, số điện thoại, tên khách, địa chỉ nhà, số booking/payment. Nếu thấy secret trong source: ghi `path:line` + loại, không chép giá trị. APPLY.md và tin Discord cũng phải sạch: che `<redacted>` trước khi ghi; ảnh phải che PII trước khi lưu.
- **Không bịa.** Thiếu bằng chứng → `UNKNOWN` hoặc `blocked: <lý do>`, không phải PASS.
- Mỗi kết luận phải có **`path:line`, route, hoặc đường dẫn ảnh**. Nhận định chung chung không tính là phát hiện.
- **Được gửi đúng một prompt apply** (mục K; có thể 2–3 tin nếu dài) qua `scripts/cloud-notify.mjs apply`; không gửi gì khác, không tạo issue, không commit.

## 1. Trước khi làm (ghi vào header của report)

- **Kanban:** mở đầu bằng `node scripts/kanban.mjs upsert docs/second-brain/kanban/audit.canvas audit-<date> doing "AUDIT <date> — đang chạy"`. Kết thúc, cùng key, `done` với `AUDIT <date> — P0=<n> P1=<n> · apply <sent|printed|none>`. Bị chặn giữa chừng → `todo` + lý do ngắn. Chỉ sửa card `audit-<date>`.

```bash
date +%F
git rev-parse --short HEAD
git status --porcelain
node -e "try{console.log(require('./graphify-out/graph.json').built_at_commit)}catch(e){console.log('no graph')}"
```

- So `built_at_commit` với `HEAD`. Lệch → ghi `graph: stale <n> commits`, đừng coi graph là bằng chứng.
- `git status` có file lạ → ghi lại; **không audit file chưa commit**.
- Thiếu `node_modules` → ghi `build/test: blocked`, đừng `npm ci` (việc này đổi filesystem).
- **Ảnh: phải thử, không được bỏ qua.** Chạy `npm run dev` (ghi PID, chờ HTTP 200), rồi chụp bằng Playwright CLI:
  `npx playwright screenshot --viewport-size="390,844" --wait-for-timeout=1500 <url> <out>.png` (thêm `--full-page` khi cần).
  Thiếu browser → `npx playwright install chromium` (cache ngoài repo). Chỉ khi lệnh chụp vẫn fail mới ghi `visual: blocked — <stderr>`; **không** ghi `not checked` khi chưa chạy thử, và không lấy ảnh cũ thay ảnh mới. Chụp xong thì dừng đúng PID dev server.
  **Reserve, Vé và Account không mở được bằng URL trần** (`routes.js` đưa Reserve về Event, `/ticket` về Home, `/profile` cần session). Ba màn đó chỉ chụp qua `scripts/golden-shots.mjs`; không chụp URL trần rồi coi là ảnh màn đó.

## 2. Các job, theo thứ tự

### A. Standup (mỗi ngày)

```bash
git log --since=24.hours --pretty=format:'%h %s — %an'
git status --short
```

Cộng với PR đang mở và workflow run fail trong 24h (nếu có `gh`). Xuất 3 dòng: commit / PR / fail.

### B. Health (mỗi ngày)

- App: `curl -fsS https://www.banbe.app | grep -q 'id="root"'`.
- Supabase REST: `GET /rest/v1/events?select=id&limit=1` bằng **anon key** (đọc từ bundle đã build, không in key); 200 là đạt.
- Ảnh: `curl -fsSI https://media.banbe.app/<một object đã biết>` nếu có URL công khai.
- Không kiểm được từ đây: disk của Mac, cron ticker của Hermes, zone token Cloudflare → ghi `blocked`.

### C. Audit kỹ thuật (core)

1. Đọc `docs/second-brain/START-HERE.md` rồi `docs/second-brain/graph/Code map.md`. Chỉ grep khi map không trả lời.
2. Đọc `docs/audit-brief-v2.md` §4 (P0–P3, luật bằng chứng, "smallest safe fix").
3. Soát **diff 24h** trước; sau đó một luồng tiền/refund/booking và một luồng auth/RLS.
4. Tối đa **7 phát hiện**, xếp theo `tác động × độ tin cậy / công sức`.
5. Nếu chạy được: `npm run build` (ghi ra `dist/`, đã khai ở §0), `npm run test:unit`. Ghi đúng exit code; không xanh thì không nhận.

### D. UI/UX review (core)

Đọc `docs/agent-os/vault/principles/*.md` (6 luật sống) và `docs/agent-os/vault/golden/README.md`; `docs/agent-os/index.html` chỉ là bản đồ (6 chỗ + 7 chiều + 3 câu hỏi cổng). Rồi:

- **6 chỗ**: Home band · Event Detail · Giữ chỗ · Hoàn tiền & tranh chấp · Khách xem · Nền tảng (Safari 16.2).
- **7 chiều**, chấm 0–5 kèm lý do: Logic · Dễ · Đẹp · Calm · Moat · An toàn · Nhanh. Ghi điểm và trọng số đã dùng; đổi trọng số thì nói rõ.
- Kiểm tối thiểu: tap ≥ 44pt, tương phản ≥ 4.5:1, không tràn ngang, Reduce Motion, empty/error state, dead end.
- **Bố cục thương mại (bắt buộc có trong report):** bản web hiện là bản thử — trên desktop app nằm trong khung iPhone (`.bb-device` / `.bb-screen`, `src/App.jsx:864`, `src/styles.css:600`). Khi thương mại, **từng màn hình có bố cục riêng** (390 / 768 / 1280+), không bọc trong một khung điện thoại. Prototype đã có trong `docs/prototypes/` nhưng **chưa được audit lại và chưa áp dụng vào app**. Vì vậy:
  - Không chấm “hẹp / khung điện thoại” là lỗi P1 khi đó là khung thử; ghi `trial shell` và đánh giá phần bên trong khung.
  - **Chọn 3 màn:** chấm 0–2 ở 4 tiêu chí — (1) đường tiền/niềm tin: Giữ chỗ → Vé → Hoàn tiền/tranh chấp; (2) độ lệch prototype canonical; (3) điểm vào/tần suất: Home, Event Detail, màn được mở nhiều; (4) rủi ro thương mại: giữ khung iPhone sẽ vỡ ở 768/1280 hoặc chặn launch. Lấy tổng cao nhất; hòa → đường tiền trước, rồi effort nhỏ hơn. Ghi điểm + lý do từng màn; ít nhất một màn trên đường tiền nếu màn đó có prototype canonical; backlog ghi điểm/lý do trượt.
  - Audit prototype ↔ app **tối đa 3 màn ưu tiên**; mỗi màn chọn đúng **một prototype canonical** (ghi path) và chỉ audit prototype đó. Màn còn lại ghi vào **backlog** (màn → prototype ứng viên → lý do chưa làm), không audit dàn trải. Kiểm 390 / 768 / 1280, light/dark, ảnh before/after cùng route. Ảnh 1440 hiện là khung thử, không phải bố cục thương mại.
  - **Ngân sách ảnh:** tổng ảnh bổ sung của cả audit (ngoài 10 golden) vẫn ≤ **12** trong `docs/audits/<date>/shots/`; không cấp thêm bộ ảnh riêng cho prototype. Ưu tiên before/after của 3 màn đã chọn; ảnh 1440 chỉ để đối chiếu `trial shell`.
  - Xuất mục **Commercial layout gaps** trong AUDIT.md: chỉ 3 màn đã audit, mỗi màn → prototype canonical → lệch → việc cần làm → P0/P1/P2; phần còn lại nằm ở backlog. Đây là input cho prompt apply; **không tự sửa app**.
- **Golden set:** `node scripts/golden-shots.mjs --out docs/audits/<date>/golden` (dev server đang chạy) ghi 10 ảnh (5 màn × 390/1440 light) vào thư mục audit, dựng state bằng fixture chứ không mở URL trần. So với `docs/agent-os/vault/golden/shots/`; lệch ngoài ý muốn là P1/P2. Home/Event vẫn đọc Supabase production nên **bỏ qua khác biệt số liệu** (số vé, thứ tự carousel); chỉ báo lệch bố cục, typography, màu hoặc trạng thái UI. **Không** ghi đè golden; chỉ chạy không `--out` khi UI cố ý đổi và commit ảnh cùng thay đổi đó. Script fail → `golden: blocked — <stderr>`, **không** thay bằng ảnh chụp sai màn.
- **Ảnh bổ sung:** 10 ảnh golden nằm trong `docs/audits/<date>/golden/`; ngoài ra tối đa **12 ảnh** trong `docs/audits/<date>/shots/` cho 320 hoặc dark của màn có phát hiện. Ảnh before/after phải cùng route, cùng viewport.
- **Baseline scan:** `npx modern-web-guidance@latest legacy-scan src --json` — ghi số vi phạm + 3 file đầu; so với 4 vi phạm còn lại đã biết trong note 90. Không cài được → `skill missing: modern-web-guidance`, không thay bằng trí nhớ.

### E. Nguồn để rà soát và cho advice — đọc kỹ phần này

**Thứ tự ưu tiên, không đảo:** repo → chuẩn → bài viết → video.

1. **Repo (bắt buộc)**
   - `docs/second-brain/START-HERE.md`, `graph/Code map.md`, `Decisions.md`, `wiki/*`.
   - `.claude/notes/*` cho behaviour; `docs/agent-os/vault/principles/*` cho gu (6 luật, mỗi luật có phản ví dụ); `docs/agent-os/index.html` cho bản đồ; `docs/audit-brief-v2.md` cho rubric; audit gần nhất để không báo lại.
2. **Skills (cài cái thiếu, ghi lại nếu không cài được)**
   - `.agents/skills/web-browsing-cli/SKILL.md` — cách đọc một URL gọn (`npx @only-cli/oc open <url>`).
   - `.claude/skills/modern-web-guidance/SKILL.md` — **bắt buộc có trong lần chạy**: `npx modern-web-guidance@latest install --agent claude-code -y` (gitignored vì vượt cap file — không commit thư mục này), rồi `npx modern-web-guidance@latest legacy-scan src --json`. Ghi số vi phạm vào report.
   - `.agents/skills/security-audit/SKILL.md` — cho luồng auth/RLS, nếu đã cài (xem `skills-lock.json`).
   - `.agents/skills/code-review/SKILL.md` — cho diff 24h, nếu đã cài.
   - Skill nào không có trên máy: ghi `skill missing: <path>`, đừng thay bằng trí nhớ.
3. **Chuẩn (bắt buộc khi claim về accessibility/tương tác)**
   - WCAG 2.2 AA — https://www.w3.org/WAI/WCAG22/quickref/
   - Apple HIG — https://developer.apple.com/design/human-interface-guidelines
   - Material 3 — https://m3.material.io
   - NN/g 10 heuristics — https://www.nngroup.com/articles/ten-usability-heuristics/
   - Laws of UX — https://lawsofux.com
   - Baymard (checkout/booking) — https://baymard.com/blog
   - web.dev Baseline — https://web.dev/baseline
4. **Bài viết (tối đa 5 URL/lần)**
   - Chỉ dùng để **xác nhận** một phát hiện đã có bằng chứng trong repo, hoặc để so sánh pattern.
   - Ghi: URL · ngày đọc · đúng ý nào. Không dẫn cả bài.
   - Ưu tiên tài liệu gốc (W3C, Apple, Google, NN/g) hơn blog tổng hợp.
5. **YouTube (tối đa 1 video/lần)**
   - Chỉ khi cần một kỹ thuật cụ thể; phải có transcript hoặc mốc thời gian và câu trích.
   - **Không bao giờ là bằng chứng duy nhất** cho P0/P1. Video chỉ được đề xuất P2/P3 hoặc cách làm.
   - `docs/agent-os/index.html` đang dẫn 2 video (Leon van Zyl; Julian Goldie) như **cảm hứng**, không phải nguồn để chấm.
6. **Cấm**: listicle "10 best practices", lời khuyên không gắn màn hình/file, đề xuất rewrite, nguồn không đọc được mà vẫn trích.

### F. Dependency (thứ Hai và Chủ nhật; hoặc khi được yêu cầu)

```bash
npm outdated --json --long
npm audit --json --omit=dev
```

Ghi: số package lỗi thời, top 5, critical/high. `npm audit` lỗi mạng → `blocked`, không phải "0 lỗ hổng".

### G. Code graph (Chủ nhật, nếu có `graphify`)

```bash
graphify update .
npm run graph:notes
```

So `built_at_commit` với `HEAD`. Không có `graphify` → `blocked: graphify not installed`. `graphify-out/` là generated, không commit; `docs/second-brain/graph/*.md` là file tracked nên nếu `npm run graph:notes` làm chúng đổi, liệt kê từng file ở "Thay đổi ngoài audit dir" để người duyệt xem diff.

### H. Second-brain compile (chỉ khi có inbox)

Nếu `docs/second-brain/raw/inbox/` tồn tại và có `*.md` mới hơn digest gần nhất: viết `docs/second-brain/raw/compiled/<date>-digest.md`, 3–5 gạch đầu dòng, mỗi dòng link tới note gốc. **Không** promote vào `wiki/`. Không có inbox → `second-brain: no inbox`, không tạo thư mục rỗng.

### I. Weekly wind-down (thứ Sáu)

7 ngày commit, 6 file bị sửa nhiều nhất, branch đang mở, "Monday starts with". Xuất 4 dòng.

### J. Việc không làm được ở đây (ghi rõ, đừng giả vờ)

- **Nightly `git bundle`**: cần file chưa commit trên Mac → `skipped: Mac-only`.
- **Apple Notes export**: cần quyền Automation macOS → `skipped: Mac-only`.

### K. Bàn giao prompt apply (sau khi audit xong)

Mục tiêu: session mới chỉ cần dán prompt, không cần đọc lại workspace cũ.

1. Đọc `docs/prompts/apply-hermes.md` để lấy khuôn.
2. Viết `docs/audits/<date>/APPLY.md` — **tự chứa**, tối đa **4.500 ký tự**: P0/P1 + P2 đáng làm, mỗi mục có `path:line`, hành vi sai, fix nhỏ nhất, nghiệm thu, test; kèm branch `fix/audit-<date>`, PR vào `main`, checklist Preview, cấm deploy/migration. Bỏ hết placeholder.
3. Viết thêm `docs/audits/<date>/APPLY.discord.md` theo đúng format gửi Discord (dưới 1.800 ký tự):
   ````text
   **Mission APPLY — <YYYY-MM-DD> (<Thứ …>) · HEAD `<sha>`**
   Dán khối dưới vào một phiên Freebuff mới (Mission):
   ```text
   <prompt tự chứa, cùng nội dung APPLY.md nhưng gọn>
   ```
   ````
   Không dùng embed; header + một code block kín để copy nguyên khối. `APPLY.md` là bản chi tiết để tra, `APPLY.discord.md` là bản gửi. Giữ dưới 1.800 ký tự để script gửi đúng **1 tin**; dài hơn sẽ bị cắt thành `Apply mission 1/n`.
4. Gửi lên Discord:
   ```bash
   if [ -f .env ]; then node --env-file=.env scripts/cloud-notify.mjs apply --file docs/audits/<date>/APPLY.discord.md; else node scripts/cloud-notify.mjs apply --file docs/audits/<date>/APPLY.discord.md; fi
   ```
   Cần `DISCORD_WEBHOOK_WEEKLY` trong `.env` (gitignored) hoặc shell. Gửi được → `apply: sent`. Thiếu webhook/lỗi mạng → in **nguyên prompt** trong khối `APPLY PROMPT` để người dùng dán, ghi `apply: not sent — <lý do>`.
5. Không có gì đáng sửa → `APPLY: none`, không gửi tin nào.

## 3. Xuất

`docs/audits/<YYYY-MM-DD>/AUDIT.md`:

```
# banbe audit — <date>
HEAD <sha> · status <clean|dirty n> · graph <fresh|stale n|none> · visual <checked|blocked|skipped>

## P0 / P1
(mỗi dòng: severity · area · finding · evidence · fix nhỏ nhất · effort S/M/L)

## Findings
(bảng P2/P3, tối đa 7 dòng, xếp theo tác động × tin cậy / công sức)

## UI/UX
6 chỗ: ...
7 chiều: logic x/5 · dễ x/5 · đẹp x/5 · calm x/5 · moat x/5 · an toàn x/5 · nhanh x/5
Ảnh: shots/... (hoặc "blocked — <stderr>")
Golden: <khớp | lệch: ... | blocked: ...>

## Nguồn đã dùng
repo: ... · chuẩn: ... · bài viết: ... · video: ...

## Thay đổi ngoài audit dir
(path + lý do; "không có" nếu sạch)

## Apply mission
APPLY.md: docs/audits/<date>/APPLY.md
Sent: discord | printed (<lý do>) | none

## Blocked / Unknown
...
```

Thêm **một dòng** vào `docs/second-brain/audits/index.md`:

```
- <date> <HH:MM> ICT · <sha> · P0=<n> · P1=<n> · <headline> · docs/audits/<date>/AUDIT.md
```

## 4. Câu cuối (đúng định dạng, để so sánh giữa các ngày)

```
JOBS: standup ok · health 2/3 · audit 7 · ux 5 · deps 4 · graph stale · second-brain skipped
FILES: docs/audits/<date>/AUDIT.md, docs/second-brain/audits/index.md (+ file ngoài audit dir nếu có)
FINDINGS: P0=0 P1=2 P2=6 P3=4
SCORES: logic 4.2 · dễ 4.1 · đẹp 4.4 · calm 3.5 · moat 4.0 · an toàn 3.6 · nhanh 3.9
SOURCES: repo=9 standards=2 articles=1 videos=0
APPLY: sent | printed | none
BLOCKED: visual (playwright install failed), graphify (not installed)
```

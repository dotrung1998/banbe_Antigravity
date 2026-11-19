# banbe product audit — v2 (Claude Code)

A read-only product audit of banbe in six passes, run by **Claude Code as a manager** with model-routed
subagents, a **graph-assisted map** of the codebase, and the **already signed-in iOS simulator**. It finds
and ranks; it never fixes. Branching happens afterwards, one branch per accepted P0/P1.

**v1 is untouched.** `docs/audit-brief.md` is still the Freebuff `/mission` brief and the 09:00 LaunchAgent
reads its goal block. This file is the Claude Code one. Do not overwrite v1.

## 0. What changed from v1

| | v1 (Freebuff) | v2 (Claude Code) |
|---|---|---|
| Driver | One agent, three sequential passes | Manager + 6 evidence workers + 1 verifier, waves of ≤3 |
| Code navigation | `code_search` / `read_files` from scratch | `graphify` map first, then narrow reads around graph/rg hits |
| iOS | Not covered | Real signed-in simulator, screenshots + existing read-only UI tests |
| Model cost | One model for everything | Haiku for mapping, Sonnet for passes, Opus only for verification/merge |
| Output | Exactly 4 files | 6 evidence files + map + verifier + `AUDIT.md` |
| Repeat runs | Full re-audit | Re-checks the 2026-11-19 baseline first, then looks for new defects |

The graph is a **map, not evidence**. It is 90% extracted and 10% inferred, and its line numbers drift.
Every finding still ends at `path:line`, a route, or a screenshot.

## 1. Settings

| Setting | Value | Why |
|---|---|---|
| Tool | Claude Code CLI, repo root | Needs `Task`, `Read`, `Bash`, `Write` |
| Subagent type | **`general-purpose`** | Workers must read, run local checks and write their evidence file; `Explore`/`Plan` cannot write |
| Manager model | **Sonnet** (`/model sonnet`) | Plans and merges; Opus only for the merge if ≥2 P1s survive |
| Verifier model | **Opus** | One fresh, adversarial context over the P0/P1 candidates |
| Scout model | **Haiku** | Mechanical graph/grep work with verbose output |
| Pass models | **Sonnet** | Money, data, web, design, iOS — judgment at a sane price |
| Mode | Normal (writes allowed) | The audit must write its own evidence files |
| Output | `docs/audits/<date>-cc/` | Never collides with the daily `<date>/` audit |
| Scratch | `/tmp/banbe-audit-<date>/` | Screenshots and throwaway Playwright scripts, outside the repo |

Do **not** run with `--dangerously-skip-permissions`. If you want it unattended, allow only the exact
commands in §2 and §6 in `.claude/settings.local.json`; keep edits restricted to the audit directory.

Why this routing: Haiku does the one job whose output is long and whose judgment barely matters (graph/grep
mapping); Sonnet does the five passes that need real judgment at a fraction of Opus cost; Opus gets exactly one
job — a fresh-context verifier where missing a P1 costs more than the tokens. Never spend Opus on screenshots,
build logs or file tours. If Opus is unavailable on your plan, run the verifier on Sonnet with the same
adversarial prompt and re-check every P1 it confirms before merging.

If your Claude Code build's `Task` tool has no per-invocation `model` parameter, create the six workers once
with `/agents` (`.claude/agents/*.md`, `model: haiku|sonnet|opus`) using the same role text. Leave
`CLAUDE_CODE_SUBAGENT_MODEL` unset so it cannot silently override the routing.

## 2. Pre-flight (human, once)

Run these before pasting the goal. Each one removes a way the audit can fail or lie.

1. **Clean tree.** `git status --porcelain` must print nothing. Any modified file means the workers would
   audit code that is not the commit you think. Commit or stash first. This includes **this brief**: commit
   it, or the audit will honestly report `DIRTY_OUTSIDE_AUDIT: 1` because the brief itself is untracked.
2. **Refresh the graph.** At the time of writing it is built from `80411f7`, four commits behind `HEAD`
   (`a9766bf`). `graphify-out/` is gitignored (`.gitignore:134`), so refreshing it does not dirty the tree:
   ```bash
   graphify update .            # AST only, no API cost
   node -e "console.log(require('./graphify-out/graph.json').built_at_commit)"
   git rev-parse HEAD
   ```
   Those two hashes should match. If `graphify update` fails, run anyway and record `graph: stale`.
3. **Web server.** `curl -fsS http://localhost:5173 >/dev/null` or start `npm run dev` in the background.
   Record the PID; stop only that PID at the end.
4. **iOS simulator.** One is already booted (`iPhone 17 Pro`, iOS 26.5) with the app signed in:
   ```bash
   xcrun simctl list devices booted
   xcrun simctl listapps booted | grep -i banbe
   ```
   Both `com.banbe.ios` and `com.thetrung.banbe.dev` are installed. Launch each and look at the screenshot
   to find the one showing Home signed in; record its bundle id. **Never** erase the simulator, reset the
   keychain, uninstall the app, or sign out.
5. **Claude Code.** `claude` in the repo root, `/model sonnet`, thinking on. Paste §5.
6. **Budget.** This run targets ≤ 400k tokens across all agents, hard stop 550k. If it approaches the stop,
   cut P3 breadth — never skip verification.

## 3. Manager protocol

You are the manager. You plan, delegate, verify and merge. **You do not run the passes yourself.**

1. **Pre-flight inline** (§2 steps 1–4). Write the results into the `AUDIT.md` header. Do not delegate this;
   every worker needs the same facts. Read `CLAUDE.md`'s note index once (the one-line-per-note list) and
   keep the handful of note paths each worker needs; do not make workers re-read 52 KB of notes.
2. **Wave 1 — map.** One `scout` (Haiku). It writes `00-map.md`. Nothing else runs in this wave.
3. **Wave 2 — evidence.** Three Tasks in one message: `money`, `data`, `web` (Sonnet). Each gets the map
   path and its own output path. They must not overlap scopes.
4. **Wave 3 — surface.** Two Tasks in one message: `design`, `ios` (Sonnet). Designer reuses the web
   screenshots instead of taking a second full tour. iOS starts with the signed-in screenshots.
5. **Wave 4 — verify.** One `verifier` (Opus) in a fresh context. Give it only the P0/P1 candidates, the
   claimed evidence, and the three healthiest claims. It confirms, downgrades or kills each one.
6. **Wave 5 — merge.** You write `AUDIT.md` from the seven cards, opening an evidence file only when a
   card is ambiguous. If ≥2 P1s survive, or two passes disagree on severity, `/model opus` before merging.

**Token rules**

- **Paste** §6.0 + the role block into each spawn. Do not tell a worker to read §6 itself; a worker that
discovers the file will read the whole brief and may re-plan the audit.
- A worker returns a ≤12-line card; the evidence file stays on disk. Never ask a worker to paste its file.
- Spawn with the map path, the role block, and the output path. Nothing else — no repo tour, no history.
- Max 3 concurrent, max 7 workers, and **no worker spawns workers**. Fan-out is how audits burn budgets.
- One owner for `npm run build` and `npm run test:unit` (the data worker). Nobody repeats them.
- Designer reuses the web screenshots; the verifier re-runs only the single check that decides a P1.
- If a worker is blocked, retry once with a narrower scope, then record `blocked:` and move on.
- Do not let a worker read `CLAUDE.md` in full (52 KB) or `AGENTS.md`; pass only the note paths it needs.
- No worker uses `WebFetch`/`WebSearch`; this is a local audit.
- Record in the report: models used, worker count, checks run, graph freshness. `/cost` if available.

## 4. Rules of evidence

**Severity**

| | Meaning | Examples |
|---|---|---|
| **P0** | Money, access or data is wrong for real users | anyone can confirm a payment; a refund writes the wrong amount; a policy leaks private rows |
| **P1** | A public-facing falsehood or a broken core flow | cancelled event bookable; false "almost full"; Reserve dead-ends |
| **P2** | Friction, inconsistency, accessibility, performance | 4.09:1 text; 3.2 MB entry bundle; four different catalogue totals |
| **P3** | Polish | date format drift; a guest sees a bare login with no context |

**Rules**

- Every row: severity, area, finding, evidence (`path:line`, route, or `/tmp/...png`), smallest safe fix, effort S/M/L.
- A finding needs a failure mode a user can hit. "This could be cleaner" is not a finding.
- Cite the **root cause**, not every symptom. Three surfaces from one stale column are one row.
- Graph-only claims are rejected. If the graph points at a file and the line does not reproduce, drop it.
- Do not audit uncommitted files, `dist/`, generated `.xcodeproj`, `graphify-out/`, or `node_modules/`.
- **Redact** account emails, names, handles, booking ids and anything that looks like a secret. A secret in
  source is reported as `path:line` and described, never printed.
- Do not propose a rewrite. The fix is the smallest change that removes the failure.
- If a pass cannot run (browser, simulator, build), write `blocked:` with the exact error. Never silently skip.

## 5. The goal to paste

<!-- GOAL-START -->
```text
READ-ONLY product audit of banbe. You are the MANAGER: you plan, delegate, verify and merge. You do not run the passes yourself.

Repo: /Users/thetrungdo/Downloads/banbe
Date: run `date +%F`; output dir `docs/audits/<date>-cc/` (if it exists, append `-2`).
Read §3, §4, §6 and §7 of docs/audit-brief-v2.md before acting.

HARD RULES
- Only repo writes: the output dir above, /tmp/banbe-audit-<date>/, and gitignored build/graph output (`dist/`, `graphify-out/`). Nothing else.
- No source, test, migration or config edit. No branch, commit, push, deploy, `supabase` command, DB write or sign-in.
- Never type a credential, OTP or real email. Never print a secret. Redact account emails/names/handles/booking ids.
- Do not audit uncommitted files. Record `git status --porcelain` before and after.
- Graph is a map, not evidence: every claim ends at path:line, a route, or a screenshot path.

PRE-FLIGHT (inline, before any spawn; write results into the report header)
1. `git rev-parse --short HEAD` and `git status --porcelain`.
2. Compare graphify-out/graph.json `built_at_commit` with HEAD; if different run `graphify update .` and record `graph: fresh|stale <n> commits`.
3. Ensure http://localhost:5173 answers; if not start `npm run dev`, record the PID, stop only that PID at the end.
4. `xcrun simctl list devices booted` and `xcrun simctl listapps booted | grep -i banbe`. Record the booted UDID and the bundle id that shows Home signed in. Never erase, uninstall, reset the keychain or sign out.
5. No duplicate checks: `npm run build` and `npm run test:unit` belong to the data worker only.

WAVES (one message per wave; never start a wave before the previous files exist)
Wave 1 - 1 Task: scout, model haiku, §6.1 -> 00-map.md
Wave 2 - 3 Tasks in ONE message: money, data, web, model sonnet, §6.2-6.4 -> 01-money-access.md, 02-data-perf.md, 03-end-user-web.md
Wave 3 - 2 Tasks in ONE message: design, ios, model sonnet, §6.5-6.6 -> 04-design.md, 05-ios.md
Wave 4 - 1 Task: verifier, model opus, §6.7. Give it ONLY the P0/P1 candidates and the three healthiest claims -> 06-verify.md
Wave 5 - you: merge and write AUDIT.md per §7. If >=2 P1s survive or two passes disagree, `/model opus` before merging.

Every spawn = Task with subagent_type "general-purpose", model <haiku|sonnet|opus>, prompt = §6.0 COMMON + the §6.x role + the map path + the exact output path. No worker spawns workers. Max 3 concurrent. If a worker is blocked, retry once narrower, then record it.

FINISH LINE
- 00-map.md, 01-...06-verify.md and AUDIT.md all exist and are non-empty.
- AUDIT.md has >=10 unique ranked rows, P0/P1 above the table, and a `Verified:` line for every P0/P1.
- `git status --porcelain` shows nothing outside the output dir.
- No finding cites only the graph or only an opinion.

FINAL MESSAGE - end with exactly these lines
PASSES: 6/6
FILES: <paths>
FINDINGS: P0=<n> P1=<n> P2=<n> P3=<n>
DIRTY_OUTSIDE_AUDIT: <n>
```
<!-- GOAL-END -->

## 6. Worker briefs

Each role below is the `prompt` for a **`Task` with `subagent_type: "general-purpose"`** and the stated
`model`; a read-only `Explore` or `Plan` agent cannot write the evidence file. Concatenate **§6.0 COMMON**
with exactly one role block, replace `<...>` placeholders, and add the map path and output path. Do not add a
repo tour, the conversation history, or other passes' opinions.

### 6.0 COMMON

```text
You are a read-only audit worker on banbe. Repo: /Users/thetrungdo/Downloads/banbe. HEAD: <sha>.
Output file: docs/audits/<date>-cc/<file>.md. Scratch: /tmp/banbe-audit-<date>/.
You cannot see the manager's conversation. Everything you need is here.

Rules: change nothing in the repo outside your output file and scratch (gitignored `dist/` from the build and
`graphify-out/` are the only exceptions). No fixes, branches, commits, migrations, DB writes, sign-ins,
installs, deploys, WebFetch or WebSearch. Do not spawn subagents. Do not read AGENTS.md/CLAUDE.md in full;
use only the note paths you are given. Do not audit uncommitted files.

Method: start from docs/audits/<date>-cc/00-map.md. Open only the files you need, in 40-120 line windows
around a graph or rg hit. Cite path:line for every claim. If you cannot verify something, write `blocked:`
with the exact error and move on. Never guess.

Output file: a table `| # | Sev | Area | Finding | Evidence | Smallest safe fix | Effort |`, plus a short
detail paragraph only for P0/P1. Max 120 lines. No narration of what you did.

Return to the manager EXACTLY this card, max 12 lines:
PASS: <name>
FILE: <path>
COUNTS: P0=<n> P1=<n> P2=<n> P3=<n>
TOP: <max 3 lines: SEV | finding | evidence>
BLOCKED: <none | one line>

Do not paste the evidence file into the reply.
```

### 6.1 Scout — graph map (`haiku`, ≤30k, 8 min)

```text
Mission: turn the graph into a map of seven flows. You are not finding defects.

Run:
  graphify god-nodes --top 20
  graphify query "<flow terms>" --budget 1200      (one query per flow)
  graphify path "<entry file>" "<key file>"        (when the query is muddy)
  graphify affected "<rpc name>" --depth 2         (for money/access flows)
Flows: (1) guest discovery Home/Search/Map/event detail, (2) catalogue truth: counts/seats/dates/cancelled,
(3) booking money: hold/payment/confirm/ticket/refund/dispute, (4) access: admin guards/RLS/anon grants/
storage, (5) host create/review/manage/reports, (6) iOS parity Home/Search/Map/Event/Account/Schedule,
(7) cron/background jobs and notifications.

Output: for each flow, 3-6 files with line anchors, the tests that already cover it, and any duplicate
implementation or stale/contradictory twin. Also list the 10 most connected files you would NOT open
without a reason. 120 lines max.
```

### 6.2 Money & access (`sonnet`, ≤70k)

```text
Scope: hold/claim/reserve, payment confirmation, refunds, disputes, admin role guards, RLS policies, anon
grants, storage buckets, and the API routes that touch them.

Do:
- Read the migration files that define each RPC/policy; grep for SECURITY DEFINER, grant execute, using (true),
  is_platform_admin, auth.uid(), storage.objects, public = true.
- Re-check the 2026-11-19 healthy claims: confirm_payment authorization, admin_* guards, invite-only policy,
  owner/organizer-only profiles, private pay-proof/payment-document/refund-proof buckets, no service-role key
  under src/.
- Check the delegate paths added in 210-215 (payment confirmation, refunds, check-in) for scope creep.
- Check API handlers for missing auth or origin checks, and for secrets in client code.
- Verify the suspected hardcoded test credential in apps/ios/BanbeAppUITests/ScreenshotCatalogTests.swift:
  report the file:line and the risk, never the value.
- `git log --oneline <graph_commit>..HEAD` and check whether any of this changed in those commits.

Do not run SQL, apply migrations, or call Supabase. Report the smallest safe fix per finding.
```

### 6.3 Data truth, build & perf (`sonnet`, ≤80k)

```text
Scope: catalogue truth and the build.

Do once, preserving exit codes:
  npm run build > /tmp/banbe-audit-<date>/build.log 2>&1; echo BUILD_EXIT=$?
  npm run test:unit > /tmp/banbe-audit-<date>/unit.log 2>&1; echo UNIT_EXIT=$?
Report totals, failures and duration; never fix a failing test. Do not run Playwright or iOS tests.

Then re-check the 2026-11-19 baseline items 1-5, 8, 9, 11 in §10 of the brief, and look for new defects:
- seats_remaining vs real fill (hold_seats/claim_seats/get_public_event_fill); soldOut derivation
- catalogue totals across Home/Search/Map/AreaSheet and the predicate behind each
- demo-twin merge, cancelled/removed events, slugs and duplicates
- date/noun/price formatting per locale
- dist sizes: `du -h dist/assets/*.js | sort -h | tail -10`, lazy chunks, maplibre/jspdf placement

Evidence must include the exact file:line or the measured number.
```

### 6.4 Web end-user (`sonnet`, ≤70k)

```text
You are a first-time visitor in Ho Chi Minh City. Guest only: never sign in, never submit payment.

Use Playwright from /tmp/banbe-audit-<date>/web.cjs (CommonJS):
  const { chromium } = require('/Users/thetrungdo/Downloads/banbe/node_modules/playwright');
Capture at 390x844 light/VI, 320x700 dark/EN, 1280x800 light/EN. Save PNGs to /tmp/banbe-audit-<date>/web/
and read each once. Collect console errors and failed requests.

Walk: (a) Home -> event -> ticket stub -> Reserve gate; (b) Tonight and Weekend -> Browse by type -> one type
list; (c) Map -> pan -> pin -> list; (d) Search -> no results -> recover; (e) Schedule -> Saved gate.
Stop before payment. For each flow record route, expected, actual, blocked yes/no, and the screenshot path.
Flag confusing copy, dead ends, missing empty states, overflow, and inconsistent numbers.

Do not add specs to tests/, do not run existing specs (they may mutate state), do not use the publish preview.
```

### 6.5 Senior UI/UX designer (`sonnet`, ≤60k)

```text
Use the installed impeccable skill (Skill: impeccable, or read .claude/skills/impeccable/SKILL.md):
`critique` on Home, Event Detail and Browse; `audit` on those plus Map and Account.

Reuse /tmp/banbe-audit-<date>/web/*.png from the web pass. Take only the missing states yourself: dark mode,
320px, and the sheets. Check contrast on the tokens actually used for 12-15px text; give measured ratios.

Report the Nielsen 0-40 and audit 0-20 scores, the top issues naming screen + element, and the specific fix
(spacing, type scale, contrast, copy). Cite the token or CSS rule. Do not propose a redesign beyond these screens.
```

### 6.6 iOS, signed in (`sonnet`, ≤50k)

```text
Use the booted simulator that already holds the session. Never erase, uninstall, reset the keychain, sign out,
type into a field, reserve/pay, delete an event, or toggle organizer mode.

1. Screenshots BEFORE any rebuild: launch the bundle that shows Home signed in, wait, `xcrun simctl io booted
   screenshot /tmp/banbe-audit-<date>/ios/home-light.png`. Repeat with `xcrun simctl ui booted appearance dark`
   and restore afterwards. Read each PNG once.
2. Deep links, only when you have a real id: `xcrun simctl openurl booted "banbe://org/<id>"`,
   `banbe://ticket/<booking-uuid>`, `banbe://join/<code>`.
3. Existing read-only drivers, verified in source: NavigationUITests and FlowWalkthroughUITests contain **no**
   `signOut` call and use **no** `-uiFixture`. Run only the navigation tests that do not touch onboarding, login,
   language or theme (those mutate local prefs: `testOnboardingRunsThroughLanguageAndTheme` leaves dark,
   `testAccountAndPreferencesSwitchLanguage` leaves VI, `testDarkThemeRepaintsTheApp` leaves light, and the two
   login tests open/type in Login):
   xcodebuild test -project apps/ios/BanbeApp.xcodeproj -scheme BanbeApp \
     -destination 'platform=iOS Simulator,id=<UDID>' \
     -derivedDataPath /tmp/banbe-audit-<date>/DerivedData \
     -resultBundlePath /tmp/banbe-audit-<date>/nav.xcresult \
     -only-testing:BanbeAppUITests/NavigationUITests/testFeedOpensAnEventAndComesBack \
     -only-testing:BanbeAppUITests/NavigationUITests/testEventOpensTheOrganizerPage \
     -only-testing:BanbeAppUITests/NavigationUITests/testCategoryFilterNarrowsTheFeed \
     -only-testing:BanbeAppUITests/NavigationUITests/testAreaSheetOpensAndFiltersTheFeed \
     -only-testing:BanbeAppUITests/NavigationUITests/testSecurityIsItsOwnScreenOffAccount
   Run FlowWalkthroughUITests the same way (guest flow, no fixtures, no prefs), then export attachments:
   xcrun xcresulttool export attachments --path <xcresult> --output-path /tmp/banbe-audit-<date>/ios/
   The test build installs the Debug app; if the signed-in bundle is `com.banbe.ios` its binary is replaced (the
   keychain session normally survives). Screenshot Home **before** the run and launch + screenshot again
   **after** it. If Home comes up signed out, record that and stop — do not sign in.
   A failing test is evidence (stale identifier or real regression) — record which and why; do not fix it.
4. FORBIDDEN: ScreenshotCatalogTests (it can sign in with a different shared account), PublicEntryScheduleUITests
   (its `routing.signOut` fixture calls `AppState.signOut`, `UITestFixtures.swift:560-562`), and any suite that
   passes `-uiFixture`.
5. Static parity review: find the iOS twins of the web findings (seats, counts, dates, i18n, a11y labels) and
   check whether iOS shares the defect. Cite Swift file:line.

If no tap driver is available beyond the existing tests, say so; do not fake interaction.
```

### 6.7 Verified merge input (`opus`, ≤90k)

```text
You are the adversarial verifier. You get the candidate P0/P1 list and the three healthiest claims from the
manager. You have a fresh context; do not trust the candidate text.

For each candidate: open the cited file:line or reproduce the route/screenshot. Mark confirmed / unconfirmed /
wrong, and say what you saw in one line. Re-check the severity against §4 and dedupe candidates that share a
root cause. For each healthy claim, spot-check one concrete guard or policy.

Do not hunt for new findings. The only allowed addition is a blocker that invalidates a candidate. Output a
verdict table plus a short "merge notes" list. If a P1 cannot be reproduced, say so plainly; that is the job.
```

## 7. Merge and `AUDIT.md`

Write one report, not a concatenation. Dedupe by root cause, rank by severity then user impact, and keep the
evidence strongest-first.

```markdown
# banbe product audit — <date> (Claude Code)

**Commit:** <sha> · **Tree:** clean|N dirty · **Graph:** fresh|stale <n> commits (`<graph sha>`)
**Run:** manager <model>, 7 workers · **Build:** exit <n> · **Unit:** <passed>/<total>
**Surfaces:** web 390/320/1280, iOS <device> signed in
**Totals:** P0=<n> P1=<n> P2=<n> P3=<n>

## Fix this week (P0/P1)
### P1 — <title>
**Evidence:** `path:line` or route + screenshot
**Cause:** one sentence
**Fix:** smallest safe change
**Verified:** <verifier verdict + what it reproduced>
**Branch:** `audit/<date>/<slug>` · **Effort:** S

## Ranked findings
| # | Sev | Area | Finding | Evidence | Fix | Source pass | Effort |

## What looks healthy
- <claim + the guard/file that proves it>

## Suggested branches
1. `audit/<date>/<slug>` — scope, acceptance

## Gaps and confidence
- what could not run, what was not tested, what is inferred

## Run log
- workers + models, checks run, graph freshness, budget notes
```

Minimum 10 unique rows. Do not pad with duplicates or restyle the table into prose.

## 8. Finish line

Stop only when all are true:

- `00-map.md`, `01-money-access.md`, `02-data-perf.md`, `03-end-user-web.md`, `04-design.md`, `05-ios.md`,
  `06-verify.md`, `AUDIT.md` all exist and are non-empty.
- `AUDIT.md` has ≥10 unique ranked rows; P0/P1 sit above the table; every P0/P1 has a `Verified:` line.
- `git status --porcelain` shows nothing outside `docs/audits/<date>-cc/`.
- No finding cites only the graph or only an opinion.
- The final message ends with exactly:

```text
PASSES: 6/6
FILES: <paths>
FINDINGS: P0=<n> P1=<n> P2=<n> P3=<n>
DIRTY_OUTSIDE_AUDIT: <n>
```

`DIRTY_OUTSIDE_AUDIT` counts porcelain entries outside the audit directory. `graphify-out/` is ignored;
`/tmp` is outside the repo. If this brief is still untracked when you start, it will be 1 — commit it first.

## 9. After the run

The report is a proposal. For each accepted P0/P1, create one branch `audit/<date>/<slug>`, work inside a
worktree (`.worktrees/`, gitignored), and review each diff before merging. Use the `code-review` skill for
that second step, not this one. Do not create branches during the audit.

## 10. Regression baseline — 2026-11-19

Re-check these first; they are cheaper than a fresh sweep and they show whether the last report was acted on.
Mark each `fixed | still | worse | n/a` in the evidence file, with new evidence.

| # | Sev | Finding | Where it was |
|---|---|---|---|
| 1 | P1 | Cancelled event re-added through its demo twin; same title twice | `src/screens/Search.jsx:146-155` |
| 2 | P1 | "Almost full" for any capacity ≤ 3, even at 0 booked | `src/lib/homeDiscovery.js:121-133` |
| 3 | P2 | `seats_remaining` never decremented but printed on Home/admin/soldOut | `BanBeContext.jsx:94,2708`; `Home.jsx:738`; `AdminManageEvents.jsx:178` |
| 4 | P2 | Four catalogue totals: Home 16, Search 18, Map 17, Area 29 | `AreaSheet.jsx` vs `Search.jsx` |
| 5 | P2 | "You've seen every event" after 2 cards | `ShortlistV23.jsx:25`; `listEnd.js:31` |
| 6 | P2 | English area sheet still in Vietnamese | `AreaSheet.jsx:109,175,179,279`; `LocationSheet.jsx:13-14` |
| 7 | P2 | Clay small text 4.09:1 / 4.33:1 | `src/index.css:84,86`; `PublicProfile.jsx:226` |
| 8 | P2 | 3.2 MB entry bundle; Map +1.0 MB, PDF +0.4 MB | `dist/assets/index-*.js` |
| 9 | P2 | Three date formats and two seat nouns | Home / Search / Map / Detail |
| 10 | P3 | Guest dock sends to a bare login with no context | dock → `/login` |
| 11 | P3 | A venue appears as an area ("Yentown, Quận 1") | area tree input |
| 12 | P3 | Guest Reserve says "Đăng nhập" but primary is "Tiếp tục" | `GuestPromptSheet.jsx` |

New suspect, verify before reporting: `apps/ios/BanbeAppUITests/ScreenshotCatalogTests.swift` carries a
shared test account's email and password in source (around lines 31-33). Report `path:line` and the risk; never
copy the value. This is also why §6.6 forbids running that suite on the signed-in simulator.

## 11. Known limits, stated up front

- **iOS interaction is not fully automatable here.** `idb`, `maestro`, `applesimutils` and `cliclick` are not
  installed, and there is no MCP browser/tap server. The iOS pass can launch the signed-in app, screenshot it,
  change appearance, follow `banbe://` deep links with known ids, and run the existing read-only UI tests. It
  cannot freely tap every screen. If that is not enough for a claim, mark it `blocked`; do not infer.
- **Web is guest-only.** The signed-in session lives in the iOS simulator. Web hold/payment/Saved/Account
  remain untested unless you sign in yourself, which this brief forbids.
- **The graph is stale until refreshed.** At the time of writing it was built from `80411f7`, four commits
  behind `HEAD`. Step 2 of the pre-flight is not optional.
- **Playwright works on this machine** (`1.63.0`, Chromium installed), but Claude Code has no built-in browser
  tool, so the web pass drives it from a throwaway script in `/tmp`.
- **The report is not a fix.** A green build and unit suite prove the code compiles, not that a flow works.

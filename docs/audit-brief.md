# Automated product audit — Mission brief

A read-only daily audit of banbe in three passes (real end-user, senior engineer, senior UI/UX designer),
merged into one ranked report. It finds and ranks; it never fixes. Branching happens afterwards, one branch
per accepted P0/P1.

## Settings

| Setting | Value | Why |
|---|---|---|
| Slash command | `/mission` | Judge model keeps the run going until the finish line is met |
| Model | **DeepSeek V4.1 Flash Fast** | Pick it under **Powerful** in the model selector |
| Reasoning | **Max** | Separate control under the model list — it is not part of the model name |
| Mode | **Build** | Plan mode is read-only and cannot write the report files |
| Effort | **5** | ~4 hour target, enough for three passes |
| Surface | **Freebuff Desktop** | Browser tools are Desktop-only; the end-user pass needs them |
| Allowance | 10 hrs/day on Flash Fast (Free plan) | One daily mission fits; the 09:00 job runs it once a day |

Two cautions before you start:

- **Clean the tree first.** On 2026-11-19 `main` carried 5 uncommitted files (`EventRowV23.jsx`, `MapExplore.jsx`,
  `AreaSheet.jsx`, `HomeFilterSheet.jsx`, `tests/helpers.js`). The brief tells the agent not to audit them, but
  `DIRTY_OUTSIDE_AUDIT` cannot be 0 while they sit there. Commit or stash before running.
- **DeepSeek models may use data for AI training.** The picker says so on the row. If this codebase or the audit
  reports must not leave your control, stop here and run the audit on a model without that note.

## Run it

1. Open this folder in Freebuff Desktop, on a clean `main`.
2. Select **DeepSeek V4.1 Flash Fast**, set **Reasoning: Max**, switch to **Build**.
3. Type `/mission`, paste the goal below, set **Effort 5**, start.
4. When it stops, read `docs/audits/<date>/AUDIT.md`. The `suggested branches` section feeds the next step.

## Paste this into the Mission goal

<!-- GOAL-START -->
```text
READ-ONLY product audit of banbe. Do not fix anything. Do not create branches, commit, push, edit source, run migrations, write to a database, sign in, or deploy. The only writes allowed are files under docs/audits/.

SETUP
1. Run `date +%F`; use that string as <date>.
2. Create docs/audits/<date>/ and write everything there. Nothing else in the repo may change.
3. Read AGENTS.md first, then only the notes its index says are relevant to what you audit.
4. Never type a credential, OTP or real email into any field.

Run three independent passes in order. Finish and write a pass before starting the next; do not let one pass's opinions leak into another.

PASS 1 - REAL END-USER -> 01-end-user.md
You are a first-time visitor in Ho Chi Minh City who has never heard of banbe. Run the dev server only if it is not already up, open its loopback URL in a browser tab, and use the browser tools. Do not use the publish preview; it refuses this repo for exceeding the file cap. At 390x844 and 1280x800, signed out, walk:
a. Home -> event -> ticket stub -> Reserve (stop before payment).
b. Tonight and Weekend -> Browse by type -> one type list.
c. Map -> pan -> open a pin -> open the list.
d. Search -> a query with no results -> recover.
e. Schedule -> Saved.
Per flow record route, expected, actual, blocked yes/no. Flag confusing copy, dead ends, missing empty states, layout breakage, console errors. No code opinions, no screenshots. If the app cannot render, record the blocker instead of skipping silently.

PASS 2 - SENIOR ENGINEER -> 02-engineer.md
Audit committed code only, never uncommitted working-tree edits. Prioritise money and access paths: hold/claim/reserve, payment confirmation, refunds, dispute access, admin role guards, RLS policies, anon grants. Use code_search and read_files; change nothing. Each finding: severity P0-P3, file:line, concrete failure mode, smallest safe fix. Run `npm run build` and `npm run test:unit`; report pre-existing failures as findings and never fix them. Skip Playwright if the browser cannot launch and say so.

PASS 3 - SENIOR UI/UX DESIGNER -> 03-designer.md
Use the installed impeccable skill: `critique` on Home, Event Detail and Browse; `audit` on those plus Map and Account. Check light and dark at 1280px, 390px and 320px. Report the heuristic score, top issues naming screen and element, and the specific fix (spacing, type scale, contrast, copy). Cite the token or CSS rule where possible. Propose no redesign beyond these screens.

MERGE -> AUDIT.md
One ranked report. Deduplicate findings describing the same defect. Table: rank, severity, area, finding, evidence (route or file:line), fix, source pass, effort S/M/L. Put P0/P1 in a "fix this week" section above the table. Add "what looks healthy" and "suggested branches" listing one branch per P0/P1 named audit/<date>/<slug>. Do not create them.

FINISH LINE - stop only when all are true
- docs/audits/<date>/ holds exactly 01-end-user.md, 02-engineer.md, 03-designer.md, AUDIT.md, all non-empty.
- AUDIT.md has a ranked table of at least 10 rows, each with severity, evidence and a fix.
- git status --porcelain shows no change outside docs/audits/<date>/.
If a pass runs long, write what you have, mark the gaps at the top of that file, and continue. Never start a pass before the previous file exists.

FINAL MESSAGE - end with exactly these lines
PASSES: 3/3
FILES: <four paths>
FINDINGS: P0=<n> P1=<n> P2=<n> P3=<n>
DIRTY_OUTSIDE_AUDIT: <n>
```
<!-- GOAL-END -->

## Why the finish line is checkable

Mission's judge runs on the same model in a fresh context and sees only what the agent wrote plus the **names**
of the tools it called, never file contents. So the goal states finish conditions the judge can observe in the
transcript: four `write_file` calls at fixed paths, a `git status` result reported back, and a four-line final
message with numbers. "Make the app better" would be unsteerable; this is not.

The `DIRTY_OUTSIDE_AUDIT` line is the guard rail: an audit that edits source to "prove" a finding is a failed run,
even if the report looks good.

## Verify the daily agent from a cold start

`scripts/launchd/cold-test.command` proves the LaunchAgent can launch Freebuff when it is not already
running. Run it from **Terminal**, not from inside Freebuff: the test quits the app, and the Freebuff
terminal panel quits with it.

```bash
cd /Users/thetrungdo/Downloads/banbe
./scripts/launchd/cold-test.command
```

It waits 30 seconds, quits Freebuff, kicks `com.banbe.daily-audit`, and asserts: the old process is gone,
a new PID exists and differs from the old one, the clipboard hash matches the installed goal, and the
agent log gained a line with `notification=sent`. It prints `RESULT: PASS` or `RESULT: FAIL - <reason>`
and appends the transcript to `~/Library/Logs/banbe-coldtest.log`. Freebuff reopens on its own; if it
does not, launch it manually.

A PASS proves the cold launch and the clipboard. `notification=sent` proves the notification was posted,
not that the banner was drawn. That still depends on Focus and Script Editor's notification permission.

## After the run

The report is a proposal, not a change. For each accepted P0/P1: create one branch (`audit/<date>/<slug>`), let
the agent work inside a worktree (`.worktrees/`, already gitignored), and review each diff on its own before
merging. The `code-review` skill is for that second step, not this one.

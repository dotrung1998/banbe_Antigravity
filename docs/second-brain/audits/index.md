---
type: index
updated: 2026-11-23
tags: [audit, operations]
---
# Audits

The daily audit is handed off by the GitHub Actions **prompt** job (05:00 ICT) as a copy-paste Freebuff mission. The old Orca/Hermes **banbe daily audit** automation is disabled; the mission still replaces the two separate loops — the dated technical audit in `docs/audits/` and the daily design review in `docs/agent-os/`.

The mission reads `docs/second-brain/START-HERE.md` and the code map first, then `docs/agent-os/index.html` for the six lenses, then the newest audit so it does not re-report known findings. It never edits source, commits, pushes, deploys or touches production.

## Current state

Last audit: 2026-11-23 · a6699b1d · P0=0 P1=0 · docs/audits/2026-11-23/AUDIT.md
Last run: 2026-11-23 18:35 ICT · P0=0 P1=0 · Build exit 0 + unit 1072/1072; 213/223/230/232 applied; no P0/P1; backup fail; 5 findings; sources 0/7 captured (7 blocked); Orca daily disabled (CLI)

## Runs

- 2026-11-23 18:35 ICT · a6699b1d · P0=0 · P1=0 · 213/223/230/232 applied + backup fail; 5 findings · nguồn 7 chiều: 7/7 blocked (không capture); PR/health có log; A/B: GH Actions giữ, Orca daily disabled (5 automation) · docs/audits/2026-11-23/AUDIT.md
- 2026-11-23 17:24 ICT · a6699b1d · P0=0 · P1=3 · Build exit 0 + unit 1072/1072; origin pinning applied; R2 reads live
- 2026-11-22 05:05 ICT · a0ed5486 · P0=0 · P1=4 · Code map fresh + iOS not compiled + verify_payment 213 unapplied; build exit 0, unit 1072/1072, npm audit 0
- 2026-11-19 · 3eb810eb · P0=0 · P1=2 · Cancelled search demo-twin + almost-full social proof; resolved next run
- 2026-11-19-cc · 3eb810eb · P0=0 · P1=0 · Follow-up to the 11-19 run (same commits)

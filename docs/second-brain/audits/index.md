---
type: index
updated: 2026-11-21
tags: [audit, operations]
---
# Audits

One job owns every audit for banbe: the Hermes cron **banbe daily audit** (05:00, Asia/Ho_Chi_Minh). It replaces the two separate loops — the dated technical audit in `docs/audits/` and the daily design review described in `docs/agent-os/`.

The job reads `docs/second-brain/START-HERE.md` and the code map first, then `docs/agent-os/index.html` for the six lenses, then the newest audit so it does not re-report known findings. It never edits source, commits, pushes, deploys or touches production.

## Current state

Last audit: 2026-11-21 · e556e5a9 · P0=0 P1=3 · docs/audits/2026-11-21/AUDIT.md
Last run: 2026-11-21 08:34 ICT · P0=0 P1=3 · Dynamic Island toasts + organizers columns + R2 behind OFF switches; build exit 0, unit green

## Runs

<!-- One line per run: date · commit · P0/P1 · headline · path -->
- 2026-11-21 08:34 ICT · e556e5a9 · P0=0 · P1=3 · Dynamic Island toasts + organizers columns + R2 behind OFF switches; build exit 0, unit green
- 2026-11-19 · 3eb810eb · P0=0 · P1=2 · Cancelled search demo-twin + almost-full social proof; resolved next run
- 2026-11-19-cc · 3eb810eb · P0=0 · P1=0 · Follow-up to the 11-19 run (same commits)

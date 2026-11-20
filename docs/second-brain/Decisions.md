# Decisions log

One row per decision that would otherwise be re-argued. The long version lives in `.claude/notes/` or the linked doc —
this page only has to be enough to stop the loop.

Add a row when: a choice is expensive to reverse, two reasonable people disagreed, or an agent keeps "fixing" it back.

| Date | Decision | Why | Source |
| --- | --- | --- | --- |
| 2026-11-17 | Web Baseline floor is **Safari 16.2 / iOS 16.2**, not "Baseline Widely available" alone | `color-mix()` is already required; anything newer needs a fallback or waits | `CLAUDE.md`, `.claude/notes/90-modern-web-guidance-pass.md` |
| 2026-11-04 | `verify_payment` may only be called by the payment's organizer; automatic Telegram confirmation removed | Any signed-in user could confirm any payment; hole closed in migration 213 | `.claude/notes/02-confirm-qr.md` |
| 2026-11-04 | Project-hub money/door keeps the `owner_id`-or-`user_id` check, never `project_is_host` | Delegation must not become a second, weaker permission path | `.claude/notes/76-event-project-hub.md` |
| 2026-10-23 | Feature flags are read server-side; a **missing** flag means ON | An unseeded flag must not silently hide a shipped feature | `.claude/notes/51-feature-switch-rewards-pulse-ticker.md` |
| 2026-10-23 | Retention/measurement switch is the only new flag ON after the retention run | Everything else ships dark until the owner turns it on | `.claude/notes/61-retention-run-production-log.md` |
| 2026-10-10 | Rewards coins are an append-only ledger, never a mutable balance | Reversals and audits need history | `.claude/notes/36-rewards-badges-following-map-foryou.md` |
| 2026-11-14 | Each event carries its own IANA `tz` + `currency`; `price_vnd` is minor units | US start times were being stored as Vietnam time | `.claude/notes/60-us-timezone-currency-push-presetup.md` |
| 2026-11-15 | Browse by type is the **list**, not a grid | The owner removed the grid; a type is a filter over one list | `.claude/notes/88-browse-by-type-is-the-list.md` |
| 2026-11-19 | The daily product audit is read-only and writes only under `docs/audits/` | It finds and ranks; fixes happen later on their own branch | `docs/audit-brief.md` |
| 2026-11-20 | The second brain's `wiki/` is human-promoted; scheduled jobs write `raw/` only | Automation must not rewrite conclusions | `docs/second-brain/AGENTS.md` |

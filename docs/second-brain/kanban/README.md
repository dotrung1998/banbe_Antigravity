# Mission Kanban

Two Obsidian Canvas boards, three columns each: **TODO · DOING · DONE**.

| Board | Owner | Card key |
|---|---|---|
| `audit.canvas` | `docs/prompts/daily-hermes.md` | `audit-<date>` |
| `apply.canvas` | `docs/prompts/apply-hermes.md` | `apply-<date>` |

The Missions update their own card at the start and end of a run, so the board shows what is queued, running and finished without a second tracker.

```bash
node scripts/kanban.mjs upsert docs/second-brain/kanban/audit.canvas audit-2026-11-22 doing "AUDIT 2026-11-22 — đang chạy"
node scripts/kanban.mjs upsert docs/second-brain/kanban/audit.canvas audit-2026-11-22 done  "AUDIT 2026-11-22 — P0=1 P1=2 · apply sent"
node scripts/kanban.mjs list docs/second-brain/kanban/audit.canvas
```

Rules:

- One card per run (`audit-<date>`, `apply-<date>`); never edit another run's card.
- One line, ≤ 140 characters; move the same card, don't create a second one.
- Blocked mid-run → back to `todo` with a short reason.
- `init` never overwrites an existing board.

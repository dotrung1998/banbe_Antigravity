# banbe second brain

A plain folder of Markdown files that outlives any one agent session. It is the "second brain" from the Hermes Agent
fundamentals video, wired to **this** repo instead of a generic vault.

Open it as a vault in Obsidian (`File → Open folder as vault`) if you want the graph view; nothing here depends on
Obsidian. Every agent on this machine can read it as ordinary files.

```
docs/second-brain/
  AGENTS.md          rules for agents: raw vs wiki, routing table, "answer from the vault"
  Home.md            the index — start here
  Decisions.md       what was decided and why, one row each, linked to .claude/notes
  Templates/         one skeleton per note type (9)
  raw/inbox/         append-only captures (gitignored)
  raw/compiled/      nightly digests (gitignored)
  wiki/              durable, linked knowledge (tracked)
  Skills/            how a repeated process becomes a callable skill
```

## The nine things the video saves here

| Video card | Where it lands here |
| --- | --- |
| Meeting notes | `raw/inbox/<date>-meeting-*.md` from `Templates/meeting-note.md` |
| Research summaries | `raw/inbox/<date>-research-*.md` from `Templates/research-summary.md` |
| Web clippings | `raw/inbox/<date>-clip-*.md` from `Templates/web-clipping.md` |
| Daily notes / journal | `raw/inbox/<date>-daily.md` from `Templates/daily-note.md` |
| Project files / PRDs | `wiki/PRD-*.md`, promoted from `Templates/project-brief.md` |
| Decisions log | `Decisions.md` + a `.claude/notes/` note when behaviour changes |
| Workflows / SOPs | `Skills/` → a real `SKILL.md` an agent can load |
| Concept / synthesis pages | `wiki/synthesis-*.md` from `Templates/synthesis.md` |
| Session memory | `raw/inbox/<date>-session-*.md` from `Templates/session-memory.md` |

## Why raw is separate from wiki

`raw/` is what happened. `wiki/` is what you concluded. A nightly job may add to `raw/` freely; it may not rewrite
`wiki/`. That is the same ownership rule the video's vault uses, and it is the only thing that stops an enthusiastic
agent from silently rewriting your decisions.

Both raw folders are gitignored: captures never dirty the working tree, and nothing automated can be committed by
accident.

## Already-existing knowledge this vault points at

Do not duplicate these — link them:

- `.claude/notes/01-…101-…` — the numbered feature/stage notes; canonical for how each part of banbe works.
- `docs/retention-delight-plan.md` — retention plan with a live status table.
- `docs/push-setup.md`, `docs/apple-setup-checklist.md`, `docs/r2-migration-runbook.md`, `docs/impl/` — owner runbooks.
- `CLAUDE.md` — the stage index and the web Baseline floor.
- `docs/audits/<date>/AUDIT.md` — the daily product audit output.

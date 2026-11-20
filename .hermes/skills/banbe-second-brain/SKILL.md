---
name: banbe-second-brain
description: Capture to and query the banbe second brain (docs/second-brain). Use when the user says remember this, save this, what did we decide, or when a session ends and a short memory note is warranted.
---

# banbe second brain

Vault: `docs/second-brain/`. Rules: `docs/second-brain/AGENTS.md` (read it; the raw-vs-wiki split is not optional).
Index: `docs/second-brain/Home.md`.

## Capturing

1. Classify with the routing table in `AGENTS.md`.
2. Copy the matching skeleton from `docs/second-brain/Templates/`.
3. Write to `raw/inbox/YYYY-MM-DD-<type>-<slug>.md`. Never write to `wiki/` directly.
4. If the capture contains a decision that is expensive to reverse, add **one row** to
   `docs/second-brain/Decisions.md` and link the detail.
5. Keep it short: a title that states the conclusion, the evidence, the next step.

## Answering

1. Start at `docs/second-brain/graph/Code map.md` (`START-HERE.md` explains the three hops): pick the area, read its
   **Start with** `file:line`, open that file. Grep is the fallback, not the first move.
2. Search the vault: `rg -l "<terms>" docs/second-brain .claude/notes`.
3. Prefer `.claude/notes/*` for how the app behaves, `Decisions.md` for why, `docs/second-brain/wiki/*` for conventions.
4. Answer from the file and cite the path. If the vault is silent, say "not in the vault" before using general
   knowledge.

## Session memory

At the end of a long session, write `raw/inbox/YYYY-MM-DD-session-<slug>.md` using
`Templates/session-memory.md`, with three lists: done-and-verified, done-not-verified, blocked. Keep the project's own
status words (IMPLEMENTED LOCALLY / committed / pushed / APPLIED / device-verified).

## Never

- Never put API keys, tokens or customer data in the vault, including `raw/`.
- Never mark something "applied" or "deployed" from memory; only from an observed log line.

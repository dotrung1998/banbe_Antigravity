# Workflows → skills

The video's last second-brain card is the useful one: **a repeatable process should stop being a note and become a
skill** an agent loads on demand.

## When to promote a note into a skill

All three must be true:

1. You have followed the same steps at least twice.
2. The steps have a checkable finish line ("build is green", "migration applied and logged").
3. Getting it wrong is annoying but not catastrophic — if it can delete data or move money, it needs a human gate in the
   middle and probably stays a runbook.

## Where skills live here

| Location | Loaded by | Use for |
| --- | --- | --- |
| `.hermes/skills/<name>/SKILL.md` | Hermes, after `hermes skills trust .` | agent-side procedures for this repo |
| `.agents/skills/<name>/SKILL.md` | Hermes and other agents that read the standard path | shared, tool-agnostic skills |
| `.claude/skills/` | Claude Code / Freebuff-style agents | existing design + web-platform skills |

Two banbe skills are installed:

- **`banbe-project`** — context, commands, guardrails. Load it before touching code.
- **`banbe-second-brain`** — the capture/compile protocol for this vault.
- **`pr-manager`** (`.claude/skills/pr-manager/SKILL.md`, Claude Code `/pr-manager`) — review, fix and merge every open
  PR into main through agents, one owner approval per batch, report in `raw/inbox/YYYY-MM-DD-review-pr-manager.md`.
  Owner prompts are logged to `raw/inbox/YYYY-MM-DD-chat.md` by the `scripts/vault-log-prompt.mjs` hook.

## Template

Copy `Templates/sop.md` into `.hermes/skills/<name>/SKILL.md` and keep it short: when to use it, the steps, the finish
line, and what NOT to do. A skill longer than two screens is a runbook with delusions.

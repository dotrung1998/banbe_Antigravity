# Second brain — rules for agents

> **Open [[START-HERE]] first.** Do not scan the repository to find out how banbe works: start at
> [[graph/Code map|Code map]], pick the area, read its **Start with** `file:line`, and only then search. The map is
> generated from the Graphify code graph by `scripts/second-brain-code-graph.mjs`; `START-HERE` explains the three hops
> and the refresh.

This folder is a plain-Markdown vault. Any agent (Hermes, Freebuff, a future one) may read it. The rules below are what
keep it useful instead of a dump.

## The one rule that matters

**If the vault has the answer, answer from the vault and cite the note.** Do not answer from training data when a note
in here covers the question. If the vault is silent, say so, then answer normally and mark the note as a gap.

## Ownership: raw vs wiki

| Folder | Who writes | What goes in | Tracked in git |
| --- | --- | --- | --- |
| `raw/inbox/` | anything, append-only | transcripts, clippings, job output, quick captures, unsorted | **no** (gitignored) |
| `raw/compiled/` | the nightly compile job | daily/weekly digests distilled from `raw/inbox/` | **no** (gitignored) |
| `wiki/` | a human, or an agent via a proposed edit | durable, linked, deduplicated knowledge | yes |
| `Templates/` | human | one skeleton per note type | yes |
| `Decisions.md` | human (agent may propose a row) | what was decided and why | yes |

Never write directly into `wiki/` from a scheduled job. Jobs write `raw/`; a human promotes a digest into `wiki/` by
copying the useful three lines and linking the source. This is the whole point of the split: automation cannot quietly
rewrite what you believe.

## Routing — where does a note belong?

| The thing you have | Goes to | Template |
| --- | --- | --- |
| A call, a voice memo transcript, a decision made in a meeting | `raw/inbox/YYYY-MM-DD-meeting-<slug>.md` | `Templates/meeting-note.md` |
| A paper, docs page, competitor teardown, a finding with open questions | `raw/inbox/YYYY-MM-DD-research-<slug>.md` | `Templates/research-summary.md` |
| An article or thread you saved to read | `raw/inbox/YYYY-MM-DD-clip-<slug>.md` | `Templates/web-clipping.md` |
| What you did today, what is next | `raw/inbox/YYYY-MM-DD-daily.md` | `Templates/daily-note.md` |
| A spec, a PRD, scope for a feature | `wiki/PRD-<slug>.md` (propose; human merges) | `Templates/project-brief.md` |
| A choice that will be re-litigated otherwise | a row in `Decisions.md` + the long version in `.claude/notes/` | `Templates/decision.md` |
| A process you repeat | `Skills/` as a skill, not a note | `Templates/sop.md` |
| A comparison across several notes | `wiki/synthesis-<slug>.md` | `Templates/synthesis.md` |
| The end of a working session | `raw/inbox/YYYY-MM-DD-session-<slug>.md` | `Templates/session-memory.md` |

## banbe-specific rules

- **`.claude/notes/` is the system of record** for how the app works, numbered 01–101. The second brain indexes it; it
  never restates it. A new decision gets one row in `Decisions.md` and, if it changes behaviour, a new note in
  `.claude/notes/`.
- **Migrations are real state.** A note saying "migration 202 NOT applied" is load-bearing. Never write "applied" without
  a dated log line, and never let a summary drop the applied/not-applied distinction.
- **Verification status is part of the fact.** "Implemented" ≠ "built" ≠ "device-checked". Keep the app's own words
  (IMPLEMENTED LOCALLY / committed / pushed / applied / verified).
- **No secrets.** API keys, tokens and passwords never enter this vault, including `raw/`.

## Code graph rules (`graph/`)

- **One file belongs to one area.** Ownership is by symbols: the community holding most of a file's symbols owns it,
  and everything else in that file is read from that one note. Never hand-add a file to a second area, and never
  accept a refresh where the same `file:line` appears in two areas — the script exits non-zero instead of writing it.
- **The notes are generated; the names are curated.** To fix a wrong area name, edit `label` on that area's entry in
  `graph/areas.json` (the script keeps it across refreshes). Do not edit the generated note; a refresh overwrites it.
- **A hot file is homed, never duplicated.** Every file in the Hot files table belongs to exactly one area: its own
  community when that is big enough, otherwise the area it links to most. That is how the most-coupled files always
  have a note to open — never by adding the file to a second area.
- **Start with must be openable.** It points at a real symbol in the area's biggest file — never a test stub,
  `CodingKeys`, or a markdown note.

## House style

- One idea per note, a title that says the conclusion, links to sources at the top.
- Dates in `YYYY-MM-DD`. Tags as `#topic/subtopic` at the end.
- Prefer `[[wikilinks]]` between notes; a dead link is a useful TODO.

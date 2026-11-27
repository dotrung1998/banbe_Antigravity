# START HERE — the graph before the grep

**Agent: read this line first.** To answer anything about banbe, open **[[graph/Code map|Code map]]** and follow the
three hops below *before* you search the repository. Grep is the fallback, not the first move.

The code map is generated from the Graphify graph of this repo — roughly **17k symbols in 26 areas** (the exact
counts and the commit it was built from are at the top of [[graph/Code map|Code map]]). Obsidian renders the same notes
as a live graph. Neither list is hand-maintained, so it cannot quietly rot.

**One file, one area.** A file is listed under exactly one area — the community holding most of its symbols — so a
`file:line` has a single home. The script enforces the rule and exits non-zero rather than write a map where a file
sits in two areas. `graph/areas.json` remembers up to three files per area (so a re-partition cannot make an old area
vanish), and its optional `label` is the hand-fixed name a refresh must not undo: fix a wrong name there, never in the
note.

## The three hops

1. **Task → area.** Open [[graph/Code map|Code map]] and match the work to a row (or in Obsidian press `Cmd+G` and
   look for the cluster). Do not read the whole table if you already know the area.
2. **Area → entry point.** In that area note read **Start with** (`file:line`) and **Key symbols**. The area note also
   lists its files and the areas it talks to most.
3. **Entry point → code.** Open that `file:line`. If it answers the question, answer and cite the path. If it does
   not, *then* grep — and write the miss to `raw/inbox/` so the graph can grow.

## What this replaces (and what it does not)

| | Obsidian | Graphify |
| --- | --- | --- |
| Note graph (wiki, decisions, captures) | **yes** — live, updates as files change, zero rebuild | no |
| Code graph (symbols, calls, imports) | **no** — Obsidian does not read code | **yes** — builds `graphify-out/<date>/graph.json` |
| What you look at | `graph/` notes, backlinks, `Cmd+G` | `GRAPH_REPORT.md`, `graph.json` |

Obsidian does not replace Graphify; it displays what this script exports from it.

## Refresh (no manual copy-paste, ever)

```bash
graphify update .                          # re-index code, no API cost
node scripts/second-brain-code-graph.mjs   # rewrite docs/second-brain/graph/*.md
```

The script takes the 12 biggest areas and then keeps the known set from the previous run by **any
of the up to three files each area owned** (`docs/second-brain/graph/areas.json`, rewritten on every run). That
list exists because graphify re-partitions the graph on each update, so "the biggest
communities" used to reshuffle on a one-file change — on 2026-11-27 the iOS Home area came
out of the new graph labelled `.selection` and was dropped as noise, and EventDetailView fell
below the size cut, so `HomeView.swift` vanished from the map entirely. If you ever *want* a
fresh re-rank, delete `areas.json` and run the script again — but that also drops the hand-fixed
`label` names, so copy them back into the fresh file.

`scripts/banbe-code-graph.sh` runs both from cron, so the notes track the code without anyone remembering. Running
this script twice on the same graph produces identical files — a refresh only shows up in git when the code changed.
The refresh also checks the ownership rule first: a file found in two areas aborts the run, so a bad map is never
written.

**Staleness check:** the top of [[graph/Code map|Code map]] says which commit the graph was built from. Compare it to
`git rev-parse --short HEAD`. If they differ, files added since then are missing — run the two commands above.

## Where the truth lives (do not invert this)

1. **Code and applied migrations** — the only facts.
2. **`.claude/notes/01–101`** — canonical history and status of each feature.
3. **`wiki/` + [[Decisions]]** — durable conclusions and the anti-re-litigation log.
4. **`graph/`** — navigation only: it tells you *where* to look, never *what is true*.
5. **`raw/`** — unpromoted captures; nothing here is a decision yet.

If a generated note disagrees with the file it points at, the file wins. Say so, and fix the graph.

## Files in this vault

| Path | What it is |
| --- | --- |
| `START-HERE.md` | this file — the first thing an agent opens |
| `graph/` | generated code map: `Code map.md` + one note per area |
| `Home.md` | human index of the vault |
| `wiki/` | durable knowledge (`Project map`, `Conventions`, synthesis, PRDs) |
| `Decisions.md` | one row per decision, linked to `.claude/notes/` |
| `Templates/` | skeletons for captures and notes |
| `raw/inbox/`, `raw/compiled/` | append-only captures and nightly digests (gitignored) |
| `AGENTS.md` | the rules: ownership, routing, house style |
| `Skills/` | how a repeated process becomes a callable skill |

## Opening it

This folder **is** the Obsidian vault (already registered in the Obsidian app). Graph view: `Cmd+G`. Backlinks:
`Cmd+click` a note, or the right sidebar → Backlinks. No plugin is required.

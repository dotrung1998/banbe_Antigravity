# Hermes Agent — installed for banbe, and proven on this repo

Set up 2026-11-20 on the owner's Mac against the existing Hermes install (`~/.local/bin/hermes`, **v0.23.1**).
Everything below was run and observed. The "not verified" list at the end is real, and two earlier claims were
corrected by the runs on this page — see **Corrections**.

## Short answer to "is this better than Freebuff?"

Different jobs, not a replacement.

| | Freebuff (this chat) | Hermes Agent |
| --- | --- | --- |
| Lives in your editor / this conversation | yes | no |
| Builds, tests, previews, deploys this repo from a live session | yes | only via scripts you give it |
| Telegram / Discord / Slack / WhatsApp / Signal front ends | no | yes (needs bot tokens) |
| Persistent memory + search across past sessions | per project notes | built in (`MEMORY.md`, `USER.md`, FTS5 session search) |
| Self-created skills from repeated work | skills are curated by hand | agent writes and improves its own skills |
| Unattended cron jobs with delivery | no | yes (this install now has 7) |
| MCP servers (GitHub, docs, filesystem, databases…) | fixed tool set | any MCP server, local or remote |
| Cost | plan | your model keys (currently a free Nous Portal model) |

The practical split: **Freebuff is where the code gets changed and checked. Hermes is the always-on assistant that
watches the repo, writes the notes, and answers from them at 3 a.m.** They can share this repo and the second brain.

## Can Freebuff drive Hermes directly?

Yes — and now with evidence, not a smoke test. The pure one-shot is `hermes -z`, and
`hermes chat --oneshot -q … --format stream-json` gives a machine-readable transcript of every tool call, which is how
the runs below were audited.

```bash
cd /Users/thetrungdo/Downloads/banbe
hermes -z "Summarise the uncommitted changes and say which note owns each file"
hermes chat --oneshot -q "…"                 # same, with tool output in the transcript
hermes chat -q "…" --format stream-json      # JSONL: tool_use / tool_result / result events
hermes -z "…" --usage-file /tmp/usage.json   # cost per call
```

What it is **not**: a tool inside this conversation. It has its own model, its own context and its own tool loop; it
cannot see this chat, and it does not inherit Freebuff's browser or preview tools. Give it a self-contained prompt and a
working directory (`--in /Users/thetrungdo/Downloads/banbe`, or the registered project below).

### Proof it does real work here (2026-11-20)

Task: trace the guest "hold a seat" path and answer with `path:line` evidence. Ground truth was established first with
my own reads (`rg`, `read_files`), then each Hermes claim was checked against the file.

| Run | Tools available | Outcome | Token cost |
| --- | --- | --- | --- |
| A | all (built-in + MCP) | exit 0 · 6 answers · **5 fully correct**, 1 minor error | 906k |
| B | MCP only (`--toolsets skills,memory`) | exit 1 (turn limit) · latest-migration answer **wrong**, one question refused | 869k |
| C | all, vault reads pinned to MCP | exit 0 · **4/4 correct**, including a verbatim quote from the vault | 580k |

What run C produced, and how it checks out:

| Claim | Ground truth | Verdict |
| --- | --- | --- |
| latest `hold_seats` is `20261231000219_219_per_person_cap.sql:17` | `rg` finds 026:282, 031:38, 053:18, 113:295, 162:487, 219:17 — 219 is newest | correct |
| hold default 30 min, `031…sql:30` | `ALTER TABLE public.events ALTER COLUMN hold_minutes SET DEFAULT 30;` on line 30 | correct |
| web caller `submitReserve`, `BanBeContext.jsx:8938`, `supabase.rpc` at `:8963`, RPC `hold_seats_with_attendees` | both lines match exactly; the string is `'hold_seats_with_attendees'` | correct |
| vault row quoted from `Decisions.md` | identical to the file | correct |

Run A's one error: it listed `151:57` and `173:17` among the migrations that redefine `hold_seats`. Both are
`hold_seats_with_attendees`. Everything else in run A (including `booking_holds_seat` at `026:112` and the exact
"NOT IMPLEMENTED" sentence in `.claude/notes/02-confirm-qr.md:19`) was exact.

**Verdict: usable as a sub-agent for read-only repo questions, with two conditions** — keep the built-in file/terminal
tools available (see B), and spot-check citations on anything that matters. It is not a replacement for this chat's
build/test loop.

### What goes wrong when the agent cannot grep (concrete)

Run B, same six-question shape, MCP tools only, `upstage/solar-mini4:free`. Read this as a **tool-affordance** failure,
not a model verdict — the A/B below shows the same model answering the same questions correctly once `rg` is available:

- It answered Q1 with `20260917000053_053_hold_seats_guest_notification.sql:18` as the *latest* definition. Wrong:
  162 (line 487) and 219 (line 17) come later; it stopped scanning.
- It refused Q3 ("I could not locate the web-side caller… won't guess a file:line") because the MCP filesystem server
  searches files **by name, not content**, and it never found a way to grep. Honest, but incomplete.
- It printed the path `docs/.claude/notes/02-confirm-qr.md` — a path that does not exist.
- It exited 1 at the 20-turn cap, and in the transcript it called `.kilo/worktrees/sulfuric-lemonade` "the authoritative
  working tree".

That last one is a **real trap in this repo, independent of the model**: `git worktree list` shows
`.kilo/worktrees/sulfuric-lemonade` (branch `sulfuric-lemonade`, `6e911b5d`) checked out *inside* the repo. Any agent
that walks the tree can read a stale copy of a migration or a screen and cite it with confidence. `rg` skips it because
`.kilo/.gitignore` exists; a naive directory walk does not. Worth removing or moving outside the repo.

### Model A/B: a free alternative is not better here

Only **Nous Portal** is authenticated (`hermes status --full`): no OpenAI, Anthropic, OpenRouter, DeepSeek or xAI key.
That login reaches **826 models**, **10 of them `:free`**; the other 816 are paid Portal models.

Same scored task, same prompt file, built-in tools allowed, `--max-turns 8`, answers checked against the repo by hand:

| Model | Wall time | Tokens (in / out) | Tool calls | Q1 latest `hold_seats` | Q2 SLA quote |
| --- | --- | --- | --- | --- | --- |
| `upstage/solar-mini4:free` (current default) | **29.5 s** | 123k / 2.3k | 5 × terminal | `20261231000219_219_per_person_cap.sql:17` ✅ | exact sentence, line 19 ✅ |
| `qwen/qwen4-max:free` | 31.9 s | 153k / 3.3k | 7 × terminal | `20261231000219_219_per_person_cap.sql:17` ✅ | exact sentence, line 19 ✅ |

Both are right, so there is **no evidence `qwen4-max:free` is better** for this kind of work: it was ~8 % slower, used
~25 % more input tokens and two more tool calls to reach the same answer. It did enumerate the whole candidate list,
which is slightly more thorough, but it still listed `151` without noting that file defines
`hold_seats_with_attendees`, not `hold_seats`.

Practical conclusion: on the free tier the **tool set** is the bottleneck, not the model. A stronger model is worth
paying for only if you want Hermes to *change* code, where run A already produced one real slip.

- **Paid models (816)** are selectable on the same login but spend Portal credit — **your decision, not taken here**.
- `hermes model` is interactive only (no `--list`); override one run with
  `hermes chat -m <model> --provider nous -q "…"`.


## Installed

### MCP servers (`~/.hermes/config.yaml` → `mcp_servers`)

| Name | Transport | Tools | Purpose |
| --- | --- | --- | --- |
| `filesystem` | stdio `npx @modelcontextprotocol/server-filesystem` | 16 | read/write/search this repo only |
| `obsidian` | stdio, same server scoped to `docs/second-brain` | 16 | the video's "read/write/search your vault" |
| `context7` | remote `https://mcp.context7.com/mcp` | 2 | version-specific library docs (React, Vite, Supabase JS) |
| `deepwiki` | remote `https://mcp.deepwiki.com/mcp` | 3 | ask questions about public GitHub repos |

All four were connected and tool-listed by `hermes mcp test <name>`; `mcp__filesystem__read_file` was then exercised in
runs A–C. `filesystem` and `obsidian` are `lazy: true`, so their process only starts on the first tool call.

Caveat learned the hard way: the filesystem server has **no content search** (`search_files` matches names). A prompt
that forbids the built-in tools therefore removes the agent's ability to grep — see run B.

GitHub is deliberately **not** an MCP server here: the catalog says so, `gh` is already authenticated
(`dotrung1998`, scopes `repo`/`workflow`), and Hermes ships a `github` skill that drives `gh`.

### Project skills

`hermes skills trust /Users/thetrungdo/Downloads/banbe` → 6 project skills load inside this repo:

- `.hermes/skills/banbe-project/` — context, commands, money/migration/flag guardrails
- `.hermes/skills/banbe-second-brain/` — capture and query protocol
- plus the repo's existing `.agents/skills/` (code-review, prototype, using-git-worktrees, web-browsing-cli)

Evidence of loading: asked to list its preloaded skills, the agent named both `banbe-project` and `banbe-second-brain`
(alongside 43 built-ins), and run A called the `skill_view` tool. Note: `-s/--skills` **rejects** project skill names
with `unknown_skill`; project skills load automatically from the repo instead — do not pass `-s` for them.

### Project

`hermes project create banbe /Users/thetrungdo/Downloads/banbe --use` → sessions started here are grouped under
"banbe" in the Desktop app.

### Scheduled jobs (`hermes cron list`)

All run in `Asia/Ho_Chi_Minh`, deliver `local` (`~/.hermes/cron/output/<job>/`), and write a note into
`docs/second-brain/raw/inbox/` (gitignored).

| Job | When | Script | What it does |
| --- | --- | --- | --- |
| banbe standup | 09:00 Mon–Fri | `banbe-standup.sh` | commits since yesterday, dirty files, notes touched, TODO count |
| banbe nightly backup | 02:30 daily | `banbe-backup.sh` | verified `git bundle --all` + uncommitted patch, 21-day retention |
| banbe health check | every 6 h | `banbe-health.sh` | site 200, cron ticker heartbeat, disk free — **silent when healthy** |
| banbe weekly dependency audit | Sun 18:00 | `banbe-deps-audit.sh` | `npm outdated` + `npm audit`, silent when clean |
| banbe Friday wind-down | Fri 17:00 | `banbe-weekly-review.sh` | week's commits, hotspots, branches, what Monday starts with |
| banbe second-brain compile | 03:15 daily | agent + `banbe-inbox-changed.sh` monitor | distils the inbox into `raw/compiled/<date>-digest.md` |
| banbe apple notes to inbox | Sun 08:00, **paused** | `banbe-apple-notes-export.sh` | Apple Notes → inbox; needs macOS Automation permission |
| banbe code graph | Sun 04:30 | `banbe-code-graph.sh` | `graphify update .` + regenerate `docs/second-brain/graph/`; no model, silent unless it fails |

The first five are `--no-agent`: no model, no tokens. The compile job runs the agent only when the inbox fingerprint
changes; it was run once manually and produced a real digest citing its sources.

### Obsidian vault and the code map

`docs/second-brain` is registered as an Obsidian vault (entry in `~/Library/Application Support/obsidian/obsidian.json`),
so `Cmd+G` is the live graph and backlinks work without any plugin. Obsidian only renders Markdown — it cannot read
code — so the code graph is bridged into the vault as generated notes:

| Path | What it is |
| --- | --- |
| `docs/second-brain/START-HERE.md` | **the first file an agent opens** — three hops, graph before grep, refresh and truth hierarchy |
| `docs/second-brain/graph/Code map.md` | 24 areas, ~18k symbols, each row linking an area note with a `file:line` "Start with" |
| `docs/second-brain/graph/<area>.md` | one note per area: key symbols, top files, connected areas |
| `scripts/second-brain-code-graph.mjs` | the generator (`npm run graph:notes`); deterministic, so an unchanged graph leaves git clean |

Refresh: `graphify update .` then `npm run graph:notes`. The cron job **banbe code graph** does both every Sunday at
04:30 via `~/.hermes/scripts/banbe-code-graph.sh` (log: `~/.hermes/logs/banbe-code-graph.log`).

Obsidian vs Graphify: Obsidian replaces the *manual* browsing/updating of the note graph — it is live, nothing to
rebuild. It cannot replace Graphify, which is the only piece that understands code; the generated notes are what make
Graphify's output visible in Obsidian at all.

### Memory

Three entries written through the `memory` tool (verified in `~/.hermes/memories/MEMORY.md`): repo path + commands, the
vault's raw/wiki rule, and the "never claim applied without a log line" rule.

Note: the memory filter rejects entries that name agent config files (e.g. an `AGENTS.md` path) as
`agent_config_mod`. Phrase such entries without the filename.

### Editor integration (ACP — VS Code / Zed / JetBrains), proven end-to-end

The docs' bootstrap snippet points at `~/.hermes/hermes-agent/.venv/bin/python`, **which does not exist here**. The real
layout on this machine:

| What | Path |
| --- | --- |
| Launcher on PATH | `~/.local/bin/hermes-acp` (a 2-line `sh` wrapper) |
| Real launcher | `~/.hermes/hermes-agent/.hermes/bin/hermes-acp` |
| Interpreter it execs | `~/.hermes/tools/python-3.14.9+20261021-darwin-arm64/bin/python3` |
| Staged venv (has `acp` + a `hermes-acp` console script) | `~/.hermes/installs/<id>/environments/<hash>/venv` |
| Adapter package | `~/.hermes/hermes-agent/acp_adapter/` (`python -m acp_adapter` also starts it) |

Working commands:

```bash
hermes acp --check                  # → "Hermes ACP check OK"
hermes acp --version                # → 0.23.1
~/.local/bin/hermes-acp             # same server without depending on PATH
hermes acp                          # what an editor should launch
```

**Full client session over JSON-RPC on stdin/stdout** — not just a handshake. Transcript: `/tmp/acp-session.jsonl`
(729 messages), readable log `/tmp/acp-transcript.txt`.

| Step | Request | Response |
| --- | --- | --- |
| 1 | `initialize` `{protocolVersion:1, clientCapabilities:{fs:{false,false}, terminal:false}}` | `agentInfo {hermes-agent, 0.23.1}`, `protocolVersion 1`, `loadSession`, `fork/list/resume`, 2 auth methods |
| 2 | `session/new` `{cwd:"/Users/thetrungdo/Downloads/banbe", mcpServers:[]}` | `sessionId local-6aa91a87d014414754ba8388c8b04bc5f3a52e29f48fc534a38dacc95d7ceb49`, `configOptions` (mode `ask`), `_meta.hermes` provenance |
| 3 | `session/prompt` `{sessionId, prompt:[{type:"text", text:"…"}]}` | `stopReason:"end_turn"`, usage `{input 86,807 · output 782 · thought 624 · total 109,989}` |
| 4 | close stdin | process exited **0** on its own |

Streamed during the turn: 90 × `agent_message_chunk`, 623 × `agent_thought_chunk`, 2 × `tool_call`, plus
`session_info_update`, `config_option_update`, `usage_update`, `available_commands_update`.

Prompt sent:

> In one sentence: for a booking with `payment_state='holding'` and `hold_expires_at` in the past, what does
> `public.booking_holds_seat(...)` return? Cite the CASE branch's file:line.

Assistant output (verbatim):

> It returns `false`, because in the `booking_holds_seat` CASE
> (supabase/migrations/20260913000026_026_payment_state_machine.sql:129), the `p_state = 'holding'` branch only holds
> when `COALESCE(p_hold_expires_at, 'infinity') > now()`, and a past `hold_expires_at` fails that comparison.

Spot-checked: line 129 of that file **is** `WHEN p_state = 'holding' THEN COALESCE(p_hold_expires_at,
'infinity'::timestamptz) > now()`, and `ELSE false` follows. Correct answer, correct citation.

So the editor bridge is not merely installed: a client can create a session, send a prompt, receive the stream and a
terminal `stopReason`, and the server shuts down cleanly. No editor was launched — the editor-side JSON is that
editor's own business, with `hermes acp` as the command to register.


## Needs your keys or accounts (nothing here is installed)

| Video card | Command once you have the credential |
| --- | --- |
| Telegram | `hermes gateway setup` → bot token from @BotFather, then `hermes gateway start` |
| Discord | `hermes gateway setup` → application + bot token |
| Composio (1,000+ SaaS) | `hermes mcp install composio` (API key) |
| NotebookLM | no Nous-catalog entry; needs a Google session — `deepwiki`/`context7` stand in for docs |
| X-Hermes (Grok trend/search) | community MCP + `XAI_API_KEY` in `~/.hermes/.env` |
| Google Meet (join + transcribe) | Google OAuth through `hermes auth`; not in the catalog |
| Spotify | community MCP + Spotify OAuth app |
| Home Assistant | `hermes plugins install homeassistant` + `HASS_TOKEN` |
| Daily AI digest → Discord | needs Discord above; then `hermes cron create "0 7 * * *" "…" --deliver discord` |
| A stronger model | paid Nous Portal credits (826 models are reachable on the current login, 816 are paid) |

## The everyday loop

```bash
hermes                              # TUI in this repo
hermes -z "what changed in payments this week?"     # one-shot
hermes cron list                    # what is scheduled
hermes cron runs "banbe standup"    # did it actually run
hermes mcp list                     # servers and status
hermes skills list | grep banbe     # project skills
hermes acp --check                  # editor bridge
```

Read the second brain at `docs/second-brain/Home.md`; its rules are in `docs/second-brain/AGENTS.md`.

## Corrections to the first version of this page

1. **ACP was reported as "not installed / unverified".** Wrong. The documented bootstrap path is wrong for this install,
   but ACP is present and now has a full client session behind it: `session/new` → `session/prompt` →
   `stopReason: end_turn` → clean exit 0 (see above).
2. **"Direct use" rested on `hermes -z` echoing `HERMES_OK`.** That proved the entry point, not the agent. Runs A–C above
   replace it: real files, real MCP calls, real citations, and a written-down failure mode.
3. **"6/6 correct" would have been too generous.** Run A had one real error (the two `hold_seats_with_attendees`
   migrations), and run B was wrong on the latest-migration question. Both are recorded above.
4. **Run B was framed as model quality.** The A/B contradicts that framing: the same `solar-mini4:free` answers both
   scored questions correctly once `rg` is available, at the same speed as `qwen4-max:free`. The failure was the
   MCP-only constraint (no content search), not the model alone.
5. **ACP was said to be "handshake verified, prompt round-trip not".** The full session above now covers session
   creation, a prompt, the stream, `stopReason` and a clean exit.

## Rollback

```bash
hermes cron remove "banbe standup"        # …and the other six by name
hermes project archive banbe
hermes skills untrust /Users/thetrungdo/Downloads/banbe
# config: remove the `mcp_servers:` block and its comment; a backup is at
# ~/.hermes/config.yaml.bak-before-banbe-<timestamp>
# scripts: ~/.hermes/scripts/banbe-*.sh
# backups: ~/.hermes/backups/banbe/
```

Nothing here touches the app's runtime, the database, migrations or deploy config. The only repo changes are the
`docs/second-brain/` vault, `.hermes/skills/`, a `.gitignore` block, one `CLAUDE.md` index line and this page. Nothing
was committed or pushed.

## Not verified

- Telegram/Discord/Spotify/Meet/Home Assistant — no credentials were provided.
- Paid Portal models (816 reachable): accuracy untested, and picking one spends the owner's credit.
- A real editor (Zed / VS Code / JetBrains) attached over ACP: the protocol session is proven, the editor-side wiring is
  not.
- The Apple Notes export (paused; the first run will ask for Automation permission).
- iOS anything: none of this builds or runs the iOS app.

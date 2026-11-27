# Cloud Discord notifications — reporting while the MacBook sleeps

Hermes lives on the MacBook (`~/.local/bin/hermes`, `~/.hermes/`) and its scheduler is an **in-process ticker**
(`hermes cron status`). Two consequences matter:

- When the Mac sleeps, the ticker sleeps too. Nothing fires, nothing is delivered, and there is no cloud copy.
- A Freebuff cloud chat cannot host it: the chat VM has no `~/.hermes`, no Hermes install, cannot reach the Mac, and
  its processes do not survive the chat being archived. Freebuff's Discord integration is also read-only for our
  purposes (guild/member/invite lookups, no channel webhooks and no message posting).

So the always-on part moved to **GitHub Actions**, which runs in GitHub's cloud on a schedule and posts to Discord
channel webhooks. No Mac, no Freebuff session and no deploy is involved.

| Hermes job (Mac) | Cloud replacement | When (ICT) |
| --- | --- | --- |
| banbe standup | `standup` job | 09:00 Mon–Fri |
| banbe monitor | `health` job | hourly; one alert per incident, ✅ recovered when it clears |
| banbe Friday wind-down | `weekly` job | Fri 17:00 |
| banbe weekly dependency audit | `deps` job | Sun 18:00 |
| banbe daily audit / code graph / second-brain compile | `prompt` job | 05:00 daily: posts a ready-to-paste Freebuff Mission. The vault and graph notes now live in the repo; `graphify` itself is still a local install |
| audit → apply hand-off | `apply` mode | after an audit: posts the synthesized apply prompt, so a new session can open the fix PR |
| prototype ladder (7 lenses × 5 clusters) | `prototype` job | 06:00 daily: **5 messages**, one Mission per cluster, building on yesterday's folders |
| nightly verified `git bundle` | **stays on the Mac** — it backs up uncommitted local work | — |
| Apple Notes export | **stays on the Mac** — macOS Automation permission | — |

Files: `.github/workflows/discord-notify.yml` (schedule) and `scripts/cloud-notify.mjs` (what gets said).

## One-time setup (owner, ~2 minutes)

1. **Create one Discord webhook per channel.** Discord → the channel → *Edit Channel* → *Integrations* →
   *Webhooks* → *New Webhook* → *Copy Webhook URL*.
2. **Add them as Actions secrets.** GitHub repo → *Settings* → *Secrets and variables* → *Actions* → *New repository
   secret*:

   | Secret | Channel it feeds |
   | --- | --- |
   | `DISCORD_WEBHOOK_STANDUP` | standup |
   | `DISCORD_WEBHOOK_ALERTS` | health failures + recovery |
   | `DISCORD_WEBHOOK_WEEKLY` | week in review + dependency audit |

   All three may hold the same URL; a bare `DISCORD_WEBHOOK` is used as the fallback for any unset one.
   Optional: **secrets** `SUPABASE_URL` (`https://<project-ref>.supabase.co`, no trailing slash) and
   `SUPABASE_ANON_KEY` (the legacy `anon` JWT — the `sb_publishable_…` key is not a JWT) add the Supabase check to
   health. `APP_URL` is a repository **variable** (defaults to `https://www.banbe.app`).
3. **Merge the workflow to the default branch.** GitHub only runs `schedule` triggers from the default branch. Then
   *Actions* → *Discord notifications (cloud)* → *Run workflow* → job `test`.

Until a webhook secret is set the job prints the message plus a `no webhook configured` warning in the log — nothing is
lost, but nothing is delivered. A failing health check also exits non-zero in that state, so the missing alert shows up
as a red run instead of disappearing.

**Which channels.** Two is enough: a quiet `#banbe-alerts` for `DISCORD_WEBHOOK_ALERTS` (health: failures and the
recovery message) and `#banbe-reports` for `DISCORD_WEBHOOK_STANDUP` **and** `DISCORD_WEBHOOK_WEEKLY` (standup, Friday
review, dependency audit). Leave `#general` for conversation — alerts get buried there and read as noise on a busy
server. On a one-person server, one `#banbe-dev` channel and a single `DISCORD_WEBHOOK` is the smallest setup that
still works.

## How the health job behaves

- The first failure posts one 🚨 alert; before that the channel stays quiet.
- While the same checks keep failing it stays quiet and repeats at most once every `HEALTH_REPEAT_HOURS` (default 6;
  set that name as a repository **variable** to change it). Hourly runs still check, they just do not re-post.
- A different failing set (for example Supabase goes down while the app is already down) alerts immediately.
- When everything passes again it posts **✅ banbe recovered**, with how long the failure had been open.
- That memory lives in the Actions cache (`health-state-*`) and is branch-scoped: scheduled runs on the default branch
  share it; a manual run on another branch starts from an empty state (so it may alert again there).

## Checking it

```bash
# Build the payload and print it, without sending:
node scripts/cloud-notify.mjs standup --dry-run
node scripts/cloud-notify.mjs weekly --dry-run
node scripts/cloud-notify.mjs deps --dry-run

# Post to a real webhook from this machine (any one of the URLs):
DISCORD_WEBHOOK_ALERTS='https://discord.com/api/webhooks/…' node scripts/cloud-notify.mjs test

# Force the healthy case to post too:
node scripts/cloud-notify.mjs health --always --dry-run
```

In Actions the same jobs are selectable from *Run workflow*.

## Turning the Hermes schedules off (pause, never delete)

Run this **on the Mac**, in the repo:

```bash
bash scripts/hermes-pause-all.sh
hermes cron list                 # every job should now show paused
hermes cron resume "<job name>"  # bring one back whenever you want
```

The script reads `~/.hermes/cron/jobs.json` read-only, gets the ids of enabled jobs, and calls
`hermes cron pause <id>` for each. Nothing is removed; `hermes cron remove` is never used.

## The daily Freebuff mission prompt

Hermes' `banbe daily audit` cannot move here: its scheduler is an in-process ticker on the Mac, and Freebuff
refuses automated runs (its CLI has no headless prompt and repeated automated use is recorded as a strike). So the
`prompt` job posts the mission as **plain text** to `#banbe-reports` every day at 05:00 ICT; a person pastes it into
a Freebuff session, which then does the work with a human in the loop. The message itself runs nothing.

The message stays short on purpose: it names the day's jobs and points at
[`docs/prompts/daily-hermes.md`](prompts/daily-hermes.md), the versioned mission that carries the full checklist —
standup, health, technical audit, UI/UX review (6 places + 7 dimensions), dependency check, and the Friday/Sunday
variants. That file also fixes the **source ladder** (repo → standards → articles → video, with caps), so a run
cannot pass off a listicle or a YouTube video as evidence for a P0/P1.

Preview it without sending:

```bash
node scripts/cloud-notify.mjs prompt --dry-run
```

## The prototype mission — five messages a day

The 8-day prototype ladder (`docs/prototypes/`) is a matrix: 7 lenses × 5 screen clusters (`onboarding`,
`discover`, `event`, `me`, `host`). The job posts **five messages a day, one per cluster**: the day's lens, that
cluster's own focus, tasks, checks, deliverable and "must keep". The shared contract (4 device frames, reset,
deep links, cross-cluster links, data rules, 20-minute budget) is `docs/prototypes/missions/STANDARD.md`; the
scaffold is `docs/prototypes/shared/`. Edit the plan and the standard, not the script. Day 8 posts the single
review mission (it reviews all five folders, so it is not split).

```bash
node scripts/cloud-notify.mjs prototype --dry-run                          # all five messages for today
node scripts/cloud-notify.mjs prototype --day 3 --cluster event --dry-run   # only the event cluster
```

Day selection: `PROTOTYPE_START` (repository **variable**, default `2026-11-27`) is day 1; today's day is the calendar
difference + 1, clamped to 1..8. `PROTOTYPE_DAY` (variable) or `--day N` pins one. Every message is wrapped like an
apply prompt — a bold header, the paste line, one fenced `text` block — and is refused (exit non-zero) above 1,900
characters, so it always stays one copyable message.

The mission names the answer file (`decisions/day-NN.json`), the previous day's folder of the same clusters, what to
capture (real screenshots — never a made-up screen), what to hand in, and a `grill-me` round per cluster (at most three
hard questions, skipping what the owner already answered on the Glance board). Day 8 reads only `done/` and produces
the APPLY prompt.

## The apply prompt after an audit

An audit that found something to fix ends by writing two files: `APPLY.md` — the detailed **self-contained** mission (≤ 4,500 characters) with exact findings, `path:line`, acceptance, tests, branch and PR rules — and `APPLY.discord.md`, the short copyable Discord message: a bold `**Mission APPLY — …**` header, the line `Dán khối dưới vào một phiên Freebuff mới (Mission):`, and one fenced `text` block containing the prompt. It posts the Discord file:

```bash
node --env-file=.env scripts/cloud-notify.mjs apply --file docs/audits/<date>/APPLY.discord.md
```

The script wraps a raw prompt into this shape and refuses anything over 1,800 characters, so an APPLY hand-off is always one copyable message and is never split. Keep `APPLY.discord.md` under 1,800 characters to pass the check. Nothing is committed and no issue is opened: the prompt never passes through the public repo.

This needs `DISCORD_WEBHOOK_WEEKLY` in the audit machine's `.env` (gitignored) or shell — the same URL as the Actions secret, which Actions cannot hand to the audit session. Without it the script prints the full prompt and exits non-zero, so the audit can paste it into chat as `apply: not sent — <reason>` instead of losing it.

The apply mission (`docs/prompts/apply-hermes.md`) tells the new session to re-check every finding against HEAD, fix P0/P1 plus selected P2, run build/unit/targeted Playwright, open a PR (never merge) with a preview checklist, and stop if nothing is still true. It also forbids secrets and PII in the prompt, PR, logs, screenshots and fixtures — the webhook URL itself is a secret and stays in `.env`.

## Limits worth knowing

- GitHub's scheduled runs can start a few minutes late; hourly means "about hourly".
- A scheduled workflow is disabled after **60 days without repository activity** — GitHub emails the owner, and any
  push re-enables it.
- `health` needs the Actions-cache state to know it already alerted. If a cache save fails, the next hour may repeat
  an alert or miss a recovery message; the checks themselves still run. A quiet channel means healthy — check
  *Actions* if a failure was expected.
- The cloud jobs cannot see uncommitted local files or the second brain compiler; those stay with Hermes on the Mac.
- The `prompt` job only sends text. Nothing in this repo can start or drive a Freebuff session; pasting the mission
  is the step that gives Freebuff its instructions.
- The `apply` job is the same: it only posts the prompt the audit already wrote. The audit has to be able to reach
  Discord with `DISCORD_WEBHOOK_WEEKLY`, and the fix PR is still opened by the session the owner pastes it into.
- If Cloudflare ever bot-challenges the runner, the App check reports `HTTP 403`; point the `APP_URL` variable at the
  Vercel deployment hostname instead.
- The Supabase check reads `/rest/v1/events?select=id&limit=1`, **not** `/rest/v1/`: Supabase answers the OpenAPI root
  with `401 {"message":"Invalid API key","hint":"Only the service_role API key can be used for this endpoint."}` even
  for a perfectly valid anon key. If `events` is ever renamed or its anon RLS removed, that check starts failing for a
  reason that is not an outage.

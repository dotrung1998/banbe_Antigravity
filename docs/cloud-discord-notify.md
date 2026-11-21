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
| banbe monitor | `health` job | hourly, silent while healthy |
| banbe Friday wind-down | `weekly` job | Fri 17:00 |
| banbe weekly dependency audit | `deps` job | Sun 18:00 |
| nightly verified `git bundle` | **stays on the Mac** — it backs up uncommitted local work | — |
| second-brain compile / code graph / daily audit | **stays on the Mac** — needs the local vault, `graphify` and a model | — |
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
   | `DISCORD_WEBHOOK_ALERTS` | health failures |
   | `DISCORD_WEBHOOK_WEEKLY` | week in review + dependency audit |

   All three may hold the same URL; a bare `DISCORD_WEBHOOK` is used as the fallback for any unset one.
   Optional: `SUPABASE_ANON_KEY` (adds the Supabase REST check to health; `SUPABASE_URL` already exists for the backup
   job) and the repository **variable** `APP_URL` (defaults to `https://www.banbe.app`).
3. **Merge the workflow to the default branch.** GitHub only runs `schedule` triggers from the default branch. Then
   *Actions* → *Discord notifications (cloud)* → *Run workflow* → job `test`.

Until a webhook secret is set the job stays green and prints the message plus a `no webhook configured` warning in the
log — nothing is lost, but nothing is delivered either.

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

## Limits worth knowing

- GitHub's scheduled runs can start a few minutes late; hourly means "about hourly".
- A scheduled workflow is disabled after **60 days without repository activity** — GitHub emails the owner, and any
  push re-enables it.
- `health` posts only when a check fails. It has no "recovered" state, so a quiet channel means healthy (or that the
  secret is missing — check *Actions* if suspicious).
- The cloud jobs cannot see uncommitted local files or the second brain compiler; those stay with Hermes on the Mac.
- If Cloudflare ever bot-challenges the runner, the App check reports `HTTP 403`; point the `APP_URL` variable at the
  Vercel deployment hostname instead.

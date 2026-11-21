#!/usr/bin/env bash
# Pause (never remove) every Hermes cron job on this Mac.
#
# Hermes' scheduler is an in-process ticker: when the Mac sleeps, no job fires
# and nothing is delivered. Pause the jobs here and let the cloud workflow
# (.github/workflows/discord-notify.yml) send the reports instead.
#
#   bash scripts/hermes-pause-all.sh          # pause every enabled job
#   hermes cron list                          # confirm they show as paused
#   hermes cron resume "<job name>"           # bring one back later
#
# Nothing is deleted. Pausing only flips enabled=false / state=paused in
# ~/.hermes/cron/jobs.json, through the CLI itself (atomic writes preserved).
set -euo pipefail

if [ -n "${HERMES_BIN:-}" ]; then
  BIN="$HERMES_BIN"
elif command -v hermes >/dev/null 2>&1; then
  BIN="$(command -v hermes)"
elif [ -x "$HOME/.local/bin/hermes" ]; then
  BIN="$HOME/.local/bin/hermes"
else
  echo "hermes not found (looked on PATH and at ~/.local/bin/hermes)" >&2
  echo "nothing was changed." >&2
  exit 1
fi

JOBS_FILE="${HERMES_HOME:-$HOME/.hermes}/cron/jobs.json"
if [ ! -f "$JOBS_FILE" ]; then
  echo "no Hermes cron file at $JOBS_FILE — nothing was changed." >&2
  exit 1
fi

# Read-only: ids + names of jobs that are still enabled. Tolerates either the
# documented shape ({"jobs":[...]}) or a bare array.
ROWS="$(
  node --input-type=module -e '
    import fs from "node:fs";
    const parsed = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const jobs = Array.isArray(parsed) ? parsed : Array.isArray(parsed.jobs) ? parsed.jobs : [];
    for (const job of jobs) {
      if (!job || !job.id || job.enabled === false) continue;
      process.stdout.write(`${job.id}\t${job.name ?? ""}\n`);
    }
  ' "$JOBS_FILE"
)"

if [ -z "$ROWS" ]; then
  echo "no enabled Hermes cron jobs — nothing to pause."
  "$BIN" cron list || true
  exit 0
fi

paused=0
failed=0
while IFS=$'\t' read -r id name; do
  [ -n "$id" ] || continue
  printf 'pausing %s (%s)… ' "${name:-unnamed}" "$id"
  if "$BIN" cron pause "$id" >/dev/null 2>&1; then
    echo "ok"
    paused=$((paused + 1))
  else
    echo "FAILED"
    failed=$((failed + 1))
  fi
done <<< "$ROWS"

echo
echo "paused $paused job(s); $failed failed; nothing was removed."
"$BIN" cron list || true
echo
echo "resume one later with: hermes cron resume \"<job name>\""

[ "$failed" -eq 0 ]

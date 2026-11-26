#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$HOME/Library/Logs"

while IFS=$'\t' read -r slug vault repo title serve_port public_port; do
  [ -z "${slug:-}" ] && continue
  case "$slug" in \#*) continue;; esac
  pidfile="$HOME/Library/Logs/banbe-notes-$slug.pid"
  if [ -f "$pidfile" ]; then
    old=$(cat "$pidfile")
    ps -p "$old" -o command= 2>/dev/null | grep -q 'ops/notes/serve.py' && kill "$old" 2>/dev/null || true
  fi
  sleep 0.3
  if lsof -nP -iTCP:"$serve_port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "PORT BUSY $serve_port — không start $slug"; exit 1
  fi
  nohup python3 "$REPO_ROOT/ops/notes/serve.py" --root "$SITES_ROOT/$slug/public" --port "$serve_port" \
    >> "$HOME/Library/Logs/banbe-notes-$slug.log" 2>&1 &
  echo $! > "$pidfile"
  echo "$slug -> $serve_port (pid $!)"
done < "$REPO_ROOT/ops/notes/sites.tsv"

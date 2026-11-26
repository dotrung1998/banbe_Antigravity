#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
TS_HOST=$(tailscale status --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')

# Base chỉ tạo một lần; không lấy config đã bị swap của site trước.
[ -f "$QUARTZ_DIR/quartz.config.base.yaml" ] || cp "$QUARTZ_DIR/quartz.config.yaml" "$QUARTZ_DIR/quartz.config.base.yaml"

while IFS=$'\t' read -r slug vault repo title serve_port public_port; do
  [ -z "${slug:-}" ] && continue
  case "$slug" in \#*) continue;; esac
  cp "$QUARTZ_DIR/quartz.config.base.yaml" "$QUARTZ_DIR/quartz.config.$slug.yaml"
  python3 "$REPO_ROOT/ops/notes/patch-quartz-config.py" "$QUARTZ_DIR/quartz.config.$slug.yaml" \
    --title "$title" --base-url "$TS_HOST:$public_port" \
    --ignore "raw/**,.obsidian/**,.trash/**,Templates/**,node_modules/**,.git/**,**/__pycache__/**"
done < "$REPO_ROOT/ops/notes/sites.tsv"

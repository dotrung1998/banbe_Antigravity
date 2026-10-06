#!/usr/bin/env bash
# Isolated local Supabase stack for E2E (own project id + ports; never touches other containers).
#   scripts/e2e-local/stack.sh up|down|migrate|env|status
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="${E2E_STACK_DIR:-${TMPDIR:-/tmp}/banbe-e2e-stack}"
SB=(npx --yes supabase@latest)
prep() {
  mkdir -p "$WORK/supabase/migrations"
  python3 - "$ROOT/supabase/config.toml" "$WORK/supabase/config.toml" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
s=s.replace('project_id = "banbe"','project_id = "banbe-e2e-r2"')
for a,b in [("port = 54321","port = 55321"),("port = 54322","port = 55322"),("port = 54329","port = 55329"),("port = 54323","port = 55323"),("port = 54324","port = 55324"),("port = 54327","port = 55327")]: s=s.replace(a,b)
for sec in ["edge_runtime","analytics","storage.analytics","storage.vector","studio"]:
    s=re.sub(r'(\[%s\]\n(?:[^\[]*?)enabled = )true'%re.escape(sec), r'\1false', s, count=1)
s=s.replace('site_url = "http://127.0.0.1:3000"','site_url = "http://localhost:5199"').replace('additional_redirect_urls = ["https://127.0.0.1:3000"]','additional_redirect_urls = ["http://localhost:5199"]')
open(sys.argv[2],'w').write(s)
PY
  rsync -a --delete "$ROOT/supabase/migrations/" "$WORK/supabase/migrations/"
}
case "${1:-}" in
  up) prep; (cd "$WORK" && "${SB[@]}" start --workdir "$WORK" -x studio,edge-runtime,logflare,vector,imgproxy) ;;
  migrate) prep; (cd "$WORK" && "${SB[@]}" migration up --local --workdir "$WORK") ;;
  down) (cd "$WORK" && "${SB[@]}" stop --no-backup --workdir "$WORK") ;;
  env) (cd "$WORK" && "${SB[@]}" status --workdir "$WORK" -o env 2>/dev/null) ;;
  status) docker ps --format '{{.Names}}\t{{.Status}}' | grep e2e-r2 || echo "stack not running" ;;
  *) echo "usage: $0 up|migrate|down|env|status"; exit 2 ;;
esac

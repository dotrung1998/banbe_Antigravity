#!/usr/bin/env bash
# LOCAL TEST HARNESS ONLY. Migrates the LOCAL docker postgres to 178 (everything BEFORE 179), builds legacy-shaped
# reward data + records what the old functions return, applies 179, then proves nothing changed for old data
# and that the new kind behaves (NOT_AVAILABLE, hidden offers, locking only for keychain designs).
set -uo pipefail
CONTAINER=${CONTAINER:-banbe-pg}; DBUSER=${DBUSER:-supabase_admin}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; T="$ROOT/supabase/_localtest"
psql_run() { docker exec -i "$CONTAINER" psql -U "$DBUSER" -d postgres -q -v ON_ERROR_STOP=1 -f - ; }
docker exec "$CONTAINER" psql -U "$DBUSER" -d postgres -q -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null 2>&1
docker exec "$CONTAINER" psql -U "$DBUSER" -d postgres -q -c "TRUNCATE storage.objects;" >/dev/null 2>&1
psql_run < "$T/00_bootstrap_storage.sql" 2>&1 | grep -E '(ERROR|FATAL):' && { echo "bootstrap FAILED"; exit 1; }
apply() { { printf 'BEGIN;\n'; cat "$1"; printf '\nCOMMIT;\n'; } | psql_run 2>&1 | grep -E '(ERROR|FATAL):' | head -2; }
for f in "$ROOT"/supabase/migrations/*.sql; do
  case "$(basename "$f")" in *_179_reward_kinds.sql|*_18[0-9]_*|*_19[0-9]_*) continue;; esac   # 179 and everything after it (they build on 179)
  err=$(apply "$f"); [ -n "$err" ] && { echo "FAILED $(basename "$f")"; echo "$err"; exit 1; }
done
psql_run < "$T/01_seed.sql" 2>&1 | grep -E '(ERROR|FATAL):' -A2 && { echo "seed FAILED"; exit 1; }
psql_run < "$T/16a_kinds_before.sql" 2>&1 | grep -E 'ERROR' -A2 && { echo "16a FAILED"; exit 1; }
err=$(apply "$ROOT/supabase/migrations/20261220000179_179_reward_kinds.sql"); [ -n "$err" ] && { echo "179 FAILED: $err"; exit 1; }
OUT=$(psql_run < "$T/16b_kinds_after.sql" 2>&1)
echo "$OUT" | grep -E 'PASS|FAIL|ERROR|KINDS RESULT' | sed 's/^psql:<stdin>:[0-9]*: //'
echo "$OUT" | grep -q 'KINDS RESULT: ALL PASS' && ! echo "$OUT" | grep -q 'ERROR'

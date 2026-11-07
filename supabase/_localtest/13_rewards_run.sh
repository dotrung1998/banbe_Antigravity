#!/usr/bin/env bash
# LOCAL TEST HARNESS ONLY — never deployed, never touches a real project or .env.
# Resets the LOCAL docker postgres (`banbe-pg`), applies every migration in order (aborting on
# the first error), then runs the rewards assertions (13_rewards_assert.sql).
#   ./supabase/_localtest/13_rewards_run.sh
set -uo pipefail
CONTAINER=${CONTAINER:-banbe-pg}
DBUSER=${DBUSER:-supabase_admin}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MIG="$ROOT/supabase/migrations"
T="$ROOT/supabase/_localtest"
psql_run() { docker exec -i "$CONTAINER" psql -U "$DBUSER" -d postgres -q -v ON_ERROR_STOP=1 -f - ; }

docker exec "$CONTAINER" psql -U "$DBUSER" -d postgres -q -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null 2>&1
docker exec "$CONTAINER" psql -U "$DBUSER" -d postgres -q -c "TRUNCATE storage.objects;" >/dev/null 2>&1
psql_run < "$T/00_bootstrap_storage.sql" 2>&1 | grep -E '(ERROR|FATAL):' && { echo "bootstrap FAILED"; exit 1; }

n=0
for f in "$MIG"/*.sql; do
  n=$((n+1))
  err=$( { printf 'BEGIN;\n'; cat "$f"; printf '\nCOMMIT;\n'; } | psql_run 2>&1 | grep -E '(ERROR|FATAL):' | head -2 )
  if [ -n "$err" ]; then echo "FAILED #$n $(basename "$f")"; echo "$err" | sed 's/^/    /'; exit 1; fi
done
echo "OK: all $n migrations applied"
psql_run < "$T/01_seed.sql" 2>&1 | grep -E '(ERROR|FATAL):' -A2 && { echo "seed FAILED"; exit 1; }
OUT=$(psql_run < "$T/13_rewards_assert.sql" 2>&1)
echo "$OUT" | grep -E 'PASS|FAIL|ERROR|REWARDS' | sed 's/^psql:<stdin>:[0-9]*: //'
echo "$OUT" | grep -q 'REWARDS RESULT: ALL PASS' && ! echo "$OUT" | grep -q 'ERROR'

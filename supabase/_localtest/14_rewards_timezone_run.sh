#!/usr/bin/env bash
# LOCAL TEST HARNESS ONLY. Resets the local docker postgres via 13_rewards_run.sh (all migrations + 165 suite),
# then runs the 177 timezone assertions on the same database.
set -uo pipefail
CONTAINER=${CONTAINER:-banbe-pg}; DBUSER=${DBUSER:-supabase_admin}
T="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$T/13_rewards_run.sh" >/dev/null 2>&1 || { echo "13_rewards_run.sh failed — run it directly"; exit 1; }
OUT=$(docker exec -i "$CONTAINER" psql -U "$DBUSER" -d postgres -q -v ON_ERROR_STOP=1 -f - < "$T/14_rewards_timezone_assert.sql" 2>&1)
echo "$OUT" | grep -E 'PASS|FAIL|ERROR|TZ RESULT' | sed 's/^psql:<stdin>:[0-9]*: //'
echo "$OUT" | grep -q 'TZ RESULT: ALL PASS' && ! echo "$OUT" | grep -q 'ERROR'

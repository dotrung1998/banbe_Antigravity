#!/usr/bin/env bash
# LOCAL TEST HARNESS ONLY — never deployed, never touches a real project or .env.
# Resets the LOCAL docker postgres, applies every migration in order (aborting on the first error), seeds, then runs
# every suite of the retention-plan run (2026-10-23 onward): 23 push, 24 US tz/currency (with the shared vectors of
# tests/fixtures/event-market.json), 25 measurement + age, and later ones as they are added below.
#   CONTAINER=banbe-pg ./supabase/_localtest/retention_suites_run.sh
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

status=0
run_suite() {   # run_suite <file> <result marker> [prefix sql]
  local out
  out=$( { [ -n "${3:-}" ] && echo "$3"; cat "$T/$1"; } | psql_run 2>&1)
  echo "$out" | grep -E 'FAIL|ERROR|RESULT' | sed 's/^psql:<stdin>:[0-9]*: //'
  echo "$out" | grep -q "$2" || { echo "SUITE FAILED: $1"; status=1; }
}
VEC=$(node --input-type=module -e '
  import { readFileSync } from "node:fs";
  const v = JSON.parse(readFileSync(process.argv[1], "utf8"));
  const q = (x) => x == null ? "NULL" : `'"'"'${String(x).replace(/'"'"'/g, "'"'"''"'"'")}'"'"'`;
  const out = ["BEGIN;",
    "CREATE TEMP TABLE vec_tz (country text, state text, tz text);",
    "CREATE TEMP TABLE vec_cur (country text, currency text);",
    "CREATE TEMP TABLE vec_resolved (country text, state text, client_tz text, tz text);",
    "CREATE TEMP TABLE vec_wall (d date, t time, tz text, utc timestamptz);"];
  for (const r of v.timeZones) out.push(`INSERT INTO vec_tz VALUES (${q(r.country)}, ${q(r.state)}, ${q(r.tz)});`);
  for (const r of v.currencies) out.push(`INSERT INTO vec_cur VALUES (${q(r.country)}, ${q(r.currency)});`);
  for (const r of v.resolvedZones) out.push(`INSERT INTO vec_resolved VALUES (${q(r.country)}, ${q(r.state)}, ${q(r.clientTz)}, ${q(r.tz)});`);
  for (const r of v.wallClock) out.push(`INSERT INTO vec_wall VALUES (${q(r.date)}, ${q(r.time)}, ${q(r.tz)}, ${q(r.utc)});`);
  console.log(out.join("\n"));
' "$ROOT/tests/fixtures/event-market.json")

run_suite 23_push_delivery_assert.sql 'PUSH RESULT: ALL PASS'
run_suite 24_event_tz_currency_assert.sql 'US RESULT: ALL PASS' "$VEC"
run_suite 25_measurement_age_assert.sql 'MEASURE RESULT: ALL PASS'
run_suite 26_quickwins_coreloops_assert.sql 'LOOPS RESULT: ALL PASS'
run_suite 27_digest_assert.sql 'DIGEST RESULT: ALL PASS'
exit $status

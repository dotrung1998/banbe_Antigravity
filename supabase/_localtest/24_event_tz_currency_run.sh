#!/usr/bin/env bash
# LOCAL TEST HARNESS ONLY — never deployed, never touches a real project or .env.
# Resets the LOCAL docker postgres, applies every migration in order (aborting on the first error),
# seeds, then runs 23_push_delivery_assert.sql (migration 194) and 24_event_tz_currency_assert.sql
# (migration 195) — the latter with the shared vectors from tests/fixtures/event-market.json.
#   CONTAINER=banbe-pg ./supabase/_localtest/24_event_tz_currency_run.sh
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
OUT=$(psql_run < "$T/23_push_delivery_assert.sql" 2>&1)
echo "$OUT" | grep -E 'PASS|FAIL|ERROR|RESULT' | sed 's/^psql:<stdin>:[0-9]*: //'
echo "$OUT" | grep -q 'PUSH RESULT: ALL PASS' || status=1

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
OUT=$( { echo "$VEC"; cat "$T/24_event_tz_currency_assert.sql"; } | psql_run 2>&1)
echo "$OUT" | grep -E 'PASS|FAIL|ERROR|RESULT' | sed 's/^psql:<stdin>:[0-9]*: //'
echo "$OUT" | grep -q 'US RESULT: ALL PASS' || status=1
exit $status

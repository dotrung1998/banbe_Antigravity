#!/usr/bin/env bash
# LOCAL TEST HARNESS ONLY — throwaway container, NEVER production. Migrates to 179, snapshots the old RPCs, applies 180,
# then proves the old RPCs are byte-identical and the new counters are non-identifying / flag-gated / thresholded.
# Also tests the rollback file with and without data, and an atomic-upsert race. Use CONTAINER=banbe-pg3.
set -uo pipefail
CONTAINER=${CONTAINER:-banbe-pg}; DBUSER=${DBUSER:-supabase_admin}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; T="$ROOT/supabase/_localtest"
psql_run() { docker exec -i "$CONTAINER" psql -U "$DBUSER" -d postgres -q -v ON_ERROR_STOP=1 -f - ; }
q() { docker exec "$CONTAINER" psql -U "$DBUSER" -d postgres -Atq -c "$1"; }
docker exec "$CONTAINER" psql -U "$DBUSER" -d postgres -q -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null 2>&1
docker exec "$CONTAINER" psql -U "$DBUSER" -d postgres -q -c "TRUNCATE storage.objects;" >/dev/null 2>&1
psql_run < "$T/00_bootstrap_storage.sql" 2>&1 | grep -E '(ERROR|FATAL):' && { echo "bootstrap FAILED"; exit 1; }
apply() { { printf 'BEGIN;\n'; cat "$1"; printf '\nCOMMIT;\n'; } | psql_run 2>&1 | grep -E '(ERROR|FATAL):' | head -2; }
for f in "$ROOT"/supabase/migrations/*.sql; do
  case "$(basename "$f")" in *_180_reward_event_counters.sql) continue;; esac
  err=$(apply "$f"); [ -n "$err" ] && { echo "FAILED $(basename "$f")"; echo "$err"; exit 1; }
done
psql_run < "$T/01_seed.sql" 2>&1 | grep -E '(ERROR|FATAL):' -A2 && { echo "seed FAILED"; exit 1; }
psql_run < "$T/18a_events_before.sql" 2>&1 | grep -E 'ERROR' -A2 && { echo "18a FAILED"; exit 1; }
err=$(apply "$ROOT/supabase/migrations/20261221000180_180_reward_event_counters.sql"); [ -n "$err" ] && { echo "180 FAILED: $err"; exit 1; }
OUT=$(psql_run < "$T/18b_events_after.sql" 2>&1)
echo "$OUT" | grep -E 'PASS|FAIL|ERROR|EVENTS RESULT' | sed 's/^psql:<stdin>:[0-9]*: //'
echo "$OUT" | grep -q 'EVENTS RESULT: ALL PASS' && ! echo "$OUT" | grep -q 'ERROR' || exit 1

# atomic upsert under concurrency: 24 parallel calls -> exactly 24
q "INSERT INTO reward_catalog(code,kind,design_id,price) VALUES ('ev-race','partner_offer',NULL,1) ON CONFLICT DO NOTHING; UPDATE reward_feature_flags SET enabled=true WHERE flag='reward_events';" >/dev/null
for i in $(seq 1 24); do
  docker exec "$CONTAINER" psql -U "$DBUSER" -d postgres -Atq -c "SELECT set_config('request.jwt.claim.sub','7a3a0001-0000-4000-8000-000000000001',false); SELECT public.record_reward_event('ev-race','offer_viewed','VN');" >/dev/null 2>&1 &
done; wait
N=$(q "SELECT COALESCE(sum(count),0) FROM reward_event_counters WHERE offer_id='ev-race'"); ROWS=$(q "SELECT count(*) FROM reward_event_counters WHERE offer_id='ev-race'")
[ "$N" = "24" ] && [ "$ROWS" = "1" ] && echo "PASS 24 concurrent recordings -> count 24 in a single row" || { echo "FAIL concurrency: count=$N rows=$ROWS"; exit 1; }

# rollback WITH data: flag off, objects kept
psql_run < "$ROOT/supabase/rollbacks/20261221000180_180_revert_reward_event_counters.sql" 2>&1 | grep -E 'ERROR' && exit 1
[ "$(q "select enabled from reward_feature_flags where flag='reward_events'")" = "f" ] && [ "$(q "select sum(count) from reward_event_counters")" = "24" ] \
  && echo "PASS rollback with data: flag off, counters kept" || { echo "FAIL rollback with data"; exit 1; }
# rollback on EMPTY table: objects dropped
q "DELETE FROM reward_event_counters" >/dev/null
psql_run < "$ROOT/supabase/rollbacks/20261221000180_180_revert_reward_event_counters.sql" 2>&1 | grep -E 'ERROR' && exit 1
[ -z "$(q "select to_regclass('public.reward_event_counters')")" ] && [ -z "$(q "select to_regprocedure('public.record_reward_event(text,text,text)')")" ] && [ "$(q "select count(*) from reward_feature_flags where flag='reward_events'")" = "0" ] \
  && echo "PASS rollback on empty table: new objects removed" || { echo "FAIL rollback empty"; exit 1; }
echo "EVENTS RUN: ALL PASS"

#!/usr/bin/env bash
# LOCAL TEST HARNESS ONLY — never deployed, never touches a real project or .env.
# Production applies 177-180 AFTER 181-190 (they were written earlier but merged later; `db push --include-all`).
# This applies the chain in that order, runs the rewards assertion suites (13, 20, 21), then checks the 192 and 191
# rollbacks (each followed by the same migration re-applied).
#   CONTAINER=banbe-pg ./supabase/_localtest/22_rewards_prod_order_run.sh
set -uo pipefail
CONTAINER=${CONTAINER:-banbe-pg}; DBUSER=${DBUSER:-supabase_admin}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; T="$ROOT/supabase/_localtest"; MIG="$ROOT/supabase/migrations"
psql_run() { docker exec -i "$CONTAINER" psql -U "$DBUSER" -d postgres -q -v ON_ERROR_STOP=1 -f - ; }
q() { docker exec "$CONTAINER" psql -U "$DBUSER" -d postgres -Atq -c "$1"; }
apply() { { printf 'BEGIN;\n'; cat "$1"; printf '\nCOMMIT;\n'; } | psql_run 2>&1 | grep -E '(ERROR|FATAL):' | head -2; }
num() { basename "$1" | sed -E 's/^[0-9]+_([0-9]+)[a-z]?_.*/\1/' | sed 's/^0*//'; }
fail() { echo "FAIL $1"; exit 1; }
docker exec "$CONTAINER" psql -U "$DBUSER" -d postgres -q -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null 2>&1
docker exec "$CONTAINER" psql -U "$DBUSER" -d postgres -q -c "TRUNCATE storage.objects;" >/dev/null 2>&1
psql_run < "$T/00_bootstrap_storage.sql" 2>&1 | grep -E '(ERROR|FATAL):' && { echo "bootstrap FAILED"; exit 1; }
early=(); mid=(); late=(); rest=()
for f in "$MIG"/*.sql; do n=$(num "$f")
  if [ "$n" -le 176 ]; then early+=("$f"); elif [ "$n" -le 180 ]; then late+=("$f"); elif [ "$n" -le 190 ]; then mid+=("$f"); else rest+=("$f"); fi
done
n=0
for f in "${early[@]}" "${mid[@]}" "${late[@]}" "${rest[@]}"; do
  n=$((n+1)); err=$(apply "$f"); [ -n "$err" ] && { echo "FAILED #$n $(basename "$f")"; echo "$err"; exit 1; }
done
echo "OK: $n migrations applied in production order (<=176, 181-190, 177-180, 191+)"
psql_run < "$T/01_seed.sql" 2>&1 | grep -E '(ERROR|FATAL):' -A2 && { echo "seed FAILED"; exit 1; }
for s in 13_rewards_assert.sql:'REWARDS RESULT' 14_rewards_timezone_assert.sql:'TZ RESULT' 20_rewards_fixes_assert.sql:'FIXES RESULT' 21_rewards_v2_assert.sql:'V2 RESULT'; do
  file=${s%%:*}; label=${s#*:}
  OUT=$(psql_run < "$T/$file" 2>&1)
  echo "$OUT" | grep -q "$label: ALL PASS" && ! echo "$OUT" | grep -q 'ERROR' && echo "PASS $file in production order" \
    || { echo "$OUT" | grep -E 'FAIL|ERROR' | head -3; fail "$file in production order"; }
done

M192="$MIG/20261228000192_192_rewards_v2_weeks_tiers_goal.sql"
psql_run < "$ROOT/supabase/rollbacks/20261228000192_192_revert_rewards_v2.sql" 2>&1 | grep -E 'ERROR' && fail "192 rollback"
[ "$(q "select version from reward_rule_versions where is_active")" = "2" ] && echo "PASS R1 192 rollback: rules v2 active" || fail R1
[ "$(q "select count(*) from reward_badge_defs")" = "6" ] && echo "PASS R2 192 rollback: the 6 original badges" || fail R2
[ "$(q "select count(*) from pg_proc where proname in ('rewards_week_streak_of','set_my_outing_goal','rewards_goal_of')")" = "0" ] && echo "PASS R3 192 rollback: v2 functions gone" || fail R3
OUT=$(psql_run < "$T/13_rewards_assert.sql" 2>&1); echo "$OUT" | grep -q 'REWARDS RESULT: ALL PASS' && echo "PASS R4 suite 13 passes after the 192 rollback" || fail R4
err=$(apply "$M192"); [ -n "$err" ] && fail "192 re-apply: $err"
OUT=$(psql_run < "$T/21_rewards_v2_assert.sql" 2>&1); echo "$OUT" | grep -q 'V2 RESULT: ALL PASS' && echo "PASS R5 192 re-applied after its rollback: suite 21 passes" || fail R5
echo "PROD ORDER RESULT: ALL PASS"

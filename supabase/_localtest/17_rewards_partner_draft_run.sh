#!/usr/bin/env bash
# LOCAL TEST HARNESS ONLY — throwaway container, NEVER production. Applies supabase/drafts/DRAFT_NOT_IN_CHAIN_*.sql
# INSIDE a transaction after the full migration chain, runs the assertions, and ROLLS BACK: the draft is never
# left applied. Use CONTAINER=banbe-pg3 (or your own throwaway container).
set -uo pipefail
CONTAINER=${CONTAINER:-banbe-pg}; DBUSER=${DBUSER:-supabase_admin}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; T="$ROOT/supabase/_localtest"; D="$ROOT/supabase/drafts"
"$T/13_rewards_run.sh" >/dev/null 2>&1 || { echo "13_rewards_run.sh failed — run it directly"; exit 1; }
RB=$(grep -vE '^(BEGIN|COMMIT);$' "$D/DRAFT_NOT_IN_CHAIN_sponsors_offers_redemptions_rollback.sql" | sed "s/'/''/g")
OUT=$( {
  printf 'BEGIN;\n'
  printf "SELECT set_config('t.get_md5', md5(pg_get_functiondef('public.get_my_rewards()'::regprocedure)), true), set_config('t.redeem_md5', md5(pg_get_functiondef('public.redeem_reward(text)'::regprocedure)), true), set_config('t.catalog_n', (SELECT count(*) FROM public.reward_catalog)::text, true);\n"
  cat "$D/DRAFT_NOT_IN_CHAIN_sponsors_offers_redemptions.sql"
  printf "SELECT set_config('t.rollback_sql', '%s', true);\n" "$RB"
  cat "$T/17_rewards_partner_draft_assert.sql"
  printf '\nROLLBACK;\n'
} | docker exec -i "$CONTAINER" psql -U "$DBUSER" -d postgres -q -v ON_ERROR_STOP=1 -f - 2>&1 )
echo "$OUT" | grep -E 'PASS|FAIL|ERROR|PARTNER DRAFT RESULT' | sed 's/^psql:<stdin>:[0-9]*: //'
# the draft must not have been left behind
LEFT=$(docker exec "$CONTAINER" psql -U "$DBUSER" -d postgres -Atc "select to_regclass('public.sponsors')")
[ -z "$LEFT" ] || { echo "ERROR: draft left applied"; exit 1; }
echo "$OUT" | grep -q 'PARTNER DRAFT RESULT: ALL PASS' && ! echo "$OUT" | grep -q 'ERROR'

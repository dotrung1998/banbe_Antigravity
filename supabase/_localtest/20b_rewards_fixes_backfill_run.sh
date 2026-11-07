#!/usr/bin/env bash
# LOCAL TEST HARNESS ONLY — never deployed, never touches a real project or .env.
# Migration 191 on EXISTING data: an event removed before 191 is reversed by the backfill; the rollback restores the
# old bodies without touching the ledger; re-applying 191 is a no-op for the data.
#   CONTAINER=banbe-pg ./supabase/_localtest/20b_rewards_fixes_backfill_run.sh
set -uo pipefail
CONTAINER=${CONTAINER:-banbe-pg}; DBUSER=${DBUSER:-supabase_admin}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; T="$ROOT/supabase/_localtest"
psql_run() { docker exec -i "$CONTAINER" psql -U "$DBUSER" -d postgres -q -v ON_ERROR_STOP=1 -f - ; }
q() { docker exec "$CONTAINER" psql -U "$DBUSER" -d postgres -Atq -c "$1"; }
apply() { { printf 'BEGIN;\n'; cat "$1"; printf '\nCOMMIT;\n'; } | psql_run 2>&1 | grep -E '(ERROR|FATAL):' | head -2; }
fail() { echo "FAIL $1"; exit 1; }
docker exec "$CONTAINER" psql -U "$DBUSER" -d postgres -q -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null 2>&1
docker exec "$CONTAINER" psql -U "$DBUSER" -d postgres -q -c "TRUNCATE storage.objects;" >/dev/null 2>&1
psql_run < "$T/00_bootstrap_storage.sql" 2>&1 | grep -E '(ERROR|FATAL):' && { echo "bootstrap FAILED"; exit 1; }
M191="$ROOT/supabase/migrations/20261228000191_191_rewards_fixes.sql"
for f in "$ROOT"/supabase/migrations/*.sql; do
  case "$(basename "$f")" in *_19[1-9]_*) continue;; esac
  err=$(apply "$f"); [ -n "$err" ] && { echo "FAILED $(basename "$f")"; echo "$err"; exit 1; }
done
psql_run < "$T/01_seed.sql" 2>&1 | grep -E '(ERROR|FATAL):' -A2 && { echo "seed FAILED"; exit 1; }

# Before 191: a guest attends, the event ends, an admin removes it -> the guest keeps 20 coins (the bug).
psql_run 2>&1 >/dev/null <<'SQL' | grep -E 'ERROR' && fail "fixture"
INSERT INTO auth.users (id,email,phone,phone_confirmed_at,confirmed_at) VALUES ('7f0b0001-0000-4000-8000-000000000001','rfb@test.dev','+84900030001',now(),now()) ON CONFLICT (id) DO NOTHING;
INSERT INTO profiles (id,display_name,handle,role,phone,phone_verified) VALUES ('7f0b0001-0000-4000-8000-000000000001','rfb','u7fb01','participant','+84900030001',true) ON CONFLICT (id) DO NOTHING;
INSERT INTO account_phone_grandfathered(user_id,cohort) VALUES ('7f0b0001-0000-4000-8000-000000000001','t') ON CONFLICT DO NOTHING;
INSERT INTO events (id,key,name,organizer_id,status,price_vnd,capacity,starts_at,seats_remaining,cat_key)
VALUES ('rfb_ev','rfb_ev','Backfill','test_org_a','live',0,50,now(),50,'music');
INSERT INTO bookings (id,event_id,user_id,purchaser_id,qty,total_vnd,code,status,payment_state,paid_marked_at)
VALUES ('7f0bb001-0000-4000-8000-000000000001','rfb_ev','7f0b0001-0000-4000-8000-000000000001','7f0b0001-0000-4000-8000-000000000001',1,0,'RFB-1','confirmed','confirmed',now());
SELECT set_config('request.jwt.claim.sub','7a000002-0000-4000-8000-000000000002',false);
SELECT public.check_in_guest('7f0bb001-0000-4000-8000-000000000001','manual');
SELECT set_config('app.event_removal_allowed','1',false);
UPDATE events SET status='ended' WHERE id='rfb_ev';
UPDATE events SET status='removed', removed_at=now() WHERE id='rfb_ev';
SQL
U=7f0b0001-0000-4000-8000-000000000001
[ "$(q "select public.rewards_balance('$U')")" = "20" ] && echo "PASS B0 before 191: the removed event still pays 20 (the bug)" || fail "B0 fixture"
LEDGER_BEFORE=$(q "select count(*) from reward_ledger")

err=$(apply "$M191"); [ -n "$err" ] && fail "191 apply: $err"
[ "$(q "select public.rewards_balance('$U')")" = "0" ] && echo "PASS B1 the 191 backfill reverses it" || fail "B1 backfill"
[ "$(q "select count(*) from reward_ledger")" = "$((LEDGER_BEFORE + 1))" ] && echo "PASS B2 exactly one row added (the reversal), nothing deleted" || fail "B2 ledger rows"
[ "$(q "select valid from reward_attendances where user_id='$U'")" = "f" ] && echo "PASS B3 attendance invalid" || fail "B3"

err=$(apply "$M191"); [ -n "$err" ] && fail "191 re-apply: $err"
[ "$(q "select count(*) from reward_ledger")" = "$((LEDGER_BEFORE + 1))" ] && echo "PASS B4 re-applying 191 writes nothing" || fail "B4"

psql_run < "$ROOT/supabase/rollbacks/20261228000191_191_revert_rewards_fixes.sql" 2>&1 | grep -E 'ERROR' && fail "rollback"
[ "$(q "select version from reward_rule_versions where is_active")" = "1" ] && echo "PASS B5 rollback: rules v1 active again" || fail "B5"
[ "$(q "select has_function_privilege('authenticated','public.check_in(text, boolean)','EXECUTE')")" = "t" ] && echo "PASS B6 rollback: legacy check_in re-granted" || fail "B6"
[ "$(q "select count(*) from reward_ledger")" = "$((LEDGER_BEFORE + 1))" ] && [ "$(q "select public.rewards_balance('$U')")" = "0" ] \
  && echo "PASS B7 rollback keeps the ledger" || fail "B7"
[ "$(q "select count(*) from pg_proc where proname='rewards_flag'")" = "0" ] && echo "PASS B8 rollback drops the helper" || fail "B8"
err=$(apply "$M191"); [ -n "$err" ] && fail "191 after rollback: $err"
[ "$(q "select version from reward_rule_versions where is_active")" = "2" ] && echo "PASS B9 191 applies again after its rollback" || fail "B9"
echo "BACKFILL RESULT: ALL PASS"

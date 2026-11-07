#!/usr/bin/env bash
# LOCAL TEST HARNESS ONLY. Needs the chain applied (13_rewards_run.sh). Fires 12 simultaneous
# redeem_reward() calls for ONE account holding 100 coins (comet=40, lantern=80, crown=120):
# the balance must never go negative, no item may be charged twice, and exactly the items that
# were unlocked must have been charged.
set -uo pipefail
C=${CONTAINER:-banbe-pg}; U=${DBUSER:-supabase_admin}
U1='7e0b0001-0000-4000-8000-000000000001'
q() { docker exec -i "$C" psql -U "$U" -d postgres -q -At -v ON_ERROR_STOP=1 -c "$1"; }
q "DELETE FROM auth.users WHERE id='$U1'" >/dev/null 2>&1
q "INSERT INTO auth.users (id,email,phone,phone_confirmed_at,raw_user_meta_data,confirmed_at) VALUES ('$U1','cc@test.dev','+84900099001',now(),'{\"display_name\":\"cc\"}',now()) ON CONFLICT DO NOTHING;
   INSERT INTO profiles (id,display_name,handle,role,phone,phone_verified) VALUES ('$U1','cc','ucc001','participant','+84900099001',true) ON CONFLICT DO NOTHING;
   INSERT INTO account_phone_grandfathered(user_id,cohort) VALUES ('$U1','t') ON CONFLICT DO NOTHING;
   SELECT rewards_add_entry('$U1','award',100,'t:seed',NULL,'seed','{}');" >/dev/null
items=(rwd-comet rwd-lantern rwd-comet rwd-lantern rwd-crown rwd-comet rwd-lantern rwd-comet rwd-lantern rwd-crown rwd-comet rwd-lantern)
tmp=$(mktemp -d)
i=0
for it in "${items[@]}"; do
  i=$((i+1))
  ( docker exec -i "$C" psql -U "$U" -d postgres -q -At -c "SELECT set_config('request.jwt.claim.sub','$U1',false); SELECT redeem_reward('$it');" > "$tmp/$i.out" 2>&1 ) &
done
wait
ok=$(cat "$tmp"/*.out | grep -c '"success": true')
bal=$(q "SELECT rewards_balance('$U1')")
unl=$(q "SELECT count(*) FROM reward_unlocks WHERE user_id='$U1'")
charged=$(q "SELECT count(*) FROM reward_ledger WHERE user_id='$U1' AND entry_type='redemption'")
paid=$(q "SELECT COALESCE(sum(-amount),0) FROM reward_ledger WHERE user_id='$U1' AND entry_type='redemption'")
price=$(q "SELECT COALESCE(sum(c.price),0) FROM reward_unlocks u JOIN reward_catalog c ON c.code=u.item_code WHERE u.user_id='$U1'")
echo "balance=$bal unlocks=$unl redemption_entries=$charged charged=$paid prices_of_unlocks=$price successes=$ok"
q "DELETE FROM auth.users WHERE id='$U1'" >/dev/null 2>&1   # cleanup (ledger rows cascade with the account)
rm -rf "$tmp"
if [ "$bal" -ge 0 ] && [ "$unl" -eq "$charged" ] && [ "$paid" -eq "$price" ] && [ $((100-paid)) -eq "$bal" ]; then
  echo "CONCURRENT REDEEM RESULT: ALL PASS"; exit 0
fi
echo "CONCURRENT REDEEM RESULT: FAIL"; exit 1

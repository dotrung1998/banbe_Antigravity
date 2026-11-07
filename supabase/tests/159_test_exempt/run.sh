#!/usr/bin/env bash
# Isolated tests for migration 159 (+ rollback 160) against a THROWAWAY local
# Postgres with a stubbed Supabase `auth` schema. Touches no real project.
set -euo pipefail
cd "$(dirname "$0")"
M=../../migrations
docker rm -f gate159 >/dev/null 2>&1 || true
docker run --rm -d --name gate159 -e POSTGRES_PASSWORD=x postgres:15 >/dev/null
trap 'docker rm -f gate159 >/dev/null 2>&1 || true' EXIT
for i in $(seq 1 30); do docker exec gate159 pg_isready -U postgres >/dev/null 2>&1 && break; sleep 1; done
sleep 2
psql_() { docker exec -i gate159 psql -U postgres -v ON_ERROR_STOP=1 "$@"; }
psql_ -q < ../123_gate/00_stub_supabase.sql
psql_ -q -c "alter role service_role bypassrls"  # real Supabase service_role bypasses RLS
psql_ -q < $M/20261104000123_123_phone_dob_gate_and_promo_consent.sql >/dev/null 2>/tmp/gate159_123.err || { cat /tmp/gate159_123.err; exit 1; }
psql_ -q < $M/20261105000124_124_dob_confirm_email_code_only.sql >/dev/null
echo "--- apply 159 (twice: idempotent)"
psql_ -q < $M/20261208000159_159_phone_test_exemption.sql
psql_ -q < $M/20261208000159_159_phone_test_exemption.sql
psql_ -q -t -A < 10_exempt.sql 2>&1 | grep -v '^{"sub"'
docker cp $M/20261209000161_161_admin_phone_exempt_search.sql gate159:/tmp/161.sql
psql_ -q -t -A < 15_admin.sql 2>&1 | grep -v "^{\"sub\""
echo "--- apply rollback 160"
psql_ -q < ../../rollbacks/20261208000160_160_revert_phone_test_exemption.sql
psql_ -q -t -A < 20_rollback.sql 2>&1 | grep -v '^{"sub"'
echo "--- 159 patch must ABORT if a fragment is missing (simulated drift)"
psql_ -q -c "create or replace function public.set_date_of_birth(p_dob date) returns jsonb language sql as \$\$ select '{}'::jsonb \$\$;"
if psql_ -q < $M/20261208000159_159_phone_test_exemption.sql >/dev/null 2>&1; then echo "FAIL: did not abort"; exit 1; else echo "ok: aborted on drift"; fi

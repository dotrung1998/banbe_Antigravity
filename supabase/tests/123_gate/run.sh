#!/usr/bin/env bash
# Focused server-side tests for migration 123 against a THROWAWAY local
# Postgres with a stubbed Supabase `auth` schema. Touches no real project.
set -euo pipefail
cd "$(dirname "$0")"
docker rm -f gate123 >/dev/null 2>&1 || true
docker run --rm -d --name gate123 -e POSTGRES_PASSWORD=x postgres:15 >/dev/null
trap 'docker rm -f gate123 >/dev/null 2>&1 || true' EXIT
sleep 6
psql_() { docker exec -i gate123 psql -U postgres -v ON_ERROR_STOP=1 "$@"; }
psql_ -q < 00_stub_supabase.sql
psql_ -q < ../../migrations/20261104000123_123_phone_dob_gate_and_promo_consent.sql >/dev/null 2>&1
psql_ -q -t -A < 10_gate_and_lockout.sql 2>&1 | grep -v '^{"sub"'
psql_ -q -t -A < 20_enrollment_and_promo.sql 2>&1 | grep -v '^{"sub"'
echo "--- seed read-back (booleans only)"; psql_ -t -A < readback_seeds.sql

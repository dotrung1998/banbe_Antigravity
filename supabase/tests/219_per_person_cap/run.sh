#!/usr/bin/env bash
# Migration 219 (6 tickets per person per event across bookings, claim_seats as a wrapper) on the THROWAWAY stack
# (../gate_e2e). Touches nothing remote. Reuses the 210 seed (event pj_main, its accounts).
set -euo pipefail
cd "$(dirname "$0")"
if ! docker ps --format '{{.Names}}' | grep -qx g-db; then
  ../gate_e2e/stack_up.sh
  ../gate_e2e/apply_migrations.sh
fi
psql_() { docker exec -i g-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q "$@"; }
psql_ < ../210_project/00_reset.sql >/dev/null
psql_ < ../210_project/10_seed.sql >/dev/null
python3 test_cap.py

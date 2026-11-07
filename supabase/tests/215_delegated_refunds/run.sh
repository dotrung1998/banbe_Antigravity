#!/usr/bin/env bash
# Migration 215 (delegated refunds, note 76 phase 9c) on the THROWAWAY real-Supabase stack (../gate_e2e). Touches nothing
# remote. Reuses the 210 seed; bookings, refund claims, dispute threads and storage objects are added inside each rolled-back transaction.
set -euo pipefail
cd "$(dirname "$0")"
if ! docker ps --format '{{.Names}}' | grep -qx g-db; then
  ../gate_e2e/stack_up.sh
  ../gate_e2e/apply_migrations.sh
fi
psql_() { docker exec -i g-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q "$@"; }
psql_ < ../210_project/00_reset.sql >/dev/null
psql_ < ../210_project/10_seed.sql >/dev/null
python3 test_refunds.py

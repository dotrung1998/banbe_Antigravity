#!/usr/bin/env bash
# Migration 210 (Event Project Hub core, note 76) on the THROWAWAY real-Supabase stack (../gate_e2e). Touches nothing
# remote. Starts the stack and applies the full migration chain (which includes 210) only if g-db is not running.
set -euo pipefail
cd "$(dirname "$0")"
if ! docker ps --format '{{.Names}}' | grep -qx g-db; then
  ../gate_e2e/stack_up.sh
  ../gate_e2e/apply_migrations.sh
fi
psql_() { docker exec -i g-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q "$@"; }
psql_ < 00_reset.sql >/dev/null
psql_ < 10_seed.sql >/dev/null
python3 test_project.py

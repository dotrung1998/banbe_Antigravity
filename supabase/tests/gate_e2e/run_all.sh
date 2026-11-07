#!/usr/bin/env bash
# Fresh real-Supabase stack -> full migration chain (001..latest) -> assertions.
set -euo pipefail
cd "$(dirname "$0")"
./stack_up.sh
./apply_migrations.sh
sleep 3   # let PostgREST pick up the pre-request hook role setting
python3 test_gate.py
node test_api_gate.mjs

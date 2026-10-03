#!/usr/bin/env bash
# Applies the repo's full migration chain (real application schema) to the
# throwaway stack, as supabase_admin, in filename order. Fails loudly.
set -uo pipefail
cd "$(dirname "$0")/../../migrations"
fails=0
for f in $(ls *.sql | sort); do
  out=$(docker exec -i g-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q < "$f" 2>&1 >/dev/null | grep -E "ERROR|FATAL" | head -2)
  if [ -n "$out" ]; then echo "FAIL $f: $out"; fails=$((fails+1)); fi
done
echo "migration files failed: $fails"
exit $fails

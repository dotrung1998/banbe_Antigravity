#!/usr/bin/env bash
# Run Playwright against the ISOLATED local stack only.
#   scripts/e2e-local/run.sh <label> <focused|r2> [playwright args...]
# focused = the existing app specs listed in focused-specs.txt, R2 flags OFF (legacy behaviour)
# r2      = specs/*.spec.mjs with the REAL /api/media handlers + local S3 emulator, R2 flags ON
# Prereqs: stack.sh up (and s3.sh up for r2). Refuses to run if any target is not loopback/local.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LABEL=${1:?label}; MODE=${2:?focused|r2}; shift 2
export E2E_REPO="${E2E_REPO:-$ROOT}" E2E_LABEL=$LABEL
export E2E_OUT_DIR="${E2E_OUT_DIR:-${TMPDIR:-/tmp}/banbe-e2e-out}"; mkdir -p "$E2E_OUT_DIR"
export E2E_STORAGE_STATE="$E2E_OUT_DIR/auth-state-$LABEL.json"      # never inside the repo
KEYS=$("$HERE/stack.sh" env) || { echo "local stack not running: $HERE/stack.sh up"; exit 2; }
get() { echo "$KEYS" | grep "^$1=" | sed -E 's/^[^=]+="(.*)"$/\1/'; }
export SUPABASE_URL=http://127.0.0.1:55321 VITE_SUPABASE_URL=http://127.0.0.1:55321
export SUPABASE_SERVICE_ROLE_KEY=$(get SERVICE_ROLE_KEY) VITE_SUPABASE_ANON_KEY=$(get ANON_KEY) SUPABASE_ANON_KEY=$(get ANON_KEY)
# loadEnv only fills keys that are ABSENT from process.env, so setting these empty blocks .env.local's real values.
for k in GMAIL_USER GMAIL_APP_PASSWORD BANK_WEBHOOK_SECRET CASSO_WEBHOOK_SECRET PAYOS_CHECKSUM_KEY TELEGRAM_BOT_TOKEN TELEGRAM_WEBHOOK_SECRET SMS_PROVIDER_URL SMS_PROVIDER_KEY ZALO_OA_TOKEN WALLET_AUTH_SECRET; do export $k=; done
if [ "$MODE" = r2 ]; then
  export R2_ACCOUNT_ID=local R2_ACCESS_KEY_ID=banbe-e2e-local R2_SECRET_ACCESS_KEY=banbe-e2e-local-secret R2_ENDPOINT=http://127.0.0.1:59000
  export R2_PUBLIC_BUCKET=banbe-media-public R2_STAGING_BUCKET=banbe-media-staging
  export MEDIA_PUBLIC_BASE_URL=http://127.0.0.1:59010 VITE_MEDIA_PUBLIC_BASE_URL=http://127.0.0.1:59010 VITE_MEDIA_R2_READS=${VITE_MEDIA_R2_READS:-1}
  export MEDIA_R2_UPLOADS=${MEDIA_R2_UPLOADS:-on} CLOUDFLARE_API_BASE=http://127.0.0.1:59100 CLOUDFLARE_ZONE_ID=local-zone CLOUDFLARE_PURGE_TOKEN=local-purge-token CRON_SECRET=local-cron-secret
  PROJECT=r2
else
  export CRON_SECRET= ; PROJECT=focused; [ "$MODE" = diag ] && PROJECT=diag
fi
node -e "import('$HERE/guard.mjs').then(m=>m.assertIsolated())" || exit 3
node "$HERE/scan-specs.mjs" || exit 3
# Socket-level guard in EVERY node process (runner, workers, web servers): non-loopback connections throw.
export NODE_OPTIONS="--require $HERE/net-guard.cjs ${NODE_OPTIONS:-}"
node --require "$HERE/net-guard.cjs" "$HERE/net-guard.selftest.cjs" >/dev/null || { echo "net-guard self-test failed"; exit 3; }
cd "$ROOT" && PROJECTS=(--project=$PROJECT); [ "$MODE" = focused ] && PROJECTS+=(--project=focused-copies)
exec ./node_modules/.bin/playwright test -c "$HERE/playwright.local.config.mjs" "${PROJECTS[@]}" "$@"

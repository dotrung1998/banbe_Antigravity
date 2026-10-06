#!/usr/bin/env bash
# Run any command with the isolated local environment + the socket-level network guard.
#   scripts/e2e-local/with-env.sh node scripts/e2e-local/privacy-gaps.mjs after
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS=$("$HERE/stack.sh" env) || { echo "local stack not running"; exit 2; }
get() { echo "$KEYS" | grep "^$1=" | sed -E 's/^[^=]+="(.*)"$/\1/'; }
export SUPABASE_URL=http://127.0.0.1:55321 VITE_SUPABASE_URL=http://127.0.0.1:55321
export SUPABASE_SERVICE_ROLE_KEY=$(get SERVICE_ROLE_KEY) VITE_SUPABASE_ANON_KEY=$(get ANON_KEY) SUPABASE_ANON_KEY=$(get ANON_KEY)
for k in GMAIL_USER GMAIL_APP_PASSWORD BANK_WEBHOOK_SECRET CASSO_WEBHOOK_SECRET PAYOS_CHECKSUM_KEY TELEGRAM_BOT_TOKEN TELEGRAM_WEBHOOK_SECRET SMS_PROVIDER_URL SMS_PROVIDER_KEY ZALO_OA_TOKEN WALLET_AUTH_SECRET; do export $k=; done
if [ "${E2E_WITH_R2:-}" = 1 ]; then
  export R2_ACCOUNT_ID=local R2_ACCESS_KEY_ID=banbe-e2e-local R2_SECRET_ACCESS_KEY=banbe-e2e-local-secret R2_ENDPOINT=http://127.0.0.1:59000
  export R2_PUBLIC_BUCKET=banbe-media-public R2_STAGING_BUCKET=banbe-media-staging MEDIA_PUBLIC_BASE_URL=http://127.0.0.1:59010 MEDIA_R2_UPLOADS=on
  export CLOUDFLARE_API_BASE=http://127.0.0.1:59100 CLOUDFLARE_ZONE_ID=local-zone CLOUDFLARE_PURGE_TOKEN=local-purge-token CRON_SECRET=local-cron-secret
fi
node -e "import('$HERE/guard.mjs').then(m=>m.assertIsolated())" || exit 3
export NODE_OPTIONS="--require $HERE/net-guard.cjs ${NODE_OPTIONS:-}"
exec "$@"

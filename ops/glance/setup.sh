#!/usr/bin/env bash
# Create ops/glance/.env once: auth secret, password hash, GitHub token, Quartz URLs.
# Never prints a secret; the password goes to the Keychain (service banbe-glance).
set -euo pipefail
cd "$(dirname "$0")"

if [ -f .env ]; then
  echo ".env exists — leaving it untouched"
  exit 0
fi

PW=$(openssl rand -base64 18)
SECRET=$(docker run --rm glanceapp/glance secret:make | tr -d '[:space:]')
HASH=$(docker run --rm glanceapp/glance password:hash "$PW" | tr -d '\r\n')
TOKEN=${GITHUB_TOKEN:-$(gh auth token)}

case "$SECRET" in ''|*[!A-Za-z0-9+/=]*) echo "unexpected secret output"; exit 1;; esac
case "$HASH" in \$2*) ;; *) echo "unexpected password:hash output"; exit 1;; esac
[ -n "$TOKEN" ] || { echo "no GitHub token: run gh auth login"; exit 1; }

umask 077
{
  printf 'GLANCE_SECRET=%s\n' "$SECRET"
  printf 'GLANCE_PASSWORD_HASH=%s\n' "$HASH"
  printf 'GITHUB_TOKEN=%s\n' "$TOKEN"
  printf 'QUARTZ_BANBE=%s\n' "${QUARTZ_BANBE:-}"
  printf 'QUARTZ_SPEZ=%s\n' "${QUARTZ_SPEZ:-}"
  printf 'QUARTZ_VIS=%s\n' "${QUARTZ_VIS:-}"
} > .env
chmod 600 .env

security add-generic-password -a "$USER" -s banbe-glance -w "$PW" -U >/dev/null
printf 'saved: security find-generic-password -s banbe-glance -w\n'

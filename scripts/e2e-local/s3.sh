#!/usr/bin/env bash
# Local S3-compatible server (Versity S3 Gateway, validates SigV4) standing in for R2. NOT R2.
#   scripts/e2e-local/s3.sh up|down   (127.0.0.1:59000, ephemeral storage, fixed local-only credentials)
set -euo pipefail
case "${1:-}" in
  up)
    docker rm -f banbe-e2e-s3 >/dev/null 2>&1 || true
    docker run -d --name banbe-e2e-s3 -p 127.0.0.1:59000:7070 --tmpfs /data \
      -e ROOT_ACCESS_KEY_ID=banbe-e2e-local -e ROOT_SECRET_ACCESS_KEY=banbe-e2e-local-secret \
      -e VGW_REGION=auto -e VGW_CORS_ALLOW_ORIGIN=http://localhost:5199 \
      versity/versitygw:latest posix /data >/dev/null
    for _ in $(seq 1 20); do curl -s -o /dev/null http://127.0.0.1:59000/ && break; sleep 0.5; done
    node "$(dirname "${BASH_SOURCE[0]}")/create-buckets.mjs" ;;
  down) docker rm -f banbe-e2e-s3 >/dev/null 2>&1 || true ;;
  *) echo "usage: $0 up|down"; exit 2 ;;
esac

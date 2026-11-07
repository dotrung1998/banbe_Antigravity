#!/usr/bin/env bash
# Throwaway REAL Supabase stack (supabase/postgres + GoTrue + PostgREST +
# storage-api + mailpit) for the gate tests. Touches nothing remote.
set -euo pipefail
JWT_SECRET="super-secret-jwt-token-with-at-least-32-characters-long"
PW="postgres"
NET=gate-e2e
docker rm -f g-db g-auth g-rest g-storage g-mail >/dev/null 2>&1 || true
docker network rm $NET >/dev/null 2>&1 || true
docker network create $NET >/dev/null
docker run -d --name g-db --network $NET -p 54329:5432 \
  -e POSTGRES_PASSWORD=$PW -e JWT_SECRET=$JWT_SECRET \
  public.ecr.aws/supabase/postgres:17.6.1.166 >/dev/null
echo "waiting for postgres..."
for i in $(seq 1 60); do
  docker exec g-db pg_isready -U supabase_admin -h localhost >/dev/null 2>&1 && break; sleep 2
done
docker exec g-db psql -U supabase_admin -d postgres -q -c "alter role supabase_auth_admin with password '$PW'; alter role authenticator with password '$PW'; alter role supabase_storage_admin with password '$PW';"
docker run -d --name g-mail --network $NET -p 54325:8025 public.ecr.aws/supabase/mailpit:v1.30.2 >/dev/null
docker run -d --name g-auth --network $NET -p 54399:9999 --add-host host.docker.internal:host-gateway \
  -e GOTRUE_API_HOST=0.0.0.0 -e GOTRUE_API_PORT=9999 -e API_EXTERNAL_URL=http://localhost:54399 \
  -e GOTRUE_DB_DRIVER=postgres -e GOTRUE_DB_DATABASE_URL="postgres://supabase_auth_admin:$PW@g-db:5432/postgres" \
  -e GOTRUE_SITE_URL=http://localhost -e GOTRUE_JWT_SECRET=$JWT_SECRET -e GOTRUE_JWT_EXP=3600 -e GOTRUE_JWT_DEFAULT_GROUP_NAME=authenticated -e GOTRUE_JWT_ADMIN_ROLES=service_role -e GOTRUE_JWT_AUD=authenticated \
  -e GOTRUE_DISABLE_SIGNUP=false -e GOTRUE_EXTERNAL_EMAIL_ENABLED=true -e GOTRUE_MAILER_AUTOCONFIRM=true \
  -e GOTRUE_MAILER_TEMPLATES_MAGIC_LINK=http://host.docker.internal:54390/magic.html -e GOTRUE_SMTP_MAX_FREQUENCY=1s -e GOTRUE_SMTP_HOST=g-mail -e GOTRUE_SMTP_PORT=1025 -e GOTRUE_SMTP_ADMIN_EMAIL=t@example.com \
  -e GOTRUE_EXTERNAL_PHONE_ENABLED=true -e GOTRUE_SMS_AUTOCONFIRM=false -e GOTRUE_SMS_PROVIDER=twilio \
  -e GOTRUE_SMS_TWILIO_ACCOUNT_SID=ACfake -e GOTRUE_SMS_TWILIO_AUTH_TOKEN=fake -e GOTRUE_SMS_TWILIO_MESSAGE_SERVICE_SID=MGfake \
  -e GOTRUE_SMS_TEST_OTP=+14155550101:123456,+14155550102:123456 -e GOTRUE_SMS_MAX_FREQUENCY=1s \
  -e GOTRUE_RATE_LIMIT_EMAIL_SENT=1000 -e GOTRUE_RATE_LIMIT_SMS_SENT=1000 \
  public.ecr.aws/supabase/gotrue:v2.196.0 >/dev/null
echo "waiting for gotrue migrations..."
for i in $(seq 1 60); do curl -sf http://localhost:54399/health >/dev/null 2>&1 && break; sleep 2; done
docker run -d --name g-storage --network $NET -p 54398:5000 \
  -e ANON_KEY=x -e SERVICE_KEY=x -e AUTH_JWT_SECRET=$JWT_SECRET -e PGRST_JWT_SECRET=$JWT_SECRET \
  -e DATABASE_URL="postgres://supabase_storage_admin:$PW@g-db:5432/postgres" -e DB_INSTALL_ROLES=false \
  -e STORAGE_BACKEND=file -e FILE_STORAGE_BACKEND_PATH=/tmp/storage -e TENANT_ID=stub -e REGION=local \
  -e GLOBAL_S3_BUCKET=stub -e IS_MULTITENANT=false -e POSTGREST_URL=http://g-rest:3000 \
  -e UPLOAD_FILE_SIZE_LIMIT=52428800 -e ENABLE_IMAGE_TRANSFORMATION=false \
  public.ecr.aws/supabase/storage-api:v1.73.1 >/dev/null
echo "waiting for storage migrations..."
for i in $(seq 1 60); do
  docker exec g-db psql -U supabase_admin -d postgres -Atc "select to_regclass('storage.objects') is not null" 2>/dev/null | grep -q t && break; sleep 2
done
for i in $(seq 1 60); do docker exec g-db psql -U supabase_admin -d postgres -Atc "select to_regclass('auth.sessions') is not null and to_regclass('auth.mfa_amr_claims') is not null" 2>/dev/null | grep -q t && break; sleep 2; done
docker run -d --name g-rest --network $NET -p 54300:3000 \
  -e PGRST_DB_URI="postgres://authenticator:$PW@g-db:5432/postgres" -e PGRST_DB_SCHEMAS=public -e PGRST_DB_ANON_ROLE=anon \
  -e PGRST_JWT_SECRET=$JWT_SECRET -e PGRST_SERVER_PORT=3000 public.ecr.aws/supabase/postgrest:v14.5 >/dev/null
echo "stack ready (db 54329, auth 54399, mail 54325)"

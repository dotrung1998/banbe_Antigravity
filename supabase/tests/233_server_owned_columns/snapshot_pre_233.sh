#!/usr/bin/env bash
# Read-only definition snapshot of every object migration 233 touches.
# Evidence for docs/runbooks/2026-11-21-security-production-apply.md §2.
#
# Each section runs as its OWN query on purpose: `supabase db query -f file`
# prints only the last result set of a multi-statement file, so a single .sql
# file would silently drop sections A-F. Touches nothing; no row data.
set -euo pipefail
cd "$(dirname "$0")/../../.."

q() {
  local label="$1" sql="$2"
  echo
  echo "== $label =="
  supabase db query --linked "$sql" 2>/dev/null \
    | grep -v -E 'Initialising login role|new version of Supabase CLI|We recommend updating' \
    || true
}

echo "Definition snapshot — production (read-only). Taken $(date -u +%Y-%m-%dT%H:%M:%SZ). No row data, no secrets."

q "A. guard functions of 233 (expect none before the migration)" \
  "select p.proname, pg_get_function_identity_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('profiles_guard_client_write','organizers_guard_client_write','messages_guard_client_insert') order by 1;"

q "B. every trigger on profiles / organizers / messages" \
  "select tgrelid::regclass::text tbl, tgname, pg_get_triggerdef(t.oid) def from pg_trigger t where not tgisinternal and tgrelid in ('public.profiles'::regclass,'public.organizers'::regclass,'public.messages'::regclass) order by tbl, tgname;"

q "C. functions 233 calls (must exist with these signatures)" \
  "select p.proname, pg_get_function_identity_arguments(p.oid) args, p.prosecdef as security_definer, has_function_privilege('authenticated', p.oid, 'EXECUTE') auth_execute from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('generate_referral_code','sanitize_social_links') order by 1;"

q "D. table-level grants" \
  "select grantee, table_name, string_agg(privilege_type, ',' order by privilege_type) privs from information_schema.role_table_grants where table_schema='public' and table_name in ('messages','profiles','organizers') and grantee in ('authenticated','anon') group by 1,2 order by 2,1;"

q "E. column UPDATE grants on messages" \
  "select grantee, column_name, privilege_type from information_schema.column_privileges where table_schema='public' and table_name='messages' and privilege_type='UPDATE' and grantee in ('authenticated','anon') order by 1,2;"

q "F. column types 233 depends on" \
  "select table_name, column_name, data_type, udt_name from information_schema.columns where table_schema='public' and ((table_name='messages' and column_name in ('kind','read_at','body','sender_id')) or (table_name='profiles' and column_name in ('social_links','referral_code','referred_by','can_manage_admins','phone_verified','attended_count','no_show_count','created_at','role')) or (table_name='organizers' and column_name in ('social_links','verified','disputes_open'))) order by table_name, column_name;"

q "G. row counts and current badge/privilege spread" \
  "select (select count(*) from public.profiles) profiles, (select count(*) from public.organizers) organizers, (select count(*) from public.messages) messages, (select count(*) from public.profiles where can_manage_admins) admins_with_team_perm, (select count(*) from public.profiles where phone_verified) phone_verified, (select count(*) from public.organizers where verified) organizers_verified, (select count(*) from public.organizers where disputes_open > 0) organizers_with_open_disputes;"

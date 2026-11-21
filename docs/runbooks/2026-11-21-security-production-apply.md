# Production apply — security audit 2026-11-21 (migration 233)

Project `ukchdgdnwytretvqjjqu` (BanBe, West EU Ireland), linked with Supabase CLI 2.121.0.
Repo `/Users/thetrungdo/Downloads/banbe`, branch `main`, HEAD `fc5125ce` at preflight.
Source of the change: `docs/security/2026-11-21-audit.md` (findings H-1…H-9, §6 owner steps).

**Preflight ran on 2026-11-21 and the apply was authorized and executed later the same day.**
§3–§5 below were run for real: the *Result* columns and §9 record the actual output. The only
production writes were migration 233 and the throwaway test fixtures in §5, which were deleted
again (§5.3).

## Status

| Item | Local | Remote (2026-11-21) | Status |
|---|---|---|---|
| `20261231000233_233_server_owned_columns_guard.sql` | present, untracked | **`20261231000233`** | **applied 2026-11-21** |
| `20261231000233_233_revert_server_owned_columns_guard.sql` | present, tested | — | ready |
| SQL proof `supabase/tests/233_server_owned_columns/` | **14/14** re-run 2026-11-21 | throwaway `g-db` only | green |
| Definition snapshot | `docs/audits/2026-11-21-security/production-snapshot-pre-233-2026-11-21.txt` | taken from production | done |
| Dry run (182/183/184 held) | lists **exactly one** migration (233) | — | green |
| Payload verification | 6 payloads + 2 smoke, all as designed | run 2026-11-21 | **green (§5.2)** |
| Authorization | — | — | **given by owner, 2026-11-21** |

Pending migrations before the run: `182`, `183`, `184` (deliberately held), `233` (this one).
The last applied remote version is `20261231000232`. `201`, `202`, `207` and `221` are already
applied remotely — earlier notes that called them pending are stale.

## 0. Why 233 is safe for the live clients (write-path inventory)

233 adds BEFORE triggers on `profiles`/`organizers` and swaps table-wide UPDATE on `messages`
for `UPDATE (read_at)` only. Every client write the apps actually make was checked against it:

| Path | What it writes | After 233 |
|---|---|---|
| `src/state/BanBeContext.jsx:9674` | `messages.update({ read_at })` | still allowed (column grant) |
| web + iOS message send | direct `INSERT` into `messages` | still allowed; `kind` defaults to `text` and the guard pins it |
| `apps/ios/BanBeApp/State/AppState+Data.swift:3911` | direct `INSERT` into `messages` | same |
| system/notice messages | 15 SECURITY DEFINER RPCs (e.g. `hold_seats`, `verify_payment`, `resolve_dispute`) | unaffected — they run as the owner, not as `authenticated` |
| profile saves | `save_profile` RPC (definer); iOS consent/prefs updates (`policy_accepted_at`, `auto_email_documents`, `locale`, `theme`) | unaffected |
| profile direct update (web) | `muted_notification_kinds` only | unaffected (not a pinned column) |
| phone verification | `verify_phone_otp`, `sync_phone_verification` (both definer) | unaffected |
| organizer writes | `update_organizer_profile` RPC (definer); no direct client INSERT/UPDATE exists | unaffected |
| `goc_flag_overdue_refunds` | `organizers.disputes_open`; the function is **invoker** | unaffected: only `pg_cron` calls it, as the job owner; no client call site |

Dependency checks run against production on 2026-11-21:

- `public.sanitize_social_links(jsonb)` exists, is `IMMUTABLE`, and returns `'[]'` for `NULL`
  (`IF p_links IS NULL THEN RETURN '[]'`), so the new trigger cannot reject a client insert
  that simply has no links. Invalid links return `NULL` → `INVALID_SOCIAL_LINKS`, which is the
  same sanitizer `save_profile`/`update_organizer_profile` already call.
- `public.generate_referral_code()` exists with zero arguments and `authenticated` EXECUTE.
- `messages.kind` is the enum `message_kind` with labels `text` (1) and `system` (2), default
  `'text'::message_kind`; the trigger's `NEW.kind := 'text'` and `IS DISTINCT FROM 'text'`
  both coerce to that enum (proved on the throwaway stack, 14/14).
- No production function updates `public.messages` or `profiles.role` internally with invoker
  rights, so no server path is caught by the new guards.

## 1. Preconditions

```bash
cd /Users/thetrungdo/Downloads/banbe
supabase --version                 # 2.121.0 was used
supabase projects list             # must show ● on ukchdgdnwytretvqjjqu
supabase migration list --linked   # 182, 183, 184, 233 must be the only blank Remote rows
```

Observed 2026-11-21:

```text
● ukchdgdnwytretvqjjqu  BanBe  West EU (Ireland)     # linked
local-only: 20261222000182, 20261222000183, 20261222000184, 20261231000233
last remote version: 20261231000232
```

Stop if any migration other than `182/183/184/233` has a blank Remote cell — the dry run in §3
would then include it.

## 2. Backup and evidence snapshot

Data safety net: Supabase dashboard backups/PITR. The owner must confirm a restore point exists
shortly before the apply. 233 changes privileges, three triggers and three functions — **no
table is altered and no row is deleted** — so the rollback file is the primary undo, and the
dashboard backup only covers operator error.

Definition snapshot (already taken, read-only, reproducible):

```bash
bash supabase/tests/233_server_owned_columns/snapshot_pre_233.sh \
  > docs/audits/2026-11-21-security/production-snapshot-pre-233-2026-11-21.txt
```

The script runs **one query per section**. `supabase db query -f file` prints only the last
result set of a multi-statement file, so a single `.sql` file silently loses sections A–F.

The file records, before the change:

| Section | Content |
|---|---|
| A | guard functions of 233: none exist (empty result) |
| B | every trigger on `profiles`/`organizers`/`messages`: `on_profile_role_change`, `profiles_relocalize_notifications`, `organizers_guard_r2_ref`, `on_message_created` |
| C | `generate_referral_code()` and `sanitize_social_links(jsonb)` exist, `auth_execute = true` |
| D | table grants: `anon` + `authenticated` hold `DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE` on all three tables |
| E | column UPDATE grants on `messages`: **every** column, including `body`, `sender_id`, `kind` |
| F | column types: `messages.kind` = enum `message_kind`, `read_at` = timestamptz, `social_links` = jsonb |
| G | row counts: profiles 14, organizers 31, messages 48; `can_manage_admins` 2, `phone_verified` 3, `verified` 1, `disputes_open > 0` 7 |

One caveat worth keeping: do **not** wrap the migration file in your own `BEGIN;`/`COMMIT;` —
233 already contains its own transaction. Wrapping it produced
`WARNING: there is already a transaction in progress` and the trailing `ROLLBACK` silently did
nothing on the throwaway stack.

Optional R2 backup (`npm run backup:supabase`), only if the R2 backup variables are configured
on this machine: `R2_BACKUP_BUCKET`, `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`,
`R2_SECRET_ACCESS_KEY`. Names only — never print values. If they are not configured, skip it
and record "dashboard backup only".

## 3. Dry run, then apply

`db push` refuses to run while the older `182/183/184` are pending. Hold those three for the
duration; the trap always puts them back.

```bash
set -euo pipefail
cd /Users/thetrungdo/Downloads/banbe
hold=$(mktemp -d)
for f in \
  supabase/migrations/20261222000182_182_*.sql \
  supabase/migrations/20261222000183_183_*.sql \
  supabase/migrations/20261222000184_184_*.sql; do
  mv "$f" "$hold"/
done
trap 'mv "$hold"/*.sql supabase/migrations/; rmdir "$hold"' EXIT

supabase db push --linked --dry-run --skip-vault
supabase db push --linked --yes --skip-vault
```

Expected dry run (observed 2026-11-21, exit 0):

```text
DRY RUN: migrations will *not* be pushed to the database.
Skipping migration .DS_Store... (file name must match pattern "<timestamp>_name.sql")
Would push these migrations:
 • 20261231000233_233_server_owned_columns_guard.sql
Finished supabase db push.
```

If the list contains anything besides 233, stop and fix the hold list — do not push.

Expected push: `Applying migration 20261231000233_233_server_owned_columns_guard.sql…` then
`Finished supabase db push.`

Afterwards:

```bash
ls supabase/migrations/2026122200018{2,3,4}_*.sql   # all three back in place
git status --short                                  # no new changes beyond the pre-existing dirty tree
```

`--skip-vault` is used because this migration touches no Vault secret; it keeps the command
from syncing anything else.

## 4. Verify the applied schema (read-only)

```bash
# 4.1 the three guards exist
supabase db query --linked "select tgname, tgrelid::regclass::text tbl from pg_trigger where not tgisinternal and tgname in ('profiles_guard_client_write','organizers_guard_client_write','messages_guard_client_insert') order by 1;"

# 4.2 messages: table UPDATE gone, read_at still writable
supabase db query --linked "select has_table_privilege('authenticated','public.messages','UPDATE') auth_table_update, has_table_privilege('anon','public.messages','UPDATE') anon_table_update, has_column_privilege('authenticated','public.messages','read_at','UPDATE') auth_read_at_update, has_column_privilege('authenticated','public.messages','body','UPDATE') auth_body_update, has_any_column_privilege('authenticated','public.messages','UPDATE') auth_any_column_update;"

# 4.3 the migration is recorded
supabase db query --linked "select version from supabase_migrations.schema_migrations where version = '20261231000233';"

# 4.4 the functions are the ones just installed
supabase db query --linked "select proname, prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('profiles_guard_client_write','organizers_guard_client_write','messages_guard_client_insert') order by 1;"
```

Expected after apply (these exact values were produced on the throwaway stack `g-db`):

| Check | Expected |
|---|---|
| 4.1 | `messages_guard_client_insert`, `organizers_guard_client_write`, `profiles_guard_client_write` |
| 4.2 | `auth_table_update = false`, `anon_table_update = false`, `auth_read_at_update = true`, `auth_body_update = false`, `auth_any_column_update = true` |
| 4.3 | `20261231000233` |
| 4.4 | three rows, `prosecdef = false` (they are plain triggers, not definer) |

Observed on production 2026-11-21, matching every row above:

```text
4.1  messages_guard_client_insert (messages), organizers_guard_client_write (organizers), profiles_guard_client_write (profiles)
4.2  auth_table_update=false  anon_table_update=false  auth_read_at_update=true  auth_body_update=false  auth_any_column_update=true
4.3  20261231000233
4.4  three functions, prosecdef=false
4.5  profiles/organizers BEFORE INSERT OR UPDATE, messages BEFORE INSERT, FOR EACH ROW
```

`auth_any_column_update = true` is expected and correct: the column grant on `read_at` makes the
table report "some column is updatable". Do not read that as a failure of 4.2 — `body` is the
column that matters and it must be `false`.

## 5. Payload verification on production (live)

Fixtures: create **own** test accounts and **own** threads. Never touch another person's data.

### 5.1 Fixtures

```bash
set -euo pipefail
cd /Users/thetrungdo/Downloads/banbe
url=$(sed -n 's/^SUPABASE_URL=//p' .env.local | head -1 | tr -d '"')
anon=$(sed -n 's/^VITE_SUPABASE_ANON_KEY=//p' .env | head -1 | tr -d '"')
svc=$(sed -n 's/^SUPABASE_SERVICE_ROLE_KEY=//p' .env.local | head -1 | tr -d '"')
pw=$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | cut -c1-24)   # never print

mkuser() {  # $1 = email; fail loudly instead of yielding "null"
  local out id
  out=$(curl -s -X POST "$url/auth/v1/admin/users" \
    -H "apikey: $svc" -H "Authorization: Bearer $svc" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"$pw\",\"email_confirm\":true}")
  id=$(printf '%s' "$out" | jq -r '.id // empty')
  if [ -z "$id" ]; then echo "create user $1 failed: $out" >&2; return 1; fi
  printf '%s' "$id"
}
HOST_UID=$(mkuser sec233-host@banbe.test)
GUEST_UID=$(mkuser sec233-guest@banbe.test)
```

The `account_gate_required` policy on `profiles`/`messages` (DOB + phone) would otherwise block
these writes and make the test look "safe" for the wrong reason. Grandfather the two fixtures —
the same mechanism the throwaway proof uses:

```bash
supabase db query --linked "insert into public.account_phone_grandfathered (user_id, cohort) values ('$HOST_UID','sec233-payload'), ('$GUEST_UID','sec233-payload') on conflict do nothing;"
```

Organizer row for the host, and a two-person thread with one message from the host (service role
bypasses RLS; `threads.event_id` is nullable, so no event is needed):

```bash
supabase db query --linked "insert into public.organizers (id, owner_id, name) values ('sec233-org','$HOST_UID','sec233 host') on conflict (id) do nothing;"
supabase db query --linked "insert into public.threads (id, guest_id, organizer_id) values ('5ec23300-0000-4000-8000-000000000001','$GUEST_UID','sec233-org') on conflict (id) do nothing;"
supabase db query --linked "insert into public.messages (id, thread_id, sender_id, body) values ('5ec23300-0000-4000-8000-000000000002','5ec23300-0000-4000-8000-000000000001','$HOST_UID','original body') on conflict (id) do nothing;"
```

Two fixture caveats found while running this:

- `authenticated` has **no table-level SELECT** on `organizers` (223 moved it to column grants),
  so `Prefer: return=representation` on an organizers PATCH returns 403 on its own. That 403 is
  the representation read, not the guard: send the PATCH without the header (204) and read the
  row back with `db query`.
- A silent pin only counts with a positive control. Include one writable column in the same
  PATCH (`name` for organizers, `muted_notification_kinds` for profiles) and confirm it changed
  while the pinned columns did not.

Sign in the two accounts to get their own JWTs:

```bash
tok() { curl -s "$url/auth/v1/token?grant_type=password" -H "apikey: $anon" -H 'Content-Type: application/json' -d "{\"email\":\"$1\",\"password\":\"$pw\"}" | jq -r .access_token; }
HOST_JWT=$(tok sec233-host@banbe.test)
GUEST_JWT=$(tok sec233-guest@banbe.test)
```

### 5.2 The six checks

| # | Call | Expected | Result 2026-11-21 |
|---|---|---|---|
| 1 | host PATCH `/rest/v1/organizers?id=eq.sec233-org` `{"name":"sec233 host v2","verified":true,"disputes_open":42}` **without** `Prefer: return=representation`, then read the row | `204`; `name` changed, `verified` still `false`, `disputes_open` still `0` | **PASS** — `204`; `name = sec233 host v2`, `verified = false`, `disputes_open = 0` |
| 2 | owner PATCH of `profiles` `{"can_manage_admins":true,"phone_verified":true,"referral_code":"EVIL123","attended_count":99}` (set `role='admin', can_manage_admins=false` on the fixture first, via service role) | `200`, body keeps `false/false/<unchanged>/0` | **PASS** — `{role:"admin", can_manage_admins:false, phone_verified:false, referral_code:"XT8TD35", attended_count:0}` |
| 3 | guest `PATCH /rest/v1/messages?id=eq.5ec23300-…0002` `{"body":"rewritten"}` | **403** (`42501 permission denied`) | **PASS** — `403`, `{"code":"42501","message":"permission denied for table messages"}`; stored body still `original body` |
| 4 | guest `PATCH` the same message `{"read_at":"<now>"}` | `204`/`200`, and the stored `read_at` is set | **PASS** — `204`; `read_at is not null = true` |
| 5 | origin/wordmark: `curl -s https://www.banbe.app/api/photo-share -H 'Host: evil.example'` and read `og:url` | canonical `https://www.banbe.app…`, never `evil.example` | **PASS for reflection** — forged Host gets `403` at the edge (never reaches the function); the normal request renders `og:url = https://banbe-two.vercel.app/…`, see R-6 |
| 6 | referral href: `PATCH profiles {"referral_code":"x\" onmouseover=alert(1)"}` | stored code unchanged (DB pin); email render is unit-tested | **PASS** — stayed `XT8TD35` |

Commands for 1–4 and 6:

```bash
# 1. host self-verification is silently pinned. No `Prefer: return=representation`:
#    organizers has no table-level SELECT for authenticated (223 granted columns
#    only), so the representation read alone returns 403. The writable `name` is
#    the positive control that proves the same UPDATE did run.
curl -s -o /dev/null -w '%{http_code}\n' -X PATCH "$url/rest/v1/organizers?id=eq.sec233-org" \
  -H "apikey: $anon" -H "Authorization: Bearer $HOST_JWT" -H 'Content-Type: application/json' \
  -d '{"name":"sec233 host v2","verified":true,"disputes_open":42}'
supabase db query --linked "select name, verified, disputes_open from public.organizers where id='sec233-org';"

# 2. admin-team flag; make the fixture a real admin without the permission first
supabase db query --linked "update public.profiles set role='admin', can_manage_admins=false where id='$HOST_UID';"
curl -s -X PATCH "$url/rest/v1/profiles?id=eq.$HOST_UID" \
  -H "apikey: $anon" -H "Authorization: Bearer $HOST_JWT" -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  -d '{"can_manage_admins":true,"phone_verified":true,"referral_code":"EVIL123","attended_count":99}'

# 3. another participant's body is unwritable (expect HTTP 403)
curl -s -o /tmp/sec233-3.json -w '%{http_code}\n' -X PATCH \
  "$url/rest/v1/messages?id=eq.5ec23300-0000-4000-8000-000000000002" \
  -H "apikey: $anon" -H "Authorization: Bearer $GUEST_JWT" -H 'Content-Type: application/json' \
  -d '{"body":"rewritten"}'
cat /tmp/sec233-3.json

# 4. read receipts still work
curl -s -o /dev/null -w '%{http_code}\n' -X PATCH \
  "$url/rest/v1/messages?id=eq.5ec23300-0000-4000-8000-000000000002" \
  -H "apikey: $anon" -H "Authorization: Bearer $GUEST_JWT" -H 'Content-Type: application/json' \
  -d "{\"read_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

# 5. public origin sink — no token, read-only
curl -s https://www.banbe.app/api/photo-share -H 'Host: evil.example' | grep -o 'property="og:url" content="[^"]*"'

# 6. referral code cannot be set by the client
curl -s -X PATCH "$url/rest/v1/profiles?id=eq.$HOST_UID" \
  -H "apikey: $anon" -H "Authorization: Bearer $HOST_JWT" -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' -d '{"referral_code":"x\" onmouseover=alert(1)"}'
```

### 5.2.1 Regression smoke — the guards must not break normal writes

| Check | Call | Expected |
|---|---|---|
| 7 | host PATCH `profiles` `{"muted_notification_kinds":[]}` (a real web write path) | `200`/`204`, value stored | **PASS** — `204` |
| 8 | guest POST `messages` `{"thread_id":…,"sender_id":<guest>,"body":"smoke"}` | `201`, and the stored `kind` is `text` | **PASS** — `{"body":"smoke","kind":"text"}` |

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X PATCH "$url/rest/v1/profiles?id=eq.$HOST_UID" \
  -H "apikey: $anon" -H "Authorization: Bearer $HOST_JWT" -H 'Content-Type: application/json' \
  -d '{"muted_notification_kinds":[]}'

curl -s -X POST "$url/rest/v1/messages" \
  -H "apikey: $anon" -H "Authorization: Bearer $GUEST_JWT" -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  -d "{\"thread_id\":\"5ec23300-0000-4000-8000-000000000001\",\"sender_id\":\"$GUEST_UID\",\"body\":\"smoke\"}"
```

Notes that decide what a result means:

- Check 3 must be **403/42501**, not `204` with 0 rows. If it is 204 but the body is unchanged,
  the guard worked through RLS instead of the grant — record it, it is still safe but not the
  proof 233 claims.
- Check 5: if Vercel rejects the unknown Host at the edge (404/421 before the function runs),
  that is evidence the edge does not forward arbitrary Hosts, **not** evidence the helper is
  broken. Record the status code and repeat with the normal Host; the unit test already proves
  `requestOrigin` ignores an unallowlisted host.
- Check 5 does not exercise the invoice wordmark itself (`api/payment-document` needs a real
  booking token). The wordmark is covered by
  `tests/unit/security-hardening.test.mjs` → `renderPaymentDocument escapes the origin used in
  the wordmark URL`. A production HTML check needs a test booking: create a free event as the
  fixture host, hold one seat as the fixture guest, confirm it as host, then open the payment
  document with `Host: evil.example`. Mark it "not done" unless someone does exactly that.
- Check 6 does **not** send an email. Sending real mail is out of scope here; the href escaping
  is covered by `renderEmail escapes a malicious CTA href` and by reading `api/notify.js:166-172`.

### 5.3 Cleanup

```bash
supabase db query --linked "delete from public.messages where thread_id='5ec23300-0000-4000-8000-000000000001'; delete from public.threads where id='5ec23300-0000-4000-8000-000000000001'; delete from public.organizers where id='sec233-org';"
supabase db query --linked "delete from public.account_phone_grandfathered where user_id in ('$HOST_UID','$GUEST_UID');"
curl -s -X DELETE "$url/auth/v1/admin/users/$HOST_UID" -H "apikey: $svc" -H "Authorization: Bearer $svc"
curl -s -X DELETE "$url/auth/v1/admin/users/$GUEST_UID" -H "apikey: $svc" -H "Authorization: Bearer $svc"
supabase db query --linked "select count(*) from public.profiles where id in ('$HOST_UID','$GUEST_UID');"   # expect 0
```

Observed 2026-11-21: both admin DELETEs returned `200`, and the leftover query returned
`profiles 0, organizers 0, threads 0, messages 0`.

## 6. Rollback

Trigger it if, after apply, any of these is true:

- chat read receipts stop working (`PATCH messages {read_at}` returns 403 for a participant);
- profile or organizer saves fail with a trigger error (not a 0-row RLS result);
- phone verification or host-mode changes stop persisting;
- any `profiles` INSERT from a client raises `INVALID_SOCIAL_LINKS` for data the app considers valid.

```bash
cd /Users/thetrungdo/Downloads/banbe
supabase db query --linked -f supabase/rollbacks/20261231000233_233_revert_server_owned_columns_guard.sql
# forget the applied version so a later push can re-apply it — only AFTER the rollback succeeded
supabase db query --linked "delete from supabase_migrations.schema_migrations where version = '20261231000233';"
```

Then verify the inverse (this is what the throwaway proof asserts):

```bash
supabase db query --linked "select has_table_privilege('authenticated','public.messages','UPDATE') auth_update, (select count(*) from pg_trigger where not tgisinternal and tgname in ('profiles_guard_client_write','organizers_guard_client_write','messages_guard_client_insert')) guards;"
```

Expected after rollback: `auth_update = true`, `guards = 0`.

Rolling back **reopens all the vulnerabilities in the audit** (self-granted admin permission,
self-awarded host badge, message rewrite). Treat it as an incident action, fix forward, and
re-apply 233 as soon as the cause is understood.

## 7. Environment and credential checklist (owner)

Nothing here was set or rotated in this session. "Observed" means what could be checked from
this machine — there is no Vercel CLI and no `.vercel/project.json`, so Vercel environment
values are **unknown** here.

| Variable | Where | Why | How to verify without printing a value | Observed 2026-11-21 |
|---|---|---|---|---|
| `PUBLIC_SITE_URL` | Vercel → Production | canonical origin for MapKit JWT, Wallet `webServiceURL`, invoice wordmark, auth redirect, photo-share `og:url` | `curl -s https://www.banbe.app/api/photo-share \| grep og:url` → today it returns the deployment host, see below | **unknown**, and `og:url = https://banbe-two.vercel.app/…` on `www.banbe.app` |
| `ORIGIN_ALLOWLIST` | Vercel → Production | only if a custom domain / preview host must be treated as an origin | a link from that host keeps that host instead of the canonical one | not needed for `banbe.app` / `www.banbe.app` / Vercel deployment hosts |
| `AUTH_REDIRECT_URL` | Vercel → Production | fallback canonical + recovery links | must equal the Site URL / redirect allow-list in Supabase → Authentication → URL Configuration; a password-reset mail must link to that host | **unknown** |
| `RESEND_API_KEY` | Vercel → Production | primary mail sender | a test notification arrives from the `EMAIL_FROM` address; without it the code silently falls back to Gmail | **unknown** |
| `EMAIL_FROM` | Vercel → Production | sender identity | same as above; default is `banbe <no-reply@banbe.app>` | **unknown** |
| `GMAIL_USER` + `GMAIL_APP_PASSWORD` | Vercel → Production | fallback sender only while `RESEND_API_KEY` is unset | mail arrives from the Gmail address (the current fallback) | **unknown** |

Consequences to state in the report rather than paper over:

- **Observed 2026-11-21 (post-apply):** `https://www.banbe.app/api/photo-share` renders
  `og:url = https://banbe-two.vercel.app/api/photo-share`. The site is served by Cloudflare in
  front of Vercel, so the function sees `x-forwarded-host = banbe-two.vercel.app`;
  `requestOrigin` allowlists the Vercel deployment hosts unconditionally and returns that host.
  **Setting `PUBLIC_SITE_URL` alone does not change this** — an allowlisted request host wins
  over the configured canonical. Fixing the customer-facing origin needs either the customer
  Host forwarded by the proxy, or a helper change that prefers the configured canonical over
  Vercel deployment hosts. That is a code/deploy follow-up, not part of 233, and it is not a
  security hole: an unknown Host is still blocked (edge `403`) and never reflected.
- Without `RESEND_API_KEY`, mail keeps going out through Gmail (`api/_lib/email.js`), which is
  the historical fallback and a deliverability risk, not a security hole.

### 7.1 Credential rotation

- **B-1 — UI-test account password.** The literal was removed from
  `apps/ios/BanbeAppUITests/ScreenshotCatalogTests.swift` in `68d960e5` (also `570a0337`,
  `76ae2fff` in history) and the file now reads the environment. The `2026-11-19` runbook §8
  records the rotation as done (admin `PUT /auth/v1/admin/users/<uid>` → 200, password grant →
  200, new value written 0600 to the ignored `apps/ios/.env.uitest`, present here). The old
  literal still exists in git history and cannot be un-leaked: treat it as burned. If there is
  any doubt it was rotated, rotate again:

  ```bash
  url=$(sed -n 's/^SUPABASE_URL=//p' .env.local | head -1 | tr -d '"')
  key=$(sed -n 's/^SUPABASE_SERVICE_ROLE_KEY=//p' .env.local | head -1 | tr -d '"')
  uid=26f10200-c108-4763-9551-a3e3bd057baf   # doqanh0906+banbe-fast-suite-shared@gmail.com
  new=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-28)
  curl -X PUT "$url/auth/v1/admin/users/$uid" -H "apikey: $key" -H "Authorization: Bearer $key" \
    -H 'Content-Type: application/json' -d "{\"password\":\"$new\"}"
  # verify with a real grant, then write $new only to apps/ios/.env.uitest (chmod 600)
  ```

- **Local keys.** `.env.local` and `supabase/.temp/.../docker.env` are gitignored and untracked
  (`git ls-files` shows neither). The key in `.temp` is the local demo `supabase-demo`, not a
  production credential. Rotate them only if the machine or a backup of it was shared.

### 7.2 Plans (B-2)

Vercel Pro and Supabase Pro are required for commercial use. This session cannot read either
plan and must not upgrade or pay. Owner confirms both; until then the outcome stays
"blocked by owner" even with 233 applied.

## 8. Not verified / open

- The six payloads and both regression smokes **were** run (§5.2, all as designed).
- The invoice wordmark was not exercised on production (`api/payment-document` needs a real
  booking token); the public `photo-share` sink uses the same `requestOrigin` helper and was.
- Email delivery (Resend/Gmail) not tested; only the template rendering is unit-tested.
- iOS was not audited in this pass and nothing here was run on a device.
- Independent verification (a second reviewer/agent) was not performed.
- A forged Host is rejected by the edge (`403`) before the function runs, so the helper's
  unallowlisted-host branch was **not** exercised through production — only in unit tests.
- `PUBLIC_SITE_URL` cannot be read from this machine, and `og:url` shows the deployment host
  (`banbe-two.vercel.app`) even on `www.banbe.app`; see §7 and the report's R-6.

## 9. Execution log

2026-11-21 (preflight only, read-only):

- `git rev-parse HEAD` → `fc5125ce`, branch `main`; working tree already dirty with the audit's
  own untracked files (not touched, not committed).
- `supabase --version` → 2.121.0; `projects list` → ● on `ukchdgdnwytretvqjjqu`.
- `migration list --linked` → local-only `182`, `183`, `184`, `233`; last remote `20261231000232`.
- `node --test tests/unit/security-hardening.test.mjs` → 10/10 pass.
- `bash supabase/tests/233_server_owned_columns/run.sh` → `233: 14 passed, 0 failed`.
- Held 182/183/184, `db push --dry-run` → exactly `20261231000233_233_server_owned_columns_guard.sql`;
  files restored by the trap.
- Definition snapshot written to
  `docs/audits/2026-11-21-security/production-snapshot-pre-233-2026-11-21.txt`.
- Pre-state read: no guard triggers; `authenticated`/`anon` hold table UPDATE on `messages`
  and every column (`body`, `sender_id`, `kind` included) — the audit's holes are still live.
- Throwaway `g-db` post-migration read: 3 triggers, `auth_table_update=false`,
  `anon_table_update=false`, `auth_read_at_update=true`, `auth_body_update=false`.
- **No production write, no deploy, no push, no secret read.**

2026-11-21 (apply session, authorized):

- Re-ran gate 1 (`10/10`, `233: 14 passed, 0 failed`) and gate 2 (dry run still lists only 233).
- `supabase db push --linked --yes --skip-vault` with 182/183/184 held:
  `Applying migration 20261231000233_233_server_owned_columns_guard.sql…` →
  `Finished supabase db push.`, exit 0. The trap put all three files back.
- `migration list --linked` → `20261231000233` on both sides; it is the new last remote version.
- §4 verify: 3 triggers, `auth_table_update=false`, `anon_table_update=false`,
  `auth_read_at_update=true`, `auth_body_update=false`, `auth_any_column_update=true`,
  version recorded, three functions with `prosecdef=false`.
- §5 payloads: P1 `204` with `name` changed and `verified=false`/`disputes_open=0`; P2
  `can_manage_admins=false`, `phone_verified=false`, `attended_count=0`, referral kept; P3 `403`
  `42501` with the body unchanged; P3b `401` for anon; P4 `204` with `read_at` set; P5 forged
  Host `403` at the edge and `og:url` on the deployment host; P6 referral unchanged; P7 `204`;
  P8 `201` `kind=text`.
- Fixtures deleted: admin DELETEs `200/200`, leftovers `0/0/0/0`.
- `git status` unchanged apart from the audit's own untracked files; no tracked file modified.

## 10. Gate status

| Gate | Condition | Status 2026-11-21 |
|---|---|---|
| 1 | local proof 14/14 re-run in the session | **PASS** |
| 2 | dry run lists only 233 | **PASS** |
| 3 | backup/snapshot available and recorded | **PASS** — owner confirmed the dashboard backup; definition snapshot on disk |
| 4 | explicit authorization in the session | **PASS** — owner authorized |

All four gates passed; 233 was applied the same day. The record is in
`docs/security/2026-11-21-audit.md` §8.

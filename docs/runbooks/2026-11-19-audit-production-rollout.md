# Production rollout — audit 2026-11-19 (migrations 222–231)

Project `ukchdgdnwytretvqjjqu` (BanBe), linked with Supabase CLI 2.121.0.
Repo `/Users/thetrungdo/Downloads/banbe`, branch `main`.
Executed 2026-11-19 20:21–20:36 UTC, then pushed to `origin/main`; Vercel built and served the new client.

## Status after this run

| Migration | Audit row | Commit | Status |
|---|---|---|---|
| `20261231000222_222_bookings_insert_lock` | 1 | `014874b` | **applied to production** |
| `20261231000223_223_organizers_private_columns` | 2 | `166a58f` | **applied after the web deploy** (see §6) |
| `20261231000224_224_events_client_write_guard` | 3 | `e97b1a8` | **applied to production** |
| `20261231000225_225_no_booking_after_event_ends` | 6 | `911b62b` | **applied to production** |
| `20261231000226_226_taken_event_keys` | 7 | `e270b69` | **applied to production** |
| `20261231000227_227_checkin_requires_payment` | 9 | `ae95390` | **applied to production** |
| `20261231000229_229_event_photos_insert_scope` | 32 | `e9db089` | **applied to production** |
| `20261231000230_230_verify_payment_expired_state` | 10 | `d27be3e8` | **applied to production** |
| `20261231000231_231_organizer_payouts_read_only` | 2 follow-up | `2bcf62a6` | **applied to production** |
| `20261222000183_183_server_only_payment_functions_and_unused_views` | 41 | — | **not recorded, effects already present** (see §7) |

`supabase migration list --linked` after the push shows **182, 183 and 184** as local-only;
182/184 are the old migrations the retention notes deliberately did not push, and 183 is the
unrecorded ACL patch from §7. 223 and 231 are applied.

## 1. Preconditions

```bash
cd /Users/thetrungdo/Downloads/banbe
supabase --version                 # 2.121.0 used here
supabase projects list             # must show ● on ukchdgdnwytretvqjjqu
supabase migration list --linked   # short header; remote blank = not applied
```

Expected for this run: the last remote version is `20261231000221`; 222–230 are blank.

`supabase db query --linked` uses the Management API (a login role), so no database password
is needed for reads. `db push --linked` also connected without a password prompt.

Backups: Supabase's dashboard backups/PITR are the data safety net. These eight migrations
change privileges, policies, triggers, functions and one view — **no table is altered and no
row is deleted** — so the rollback SQL below is the primary undo. A definition snapshot of the
affected objects was written to
`docs/audits/2026-11-19-cc/production-snapshot-pre-222-2026-11-19.txt` (907 lines, ignored).

## 2. Apply the seven safe migrations (used)

`db push` refuses 222+ while 182–184 are older pending migrations, and it would also pick up the
held 223. Move the four out of `supabase/migrations/` for the duration; the trap always restores
them.

```bash
set -euo pipefail
hold=$(mktemp -d)
for f in \
  supabase/migrations/20261222000182_182_*.sql \
  supabase/migrations/20261222000183_183_*.sql \
  supabase/migrations/20261222000184_184_*.sql \
  supabase/migrations/20261231000223_223_*.sql; do
  mv "$f" "$hold"/
done
trap 'mv "$hold"/* supabase/migrations/; rmdir "$hold"' EXIT

supabase db push --linked --dry-run --skip-vault
supabase db push --linked --yes --skip-vault
```

Expected dry run:

```
Would push these migrations:
 • 20261231000222_222_bookings_insert_lock.sql
 • 20261231000224_224_events_client_write_guard.sql
 • 20261231000225_225_no_booking_after_event_ends.sql
 • 20261231000226_226_taken_event_keys.sql
 • 20261231000227_227_checkin_requires_payment.sql
 • 20261231000229_229_event_photos_insert_scope.sql
 • 20261231000230_230_verify_payment_expired_state.sql
```

Expected push: `Applying migration …` for each of the seven, then `Finished supabase db push.`
Observed 2026-11-19: exactly that.

Afterwards confirm the four files are back:

```bash
ls supabase/migrations/20261231000223_223_*.sql
git status --short
```

`git status` must stay clean apart from the owner's untracked `map-dark.png`.

## 3. Verify the applied schema (read-only)

```bash
# 222: no client INSERT, old policy gone
supabase db query --linked "select has_table_privilege('authenticated','public.bookings','INSERT') auth_insert, has_table_privilege('anon','public.bookings','INSERT') anon_insert, (select count(*) from pg_policies where schemaname='public' and tablename='bookings' and policyname='bookings_insert_guest') old_policy;"

# 224/225/227: one trigger each
supabase db query --linked "select tgname, tgrelid::regclass::text tbl from pg_trigger where not tgisinternal and tgname in ('events_guard_client_write','bookings_guard_event_over','check_ins_guard_payment') order by 1;"

# 225: venue-clock end function exists
supabase db query --linked "select proname, pg_get_function_identity_arguments(p.oid) args from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('event_ends_at','bookings_guard_event_over','get_taken_event_keys','check_ins_guard_payment') order by 1;"

# 226: anon and authenticated may call the taken-keys function
supabase db query --linked "select has_function_privilege('anon','public.get_taken_event_keys()','EXECUTE') anon_keys, has_function_privilege('authenticated','public.get_taken_event_keys()','EXECUTE') auth_keys;"

# 227: both lookups require a confirmed payment
supabase db query --linked "select pg_get_functiondef('public.get_event_checkin_names(text)'::regprocedure) like '%payment_state = ''confirmed''%' names_paid_only, pg_get_functiondef('public.project_checkin_lookup(uuid)'::regprocedure) like '%payment_state IS DISTINCT FROM ''confirmed''%' lookup_paid_only;"

# 229: storage insert policy is host-scoped
supabase db query --linked "select with_check from pg_policies where schemaname='storage' and tablename='objects' and policyname='event_photos_host_insert';"

# 230: expired is refused before any write
supabase db query --linked "select pg_get_functiondef('public.verify_payment(uuid,text,text,jsonb)'::regprocedure) like '%v_b.status = ''expired''%' expired_guard;"
```

Observed 2026-11-19:

| Check | Result |
|---|---|
| 222 `auth_insert` / `anon_insert` / `old_policy` | `false` / `false` / `0` |
| triggers | `bookings_guard_event_over`, `check_ins_guard_payment`, `events_guard_client_write` |
| `event_ends_at` | present with `(timestamptz, time, boolean, text)` |
| 226 grants | `true` / `true` |
| 227 bodies | `names_paid_only = true`, `lookup_paid_only = true` |
| 229 `with_check` | `bucket_id = 'event-photos'` + event id from the first path segment + organizer owner check |
| 230 guard | `expired_guard = true` |

## 4. Rollback (reverse order)

Every rollback is a file under `supabase/rollbacks/`. Run it, verify, then delete the migration's
history row so a later push can re-apply it. Do **not** delete history first.

```bash
# 230
supabase db query --linked -f supabase/rollbacks/20261231000230_230_revert_verify_payment_expired_state.sql
# 229
supabase db query --linked -f supabase/rollbacks/20261231000229_229_revert_event_photos_insert_scope.sql
# 227
supabase db query --linked -f supabase/rollbacks/20261231000227_227_revert_checkin_requires_payment.sql
# 226
supabase db query --linked -f supabase/rollbacks/20261231000226_226_revert_taken_event_keys.sql
# 225
supabase db query --linked -f supabase/rollbacks/20261231000225_225_revert_no_booking_after_event_ends.sql
# 224
supabase db query --linked -f supabase/rollbacks/20261231000224_224_revert_events_client_write_guard.sql
# 222 — restores the insecure direct-INSERT policy; only for an incident, then re-apply 222
supabase db query --linked -f supabase/rollbacks/20261231000222_222_revert_bookings_insert_lock.sql

# after each successful rollback, forget the applied version
supabase db query --linked "delete from supabase_migrations.schema_migrations where version = '20261231000230';"
```

Expected: `Finished supabase db query.` and the inverse object disappearing (`event_ends_at`
gone, triggers gone, 222 policy and INSERT grant restored). 223's rollback drops
`organizer_payouts` and restores full table SELECT; it is only for a failed 223 rollout, and it
breaks a client that already reads the view — roll it back together with that client.

## 5. Post-rollout smoke tests

Run as a signed-in guest on production, in this order:

1. Home / Map load; a live event opens.
2. Reserve a seat on a live event (RPC hold still works after 222).
3. Open the payment screen (bank details still read — 223 is intentionally not applied).
4. Host → Settings → Payout and the QR manager still load.
5. Admin review detail still shows the tax code.
6. Check in a paid ticket; an unpaid/expired hold is refused with `PAYMENT_NOT_CONFIRMED` / `NOT_ELIGIBLE`.
7. An event whose end time has passed shows no active Reserve; a hold attempt is refused `EVENT_ENDED`.
8. Upload a photo to your own event; uploading into another host's event folder is denied.

Expected: 1–5 unchanged; 6–8 are the new refusals. Any 403 on 3–5 means 223 was applied early.

## 6. 223 — applied after the web deploy

Evidence collected 2026-11-19: the live bundle
`https://www.banbe.app/assets/index-CS6nEv4E.js` contained `bank_account_no` 3 times and
`organizer_payouts` **0** times. The pre-audit client still selected `bank_name`,
`bank_account_no`, `pay_qr_path`, `pay_note`, `billing_address`, `tax_code` and `momo_phone`
directly from `organizers` (`src/state/BanBeContext.jsx`, `PaymentDetails.jsx`,
`PaymentQrManager.jsx` at `e7e3a22b`). Applying 223 before the client shipped would have broken
payment, payout, QR and admin tax-code screens, so it was held until the push deployed the new
client.

Pushing `main` triggered Vercel's Git build. By 20:32 UTC the served bundle was
`/assets/index-z0hlFZy6.js`, which contains `organizer_payouts` 3 times. 223 was applied at
20:33 UTC with the command below, so the live client and the database match.

Order (reproduce on a fresh environment):

1. Deploy the web build that contains commit `166a58f` (it reads `organizer_payouts`).
2. Smoke-test payment, payout, QR and admin review on the deployed build.
3. Apply 223 alone:

```bash
set -euo pipefail
hold=$(mktemp -d)
for f in \
  supabase/migrations/20261222000182_182_*.sql \
  supabase/migrations/20261222000183_183_*.sql \
  supabase/migrations/20261222000184_184_*.sql; do
  mv "$f" "$hold"/
done
trap 'mv "$hold"/* supabase/migrations/; rmdir "$hold"' EXIT
supabase db push --linked --include-all --yes --skip-vault
```

Expected: `Applying migration 20261231000223_223_organizers_private_columns.sql…` and
`Finished supabase db push.` (`--include-all` is required because 223 sorts before the already
applied 224–230.)

4. Verify:

```bash
supabase db query --linked "select to_regclass('public.organizer_payouts') is not null as view_exists, has_column_privilege('authenticated','public.organizers','bank_account_no','SELECT') as bank_column_readable;"
```

Observed after 223: `view_exists = true`, `bank_column_readable = false`. A simulated
`authenticated` session saw 6 payout rows where it was host or booker.

### 6.1 Follow-up 231 — the view is read-only

223 created the view but Supabase's default privileges left ALL on it for `authenticated`
(`relacl arwdDxtm`). PostgreSQL reports `pg_relation_is_updatable = 28` (INSERT/UPDATE/DELETE),
so a guest with a booking could update a host's bank/tax columns through the view with the view
owner's rights. 231 revokes everything and grants SELECT back (`2bcf62a6`, applied 20:35 UTC).

```bash
supabase db query --linked "select has_table_privilege('authenticated','public.organizer_payouts','SELECT') sel, has_table_privilege('authenticated','public.organizer_payouts','UPDATE') upd;"
```

Observed: `sel = true`, `upd = false`; a simulated authenticated UPDATE fails with
`42501: permission denied for view organizer_payouts`, SELECT still returns the same rows, and
service-role reads return 200.

Rollback 223 with its rollback file (§4), delete its history row, and redeploy the previous web
build if the view path fails. 231's rollback restores the pre-231 ALL grant (it reopens the
auto-updatable view; diagnose only).

## 7. Row 41 — production ACL check (answered)

Migration `20261222000183` is **not** in `supabase_migrations.schema_migrations`, but its effects
are already present on production (the file says it was applied by hand). Read live:

```bash
supabase db query --linked "select
  has_function_privilege('anon','public.verify_phone_otp(uuid,text)','EXECUTE') anon_verify_phone,
  has_function_privilege('authenticated','public.verify_phone_otp(uuid,text)','EXECUTE') auth_verify_phone,
  has_function_privilege('anon','public.log_payment_event(uuid,text,public.payment_state,public.payment_state,uuid,text,text,text,jsonb)','EXECUTE') anon_log_payment,
  has_table_privilege('anon','public.reservations','SELECT') anon_reservations,
  has_table_privilege('authenticated','public.reservations','SELECT') auth_reservations,
  has_table_privilege('anon','public.checkins','SELECT') anon_checkins,
  has_table_privilege('anon','public.v_host_ledger','SELECT') anon_host_ledger,
  has_table_privilege('authenticated','public.v_host_ledger','SELECT') auth_host_ledger,
  has_table_privilege('anon','public.v_event_availability','SELECT') anon_availability,
  has_function_privilege('anon','public.record_bank_transaction(text,text,bigint,text,jsonb,boolean)','EXECUTE') anon_bank;"
```

Observed 2026-11-19: **all false**. Row 41 is therefore **not a live P0**; the three owner-side
attacks the audit described are closed in production even though 183 is unrecorded.

Optional drift cleanup (idempotent, ACL-only): record 183 so history matches reality. It has no
object changes; with 182/184 moved out, `supabase db push --linked --include-all` applies only
183 (move 223 out too if it is still pending). Do this only after re-running the query above.

## 8. Row 5 — UI-test password rotation (done)

Account: `doqanh0906+banbe-fast-suite-shared@gmail.com` (id `26f10200-c108-4763-9551-a3e3bd057baf`).
The old literal is still in git history but is no longer valid. Rotation used the Auth admin API:

```bash
url=$(sed -n 's/^SUPABASE_URL=//p' .env.local | head -1 | tr -d '"')
key=$(sed -n 's/^SUPABASE_SERVICE_ROLE_KEY=//p' .env.local | head -1 | tr -d '"')
uid=26f10200-c108-4763-9551-a3e3bd057baf
new=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-28)
curl -X PUT "$url/auth/v1/admin/users/$uid" \
  -H "apikey: $key" -H "Authorization: Bearer $key" \
  -H "Content-Type: application/json" -d "{\"password\":\"$new\"}"
```

Expected and observed: HTTP 200. Verify with a real grant, not just the update:

```bash
url=$(sed -n 's/^SUPABASE_URL=//p' .env.local | head -1 | tr -d '"')
anon=$(sed -n 's/^VITE_SUPABASE_ANON_KEY=//p' .env | head -1 | tr -d '"')
curl -o /dev/null -w '%{http_code}\n' "$url/auth/v1/token?grant_type=password" \
  -H "apikey: $anon" -H "Content-Type: application/json" \
  -d "{\"email\":\"doqanh0906+banbe-fast-suite-shared@gmail.com\",\"password\":\"$new\"}"
```

Observed: `200`. The new value was written only to the ignored `apps/ios/.env.uitest`
(0600), which `UITestAuthHelpers.swift` reads:

```bash
set -a; source apps/ios/.env.uitest; set +a
xcodebuild test ...   # signed-in suites
```

If the admin API ever returns 500 (`Database error finding users`), update the same user by id
with `extensions.crypt(<password>, extensions.gen_salt('bf'))` and retest the grant. Rollback is
another rotation — never restore the leaked password. Update CI/local scripts that still hold the
old value; the repo's HEAD no longer contains a literal (`68d960e`).

## 9. Execution log (2026-11-19)

- 20:21 UTC — preflight: 36 events, 41 bookings, 31 organizers; last remote migration 221.
- 20:22 UTC — definition snapshot written (907 lines).
- 20:22 UTC — dry run listed exactly the seven; real push applied them in order.
- 20:23 UTC — post-checks: 222 revokes client INSERT; 224/225/227 triggers present; 226 grants
  anon/authenticated; 227 lookups paid-only; 229 policy host-scoped; 230 expired guard present.
- 20:23 UTC — pending list: 182, 183, 184, 223.
- 20:24 UTC — live bundle check: `bank_account_no` 3, `organizer_payouts` 0 → 223 held.
- 20:30 UTC — `git push origin main` (43 commits, fast-forward `a5f2a6ea..9e2b8685`).
- 20:32 UTC — served bundle switched to `index-z0hlFZy6.js`; `organizer_payouts` 3 → 223 applied.
- 20:35 UTC — live 223 audit: ACLs all on the view, bitmask 28, simulated UPDATE succeeded → 231 written and applied.
- 20:36 UTC — 231 verified: SELECT true, INSERT/UPDATE/DELETE false, UPDATE denied (42501), SELECT 6 rows, service role 200.
- 20:24 UTC — row 41 ACL query: all false → no live P0.
- 20:25 UTC — row 5 admin PUT 200, password sign-in 200, `apps/ios/.env.uitest` written 0600.

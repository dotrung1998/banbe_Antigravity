# 32 — Phone-OTP test exemption (IMPLEMENTED LOCALLY, NOT APPLIED)

Status: migration 159 + rollback 160 + grant script + web/iOS status row written and locally tested. **Nothing applied to live data, nothing deployed/committed.**

## What it is
`account_phone_test_exempt(user_id, reason, granted_at)` — service-role-only (RLS on, no policy, anon/authenticated revoked; local test proves a client cannot read, insert, update or delete). `account_gate_status()` skips ONLY the phone requirement for those users and returns `phone_test_exempt` (true only while the phone is not really verified). `set_date_of_birth()` accepts the exemption in its "phone verified first" check. DOB enrollment, per-session DOB confirmation, the RLS gate and `gate_pre_request` are unchanged. The phone stays unverified: `phone_verified` false, `phone_confirmed_at` never set, no SMS.

Why not reuse `account_phone_grandfathered`: it also waives DOB enrollment and is the permanent legacy cohort (never edited here).

## Patching approach
159 reads the CURRENT `pg_get_functiondef` of both functions and applies exact single-occurrence replacements (aborts on 0 or >1 matches, so later edits are preserved and drift is loud). 160 (`supabase/rollbacks/`, deliberately NOT in `supabase/migrations/` so `db push` won't run it) reverses exactly those edits and drops the table — not a restore of 124.

## Data
`scripts/grant-phone-test-exemption.mjs` — dry-run by default; prints user IDs, previous values, writes, undo SQL and a plan hash. `--apply --approve <hash>` re-reads everything and aborts if the hash changed; writes are compare-and-set; undo SQL saved to `.migration-state/`. Contact phone goes to `profiles.phone` only.

## Admin self-service (added in the same migration 159)
`admin_phone_exempt_lookup(email)` and `admin_set_phone_exemption(user, phone, dob, grant)` — SECURITY DEFINER, authorized server-side by `is_platform_admin()` (`profiles.role='admin'`, role writes blocked for clients by `guard_profile_role`) + `account_gate_ok()`. Admin cannot target themselves. Validates E.164 (+NANP/DE rules) and `profiles.phone` collisions before writing anything; DOB is only inserted when absent (`DOB_ALREADY_SET` otherwise); grandfathered users get no exemption row; every call is written to `phone_test_exempt_audit` (never the DOB value). UI: web `src/screens/AdminTestAccounts.jsx` (`/admin/test-accounts`) and iOS `AdminTestAccountsView.swift`, both under Review & Moderation. Rollback 160 drops the RPCs and audit table too. No password setting is part of this.

## Profile-only phones do NOT enable promo texting
`begin_promo_compose` (migration 123/126) reads the recipient phone from `auth.users.phone`. These test numbers live only in `profiles.phone` (auth phone stays empty, unconfirmed), so these accounts will never be offered or composed to as promo recipients. That's intentional — filling `auth.users.phone` risks Supabase unique-phone conflicts and would make a later real verification fail with `phone_exists`.

## Known / not done
- `profiles.phone` and `profiles.phone_verified` are client-writable via `profiles_update_own` (pre-existing). The UI therefore reads verified/exempt state from the server gate status, never from the profile row. Not fixed here.
- `auth.users.phone` collision check is not possible via the admin API (`listUsers` returns 500 on this project); only `profiles.phone` collisions are checked. Irrelevant for this feature (auth phone untouched) but matters when the user later verifies for real.
- Live data seen 2026-10-07: `doqanh0906@gmail.com` is legacy-grandfathered (no exemption needed, no DOB yet); `doqanh0609@gmail.com` (the spelling seeded in 123) does not exist, so that seed never matched.

## Tests
`bash supabase/tests/159_test_exempt/run.sh` (Docker, throwaway Postgres): idempotent apply, exempt-but-unverified, DOB still required, email-code DOB confirm kept, normal user blocked, verified user, no client access to the table, cohort unchanged, user-delete cascade, rollback, abort on drift.

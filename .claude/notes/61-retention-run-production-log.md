# 61 — Retention plan run: production log and status (2026-10-23)

Owner brief of 2026-10-23: work through `docs/retention-delight-plan.md` autonomously, production Supabase + Vercel
authorized, one counts-only baseline query authorized. Every production change is logged here (what, why, when, file).
Implementation plans per phase: `docs/impl/`.

## Production log (UTC)

**Backup (before any change).** `supabase db dump --linked` → `~/banbe-backups/2026-10-23-pre-185-194-195/`
(`schema.sql` SHA-256 prefix b2ec0385e0921e36, `data.sql` a63c969e522c6c73; chmod 600, outside the repo, contains
personal data: keep private). Supabase's own daily physical backup also exists.

**Dry run.** Fresh container: all 188 migrations + suites 23 (push) / 24 (US) ALL PASS; existing suites (run.sh, 13, 20,
21) ALL PASS. Production SCHEMA only (no data) restored into a container: 185 → 194 → 195 applied without error,
suites 23/24 ALL PASS there, catalog snapshot diff per migration reviewed (only intended changes).

**Applied, one migration per push** (one-file workdir = production's applied set + the target, `db push --linked
--include-all`, dry-run listed exactly one file each time):
| Migration | Time | Verification |
|---|---|---|
| 185 organizers anon public columns only | 09:50:42 | recorded; diff == copy diff (policy text prints `auth.uid()` vs `uid()`, cosmetic); anon `SELECT bank_account_no` → 42501, public columns OK |
| 194 push delivery + switch defs | 09:51:10 | recorded; new functions/tables: no anon/PUBLIC grant, client RPCs authenticated only; flags admin_event_wipe=true, push_enabled=false, rewards=false, rewards_v2=false; outbox 0; tick job; pg_net |
| 195 event tz + currency | 09:51:37 | recorded; 23/23 events → Asia/Ho_Chi_Minh + VND (0 US events existed); create/resubmit now authenticated-only (were PUBLIC since 112) |

**F2 check on production** (`docs`-less, one DO block that always ends in RAISE EXCEPTION, as the test admin):
US/California 19:00, $12.50 → tz America/Los_Angeles, currency USD, price 1250 (cents), venue-local 19:00
(03:00 UTC, PST); paid USD booking → PAID_BOOKING_NOT_AVAILABLE; free USD booking allowed; VN event unchanged
(Asia/Ho_Chi_Minh, VND, 19:00). Residue check: 0 events left. US locations therefore stay unblocked.

**Web deploy.** `git push origin main` (5c8e4f5) at ~09:53; the live bundle served the new code ~40 s later.

**Baseline query** (`docs/sql/retention-baseline.sql`, run once, read-only, counts only, test accounts excluded, groups
< 20 hidden): every group is `<20`. Fewer than 20 real (non-test) users exist, so there is no measurable baseline yet.
Groups present: markets VN and unknown only (no US); app-open hours 07, 08, 18 (VN time), Tue–Thu; booking statuses
confirmed / cancelled / expired; notification kinds read: booking_requested, hold_created, hold_expired, new_message,
organizer_invite.

### Wave 2 (196 measurement, 197 age 16, 198 quick-win server)
**Backup:** `~/banbe-backups/2026-10-23-pre-196-198/` (schema 166e203405e6deb1, data b6e9ab1dbd941ca6).
**Dry run:** current production SCHEMA restored into a container; 196 → 197 → 198 applied cleanly; suite 25 ALL PASS
there; full chain on a fresh container: suites 23–27 ALL PASS, older suites run.sh / 13 / 20 / 21 ALL PASS.
**Applied:** 196 at 10:54:32, 197 at 10:54:36, 198 at 10:54:41 (each its own one-file workdir and dry-run listing exactly
one file). **Deviation:** the three ran in one loop, so the catalog snapshot and audit were taken once after 198
instead of after each; the combined diff contains only the intended objects (below), nothing removed.
**Verified:** recorded as applied (not applied now: 182–184 on purpose, 199, 200); new functions: client RPCs
(`admin_retention_report`, `get_host_confirmation_time`, `log_app_events`) authenticated only, helpers service-role
only; new tables `app_events`, `app_event_names`, `report_excluded_users` no anon/authenticated grant; switch
app_events=false; app_events rows 0; profiles.market backfilled for 5 profiles; report_excluded_users 2 (the two test
logins); `set_date_of_birth` contains the AGE_TOO_YOUNG check.

### Wave 3 (199 core loops, 200 digest + switches)
**Backup:** `~/banbe-backups/2026-10-23-pre-199-200/` (schema f3a78ab28282c5af, data 8b4074972960e442).
**Dry run:** production schema copy: 199 → 200 applied cleanly. Suites 26/27 on the copy failed only where the copy
differs from production: (a) translation ROWS are data, not schema, so the copy had none (production has them:
checked 3/3 rows of 198); (b) on the copy, restored functions belong to `postgres` while new objects belong to the
local superuser (sequence permission); in production both belong to `postgres` — proven below. Fresh-chain suites
23–27 ALL PASS.
**Applied one at a time, verified after each:**
- 199 at 12:31:12 — client RPCs (submit/get feedback, feedback summary, host recap) authenticated only; helpers and
  tables `event_feedback`, `event_reminder_log`, `follow_alert_queue` closed to clients; `follows.created_at` inherits the
  table's existing column grants (RLS unchanged); switches event_reminders=true, event_recap/host_recap/follow_alerts=false;
  jobs `bb_event_reminders`, `bb_follow_alerts`; rolled-back run of `send_event_reminders()` → 0 due now.
- 200 at 12:31:45 — `set_my_digest_opt_in` authenticated only; `notification_consent_log`, `weekly_digest_log` closed;
  rolled-back functional check as the test admin: digest opt-in refused while the switch is off (NOT_AVAILABLE),
  promo push opt-in writes its consent row (sequence OK), preferences return both keys; switches weekly_digest,
  intent_foryou, live_activity, market_share all false; `send_weekly_digests()` → 0. Residue: 0 consent rows.
  Minor: the trigger function `notification_consent_log_append_only()` keeps the default EXECUTE grant (it only raises).

## Flags (final values are reported at the end of the run)
admin_event_wipe=true (untouched), rewards=false (untouched), rewards_v2=false (untouched), push_enabled=false (new).

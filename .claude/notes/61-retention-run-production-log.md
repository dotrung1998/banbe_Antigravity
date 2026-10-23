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

## Flags (final values are reported at the end of the run)
admin_event_wipe=true (untouched), rewards=false (untouched), rewards_v2=false (untouched), push_enabled=false (new).

# 58 — Rewards v2: Phase 0 fixes + weekly streak, grace/repair, tiers, next badge, goal (2026-10-22)

Branch `feat/rewards-v2` (worktree `../banbe-rewards-v2`), built from the approved plan
(`~/.claude/plans/logical-spinning-iverson.md`). **APPLIED TO PRODUCTION 2026-10-22 (177, 178, 179, 180, 191, 192 +
corrective 193), see "Production log" at the end. Merged into `main` locally; web NOT deployed yet (push blocked).**
Builds on note 36 (165), note 51 (187) and the unmerged Phase 0 branch `feat/rewards-phase0` (177-180), which is
merged here **with its original numbers** (owner's choice).

## Status
- 177-180 (Phase 0 branch), 191 fixes, 192 Rewards v2, 193 corrective: APPLIED to production 2026-10-22.
  Switch `rewards_v2` seeded OFF and left OFF. `rewards` left at its original value (OFF).
- Web: IMPLEMENTED (unit 367/367, `vite build` ok), merged into main, NOT deployed (see Production log).
  `tests/rewards-v2.spec.js` is opt-in (`BANBE_E2E_REWARDS_V2=1`), never run: it needs the shared signed-in account.
- iOS: IMPLEMENTED, see "Verification". Not device-checked. Run `xcodegen generate` after pulling (new test file).
- Policy: `banbe_User_Policy.md` UNCHANGED. Draft clauses 1.3b/1.3c added to `docs/policy-rewards-draft.md`.

## Deploy order (production already has 165-190)
`supabase db push --include-all` is required: 177-180 have timestamps older than 181-190. Verified locally that no
function in 177-180 is redefined by 181-190 and that the production order (<=176, 181-190, 177-180, 191, 192) gives
the same result as a fresh reset: `supabase/_localtest/22_rewards_prod_order_run.sh`. Apply one at a time per the
branch runbook (`docs/rewards-staging-runbook.md`), 177 → 180 → 191 → 192, staging first.

## 191 (fixes) — what and why
1. **Removed events kept their coins** (real bug since 188/189): `rewards_desired_sources` now excludes `removed`;
   the status trigger re-syncs on removal AND on restore, and refreshes host milestones on entering/leaving
   ended/removed. One-time backfill reverses coins of already-removed events.
2. **Server-side Rewards switch**: `redeem_reward`, `record_active_day`, `set_my_reward_timezone` return
   `NOT_AVAILABLE` while `rewards=false` (missing = on). Reads and awards unchanged (note 51's intent).
3. **Attendance window (rules v2)**: check-in outside `[starts_at − 3h, starts_at + 24h]` → attendance still valid,
   award 0 coins, reason `off_window`; does not use up the monthly cap. Judged on the booking's FIRST recorded
   check-in time, so a restore/re-sync never zeroes a fair award. Events have no end time; no starts_at = not judged.
4. Legacy `check_in(text, boolean)` (007): EXECUTE revoked — no caller in web/iOS/api; it bypassed check_in_guest.

## 192 (v2) — design decisions
- **Week = Mon–Sun in the user's rewards tz**; any verified active day keeps it (owner chose the low bar).
- Grace: 1 per 4 active weeks, max 2, auto-used on a missed finished week; streak keeps its length.
- Repair: streak ≥4 weeks that breaks → restored by a still-valid attendance dated within 14 days after the missed
  week ended. Saves can't repair. Reported as `repair {weeks, until}` (a real date; no countdown UI).
- Not retroactive: `rules.week_streak.start` = apply date; grace/repair only from that week.
- All derived (`rewards_week_streak_of`), no table, no backfill, no ledger rows. Daily `streak` key kept for old builds.
- Tiers: `reward_badge_defs` + family/tier/metric/starts_on/ends_on/v2. Old 6 codes = tiers 1-3, unchanged. 10 new
  defs incl. seasonal `season_tet_2027` (events starting 25 Jan–21 Feb 2027). v2 rows listed only while
  `rewards_v2` is on, but earned silently. Seasonal listed from 14 days before its window, or once earned.
- **Dropped from the plan:** a "Goals met" badge family — a goal you can lower after the fact makes it gameable.
  Monthly goal pays nothing and earns nothing; it only shows progress.
- Deviation: plan had 196/197/198 as three migrations; shipped as ONE (192) so the payload RPCs are rewritten once.
- Deviation: 179's duplicate `reward_feature_flags` table was NOT folded into `app_feature_flags` (owner chose to
  keep 177-180 as-is). `rewards_v2` lives in `app_feature_flags`; `partner_offers`/`reward_events` still in 179's.

## Celebrations (client-only)
Newly earned badge / week milestone (4, 8, 12, 26, 52) / successful redeem → status card + ConfettiBurst (+ iOS
`Haptics.success` and a VoiceOver announcement). Once per account per device (localStorage / UserDefaults
`…celebrated.v1.<uid>`); the FIRST visit on a device only remembers, so an existing collection never bursts on a new
phone. Same keys on both platforms (shared test vectors).

## Tests
- SQL harness (container `banbe-rv2`, image 17.6.1.166): 13, 13b, 14, 15, 16, 17, 18 (branch), 20 (191, 37
  checks), 20b (191 backfill/re-apply/rollback), 21 (192, 60 checks), 22 (production order + 192 rollback/re-apply).
  Fixture changes: suite 13 checks guests in at the event start (window); 01_seed turns the Rewards switch on;
  suite 16 skips 19x; suites 14/20 key checks made additive-safe.
- Shared parity vectors: `tests/fixtures/rewards-v2-week-streak.json` (web `tests/unit/rewardsV2.test.mjs`, iOS
  `BanbeAppTests/RewardsV2Tests.swift`).
- Suite 13 T15a "flake" FIXED: a brand-new container didn't grandfather the seeded fake accounts past the gate
  (auth.users survives the harness reset, so only reused containers were grandfathered). 01_seed now does it.

## Known limitations / open
- Undoing a check-in still doesn't remove its active day (165 quirk) — a week can stay "active" after an undo.
- Off-window coins are not re-evaluated later; host check-in UI does not warn hosts about the window yet.
- No real retention metrics yet (only no-op analytics events: rewards_badge_celebrated, rewards_week_milestone,
  rewards_goal_set). Production volume is far below what an A/B test needs (~1,400/arm).
- Lawyer items unchanged from the plan (partner offers, shared_phone, nudges consent, expiry, CCPA notice).

## Production log (2026-10-22, all times UTC)
Every change below was made by Claude Code from this repo, linked project via `supabase` CLI 2.121.

**Step 1 — state found (read-only).** `supabase migration list --linked`: production had everything up to 176, plus
181, 186, 187, 188, 189, 190, and 165/166 (the 166 MIGRATION, not the 166 rollback). NOT applied: 177-180, 182, 183,
184, 185 (182-185 belong to other workstreams and were deliberately NOT pushed; `db push --include-all` from the repo
would have pushed them, so each migration was applied from a per-migration workdir holding exactly production's set
plus one file). This settles notes 51 vs 54: 187-190 ARE live. Flags found: `rewards=false`, `admin_event_wipe=true`.
Reward data: 4 ledger rows (sum 40), 4 user badges, 3 active days, 0 attendances, 0 check-ins, 0 removed events.

**Backup.** Supabase physical daily backup of 2026-10-22T07:07Z (PITR off), plus a full pg_dump taken before any
change: `~/banbe-backups/2026-10-22-pre-rewards-v2/` (schema.sql + data.sql, chmod 600, outside the repo; contains
personal data, keep private). SHA-256 prefixes: schema 5ad8c3af86b19dee, data 9e1cefc8d77d691a.

**Dry run.** All 11 harness suites (13, 13b, 14-18, 20, 20b, 21, 22) on a brand-new container: ALL PASS. Production
schema+data restored into a local container and 177→180→191→192 applied in production order: no errors, old-key RPC
snapshot byte-identical after each step, ledger unchanged. Suites 14/20 pass there too (13 T1a and 21 A1 fail only
because the restored copy's auth/ACLs can't be rebuilt locally; production ACLs were audited directly instead).

**Applied, one migration per push (`db push --workdir <one-file workdir> --linked --include-all`), each dry-run first
(exactly one file listed), each followed by: recorded-as-applied check, snapshot diff of balances/streaks/badge
progress/history/catalog for all 6 users with reward rows (identical every time), RLS + GRANT audit, flags + ledger.**
| Migration | Started | Result |
|---|---|---|
| 177 user reward timezone | 17:20:49 | ok |
| 178 reward risk flags | 17:26:41 | ok (risk scan stays disabled) |
| 179 reward kinds | 17:27:44 | ok (`partner_offers` false) |
| 180 reward event counters | 17:29:47 | ok (`reward_events` false, 0 counters) |
| 191 rewards fixes | 17:30:10 | ok (legacy check_in no longer client-callable, rules v2) |
| 192 rewards v2 | 17:30:29 | ok (`rewards_v2` seeded false, rules v3, 16 badge defs) |
| 193 revoke rewards_tz_valid (corrective, new) | 17:32:25 | ok |
**Fixed along the way:** the grant audit after 177 showed `rewards_tz_valid(text)` executable by anon/authenticated
(177 never revoked it). Harmless (catalog lookup only) but not intended → corrective migration 193 (tested locally
with suites 14/20/21/22, suite 20 now asserts it), audit clean afterwards. Ledger after everything: 4 rows, sum 40.

**Verification on production (test account `banbetestadmin` only).** One DO block that ALWAYS ends in RAISE EXCEPTION,
so everything rolled back (temporary guest, two test events, bookings, check-ins, ledger rows, notifications, the
removal and restore). Real RPCs (check_in_guest, admin_remove_events, admin_restore_events, get_my_rewards,
redeem_reward) as a password session: check-in at start +20 `attendance`; check-in 30 h after start 0 `off_window`
(cap count 1); admin removal → balance back to 0, attendance invalid; restore → +20 `attendance`; payload keeps every
old key (6 badges, v2 off); redeem while Rewards off → `NOT_AVAILABLE`. Residue check afterwards: 0 events, 0 users,
ledger still 4/40. No DB webhooks exist (checked), so nothing escaped the rollback.
**Switch check:** `/privacy` served from this commit against production's real switches: OFF → no Rewards text;
`admin_set_feature_flag('rewards', true)` as the test admin at 17:36:32 → A9/B2 rows appear with no redeploy;
set back to `false` at 17:36:39 → hidden again. Two audited flag changes, final value = original (false).
Old iOS builds: decoding tests (old payload + optional new keys) + the production payload check above.

**Not done:** web deploy. `git push origin main` (Vercel deploys from GitHub) was refused by the session's
permission rules; main is merged locally and ahead of origin. Until it is pushed, the live web runs the old client
against the new server (compatible: old keys unchanged; the new server only refuses writes while Rewards is off,
which the old client already hides).

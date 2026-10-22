# 57 — Rewards v2: Phase 0 fixes + weekly streak, grace/repair, tiers, next badge, goal (2026-10-22)

Branch `feat/rewards-v2` (worktree `../banbe-rewards-v2`), built from the approved plan
(`~/.claude/plans/logical-spinning-iverson.md`). **Nothing applied to any Supabase project; not deployed.**
Builds on note 36 (165), note 51 (187) and the unmerged Phase 0 branch `feat/rewards-phase0` (177-180), which is
merged here **with its original numbers** (owner's choice).

## Status
- 191 rewards fixes: IMPLEMENTED, harness-tested, NOT applied.
- 192 Rewards v2: IMPLEMENTED, harness-tested, NOT applied. Switch `rewards_v2` seeded OFF.
- Web: IMPLEMENTED (unit 358/358, `vite build` ok). Playwright `tests/rewards-v2.spec.js` written, NOT run (global
  setup signs into the real shared account).
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
- One flaky first run of suite 13 (T15a) on a brand-new container; not reproduced in 6 later runs. Unexplained.

## Known limitations / open
- Undoing a check-in still doesn't remove its active day (165 quirk) — a week can stay "active" after an undo.
- Off-window coins are not re-evaluated later; host check-in UI does not warn hosts about the window yet.
- No real retention metrics yet (only no-op analytics events: rewards_badge_celebrated, rewards_week_milestone,
  rewards_goal_set). Production volume is far below what an A/B test needs (~1,400/arm).
- Lawyer items unchanged from the plan (partner offers, shared_phone, nudges consent, expiry, CCPA notice).

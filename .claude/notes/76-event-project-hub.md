# 76 — Event Project Hub (Hosting): per-event private team workspace

Status: **phases 1-2 of 13 done.** Phase 1 (pure logic + switches) committed c731375. Phase 2 = migration 210, tested on
the throwaway stack only, NOT applied to production. No UI yet, nothing reachable in the app. Plan (approved 2026-11-03):
`~/.claude/plans/pasted-content-id-234b-plan-mode-composed-koala.md`. Design source of truth for roles, tabs and layout:
`banbe_hosting_project_hub_v6.html` (owner attachment, not in the repo).

## Words
- Project roles: **Manager** ("Quản lý", identifier `manager`), Finance & door (`finance`), Lane lead (`lane_lead`),
  Helper (`helper`). The Host is derived, never stored.
- The policy's own word for the organizer's second account (Terms A, Privacy B4) means a different thing and is
  never used for a project role. `tests/unit/projectNaming.test.mjs` fails if project code, fixtures or this note
  use it. The repo-wide list of where that word already appears is §5g of the plan.

## Phase 1 (this pass)
| Piece | Web | iOS | Shared vectors |
|---|---|---|---|
| Day-of layout, a rule-for-rule port of v6 `layoutDay` (stretch, squeeze next only, freeze on tick, overlap flag, half-hour axis) | `src/lib/rosLayout.js` | `Lib/RosLayout.swift` | `tests/fixtures/ros-layout.json` (11 cases: 17:40 prototype, tick freeze, long overrun, out-of-order tick, edit while running, midnight, US DST, zero length, empty) |
| Permissions, every action, both Host definitions | `src/lib/projectPermissions.js` | `Lib/ProjectPermissions.swift` | `tests/fixtures/project-permissions.json` (10 actors × 70 rows × `either`/`owner_only`) |
| Limits (one file) | `src/data/projectLimits.json` (imported) | bundled by `project.yml`, `Lib/ProjectLimits.swift` | `ProjectLimitsTests` checks bundle == repo file == fallback |
| Team channel links | `src/lib/projectChannels.js` | `Lib/ProjectChannels.swift` | `tests/fixtures/project-channel-links.json` (SQL will reuse it in 210) |
| Invite links / codes | `src/lib/projectInviteLink.js` | `Lib/ProjectInviteLink.swift` | `tests/fixtures/project-invite-links.json` |
| Switches (all OFF_UNLESS_SET, both platforms, category "Event projects", admin rows) | `featureFlags.js`, `featureFlagCategories.js`, `AdminFeatures.jsx` | `FeatureFlags.swift`, `FeatureFlagCategories.swift`, `AdminFeaturesView.swift` | `featureFlags.test.mjs`, `featureFlagCategories.test.mjs`, `FeatureFlagsTests` |

Switches: `event_project_hub`, `project_qr_invite`, `project_delegate_checkin`, `project_delegate_payments`,
`project_delegate_refunds`. Until migration 210 is applied, `admin_set_feature_flag` refuses them (no row in
`app_feature_flag_defs`, 194:62), so an admin cannot turn on a half-built feature.

## Decisions made while building (read before phase 2)
- **Money/door never uses the project Host check.** `projectIsHost` / server `project_is_host` (v1 = either organizer
  account) governs project actions only. Check-in, confirm payment, proof viewing and refunds keep the existing RPCs'
  own check (`owner_id OR user_id`), and delegation is OR'ed on top. Otherwise a later owner_id-only switch would
  silently strip today's second account of door and money rights. The fixture encodes it: under `owner_only`,
  second_account loses project rights and keeps money rights (`allowOwnerOnly` rows).
- Delegated actions need: the hub switch, the step's switch, an active member, the capability (Finance always has
  both), an unexpired grant (event end + 7 d, Host can extend up to read-only) and a project that is not read-only.
- An open-dispute grant (migration 138's one-open-thread-per-claim) allows refund actions only, on that claim only,
  until its date or until the dispute closes. It never opens check-in or payments.
- Rejecting a pending payment (`money.reject`) is never delegated.
- Text lengths count Unicode scalars on iOS (same as JS `[...s].length` and Postgres `length()`), so decomposed
  Vietnamese cannot pass on one side and fail on the other.
- Channel hosts must BE the platform domain or a subdomain of it (stricter than 102's `~ 'x\.com$'`). Ports,
  `user@`, whitespace and non-https are rejected.
- Invite codes: `BB-` + 4 from `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (31, no 0/O/1/I/L). Links carry a 22-character
  token. Accepted: `https://(www.)banbe.app/join/…`, `banbe://join/…`, a bare token or a typed code. Referral links
  (`/?ref=`) are never parsed as invites.

## Verified
- Web unit: `npm run test:unit`, 898/898 (baseline was 713). The permission suite failed 6 times before the switches
  were registered OFF_UNLESS_SET (missing key = on), which is the exact danger the plan names.
- `npx vite build` OK.
- iOS: `xcodegen generate`; the full `BanbeAppTests` run: 543 tests, the only failure is the PRE-EXISTING
  `GiftTicketPDFTests.testPDFLinksPointAtRealDestinations` (see notes 43–48). The 24 new/changed tests are green.
- Not checked: the admin switch rows on screen (web/iOS), not rendered.

## Phase 2 — migration 210 (LOCAL HARNESS ONLY, NOT applied to production)
`supabase/migrations/20261231000210_210_event_project_core.sql`, rollback
`supabase/rollbacks/20261231000210_210_revert_event_project_core.sql`.

- 13 tables (projects, lanes, members, invites, invite attempts, change requests, tasks, posts, votes, replies, seen,
  run-of-show items, log), SELECT-only RLS through `is_event_project_member()`, and every write as a SECURITY DEFINER
  RPC. Supabase's default grants on new tables and functions are revoked explicitly. Invites are visible to the Host and
  their creator only, change requests to the Host and the proposer only, and invite attempts to nobody.
- **Host = `project_host_ids()`** (v1 `ARRAY[owner_id, user_id]`). `project_is_host()` wraps it. Swapping that one
  function to owner_id only is the whole switch: the SQL matrix runs twice to prove it.
- No stored dates: `project_event_end()` = later of midnight after `event_date` in `events.tz` and the last run-of-show
  end. Read-only = end + 30 d. Moving the event or adding a late item moves everything.
- RPCs: reads (`get_event_project` with `p_since_version` → `{unchanged}`, posts paging, one post, trash, `get_event_project_ros` poll,
  `get_my_event_projects`), `start_event_project` (opt-in, client-supplied lane names, de-duplicated), invites (create /
  list / revoke / `peek_project_invite` / `project_redeem_invite`, 128-bit token + BB-XXXX, 48 h, 1..20 uses, multi-use
  only with `project_qr_invite`, 10 failures per hour lock, a removed member can rejoin with the new role and no money
  caps), members (set, remove: unassigns open tasks, leave), lanes and channels (Host applies; Manager proposes through
  `event_project_change_requests`, the Host approves with an optional reason or declines with a required one; approval
  re-runs the same checks), tasks, topics (4 types, limits, quiet-only edits, vote toggle, decide = locked decision,
  delete with a reason), run-of-show (10-minute minimum, within [start − 12 h, start + 24 h], server-clock ticks),
  trash (restore / purge, keeps the 30 newest).
- Only "blocked" notifies at once (both Host accounts, never the blocker); joining notifies the inviter. The daily
  digest and purge jobs come with 211.
- Bug classes caught while building: (1) `IF NOT (... v_me.role = 'manager' ...)` is NULL for a caller without a member
  row, and plpgsql SKIPS the refusal. Every permission check is now `NOT coalesce((...), false)`. (2) A missing JSON
  `primary` key became `null`, not `false` (found by the shared channel fixture).
- Deviations from the plan: the blocked alert is in 210 (no cron needed), `project_leave` was added, peek requires
  sign-in (the token waits on the device through signup), and starting lanes come from the client in the Host's language.

### Verified (throwaway real-Supabase stack, `supabase/tests/210_project/run.sh`)
- The full chain 001→210 applies with 0 failures on a fresh stack. 210 re-applies cleanly, and the rollback removes
  every table, function and switch.
- `test_project.py`: **984 checks, 0 failures**. That's the shared `project-permissions.json` (45 project rows × 10
  actors × both Host definitions, money rows wait for 212-214), all channel vectors, limits == `projectLimits.json`,
  RLS (outsider, removed member, hub off, anon, direct insert, internal helpers), invites, caps, trash, start, versions,
  notifications, decisions, structure proposals, run-of-show time rules, read-only, and a lint that organizer
  owner/second-account columns appear only in `project_host_ids()`.
- Mutation check: removing the Host-only check from `project_host_write` made 48 checks fail. Restored → green.

## Next: phase 3 (iOS shell)
`ProjectTabBar` (icon over label, 5 visible, swipe for the 6th), hub screen, Overview with team channels, Tasks, the
Hosting card "Start a project" and Account "Projects I'm in", against a UI-test fixture (flag off = unreachable).

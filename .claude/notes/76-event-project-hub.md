# 76 — Event Project Hub (Hosting): per-event private team workspace

Status: **phase 1 of 13 IMPLEMENTED LOCALLY, not committed.** Pure logic, shared vectors and switches only. No
migration, no UI, nothing reachable in the app. Plan (approved 2026-11-03):
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

## Next: phase 2 (migration 210, throwaway Postgres only)
Tables, `project_is_host`, RLS, RPCs, invite tokens, channels sanitizer, read-only/purge columns, and the SQL test
suite running `project-permissions.json` twice (v1 body, then `owner_only` body swapped in) plus the channel vectors.

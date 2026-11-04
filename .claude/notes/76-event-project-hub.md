# 76 — Event Project Hub (Hosting): per-event private team workspace

Status: **all 12 build phases (1-9c) done.** Phase 1 (pure logic + switches) c731375; phase 2 (migration 210, throwaway stack only,
APPLIED to production 2026-11-04, see Production log) 47c7b7a; phase 3 (iOS shell) f96091d; phase 4 (iOS Topics, Team, invites, join) 2c7cff9; phase 4b (QR invites) 210f85d; phase 5 (iOS Day-of) b72c199; phase 6 (iOS Money & door, Host) 9e569c9; phase 7 (migration 211 jobs, throwaway stack only, NOT applied to production) 76e7f3c; phase 8 (web parity) df543fd; phase 9a (delegated check-in, migration 212, throwaway stack only, NOT applied to production) 1cbeeb8; security fix migration 213 (verify_payment hole, automatic confirmation removed) bd36f73; phase 9b (delegated payments, migration 214, throwaway stack only, NOT applied) 70ec4f1; phase 9c (delegated refunds, migration 215, throwaway stack only, NOT applied) implemented locally. Nothing is reachable while the switch is off. Plan (approved 2026-11-03):
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

## Phase 3 — iOS shell (IMPLEMENTED LOCALLY; reachable only with `event_project_hub` on)
- **Screens:** `Screen.eventProject` (`Views/Project/ProjectHubView.swift`) and `.myProjects` (`MyProjectsView.swift`),
  routed in RootView, with edge-swipe back cases in `goBack()` (a missing case is a silent no-op, recorded twice there).
- **`ProjectTabBar`:** icon over label, exactly 5 slots at rest through `containerRelativeFrame(count: 5)`, view-aligned
  scrolling, the selected tab scrolled into view. The right-edge fade + chevron follow `.scrollPosition(id:)` (a
  preference-based first try never reported from inside the ScrollView, so the hint never showed). One-word labels
  shrink instead of breaking mid-word. VoiceOver: "Tasks, tab 2 of 6, needs attention".
- **Overview:** proposals banner (Host), team channels card (Host edits, Manager suggests, members open), readiness ring +
  lane bars, needs attention (blocked, then late), coming up, decision log.
- **Tasks:** proposals (Host approves in one tap, declines with a required reason; a Manager sees their own with the
  answer), All | Mine (`GlassSegmentedControl`), add lane (Host) / propose lane (Manager), lanes with a 44 pt tick,
  floating "Add task", task sheet (edit form for Host / Manager / own-lane lead; status-only detail for the assignee;
  delete with a reason), lane manage (rename, archive with a reason once no open task is left).
- **Team** is a read-only roster for now. Topics, Money & door and Day-of show an honest "Coming soon" card
  (phases 4/6/5).
- **Entries:** the Hosting Home hero gets "Start a team project" / "Open project · N tasks for you"; Account (both tabs)
  gets a "Projects I'm in · N" strip. Sign-out clears every project field.
- **Data:** `Models/EventProject.swift` (timestamps kept as strings, read by `ProjectDates.parse`, fractional or not),
  `State/AppState+Project.swift` (open/refresh with `p_since_version`, one `projectWrite` path with plain-words refusals,
  writes for tasks/lanes/channels/proposals/leave; in a DEBUG fixture writes change the in-memory snapshot).
- **Pure presentation:** `Lib/ProjectPresentation.swift` (readiness, lanes, my tasks, attention, coming up, waiting
  on me, due labels and countdown in the EVENT's zone) with shared vectors `tests/fixtures/project-presentation.json` over
  `tests/fixtures/project-snapshot.json`. The snapshot fixture is demo data in the exact RPC shape, and the 210 suite now
  checks its keys against the live `get_event_project` answer.
- **Tokens:** the prototype's green "done" has no token here. Done = filled ink check, doing = honey, blocked = alert, to
  do = ink3 ring, readiness = clay. No new colour was added.
- **Bugs found while testing:** an `.accessibilityIdentifier` on a container stamped every child with the same id (fixed
  with `.accessibilityElement(children: .contain)`). The fixture loader climbed 4 folders instead of 5. At the largest text
  sizes, the banner, channel rows, task tags and the proposal buttons now stack instead of breaking words letter by letter.

### Verified
- `ProjectHubUITests` (11, on the real RootView with `-uiFixture shell.project`, "now" pinned to 3 Nov in the event's
  zone): 5 tabs visible and the 6th by swipe with the hint going away, 5 tabs + 44 pt at AX XXXL, opening on Day-of
  scrolls it into view, VoiceOver labels, Host overview, channel edit (Host) vs suggest (Manager) vs open (helper), tick,
  refusal for a helper on someone else's task, add task, approve proposal, Vietnamese + dark. Screenshots were reviewed
  (light/dark, vi/en, AX XXXL).
- `ProjectPresentationTests` (3) green. Web unit 898/898 (the naming guard also covers the new iOS files and 210). The
  210 SQL suite: 985/985.
- Not checked: a real device, real network calls against a project (210 is not applied anywhere but the throwaway
  stack), light mode of the Tasks tab, iPad.

## Phase 4 — iOS Topics, Team, invites, join (IMPLEMENTED LOCALLY; no migration)
- **Topics** (`Views/Project/ProjectTopicsTab.swift`, `ProjectPostSheets.swift`, `State/AppState+ProjectTopics.swift`):
  collapsible rules card, lane chips, "Waiting on you" (`ProjectPresentation.awaiting`), all posts newest first with
  "Show older" (20 a page; `mergeOlderPosts` keeps opened pages through refreshes). Thread sheet: vote bars (tap again
  takes the vote back), Mark as seen, up to 10 replies, Decide on the leading option (a tie picks the first, as 210 does),
  Resolve for questions, Edit/Delete while the post is quiet, delete needs a reason. "New post" is two steps: the four
  types (dimmed with the reason when the role can't post one), then the form; the small-talk line links the team's
  primary channel. The rules card does NOT mention the 18:00 digest or live sync yet: those come in phases 7 and 5.
- **Team** (`ProjectTeamTab.swift`, `ProjectTeamSheets.swift`, `State/AppState+ProjectTeam.swift`): members with role,
  lane, Money/Check-in tags and open-task count; member sheet (Host: role, lane, two access toggles, remove with reason
  and a "change the channel links" nudge; others read only); invite sheet (Host presets any role, a Manager Lane lead or
  Helper; single use, 48 h; code card, Copy link, Share); live invites with Cancel; "Who can do what" table; privacy card.
- **The table is data** (`Lib/ProjectRoleMatrix.swift`); `ProjectTeamTopicsTests` checks every cell against
  `ProjectPermissions`. Finance's money/check-in cells say ✓ but only take effect once the delegation switches are on;
  the table's footnote says so and a test proves they're off by default.
- **Join** (`ProjectJoinView.swift`, screen `.projectJoin`): `banbe://join/<v>` (`handleDeepLink`), `https://(www.)banbe.app/join/<v>`
  (`handleUniversalLink`; needs `/join/*` in the AASA file, phase 4b), Account's personal row "Join an event team with a
  code" when I'm in no project, and "Have an invite code?" on Projects I'm in. Signed in: `peek_project_invite` card, then
  `project_redeem_invite` opens the project. Signed out: the screen is guest-allowed, the code is parked in UserDefaults
  (`banbe.pendingProjectInvite`, cleared on join and sign-out) and "Log in to join" resumes here through
  `AuthResume.joinProject`. A sign-in that did not start from this screen does not reopen it (the code pre-fills next time).
- **Notifications:** `project_joined`, `project_blocked`, `project_digest` open the project from the bell or a push, only
  after `get_my_event_projects` confirms I'm still in it.
- **Fixtures:** `shell.project` writes posts/replies/members/invites in memory; `shell.projectJoin` with
  `-uiFixtureProjectJoin BB-7K2Q` (live Helper invite), `BB-XPRD` (expired), anything else = not found, `-uiFixtureGuest YES`.
- **Found while testing:** the invite sheet opens at half height, so the new code and buttons were below the fold; it now
  scrolls them into view.

### Verified
- `ProjectTeamTopicsUITests` (18) + `ProjectHubUITests` (11) green on the real RootView. Screenshots reviewed: Topics (en
  dark), Team (vi dark), invite code, resolved thread, helper composer, join (signed in / signed out), Team at AX XXXL.
- `ProjectTeamTopicsTests` (5) green. Web unit 898/898 (naming guard covers the new files). No SQL change (210 suite as
  in phase 2).
- Not checked: a real device, real network calls (210 isn't applied anywhere but the throwaway stack), iPad, light mode.

## Phase 4b — QR invites (IMPLEMENTED LOCALLY; switch `project_qr_invite`, OFF; no migration)
- **Invite sheet with the switch on** (`ProjectTeamSheets.swift`): opens full height, mints an invite at once (no Create
  button) and shows a white QR of the join link + the BB- code + "Expires in 48 hours · single use / up to 20 people", a
  "Single use only" toggle (off = `max_uses` 20; the server refuses more than 1 use while the switch is off), Copy link,
  Share, and "The QR holds only the invite code". Changing role, lane or the toggle mints a new invite 400 ms after the
  last change and cancels the one it replaces; an invite minted after the choices moved on is cancelled unseen. The
  Team button reads "Invite by QR". Switch off = the phase 4 sheet, unchanged.
- **Scanning:** the invitee's "Scan a QR code" on the Join screen (`ProjectInviteScanSheet`, reuses `CameraPreview`), and
  the door scanner (`QRScannerView`) hands an invite QR to the Join screen instead of looking it up as a ticket. Both
  accept only the full link (`ProjectInviteLink.joinLink` ⇄ web `parseJoinLink`, shared vectors `joinLink` in
  project-invite-links.json), so a booking id can never be read as an invite. A pasted or scanned link is normalised to
  the bare token/code before peek/redeem (`AppState.projectInviteValue`): 210's `project_invite_value` takes no URLs.
- **AASA:** `public/.well-known/apple-app-site-association` now lists `"/join/*"` next to `"/u/*"`. NOT deployed. Until a
  web deploy (and a build with Associated Domains and the real Team ID; the file still says `TEAMID`), a phone camera
  opens `https://www.banbe.app/join/…` in the browser, and the web has no `/join` route before phase 8.
- Camera permission text now also names "to scan an event team invite" (project.yml + Info.plist).
- `CardSheet` gained `fullHeight` (default false, nothing else changed).

### Verified
- `ProjectQRInviteUITests` (4, `-uiFixtureProjectQR YES`, `-uiFixtureProjectScan` instead of a camera), the 18 phase 4 UI
  tests, `ProjectInviteLinkTests` (4) and `ProjectTeamTopicsTests` (6) green. Web `projectInviteLink` 5/5.
- Not checked: a real camera scan, a universal link opening the app (needs the deploy + signing above).

## Phase 5 — iOS Day-of (IMPLEMENTED LOCALLY; no migration)
- **Tab** (`ProjectDayOfTab.swift`): the event week (7 days ending on the event day, in the event's zone, open tasks
  due per day, ★ on the day; a tap lists that day's tasks), the event-day card ("Live now · every 15 s" on the day,
  otherwise when it will be live) with "Join call" for the primary channel, List | Calendar, "Add item" for the Host and
  Managers. List rows: event-zone time, title (struck through when done), owner, "+N′" while running over, edit (editors)
  and a 44 pt tick (everyone).
- **Time grid** (`ProjectRosGrid.swift`): hour lines, blocks placed by `RosLayout` (phase 1, fixture-tested port of
  v6 layoutDay), now line, legend, "Versus the plan" chips, "Jump to now" (scrolls the hub through the
  `projectScrollTo` environment hook). Redrawn every 30 s by a TimelineView so an unticked item visibly stretches.
  Tokens: active = clay, overrun = alert, squeezed = honey, done = inset/ink3 (no moss token). Taller scale at AX sizes.
- **Sheets** (`ProjectDayOfSheets.swift`): item add/edit (name 2–40, start/end pickers in the event's zone limited to the
  server window [start − 12 h, start + 24 h], moving the start keeps the length, end ≥ start + 10 min, owner), delete
  with a reason; Trash (⋯ menu, Host and Managers): tasks, posts, items, archived lanes, Restore; purge for the Host.
- **Poll** (`AppState+ProjectDayOf.swift`, ProjectHubView `.task(id: live)`): `get_event_project_ros` every 15 s only
  while the hub is open on Day-of, the app is active (`scenePhase`) and it is the event day in the event's zone. The
  poll keeps its own `projectRosVersion`, so it never makes a later full refresh answer {unchanged} for other changes.
- Tick time comes from the server (`project_tick_ros_item`), never the phone.
- Fixture: `-uiFixtureProjectNow 2026-11-14T18:10:00+07:00` = event day, the first item 40 minutes over and the next
  squeezed by 40.

### Verified
- `ProjectDayOfUITests` (7) + `ProjectHubUITests` (11, Day-of placeholder check updated) green; `ProjectDayOfTests` (2) and
  `RosLayoutTests` green; iOS unit 555 with only the known GiftTicketPDF failure; web unit 899/899. Screenshots reviewed:
  list (3 Nov), live grid (event day, en dark and vi dark), trash, grid at AX XXXL.
- **Found while testing:** at AX XXXL the grid's hour labels broke one character per line and the plan chips were cut
  off. The grid is now capped at `accessibility1` (spatial layout; the List keeps full Dynamic Type and each block reads
  everything to VoiceOver), hour labels stay on one line, and the chips stack and wrap. The week strip says "1 due", not
  a bare "1".
- Not checked: the poll against a real backend (210 not applied), a real event day, iPad.

## Phase 6 — iOS Money & door (IMPLEMENTED LOCALLY; no migration, nothing new on the server)
- **Host** (`ProjectMoneyTab.swift`, `State/AppState+ProjectMoney.swift`): Confirmed amount (VND; paid USD booking is off),
  Awaiting a check, Refund asks; "Act on it" rows that open the EXISTING screens with Back returning to the project:
  Check payments → `openVerifications`, Refunds → `openVerificationsRefunds`, Door check-in → `openAttendance` (with
  "N/M seats in"); Team access (members holding money/check-in, "takes effect once banbe turns it on"); "payout and
  cancelling stay with you". The Money tab shows a dot while guests wait or refunds are open (loaded with the project).
- **Data:** read only, what the Host can already read: the event's `bookings` (RLS) and `get_host_refund_claims`
  (via `loadRefundCenter`, so only uuid event ids get refund counts). Rules in the pure
  `AppState.projectMoneySummary` (expired unpaid holds are nobody's seat; an expired hold marked paid still waits for a
  check; only owed/disputed claims count). Access = `projectCan("money.view")` = the existing organizer-account check.
- **Everyone else:** the v6 lock card with who has access; a member the Host granted money or check-in is told it isn't
  on yet (delegation = migrations 212–214, phases 9a–9c). No amounts are ever loaded for them.
- **Found while testing:** the lock card's id merged into the tab's (only child), now on its title; at AX XXXL the stat
  tiles and action rows broke words ("Await-ing"), now one tile per line and stacked rows without the chevron.

### Verified
- `ProjectMoneyUITests` (5: Host numbers + dot, Check payments → Verifications → Back to the tab, helper lock, Finance
  "not on yet", vi dark + AX XXXL), `ProjectMoneyTests` (1), `ProjectHubUITests` (11) green. iOS unit 556 with only the
  known GiftTicketPDF failure; web 899/899. Screenshots reviewed.
- Not checked: real numbers against a backend (210 not applied), Attendance and the refund section opened from here on a
  device.

## Phase 7 — migration 211 jobs (LOCAL HARNESS ONLY, NOT applied to production)
- `supabase/migrations/20261231000211_211_event_project_jobs.sql` + rollback `supabase/rollbacks/20261231000211_211_revert_event_project_jobs.sql`.
- **`send_project_digests(p_now)`**, cron `bb_project_digest` `7 * * * *`: at `digestHour` (18) on each person's own clock
  (`user_local_zone`, the weekly digest's rule), at most one per person per local day (`event_project_digest_log`),
  only while `event_project_hub` is on, muted by `project_digest` in `muted_notification_kinds`, silent when nothing.
  Counts per open project (`project_digest_items`): my open tasks due by tomorrow in the EVENT's zone (late included),
  posts waiting on me (question to me, proposal I haven't voted on, update/decision I haven't seen; never my own), and
  for a Host (both organizer accounts) blocked tasks. Read-only projects and cancelled/removed events are skipped. It
  opens the project with the most waiting (`data.screen = event_project`, already routed on iOS since phase 4).
- **`purge_project_data(p_now)`**, cron `bb_project_purge` `17 20 * * *` (03:17 in Vietnam): projects 90 days after the
  event end (everything cascades; the event, bookings, payments and refunds are other tables), trash older than 7 days
  (an archived lane takes its remaining done tasks/posts, same as the Host's purge in 210), invites expired or revoked
  over a day ago, invite attempts over a day old, digest log over 14 days.
- **Read-only** needed no job: `project_guard()` already compares `now()` with `project_read_only_at()`.
- `project_limits()` gains `digestHour` (the rollback restores 210's body). Kinds `project_digest`, `project_blocked`,
  `project_joined` added to `notification_kind_policy` as service (never promotional). All three functions revoked from
  anon/authenticated.
- **Text is Vietnamese only**, like the weekly digest; 142's `localize_notification_text` has no pattern for it yet, so
  English readers see Vietnamese until one is added (flag for later).
- The iOS Topics rules card now names the 18:00 digest.

### Verified (throwaway stack)
- `supabase/tests/211_project_jobs/run.sh` (reuses the 210 seed): 38/38. A mutation run (no hour check, blocked count
  for everyone) failed exactly the 3 checks that guard them. The 210 suite: 985/985 after making its rollback check run
  211's rollback first (rollbacks go newest first).
- Not checked: pg_cron firing on its own (functions called with an injected `p_now`), push delivery of the digest.

## Phase 8 — web parity (IMPLEMENTED LOCALLY; no server change)
- **State:** `src/state/useEventProject.js` (hook over BanBeContext's `set`; one function per iOS write, same RPCs, same
  refusal texts). New context keys (`projectSnapshot`, `projectTab`, `myProjects`, `projectJoin*`, `projectMoney`, ...) in
  `initialState`, and the account-owned ones in `PRIVATE_STATE_KEYS` so sign-out clears them. Dev-only demo mode
  (`window.__banbeDevSet({ projectDemo: true, ... })`, ignored outside `import.meta.env.DEV`) makes writes local for tests.
- **Pure logic:** `src/lib/projectPresentation.js` (twin of ProjectPresentation.swift; `projectCan` from a snapshot,
  `moneySummary`, `projectInviteValue`) on the shared project-presentation.json vectors; `src/lib/projectRoleMatrix.js`
  (same rows as ProjectRoleMatrix.swift, a test compares the row ids and checks every cell against `canProject`).
- **Screens:** `src/screens/EventProject.jsx` (bar, six tabs with exactly five visible: slot width measured from the row,
  edge fade/chevron, notice, read-only banner, Add task / New post), `src/components/project/` (ProjectUI,
  ProjectOverviewTasks, ProjectTopics, ProjectTeam with QR invites behind `project_qr_invite` via npm `qrcode`,
  ProjectMoney linking to the existing Verifications / refunds / Attendance with Back to the project, ProjectDayOf with the
  `rosLayout` grid, the 15 s poll gated on `document.visibilityState`, item sheet and trash, ProjectSheets),
  `src/screens/ProjectJoin.jsx`, `src/screens/MyProjects.jsx`.
- **Routes** (`src/lib/routes.js`): `/e/<event id>/project`, `/join/<token or BB- code>`, `/join`, `/projects`. A signed-out
  `/join/…` link opens Join after the splash/Welcome (`useUrlSync` guest rule); the code is kept in localStorage and
  Login returns to Join (`authReturnScreen`).
- **Entries:** Hosting Home hero row "Start a team project" / "Open project · N tasks for you"; Account Activity row
  "Projects I'm in" or "Join an event team with a code"; bell routing for `project_joined` / `project_blocked` /
  `project_digest` after `get_my_event_projects` confirms membership.
- **Not on web:** an in-app camera scanner for invite QRs (people scan with the phone camera; the link opens Join).

### Verified
- `tests/event-project.spec.js`: 15 tests × Chromium/Firefox/WebKit = 45 passed twice in a row (one earlier run had a single
  unrepeated flake). Run WITHOUT the service-role key (`SUPABASE_SERVICE_ROLE_KEY= npx playwright test ...`) so the
  global setup never touches the shared production test account. Screenshots reviewed (en light, vi dark, grid, QR).
- Web unit 905/905 (new projectPresentation + projectRoleMatrix tests, naming guard over the new files); `vite build` OK.
- Not checked: the web against a real backend (210/211 not applied), keyboard-only navigation of the sheets, screen
  readers on the web.

## Phase 9a — delegated check-in (migration 212; LOCAL HARNESS ONLY, NOT applied; switch `project_delegate_checkin`, OFF)
- `supabase/migrations/20261231000212_212_delegated_checkin.sql` + rollback `supabase/rollbacks/20261231000212_212_revert_delegated_checkin.sql`
  (puts 151's `check_in_guest` back verbatim; KEEPS `event_money_audit`, whose rows follow the booking).
- **Who:** an active member who is Finance & door or has `cap_checkin`, while `event_project_hub` AND
  `project_delegate_checkin` are on, the grant is live (`grant_expires_at`, default event end + 7 d) and the project is not
  read-only, on an event that is not cancelled/removed (`project_delegate_ok`). `can_event_capability(event, cap)` = the
  EXISTING organizer-account check OR admin OR that delegate rule (never `project_is_host`).
- **`check_in_guest`:** 151's body with every original line kept in order (a test proves it); delegation is only tried
  when the original check fails, and each delegated admission writes ONE `event_money_audit` row (`checkin`). The Host
  path writes no audit row and behaves exactly as before.
- **Names only:** `get_event_checkin_names(event)` = booking id, attendee id, name, party, checked in (no amount, code,
  token, proof or birth date). **Decision for the owner's review:** the scanner path for delegates is a NEW
  `project_checkin_lookup(code)` that answers name + `meets_min_age` (from `events.details.min_age`) instead of the date of
  birth; the Host-only `get_checkin_guest_info` (DOB, rate-limited, logged) is untouched. Policy B4's draft says "names only,
  no amounts"; it does not cover ages, so the delegate sees a yes/no, never the date.
- **Not delegated:** `undo_check_in`, `reject_pending_guest`, cancel, payout (unchanged).
- **Grants:** `project_extend_grants(event, until, member?)` (Host only, never past `read_only_at`, one audit row
  `extend_grants`). The "team access ended" notice listing open refunds belongs with refunds (9c).
- **`event_money_audit`:** shared with 213/214. SELECT for the event's organizer accounts and admins only; no client
  INSERT/UPDATE/DELETE; written by `event_money_audit_add` (server-only).
- **Apps:** iOS `ProjectDoorList` (in ProjectMoneyTab) and web `Door` (ProjectMoney.jsx): count "N of M people in",
  search, one Check in per party (`check_in_guest` 'manual' admits everyone in it not yet in), "Names only. Money and
  refunds stay with the Host. Every check-in is recorded". No delegate scanner UI yet (the RPC is ready).
- **Found while testing:** the door list's accessibility id merged into the tab's (only child) like the lock card in phase 6;
  a seed `details` value needs `{"v": 1}`.

### Verified (throwaway stack)
- `supabase/tests/212_delegated_checkin/run.sh`: 58/58 (switch off = nothing changes, every role on/off, names-only shape,
  one audit row per person, expired/read-only/cancelled/hub-off refusals, undo not delegated, lookup without a birth date,
  extension caps, audit table private and append-only, verbatim 151 lines, re-apply, rollback). A mutation run (switch
  ignored, audit insert removed) failed exactly the 7 checks guarding them. 210: 985/985 (rollbacks now run 212 → 211 →
  210); 211: 38/38.
- iOS: `ProjectMoneyUITests` 7 (door list + needs access and switch), `ProjectDoorTests` 1. Web: `tests/event-project.spec.js`
  16 × 3 browsers = 48/48; unit 906/906; build OK.
- Not checked: a real event night, a delegate on a real device, the policy text (B4 amendment is a draft for legal review).

## Before 9b — migration 213: the verify_payment hole, and automatic confirmation removed (LOCAL ONLY, NOT applied)
- **Found while planning 9b:** `verify_payment()` (026, never redefined) skipped its organizer check when
  `p_actor_kind` was `'webhook'` or `'system'`, and EXECUTE was granted to every signed-in user. Any account could mark any
  guest's payment confirmed (ticket issued, receipt raised) without paying. Proven on the throwaway stack (rolled back);
  production NOT queried. 183 had locked `record_bank_transaction` / `verify_payment_from_bot` but not `verify_payment`.
- **Owner decision (2026-11-04):** fix it first, and remove automatic payment confirmation entirely (Telegram and the bank
  feed), because it is no longer needed. **Same day, later:** the owner asked for the Casso/PayOS bank feed back ("Add
  again Casso/PayOS, dont need to test"); Telegram stays removed. See the restore line below.
- `supabase/migrations/20261231000213_213_remove_auto_payment_confirmation.sql`: `verify_payment` = 026's body without
  the bypass (every caller must be an organizer account of the event or an admin; an old client sending `'webhook'` as
  the owner still works and is logged as `organizer`); drops `verify_payment_from_bot`, `record_bank_transaction`,
  `save_organizer_alert_routing`, `v_alert_queue`; unschedules `bb_sweep_verification_slas` (it only queued Telegram
  reminders). Kept: `payment_webhook_events`, `alert_outbox`, `organizers.telegram_chat_id` / `alert_phone`, the sweep
  function. Rollback `supabase/rollbacks/20261231000213_213_revert_remove_auto_confirmation.sql` restores 026 + 027 + 183
  ACLs (WITH the hole; emergency only, with the code).
- **Code removed:** `api/payment-webhook.js`, `api/telegram-webhook.js`, `api/_lib/alerts.js`,
  `api/_lib/handlers/cronEscalateVerifications.js`, the `escalate-verifications` job in `api/cron.js` and `vercel.json`.
  The guest's payment hint no longer promises automatic reconciliation (web PaymentDetails, iOS PaymentViews); stale
  comments updated. `TELEGRAM_*` secrets in Vercel are no longer used (owner may delete them).
- **Bank feed restored (owner, 2026-11-04, NOT tested at the owner's request):** 213 no longer drops
  `record_bank_transaction` (service-role only since 183); `api/payment-webhook.js` is back unchanged from before 213
  (Casso `CASSO_WEBHOOK_SECRET`, PayOS `PAYOS_CHECKSUM_KEY`, generic `BANK_WEBHOOK_SECRET`; keep those Vercel secrets).
  `verify_payment` (213, and its copies in 214 and 214's rollback) sets `v_bank := p_actor_kind = 'webhook' AND
  auth.role() = 'service_role'` and skips the organizer check only then; the confirmation is logged as `webhook` with
  the "tự động đối soát qua ngân hàng" chat line. A signed-in user claiming 'webhook' is checked like anyone else. The
  guest hint again mentions automatic confirmation, now "if the host has connected their bank". The 213 test file's
  expectations were updated (bank feed kept, service-role confirm) but the suites were NOT re-run.
- **Numbering:** delegated confirm-payment is now migration **214** (9b), delegated refunds **215** (9c).
- **Verified (throwaway stack):** `supabase/tests/213_payment_confirmation/run.sh` 31/31 (strangers refused whatever kind
  they claim, project members refused, anon cannot call; owner, second account and admin confirm; idempotent; dropped
  objects gone, history kept; re-apply; rollback brings 026 back, proving the hole existed). 210 985/985, 211 38/38,
  212 58/58; web unit 906/906, build OK; iOS build OK.
- **Owner follow-ups:** apply 213 to production through the usual routine (backup, apply, grant audit, check); optionally
  look for bookings confirmed by a non-organizer (`payment_audit_log` actor_kind 'webhook'/'system' with an actor that is
  not an organizer account) to see whether the hole was ever used.

## Phase 9b — delegated payment confirmation (migration 214; LOCAL HARNESS ONLY, NOT applied; switch `project_delegate_payments`, OFF)
- `supabase/migrations/20261231000214_214_delegated_payments.sql` + rollback `supabase/rollbacks/20261231000214_214_revert_delegated_payments.sql`
  (puts 213's `verify_payment` and 060's `confirm_payment` back verbatim; restores 211's `project_limits()`).
- **Who:** an active member who is Finance & door or has `cap_money`, with `event_project_hub` + `project_delegate_payments`
  on, a live grant and a project that is not read-only (`project_delegate_ok(.., 'money')` from 212).
- **`verify_payment` (Verifications' "Money received") and `confirm_payment` (Attendance's accept):** every original line
  kept in order (tested); a delegate is only tried when the organizer/admin check fails, and ONLY for a booking in
  `pending_verification` (the guest said they paid). Not for holds, disputes or anything else. One `event_money_audit` row
  (`confirm_payment`) per delegated confirmation; the Host path writes none. `verified_by` = the delegate.
- **Not delegated (M3):** `reject_payment` ("Can't find it") and `reject_pending_guest`; refunds (215), cancel, payout.
- **`get_event_money_view(event)`:** confirmed amount and seats, and the bookings awaiting a check with name, seats, amount,
  payment reference, when they said they paid, and `has_proof` (a yes/no, never the path). No invoices or receipts.
- **Transfer proofs (N3, M2):** `open_payment_proof(booking)` (delegates only; the Host keeps `pay_proof_read`) works only
  for a booking in `pending_verification` with a proof, writes a `proof_open` audit row and returns the path. The new
  storage policy `pay_proof_read_delegate` (via the boolean-only definer helper `pay_proof_delegate_ok`) lets that delegate
  read that one object for `proofOpenMinutes` (5) after their audit row, while the booking is still waiting and their
  delegate rights hold. `payment-documents` is never reachable. The app signs a `proofUrlSeconds` (60) link and shows it
  with no share/save controls; that part is a UI rule only (a screenshot is always possible).
- **Apps:** iOS `ProjectPaymentsList` + `ProjectProofSheet`, web `Payments` (ProjectMoney.jsx): "Payments to check" with the
  confirmed total, per booking amount + reference, "View transfer proof" (only when one exists) and "Money received",
  above the door list when the person has both. **Bug fixed from 9a:** the tab chose the Host view by `money.view`, which a
  delegate also passes once 214's switch is on; it now also requires `is_host` (iOS `projectMoneyAccess`, web `moneyAccess`).

### Verified (throwaway stack)
- `supabase/tests/214_delegated_payments/run.sh`: 61/61 (switch off = no change; every role on/off; view shape without
  paths or documents; one audit row per confirmation on both RPCs; holds/disputes refused; expired, read-only and wrong-switch
  refusals; rejects stay with the organizer; proofs: unreadable before opening, readable after, only that booking, never
  payment-documents, closed after 5 minutes, after settling and when the switch goes off; Host and guest still read via
  pay_proof_read; originals verbatim; re-apply; rollback keeps 213 closed). Mutation runs: dropping the
  pending_verification rule failed 2 checks; a proof helper that ignores the audit failed 4. 210 985/985 (rollbacks
  214 → 212 → 211 → 210), 211 38/38, 212 58/58, 213 31/31.
- iOS `ProjectMoneyUITests` 9 + unit tests; web `tests/event-project.spec.js` 17 × 3 = 51/51, unit 906/906, build OK.
- Not checked: a real proof image through a real signed URL, a real event, the policy text (the B4 amendment naming
  money delegates and transfer proofs is a draft for legal review).

## Phase 9c — delegated refunds (migration 215; LOCAL HARNESS ONLY, NOT applied; switch `project_delegate_refunds`, OFF)
- `supabase/migrations/20261231000215_215_delegated_refunds.sql` + rollback `supabase/rollbacks/20261231000215_215_revert_delegated_refunds.sql`
  (puts 128's `mark_refund_sent`, 211's `purge_project_data` and 214's `project_limits()` back verbatim; drops the new
  tables, functions, policy and column; keeps `event_money_audit` and its widened action list).
- **Who:** an active member who is Finance & door or has `cap_money`, with `event_project_hub` + `project_delegate_refunds`
  on, a live grant and a project that is not read-only (`project_refund_member_ok`). Unlike check-in and payments, a
  **cancelled** event still counts (cancelling is what creates most refunds); a removed one does not.
- **Approval mode (N1), `event_projects.refund_approval`:**
  - `host` (default): the delegate records the transfer with `request_refund_send` (note ≤ 280, optional receipt under
    `refund-proof/<claim_id>/`). The guest is told nothing yet. Both organizer accounts get `project_refund_request`.
    The Host runs `approve_refund_send` (which calls `mark_refund_sent` as the Host, with the team's note and receipt) or
    `decline_refund_send` with a reason (3–140); the person who recorded it gets `project_refund_declined` and may record
    again. One pending record per claim. A record made before the delegate's grant ended stays approvable.
  - `finance_alone`: the delegate may call `mark_refund_sent` directly. A delegate calling it under `host` gets
    `APPROVAL_REQUIRED`. Only the Host switches (`project_set_refund_approval`); each real switch writes one audit row.
- **`mark_refund_sent`:** every line of 128 kept in order (tested). The delegate is only tried when the organizer check
  fails; the Host path is unchanged and writes no audit row. A Host marking sent directly closes a waiting team record.
  128 already accepted claims in `disputed` status (this settles the plan's UNVERIFIED item). Reservation-based claims
  (`COALESCE(booking_id, reservation_id)`) take the same path everywhere in 215.
- **Not delegated:** `resend_refund_transfer_info`, the batch runner, every dispute RPC and dispute chat, cancel, payout.
- **`get_event_refund_view(event)`:** open claims (`owed`/`disputed`) with name, amount, due date, `dispute_open`, the
  guest's refund account (bank, number, holder: needed to send the money), the waiting record and my last decline reason.
  Never a refund proof, payment proof, claim note or document. Delegates cannot read `refund-proof` back
  (`refund_proof_read` unchanged); they can only upload into an open claim's folder (`refund_proof_delegate_insert`).
- **Dispute grants (M5):** `project_extend_dispute_grant(event, user, claim, until)`, Host only, only while the claim has an
  open `dispute_threads` row (`resolved_at IS NULL`), `until` ≤ now + `disputeGrantMaxDays` (30) per extension, only for
  someone who holds (or held, by an earlier dispute grant) money access; never for a removed member. Stored in
  `event_dispute_refund_grants`, so it outlives the project's read-only date and purge. Covers that claim's refund
  actions only (request; mark sent under `finance_alone`); not check-in, payments, proofs or chat. Dead the moment the
  dispute is resolved, the switch goes off or the person is removed. **Found while testing:** `project_limits()` had no
  `disputeGrantMaxDays` (JSON had it), so the cap was NULL and never enforced; 215 adds it.
- **"Team access ended" notice:** the daily `purge_project_data` sends both organizer accounts one `project_grants_expired`
  when every money delegate's grant is over and refunds are still open ("N refunds are back with you"), once per project
  (`event_projects.grants_expired_notified_at`); silent while nothing is open, so a later claim still triggers it.
- **Audit actions added:** `refund_decline`, `extend_dispute_grant` (with `refund_request`, `refund_approve`,
  `refund_mark_sent`, `set_refund_approval` from 212's list).
- **Notification kinds:** `project_refund_request`, `project_refund_declined`, `project_grants_expired` (service). Deep link
  `{screen: 'event_project', event_id, tab: 'money'}`.

### Verified (throwaway stack)
- `supabase/tests/215_delegated_refunds/run.sh`: 112/112 (switch off = no change; every role; list shape without proofs or
  notes; Host approval flow end to end incl. notices and audit; decline needs a reason; bad records; mode switch Host-only
  and audited; finance_alone; expired grant, wrong switches, cancelled vs removed events; dispute grants: caps, scope, dies
  on resolve/expiry/removal/switch off, survives purge, renewal; receipt upload allowed/denied; the notice: once, both
  accounts, not while a grant is live or the switch is off, silent with nothing open; originals verbatim; grants; re-apply;
  rollback). Mutation runs: dropping the APPROVAL_REQUIRED rule failed 4 checks; a dispute grant that ignores the open
  thread failed 1. 210 985/985 (rollbacks 215 → 214 → 212 → 211 → 210), 211 38/38 (its kind checks narrowed to its own
  three kinds), 212 58/58, 213 31/31, 214 61/61.
- Not checked: a real receipt upload through the app to real storage, a real event, the policy text (B4 amendment naming
  refund delegates and the guest's refund account is a draft for legal review).

### Apps (9c)
- **Delegate ("Refunds to send", Money & door tab, between "Payments to check" and the door list):** shown to non-Hosts
  allowed `refund.request` or `refund.markSent`. Rows: name, amount, due date in the event zone, "Disputed" pill; states
  "Waiting for Host" / "You recorded this · waiting for the Host" (no button), "Host declined: <reason>" (can record again),
  no refund account (button off, reason shown), empty "No refunds to send". Sheet: amount, bank / number / holder each with
  Copy, optional note (280), "Attach receipt" (uploads to `refund-proof/<claim_id>/`, same image rules as the Host's
  receipt; only "Receipt attached" is shown back). Button follows the mode: "Record transfer for Host approval" ("The guest
  is told only after the Host approves.") or "Mark refund sent" ("The guest is told right away.").
- **Host (below the summary):** "Refunds from the team" card (who recorded it, note, receipt flag; Approve with a
  confirmation, Decline with a required reason 3–140), "Refund approval" two-option control (confirmation before
  "Finance can refund alone"; only while `project_delegate_refunds` is on), "Let the team handle this refund" on open
  disputes (one Finance/money member, 7/14/30 days; end time sent one minute under the 30-day cap).
- iOS: `State/AppState+ProjectRefunds.swift`, `Views/Project/ProjectRefundsViews.swift`; the Host's receipt upload was
  pulled out of `markRefundSent` into `uploadRefundProof(_:claimID:)` (same behaviour); fixtures
  `-uiFixtureProjectRefunds YES` and `-uiFixtureProjectRefundMode finance_alone`; at AX sizes the amount moves under the name.
- Web: `useEventProject.js` (`refundsAccess`, `loadRefunds`, `sendRefund`, approve/decline/mode/dispute grant, demo data),
  `ProjectMoney.jsx`, pure helpers `refundRowState`, `teamRefundRequests`, `refundDelegates`, `teamGrantsOver` in
  `projectPresentation.js`; `projectRefunds` in BanBeContext initial state and the sign-out reset.
- **Known limits:** the snapshot has no per-member grant end dates, so the dispute hand-off shows when the project is
  read-only or the default grant (event end + 7 days) has passed; someone whose ONLY access is a dispute grant does not get
  the list in either app (the server would accept their calls); the Host card loads only while the switch is on; a failed
  Host refund load on web shows an empty card, not an error.
- **Verified:** iOS unit 11/11 (`ProjectRefundsTests` 3 new, Money, Door, Permissions, Limits), `ProjectMoneyUITests` 18/18
  (9 new), AX XXXL screenshots checked; web unit 909/909, Playwright `tests/event-project.spec.js` 63/63 (21 × 3, 4 new
  cases), build OK; naming guard green. **Not checked:** RPCs and the receipt upload against a real Supabase (215 is applied
  nowhere), a real device, VoiceOver, clipboard and photo picker by hand, Vietnamese sheet text on screen.

## Production log (2026-11-04, UTC): migrations 210–215 APPLIED (owner: "please apply your created migrations on the production")
- **Before:** production had every migration through 209 except 182–184 (held back on purpose, unchanged). The audit
  confirmed the 213 hole was LIVE: `verify_payment` and `mark_refund_sent` were executable even by `anon`.
- **Change made for production:** 183 (which locked `record_bank_transaction` to the service role) is not in production, so
  213 now revokes it from PUBLIC/anon/authenticated and grants service_role itself (bank feed trusts `p_signature_ok`).
- **Local re-run first (throwaway g-db, 213–215 rebuilt):** 210 985/985, 211 38/38, 212 58/58, 213 33/33 (incl. the
  service-role bank-feed confirm), 214 61/61, 215 112/112.
- **Backup:** `supabase db dump --linked` → `~/banbe-backups/2026-11-04-pre-210-215/` (schema.sql SHA-256 prefix
  b6debe9e5679f5d2, data.sql 12dc028d5fade33c; chmod 600, outside the repo, contains personal data).
- **Dry run:** production SCHEMA restored into a fresh `supabase/postgres:17.6.1.166` container (storage schema copied from
  the local stack; one harmless restore error, `auth.sessions`); 210 → 215 each applied cleanly in its own transaction.
- **Applied, one migration per push** (workdir = production's applied set + the target; every dry run listed exactly that
  one file): 210 at 11:59:22, 211 at 12:00:07, 212 at 12:00:10, 213 at 12:00:13, 214 at 12:00:17, 215 at 12:00:20.
- **Audit after each:** no new function or table open to anon; RLS on all 17 project/money tables; every project switch
  false (event_project_hub, project_qr_invite, project_delegate_checkin/payments/refunds); 0 projects; jobs
  `bb_project_digest` + `bb_project_purge` scheduled (211), `bb_sweep_verification_slas` gone (213); `record_bank_transaction`
  not executable by authenticated. After 213 `verify_payment` lost its anon grant; after 215 `mark_refund_sent` too.
- **Functional check (DO block that always ends in RAISE, so nothing persisted):** a stranger (authenticated, random id)
  calling `verify_payment` on a real confirmed booking with `'webhook'` and with `'system'` → NOT_AUTHORIZED both; anon
  EXECUTE false. **The hole is closed in production.**
- **Live API:** recorded as applied in `migration list`; through the live REST API (the key in the live bundle) the new RPCs
  and `verify_payment` answer 42501 permission denied to anon (known to the schema cache, closed to anon). The OpenAPI root
  is refused for anon keys ("Invalid API key"), so the memory's OpenAPI check no longer works with the anon key.
- **Not done:** no switch turned on; the bank feed (Casso/PayOS) was not exercised against production; the web app with the
  9b/9c UI is in main, but nothing reaches the hub while `event_project_hub` is off.

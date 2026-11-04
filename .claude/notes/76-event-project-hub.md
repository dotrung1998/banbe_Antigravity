# 76 — Event Project Hub (Hosting): per-event private team workspace

Status: **phases 1-7 of 13 done.** Phase 1 (pure logic + switches) c731375; phase 2 (migration 210, throwaway stack only,
NOT applied to production) 47c7b7a; phase 3 (iOS shell) f96091d; phase 4 (iOS Topics, Team, invites, join) 2c7cff9; phase 4b (QR invites) 210f85d; phase 5 (iOS Day-of) b72c199; phase 6 (iOS Money & door, Host) 9e569c9; phase 7 (migration 211 jobs, throwaway stack only, NOT applied to production) implemented locally. Nothing is reachable while the switch is off. Plan (approved 2026-11-03):
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

## Next: phase 8 (web parity)

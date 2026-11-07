# 44 — iOS public entry, auth motion, Schedule tab, Apple Calendar export, report breakdowns (2026-10-17)

Status: IMPLEMENTED LOCALLY (iOS only), NOT committed/pushed/deployed. No DB/RPC/migration/Supabase/web change. Builds on note 43 (commit 0d6bc88). Simulator-verified with DEBUG fixtures only.

## Public entry vs returning users
- New `Screen.welcome` (guest-allowed). Signed out after splash (+ first-device language/theme) → `.welcome`; normal sign-out → `.welcome` (not Login). Signed in → never sees it (`PublicEntryRouting.destination`).
- Welcome = ONE screen: headline + sentence + static illustration (bundled catalogue photos + For You chip), **Get started** (→ Login on Sign up) and an equally visible **Already have an account? Log in** (→ Login on Log in, zero intermediate pages). Language/theme pills on top.
- Optional "See how banbe works": 2 pages, Back / Skip / progress, never auto-advances; last page shows both CTAs. Opening it sets device-local `banbe.publicStory.seen.v1`; afterwards the link is de-emphasised ("How banbe works"). Nothing ever replays automatically.
- Login mode is a route intent (`app.authIntent`, set by `openAuth(_:from:)`), not a view-local default. Typed email/display name live in `authDraftEmail/authDraftName` (never passwords/codes) so Back to welcome or Log in ↔ Sign up keeps them; cleared on sign-in.
- Protected screen while signed out (RootView guard, now `PublicEntryRouting.protectedRedirect`): Login directly, return to that screen after sign-in, Back → `.welcome`. `requireAuth(returnTo:backTo:)` unchanged. `authMandatory` is now always false (Login always has Back); edge-swipe stays disabled on `.login` and `.welcome`.
- Unchanged: splash, policy consent, OAuth/OTP/password/reset semantics, account gates, gift claims, Face ID, personalization markers, deep links.

## Motion
`AuthMotion` (Lib/PublicEntry.swift): welcome ↔ story ↔ Login and Log in ↔ Sign up headline = asymmetric 28pt slide + fade, 0.2s easeOut, Back reverses; Reduce Motion → 0.12s cross-fade only. RootView special-cases only `.welcome`/`.login`; every other screen keeps its existing transition. Schedule day/mode changes = 0.15s opacity (none under Reduce Motion). No auto-advance, parallax, bounce or scale. VoiceOver focus moves to the new heading on story page changes.

## Dock: Schedule replaces Notifications (still five)
Order `Home — Map — Schedule — Messages — Account` (`BottomTabBar.dockOrder/visibleScreens`, item id `schedule`, new `ScheduleGlyph`, `RootTabOutline .schedule`). No sixth tab, no new window/overlay; DockCreateButton/overlay architecture untouched.
Notifications kept in full (screen, polling, badges, every `back: .notifications` deep-link destination): Home header bell `home.notifications` with unread badge (text + spoken count), Account row `account.notifications` (+ Account search entry), Action Center "See all". It is now a pushed screen with its own Back (`notificationsBack`, `notifications.back`). Rationale: five-slot custom dock (scrub hit-testing is 1/count slices) vs Apple's ≤5 guidance; Schedule is a daily destination; nothing in the repo made Notifications operationally dock-only.

## Schedule (Lib/SchedulePresentation.swift, State/AppState+Schedule.swift, Views/ScheduleView.swift)
- Sources, strongest first, one row per event: **booked** (status pending/confirmed/attended + payment confirmed = `isGoing` rule) > **awaiting** (pending_verification) > **holding** (unexpired hold only) > **hosting** (own organizer's non-cancelled events via `myOrgEvents`) > **added** (manual). Excluded: cancelled events, cancelled/expired bookings, **tickets gifted to someone else** (`giftedAt != nil && claimedBy != me`). Undated plans are counted in a note, never silently dropped. Past booked/hosted events stay on their day as history.
- **Favorites/Saved are NOT a source** (they mean bookmarked, not "going").
- Manual "Add to banbe Schedule" = **device-local** `InAppCalendarStore` (UserDefaults `banbe.schedule.added.v1.<uid>`, event ids + addedAt only). Does NOT sync across devices or to web. Namespaced per account; in-memory list reset on sign-out/account switch (entries stay on the device for that account, invisible to others). Idempotent; becomes "In My schedule" from any source; Remove only for manual adds.
- Discover = upcoming, public, live, not sold-out/invite-only/cancelled/ended `discoveryEvents` not already in My schedule; dashed outline + "Discover" label so it never looks like a plan.
- **No end times exist** (note 38). Items carry an optional `end`; "Overlaps with n plans" only when both have real ends; otherwise the only claim is **"Starts within 2 hours of n plans"**. Never blocks adding. Never reads Apple/Google calendars.
- Agenda zone = device calendar/zone, week strip honours the calendar's first weekday; when the venue zone differs a "19:00 at the venue" note shows. Today button, prev/next week, graphical month sheet. No persistence of mode/date (session only, reset on sign-out).
- Error states: `paymentBookingsLoadFailed` and `discoveryEventsLoadFailed` (both previously silent: the loaders empty their lists on failure). There is no "stale" state because both loaders discard data on failure.

## Apple Calendar
`SystemEventEditor` = pre-filled `EKEventEditViewController` (title, start, end, location, public `/api/photo-share?eid=` link, short note). iOS 17+: runs out of process, **no calendar permission requested**, nothing written unless the person saves. No end time → 2h default + a note saying so. Results saved/cancelled/deleted/unavailable reported honestly. Used by Event Detail (`event.appleCalendar`), Schedule cards and ConfirmedView's existing "Apple Calendar" option, which previously requested **full access and saved silently** (`addToCalendarApple`, removed). `NSCalendarsFullAccessUsageDescription` removed from project.yml (no code requests access). Google Calendar link unchanged. Wording: "Add to Apple Calendar", never "sync".

## Reports (note 43 architecture unchanged)
New `insights` (Breakdown section), only where the payload supports it: host share of owed refund claims that are overdue (numerator and denominator from the SAME `refunds_owed.rows`); personal outstanding refunds by status (rows); admin open backlog (reviews vs disputes counts) and waiting-age buckets (<1, 1–3, 3–7, 7+ days from rows' `age_days`). Mini bar strips in KPI tiles only for series with activity. At accessibility text sizes every chart/ring/bar becomes its summary sentence. Golden export tests unchanged and green.

## Analytics (no-op sink, no vendor)
public_entry_viewed/get_started/login, public_story_opened/completed/skipped(step), schedule_opened, schedule_mode_selected(mode), schedule_day_selected(past|today|next7|later), schedule_conflict_shown(bucket), banbe_schedule_add/remove/result(enum), system_calendar_editor_opened/result(enum). No titles, locations, calendar names, emails or free text.

## Tests / verification (2026-10-17, Xcode 27, iPhone 17 + iPhone 17e simulators)
- Unit: 227 run, only failure = PRE-EXISTING `GiftTicketPDFTests.testPDFLinksPointAtRealDestinations` (failing at baseline too). New: PublicEntryTests (12), SchedulePresentationTests (16) + InAppCalendarStoreTests (4) + ScheduleAppStateTests (2), CalendarExportTests (4) + ReportInsightTests (5). Phase F goldens unchanged and green.
- Fixture UI (`-uiFixture auth | routing.signedIn|signedOut|signOut | schedule[.discover|.empty|.error] | plan` + note 43's): PublicEntryScheduleUITests 15/15, ReportsAndOnboardingUITests 11/11, PhaseGAccessibilityAuditUITests 4/4 (`performAccessibilityAudit` on Welcome, My schedule, Discover, Event plan actions). Audit exceptions, documented in the test: the 7-column week strip caps Dynamic Type at xxLarge (full-size day title restates the date) and fixture-only scaffolding. The audit found and this pass fixed: fixed-size CTA fonts (InkButton gained an optional `font:`; default unchanged elsewhere), a 17pt story-link target, 28pt week chevrons, a 32pt month button, low-contrast weekday letters, a header that could not grow, two clipping captions.
- Release build succeeds (fixtures compiled out).
- Screenshots checked (iPhone 17e): Welcome EN light / VI dark, Schedule My/Discover light+dark VI/EN, plan actions, report breakdowns, AX5 for Schedule/Welcome/Reports. Found+fixed: cards showing the VI date-laden `where` string as location (now area label only, calendar export too), wrapped 3-line action pills, AX5 week-strip digit splitting, AX5 report attention icon overlap (Phase F).
- **Network UI suites (BottomTabBar/InteractionPrecedence/Navigation/MapExplore) NOT green, environment-blocked:** the simulator's restored session is held by the server-side account gate "Ngày sinh" (DOB required; DOB cannot be changed after saving), which covers Login/Home. Passing it means writing a permanent DOB to a production test account — not done without approval. Their helpers were updated for the new public entry (`UITestAuthHelpers.reachLogin`: welcome → Log in) and `tab.notifications` → `tab.schedule` / Home bell.
- Not verified: real VoiceOver (Simulator has none), a real device, a real Apple Calendar save (only Cancel is automated), real network data, Switch Control. Fixtures still construct AuthViewModel, whose Supabase SDK may refresh a locally stored session.

## Known limitations
- Manual schedule additions are device-only (needs a backend relationship to sync — not done, would need a migration + RPC).
- Overlap is mostly "starts within 2h" until events gain end times.
- The Apple editor's Cancel/Discard UI is system-owned; only cancel is automated in tests (never a real save).
- Discover only knows events already loaded by `loadDiscoveryEvents` (max 300 public rows).

## Web parity
Web needs: a public welcome route with immediate Log in, a Schedule nav item (same sources/dedupe/near-rule, localStorage for manual adds — same device-only caveat), "Add to Google/Apple calendar" via .ics download rather than EventKit, the report breakdowns via the same derivations, and the same analytics names behind a no-op `track()`. A synced manual-schedule needs a shared backend table first.

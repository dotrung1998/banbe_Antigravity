# Strict invite-only events + interest surveys — domain note

## Status: PARTIALLY WORKING, web AND iOS. Read this before touching invite-only events, event photo privacy, or surveys again.

Slice A (invite-only events) backend is real and tested, including the
**critical fix described below** (the actual booking RPC, not just the one
originally gated) — web AND iOS both create/read/book through it, and iOS
has the same private-bucket-aware photo resolution as web. Slice B
(interest surveys) backend + a functional web AND iOS host/respondent UI
are real and tested/build-clean; the dedicated browser route is web-only
by nature. **Slice D (surveys in stories) is now real, web AND iOS — see
the 2026-10-29 pass below.** Slice C (candidate generation) is still **not
started**, either platform. Host invite-management UI, invite email
delivery, and EventDetail accept/decline for event invites are also **not
started**, on either platform.

## Slice D — survey sharing, in-app popup, lightweight respondent verification, public discovery (2026-10-29 pass)

### What's real

- `supabase/migrations/20261029000117_117_survey_share_stories_and_public_discovery.sql`
  (**not yet applied to any deployed database**) — `stories.survey_id` +
  `kind = 'survey_share'` (same additive pattern 068's `event_share` already
  established); `create_survey_share_story()` (owner + `status='active'`
  enforced server-side, mirrors `create_event_share_story`);
  `get_survey_card(p_survey_id)` (authenticated-only twin of
  `get_survey_public`, keyed by `survey_id` since a story row has that, not
  a `public_id`); a NEW, additive `stories_select_survey_share_public` RLS
  policy — a `survey_share` row is visible to ANY authenticated user once
  its survey was ever published (`status <> 'draft'`), independent of
  `stories_select_active_permitted`'s existing author/co-owner/follower
  gate, which is **unchanged** and still governs ordinary photo/video
  stories exactly as before.
- **Canonical link**: `src/lib/surveyLink.js` (web) / `AppConfig.
  publicWebOrigin` (iOS, `SupabaseService.swift` — an alias for the
  already-correct `apiBaseURL`) replace `SurveysHostingView.swift`'s
  hardcoded `https://banbe.app` (confirmed via `vercel project ls`/`vercel
  domains ls`: this project has 0 custom domains attached; the real,
  currently-serving production origin is `https://banbe-two.vercel.app`,
  verified with a direct `curl` — 200 on both `/` and `/surveys/<id>`).
  Web's own Copy/Share Link already used `window.location.origin` (correct,
  just duplicated) — now routed through the one shared builder too.
- **In-app popup** (`src/screens/sheets/SurveyResponseModal.jsx` /
  `.fullScreenCover` in `RootView.swift`): a story's "Answer Survey" CTA
  opens the EXISTING `SurveyPublic`/`SurveyPublicView` screen as a modal
  over the still-mounted Home+StoryViewer (never a `screen`/navigation
  change), with a real X, unsent-draft keep/discard confirm, a distinct
  "Response Submitted. Thank You!" success state with its own Close button
  (never auto-closed), and a "You Have Already Responded" read-only summary
  with Edit Response (only while the survey is still active). The story
  genuinely pauses and resumes from the same point: web reuses
  `StoryViewer.jsx`'s own existing hold-to-pause `pause()`/`resume()`,
  watching `storySurveyModalPublicId`; iOS reuses `StoryViewerView`'s
  existing `isSuspended` parameter (the same mechanism an Event Detail
  sheet on top of a story already proved out) — no new pause/resume
  mechanism invented on either platform.
- **Lightweight respondent verification** (section 3): `api/auth/index.js`'s
  `send_email_code` gets a third `mode: 'respond'` branch that auto-detects
  existing-vs-new identity (same `generateLink` login/signup branching the
  ordinary modes already do internally) instead of requiring the caller to
  guess, and returns `isNewAccount` so the UI can disclose which one just
  happened BEFORE the respondent types the code — never silently, never
  called "anonymous." Still finishes with the SAME `supabase.auth.verifyOtp`
  every other code flow uses, so `submit_survey_response`'s existing
  `auth.uid()`-only identity resolution and `UNIQUE(survey_id,
  respondent_id)` upsert (migration 114, unchanged) are what actually
  guarantee one current response per identity — this pass added NO new
  dedup mechanism because that one was already correct. An explicit
  consent checkbox (own copy, own text) gates sending the code — the
  additive consent path for a respondent who never saw the ordinary Login
  screen's own checkbox. New UI: `RespondVerifyInline`
  (`SurveyPublic.jsx`) / `RespondVerifyInlineView`
  (`SurveyPublicView.swift`); new API: `AuthAPIService.
  requestRespondEmailCode` / `AuthMode.respond` (iOS).
- **Host "Share To Story"/"Share Link"** (`SurveysHosting.jsx` /
  `SurveysHostingView.swift`): both require an `active` survey, both show
  an explicit preview-then-Publish confirm sheet (never auto-posts) that
  renders the SAME card content the real story shows.
- **Public discovery** (`loadHomeStories`, both platforms): now also
  queries `follows` directly to tell "own/followed" apart from "neither" —
  a `survey_share` row for an organizer the account does NOT follow is
  routed into a SEPARATE `homeSurveyDiscovery` bucket (same name both
  platforms; one card per organizer, newest-first, capped to 20), never mixed into
  the existing follow-gated per-organizer story rings. New Home section:
  "Help Shape Upcoming Events" (web `Home.jsx`, iOS `HomeView.swift`'s
  `surveyDiscoveryRow`), tapping a card opens the same in-app modal a
  story's own CTA does.

### Verification performed

`npx vite build` clean. `xcodebuild -scheme BanbeApp -configuration Debug
-sdk iphonesimulator build` → **BUILD SUCCEEDED** after fixing one
pre-existing-enum-now-non-exhaustive switch in `LoginView.swift` (adding
`AuthMode.respond` made its `(method, mode)` switch non-exhaustive; added
an explicit unreachable `.respond` case, no behavior change) and giving
`SurveyCard` `Hashable` conformance (`StoryItem` needs it transitively).
No real Supabase project was touched, no migration was applied, no
simulator/device run — this environment has no `supabase` CLI/local
project and no iOS simulator/device access, same documented limitation as
every other pass in this file. The lightweight respondent-verification
flow's actual email delivery/identity-linking behavior was NOT exercised
against the real `/api/auth` endpoint or a real inbox this pass — reasoned
through by reading `api/_lib/authLookup.js`'s existing `resolveAuthUserId`/
`linkRegistration` (already used correctly by the `login`/`signup` modes),
not independently tested.

### Not done this pass

- **Slice C (candidate generation)** — still not started; untouched.
- **Static social-preview metadata** for `/surveys/<publicId>` (task 6's
  "safe public preview metadata where feasible") — this SPA has no
  per-route server-rendered `<meta>` tags anywhere (confirmed: `index.html`
  is one static shell), so adding real per-survey Open Graph tags would
  need a new serverless metadata route, out of this pass's scope; external
  shares get a working link and native share-sheet, just a generic/no link
  preview card today, same as every other in-app deep link this app
  already generates.
- **iOS `.fullScreenCover` vs the dock overlay window**: the new survey
  modal was wired to follow the exact existing `DeleteAccountView`/
  `QRScannerView` `.fullScreenCover` pattern (RootView.swift) rather than
  the separate always-on-top dock `UIWindow` — consistent with every other
  full-screen modal in this app, but NOT verified on a real device that the
  dock stays correctly hidden under it (reasoned from the existing pattern
  already working for those other covers, not independently confirmed here).
- **`shareOrganizerProfile`/`u/<handle>`-style links elsewhere in this
  codebase still hardcode `banbe.app`** (e.g. `GocContext.jsx`'s
  `shareOrganizerProfile`) — found while auditing this area, deliberately
  NOT touched (this ticket's own "do not modify unrelated links blindly"
  rule); worth a follow-up pass with the same canonical-origin treatment.

### Fix pass — published survey story invisible to a non-follower (confirmed root cause, fix NOT yet deployed), publish-preview redesign

**Confirmed root cause, by a real authenticated integration test against
the deployed project** (`tests/e2e/survey-story-visibility.integration.mjs`
— the sanctioned real-backend pattern `tests/e2e/setup.mjs`/
`dispute-flow-e2e.spec.js` already established: service-role ONLY to seed
two throwaway accounts, an anon-key client mirroring the real app for every
actual assertion, full cleanup after): migration 117 **is** deployed
(`create_survey_share_story` exists and works; a throwaway host's story
publishes correctly — `kind='survey_share'`, `survey_id` set, `media_path`
empty). The bug is in `stories_select_survey_share_public`'s own RLS
policy: its `EXISTS (SELECT 1 FROM surveys sv WHERE sv.id = stories.
survey_id AND sv.status <> 'draft')` subquery runs under the CALLING
user's own privileges — for a non-owner/non-admin viewer, that subquery is
itself subject to `surveys_select_host` (host/admin-only SELECT), which
returns zero rows for them regardless of the real row's status. `EXISTS`
therefore always evaluated false for exactly the audience this policy
existed to serve. **Proven live**: a throwaway non-follower viewer's own
authenticated `stories` SELECT (the exact query `loadHomeStories()` issues)
returned the published story for ZERO rows, while `get_survey_card()` (a
SECURITY DEFINER RPC, structurally immune to this bug class) correctly
returned the survey for that same viewer in the same test run.
**Fix written, NOT YET deployed**: `supabase/migrations/
20261030000118_118_fix_survey_share_story_rls_subquery.sql` — the exact
`is_event_host`/`has_event_invite_access` pattern note 21's own Slice A
already established for an identical "a policy needs to check another
RLS-protected table without being subject to that table's own RLS"
problem: a small `SECURITY DEFINER` function
(`is_survey_publicly_shareable(p_survey_id)`) the policy calls instead of a
raw subquery. `surveys_select_host` itself is completely untouched — only
this one boolean check now sees through it, exactly like
`get_survey_card()` already safely does today. **This environment has no
`supabase` CLI/DB credentials to actually apply a migration or run raw SQL
against the live project** (same documented limitation as every other pass
in this file) — `supabase db push` (or applying the migration's SQL
directly) is required before this is live, and the integration test above
should be re-run afterward to confirm (it's the exact reproduction case).
Also fixed while here (not previously implemented): `loadHomeStories()`
(both platforms) used to treat a real query/decode error identically to
"zero stories" for the WHOLE function, including the public-discovery
feed — `homeSurveyDiscoveryLoading`/`homeSurveyDiscoveryError` (web:
`GocContext.jsx`; iOS: `AppState.swift`/`AppState+Data.swift`) now
distinguish loading/error/empty/cards, and Home's "Help Shape Upcoming
Events" section (`Home.jsx`/`HomeView.swift`) is now always rendered (not
only when cards already exist) so a real failure is never indistinguishable
from the section not existing. Confirmed (by reading, not assumed) that
account-switch already reloads this correctly — both platforms' Home mount
effects already key on the signed-in user id and re-run `loadHomeStories()`
on change; no fix needed there.

**Publish-preview redesign** (task 2): `ShareSurveyToStoryConfirmView`
(`SurveysHosting.jsx`/`SurveysHostingView.swift`) rebuilt as a full-bleed
story-canvas (9:16, rounded, clipped) instead of a small padded card
floating in a mostly-empty medium sheet — small preview heading + X at
top, the host's own REAL organizer name/avatar (`s.orgRegName`/
`s.myOrganizerAvatarPath`, never a generic "Your organizer"), the existing
Banbe Pulse dusty-rose/sage/sand gradient as the canvas background (no new
uploaded artwork, no invented survey content), Cancel/Publish anchored in
their own safe-area-aware bottom bar outside the scrollable canvas (a long
title/description can never push them off-screen). New shared renderer —
`src/screens/sheets/SurveyStoryCard.jsx` / `SurveyStoryCardView.swift` — is
used by BOTH this preview (`fill: true`, `onAnswerSurvey: nil` — a visual
preview only, never an accidental submit/navigation) and the real in-story
card (`StoryViewer.jsx`'s/`StoryViewerView.swift`'s `SurveyShareCard`,
`fill: false`, real `onAnswerSurvey` tap handler), so the preview is
provably the same layout viewers actually see, not just a visual
approximation. In-flight guard/errors/dismissal cleanup/explicit-publish
logic (`surveyShareToStoryBusy`/`surveyShareToStoryError`/
`closeShareToStoryConfirm`/`confirmShareSurveyToStory`) are untouched —
only the presentation changed.

**Verification performed**: the integration test above (migration 117
deployed, story publishes correctly, root cause reproduced live — see
above). `npx vite build` clean. `xcodebuild clean && build -scheme
BanbeApp` → **BUILD SUCCEEDED** (added `SurveySummary.description`,
missing from the iOS model despite the client's own `select()` already
fetching it). `BanbeAppTests` — 3/3 still passing post-clean. No simulator/
device UI run of the redesigned preview itself (no simulator/device
interaction this pass beyond compiling) — the 9:16 aspect-ratio math and
safe-area bottom bar should be checked on a real device per this ticket's
own iPhone-testing plan.

**Not done / explicitly out of scope this pass**: applying migration 118
(approval gate — see above); adding an organizer avatar field to
`get_survey_card()`'s own payload so the REAL in-story card (not just the
host's own preview) can show a host avatar too — today it only shows
`host_name` text, since the preview's avatar comes from the host's own
already-loaded local state while the viewer-facing RPC was not touched
this pass (kept the change minimal/proven-safe rather than widening an
RLS-sensitive RPC's return shape without a specific need for it).

## Fix pass — Home discovery collapse/expand, dock hidden during survey modal (iOS), keyboard handling for every survey field

**1. Compact Home discovery** — `app.homeSurveyDiscoveryExpanded` (iOS:
`AppState.swift`; web: `GocContext.jsx`'s `homeSurveyDiscoveryExpanded`),
collapsed by default. `HomeView.swift`'s/`Home.jsx`'s `surveyDiscoveryRow`
header is now a tappable row (title + an honest active-survey count +
chevron) — the row's own existing compact horizontal card strip (already
the "compact strip, not a tall stack of full cards" shape this ticket
wanted — it was never rebuilt) only renders while expanded. Count is
`app.homeSurveyDiscovery.count`, shown as `"20+"` once at
`loadHomeStories()`'s own `.prefix(20)` cap (iOS) / `.slice(0, 20)` (web)
rather than claiming that's the real total. State lives on
`AppState`/`GocContext`, not local component state, specifically so it
survives a round trip into the survey modal and back (HomeView/Home.jsx
never unmount for that — RootView's `.fullScreenCover` / App.jsx's
`SurveyResponseModal` overlay); reset to `false` on sign-out
(`signOut()`/`logout()`) and on a signed-out `loadHomeStories()` call so a
new account never inherits a stale previous user's expanded/collapsed
choice. Public non-follower discovery, dedup-by-survey-then-by-organizer,
and the 20-card cap are UNCHANGED — this pass only gates whether the
already-correct strip renders, never what it contains.

**2. Dock hidden during the survey modal (iOS only — web already had this
right)** — real, confirmed root cause: the survey response
`.fullScreenCover` (`app.storySurveyModalPublicID`, RootView.swift) never
changes `app.screen`, so `BottomTabBarOverlay`'s screen-based
`updateVisibility(for:)` never saw it, and the dock lives in its own
always-on-top `UIWindow` (`windowLevel = .normal + 1`) that paints above
ANY main-window content including a `.fullScreenCover` — confirmed by
reading `BottomTabBarOverlay.swift`'s own extensive doc history of this
exact bug class for other modals (Pulse, the area sheet, the dock tray).
Web was never affected: `App.jsx`'s `showBar` already ANDs in
`!state.storySurveyModalPublicId` explicitly. Fixed per this ticket's own
"use the centralized visibility/lifecycle mechanism... add a dedicated
survey-presentation reason" instruction: a new, INDEPENDENT
`surveyModalOpen` flag + `setSurveyModalOpen(_:)`
(`BottomTabBarOverlay.swift`, same "independent callers, independent
flags" pattern as `storyViewerOpen`/`pulseViewerOpen`/`areaSheetOpen` —
never a reuse of any of those, so one modal's `false` can never clobber
another's still-active `true`), folded into `applyVisibility()`'s
`shouldShow` check; wired from a new
`.onChange(of: app.storySurveyModalPublicID)` in RootView.swift. Covers
every entry point into that one modal (story CTA, Home discovery card tap
— both set the same published field) and every state inside it
(verification, success, unsaved-changes confirm — none of them touch
`storySurveyModalPublicID`, so the dock stays correctly hidden through all
of them) and restores correctly on every close path (X, discard, submit
success, `closeSurveyStoryModal()` is the one place that clears the field).
**Not verified on a real device this pass** — reasoned from the exact same
mechanism already proven for Pulse/the area sheet/the dock tray, not
independently confirmed with a physical iPhone.

**3. Keyboard handling, every survey field** — `SurveyPublicView.swift`
previously had NO `@FocusState`/keyboard toolbar/dismiss-on-tap/dismiss-
on-scroll anywhere (confirmed by reading the whole file — every field was
a bare `TextField`/`TextEditor`/`SecureField`-less primitive). Added one
shared `SurveyFocusField` enum (`groupSize`, `freeText`, `respondEmail`,
`respondCode`) and one `@FocusState` in `SurveyPublicView`, threaded into
the nested `RespondVerifyInlineView` as a `FocusState<SurveyFocusField?>.Binding`
parameter (not a second independent focus state — one shared Done/dismiss
mechanism has to reach fields in both). `.toolbar { ToolbarItemGroup(placement: .keyboard) }`
adds one localized "Xong"/"Done" button above EVERY keyboard this screen
shows, including the Group-size number pad (which has no Return key at
all to resign with otherwise) — resigns focus only, never submits.
`.scrollDismissesKeyboard(.interactively)` on the ScrollView (drag-to-
dismiss) + a `.onTapGesture` on the form's own outer `VStack`
(`.contentShape(Rectangle())` first, so the WHOLE frame including empty
padding margins is tappable, not just drawn pixels) for "tap neutral
background to dismiss" — deliberately NOT a separate full-bleed overlay
view layered on top of the form's own controls, which is the usual way
this exact pattern ends up swallowing the first tap meant for a
chip/button instead: SwiftUI resolves a Button's own more-specific gesture
before an ancestor container's plain `.onTapGesture`, so every chip/option/
Submit/X tap still fires on the first tap, confirmed by reading how
`MapExploreView.swift`'s own background `.onTapGesture { selectedId = nil }`
already coexists with real pin buttons the same way. `ScrollViewReader` +
`.id(SurveyFocusField.*)` on each field's container + `.onChange(of: focusedField)`
brings the focused field into view (`proxy.scrollTo(field, anchor: .center)`)
without any manual offset math. Submit and the two
`RespondVerifyInlineView` actions (send code / confirm code) all resign
focus (`focusedField = nil` / `focusedField.wrappedValue = nil`) before
their own async call — ends editing without submitting twice, and a failed
server-side validation still re-renders the same `form(config:)` with
`app.surveyDraft` completely untouched (the error path never clears a
field), so every answer survives exactly as this ticket requires either
way. X (`requestClose()`) also resigns focus first, then follows the
EXISTING unsaved-draft confirm logic unchanged. No new global keyboard
handler, no full-screen gesture competing with any other screen — every
change here is scoped to this one file. Web (`SurveyPublic.jsx`) was
already using correct native input types (`type="number"`, `type="email"`)
which already gets a real "Done" affordance from the mobile browser's own
native keyboard chrome — left untouched, per this ticket's own "no
iOS-only fake toolbars" instruction (nothing to add there, not an
oversight).

**Verification performed**: `npx vite build` — clean. `xcodegen generate`
clean (no new files, `git status` confirms the regenerated `.xcodeproj`
produced no diff). `xcodebuild -scheme PersonalTeamDebug -configuration
Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator'
build` → **BUILD SUCCEEDED**. No simulator/device UI run, no screenshots —
per this ticket's own "no claimed device verification" instruction, the
three checks below are the user's own to run on a physical iPhone.

**Not done / out of scope this pass**: Slice C (candidate generation) —
untouched, unrelated to this pass. The known, pre-existing "dock stays
tappable during an edge-swipe-back peek" `isPeeking` edge case
(`RootView.swift`'s own comment) is untouched — unrelated to the survey
modal.

## Fix pass — discovery completeness (real cause found, not a bug), host avatars, compact cards + strip-swipe-vs-tab-swipe gesture conflict

**1. "Missing third survey" — root cause found by directly querying the live
project (service-role, `tests/e2e/loadEnv.mjs` + `.env.local`), not
guessed**: only 2 `stories` rows exist with `kind='survey_share'` ("T2",
org `org_a96236c5`; "Test", org `org_compound`). A third survey ("Tôi", same
`org_compound`, `status='active'`) has **no `stories` row at all** —
confirmed directly against the `surveys`/`stories` tables. Publish
(`publish_survey`) and "Share To Story" (`create_survey_share_story`) are
two separate, explicit host actions (`AppState+Surveys.swift:426`/`:489`,
`SurveysHostingView.swift:128`/`:138`) — a published survey with no story
share is real, expected state, not a missing-survey bug; `get_survey_card`/
migration 118 (the earlier RLS fix) were re-verified live and are correct
(`is_survey_publicly_shareable` returns `true`; the full non-owner/
non-follower pipeline re-run via `tests/e2e/survey-story-visibility.
integration.mjs` — **all PASS**, service-role seed + real anon-key viewer
session, cleans up after itself). **Fix**: made the distinction visible to
the host instead of leaving it silently ambiguous — `mySurveySharedIds`
(iOS: `AppState.swift`, `AppState+Surveys.swift`'s `loadMySurveys()`/
`confirmShareSurveyToStory()`) is a lightweight `stories` query scoped to
the host's own organizer; `SurveysHostingView.swift` now shows a "Chưa chia
sẻ lên story"/"Not Shared To Story" label on any `active` survey missing
from that set, right next to the existing Share To Story button — no
auto-publish-to-story invented, no change to `loadHomeStories()`'s own
dedup logic (already correct from the previous pass — deduped by survey id,
includes owner/followed/non-followed hosts alike, confirmed unchanged by
re-reading it start to finish this pass).

**Diagnostics added, not removed** (iOS `loadHomeStories()`,
`AppState+Data.swift`): every `survey_share` story row and every
`get_survey_card()` outcome (success / `success:false` / thrown error) is
now printed — the per-survey `try?` that used to silently drop a failed
card with zero trace is now a real `do/catch` with a console line per
survey id.

**2. Host avatar blank/white in the survey story** — real, confirmed bug:
`get_survey_card()` (migration 117) returns no avatar field at all, and
`SurveyShareCard` (iOS `StoryViewerView.swift`, web `StoryViewer.jsx`)
always passed `hostAvatarURL`/`hostAvatarUrl` as `nil`/`undefined` — blank
for EVERY survey story, not just ones missing a real photo. Fixed
client-side (no RPC widened): `loadHomeStories()` on both platforms now
also selects `organizers.avatar_path` and resolves it through the SAME
public-bucket URL builder (`organizer-photos`) every other organizer avatar
in this app already uses (iOS: `AppState+Data.swift`'s notification-avatar
map pattern; web: `Account.jsx`/`Dashboard.jsx`/`OrganizerProfile.jsx`/
`SurveysHosting.jsx`'s own `organizerAvatarUrl` helper) — travels on the
story item itself (`StoryItem.hostAvatarURL` / `hostAvatarUrl`), not a
widened RPC payload. `SurveyStoryCardView.swift`/`SurveyStoryCard.jsx` (the
ONE shared renderer for both the publish preview and the real in-story
card — both updated for free) now fall back to the host's own initial
(same convention the main story ring already uses), never a blank tile,
on missing OR failed-to-load avatar, with no layout shift. iOS reuses
`RemoteImage`/`PhotoLoader` (the app's own memory+disk cache and in-flight
de-dupe, not a raw `AsyncImage`) via its existing absolute-URL fast path.

**3. Compact cards + exclusive horizontal scroll** — card width 220→190,
padding 14→11, smaller type, a small inline clock glyph before the deadline
(iOS: SF Symbol `clock`; web: 🕐), same host/2-line-title/deadline/Answer
Survey content and the same full-card tap target, nothing removed.
**Gesture conflict, root cause**: iOS's `RootView.swift` `tabSwipeGesture`
(root-tab swipe, a `.simultaneousGesture` DragGesture spanning the whole
screen) decided "horizontal" purely from dx-vs-dy with only an edge-strip/
Map-specific exception — any OTHER horizontal drag (the survey strip's own
`ScrollView(.horizontal)`) was read as a tab-swipe AT THE SAME TIME the
child ScrollView was also scrolling it, so a swipe through the cards could
commit a tab change. Fixed by reintroducing the same kind of frame-
registration check a PRIOR pass already used for Inbox rows (removed only
because Inbox stopped needing it, per that code's own comment) — generalized
as `AppState.horizontalScrollZones` ([String: CGRect], published via a new
`HorizontalScrollZonePreferenceKey`, same merge-latest shape as the
existing `StoryRingFramePreferenceKey`), registered only by the survey
strip for now, checked once (a touch's START location only — never
re-decided mid-drag, so it can't flip back to "horizontal" at either
scroll edge) alongside the existing edge-strip check. Web already HAD this
exact mechanism (`data-hscroll="true"`, checked in `App.jsx`'s
`onGesturePointerMove` via `e.target?.closest?.('[data-hscroll]')`) — the
survey discovery row in `Home.jsx` was simply the one carousel missing the
attribute every other Home carousel already has; added, nothing else
touched.

**Verification performed**: `tests/e2e/survey-story-visibility.
integration.mjs` run against the live project — all PASS (real anon-key
non-owner/non-follower session, service-role seed/cleanup only). Direct
service-role read of `stories`/`surveys` confirmed the exact missing-share
state above. `npx vite build` clean. `xcodebuild -scheme PersonalTeamDebug
-sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build` →
**BUILD SUCCEEDED**. No simulator/device UI run, no screenshots, no
production data mutated (the integration test cleans up its own throwaway
rows) — the three checks below are the user's own to run on a physical
iPhone.

**Remaining/not done**: no migration was written or deployed this pass
(avatar resolved entirely client-side); `mySurveySharedIds` is a live
`stories` query, not derived from a server-computed flag, so a *very*
stale `loadMySurveys()` call (before a share completes) could in principle
show "Not Shared" for a beat — `confirmShareSurveyToStory()` now reloads it
immediately after a successful share, same as `loadHomeStories()` already
did, so this should not be visible in practice. `horizontalScrollZones` is
currently wired for the survey strip only, by design/scope — the other
Home carousels' own narrower historical exposure to this bug class wasn't
otherwise reported and was left untouched.

## Slice A — Strict invite-only events

### What's real and verified

- `supabase/migrations/20261025000113_113_strict_invite_only_events.sql`
  (**not yet applied to any deployed database** — see Deployment below).
- `event_invites` table (pending/accepted/declined/revoked/expired), RLS
  scoped to host/admin/invitee via two bypass-RLS helper functions
  (`is_event_host`, `has_event_invite_access` — needed to break a genuine
  mutual-recursion cycle between `events` and `event_invites` RLS,
  confirmed by actually reproducing "infinite recursion detected in
  policy" against a local Postgres before fixing it this way).
- `events_select_public` narrowed to require `visibility='public'`
  (previously ignored visibility entirely — any invite-only event was
  fully readable by direct id/slug). `events_select_invited` is the
  additive policy for the invited case, same pattern as the existing
  `events_select_admin` (085).
- **CRITICAL, found and fixed after the first pass looked done**:
  `claim_seats` (007) was gated first, but reading `GocContext.jsx`'s own
  `submitReserve` comment revealed the REAL reserve flow calls
  **`hold_seats()` (migration 053)**, not `claim_seats` — the latter is
  explicitly described in that comment as legacy (it never touches
  `payment_state`/`hold_expires_at`). Gating `claim_seats` alone left the
  actual booking path completely unprotected despite looking fixed.
  **Both are now gated**: `claim_seats` for defense-in-depth, `hold_seats`
  because it's what the app actually calls — verified end-to-end against
  the local Postgres harness (stranger blocked with `INVITE_REQUIRED`,
  invitee books successfully, owner bypasses without needing an invite,
  correct notifications fire). **Lesson for next time**: always trace a
  client call site to its real RPC name before declaring a server-side
  gate complete — a plausible-sounding function name is not proof it's
  the live path.
- Real photo privacy: invite-only events' photos go to a **separate,
  genuinely private bucket** (`event-photos-private`), not the existing
  public `event-photos` bucket. This matters because Supabase serves a
  `public: true` bucket's objects via `getPublicUrl()` regardless of
  `storage.objects` RLS — gating RLS alone would NOT have closed the "a
  private event's public image URL isn't private" gap the task called
  out. Public events are completely unaffected (same bucket/path, same
  synchronous `getPublicUrl()` fast path as always).
- `create_event_invites`/`revoke_event_invite`/`respond_to_event_invite`/
  `redeem_event_invite_token`/`set_event_visibility` RPCs. Tokens are
  high-entropy (32 random bytes), stored only as a SHA-256 hash, returned
  to the caller once. Redemption re-verifies the caller's own
  `auth.users.email` against the invited address at redemption time — a
  forwarded link cannot grant a different account access.
- Existing-user invites insert a real `notifications` row (kind
  `event_invite`), reusing the existing table/RLS/toast pipeline — no new
  inbox. `openNotification()` routes it to `goEvent()` (GocContext.jsx).
- `MapExplore.jsx`'s `fetchLiveEvents` now filters `visibility='public'`
  (it never had before — the only web discovery query with this gap).
- **iOS parity fix, found by re-auditing after the web fix**:
  `AppState+Data.swift`'s `loadMapEvents()` (the Map screen's real query)
  had the EXACT SAME missing-visibility-filter bug as `MapExplore.jsx` —
  fixed the same way (`.eq("visibility", value: "public")`). iOS's
  `locationUniverse`/Home-feed filters (`AppState.swift:1635`/`:1757`)
  were re-checked and are already correct (`!e.inviteOnly`, mirroring
  web's `Home.jsx`) — no change needed there. `ViewModels/HomeViewModel.
  swift` has the same bare `status=live` query with no visibility filter,
  but is dead code (grepped: referenced nowhere else in the app) — left
  alone; RLS is the real backstop for it regardless if it's ever wired up.
- The static demo catalogue's `banrieng` entry (`src/data/events.js`,
  iOS `Resources/events.json`) is **removed** — it was gated only by a
  hardcoded client-side map plus an `s.invited` array that was never
  actually populated (dead code, always `[]`), so any signed-in user
  navigating to it directly got full "private" demo content for free. The
  real seeded `events` row with the same id (migration 020) now goes
  through the real RLS/`event_invites`/booking path this migration added.
- Fixed a fabricated claim: EventDetail (web + iOS) used to show "You can
  bring one +1" on any invite-only event — leftover flavor text from the
  removed demo event's own fiction. No "+1" mechanism exists anywhere in
  the invite model; now shows a truthful "This event is invite-only"
  instead, on both platforms, since this line now renders for REAL
  invite-only events.
- `CreateEvent.jsx` has a Public/Invite-only toggle (`s.createVisibility`,
  persisted via the new `set_event_visibility` RPC, deliberately NOT a new
  param on the already-large `create_event_draft`/`resubmit_event_for_
  review` — same pattern as the existing `set_event_keywords`) and shows
  it on the Review step.
- `submitReserve`'s (web) and iOS's equivalent error-mapping both now show
  a truthful "This event is invite-only" for `INVITE_REQUIRED`, instead of
  the generic "could not hold this spot, try again" fallback.

### Verification performed (Slice A)

No local/staging Supabase instance exists in this environment (no
`supabase` CLI, no running project). Verified instead against a throwaway
local Postgres container running a minimal stub of the relevant schema —
NOT a substitute for a real `supabase db push` + `supabase migration list`
check. Confirmed, calling the RPCs directly under different session
identities (`request.jwt.uid` session var standing in for `auth.uid()`):
- Non-invitee: 0 rows on direct `SELECT events`; both `claim_seats` AND
  `hold_seats` raise `INVITE_REQUIRED`.
- Invited (pending, no explicit accept) user: sees the event, books
  successfully via `hold_seats` (the real path) with correct
  `payment_state`/notifications.
- The event's organizer owner books their own private event without
  needing an invite.
- Host revokes → invitee's next booking attempt fails (`INVITE_REQUIRED`);
  the invitee's EARLIER booking is untouched (no silent cancellation/
  financial-state change).
- Email-only invite: wrong token → `INVITE_NOT_FOUND`; correct token from
  the wrong identity → `IDENTITY_MISMATCH`; correct token from the actual
  invited email → binds `invited_user_id`, succeeds.
- `create_event_invites` on a `visibility='public'` event →
  `EVENT_NOT_INVITE_ONLY`.
- `event_photos` row visibility follows the same rules (stranger: 0 rows,
  invitee: sees them).
- `set_event_visibility` rejects a non-owner (`NOT_AUTHORIZED`) and
  correctly inserts a `notifications` row for an existing-user invite.
- `npx vite build` clean. `xcodebuild -scheme PersonalTeamDebug ... build`
  → **BUILD SUCCEEDED**, after the iOS `loadMapEvents`/error-mapping/"+1"
  copy fixes.

### Not done (Slice A)

- **Host invite-management UI** (send invites, see pending/accepted/
  revoked list, revoke button) — the RPCs exist and are tested, but no
  screen calls them yet.
- **Email delivery for email-only invites** — `create_event_invites`
  returns the plaintext token, but nothing calls `/api/notify` yet to
  actually send it. Needs a new `event_invite` case in `api/notify.js`
  (same Bearer-token/service-role pattern as its existing cases).
- **EventDetail accept/decline banner** for event invites — an invitee
  lands on the event (RLS-permitted) but there's no UI surfacing "you're
  invited, accept/decline."
- **iOS is now at full parity with web for what web itself has**:
  `CreateEventView` (OnboardingViews.swift) has the same Public/Invite-only
  toggle, persisted via the same `set_event_visibility` RPC; photo uploads
  route to `event-photos-private` for invite-only events
  (`reconcileEventMedia`); a new `resolveEventPhotoURL` helper
  (AppState+Data.swift) resolves signed URLs for the private bucket and is
  now used everywhere an event photo is displayed (EventDetailView's
  gallery, CreateEventView's edit-seed, AdminEventsView's review gallery
  via `loadEventGalleryURLs`, notification thumbnails via
  `firstPhotoURLByEvent`); `loadMapEvents` (the Map screen's real query,
  found to have the exact same missing-visibility-filter bug as web's
  `MapExplore.jsx`) is fixed; `hold_seats`'s `INVITE_REQUIRED` error maps
  to the same truthful message. Still not done, either platform: invite
  RPC calls (create/revoke/accept/decline/redeem) have no UI at all yet —
  see the bullets above, unchanged by the iOS work.
- **Organizer public-profile stats leak (found, not fixed)**: `get_
  organizer_profile` (095) and the organizer public team page (100) count
  `event_count`/`hosting_since_year` over `status IN ('live','ended')`
  with **no visibility filter** — an invite-only event's existence
  contributes to a PUBLIC organizer page's numbers even though the event
  row itself is now correctly hidden. Not fixed: both are large (100+
  line) `SECURITY DEFINER` functions redefined multiple times across later
  migrations, and this environment can't test a full redefinition against
  the real schema — retyping them by hand under time pressure without a
  real test was judged riskier than leaving a documented, lower-severity
  leak (aggregate counts/year, not event content) for a follow-up pass.
- **Organizer-team invites vs event invites**: deliberately kept separate
  — `event_invites` is attendee-level event access; `organizer_members`/
  `invite_organizer_member` (098) is organizer-team membership. No shared
  table, no shared RPC.

## Slice B — Interest surveys before an event

### What's real and verified

- `supabase/migrations/20261026000114_114_interest_surveys.sql` (**not yet
  applied to any deployed database**).
- Fixed MVP question set stored as ONE structured `surveys.config` JSON
  block (date/time options, location options, budget options, activities,
  group size bounds, per-field `required` flags) — deliberately not a
  generic question/option engine, per the task's own "don't build an
  unrestricted complex form-builder" instruction.
- `surveys` (draft/active/closed/archived) + `survey_responses`
  (`UNIQUE(survey_id, respondent_id)`, atomic upsert = "one current
  response, editable until closure"). Direct table SELECT is host/admin
  only; the public browser route reads exclusively through
  `get_survey_public()`, an allowlisted-field RPC that can never leak more
  than it explicitly returns, and that computes EFFECTIVE status
  (`closes_at <= now()` ⇒ closed) rather than trusting the stored column
  alone, in case the closure worker hasn't run yet.
- RPCs: `create_survey`/`update_survey` (host, structural `config` changes
  LOCKED once any response exists — not versioned, an explicit simpler
  choice, see Not done)/`publish_survey`/`close_survey`/`archive_survey`/
  `get_survey_public`/`submit_survey_response`.
- `submit_survey_response` validates: survey is active AND
  `opens_at <= now() < closes_at` (enforced here too, not just by the
  worker — "enforce closes_at on response writes even if the worker is
  late"), every required field per the survey's own `config.required`,
  every submitted option id is a real member of that survey's own option
  set, group size within `config.group_size_min/max`. Atomic upsert via
  `ON CONFLICT (survey_id, respondent_id)` under the survey row's own
  `FOR UPDATE` lock, so a host's `close_survey()` and a respondent's
  concurrent submit can't race past each other.
- Deadline closure: `close_expired_surveys()` on `pg_cron` (`* * * * *`,
  same pattern as the existing `goc_expire_lapsed_pendings`/`goc_mark_
  past_events` jobs, migration 008) — idempotent, host doesn't need the
  app open.
- Respondent privacy: RLS on `survey_responses` scopes SELECT to
  `respondent_id = auth.uid()` OR the survey's own host/admin — a
  respondent can never see another respondent's name or answers.
- Contact consent (`contact_consent`) is a separate boolean field, never
  implied by answering, never auto-true.
- Browser route: real path `/surveys/<publicId>` (NOT a query param — see
  the correction below), read the same way this app's existing `/u/
  <handle>` and `/org/<id>` deep links are (parsed from
  `window.location.pathname` once at module load, before React mounts;
  works signed out via the anon-granted RPC). One screen
  (`SurveyPublic.jsx`) serves both the dedicated browser page and in-app
  navigation (`goSurveyPublic`), sharing the exact same backend calls, per
  the task's "reuse... the SAME response backend" instruction.
- Draft answers persist through a sign-in round trip via `sessionStorage`
  (keyed by `public_id`), restored on mount, cleared on successful submit
  — "preserve entered answers through auth."
- Host screen: `SurveysHosting.jsx`, reachable from Account → Hosting →
  "Khảo Sát & Ý Tưởng Sự Kiện" (new `GroupCard`, badge honestly `0` since
  the real unseen-candidate-count driving that badge is Slice C, not
  built). Active/Closed/Suggested-Drafts tabs; create form (title,
  description, days-until-close, comma-separated option lists, max group
  size); publish/close-early/archive actions; a "Preview" link that opens
  the same `SurveyPublic` screen in-app. The Suggested-Drafts tab shows an
  honest empty state explaining candidate generation isn't built —
  present in the IA (a real, correctly-positioned entry point), never
  claiming content that doesn't exist.

### Correction made mid-implementation (routing)

An earlier audit pass concluded this app has "no client-side router...
so `/surveys/:publicId` must be a query-param convention," based on
`MapExplore.jsx` and query-param usage. That was **wrong** — re-checking
`GocContext.jsx` directly during implementation found `sharedProfileHandle`/
`sharedOrganizerId` already parsing REAL paths (`/u/<handle>`, `/org/<id>`)
from `window.location.pathname` at module load, working fine under
`vercel.json`'s catch-all SPA rewrite (any path still serves `index.html`,
so this JS still runs and still sees the real pathname on direct load and
refresh). `/surveys/<publicId>` uses the exact same, already-proven
pattern — a real path, not a query param. **Lesson**: verify a structural
claim like "this app has no path-based routing" by grepping for the
actual mechanism, not by trusting one prior investigation's summary.

### Verification performed (Slice B)

Same local-Postgres-harness method as Slice A (extended with `surveys`/
`survey_responses`/pg_cron stub). Confirmed:
- Draft survey not reachable via `get_survey_public` (`NOT_FOUND`, same as
  a genuinely missing link — a draft was never meant to be reachable yet).
- Respondent blocked from submitting before publish (`SURVEY_NOT_ACTIVE`).
- After publish: `get_survey_public` reports `active`; a respondent
  submits successfully; the SAME respondent editing their answer updates
  the same row (not a duplicate — `UNIQUE(survey_id, respondent_id)`
  proven, not assumed).
- Invalid option id → `INVALID_LOCATION_OPTION`; missing required field →
  `DATE_OPTIONS_REQUIRED`; out-of-bounds group size → `INVALID_GROUP_
  SIZE`.
- A second respondent's row is invisible to the first respondent via
  direct `SELECT` (RLS proven with two real, different session
  identities, not assumed from the policy text alone).
- Host sees both respondents' full rows.
- `update_survey` with a `config` change AFTER a response exists →
  `STRUCTURAL_CHANGE_LOCKED`; the SAME call with only `title` changes
  still succeeds.
- Host `close_survey()` → subsequent respondent submit →
  `SURVEY_NOT_ACTIVE`; `get_survey_public` reports `closed`.
- `npx vite build` — clean (`SurveyPublic.jsx`, `SurveysHosting.jsx`,
  `Account.jsx`, `App.jsx`, `GocContext.jsx` changes).

**Not run**: no iOS survey code was written this pass, so no iOS build
was needed for it (the earlier Slice A iOS build already covers the fixes
that touch iOS files). No real Supabase project was touched; no data was
written to any deployed database.

### Not done (Slice B)

- **True invite-gated private surveys** — this pass ships public-by-link
  audience only (anyone with the `/surveys/<publicId>` link can respond,
  same trust model as any other shared link in this app). Reusing
  `event_invites` to gate a survey's audience is not implemented.
- **Question-level versioning** — `update_survey` HARD LOCKS `config`
  changes once any response exists, rather than the task's alternative
  "or implement explicit versioning so old answers keep their meaning."
  `config_version` exists on both `surveys` and `survey_responses` for a
  future pass that wants true versioning instead of a lock; this pass
  took the simpler, safer branch given time constraints.
- **Explicit rate-limiting** of `submit_survey_response` itself — the
  atomic per-respondent upsert structurally caps meaningful writes to one
  effective row no matter how many times it's called (idempotent, not
  spammable into duplicates), and identity verification itself already
  rate-limits via the existing OTP/email-code infra (`otp_codes.attempts`)
  reused for sign-in. No NEW request-throttling infra (e.g. a sliding
  window) was added.
- **iOS now has full survey parity with web**: `AppState+Surveys.swift`
  (models + every RPC call — `get_survey_public`, `submit_survey_response`,
  `create_survey`/`publish`/`close`/`archive_survey`, `loadMySurveys`,
  `loadMySurveyResponse`), `SurveyPublicView.swift` (one screen for both
  in-app navigation and the `/surveys/<publicId>` universal-link deep link
  — `handleUniversalLink` in AppState+Profile.swift now recognizes a
  `surveys` path segment the same way it already does `u`/`org`; actual
  resolution still needs the real Team ID for Associated Domains, same
  documented caveat as every other universal link in this app, see note
  17), `SurveysHostingView.swift` (Active/Closed/Suggested-Drafts tabs,
  create form, copyable link), a new Account → Hosting entry point.
  `xcodebuild -scheme PersonalTeamDebug ... build` → BUILD SUCCEEDED after
  adding all of this. No draft-persistence-through-sign-in mechanism was
  needed on iOS the way web's `sessionStorage` fix was — the app itself is
  the durable session, so there's no "browser tab reload mid-auth" failure
  mode to guard against.
- **Slice C (candidate generation)** — not started. Schema was shaped
  with this in mind (`date_options`/`location_options` stored as
  queryable arrays per response) so a later deterministic scoring pass
  doesn't need a data migration first, but no scoring function, candidate
  table, or "Use This Idea" → Create Event prefill exists.
- **Slice D (surveys in organizer stories)** — not started. No survey
  story/card type, no "Answer Survey" CTA, no pause-story-for-response
  flow.
- **Notifications/badges for survey results** — no "your event ideas are
  ready" notification exists (there's nothing to notify about yet, since
  Slice C doesn't exist); the Hosting/dock badge Slice C would eventually
  drive is a hardcoded `0` for now, honestly, not a fabricated count.

### Bugs found testing on a physical iPhone (2026-10-01), fixed

- `get_survey_public()` unconditionally returned `NOT_FOUND` for a draft,
  with no exception for the survey's own host — so "Preview" on any draft
  (web and iOS both call this same RPC) showed "couldn't be found," the
  exact reported symptom. Fixed in migration 116: the host/admin can now
  preview their own draft (a stranger still gets the same honest
  `NOT_FOUND`); the returned effective `status` for that case is `'draft'`
  specifically, and both `SurveyPublicView.swift` and `SurveyPublic.jsx`
  now render an explicit "this is a preview, not published yet" state for
  it instead of showing the live response form.
- No way to delete a mistaken/unwanted draft. Added `delete_survey()`
  (migration 116), deliberately restricted to `status = 'draft'` only —
  once a survey has ever been published it may have real respondent
  answers, and `archive_survey()` is the correct action from there, never
  delete. Wired on both platforms (`deleteSurvey`/`deleteSurveyAction`,
  a "Delete" action next to "Publish" on a draft card).
- Verified against the local Postgres harness: host previews own draft
  (success, `status: 'draft'`); stranger previews same draft (`NOT_FOUND`);
  stranger tries to delete host's draft (`NOT_AUTHORIZED`); host deletes
  own draft (succeeds), deleting again fails (`SURVEY_NOT_FOUND`); host
  tries to delete an already-published survey (`ONLY_DRAFT_CAN_BE_DELETED`).
  `npx vite build` and `xcodebuild -scheme PersonalTeamDebug ... build`
  both clean after the client-side changes.

## Deployment status

This environment has no `supabase` CLI and no local/staging project, so
none of this was ever applied FROM here — all real `supabase db push` runs
happened on the user's own machine:
- `20261025000113` (invite-only events) and `20261026000114` (surveys) —
  the first `db push` attempt failed on 114's `gen_random_bytes` default
  (pgcrypto schema issue); **confirmed applied successfully** after that
  fix, since the user went on to create and test real draft surveys on a
  physical iPhone ("T2", "Test survey").
- `20261027000115` (pgcrypto schema-qualification fix for 113's
  `create_event_invites`/`redeem_event_invite_token`) — applied together
  with 114 in that same successful push.
- `20261028000116` (this pass's draft-preview + delete_survey fix) —
  **written this pass, NOT YET applied** — run `supabase db push` again to
  pick it up. Every RPC/table change in it was verified against a local
  Postgres harness before being handed over (see above), the same way
  113/114/115 were, but that is still not a substitute for confirming it
  on the real project.

## iPhone/browser checklist (once migrations are deployed)

- Create an event, toggle Invite-only, confirm it does NOT appear on
  Home/Map for a second test account with no invite.
- From a second account with no invite, try to reserve the same event by
  guessing/reusing its id directly (not through the UI) — should fail.
- Open `/surveys/<publicId>` for a published survey directly in Safari,
  signed out: description/deadline/form should render; submitting should
  prompt sign-in, then land back on the same survey with the draft intact.
- Refresh the browser survey page mid-form — draft answers should survive
  (sessionStorage).
- As the host, publish a survey, submit a response from a second account,
  confirm it appears in `SurveysHosting`'s Active tab; close it early;
  confirm the browser page now shows "closed" and rejects a new submit.
- iOS: repeat the Invite-only toggle + photo-upload check in the app's own
  Create Event flow; open Account → Hosting → "Khảo Sát & Ý Tưởng Sự Kiện"
  and create/publish/close a survey from the phone; tap "Xem trước" and
  confirm the in-app survey form matches the browser version's behavior.

# 64 — "Do it, then ✓" button, sign-in hand-off + reveal, admin switch categories, onboarding Version 3 tour

Status (2026-10-27): IMPLEMENTED LOCALLY (web + iOS), not committed.
- Migration 202 NOT applied. It was verified in a throwaway Postgres 16 container against a stubbed schema.
- Until 202 is applied, Admin shows the old "Version 2" switch and nobody gets Version 3.

## What and why
The owner's brief (`/plan` brief "banbe iOS + Web") asked for four things:
- **A.** One reusable async button that morphs into a spinning circle and then a ✓. Initial sign-in uses it, with no
  in-between loader and a top-to-bottom reveal of the first Home.
- **B.** Admin feature switches grouped into collapsible categories.
- **C.** Onboarding Version 3: a guided tour over the real app.

Owner decisions (2026-10-27):
- Version model: a boolean `onboarding_v3` plus one atomic, audited setter. Clients resolve v3 > v2 > v1.
- V3 starts after personalization: gates, then the For You questions if owed, then the Home reveal, then the tour.
- Morph adoption in phase 1: login, Hold seats, profile/settings saves, Create-event submit.
- Tour: any step number can be selected, Skip is always there, and Finish/Skip ends on Home scrolled to the top.

## A. AsyncSuccessButton
**State model.** One pure reducer per platform: `src/lib/asyncAction.js` and `Lib/AsyncAction.swift`. Twin tests are
`tests/unit/asyncAction.test.mjs` and `AsyncActionTests`.
- Phases: `idle → pending → success → completed`, or `pending → failure → idle`.
- `start` is ignored outside idle, so a double tap never runs the operation twice.
- `animDone` flips `fired` once, so the callback runs exactly once.
- **Only an explicit success counts.** On web that is `true` or `{ok:true}`; on iOS `.success`. `undefined` (an early
  `return`) or a throw is a failure. This was tightened after finding that `savePayoutDetails` returned `undefined` on
  its no-host-page path.

**Components.** Web `src/components/ui/AsyncSuccessButton.jsx`, iOS `Views/AsyncSuccessButton.swift`.
- They render a real `<button type="button">` / `Button`, at least 44pt high, with roles primary, secondary and
  destructive.
- On tap the button freezes its width and morphs into a circle on its own axis. An arc spins while the real request
  runs.
- On success the arc finishes its current turn, a ✓ draws, success is announced (aria-live / VoiceOver
  announcement), and only then does `onSuccessAnimationComplete` run.
- On failure the label comes back, focus stays on the button, and the caller's `role="alert"` error shows.
- Reduce Motion: no morph and no spin, just a 150ms crossfade with the same state timing.
- iOS arcs hold still under `UITestFixture.isActive` (the note 63 lesson: XCUITest waits for an idle app).
- `resetAfterSuccess` is for stay-and-update saves.
- **Web gotcha.** React StrictMode mounts, unmounts and remounts once in dev. The mounted guard must be set to true on
  every mount, otherwise every result is dropped and the button stays pending forever (found by the e2e).
- The web "not yet" (grey) look only applies while idle.
- On iOS `looksEnabled` stops a caller's own busy flag from greying the circle mid-request.
- Shared hook: `src/lib/useReducedMotion.js`, lifted from `HowBanbeWorks.jsx`.

**Sign-in hand-off.** The rule has two conditions and produces one navigation: the session is applied AND the ✓ has
finished. The gates keep authority.
- **Web** (`BanBeContext.jsx`):
  - `beginSignInHandoff`, `awaitSignInReady`, `completeSignInHandoff`, `cancelSignInHandoff`.
  - While `signInHandoff` is set, `onAuthStateChange` leaves Login on screen and `AccountGate.jsx` renders nothing.
  - Ready means: user loaded, `authSyncing` false, and the account gate answered (`ready`, `blocked` or
    `unavailable`).
  - A blocked gate appears right after the ✓.
  - `completeSignInHandoff` navigates to `authReturnScreen` and sets the one-shot `justSignedIn` (Home only).
  - The 20s timer only rescues a stuck request: it falls back to today's behaviour and never decides success.
- **iOS** (`State/AppState+SignInHandoff.swift`):
  - `RootView.showsAccountGate` is false while `signInHandoffPending`.
  - The `GateTaskKey` task calls `markSignInReady()` after `applySession` instead of navigating. An
    `.onChange(of: auth.gate)` also marks ready for blocked/unavailable.
  - `completeSignInHandoff(sessionApplied:)` navigates once and runs `runPendingAuthResume()`.
  - Policy and OAuth routing still win: completion only navigates while the screen is still Login/Welcome.
  - Also fixed: LoginView's `submitting` had no `defer` reset.
- **Send code / sign-up** (which ends in a code) is intermediate: it spins and returns to the form, with no ✓.
- **Google:**
  - Web is a full-page redirect, so it shows pending only (now a real `<button>`). The return goes through the
    existing gate loader, with no ✓.
  - iOS awaits the in-app web auth session, so its button gets the full handshake.

**First-Home reveal.** Order: header 0, summary 1, feed 2, dock 3.
- Web: `data-reveal` on the Home regions (plain block wrappers, layout unchanged) and on `DockRow`. `useSignInReveal`
  sets `<html data-reveal="1">` once. CSS is at the end of `src/index.css`.
- iOS: `.revealRegion(n)` (`Views/RevealRegion.swift`) on Home and the dock in its window.
- Content stays rendered and accessible; only opacity and translate move. Reduce Motion fades everything together.
- The end of the reveal is an entry point for the v3 tour.

**Phase-1 adoption** (the classification table is in the plan). Each flow got a `deferNavigation` / `noLoader` /
`showsLoader:false` variant, so the button owns progress and navigates after the ✓:

| Flow | Class | Notes |
|---|---|---|
| Hold seats | navigate | Ends on Confirmed. The full-screen `Loading` / `loadingOverlay` is no longer used for it. |
| Edit profile | navigate | Ends on Account. |
| Billing, Payout | stay + update | |
| Event preferences | stay + update | Navigates instead when opened from a reservation. |
| Create-event submit | present modal | The ✓ is labelled "Sent for review", never "live". The chooser opens after it. |

Excluded on purpose:
- Admin and organizer switches: they are switches, not buttons.
- Refund, check-in, cancel and delete: a ✓ could imply later server processing, and some are destructive.

## B. Admin categories
- Metadata twins: `src/lib/featureFlagCategories.js` and `Lib/FeatureFlagCategories.swift`.
- `tests/unit/featureFlagCategories.test.mjs` parses the Swift file and checks that every flag sits in exactly one
  category.
- Categories:
  - Onboarding & discovery: the version control, `intent_foryou`, `market_share`
  - Rewards & engagement
  - Notifications & retention
  - Events & recaps
  - Platform & measurement: `app_events`, plus iOS-only `admin_event_wipe`
- Every section is collapsed on open, and sections expand independently.
- Headers:
  - Web: `<button aria-expanded aria-controls>` with an "n/total on" count and a chevron (no rotation under reduced
    motion). Test IDs `admin-cat-<key>`, `-toggle`, `-count`.
  - iOS: `Button`, header trait, Expanded/Collapsed value, ID `adminFeatures.cat.<key>`.
- Collapsed bodies are not rendered, so a switch can't fire by accident. Existing per-flag IDs are unchanged.
- The NOT_DEPLOYED message is now generic on both platforms.

## C. Onboarding Version 3
**Migration 202** (`20261231000202_202_onboarding_version.sql`, rollback in `supabase/rollbacks/`):
- Adds the `onboarding_v3` def and seed row (false).
- Adds `admin_set_onboarding_version(p_version int)`:
  - SECURITY DEFINER, admin and account-gate checks, accepts 1..3.
  - Upserts BOTH booleans in one transaction and writes two audit rows.
  - Execute is granted to authenticated only.
- `admin_set_feature_flag` is unchanged: it could still set `onboarding_v3` alone. Clients' precedence makes any pair
  resolve to one version.
- Old clients only know `onboarding_v2`. Picking 3 turns v2 off, so they fall back to Version 1.

**Resolver.** `onboardingVersion(flags)` (web) and `FeatureFlags.onboardingVersion` / `AppState.onboardingVersion`
(iOS).
- `onboardingV2Enabled` now means version ≥ 2, so v3 keeps the v2 Welcome and story.
- Admin shows a Version 1/2/3 segmented control (`admin-onboarding-version[-n]`, `adminFeatures.onboardingVersion.n`)
  once the server returns an `onboarding_v3` key. Before that, the old v2 switch row stays.

**Tour.**
- Step data twins: `src/data/onboardingTour.js` and `Models/OnboardingTourContent.swift`, checked by
  `tests/unit/onboardingTour.test.mjs`.
- 8 steps: search, For You, first event card, Map, Schedule, Messages, Account organizer toggle, and dock + (hosts
  only).
- A target that has not appeared after 1.5s is skipped in the direction of travel; its number is disabled.

**Web** (`src/components/tour/OnboardingTour.jsx`, mounted in `App.jsx`):
- Portals outside `#root` and sets `inert` on `#root`.
- SVG scrim with a cut-out. `role="dialog" aria-modal`, focus trap, Escape = Skip, focus restored afterwards.
- Targets resolve to existing data-testids (`WEB_TARGETS`) and are scrolled into view.
- Analytics are paused (`setAnalyticsPaused`), and Home's For You alert is passive while `s.tourActive`.

**iOS:**
- The overlay (`Views/OnboardingTourOverlay.swift`) is hosted in the dock's always-on-top window, the only window
  above both the main window and the dock.
- `BottomTabBarOverlay.setTourActive` makes that window take every touch. RootView's content is
  `accessibilityHidden`.
- Targets publish global frames with `.tourTarget(id)` (`onGeometryChange`) into
  `OnboardingTourController.shared`. That is a separate ObservableObject, so frame updates re-render only the overlay.
- The event-card step asks Home's ScrollViewReader to bring the first card into view.
- `Analytics.paused` is set and `observeForYouAlert` is skipped while the tour runs.

**Entry points.**
- First run: the reveal ended (`noteSignInRevealDone` / `signInRevealDidFinish`), or `finishOnboardingFlow` landed
  on Home without opening an event. Then the tour checks: version 3, signed in, no marker, no gate / policy /
  personalization, and the screen is Home.
- Existing persisted sessions never auto-start.
- Marker: `banbe.tour.v3.done.<uid>`, written on Finish or Skip of a first run.
- Help & Legal shows a "Tour the app" row (`help-app-tour` / `help.appTour`) only while version 3 is on. Replay
  never reads or writes the marker.
- The tour aborts (no marker) on a gate, personalization, sign-out, or leaving Home/Account (a deep link).
- `forfeitExpiredHold` on Home mount was left as is. It is server reconciliation that runs on any Home mount anyway.

## Verification (2026-10-27)
**Web**
- `npm run test:unit`: 458/458.
- `npm run build`: OK.
- Public Playwright: `tests/public/signin-morph-tour.spec.js` 3/3, fully mocked Supabase with a synthetic account and
  nothing reaching the backend.
  - A refused login returns the button with its label and an alert.
  - A successful login shows the ✓, then exactly one Login→Home switch, and the gate loader never appears.
  - The v3 tour starts, `#root` is inert, and a click on the highlighted control does nothing.
  - For You (no preferences) is skipped; direct jump and Back work; the Account step highlights the real toggle.
  - Tab is trapped, Escape skips and writes the marker.
  - No writing RPC runs during the tour.
  - The Reduce Motion run passes.
- `onboarding-v2.spec.js` still passes 5/5.
- Signed-in Playwright: `tests/rewards-switch.spec.js` 24/24 across Chromium, Firefox and WebKit, with mocked RPCs.
  - Categories start collapsed; keyboard Enter/Space work; counts are right.
  - The version control makes one call and exactly one version shows as active.
  - The pre-202 fallback is covered.

**iOS**
- `xcodegen generate`, then a clean build with no warnings.
- Unit: `AsyncActionTests` 5/5 and `FeatureFlagsTests` (precedence, category coverage).
- UI:
  - `OnboardingTourUITests` 3/3: Next, missing-target skip, step jump, Back, Account step, Done ends on Home; the
    highlighted control is never pressed; a host sees the Create step.
  - `DiscoveryFixtureUITests.testAdminFeatureSwitchFlipsState`, now opening its category first.
  - `OnboardingV2UITests` 5/5.
- **Migration 202** in a throwaway Postgres 16 container with stubs:
  - versions 3 and 2 set exactly one flag;
  - 4 and NULL are INVALID_VALUE; a non-admin gets NOT_AUTHORIZED;
  - 4 audit rows, anon cannot execute, authenticated can;
  - the rollback drops the function and the rows.

- **Full iOS unit suite + ReviewRetentionUITests:** green.
- **`NavigationUITests` (10 tests): fails, but this predates this work.** It expects the feed as the first screen,
  while signed-out launch has opened Welcome since notes 44/49. Confirmed by running it on an untouched HEAD worktree:
  same failures.

**Not verified**
- On-device feel of the morph, the reveal and the dock-window overlay.
- iPad and landscape.
- VoiceOver and Dynamic Type AX-XXL on the tour card.
- Web at 200% zoom.
- A real iOS sign-in: there is no fixture for it, and the existing login UI tests use real credentials, so they were
  not run.
- `tests/profile-long-intro-and-links.spec.js` (Edit profile save): it writes the shared account's real profile and
  that account is DOB-gated (note 49), so it was not run.

## Going live
1. Apply 202 (`supabase db push`, or apply only 202). Verify with REST OpenAPI that
   `admin_set_onboarding_version` exists, and that `get_feature_flags` returns `onboarding_v3`.
2. Deploy web and ship iOS.
3. An admin picks Version 3 under Feature switches > Onboarding & discovery. Picking 1 or 2 turns it off again
   without a release.

Rollback: `supabase/rollbacks/20261231000202_202_revert_onboarding_version.sql`. The client code falls back to v1/v2
on its own.

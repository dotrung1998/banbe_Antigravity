# 63 — Onboarding Version 2: animated Welcome entrance + swipeable "How banbe works" demos

Status (2026-10-24): IMPLEMENTED LOCALLY (web + iOS), not committed. Migration 201 NOT applied. Until it is, every
client shows Version 1, and flipping the switch in Admin fails with "server does not have this switch".

## What changed
Owner request: make first open / "How banbe works" interactive instead of reading text. The previous experience is
**Version 1**; the new one is **Version 2**. The admin chooses between them.

Owner decisions (2026-10-24):
- Web + iOS.
- One switch controls both the entrance and the story.
- The entrance plays every time Welcome opens. It does not replay when coming back from the story.
- The story is also reachable from Account > Help & Legal (signed-in replay, ends with Done).

## Switch
- Key `onboarding_v2`, boolean. Off or missing = V1, on = V2.
- It is in `OFF_UNLESS_SET` (web `src/lib/featureFlags.js`, iOS `Lib/FeatureFlags.swift`).
- Migration `20261231000201_201_onboarding_v2_switch.sql` inserts the defs row and a seed row (false). Rollback is in
  `supabase/rollbacks/`.
- Client-only: no server function reads it.
- The admin row is "Onboarding demo: Version 2" in `AdminFeatures.jsx` / `AdminFeaturesView.swift`. Its state line
  reads "Showing Version 1/2". On web this uses new optional `stateOn`/`stateOff` fields on the flag entry.
- iOS accessor: `AppState.onboardingV2Enabled`.

## Welcome entrance (V2), timings shared web/iOS, easeOutQuint (.22,1,.36,1)
1. **0–1.0s, photos:**
   - The left photo slides in from the left edge (−70vw / −320pt) and swings 16° into its 7° fan.
   - The right photo does the same from the right (starts 0.08s later).
   - The middle photo rises 50 and scales from 0.88 (starts at 0.2s).
2. **0.75s, For You chip:** comes up 56 from below, from scale 1.35. A gold glow ring flashes at about 1.05s, then
   fades back to the normal hairline.
3. **1.0s + i×0.09s, copy:** headline, subcopy, CTA block and story link each rise 24 over 0.8s.

Reduce Motion: a 0.2–0.3s fade only, no glow, no travel.

How each platform does it:
- **Web:** `.bb-wel-*` classes in `src/index.css`. They use the individual `translate`/`rotate`/`scale` properties, so
  the inline fan `transform` stays.
- **iOS:** `WelcomeIllustration(animated:)` plus the `riseIn` modifier in `WelcomeView.swift`.

## Story V2
- **Copy:** in one place per platform, `src/data/howItWorks.js` and `Models/HowItWorksContent.swift` (twins). V1
  `points` and V2 `cards` live side by side.
- **Body component:** web `src/components/HowBanbeWorks.jsx` (`HowBanbeWorksV1` / `HowBanbeWorksV2`), iOS
  `Views/HowBanbeWorksView.swift` (`HowBanbeWorksBody`). The host passes `finale`: Welcome passes its CTAs, Help passes
  Done.
- **Per section:**
  - Title (emoji + name).
  - A caption that follows the centred screen.
  - A deck of 3–7 demo cards: 66% width (max 280), 4:5, radius 28. Neighbours are scaled 0.86, at opacity 0.45 and
    blurred 3px, interpolated live while dragging.
  - Dots, then a "Swipe to see more" hint until the first swipe.
  - Next goes to the next section; the last section shows the finale.
- **Deck mechanics:**
  - Web: native `scroll-snap`, with per-frame DOM transforms from the distance to centre (no re-render while
    dragging). Arrow keys work.
  - iOS 17: `.scrollTargetBehavior(.viewAligned)` + `.scrollPosition(id:)` + `.scrollTransition`, with a selection
    haptic on snap.
- **Demo cards (made from catalogue data, nothing saved):**
  - quiz: chips toggle.
  - stars: ★ For You stamps on.
  - private.
  - tickets: 1·2·3 changes the total.
  - hold: 30:00 countdown ring.
  - pay: bank card.
  - qr: ticket plus a Schedule dot.
  - organizer: a working switch.
  - free: 0₫.
  - direct: 💸 flows guest → host.
  - 5 × step: progress ring, fields and a tip.
  - recipe: meter fills, ticks stamp in.
  - live: submitted → reviewing → live, with a pulse.
- **Analytics:** unchanged (`public_story_opened/skipped/completed`). Events cannot say which version or entry point
  was used: their fields are whitelisted in a fixture shared with iOS and the server (`tests/unit/appEvents.test.mjs`).

## Help & Legal entry
- **Web:** screen `howItWorks`, route `/help/how-banbe-works`, file `src/screens/HowItWorks.jsx`. Row
  `help-how-it-works` is the first row in the helpLegal group.
- **iOS:** `Screen.helpHowItWorks`, view `HowItWorksScreen`. Row `help.howItWorks`. Back and swipe-back go to
  Help & Legal.
- The Help text "Getting started" (personal guide) now mentions the replay. iOS `HelpContent.swift` was regenerated
  with `scripts/gen-help-content-ios.mjs`.

## Tests
- **Unit:**
  - `tests/unit/featureFlags.test.mjs`: missing = V1.
  - `FeatureFlagsTests.testOnboardingV2IsVersionOneUnlessExplicitlyOn`.
- **Web e2e:** `tests/public/onboarding-v2.spec.js` (V1 text, V2 deck/keyboard swipe/Next ×3/CTAs, demo control, Skip
  with no entrance replay). 4/4 green. Set `HIW_SHOTS=<dir>` to save screenshots.
- **iOS UI:** `OnboardingV2UITests` (4/4 green). The fixture flag is `-uiFixtureOnboardingV2 YES`. Set
  `TEST_RUNNER_HIW_SHOTS=<dir>` for screenshots. The existing V1 story tests still pass.
- **Not verified:**
  - Entrance motion mid-flight on iOS. XCUITest waits for animations, so screenshots only show the end state.
  - On-device feel and dark mode.
  - The signed-in Help entry. No e2e covers it; the public spec cannot sign in.

## Going live
1. `supabase db push` (or apply 201). Check it with the REST method from memory: `get_feature_flags` should include
   `onboarding_v2`.
2. Deploy web and ship iOS.
3. An admin flips "Onboarding demo: Version 2" on. Turning it off returns everyone to V1 without a release.

## Owner device review, 2026-10-24 (round 2)
- **Quiz card:** now shows the REAL onboarding interests question. iOS reuses `OnboardingTopBar` and
  `OnboardingChoiceRow` (no longer private) plus `EventPrefTaxonomy.interests`. Web reuses the exported `ChoiceRow`
  and `QUESTION_COPY` from `EventOnboarding.jsx`. It is laid out at 390pt and scaled into the card. The scale is
  guarded against a 0 width: a divide by zero there hung layout and UI tests.
- **Cards:** bigger (76% width, max 330, 10:13) with larger type. Every card fills its height. Rows use
  `FieldBox(stretch:)` on iOS and `grow` on web, so the boxes themselves grow instead of leaving gaps. Some cards got
  an extra useful row: tickets "held 30 min", pay "seat still held", free "you receive 100%", 3 fields per create
  step, and the money-flow card explains the bank transfer.
- **Wording:** "I've paid" is now "I've transferred".
- **Account card:** left-aligned rows, banbe favicon as the profile picture (iOS asset `BanbeFavicon`), and a host
  tools box that lights up when the switch is on.
- **Swipe to the next section:** a grey chevron pulses on the last screen of sections 1–3, and swiping past it opens
  the next section. Only a drag that STARTS on the last screen counts; otherwise the swipe that lands on it would
  skip the section.
- **Very last screen:** a clay ✓› pill hops with a springy bounce. Swiping past it, or Done in Help, shows a thank-you
  (🎉, confetti, a warm closing wish). Welcome keeps its sign-up buttons under it; Help shows "Back to Help".
- **Looping animations under UI tests:** they hold still when `UITestFixture.isActive`, because XCUITest waits for an
  idle app.
- **Tests:**
  - iOS `OnboardingV2UITests` 5/5, including `testEveryCardAndSwipeToFinish`, which screenshots all 17 cards and the
    thank-you.
  - Web `tests/public/onboarding-v2.spec.js` 5/5. Clicking the bouncing hint needs `force: true`.

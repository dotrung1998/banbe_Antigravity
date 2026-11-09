# 80 — Onboarding v5 (iOS + web): 3 questions, never-empty For You, one choice per screen, chaptered tour

Status (2026-11-09): IMPLEMENTED on iOS, then mirrored on the web (see "Web parity" at the end). No migration. iOS was not built in Xcode and not run on a
simulator or device (the work was done on Linux): the pure model and coordinator were compiled and their 33 unit
tests run with Swift 6.0.3 on Linux, every changed Swift file passes the Swift parser, the web/iOS tour parity test
passes 5/5. SwiftUI views and the UI tests are unverified until an Xcode build runs them.

Prototype: `docs/prototypes/banbe-onboarding-v5-standalone.html` (commit 763e850).

## Plan (what v5 changes, mapped to the iOS app)
1. Welcome: one promise, one main button, "3 questions, about a minute", real event photos on a blurred backdrop.
2. Three questions instead of five: What sounds fun? (interests), When are you usually free? (availability), A
   comfortable ticket price? (budget). Goals and languages stay in Account › Event preferences.
3. Every option shows a live event count; a feedback line answers each tap; Continue waits for an answer, "Skip this
   question" is the other way on; Back is kept.
4. Interest tiles = only types with events on now, most first, at most 5, plus a 6th "More types" tile that searches
   every type (no placeholders, App Review 2.1). Types picked there show as removable chips.
5. "Your For You" reveal that is never empty (4 cases: picked, topped, soon, popular), each saying which case it is
   and offering a way back to the answers.
6. One choice per screen instead of the settings-review list. Each writes a real setting, nothing starts on.
7. Recap (read-only, with where to change each choice) and a tour offer with its length and chapters.
8. Tour: forward only (no Back, no jumpable numbers), short chapters, a break after each chapter, a "do it" step.

## Questions the plan raised, and the answers used
- **Is "News from hosts you follow" a real setting?** No. The app and server have no such switch (notification
  preferences are only the weekly digest and promotional push). Building one would need a migration and a sender.
  Answer: replaced by the closest real, server-backed opt-in, the **weekly digest** (`set_my_digest_opt_in`,
  migration 200), shown only while the `weekly_digest` switch is on, with honest copy (promotional, off unless yes).
- **Which choice screens show?** Decided once when the flow opens (`AppState.onboardingConsents`), only while the
  server owes the settings step: notifications only when Continue would really bring up the iOS alert (ENABLE_PUSH
  build, `push_enabled` on, iOS never asked); digest only while its switch is on; Hosting mode only for someone not
  already in it. The last choice writes `complete_settings_onboarding` as before.
- **Push screen buttons?** One Continue, then the real iOS alert decides (Apple HIG). It also marks the ticket-time
  ask (Q6) as offered so the question never comes twice.
- **What happens to the old settings review (haptics, email documents, host promotional texts)?** Removed with
  `OnboardingSettingsStep`. Haptics keep their stored default (on). Email documents no longer get switched on for new
  accounts (the server default, off, applies; Account still has the switch). Host promotional texts stay off.
- **Availability options?** The server ids can't change (migration 162), so the 4 existing ones (weekdays, weekends,
  daytime, evening) are kept with v5 detail lines, instead of the prototype's weeknights/weekends/daytime.
- **Budget tiers?** Same reason: free / low / medium / flexible (shown as "Price doesn't matter"), VND/USD picker kept
  for the US market. The prototype says budget only ranks; the real matcher excludes pricier events, so the copy says
  that instead ("Pricier events are left out").
- **"You'll hear when a host posts one"?** No such notification exists, so the copy says those types "show up as
  hosts post them" (true: the matcher includes them once they exist).
- **Does Home's For You change?** No. The reveal's "never empty" fill-in is the reveal's own list
  (`OnboardingCounts.reveal`); Home's ★ For You chip still shows exact matches only, and the reveal says so.
- **Can reveal cards still open an event?** No: with choices and a recap after the reveal, opening an event mid-flow
  would skip them. Cards keep ♡ Save.
- **Tour chapters on the real app?** The prototype's Activity tab, Tonight/Weekend tabs and gear don't exist on iOS.
  Chapters reuse the 8 existing step targets so the web parity test (`tests/unit/onboardingTour.test.mjs`) still
  holds: Discover (search, For You, event card, Map), Plans and messages (Schedule, Messages), Your account (Hosting
  mode, and Create for hosts). Copy is iOS-only for now.
- **Which steps are "do it" steps?** Only For You: tapping inside its highlight (or the card's "Tap For You" button,
  which VoiceOver can reach) runs the chip's own action from the overlay; the real control is never pressed. Other
  candidates would navigate off Home/Account, which ends the tour.
- **Who sees the tour?** Everyone who reaches the recap and taps "Start the tour" (no version switch). "Skip, go to
  Home" writes the first-run marker. The Version 3 auto-start after the sign-in reveal is unchanged. The Help & Legal
  "Tour the app" row now shows for every signed-in person (it was Version 3 only), because the recap points there.
- **Gate behind a new switch?** No: iOS-first replacement, no migration. Revert the commit to go back.

## Where things are
- Model, reducer, draft store (key bumped to `banbe.onboardingDraft.v2`), counts and reveal plan:
  `Lib/OnboardingFlow.swift`. Stages: welcome, question, saving, saveFailed, reveal, consent(i), settingsSaving,
  settingsFailed, recap, finished.
- Screens and coordinator: `Views/OnboardingFlowViews.swift`. `OnboardingTopBar`/`OnboardingChoiceRow` are kept for
  the "How banbe works" quiz card.
- Choices and area candidates: `AppState+EventPrefs.swift` (`onboardingConsents`, `applyOnboardingConsent`,
  `forYouAreaCandidates`); push: `AppState+Push.swift` (`canOfferPushInOnboarding`, `requestPushFromOnboarding`).
- Tour: `Models/OnboardingTourContent.swift` (chapters, do-it map, hosting-on copy),
  `State/OnboardingTourController.swift` (phases step / chapterDone / finished),
  `Views/OnboardingTourOverlay.swift` (card, read-only bars, break and finish sheets).
- Analytics unchanged (question ids interests/availability/budget were already whitelisted).

## Tests
- Unit `OnboardingFlowTests` (33): 3-question order, choices → marker → recap, failure paths, redo, coordinator
  writes only on Continue, tiles/counts/reveal modes. Run green on Linux against the real sources (with stubs for
  UIKit-only types), not yet in Xcode.
- UI tests updated: `ReportsAndOnboardingUITests` (onboarding part), `OnboardingTourUITests`,
  `PolishPassUITests.testOnboardingTilesAndFeedback`, `ReviewRetentionUITests.testOnboardingWelcomeSaysHowLongItTakes`.
  Not run.

## Not verified / open
- Xcode build, all UI tests, the look of every new screen (light/dark, Dynamic Type, VoiceOver), the push alert on a
  device, Hosting mode's first-activation sheet appearing over onboarding.

## Web parity (2026-11-09, second pass)
Same flow and rules on the web, same copy (EN/VI). Files:
- `src/lib/onboardingFlow.js`: 3 questions, stages consent/settingsSaving/settingsFailed/recap, `completeSettings`
  effect, draft key `banbe.onboardingDraft.v2`, live counts and `revealPlan` (twin of iOS `OnboardingCounts`).
- `src/screens/EventOnboarding.jsx`: welcome (blurred photo + photo fan), questions with live counts and the "More
  types" sheet, reveal rail, choice screens, recap. `ChoiceRow` and `QUESTION_COPY.interests` are kept for the
  "How banbe works" quiz card. The old settings review (`SettingsStep`) is gone, as on iOS.
- **Choices on web: weekly digest (while `weekly_digest` is on) and Hosting mode only.** The web has no push
  permission, so there is no notifications screen. Continue writes `set_my_digest_opt_in` / `applyOrganizerMode(true)`
  (now exported from the context); Not now writes nothing.
- `src/data/onboardingTour.js` (`TOUR_CHAPTERS`, `TOUR_DO_IT`, `HOSTING_ON_COPY`, `tourPlan`) and
  `src/components/tour/OnboardingTour.jsx`: forward only, chapter breaks, read-only progress, For You do-it step,
  Escape = End tour. Step ids/targets/order unchanged (parity test still 5/5).
- Context: `finishOnboardingFlow({ startTour })`; the recap's "Start the tour" sets `tourRecapStartToken` (no version
  switch), "Skip, go to Home" writes the first-run marker. Help › "Tour the app" shows for every signed-in user.

Web verification: `npm run build` green; unit `onboardingFlow` (29), `onboardingTour` (5), `onboardingVisuals`,
`eventPrefs-forYou` pass (50 total); new mocked Playwright spec `tests/public/onboarding-v5.spec.js` 2/2 (Chromium),
screenshots reviewed at 390×844 (welcome, interests, reveal, choice, recap, tour do-it, chapter break).
`tests/public/signin-morph-tour.spec.js` was updated for the chaptered tour. Its "success" test already failed on the
base commit at `login-submit-check` (the ✓ morph), unrelated to this change; with that one line removed locally, the
updated tour part passes. `onboarding-v2.spec.js` 5/5. Not checked on web: Firefox/WebKit, dark mode, real backend.

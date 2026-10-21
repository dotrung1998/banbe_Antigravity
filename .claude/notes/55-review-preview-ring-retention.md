# 55 — Real-detail Public preview, progress ring, For You intro motion, delete-account retention, post-signup Home

Status: IMPLEMENTED LOCALLY (web + iOS), NOT committed. iOS checked in the simulator through new UI tests and their
screenshots (`ReviewRetentionUITests`). Web: unit tests and the build pass, but it has NOT been checked visually, because
these screens need a signed-in host or new account and the signed-in Playwright suite is blocked by the DOB gate (note 49).

Source: the owner's 5 device screenshots plus their task list (2026-10-21). Plan:
`~/.claude/plans/calm-booping-hanrahan.md`.

## 1. Create-event "Public preview" is the real Event Detail
- **iOS.** `EventDetailView(preview: EventDetailPreview)` renders the draft through the real page.
  - `CatalogEvent.fromDraft(EventDraft)` builds the event. The key is `draft-preview`.
  - The `where` line has no distance segment. The old preview showed "9665,7 km away".
  - In preview mode nothing is fetched or saved: photos, org stats, criteria, eligibility and the scroll memory are
    all skipped, and the close gestures are off.
  - These are visible but inert: ⋯, share, save, calendar pill, track record, host card, seat chips and Reserve.
  - The preview always shows 1 ticket.
  - The back pill returns to the Private tab.
  - The review sheet's Confirm & submit (`confirmBlock`) sits under the inert reserve bar.
  - The old hand-built public layout and its own Included sheet, organizer screen and photo viewer were removed.
- **Web.** `EventDetail({ preview })` with `shapeDraftAsCurEvent` (`src/lib/draftPreview.js`), using the same rules.
  It is mounted full-screen over `ReviewStep` while the public tab is open.
- **Rotation.** Staged local photos are now baked upright (`UIImage.normalizedUp()`, `MediaUploader.swift`). This
  matches the uploaded copy.
  - Caveat: SwiftUI's `Image(uiImage:)` already honours EXIF orientation, so the sideways cover in the owner's
    screenshot is not proven to be this bug. Re-check on a device with a portrait photo.
- **Gotcha.** Don't put `.accessibilityIdentifier` on the `EventDetailView` container. It overrides every child id,
  including `event.back`.

## 2. StepProgress: a ring instead of the bar
- iOS `FormControls.swift` and web `FormControls.jsx`.
- The linear bar is gone. The percentage sits in a 44pt ring.
- The message and the percentage use one size (footnote/13px semibold) at full ink. The `showsBar`/`showBar` parameter
  was removed.
- This reaches create-event, the iOS signup gate and the booking journey.

## 3. For You intro
- **Equal tiles.** All three cards share the tallest height and are top-aligned. The third title is now "Đổi lúc nào"
  (was "Đổi bất cứ lúc nào", which wrapped).
- **Entrance.** The content rises 24pt while fading in. The tiles land left to right, at `0.12 + i·0.07`s on iOS and
  `120 + i·70`ms on web. With Reduce Motion it is a fade only.
- **iOS jerk fix.**
  - `applySession` now awaits the event-preferences load before it lifts the account gate. Before, Home could flash
    between "Complete sign-up" and the intro.
  - RootView animates the gate and onboarding overlays (`showsAccountGate` / `showsEventOnboarding`).

## 4. Delete account: "Before you go" pop-up
- Based on "We Studied 393 Cancel Flows. This Wins People Back." Only the title was readable; the owner chose
  "ask why + tailored fix".
- **Pop-up contents.**
  - What you'd lose: booked events, hosted events (with the open-events blocker note), saved events, followed hosts,
    and coins (only while the Rewards switch is on). Rows with zero are hidden.
  - The six existing reason chips.
  - One offer for the picked reason:

| Reason | Offer |
|---|---|
| `too_many_notifications` | Mute `event_announcement` and turn off host promo consent. Transactional kinds stay on. |
| `not_using` | Event preferences |
| `privacy` | Security |
| `found_alternative`, `other`, `prefer_not_say` | Sign out |

- **Buttons.**
  - "Keep my account" (ink).
  - "Continue deleting" (plain alert text). It opens the existing wizard at **confirm**, with the reason filled in and
    the identity card and permanence note carried up. Apple 5.1.1(v): deletion stays one tap away.
- **Files.**
  - Logic: `Lib/AccountRetention.swift` and `src/lib/accountRetention.js`.
  - Views: `DeleteAccountStayView.swift` and `DeleteAccountStaySheet.jsx`.
  - State: `deleteAccountStayOpen`, `deleteAccountContinue` and `deleteAccountPresetReason` on iOS.
    `deleteAccountStayOpen` and `deleteAccountFromStay` on web.
  - The wizards share the reason list.

## 5. Post-signup Home at the top, and the checklist celebrates
- **Cause.** Home's saved scroll from guest browsing was never cleared, so it was restored after signup. On iOS,
  `.scrollPosition(id:)` also kept the first feed card in place when the checklist was inserted above it.
- **Fix.**
  - iOS: `resetHomeScrollToTop()` (anchor/offset nil, plus `homeScrollToTopToken`). `ScaffoldScrollProbe.pinToTop()`
    holds the top for about 0.5s and stops when the user touches the screen. It runs on account change, sign-out and
    `finishOnboardingFlow`.
  - Web: `homeScrollTopToken` and an account-change effect in `App.jsx`.
- **Celebration.**
  - The checklist state gained `celebrated`. The iOS decoder is tolerant, so states saved before it still load.
  - When every item is done, the card shows "Bạn đã sẵn sàng! 🎉" with ConfettiBurst and a success haptic (iOS). It
    folds away after 2.4s and never shows again.

## Tests
- **Web.** `npm run test:unit` is 333/333, including new `accountRetention` and `draftPreview` tests and the updated
  checklist test. `npm run build` passes.
- **iOS.**
  - New unit tests `AccountRetentionTests` and `CatalogEventDraftTests`; `OnboardingFlowTests` updated.
  - UI tests: `ReviewRetentionUITests` (4) and `PolishPassUITests` (7) are all green.
  - DEBUG fixture `-uiFixtureReview YES` with `shell.create` opens Review with synthetic photos, one of them stored
    sideways.
  - Already failing on HEAD and not touched here: `GiftTicketPDFTests.testPDFLinksPointAtRealDestinations` and
    `PublicEntryTests.testNotificationsReturnsToWhereItWasOpened`.

## Not verified
- On a real device: the overall feel of the gate → intro motion, and the Home scroll after a real signup.
- The checklist celebration was not run in any fixture.
- Any web visual check.

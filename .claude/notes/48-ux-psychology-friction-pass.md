# 48 — UX psychology / low-friction pass (2026-10-18)

Status: IMPLEMENTED LOCALLY (iOS: everything below; web: everything except guest browsing), NOT committed/deployed. No migration. Source: the video "The UX Psychology Behind Apps People Can't Stop Using" (YouTube 2TlIg3VokY8, read through the sozai.app transcript because YouTube blocked direct access). Plan: `~/.claude/plans/i-have-a-very-effervescent-river.md`.

## The six principles and how they're applied (guardrails first)
- Smart defaults never apply to **consent**, and never to **money the host didn't choose**. A returning host's own last price is theirs to reuse; a first event never gets a stock price.
- Loss and contrast framing is used only in honest forms: the real 30-minute hold, real unsaved input, real prices of similar events. There's no confirmshaming ("I'll risk it"), no fake scarcity and no hidden fees.

| Principle | What changed |
|---|---|
| 1 Smart defaults | Create event pre-fills from the host's last event (weekday, time, price, category) or, for a first event, next Saturday ≥2 days out at 19:00 with no price. **Seats are never pre-filled on iOS** (start at 0, so the Tickets step only ticks once the host sets capacity; user request 2026-10-18). Web still pre-fills 14 / the last event's capacity — align when web gets the step flow. A "Prefilled from …" notice offers **Start blank**. Location is never copied, since a new address must be re-confirmed. Date/time quick picks were added to the shared `EventDateTimeSheet` (surveys get them too). Price chips: Free/200k/300k/500k. Seats: chips (10/20/30/50) plus a stepper. Refund accounts: holder pre-filled from the profile name, plus top-10 Vietnamese bank chips. Buttons now state the outcome: "Hold 2 seats ▪︎ 30 min", "Review your event", "Save account". |
| 2 Goal gradient | Shared `StepProgress` (named steps, %, head start). Onboarding counts "Account ✓" as done, so question 1 opens at 17%. Booking journey "Event ✓ → Hold → Pay → Ticket" appears on Reserve and Confirmed (hidden for expired/disputed bookings). Create event has a sticky, tappable section bar (Host/Basics/When & where/Tickets/Photos, any order). Account gate shows "Account ✓ · Phone · Birthday". |
| 3 Reciprocity / 4 IKEA | **iOS only:** read-only guest browsing of Home/Map/Event. Welcome's primary button is now "Explore events". Save/Follow/Reserve/Message/Like open a contextual `GuestPromptSheet` ("Continue" / "Log in" / "Not now"). Sign-in resumes the action (`AuthResume`). |
| 5 Loss (honest) | Leaving a new create-event draft with input asks "Discard this event? Your N photos and details will be lost." with neutral Keep editing / Discard buttons. The hold countdown already existed (ConfirmedView). |
| 6 Contrast (honest) | Price hint "Similar events: X–Y" (middle half of paid prices of loaded live events in the same category; hidden with fewer than 5 samples). |

Also part of this pass:
- **Promo-text consent defaults to OFF** on both platforms. This resolves note 43's open decision; the server default (migration 123) was already OFF. iOS writes consent only when the stored value loaded and the person changed it. Web's pre-enabled Location toggle was removed (iOS parity).
- Disabled buttons now say why ("Add the date of birth for ticket 2", "Still needed: …").
- **Bug fix:** the iOS refund-account Save button was always enabled-looking and silently did nothing on an incomplete form (`canSave` was never passed to it).
- Create-event field errors appear only after a Review attempt (iOS; web already did this). Tapping Review with gaps scrolls to the first incomplete section.
- Survey create: closing days and max group size are steppers, and budget/activity options are editable chips (same stored labels). Survey response group size is a stepper (0 = unanswered).

## Files
- **iOS new:**
  - `Views/FormControls.swift`: `ChoiceChip`, `CountStepper`, `StepProgress` (+`completed:` flags, `onSelect:`), `StepProgressModel`, `ProgressEncouragement`, `BookingJourneyProgress`, `OptionChipsEditor`.
  - `Lib/SmartDefaults.swift`: banks, gaps, `eventDraftDefaults`, `nextWeekday` (Vietnam calendar), quick picks, `similarPriceRange`.
  - `State/AppState+GuestAccess.swift`
  - `Views/GuestPromptSheet.swift` (+`GuestBrowseBanner`)
  - Tests: `SmartDefaultsTests`, `GuestAccessTests`.
- **iOS changed:**
  - `InkButton.disabledReason` in Components.
  - ReserveView, ConfirmedView, RefundAccountsView
  - CreateEventView + `EventDateTimeSheet` in OnboardingViews
  - `AppState.applyCreateDefaults/clearCreateDefaults/createDraftMatchesAppliedDefaults/lastHostedEventSnapshot` (`goCreate` applies the defaults; once the host's events load it upgrades them, but only if the draft is still untouched)
  - OnboardingFlowViews top bar, AccountGateViews, EventPreferencesViews (promo), SurveysHostingView, SurveyPublicView
  - WelcomeView, HomeView (guest banner; survey row and Action Center hidden for guests)
  - RootView (prompt sheet, resume, redirect back-target), PublicEntry `protectedRedirect(from:browsable:)`
  - Analytics: `guest_browse_started`, `guest_signin_prompt_shown/accepted(context)`, `create_event_started_blank`
- **Web new:** `src/components/ui/FormControls.jsx` (the same controls plus a real `<button disabled>` InkButton with a reason), `src/lib/smartDefaults.js`.
- **Web changed:** Reserve.jsx (the Reserve button was a clickable `div`), RefundAccounts.jsx, CreateEvent.jsx, EventOnboarding.jsx, SurveysHosting.jsx, SurveyPublic.jsx, BanBeContext.jsx (`goCreate` defaults + last-event upgrade, `clearCreateDefaults`), tests/payment-state-machine.spec.js (label guard keeps "30" and drops the exact old string).

## Guest browsing: audit and decisions (iOS)
- **Reverses note 09's "no guest browsing".** `guestAllowedScreens` now includes `.home`, `.mapExplore` and `.event`. Everything personal still goes through `promptSignIn`/`requireAuth` or the RootView guard. Login's Back returns to the browse screen the guest came from (`guestBrowseScreens`).
- **Data that anon can read:**
  - `events_select_public` (113) = live/ended/cancelled **and** public, so invite-only, draft and review events are invisible.
  - The private photo bucket fails closed for anon.
  - Pulse and organizer-profile RPCs are anon-granted and filtered to public data.
  - The account gate (123/126) applies only to `authenticated`. Keep `AccountGateOverlay` covering the app: a half-enrolled session sends an authenticated JWT and gets 403 everywhere.
- **Fixed for guests:** `applySession(nil)` now also clears `homeStories` (signed private story URLs), `homeSurveyDiscovery`, `myAdminInvite`, refund/host lists, `following`, `photoEngagement`, `realEventsByID` and `eventPhotoURLs`. Otherwise a guest on a shared phone would have seen the previous account's data.
- **Save/follow fixes:**
  - Guest save/follow used to flip locally and vanish; they now ask instead.
  - Following an organizer or from Pulse used to do nothing silently; it now asks.
  - Photo like used to send the guest to Account after login; it now asks in place.
- **Reserve from a guest:** resumes through `goReserve()` after sign-in, so the attendee drafts and the eligibility check are set up. The old `returnTo: .reserve` skipped both.
- **Not done:**
  - Guest For You onboarding before sign-up (answers on-device, migrated on sign-in). It needs the server-driven onboarding flags and overlay conditions reworked; Welcome's story copy still correctly says "after you sign up".
  - Web guest browsing. It needs its own audit of web sign-out state clearing and loaders first.

## SECURITY: pre-existing, NOT fixed here (needs a migration + owner decision)
- `organizers_select_public` is `USING (true)` for **anon** (001:115) with no column revoke. Anyone holding the shipped anon key can read every organizer's `bank_name`, `bank_account_name`, `bank_account_no`, `momo_phone`, `pay_qr_path`, `pay_qr_payload`, `tax_code` and `owner_id`/`user_id`.
  - This is live today, independent of guest browsing.
  - Suggested fix: revoke SELECT on organizers from anon and grant only the public columns (id, name, avatar fields, bio fields…). Check what the signed-out pages (organizerProfile/Team via RPCs) and payment screens (authenticated) actually select first.
- `toggle_photo_like` is revoked from anon but not from PUBLIC (083:94). It's harmless because the body raises AUTH_REQUIRED, but it's the same pattern migration 184 fixed for `log_photo_share`.
- Minor: anon can read `reviewed_by`, `rejection_reason` and `withdrawal_reason` columns on public events. `get_photo_engagement` has no visibility filter, but photo UUIDs aren't discoverable by anon.

## Verification (2026-10-18, Xcode 27, iPhone 17e simulator)
- iOS app build: OK. Unit tests: 258 run. The only failure is the PRE-EXISTING `GiftTicketPDFTests.testPDFLinksPointAtRealDestinations` (it also fails at baseline, see note 44). The new SmartDefaultsTests (14) and GuestAccessTests (6) are green.
- iOS fixture UI suites (PublicEntrySchedule, ReportsAndOnboarding, PhaseGAccessibilityAudit, ShellFixture):
  - All Welcome, routing and onboarding tests pass, including the updated `testVietnamesePublicEntry` and the new `testExploreEventsBrowsesHomeAsGuest`. `testWelcomeAudit` (accessibility) passes.
  - The remaining failures are PRE-EXISTING; each was re-run on a clean HEAD worktree and failed there too:
    - 4 Schedule/plan accessibility audits ("Discover" Dynamic Type, a 0×0 hit area)
    - `testDiscoverShowsOnlyNonPlansWithHonestConflictAndAdds`
    - 3 ShellFixture swipe/Account-tab tests
  - `testAppleCalendarEditorPresentsAndCancelIsHonest` and `testAddToBanbeScheduleThenNoDuplicate` are flaky: each failed in one full-suite run and passed in another, on both trees.
- Web: `vite build` OK. `npm run test:unit` 219/219.
- Playwright (chromium) on onboarding/create-event/payment/auth specs: 12 pass, 5 fail. **The same 5 fail on a clean HEAD worktree**: they time out waiting for Home in `setupToHome`, an environment/session issue, not this change.
- **Not verified:**
  - Real device; screenshots of each new control in light/dark × VI/EN.
  - A real guest session against production data. Network UI suites are still environment-blocked by the DOB gate (note 44).
  - VoiceOver on the new controls (they have adjustable/selected traits, but haven't been audited by hand).
  - Web controls rendered in a browser.

## 2026-10-18 follow-ups (iOS, from on-device review)
- Guest sign-in sheet hides the dock (`.hidesDock`) and was redesigned (context icon tile, 3 benefit rows, Continue / Log in / Not now).
- Dock returns to full size on any section change (screen, Account tab, Schedule mode, Inbox view) via `resetDockSizeForNewSection()`, with a 0.6s scroll-collapse pause.
- Create event is a 5-step flow (one section per page, Back/Next, tap a numbered step to jump), numbered step bar with % + encouraging line, icon labels + large rounded outlined fields (`BanbeField(icon:)`, `FormFieldLabel`, `roundedFormEditor`), redesigned Included editor.

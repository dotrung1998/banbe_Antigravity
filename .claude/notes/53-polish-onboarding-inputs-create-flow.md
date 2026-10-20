# 53 — Polish pass: onboarding visuals, field states, create-event flow (2026-10-20)

Status: IMPLEMENTED LOCALLY (web + iOS), NOT committed. No migration. Plan:
`~/.claude/plans/pasted-content-id-1ce6-i-would-cryptic-newell.md`.

Sources:
- The owner's on-device screenshots.
- Three video notes:
  - Tim Gabe, "How top 1% apps earn your second visit" (peak-end rule, put the ask inside the peak).
  - Kole Jain, "Every UI/UX concept in 10 minutes" (hierarchy, input states, feedback).
  - uxpeak, "Junior to senior" (emoji + live feedback on choices, selection over typing).
- Event-app research: Partiful, Ticketmaster/StubHub onboarding, Baymard ticketing.

## What changed and why

| Owner's issue | Root cause | Fix |
|---|---|---|
| Onboarding buttons look alike; screens are text-heavy | On iOS, a **selected answer row was solid ink, the same as the Continue button**. Secondary actions were only underlined text. Each question showed 3 progress indicators | One 3-level button system: primary = solid ink; secondary = `field` fill + hairline (`SecondaryButton` / `Button variant="secondary"`); tertiary = text only. Selected answers are a tint + ink outline + check + bigger emoji, never solid ink. Emoji per answer (`PrefEmoji` / `OPTION_EMOJI`, keyed by the fixed migration-162 ids) and per question; 2-column tiles for short answers; a live "what this does" line under the options; one compact progress line (bar + `n/5`). |
| No focus feedback on fields | Web set `outline: 'none'` in 56 places with no replacement; iOS `BanbeField` had no focus state | Field states with existing tokens: **focus = clay border + soft clay halo**, error = alert, warning = honey. Web: global `:where(input…)` rules in `index.css` (inset + outer ring, because `theme.js fieldGlass` masks its element); bare inputs inside a styled pill use `data-bare` + `.bb-focus-ring`. iOS: `FieldChrome` / `.fieldChrome(focused:state:)`; `BanbeField` tracks its own focus or takes `focus:`/`focusID:`. |
| Recipe bar loads before the rest of the screen | iOS drew the Host step on the first frame, then `onAppear` swapped to Basics. The bar lives in `.safeAreaInset` (instant) while the body cross-faded. The meter was hidden on Host, so it popped in | Starts on Host (no swap). The meter shows on every step, so the header height never changes. Steps slide in a direction (`stepTransition`) in the same transaction as the bar. |
| Fix goes to the step, not the field | `fix.field` was never read | `createFieldGuide.js` / `CreateFieldGuide.swift` map field → step. `guideTo(field, hint)` opens the step, centres the field, plays the For You halo reshaped for a rounded field (`.bb-attn` / `attentionHalo`), shows a "👇 tip" that floats ABOVE the field (out of layout), and focuses typing fields. Web renders the step with `flushSync` so `focus()` happens inside the tap (iOS Safari only opens the keyboard then). Review-with-gaps lands on the first missing field the same way. |
| Starts at step 2 | Deliberate "skip Host" (note 48) | **Superseded:** always opens on step 1. Host ✓ / 20% still show, plus "✓ Filled from your organizer profile — check it and continue" and a "Looks good · Next: Basics" button. |
| Keyboard covers Event introduction | iOS `TextEditor` scrolls inside itself, so the screen scroll only saw its top edge; there was no focus tracking. Web had no `visualViewport` handling | iOS: one `@FocusState focusedField: String?` across all Create inputs; on change, scroll that field to centre after the keyboard settles; `.scrollDismissesKeyboard(.interactively)`. Intro and greeting use `TextField(axis: .vertical).lineLimit(5...12)` (grows with the text). Web: `useKeepFocusedVisible()` in App's Shell (app-wide). Intro counter turns honey at 3800 and alert at 4000. |

Also in this pass:
- **Login: "already has an account" / "no account" is a warning on the email field** with a one-tap "Log in instead?" / "Sign up instead?". The email is kept across the switch.
  - Web: `authEmailIssue` state.
  - iOS: `AuthViewModel.errorCode` and `BanbeField(noteAction:)`. This also localises the iOS message, which was English-only.
- **Peak-end moments:**
  - Onboarding reveal: confetti (`ConfettiBurst`, both platforms) + `Haptics.success()`, and a ♡ Save on each revealed card (the ask inside the peak).
  - Event submitted: 🎉, confetti + haptic, and an honest "✓ Sent → banbe reviews → goes live, we'll notify you". This deviates from the plan: **no "Share link"**, because a pending event has no public page yet.
- Policy gate and Welcome use the shared button levels. Pressed state everywhere: `.bb-press` / `PressableButtonStyle` (scale 0.97 + dim + light haptic; no movement under Reduce Motion).

## Not done (proposed, needs owner go-ahead)
- Live Activity for the 30-min hold.
- Ticket "unwrap" reveal.
- Fee-inclusive total before Reserve.
- "Recent venues" chips in When & where (from plan Phase 3). Skipped: the loaded event summaries would need their address checked first, and this pass was already large.
- Reserving height for benchmark-driven lines (demand line, keyword suggestions). Skipped because migration 186 isn't applied: they always resolve to nothing, so a placeholder would only add an empty gap.

## Files
- **Web new:**
  - `src/lib/createFieldGuide.js`
  - `src/lib/useKeepFocusedVisible.js`
  - `src/components/ui/ConfettiBurst.jsx`
  - `tests/unit/createFieldGuide.test.mjs`
  - `tests/unit/onboardingVisuals.test.mjs`
- **Web changed:**
  - `index.css`: field states, `.bb-press`, `.bb-attn`, confetti
  - `FormControls.jsx`: `Button`, `FieldNote`
  - `CreateEvent.jsx`
  - `EventOnboarding.jsx`
  - `Welcome.jsx`
  - `Policy.jsx`
  - `Login.jsx`
  - `BanBeContext.jsx`: `authEmailIssue`
  - `eventPrefs.js`: emoji
  - `onboardingFlow.js`: `selectionFeedback`
  - `App.jsx`
  - `MapExplore.jsx`, `Following.jsx`, `AreaSheet.jsx`: `data-bare`
- **iOS new:**
  - `Lib/CreateFieldGuide.swift`
  - `Views/ConfettiBurst.swift`
  - `BanbeAppTests/CreateFieldGuideTests.swift`
  - `BanbeAppTests/OnboardingVisualsTests.swift`
  - `BanbeAppUITests/PolishPassUITests.swift`
- **iOS changed:**
  - `Components.swift`: `PressableButtonStyle`, `SecondaryButton`, `FieldState`, `FieldChrome`, `FieldNote`, `BanbeField` focus/state
  - `ForYouAlert.swift`: `cornerRadius`, `FieldAttentionHalo`
  - `OnboardingViews.swift`: `CreateEventView`
  - `OnboardingFlowViews.swift`
  - `WelcomeView.swift`
  - `PolicyView.swift`
  - `LoginView.swift`
  - `AuthViewModel.swift`
  - `EventPreferences.swift`: `PrefEmoji`
  - `OnboardingFlow.swift`: `OnboardingFeedback`
  - `DiscoveryFixtureUITests.swift`: Create now opens on Host
- Run `xcodegen generate` after pulling.

## Verified (2026-10-20, Xcode 27, iPhone 17e simulator, iOS 26.5)
- **Web:**
  - `npm run test:unit`: 321/321 (5 + 3 new tests).
  - `vite build` OK.
  - Playwright screenshots (guest, 390×844) of Welcome and Login (error border + message; clay focus ring). No page errors.
- **iOS:**
  - Builds.
  - `BanbeAppTests`: 300 run. The 3 failures are pre-existing and fail identically on a clean HEAD worktree: `GiftTicketPDFTests.testPDFLinksPointAtRealDestinations` (2 assertions) and `PublicEntryTests.testNotificationsReturnsToWhereItWasOpened`.
  - `PolishPassUITests`: 4/4. Their screenshots show:
    - Host step with the meter
    - Fix → keywords focused with keyboard + halo + tip above
    - intro typed with keyboard up and fully visible
    - onboarding tiles with tint selection + feedback line
  - `ReportsAndOnboarding`, `PublicEntrySchedule` and `DiscoveryFixture` suites: all pass except `testAddToBanbeScheduleThenNoDuplicate` and `testDiscoverShowsOnlyNonPlansWithHonestConflictAndAdds`. Both are pre-existing: they fail identically on clean HEAD, see note 48.
- **NOT verified:**
  - A real device (the owner's original repro).
  - Dark mode / VI screenshots of the new screens.
  - Web Create and onboarding in a browser (DOB-gated test account, note 49).
  - VoiceOver pass on the new tiles.
  - The note-47 Home mount-count test (RootView was not touched).

## Follow-up 2026-10-20 (owner's on-device report)
1. **Crash after "create new event → make changes → go back": FIXED (simulator-verified; device re-test by the owner pending).**
   - Two device crash logs were pulled from the connected iPhone with `xcrun devicectl device copy from --domain-type systemCrashLogs`.
   - Both show EXC_BAD_ACCESS in the main thread's **stack guard** while rendering `CreateEventView.createFormScroll`. There were only 76 frames, but the 1 MB stack was full.
   - Cause:
     - In a Debug build, SwiftUI's unspecialised generic inits (VStack/TupleView/Group...) keep copies of the view value on the stack.
     - The whole form was one ~20 KB value: Basics 8.4 KB, When & where 3.9 KB and Host 1.5 KB measured unerased, plus Tickets, Photos and the header.
     - This pass's richer `BanbeField` and `guided` overlays pushed it past the iPhone's 1 MB main stack. The simulator's larger stack never overflowed, so the UI tests couldn't reproduce it.
     - Static `sub sp` frame sizes are unchanged from HEAD (createFormScroll closure 10.5 → 10.9 KB). The growth is in these dynamic copies.
   - Fix: each step is its own `AnyView` property (`hostStepView`…`photosStepView`) and `guided()` returns `AnyView`. Measured afterwards: each step is 0.6–2 KB, and the form holds only AnyView boxes.
   - **Rule for this screen:** keep new sections type-erased. Don't inline big view trees back into `createFormScroll`.
   - Tests: `PolishPassUITests` gained leave-after-typing, leave-with-keyboard-up and real-entry (`shell.createNew` fixture → `goCreate()`) back-navigation tests. All pass.
2. **Dock switching felt jerky: FIXED (simulator dock tests pass; feel to be judged on device).**
   - Cause: every dock tap ran the push/pop slide (`.move(edge:)` + opacity, 0.28s), with two full screens moving at once.
   - Fix: a dock tap now sets `AppState.dockTabSwitch` (plain var, not @Published) for 0.4s. RootView then uses `.opacity` with `.easeOut(0.16)` for dock screens. Swipes and push/pop keep their motion.
   - Debug builds are much slower in SwiftUI: judge smoothness on a **Release** run (Scheme → Run → Build Configuration: Release).
   - `ShellFixtureUITests`: all pass except `testAccountTabsAreSwipeableAndStayInAccount`, which is pre-existing (note 48).
3. **Dock tabs: logo + title jumped between Home / Schedule / Messages / Account: FIXED.**
   - Measured on an iPhone 17 simulator, title frame per tab (`DockHeaderUITests`):

     | Tab | x | y | Cause |
     |---|---|---|---|
     | Home | 142 | 103.3 EN / 104.0 VI | `ViewThatFits` row height |
     | Schedule | 140 | 99.3 | 8pt gap; shorter row; top 12 |
     | Messages | 144 | 103.3 | 24pt side padding |
     | Account | 140 | 103.3 | 8pt gap |

   - Fix: one shared `DockHeaderTitle` in Components.swift: 112pt wordmark, 10pt gap, display 27, 52pt row, 20pt side padding.
     - All four tabs use it.
     - Home's header row is pinned to 52pt.
     - Messages and Account rows are pinned to 52pt.
     - Schedule's top padding is 16.
   - Result: every tab is at x 142, y 104.0, height 32.3, in EN and VI. Guarded by `DockHeaderUITests`.
   - Home's narrow-phone fallback variants (smaller wordmark) still apply only when the full row can't fit.
4. **Same dock-header fix on web (2026-10-20).**
   - Before, in code:

     | Tab | Top | Side | Gap | Other |
     |---|---|---|---|---|
     | Home | 62 | 20 | 8 with rewards shortcuts, else 10 | |
     | Schedule | 58 | 20 | 14 | `h1` |
     | Messages | 62 | 24 | 10 | "Tin Nhắn" |
     | Account | 66 | 20 | 10 | |

   - Now all four use `src/components/ui/DockHeaderTitle.jsx` (`DOCK_HEADER`: top 62, side 20, row 52, wordmark 96, gap 10, title 27). `homeHeaderLayout.js` `wordmarkGap` is now 10.
   - Measured in Chromium (390×844, EN + VI, via the dev-only `window.__banbeDevSet` hook in BanBeContext; it is stripped from production builds): every tab has its logo at x 20 / y 66.3 / 96×43.3 and its title at x 126 / midY 88.0.
   - Unit tests 321/321, `vite build` OK.

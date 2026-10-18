# 47 — iOS event zoom from Home: jerk + white flash from the second open (2026-10-18)

Status: FIXED LOCALLY (iOS only), not committed. Simulator-verified with a regression test; feel on a real device still to be confirmed by the owner.

## Symptom
Opening or closing an event from Home zoomed smoothly once. From the second event on it was jerky, with a brief white flash.

## Root cause (measured, not guessed)
`RootView` wrapped the screen stack in `if dock screen { rootScreenStack.simultaneousGesture(tabSwipe) } else { rootScreenStack }`. The two branches of an `if/else` are different views to SwiftUI. Home is a dock screen and Event Detail isn't, so **every** open and **every** close destroyed the entire screen stack and built a new one.
- The "live Home underlay" that the zoom relies on (`eventHasLiveUnderlay`, c071170) was in fact a **brand-new HomeView** on each open and close. Its ~10 `.task` loaders, scroll restore, ForYou alert replay and card photo loads all re-ran mid-zoom, publishing AppState changes while the spring ran. That was the jerk.
- During the branch switch, the old and new stacks **cross-faded** (the default `.opacity` transition under the screen spring), with the paper background showing through both half-transparent layers. That was the white flash.
- Measured: a temporary log on HomeView appear/disappear showed one new appear and one old disappear on every open and every close. The new regression test counted Home mounts going **1 → 11** across 5 open/close cycles before the fix, and staying at **1** after it.
- The `if/else` (ec06c78) predates the zoom (c071170), so the zoom's "Home stays mounted" design never actually held.

Second, timing-dependent bug: `eventOpening` was cleared by a fixed 1.4s timer and `eventClosing` by a 0.6s timer. After open → close → reopen within that window, the first open's timer cleared the flag halfway through the second zoom. `zoomOrigin` went nil, so the hero snapped from the card to the centre pose.

## Fix
- `RootView`: there is now one branch. `rootScreenStack.simultaneousGesture(tabSwipeGesture, including: isDockScreen ? .all : .subviews)`. The `.subviews` mask disables only the tab-swipe recognizer, so on pushed screens it still never competes with the edge-swipe strip (the reason the `if/else` existed). The stack's identity is now stable through every navigation.
- `AppState.goEvent`: the open timer only clears `eventOpening` if `eventOpenTick` is unchanged. `backFromEvent` clears `eventOpening` and only the latest close (`eventCloseGeneration`) clears `eventClosing`.
- `EventDetailView.zoomOrigin`: closing takes priority over a still-flagged open (shrinks into the card's live frame).
- `goEvent` in fixture mode now runs the real navigation and zoom bookkeeping and skips only the two network loads. Before, it took a shortcut that never set `eventBackScreen` or the zoom, so the bug couldn't be tested.

## Side effect to watch on device
Any navigation between a dock screen and a pushed screen (not just events, e.g. Account → Reports) used to get an extra whole-stack cross-fade from the branch switch. Now only each screen's own `transition(for:)` plays (slide + fade), which is the intended motion. It should feel the same or cleaner; flag it if anything looks different.

## Tests
- New in `ShellFixtureUITests` (real RootView, `-uiFixture shell.home`, no network):
  - `testOpeningAndClosingEventsNeverRebuildsHome`: 3 open/close cycles plus a quick reopen inside the 1.4s window; asserts the DEBUG-only `fixture.homeMounts` counter is unchanged. It **fails without the fix** (11 vs 1) and passes with it.
  - `testEdgeSwipeBackFromEventStillReachesHome`.
- `UITestFixture.homeMounts` is DEBUG-only (HomeView onAppear bumps it under fixtures; the shell fixture shows it as an invisible element).
- Shell suite: 9/12 pass. The 3 failures (`testAccountTabsAreSwipeableAndStayInAccount` 20 < 44pt touch target, `testSwipeOnTheWeekStripChangesWeekAndNeverTheSection`, `testSwipeOverTheAgendaStillSwitchesDockSections`) fail **identically without this fix**, so they are pre-existing and left alone.
- Unit tests: 239 run; the only failure is the pre-existing `GiftTicketPDFTests.testPDFLinksPointAtRealDestinations` (note 43).
- Not run: the network/login UI suites (`InteractionPrecedenceUITests`, `BottomTabBarUITests`).
- **On device:** the zoom feel on repeated opens, edge-swipe back from an event, and dock tab swipes.

## Follow-up pass (same day, after on-device review: stutter confirmed fixed)

### Haptics
- Removed: the tick on opening an event (`EventDetailView.onAppear`) and on opening a photo (`AppState.openPhoto`), on closing (`closeAnimated`, `AppState.backFromEvent`, which also covered edge-swipe back, and the photo viewer's `dismiss()`), and on switching dock tabs (`BottomTabBar` selection tick).
- Kept/added: exactly one light tick during a downward drag-to-close, at the moment the drag passes the point where letting go closes (Event Detail: 140pt, `dismissCloseDistance`; photo viewer: `swipeThreshold` 44pt). It re-arms if the finger comes back above the point. Nothing on release, during the shrink, or when the dock appears. Tap-to-close and the Back button are silent.
- Untouched: toast, favourite toggle, filters, header buttons and the other haptics elsewhere.

### Drag-down close landed below the card (Back button was fine)
Root cause, measured with screenshots timed after release (hero outlined red, card blue): while dragged, the WHOLE Event Detail, cover photo included, was scaled about the page centre (1 − 0.16p), pushed down (0.35 × drag) and masked. On release, the photo shrank into the card while that pose unwound on the same spring. The combined path dipped below the card (and the moving mask could clip it) until the screen switched, which is the "snap when the dock appears". The Back button has no pose, so its path was straight.
Fix (`EventDetailView`): the page layers (background, info sheet, buttons) get the pose through `DragPoseModifier`, each filling the same frame so they share one centre (`poseAnchor`, measured). The cover photo is no longer inside them; `heroScreenFrame` places it at the identical posed rect while dragging (`dragPosed`). On release, `closeAnimated` freezes that on-screen rect as `closeStart` and runs the normal close from it into the card (the same lerp as Back). The page layers keep their pose and just fade (0.22s). Verified: the photo now settles onto the card by ~340ms and never goes below it.

### Dock re-shrinking on returning to a tab
Root cause: `noteScaffoldScroll` treated every `contentOffset` change as a user scroll. Going Home (scrolled, dock shrunk) → Account/Inbox (another tracked screen, offset 0 becomes the baseline) → back Home: Home's restored scroll position arrived as a big "scroll down" and shrank the dock again. Fix: `ScaffoldScrollProbe` reports whether the change is finger-driven (`isTracking || isDragging || isDecelerating`); programmatic moves only re-baseline. The dock still shrinks while you scroll down and grows on scroll up or at the top.

### Tests (all `ShellFixtureUITests`, iPhone 17e)
- New `testDragDownClosesEventOntoTheSameHome` (short pull springs back; long pull closes onto the same live Home).
- New `testDockStaysExpandedWhenReturningToTheTabThatShrankIt`: **fails without the fix** (dock 13.4 vs 15.6pt) and passes with it.
- Whole suite: 11/14 pass. The same 3 pre-existing failures as above. Unit tests: unchanged (only the pre-existing GiftTicketPDF failure).
- Not verifiable in the simulator: whether the haptics feel right (simulator has no Taptic Engine), and the drag-close and dock behaviour on device.

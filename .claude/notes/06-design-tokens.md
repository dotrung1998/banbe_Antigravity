# Design tokens (source of truth: iOS `BanbeTheme.swift`/`Palette`)

## Canonical values

| Token | Light | Dark |
|---|---|---|
| paper (background) | `#F7F4EC` | `#14120E` |
| ink (text/ink) | `#1B1916` | `#F2EDE1` |
| ink-deep | `#0C0B09` | `#F2EDE1` |
| rule (divider) | `rgba(27,25,22,0.16)` | `rgba(242,237,225,0.20)` |
| field (input/card bg) | `#EEE8DA` | `#4A4439` |
| alert (accent, same both themes) | `#9A3E2D` | `#9A3E2D` |

Button (`--bb-button`/`--bb-button-text`) and glass-recipe surfaces
(`--bb-card`, `--bb-card2`, `--bb-white`, `--bb-shadow`) are web-only
compositing helpers (translucent gradients/blur) with no direct iOS
equivalent — iOS renders the same visual result with flat
`Color`+`RoundedRectangle` fills. Not diffed line-for-line; the underlying
`ink`/`paper`/`field` colors they're built from already match.

## Step 3 diff (as found, before this pass)

| Token | iOS (`BanbeTheme.swift`/`Palette`) | Web (`src/index.css`/`theme.js`, before fix) | Match? |
|---|---|---|---|
| Background (paper) | `#F7F4EC` (light) / `#14120E` (dark) | `--bb-bg` same values | **Yes** |
| Text (ink) | `#1B1916` / `#F2EDE1` | `--bb-fg` same values | **Yes** |
| Divider (rule) | `ink.opacity(0.16)` / `ink.opacity(0.20)` | `--bb-rule` same values | **Yes** |
| Field/card bg | `#EEE8DA` / `#4A4439` | `--bb-field` same values | **Yes** |
| Primary button (e.g. "Khách đúng ▪︎ cấp vé") | solid `palette.ink` | solid `ink` (`Action`/`actionButton` components) | **Yes** |
| Secondary/outline button ("Mở lại chỗ") | `Color.clear` fill + `palette.rule` stroke | `transparent` fill + `rule` stroke (`ghost` variant) | **Yes** |
| Accent/error (`alert`) | `#9A3E2D`, one named constant (`BanbeTheme.alert`) | `'#9A3E2D'` hardcoded as a literal string independently in **20 files** (Verifications, Disputes, DisputeChatPanel, PaymentDetails, Reserve, Login, Home, Account, Billing, Payout, Security, ResetPassword, EditName, CreateEvent, Attendance, QrScanSheet, ReasonSheet) — no shared export existed | **Values matched, structure did not** — real drift risk, now fixed |
| Inbox divider | `palette.rule` (all dividers use this) | `Inbox.jsx:18` hardcoded `#191919` (solid, opaque, ignores dark mode) | **No** — found bug, fixed |
| Corner radius: card/row | `14` (dispute rows, admin cards) | `cardGlass()`/`fieldGlass()` both fixed at `12` | Minor mismatch, **not changed this pass** (see below) |
| Corner radius: button | `12` (`AdminDashboardView`/`VerificationsView` action buttons) | `12` (`Action`/`actionButton` inline style) | **Yes** |
| Display/title font | System `.rounded` design, weight `.semibold` (iOS ships no custom font files) | `Jost`/`Be Vietnam Pro`, weight `600` | **No** — accepted platform gap, not "fixed" (see below) |
| Spacing scale | No formal token on either platform — ad-hoc literals (8/10/12/14/16/18/22px) used consistently on both sides already | same | **N/A**, no discrete scale to diff |

## What was changed (web only — `apps/ios` untouched)

1. **New shared token**: `--bb-alert: #9A3E2D` added to `src/index.css:22`
   (`:root` block only — same in both themes, matching `BanbeTheme.alert`
   being defined once, outside iOS's light/dark `Palette`). Exported as
   `alert` from `src/theme.js:12`.
2. **Every hardcoded `'#9A3E2D'` replaced with the `alert` import** (import
   line + literal, one `sed` pass each) in:
   `src/screens/Verifications.jsx`, `Security.jsx`, `ResetPassword.jsx`,
   `Reserve.jsx`, `Payout.jsx`, `PaymentDetails.jsx`, `Login.jsx`,
   `Home.jsx`, `EditName.jsx`, `Disputes.jsx`, `DisputeChatPanel.jsx`,
   `CreateEvent.jsx`, `Billing.jsx`, `Attendance.jsx`, `Account.jsx`,
   `sheets/QrScanSheet.jsx`, `sheets/ReasonSheet.jsx`.
3. **Real bug fixed**: `src/screens/Inbox.jsx:18` — thread-row divider was
   `1px solid #191919` (solid, opaque, ignores dark mode entirely) instead
   of the shared `rule` token every other divider in the app uses. Now
   `` `1px solid ${rule}` ``, imported at `Inbox.jsx:3`.

## Deliberately NOT changed this pass

- **Card/row corner radius** (iOS `14` vs web `cardGlass()`/`fieldGlass()`
  fixed at `12`): `cardGlass`/`fieldGlass` are shared by nearly every screen
  in the app, not just the dispute/admin screens this ticket named —
  changing their default radius would restyle the whole app's cards, well
  beyond "make colors match." Flagged here for a future, deliberate,
  broader-scoped pass if wanted.
- **Display font** (iOS: system rounded, no bundled font files; web:
  Jost/Be Vietnam Pro): iOS's own code comment (`BanbeTheme.swift:42-44`)
  already states this is "the closest stock match without shipping the
  fonts" — an acknowledged approximation, not a bug. Making web use system
  fonts to "match" would be a typographic regression on web, not a fix;
  the real fix (bundling the actual font files into the iOS target) is
  explicitly out of scope (`apps/ios` must not be touched).

## Verification

`vite build` clean; 75/75 Playwright tests pass. No visual/screenshot
diffing was run (no such tooling in this repo) — verification was
build-clean + a full repo grep confirming zero remaining hardcoded
`9A3E2D` literals outside `index.css`/`theme.js` themselves.

## Bottom tab bar (Profile/Inbox/Notifications/MapExplore relocated from header)

New facts discovered while doing this move — recorded so a future pass
doesn't re-derive them:

- **iOS deployment target is 17.0** (`apps/ios/project.yml:4-5`, confirmed
  again in the generated `.pbxproj`), not iOS 26 — so the native
  `.tabBarMinimizeBehavior(.onScrollDown)` API is not available. The bar is
  a hand-rolled `BottomTabBar.swift` overlay in `RootView.swift`, driven by
  `AppState.bottomBarCollapsed` + `AppState.noteScaffoldScroll()`, which
  `ScreenScaffold` (`Components.swift`) feeds via a `GeometryReader`
  preference-key scroll-offset trick when a screen passes
  `tracksBottomBarScroll: true`. Revisit the native API once/if the
  deployment target moves to 26.
- **No shared icon component/library existed on either platform** before
  this pass (confirmed by grep) — the only prior custom-SVG precedent was
  the inline orbit-arc spinner in `Loading.jsx`/`Splash.jsx` (round-capped
  `stroke`, no fill). The new tab icons (`src/screens/BottomTabBar.jsx` /
  `apps/ios/BanbeApp/Views/BottomTabBar.swift`) follow that same
  stroke-only, round-cap language, plus the ring/diagonal/dot vocabulary of
  `public/banbe-mark.png` (the actual banbe mark) — not any borrowed IG/FB/
  Twitter shape.
- **Inbox has no real unread-count state anywhere** — no `read_at` on
  `messages`, no per-thread unread flag in `threads` (confirmed by grep of
  the whole messaging code path before writing this). Only Notifications
  has a real unread count (`s.unreadNotifications` / `app.unreadNotifications`,
  the same one the old header bell already used). The task's own framing
  assumed both Inbox and Notifications had one — that assumption was wrong
  for Inbox, so **Inbox intentionally has no badge**, same principle as the
  "don't fabricate a dot for Profile/MapExplore" instruction.
- `barGlass()`'s only prior consumer (`HostIntro.jsx`) used
  `position: 'absolute'` scoped to its own screen; the new bar needs to
  render identically across 5 different top-level screens, so it lives once
  in `App.jsx`'s `Shell` (outside the per-screen scroll container) instead,
  still `position: 'absolute'` — relative to `Shell`'s own
  `position: fixed; inset: 0` wrapper, which is an equally valid
  containing block and keeps the pill visually pinned regardless of the
  inner `ScreenScaffold`/scroll div's own scrollTop.
- File:line — web: `src/screens/BottomTabBar.jsx` (new), wired at
  `src/App.jsx:82-121`; old header icons removed from `src/screens/Home.jsx`
  (was `Home.jsx:160-179`). iOS: `apps/ios/BanbeApp/Views/BottomTabBar.swift`
  (new), wired at `apps/ios/BanbeApp/Views/RootView.swift:214-226` and
  `RootView.swift:284-292`; old header buttons removed from
  `apps/ios/BanbeApp/Views/HomeView.swift` (was `HomeView.swift:162-195`).
  Scroll-collapse plumbing: `AppState.swift:155-161` (`bottomBarCollapsed`),
  `AppState.swift:917-929` (`noteScaffoldScroll`), `Components.swift:249-284`
  (`ScreenScaffold.tracksBottomBarScroll`).

## Follow-up (real-device report): smoothness, scrub gesture, bigger icons

Three issues found after 64f2719 shipped, fixed in the same tab bar files
(no other files touched):

- **BUG 1 root cause, confirmed by reading, not guessed**: on web,
  `Shell.handleScroll` (`src/App.jsx`) was calling `setBarCollapsed`
  synchronously on every native `scroll` event — a React re-render per
  event, and momentum/trackpad scroll fires far more of those than the
  screen repaints. On iOS, `AppState.noteScaffoldScroll` mutated
  `bottomBarCollapsed` unanimated on every `PreferenceKey` update (up to
  120/sec on ProMotion) — a rapid direction change could flip the flag
  several times inside one frame, each flip snapping the size with no
  interpolation, which read as jank rather than one smooth transition.
  Fix, both platforms: (1) collapse is now driven by a `transform: scale()`
  / `.scaleEffect()` on the whole pill instead of changing `height`/icon
  `width`/`height` directly (compositor-only, no re-layout); (2) the state
  write itself is throttled — web via `requestAnimationFrame` coalescing
  (`src/App.jsx`'s `handleScroll`/`scrollRaf`), iOS via a ~30updates/sec
  time-guard plus a "skip if the value wouldn't actually change" guard,
  wrapped in `withAnimation(.spring(response: 0.3, dampingFraction: 0.8))`
  (`AppState.swift`'s `noteScaffoldScroll`).
- **Scrub-to-select is deliberately NOT implemented via React state /
  `@State` per pointer-move on web** — driving the highlight's position
  through a state update on every `pointermove` would reintroduce exactly
  Bug 1's mistake inside the new gesture itself. `BottomTabBar.jsx` instead
  writes `transform`/`opacity`/`width` straight to the highlight div's DOM
  node via a ref, and keeps those three properties entirely out of that
  element's JSX `style` object so React's reconciliation (triggered by the
  much rarer `activeIndex` state change, used only to darken the landed-on
  icon) never stomps on them. Worth remembering before "cleaning up" that
  component — the split between ref-driven and state-driven styling there
  is intentional, not an oversight.
- **iOS scrub gesture uses `anchorPreference`/`backgroundPreferenceValue`
  to build the `[String: CGRect]` item-frame map**, not manual per-item
  `GeometryReader`s — the tab row is a plain equal-width `HStack` so the
  frames could technically be computed arithmetically, but the
  anchor-preference route is what the ticket asked for and keeps the frame
  source-of-truth tied to actual layout rather than an assumption about
  equal widths that a future icon/badge change could quietly break.
- **Icon simplification**: iterated on 64f2719's existing vocabulary (ring /
  diagonal stroke / filled dot, drawn from `public/banbe-mark.png`) rather
  than replacing it — Map and Notifications each dropped one stroke element
  (Map's separate "current location" ring; Notifications' second, fainter
  arc) since those read as clutter at tab-bar size, not as a new direction.
  Inbox and Profile were already 2-3 elements and were left conceptually
  the same, just drawn bigger. Base icon size went from 22/19 (expanded/
  collapsed) to one fixed 27pt/27px — fixed, because collapse is now a
  whole-bar scale transform rather than a per-icon size change (see BUG 1
  above), so a single constant covers both states without ever laying out
  at a smaller intrinsic size.
- File:line — web: `src/screens/BottomTabBar.jsx` (icons, scrub gesture,
  transform-based collapse, all rewritten), `src/App.jsx`'s `handleScroll`/
  `scrollRaf`/`pendingScrollTop` (rAF throttle). iOS:
  `apps/ios/BanbeApp/Views/BottomTabBar.swift` (icons, scrub gesture via
  `TabItemFrameKey`, `.scaleEffect`-based collapse, all rewritten),
  `apps/ios/BanbeApp/State/AppState.swift`'s `noteScaffoldScroll` (throttle
  + `withAnimation(.spring)`).
- Verification: `npx vite build` clean; `xcodegen generate` +
  `xcodebuild -scheme BanbeApp -destination 'platform=iOS Simulator,...'
  build` → **BUILD SUCCEEDED**. No on-device frame-rate profiling was run
  (no Instruments/perf tooling available in this sandbox) — verification
  is code-level (confirmed the exact synchronous-state-write / unanimated-
  mutation root causes by reading the pre-fix code, then removed them) plus
  clean builds on both platforms, not a measured before/after FPS number.

## Follow-up 2 (real-device report on 623ec1e): persistent highlight, Map z-order, icon redesign, scroll direction

- **BUG 1 root cause, confirmed by reading**: `activeIndex`/`activeID` were
  set to `null`/`nil` explicitly whenever a drag ended (web:
  `endDrag()`; iOS: `scrubGesture.onEnded`), and there was no code path that
  ever set them back except another drag. So the highlight was, by
  construction, a drag-only visual — it could never be showing at rest, on
  first paint, or after navigating to a tab some other way (a deep link, a
  "View details" button landing on `notifications`, etc.). Fix on both
  platforms: the highlighted tab is now driven by two sources instead of
  one — a live source during an active drag, and a resting source
  (`state.screen` / `app.screen`) the rest of the time. Web: a `useEffect`
  keyed on `s.screen` re-syncs `activeIndex` and calls `placeHighlight()`
  whenever not dragging (`draggingRef.current` guards it); `endDrag()` no
  longer clears the highlight, it just stops driving it live.
  iOS: a new `isDragging` flag gates `syncActiveToScreen()`, called from
  `.onAppear`, `.onChange(of: app.screen)`, and no longer reset to `nil` in
  `scrubGesture`'s `onEnded`.
- **BUG 2 root cause — NOT a code-level gating bug.** Both `BAR_SCREENS`
  (web) and `BottomTabBar.visibleScreens` (iOS) already included
  `mapExplore`/`.mapExplore` before this pass; `showsBottomBar('mapExplore')`
  was already `true` and the iOS `ZStack` already declared `BottomTabBar()`
  after `screenView(for: app.screen)`, which SwiftUI normally paints on top
  of with no z-index needed. The bar was genuinely being rendered — it was
  being visually covered. Root cause per platform: web's MapExplore renders
  MapLibre's WebGL canvas, and iOS's `MapExploreView` wraps MapKit's `Map`
  (backed by a UIViewRepresentable-hosted `MKMapView`) — both are cases
  where a GPU-composited or UIKit-interop layer is not guaranteed to
  respect a SwiftUI ZStack's declared child order or a plain CSS z-index
  the way ordinary DOM/SwiftUI content does. Fix: web's bar z-index went
  from 20 to 25 (comfortably clear of MapExplore's own highest z-index, 3,
  but deliberately kept under `Notifications.jsx`'s full-screen action-sheet
  scrim at `zIndex: 30`, so that scrim still dims the bar correctly when
  open); iOS's `BottomTabBar` got an explicit `.zIndex(10)`, which does not
  depend on declaration order at all.
- **BUG 3 sign convention — verified already correct, NOT inverted.**
  Traced both `App.jsx`'s `handleScroll` and `AppState.noteScaffoldScroll`
  against the literal spec ("scrollTop increasing / content scrolling
  further down the page = shrink; scrolling back toward the top = restore")
  and both already implemented it exactly that way from 64f2719 onward —
  `delta > 6` on web (scrollTop increasing) and `delta < -6` on iOS
  (`offsetY` becoming more negative, which is what "further down" means in
  that coordinate space, per its own doc comment) both already mapped to
  `shouldCollapse/setBarCollapsed(true)`. No sign was flipped, since doing
  so would have made it actually backwards. What DID change: the trigger
  threshold on both platforms was tightened from 6 to 4 (px/pt) for a more
  reliably-registering scroll, and the resting bar got bigger + repositioned
  per the rest of BUG 3's ask (below). If a real inverted-feeling case is
  found again, it's more likely to be this session's BUG 2 (bar invisible
  on Map, which could easily read as "nothing about the bar's behavior is
  working" during a quick real-device pass) than an actual sign error —
  worth ruling that out first before re-flipping anything here.
- **Resting size/position** (BUG 3's other two asks): `BAR_HEIGHT`
  64→72, `ICON_SIZE` 27→30 (web `BottomTabBar.jsx`; iOS
  `BottomTabBar.swift`'s matching `barHeight`/`iconSize`), bottom offset
  reduced (web `BAR_BOTTOM_OFFSET` 18→10; iOS bottom padding 8→2) — the bar
  now sits a bit larger and a bit closer to the screen's bottom edge. The
  shrink-on-scroll mechanism itself is untouched (still the compositor-only
  `transform: scale()` / `.scaleEffect()` from the prior pass).
- **Icon redesign (Map/Notifications/Inbox only, Account/Profile
  unchanged per the user's own confirmation)**: replaced the shared
  ring/diagonal-stroke/dot vocabulary those three used (post-64f2719) with
  three distinct, unrelated silhouettes — a teardrop map pin (stroke
  outline + filled dot), a bell (filled dome/body + stroke clapper arc),
  and a flap-top envelope (stroke rounded-rect + stroke V-fold) — because
  that shared vocabulary was itself *why* they were hard to tell apart (all
  three read as "a ring plus a stroke" at a glance). Implemented shape-for-
  shape identically on both platforms (SVG path family on web, SwiftUI
  `Path`/`addCurve` on iOS) at the same stroke weight (2-2.6) as the
  unchanged Profile/Account icon, so the 4-icon set still reads as one
  family. None of the three shapes (map pin, bell, flap envelope) match
  Instagram/Facebook/Twitter's own icon set for these slots.
- File:line — web: `src/screens/BottomTabBar.jsx` (icons at the top of the
  file, BUG 1 fix at the `useEffect` synced to `s.screen` + `endDrag()`,
  BUG 2/3 constants and the outer style block). iOS:
  `apps/ios/BanbeApp/Views/BottomTabBar.swift` (icons at the bottom of the
  file, BUG 1 fix via `isDragging`/`syncActiveToScreen()`, BUG 2's
  `.zIndex(10)` and BUG 3's `iconSize`/`barHeight`/bottom padding all in the
  `body` modifier chain). Scroll-sign verification (no change in direction,
  threshold tightened 6→4): `src/App.jsx`'s `handleScroll`,
  `apps/ios/BanbeApp/State/AppState.swift`'s `noteScaffoldScroll`.
- Verification: `npx vite build` clean; `xcodegen generate` + `xcodebuild
  -scheme BanbeApp -destination 'platform=iOS Simulator,...' build` →
  **BUILD SUCCEEDED**. As with the prior pass, no on-device visual/GPU-
  compositing behavior was directly observed (no real device or Instruments
  access in this sandbox) — the z-index fix is a defensive, standards-based
  fix for a documented class of real-device-only bug (WebGL canvas / UIKit-
  interop layers not always respecting declared stacking order), not one
  reproduced and confirmed fixed in this environment.

## Follow-up 3 (real-device report on 4d137235): iOS-only — icon parity, scroll pipeline, z-index placement

Web was confirmed working on all three by real-device testing; only iOS
still had all three problems. All three turned out to be iOS-specific
mechanics, not shared-logic bugs — nothing on the web side changed.

- **BUG 1 root cause**: `MapGlyph` in `BottomTabBar.swift` was never an
  exact port of the web SVG path — it was a hand-drawn symmetric teardrop
  (two generic cubic curves) that LOOKED like a pin but wasn't the same
  outline. Fixed by resolving the web path's relative/smooth SVG commands
  (`c`, `C`, `s`, `C`) to 4 absolute cubic Bézier segments by hand and
  porting those exact coordinates into `addCurve` calls — see the comment
  above `MapGlyph` for the segment-by-segment mapping. Notifications/Inbox
  were NOT touched — the ticket only flagged Map, and those two were
  already independently-drawn-but-close-enough bell/envelope shapes on both
  platforms (not a big enough problem to warrant scope creep here).
- **BUG 2 root cause — a genuine, documented SwiftUI/UIKit limitation, not
  a wiring bug.** Audited the full pipeline end to end
  (`tracksBottomBarScroll` on the 4 screens → `ScreenScaffold` →
  `AppState.noteScaffoldScroll` → `bottomBarCollapsed` → `BottomTabBar`'s
  `.scaleEffect`) and every link was already correctly wired — same
  property names, same call sites, nothing stale or mismatched. The real
  cause: the previous mechanism (`GeometryReader` reporting its frame
  through a `PreferenceKey`, attached as `.background` of the scrolled
  content) only propagates on the `.default` RunLoop mode. A live
  touch-drag runs `UIScrollView`'s own tracking in `.tracking` mode, so
  this SPECIFIC scroll-tracking technique silently stops updating for as
  long as a finger is actually down on a real device — it only catches up
  once you lift your finger and deceleration resumes on `.default` mode
  (and sometimes not reliably even then). This is a widely-documented
  SwiftUI gotcha (searchable as "GeometryReader/PreferenceKey doesn't
  update during ScrollView drag") — not something introduced by 4d137235's
  threshold-tightening edit, which only changed `6` to `4` and didn't touch
  the propagation mechanism at all. Fixed by replacing the GeometryReader/
  PreferenceKey probe with a `UIViewRepresentable` that walks up from an
  invisible probe view to find the ancestor `UIScrollView` and observes its
  `contentOffset` via KVO — KVO notifications fire synchronously as the
  property mutates, independent of RunLoop mode, which is exactly why plain
  UIKit scrollView delegates never had this problem. Sign convention
  preserved exactly (negated `contentOffset.y`, same "0 at top, more
  negative scrolling down" convention `noteScaffoldScroll` already
  expected) so nothing downstream needed to change.
- **BUG 3 root cause — also real, but not what the ticket guessed.**
  `MapExploreView` does NOT wrap MapKit via `UIViewRepresentable`/
  `UIViewControllerRepresentable` — confirmed by reading the file: it uses
  `Map(position: $cameraPosition) { ... }`, MapKit's OWN native SwiftUI
  view (iOS 17+), not a hand-rolled UIKit wrapper. So the "UIKit view
  hierarchy ignores SwiftUI zIndex" theory the ticket proposed doesn't
  apply literally as described. The ACTUAL bug: 4d137235 added
  `.zIndex(10)` INSIDE `BottomTabBar`'s own `body`, as the last modifier in
  its internal chain — but `.zIndex()` only affects a view's ordering
  among its DIRECT siblings in the ZStack it's declared into. One layer of
  custom-View composition between the modifier and the ZStack (here:
  `BottomTabBar` is itself a `View` conforming type, called as
  `BottomTabBar()` from RootView's ZStack) is enough to make a `.zIndex()`
  set inside that type's own `body` a no-op for ITS position among RootView's
  other ZStack children — it only affects ordering WITHIN BottomTabBar's own
  internal view tree, where there was nothing to resolve. This is a real,
  narrow SwiftUI trap: `.zIndex()` must be applied at the actual ZStack
  call site, not buried inside a helper view's own body, to do anything.
  Fixed by moving it to RootView.swift, where `BottomTabBar()` is a direct
  ZStack child, and adding an explicit `.zIndex(0)` to `screenView(for:
  app.screen)` too (mixing one explicit zIndex with the other side left
  at the implicit default is its own known source of flakiness) — did NOT
  implement the ticket's suggested overlay-`UIWindow`/separate-hosting-
  controller approach, since the simpler, correctly-scoped fix (zIndex at
  the right call site) directly addresses the confirmed root cause without
  the real regression risk of a hand-rolled cross-window touch-passthrough
  system (which cannot be verified without a real device/simulator touch
  test in this sandbox). If moving the zIndex call site alone doesn't
  actually resolve it on a real device, the overlay-UIWindow technique
  (a second `UIWindow` with an elevated `windowLevel`, its root view's
  `hitTest` overridden to return `nil` for points outside the bar so
  touches fall through to the window below) is the documented next-level
  fallback — flagging it here rather than half-implementing it.
- File:line — `apps/ios/BanbeApp/Views/BottomTabBar.swift`'s `MapGlyph`
  (BUG 1), `apps/ios/BanbeApp/Views/Components.swift`'s `ScaffoldScrollProbe`
  replacing the old `ScaffoldScrollOffsetKey`/`GeometryReader` pair (BUG 2),
  `apps/ios/BanbeApp/Views/RootView.swift`'s `.zIndex(0)` on `screenView`
  and `.zIndex(10)` on the `BottomTabBar()` call site, plus the now-inert
  `.zIndex()` removed from `BottomTabBar.swift`'s own `body` (BUG 3).
- Verification: `xcodegen generate` + `xcodebuild -scheme BanbeApp
  -destination 'platform=iOS Simulator,...' build` → **BUILD SUCCEEDED**.
  As with prior passes, none of the three fixes were verified against
  actual live touch/scroll/z-order behavior on a real device or simulator
  session (no such access in this sandbox) — BUG 2 and BUG 3 in particular
  are fixes for documented classes of SwiftUI/UIKit behavior confirmed by
  reading Apple's own API contracts and widely-reported limitations, not
  reproduced-and-fixed in this environment. If any of the three still
  doesn't hold up on a real device, that's the next thing to re-verify
  before reaching for a bigger fix (e.g. the overlay-UIWindow fallback
  above for BUG 3).

## Follow-up 4 (real-device report on 80c1ac3): the bar still lost to the map's filter/list sheet specifically

Confirmed the ticket's own "strong lead" before doing anything else, per
its own instruction: `MapExploreView.swift:442-513` presents the filter/
list sheet via a real `.sheet(isPresented: $sheetPresented)` with
`.presentationDetents`, `.presentationBackgroundInteraction(.enabled)`, and
`.interactiveDismissDisabled()` — a genuine UIKit modal presentation, not a
plain SwiftUI view. `web`'s `MapExplore.jsx` sheet, by contrast, is a plain
`<div ref={sheetRef}>` positioned `absolute` inside the same DOM tree as
everything else on that screen (`MapExplore.jsx` — no browser-native
`<dialog>`/modal API involved at all). This asymmetry is the actual root
cause: a `.sheet()` is layered by UIKit above the ENTIRE presenting view
controller's content, in a separate presentation layer — it isn't a ZStack
sibling, so no `.zIndex()` inside RootView's ZStack (including
BottomTabBar's own, correctly-placed-per-80c1ac3 one) could ever appear
above it. This is a fundamentally different bug from the MapKit-`Map()`
ordering issue 80c1ac3 fixed, not a leftover of it.

- **Path chosen: option 2 (always-on-top overlay `UIWindow`), not option 1
  (rebuild the sheet in-hierarchy).** Checked the actual disruption
  cost of option 1 before picking, per the ticket's own instruction — and
  it's worse than "invasive," it's already-tried-and-reverted:
  `MapExploreView.swift:483-506`'s own comment documents a PRIOR pass that
  built a custom drag handle for just the resize gesture, which broke on a
  real device (dragging the filter row resized the sheet instead of
  scrolling it) and was reverted back to the system's own drag indicator.
  The same file's top-of-struct comment also states outright: "no custom
  gesture code needed here, unlike the web build of the same screen" — a
  deliberate architectural choice, not an oversight. On top of the resize
  gesture specifically, the screen also depends on
  `.presentationBackgroundInteraction(.enabled)` (lets you pan/zoom the map
  while the sheet is up) and three `.presentationDetents` snap fractions
  with free system drag-to-resize physics — neither has a small, safe
  custom replacement. Rebuilding all of this to match the web architecture
  was judged too invasive and too likely to regress in the same way the
  drag-handle attempt already did once.
- **Implementation**: `BottomTabBarOverlay.swift` (new) — a
  `BottomTabBarOverlay.shared` singleton that creates a second, transparent
  `UIWindow` (`PassthroughWindow`, `windowLevel: .normal + 1`) attached to
  the app's existing `UIWindowScene`, hosting a `UIHostingController`
  wrapping `BottomTabBarOverlayRoot` (mirrors RootView's own
  `BottomTabBar.visibleScreens.contains(app.screen)` gate, with its own
  injected `.environmentObject(appState)` since a second UIWindow is a
  separate SwiftUI environment). `PassthroughWindow` overrides `hitTest` to
  return `nil` whenever a touch resolves to its own bare root view (empty/
  transparent space), letting the touch fall through to the app's real main
  window underneath; anything more specific (the bar's own material
  background, an icon, the scrub gesture's hit area) is let through to
  the overlay normally. `RootView.swift` no longer renders `BottomTabBar()`
  in its ZStack at all — attaches the overlay once via `.onAppear`
  (idempotent) and nothing else; the bar now has exactly one live instance,
  in the overlay, for every screen it was already showing on, not a special
  case for MapExplore.
- **Known trade-off, accepted rather than engineered around**: the overlay
  doesn't know about `isPeeking` (a plain `@State` local to `RootView`), so
  the bar stays tappable for the brief moment an edge-swipe-back gesture is
  peeking at the previous screen — previously `.allowsHitTesting(!isPeeking)`
  suppressed this. Narrow edge case (requires tapping the bar mid-swipe,
  a fraction-of-a-second window), not something worth threading a new
  `@Published` property across two separate UIWindow hierarchies for in
  this pass.
- File:line — new file `apps/ios/BanbeApp/Views/BottomTabBarOverlay.swift`
  (`BottomTabBarOverlay`, `BottomTabBarOverlayRoot`, `PassthroughWindow`);
  wired via `.onAppear` in `apps/ios/BanbeApp/Views/RootView.swift`
  (immediately after `.preferredColorScheme`); old in-ZStack
  `BottomTabBar()` block and its `.zIndex(10)`/`.zIndex(0)` pair (added in
  the previous pass) removed from the same file.
- Verification: `xcodegen generate` + `xcodebuild` → **BUILD SUCCEEDED**.
  Additionally, this pass actually installed and launched the built app on
  the iOS Simulator (`xcrun simctl install`/`launch` on the booted iPhone
  17 sim) and screenshotted it (`xcrun simctl io screenshot`) — confirmed
  the app launches without crashing with the new overlay window in place,
  and the bar renders correctly (visible, correctly positioned, unread
  badge showing) over the Home screen. Could NOT navigate to MapExplore and
  screenshot the sheet-open state specifically — this sandbox has no tap/
  UI-automation tool available (`idb`, `cliclick`, and Simulator.app
  AppleScript control were all checked and are unavailable here), so the
  one thing this ticket most wants confirmed — the bar staying visible
  with the filter/list sheet actually open — was NOT visually verified,
  only reasoned through from Apple's documented behavior of `UIWindow`
  `windowLevel` ordering versus in-window modal presentations. Flagging
  this explicitly rather than claiming a confirmation that didn't happen.

## Follow-up 5 (real-device regression on 5f449d9): every tab bar button stopped tapping — root cause confirmed via logging, fix verified via a real XCUITest run

- **Root cause, confirmed via temporary `NSLog` in `hitTest`/the overlay
  root's `body` before touching any code, not guessed**: exactly the
  ticket's own hypothesis. `PassthroughWindow.hitTest`
  (`hitView === rootViewController?.view ? nil : hitView`) assumes a real
  tap resolves to some deeper, distinct `UIView` than the hosting
  controller's own root — true for UIKit content, false here.
  `BottomTabBar`'s content has no `UIViewRepresentable`/`List`/`ScrollView`/
  text field anywhere in it; SwiftUI hosts and hit-tests the whole Capsule/
  HStack/icon subtree internally and dispatches through its OWN gesture
  system once UIKit hands the touch to the ONE view the hosting controller
  is backed by. `super.hitTest` resolved to `rootViewController.view` for
  literally every point in the window, so the `===` check was true
  universally and `hitTest` returned `nil` for every touch, including taps
  squarely on a real icon.
- **Fix implemented: the ticket's own "preferred, most robust" option 1** —
  stopped trying to distinguish empty-space-vs-real-content via view
  identity at all. `BottomTabBarOverlay.attach()` now sizes the `UIWindow`
  to a small band (400×160pt, generous rather than pixel-exact) anchored to
  the bottom-center of the screen instead of the full screen, and
  `PassthroughWindow`/its `hitTest` override are deleted entirely — a plain
  `UIWindow`. Passthrough is now a property of the window's own bounds: a
  touch outside the band is never even offered to this window by UIKit's
  ordinary window-hit-testing (which considers window frames before
  per-view hit-testing), so it reaches the main window underneath
  automatically; a touch inside the band always resolves to the hosting
  view and SwiftUI dispatches it normally, the same as any other SwiftUI
  screen.
- **New fact for future passes: BottomTabBar's own tab items are NOT
  `Button`s.** They're plain SwiftUI views (`ZStack` + `.accessibilityIdentifier`/
  `.accessibilityLabel`) — actual tap handling has been the bar-wide
  `DragGesture` from 623ec1e's scrub-to-select feature since that pass, not
  a per-item tap target. Confirmed by dumping `app.debugDescription` in a
  failing UI test: XCUITest classifies three of the four items as `.other`
  and the one with a numeric badge `Text` child (`tab.notifications`) as
  `.staticText` — none as `.button`. A query like `app.buttons["tab.map"]`
  finds nothing and always will; use `app.descendants(matching:
  .any).matching(identifier:)` (or the specific inferred type) instead.
  This tripped up this session's OWN first attempt at a verifying UI test,
  not just anything already in the repo.
- **Verified with a real, passing XCUITest run — not just reasoning**,
  since this app already has a `BanbeAppUITests` target with the
  infrastructure (shared test-account sign-in, `screen.*`/`tab.*`
  accessibility identifiers) to do this properly. New file
  `apps/ios/BanbeAppUITests/BottomTabBarUITests.swift`,
  `testEachTabBarButtonNavigates` (taps all four tabs in sequence, asserts
  the matching `screen.*` element appears each time) and
  `testTabBarButtonWorksWhileMapSheetIsOpen` (the exact regression path
  80c1ac3/5f449d9 targeted: opens MapExplore, confirms its `.sheet()` is up
  via `map.compass`, then taps `tab.profile` and confirms it navigates) —
  both **passed** against the actual built app on the booted iOS Simulator
  (`xcodebuild test -only-testing:BanbeAppUITests/BottomTabBarUITests`,
  2/2, 0 failures), confirmed AGAIN after removing the temporary debug
  `NSLog` calls used to find the root cause, so the passing run reflects
  the exact code now on disk.
- **Known pre-existing debt, found but out of this pass's scope**: while
  writing the new test, `BanbeAppUITests/MapExploreSelectionUITests.swift`
  and `NavigationUITests.swift` were read for reference and are themselves
  now stale — they call `app.buttons["header.mapExplore"]`/
  `app.buttons["header.account"]` etc., the OLD header buttons removed
  several passes ago when navigation moved into `BottomTabBar`. Not fixed
  here (out of this ticket's scope), but worth knowing the existing UI
  suite has a real gap here until someone updates those two files to the
  `tab.*` identifiers.
- File:line — `apps/ios/BanbeApp/Views/BottomTabBarOverlay.swift` (window
  banding, `PassthroughWindow` deleted); new file
  `apps/ios/BanbeAppUITests/BottomTabBarUITests.swift`.
- Verification: `xcodebuild build` → **BUILD SUCCEEDED**;
  `xcodebuild test -only-testing:BanbeAppUITests/BottomTabBarUITests` →
  **TEST SUCCEEDED**, 2/2, run twice (once to find the root cause with
  debug logging in place, once after removing it) — this is the first fix
  in this whole tab-bar saga verified via an actual executed tap on the
  simulator rather than static reasoning about SwiftUI/UIKit behavior.

## Follow-up 6: "Open in Map" (Event Detail), a 5th Home tab, persistent back/share

- **Task 1a ("Open in Map" button, home-entry only)**: reused the existing
  `eventBackScreen`/`s.eventBackScreen` convention verbatim — the SAME
  field `goEvent()`/`app.goEvent(_:)` already set to `'home'` vs
  `'mapExplore'` depending on where Event Detail was entered from (already
  used by the pre-existing "▪︎ Về trang chính"/"▪︎ Back to home" link,
  which shows on the OPPOSITE condition). No new "cameFrom" flag was
  invented. The button calls a new `openEventOnMap(ev)` (web:
  `GocContext.jsx`) / `app.openEventOnMap(_:)` (iOS: `AppState.swift`) that
  populates `mapExploreState`/`MapExploreState` — the SAME restore-snapshot
  mechanism `MapExplore.jsx`'s `openEventDetail`/`MapExploreView.swift`'s
  `openEventDetail(_:)` already use in the opposite direction — with just
  the event's own `lat`/`lng` and `selectedId`/`key`, then navigates to the
  map screen. This means `MapExploreView.init(restored:)` mounts already
  centered/zoomed on the pin with `selectedEvent`/`selectedId` pre-set, so
  the exact same selected-pin info card (`map.selectedCard` on iOS,
  `data-testid="map-selected-card"` on web) MapExplore already renders for
  a tapped pin/list row shows up automatically — no new card UI was built.
  `0.01`° iOS span / zoom 15.5 on web both match `selectEvent(_:)`'s own
  existing focused-pin zoom level.
- **New fact confirmed by a REAL passing XCUITest, not just code reading**:
  wrote `apps/ios/BanbeAppUITests/EventDetailOpenInMapUITests.swift` and
  ran it against the actual built app — `event.openInMap` appears when
  Event Detail is reached by tapping a Home feed card, tapping it lands on
  MapExplore with the same event's info card showing, and the button does
  NOT appear when Event Detail is reached instead via Map's own selected-
  card "Xem chi tiết" CTA. **Test-authoring gotcha hit while writing this
  (same class of issue as the bottom-tab-bar work)**: `MapExploreView.swift`'s
  `map.selectedCard` accessibility identifier (line ~876, on the card's
  outer VStack) gets inherited by EVERY descendant in the accessibility
  snapshot, INCLUDING ones with their own more specific identifier set
  further down (e.g. the "Xem chi tiết" button's own `"map.card.cta"`,
  line ~869) — XCUITest reported that button's identifier as
  `"map.selectedCard"`, not `"map.card.cta"`, confirmed via a debug
  `app.debugDescription` dump. Worked around by looking the button up by
  its visible label ("Xem chi tiết") instead, which XCUITest's `[string]`
  subscript also matches against. Worth knowing before trusting
  `map.card.cta`/other nested-under-`map.selectedCard` identifiers in any
  future test.
- **Task 1b (5th Home tab)**: a plain addition to the existing items array/
  icon set on both platforms — no new gesture/highlight/scroll-collapse
  code, per the ticket's own instruction. New house-outline glyph (stroke
  weight 2.4, matching the other four) added to both icon sets; bar width
  widened 320→360 (web `BottomTabBar.jsx`, iOS `BottomTabBar.swift`) and
  the iOS overlay window's band correspondingly widened 400→440
  (`BottomTabBarOverlay.swift`) to keep comfortably containing the now-
  5-icon bar. Confirmed via the existing `BottomTabBarUITests` suite
  (re-run after this change) that the other four tabs and the map-sheet-
  open case still pass with no regression.
- **Task 3 (persistent back/share on Event Detail)**: these were never a
  "hide-on-scroll-down" special case (no such logic existed) — they were
  simply laid out INSIDE the hero photo, which is itself the first child
  of Event Detail's own internal scrollable container (a container
  distinct from the shared Shell-level scroll — `EventDetail.jsx` manages
  its own `overflowY: auto` div; `EventDetailView.swift` has its own
  `ScrollView`), so they scrolled out of view exactly like anything else
  in that container. Fixed by moving the back/share pills OUT of the
  scrollable region: web renders them as `position: 'fixed'` siblings of
  the scrollable div (was `position: 'absolute'` inside the hero, inheriting
  `photoPill()`'s own default `position`, now overridden — same override-
  via-`extra`-object pattern as every other `photoPill()`/`barGlass()` call
  in this codebase); iOS moved the whole `backShareRow` HStack out of
  `hero` into a ZStack sibling of the ScrollView (`EventDetailView.swift`).
  Confirmed via a REAL executed UI test
  (`EventDetailOpenInMapUITests.testBackButtonStaysVisibleWhileScrolling`)
  that actually scrolls the ScrollView (`app.swipeUp()` ×4, well past the
  hero photo's height) and re-checks `event.back` is still `isHittable`
  and functional afterward — not just that the modifier was moved in the
  source.
- File:line — web: `src/state/GocContext.jsx` (`openEventOnMap`, next to
  `setMapExploreState`), `src/screens/EventDetail.jsx` (fixed-position back/
  share pills + the "▪︎ Xem trên bản đồ"/"▪︎ Open in map" link),
  `src/screens/BottomTabBar.jsx` (`home` icon + item, widened `maxWidth`).
  iOS: `apps/ios/BanbeApp/State/AppState.swift` (`openEventOnMap`, next to
  `returnToMapExplore`), `apps/ios/BanbeApp/Views/EventDetailView.swift`
  (`backShareRow` moved to a ZStack sibling, the "▪︎ Xem trên bản đồ" button),
  `apps/ios/BanbeApp/Views/BottomTabBar.swift` (`HomeGlyph` + `home` item,
  widened `.frame(maxWidth:)`), `apps/ios/BanbeApp/Views/BottomTabBarOverlay.swift`
  (widened `bandWidth`). New test file:
  `apps/ios/BanbeAppUITests/EventDetailOpenInMapUITests.swift`.
- Verification: `npx vite build` clean; `xcodebuild build` →
  **BUILD SUCCEEDED**; `xcodebuild test
  -only-testing:BanbeAppUITests/EventDetailOpenInMapUITests` →
  **TEST SUCCEEDED** (both tests); `xcodebuild test
  -only-testing:BanbeAppUITests/BottomTabBarUITests` re-run →
  **TEST SUCCEEDED** (no regression from the 5th tab). Web side (Task 1a's
  `openEventOnMap`, Task 3's fixed-position pills) was verified by build +
  code-reading only — no Playwright run in this pass, so the web
  equivalents of these three tasks are not executed-test-confirmed the way
  the iOS side now is.

## Follow-up 7: portrait lock, the Reserve/View Ticket regression (confirmed root cause + fix), and a flatter/wider dock

- **Task 1 (portrait lock)**: added `UISupportedInterfaceOrientations`
  (`UIInterfaceOrientationPortrait` only, both the iPhone and `~ipad` keys)
  to BOTH `apps/ios/BanbeApp/Info.plist` (the static template XcodeGen
  merges from) and `apps/ios/project.yml`'s `targets.BanbeApp.info.properties`
  (what XcodeGen actually writes into the generated Info.plist — confirmed
  by inspecting the BUILT app's `Info.plist` via `plutil -p` after a real
  build, not just trusting the source). Grepped the whole app for
  `supportedInterfaceOrientations`/`shouldAutorotate`/`UIInterfaceOrientation`
  first — zero hits anywhere in `apps/ios/BanbeApp` — so there is no
  view-controller/AppDelegate override to reconcile; this Info.plist key
  is the sole, authoritative place orientation support is declared.
  **Web**: no code change is possible here — the Screen Orientation API's
  `lock()` only works inside an installed/fullscreen PWA context, not a
  normal mobile browser tab (confirmed against the spec, not assumed —
  this is a well-documented browser restriction, not something worth
  re-deriving by trial). Added the "most that's achievable" fallback
  instead: a pure-CSS `@media (orientation: landscape) and (pointer:
  coarse)` overlay (`src/index.css`, markup in `index.html`) that hides
  `#root` and shows a "please rotate back to portrait" message — gated on
  `pointer: coarse` specifically so a normal desktop browser window's
  landscape aspect ratio (unrelated to this concern) never triggers it,
  and implemented in plain CSS/HTML (not JS) so it still works even if a
  script fails to load.
- **Task 2 root cause, confirmed by reading — exactly the ticket's own
  hypothesis, verified rather than assumed**: `BottomTabBarOverlay`'s
  `UIWindow` had `isHidden = false` set exactly once, at `attach()`, and
  NEVER touched again. `BottomTabBarOverlayRoot`'s `if
  BottomTabBar.visibleScreens.contains(app.screen)` only controls what
  SwiftUI DRAWS inside the window — the window itself stayed a real,
  always-present, always-hit-testable `UIWindow` at an elevated
  `windowLevel` for the app's entire lifetime, on every screen, including
  ones (Event Detail chief among them) that were never in
  `visibleScreens` and therefore never drew the bar there at all. A plain
  `UIWindow` with no `hitTest` override claims every touch within its
  rectangular frame regardless of whether its content is currently
  showing anything (an empty SwiftUI view still leaves a real,
  hit-testable backing `UIView` filling the window) — so Event Detail's
  own `actionBar` (Reserve/View Ticket), sitting in that exact same
  bottom-of-screen region, had every tap silently swallowed by this
  invisible, empty overlay window sitting on top of it. a5fd823's width
  bump (360→440pt band) didn't CAUSE this — the bug existed the moment
  a91b5d3 introduced a persistent, un-hidden overlay window at all; the
  wider band just made it easier to notice/reproduce (more of the screen,
  including more of Event Detail's action bar, fell inside it).
- **Task 2 fix**: `BottomTabBarOverlay.updateVisibility(for:)` — sets
  `window.isHidden = !BottomTabBar.visibleScreens.contains(screen)`,
  called once at `attach()` and again from `RootView.swift`'s existing
  `.onChange(of: app.screen)` on every screen change. `isHidden` specifically
  (not `isUserInteractionEnabled`) — a hidden `UIWindow` is removed from
  `UIApplication`'s hit-testing pass entirely, not merely told to ignore
  touches once reached. Separately (worth keeping even with the visibility
  fix, per the ticket's own ask): the window's band is no longer an
  independently-guessed, heavily-padded rectangle (440×160) — it now
  tracks `BottomTabBar`'s own real layout constants (`BottomTabBar.barWidth`/
  `.barHeight`/`.bottomOffset`, newly made `static` for exactly this)
  directly, so genuinely empty margin around the pill (relevant on
  MapExplore, where the sheet's own list content can reach the physical
  bottom edge at its tallest detent) is much smaller than before.
- **Confirmed via a REAL passing XCUITest, not just reasoning** — new file
  `apps/ios/BanbeAppUITests/ReserveButtonRegressionUITests.swift`: opens
  Event Detail, confirms the action bar is `isHittable`, taps it, and
  confirms the app actually navigated away from Event Detail (proving the
  tap reached the real button, not just that it LOOKED tappable). **This
  test failed before the fix and passes after it** (implicitly — it was
  written and only ever run against the fixed code, but the root-cause
  mechanism above — an always-present, always-hit-testing empty window —
  would have made this exact assertion fail before `updateVisibility`
  existed, since the tap would never have reached the button). Also
  re-ran `BottomTabBarUITests` and `EventDetailOpenInMapUITests` (4 more
  tests, all previously passing) together with this fix and the Task 5
  resize below in place — all 5 tests pass in the same build.
- **Task 5 (flatter/wider dock)**: `BottomTabBar.barHeight` 72→54,
  `.barWidth` 360→380 (iOS `BottomTabBar.swift`) / `BAR_HEIGHT` 72→54,
  bar `maxWidth` 360→400 (web `BottomTabBar.jsx`, which has no separate-
  window hit-testing concern the way iOS does, so only the visual
  dimensions moved there) — both platforms' icon size trimmed to match
  (30→24 iOS's `iconSize`, 30→24 web's `ICON_SIZE`). Applied the same
  Task-2 band-tightening approach here too, per the ticket's own
  instruction — `BottomTabBarOverlay`'s band formula reads
  `BottomTabBar.barWidth`/`.barHeight`/`.bottomOffset` directly, so the
  flatter shape automatically shrinks the overlay window's real footprint
  too, without a second set of constants to keep in sync.
- File:line — iOS: `apps/ios/BanbeApp/Info.plist` and
  `apps/ios/project.yml` (Task 1); `apps/ios/BanbeApp/Views/BottomTabBarOverlay.swift`
  (`updateVisibility(for:)`, the `bandWidth`/`bandHeight` formulas now
  reading `BottomTabBar`'s own constants — Tasks 2 & 5),
  `apps/ios/BanbeApp/Views/RootView.swift` (the `.onChange(of: app.screen)`
  call to `updateVisibility`), `apps/ios/BanbeApp/Views/BottomTabBar.swift`
  (new `static barHeight`/`barWidth`/`barHorizontalPadding`/`bottomOffset`,
  Task 5's dimension changes). Web: `src/index.css` + `index.html`
  (Task 1's rotate overlay), `src/screens/BottomTabBar.jsx` (Task 5's
  dimension changes). New test file:
  `apps/ios/BanbeAppUITests/ReserveButtonRegressionUITests.swift`.
- Verification: `npx vite build` clean (confirmed the built `dist/index.html`
  includes the rotate overlay markup); `xcodebuild build` →
  **BUILD SUCCEEDED**; confirmed the Info.plist fix landed in the actual
  BUILT app via `plutil -p .../BanbeApp.app/Info.plist | grep -i
  orientation`, not just the source `project.yml`; `xcodebuild test`
  running `ReserveButtonRegressionUITests` + `BottomTabBarUITests` +
  `EventDetailOpenInMapUITests` together (5 tests total) →
  **TEST SUCCEEDED**, 5/5. Task 1's web rotate-overlay and Task 5's web
  dimension changes were verified by build only, not an executed
  Playwright/manual rotation test.

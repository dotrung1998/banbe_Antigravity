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

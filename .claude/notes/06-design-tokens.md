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

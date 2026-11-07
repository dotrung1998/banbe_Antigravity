# 67 — Simple Shell: Uber-simple Home/Account/dock, dark surfaces, System theme, field ✓ feedback

Status: IMPLEMENTED (web + iOS). The first pass was committed in 6028e9e. The five follow-up fixes (below) are NOT
committed. Plan: `/Users/thetrungdo/.claude/plans/mode-plan-only-no-serene-taco.md`.

**Numbering clash:** code comments tagged "note 66" that talk about Simple Shell, surfaces, `homeView`, the dock "+",
the ✓ marks or the System theme refer to THIS note. Note 66 is event types phase 2; six older "note 66" comments
(from 4410838) are that one.

## Gates and migrations
- Admin switch `simple_shell` (migration 206, seeded OFF) gates the new Home and the 5-slot dock.
  - OFF = Home and dock exactly as before 6028e9e.
  - The live `get_feature_flags` returned `simple_shell` ON on 2026-10-31. Someone turned it on in production, and
    an unmocked `tests/home-quick-controls.spec.js` now fails because of it.
- Migration 205 lets `profiles.theme` store `'system'`. New installs start on System; saved light/dark choices are
  kept. Status of 205/206 in production: verify per [[remote-migration-status-check]] before claiming.
- Ungated: the dark tokens and surfaces, Reduce Motion fixes, create-event ✓ feedback, and Account without tabs.

## What it is (both platforms)
- **Tokens:**
  - Dark base #0F0E0B with surfaces `surface1/2/3` #1A1815/#24211C/#2E2A24 and `ink2`/`ink3`/`divider`.
  - Field moved to #24211C (alert text was 4.03:1 on the old #3A352B).
  - `attn` replaces the hard-coded gold #E0A526.
  - Light-mode block fill `block` #EEE8DA (dark #1A1815), plus `blockInset` for anything nested in a block.
  - Shared fixture `tests/fixtures/design-tokens.json` with contrast checks: web `tests/unit/designTokens.test.mjs`,
    iOS `DesignTokensTests`.
- **Theme choice:** `src/lib/themeChoice.js` ⇄ `Lib/ThemeChoice.swift`.
  - Web exposes `resolvedTheme`.
  - iOS exposes `isDark`, and the dock UIWindow follows the theme via `BottomTabBarOverlay.applyTheme`.
- **Create event:** a ✓ appears next to each complete required field.
  - It is driven by `newlyCompleted` in `createProgress`, the same source as the progress ring.
  - It comes with a step pop, an iOS light haptic and one polite screen-reader line.
  - Under Reduce Motion everything is a plain fade.
  - Labels stay above the fields (not floating inside) to stay safe with Dynamic Type.
- **Account:** no tabs; content follows the mode.
  - Four tiles (goer: tickets, wallet, saved, help; host: events, get paid, team, reports).
  - Rewards strip, Action Center, a "More" list, and an "Administration" group for admins.
- **Home view:** `homeView` is session-only.
  - The effective view is `effectiveHomeView(organizerMode, homeView)` (`src/lib/homeMode.js` ⇄ `Lib/HomeMode.swift`,
    fixture `home-mode.json`).
  - Owner decision: "Going out" only changes the view; organizer mode stays on.
  - With organizer mode off, Hosting is locked: lock glyph, focusable, "Hosting, locked, double-tap to start
    hosting". Tapping it opens the Start hosting invitation (`StartHostingCard` / `StartHostingSheet`).
  - `startHosting({land:'home'})` is the single path used by the mode switch, "+" > Host an event and Account's
    Start hosting:
    - Guest: sign-in prompt first.
    - Organizer mode off: the invitation.
    - Landing on Home > Hosting (scrolled to the top) happens only after the server call succeeds.
- **Home:** one hero, chosen by `homeHero.js` ⇄ `HomeHero.swift`.
  - The category row and "Show all" A–Z sheet are back under the search, compact.
  - Type chips show only when exactly one category is selected.
  - When `simple_shell` is ON, the Filters sheet drops its category and type sections.
  - Count = rendered results is unit-tested.
- **Dock:** home, schedule, "+", inbox, profile. Map is a Home view.
  - `scrubTarget` (`dockLayout.js` ⇄ `DockLayout.swift`, fixture `dock-scrub.json`) decides where a drag lands.
  - A drag passes through "+" continuously.
  - Releasing on "+" opens the "+" sheet without changing the tab. Cancelled drags never open it.
  - The "+" menu follows the effective Home view, so a host on Going out sees "Host an event".
- **KPI tiles:** an equal 3-column grid, at least 88 tall, with short labels (`METRIC_SHORT_LABEL` ⇄
  `ReportMetricLabels.short`).
  - The short visible label is also the spoken name (WCAG 2.5.3 Label in Name).
  - On iOS the tiles stack to one column at accessibility text sizes.

## Tests
- **Web:**
  - Unit: `homeMode`, `dockLayout`, `designTokens`, `homeHero`, `homeDiscovery` parity, `reportsPresentation`
    short labels.
  - Playwright: `tests/simple-shell-home.spec.js`, `tests/simple-shell-dock.spec.js` (mock `get_feature_flags`,
    guest).
- **iOS:**
  - Unit: `HomeModeTests`, `DockLayoutTests`, `DesignTokensTests`, `HomeHeroTests`, `HomeDiscoveryTests`.
  - UI: `SimpleShellDockUITests` and `ShellFixtureUITests`.
  - Fixture launch args: `-uiFixtureSimpleShell YES`, `-uiFixtureGuest YES`, `-uiFixtureHostMode YES`,
    `-uiFixtureHostKPIs YES`.
- **Not runnable here:**
  - The signed-in web cases and `BottomTabBarUITests`/`ReserveButtonRegressionUITests` need the live test-account
    login, which is blocked by the DOB gate and simulator keyboard focus.
- **Known unrelated failure:** `GiftTicketPDFTests.testPDFLinksPointAtRealDestinations` (it rejects banbe.app links
  after the note 41 domain switch).

## Known gaps
- Light mode: an event card with no photo shows a beige placeholder that merges into the beige block.
- Web KPI tiles don't stack at large text sizes (there's no Dynamic Type on web).

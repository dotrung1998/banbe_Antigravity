# 98 · Browse: area scope, a complete type picker, and the reader's face

Status (2026-11-30): IMPLEMENTED (web + iOS). No migration, no switch. Web build green. Playwright could not launch
(this VM's Chromium is missing `libnspr4.so`, `libnss3.so` and the X11/ATK/ALSA libraries). iOS was not compiled: this
VM has no `swiftc`, `xcodebuild` or `xcodegen`.

## What the owner saw

- Browse by type showed "1 event · Khu phố 1, Quận 4", but its Filters sheet offered only When, Price and Seats:
  there was no Location row, so the area in the count line could not be changed.
- Coming from Home's empty "Browse all events" landed on that same area-scoped list with no way to widen it.
- The account control used initials or a generic person glyph even when Account showed a profile photo.
- Changing event type meant scrolling the horizontal chip strip; after scrolling down the list the strip was gone.

## What changed

### 1. Area is an explicit two-choice scope on every Browse screen

- Web `src/screens/Browse.jsx` and iOS `BrowseView.swift` now put two pills under the heading:
  `[pin] <current area>` (opens the location picker) and `All areas` (sets the app area to every location). When no
  area is on, the pair reads `Choose area` / `All areas`.
- Web `HomeFilterSheet.jsx` no longer hides its Location section in `browseMode`, and Browse passes `areaLabel` into
  the sheet. iOS's shared filter sheet already had the Location row in `quickRows`; it stays there.
- The filter badge counts only the sheet's own filters. Area is already explicit in the two pills, and the sheet's
  Reset cannot clear the app-wide area, so counting it in the badge would promise a reset that does not happen.
- An area with nothing on is not a dead end: the empty card leads with `All areas` (web `browse-empty-all-areas`,
  iOS `browse.emptyAllAreas`) before the usual tab/map/host escapes.
- Re-tapping the already-selected `All areas` returns to the heading, like re-tapping a type or scope (note 96).
- Changing area returns the list to its heading (web effect on `areaKey`, iOS `browseTopToken` on `app.area`) instead
  of leaving the reader at a scroll position that belonged to the previous area.

**Decision:** area stays the app-wide setting (`curArea` / `app.area`). Choosing "All areas" on Browse widens Home too,
exactly like the same choice everywhere else. A Browse-only area would need a second filter state and was not added.

**Reversal:** note 81 deliberately made Browse's sheet "When, Price, Seats only". The owner's 2026-11-30 request
overrides that; `tests/public/browse-v23.spec.js` now expects the Location row instead of asserting its absence.

### 2. A complete type picker

- A `Loại ▾` / `Type ▾` control sits beside Filters on both platforms. It opens a sheet listing every type with the
  same category glyph, its live count, and a checkmark for the open type; zero-count types stay listed and muted.
- The horizontal chips remain for quick adjacent picks. The sheet is the reliable path when a type is off-screen.
- Choosing a type updates the heading and URL/state and scrolls back to the list top.
- iOS's hosts, filters, area and type sheets are one private `SheetRoute` behind a single `.sheet(item:)`; the four old
  `.sheet(isPresented:)` modifiers are gone, so no two sheets can compete for presentation.

### 3. One account face, one control size

- New web `src/components/AccountAvatar.jsx` and iOS `AccountAvatarView` (defined in `HomeShellV5Views.swift`): the
  real profile photo, initials when a signed-in profile has none, and the person glyph for a guest.
- Used by Home's band, Browse's nav, and the 64 px/pt row at the top of the quick settings panel. Home still opens
  quick settings; Browse still opens Account.
- The component takes a diameter: 40 px/pt in headers, 64 in the quick panel, so the initials and guest glyph scale
  with the disc instead of staying at their old header-only size.
- Browse's header controls are now the note-94 40 px/pt circles (they were 44), so Home and Browse share one control
  language. Category glyphs are 16 px web / 14 pt iOS in chips, 18 px / 16 pt in the picker.

## Files

- Web: `src/screens/Browse.jsx`, `src/screens/Home.jsx`, `src/screens/sheets/HomeFilterSheet.jsx`,
  `src/components/home/HomeShellV5.jsx`, `src/components/home/QuickSheetV5.jsx`, new `src/components/AccountAvatar.jsx`,
  `src/index.css`, `tests/public/browse-v23.spec.js`.
- iOS: `apps/ios/BanbeApp/Views/BrowseView.swift`, `apps/ios/BanbeApp/Views/HomeShellV5Views.swift`,
  `apps/ios/BanbeApp/Views/HomeFilterSheet.swift` (doc comment only), `apps/ios/BanbeApp/Views/QuickSheetView.swift`.
- Test ids added: `browse-area-scope`, `browse-area-current`, `browse-area-all`, `browse-type-button`,
  `browse-type-sheet`, `browse-type-option-<key>`, `browse-empty-all-areas`; iOS `browse.areaScope`,
  `browse.area.current`, `browse.area.all`, `browse.typeButton`, `browse.typeSheet`, `browse.typeOption.<key>`,
  `browse.emptyAllAreas`. Existing ids (`browse-account`, `browse-filters-button`, `browse-filter-badge`,
  `home-filter-area`, `home.avatarButton`, `browse.account`, `quick-account` / `quick.account`) are unchanged.

## Skills

Used `find-skills` to review the skills.sh leaderboard and install two fitting skills **globally** (no repo files):
`ios-design` (`uizze.sh`) and `web-design-guidelines` (Vercel). `design-mobile-apps` was rejected because it generates
screens through the Sleek API, and `frontend-design` because it pushes a new visual identity rather than consistency
inside the existing one.

## Checks

- `npm run build` — exit 0 (Vite 6.4.3, 712 modules). Only the existing chunk-size warnings and a pre-existing
  esbuild warning in `src/screens/Rewards.jsx`.
- Unit: `tests/unit/browse.test.mjs` covers `withAllAreasAction` (area action first, existing actions demoted, input not
  mutated) in the full `npm run test:unit` pass.
- Playwright: a new `browse-v23` test selects the always-present US root (zero events), asserts the empty card's
  `browse-empty-all-areas`, clicks it, and checks the list returns. It cannot run in this VM for the Chromium system-library
  reason above.
- `node --check tests/public/browse-v23.spec.js` — parsed.
- Playwright — `npx playwright test tests/public/browse-v23.spec.js --project=chromium -g "own Filters|Browse exposes"`
  failed at browser launch, not at an assertion: `chrome-headless-shell: error while loading shared libraries:
  libnspr4.so: cannot open shared object file`. `npx playwright install chromium` downloaded the shell, but the system
  libraries (`libnspr4`, `libnss3`, `libatk`, `libX*`, `libasound`) are absent and there is no root to install them.
  The new spec (area pills, area sheet, type picker) has therefore not been executed.
- iOS — source-reviewed only. Not compiled. On a device, check: the Location row in Browse's filter sheet, the two
  area pills, the type sheet's counts and selection, the avatar photo/initials/guest fallback, and that opening hosts,
  filters, area and type in sequence always presents exactly one sheet.
- Not visually inspected on web or iOS.

## Fresh-eyes review (owner screenshot, same day)

- The quick panel still showed initials while Home's band showed the photo. Both platforms now render the shared
  avatar in the quick panel as well (web `QuickSheetV5.jsx`, iOS `QuickSheetView.swift`); the guest branch is unchanged.
- Removed area from the filter badge: the badge now counts only what the sheet's Reset can actually clear.
- Added the missing empty-area escape and the re-tap-to-top behavior for `All areas` on both platforms.
- `All areas` gets `layoutPriority(1)` on iOS so a long current-area name truncates first instead of squeezing the
  second choice off a narrow screen; the web pill truncates its label inside the button, and both pills are 40 px/pt
  targets (they were 34, below the app's control standard).

## Open

- The owner's iOS screenshot showed no Location row in "Filter Browse by type" while the current source's
  `HomeFilterSheet` builds it in `quickRows`. Verify the build under test; the explicit area pills do not depend on
  that row.
- The global area choice still changes Home's area as well (by design).

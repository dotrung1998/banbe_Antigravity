# 87 · Browse by type lists every type, names itself in the nav row, and Back is one step

Status (2026-11-15): IMPLEMENTED (web + iOS). iOS built for the simulator (Debug, scheme `BanbeApp`, green). Web
`vite build` green and `npm run test:unit` 1013/1013 on the remote build Mac; the Playwright cases still cannot run there
(its chromium crashes). No migration. Same switch as note 81 (`home_v23`). Refines notes 85 and 86.

## Problem (owner, from two simulator screenshots)

1. From For You / Tonight / Weekend, "Browse by type" should show **all the types**, like the old version did.
2. On a type's list the type's name should be the **section under the nav row**, and the nav row itself (the one with
   search and the map button) should be called **"Browse by type"**.
3. Going Back should land on the **previous screen** so Browse by time is one tap away, instead of today's two
   (type's list → grid → tab).

## What changed

- **Every type is on the grid.** `browseTypeTiles` / `tiles` map the whole catalogue (`categoryDefs()`) with its count,
  including types with nothing on, sorted by count and then by the catalogue's own order. A zero-count tile opens that
  type's list and its honest empty card instead of bouncing back to the grid: the "unknown type" fallback now checks
  whether the key exists in the catalogue, not whether it has events. (Today the catalogue has five types, so the grid
  looks the same; the rule is what was asked for.)
- **The nav row names the screen, the content names the type.** On a type's list (grid family) the nav title is
  "Duyệt theo loại" / "Browse by type", and the type is a 30px heading in the content with its own count line
  ("6 events · Everywhere"). A running search shows only its query in the nav row (`“jazz”`), since the heading already
  says the type. Type lists reached through a tab keep "Tonight · Music" in the nav row, because there the type is not a
  heading.
- **Back is one step when Browse by type came from a tab.** `browseFrom` is already remembered; `backFromBrowse` and
  Browse's `goBack` now check it first, so a type's list (and the grid) return to the tab. Opened from Home, a type's list
  still steps up to the grid, and the "All" chip still reaches the grid in one tap. The back label follows: "Về Tối nay" /
  "Back to Tonight" whenever the tab is known, else "All types", else "Back to Home".

## Files

- Web: `src/screens/Browse.jsx` (`tiles`, `known`, `navTitle`, the type list's heading, `fromTab` / `goBack` order).
- iOS: `apps/ios/BanbeApp/Views/BrowseView.swift` (`tiles`, `known`, `navTitle`, `typeListHead`, `backLabel`,
  `typeGrid(_:counts:)` now takes the tiles) and `AppState.backFromBrowse` (the `browseFrom` branch first).
- Tests: `tests/public/browse-v23.spec.js` — the deep link now expects the nav title "Browse by type" and the type as
  `browse-title`; the grid asserts a zero-count type is listed; the tab case taps a type and checks Back goes to the tab.

## Checks

- **iOS:** `xcode_build` (Debug, scheme `BanbeApp`, simulator) green.
- **Web:** `npm ci`, `npm run build` green, `npm run test:unit` 1013/1013.
- **Not run:** the Playwright spec (chromium in this environment dies with `SIGSEGV` before any page loads, including
  the cases that predate these changes). No visual review on either platform.

## Open

- Whether the catalogue's empty types belong on the grid is a product call; they are there because that is what "all the
  types" asked for, and they are sorted to the end.
- The tab's own type lists (`/see-all/<tab>/<type>`) were left as they were: nav "Tonight · Music", no heading, Back to
  Home. Only the grid family got the new name/heading.

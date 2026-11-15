# 86 · A tab's See all reaches Browse by type, and Back returns to the tab

Status (2026-11-15): IMPLEMENTED (web + iOS). iOS built for the simulator (Debug, scheme `BanbeApp`, green). Web bundle
builds green and the unit suite passes, both run on the remote build Mac; the Playwright case could NOT be run (chromium
crashes on that machine, see Checks). No migration. Same switch as note 81 (`home_v23`).

## Problem

Note 85 made See all carry Home's three tabs and made Browse by type types only, but it left the two screens apart: from
`/see-all/tonight` (or For You, or Weekend) there was no way to reach `/browse` — the catalogue's type grid — without
going back to Home and starting again. The type chips only narrow the open tab (`/see-all/<tab>/<type>`), which is a
different question from "every type in the catalogue".

## The change

- **A quiet link under the type chips on a tab screen** — right-aligned, 44pt target, grid glyph + "Duyệt theo loại" /
  "Browse by type" + chevron, in the same look Home already uses for its "See all N" link. It sits at the end of the type
  row's own story ("these are this tab's types → all of them"), so it is never mistaken for another filter chip, and it is
  always visible (the chips row itself scrolls, so anything inside it could sit off-screen). Never drawn on `/browse`,
  which is where it leads.
- **`browseFrom` remembers the tab.** Opening the grid from a tab records that tab (web: `browseFrom` in `BanBeContext`;
  iOS: `AppState.browseFrom`). Back on the grid then returns to that tab instead of Home, labelled for where it goes
  ("Về Tối nay" / "Back to Tonight").
- **The full ladder**, now: a type's list under `/browse` → the grid (note 85) → the tab it was opened out of (this note)
  → Home. A type's list under a tab (`/see-all/<tab>/<type>`) → Home, unchanged.
- `browseFrom` is memory only, never in the URL: a reloaded or pasted `/browse` link has no tab to return to and Back
  goes Home. Switching tab inside See all clears it (`browseScopeTo` / `browseSwitchScope`), and every other `openBrowse`
  (Home's Browse by type, "Find a type", the end card's "All types") clears it too.

## Web

- `src/state/BanBeContext.jsx`: state gains `browseFrom: null`; `openBrowse({ type, scope, keep, from })` writes it
  (`keep` — browser back/forward — keeps what was there), and `backFromBrowse` steps the grid back to `browseFrom` (clean
  search + filters, type `all`) before falling back to Home.
- `src/screens/Browse.jsx`: new `from` and `onBrowseTypes` props, the link row under the type chips
  (`data-testid="browse-browse-types"`, `aria-label` "Duyệt mọi loại sự kiện" / "Browse every event type"), and a
  `backLabel` that now has three cases (a type's list → "All types", the grid opened from a tab → "Back to <tab>", else
  "Back to Home").
- `src/screens/Home.jsx`: `browseTypesFrom(tab)` opens the grid with `from`, and Browse gets
  `from={s.browseFrom}` / `onBrowseTypes`. `browseScopeTo` clears `browseFrom`.

## iOS (`apps/ios/BanbeApp/Views/BrowseView.swift`, `State/AppState.swift`)

- `@Published var browseFrom = ""` (`""` = opened from Home), `openBrowse(..., keep:, from:)` writes it, `backFromBrowse`
  restores the tab (clean search + filters, type `all`), `browseSwitchScope` clears it, and `browseOpenTypes()` is the
  link's action (remember the tab, then show the grid).
- `browseTypesLink` sits between the type chips and the count row on tab screens; `typeChips` now also renders when a tab
  has no types at all, so the link is there in the empty case too.
- `backLabel` gained the "Về <tab>" / "Back to <tab>" case. Identifier: `browse.browseTypes`.

## Checks

- **iOS:** `xcode_build` (Debug, scheme `BanbeApp`, simulator) — green after the change. Not looked at on a simulator or
  device, so the link row's weight under the chips has had no visual review.
- **Web:** built and unit-tested on the remote build Mac (Node 22, `npm ci`): `npm run build` green (709 modules, only
  the pre-existing `Rewards.jsx` esbuild warning and the jszip chunk note), `npm run test:unit` 1013/1013 pass. Nothing in
  `src/lib/` changed, so the route table and the pure helpers are untouched.
- **Web browser spec: NOT run.** `tests/public/browse-v23.spec.js` gained one case: from `/see-all/tonight`, the link
  opens `/browse` in index mode with no scope tabs, and Back is labelled "Back to Tonight" and lands on
  `/see-all/tonight` with Tonight selected. On the build Mac every case in that file — including the ones that existed
  before this change — fails the same way: the Playwright chromium binary dies with `SIGSEGV` before the page loads, so
  nothing about the app is being measured there. The specs still need to run somewhere with a working browser (CI or the
  owner's machine).
- **Not seen:** no visual review of the link row on either platform.

## Open / not done

- A visual pass on both platforms: the link row at 14px under the 14px chips, and the empty-tab case (chip row with only
  "All 0" plus the link).
- The link is on tab screens only. A type's list under a tab reaches the grid through the same link but loses the picked
  type on the way back (Back returns to the tab, type `all`); keeping the type there was not worth a second state field
  until someone wants it.

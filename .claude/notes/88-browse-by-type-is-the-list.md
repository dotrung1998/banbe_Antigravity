# 88: Browse by type is the list, never a grid

Status (2026-11-15): IMPLEMENTED (web + iOS). Web published to the preview (build green). iOS not re-built with this change yet — see Checks. No migration. $home_v23
switch as before. Supersedes the grid part of notes 84, 85 and 87; keeps the tab chips (85), the link (86) and the Back-to-tab rule (86).

## What was asked

Chips on a tab's See all lead to a grid of type tiles; tapping a type then shows its events. The owner wants no grid at all:
tapping "Browse by type" should show every event straight away, and tapping "All" on a type's list should show every event
too, not send you back to a grid. So: the grid is removed.

## What changed

- The browse screen has one shape now: a list. `/browse` is every event with the type chips above it, `/browse/<type>` is
  the same list narrowed by the type, and a tab's own list works as before. There is no `index`/grid mode, no
  `browse-type-grid`, no `browse-grid-<key>` tiles.
- "All" is a filter reset, not a navigation: `pickType('all')` just sets the type to `all`, both on a tab screen and on
  `/browse`, so every event shows in place. It no longer clears the search or filters, which now stay put like every other
  chip.
- The nav row names the screen: `/browse[/<type>]` shows "Duyệt theo loại" / "Browse by type"; a picked type is the content's
  30px heading with its own count line ("6 sự kiện · Everywhere"); a running search shows its query.
- Back leaves the screen: from `browseFrom` (opened through a tab's link) it returns to that tab; otherwise Home. The
  "All types" back label and the grid step-up are gone.
- The tab screen's "Browse by type" link (note 86) is unchanged: it opens `/browse` (every event) and remembers the tab.
- A type's own list no longer needs to exist in the catalogue to be reachable: a key the catalogue does not have still
  falls back to `all`, a real key keeps its list (and its honest empty card).

## Files

- Web: `src/screens/Browse.jsx` (grid branch and `tiles` removed, `pickType`/`Back` simplified, nav title, `/browse` list),
  `src/state/BanBeContext.jsx` (comments only), `src/screens/Home.jsx` (comment only),
  `tests/public/browse-v23.spec.js` (deep link, `/browse`, and the tab case rewritten for the list).
- iOS: `apps/ios/BanbeApp/Views/BrowseView.swift` (`typeIndexHead`/`typeGrid`/`tiles` removed, one list body, nav title,
  `backFromBrowse` and `browsePickType` simplified, `backLabel` no "All types" case).

## Checks

- **Web:** `publish_preview` green — the bundle builds and the preview is published
  (https://banbe-antigravity-xu2e--preview.freemilk.app). The rewritten Playwright cases were not run (chromium crashes on
  the build machine); `npm run test:unit` is unaffected by these files and was 1013/1013 on the previous run.
- **iOS:** not built for this change. The project is tagged as a web app now (so the preview can be published), which is
  the tag that offers the iOS build tools, so `xcode_build` is not available in this chat any more. The Swift edits mirror
  the web ones one-for-one and were reviewed by hand; switch the repository back to iOS app and run `xcode_build` before
  shipping the app.

## Open

- The Playwright file has three rewritten cases that have never run anywhere.
- Visual review: the `/browse` every-event screen now opens straight into hosts, chips, count and rows; the type heading
  only appears once a type is picked. Worth a look on the preview.

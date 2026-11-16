# 91 — Empty tabs get real actions, headings under the tabs, and a water drop on the page numbers

Status (2026-11-15): IMPLEMENTED (web + iOS). Web `publish_preview` green
(https://banbe-antigravity-xu2e--preview.freemilk.app). iOS edited by hand and not built: the repository is tagged as a
web app, so no `xcode_build` is offered in this chat. No migration. Refines notes 90 (which introduced the Browse tabs).

## What was asked

1. Tonight (and any other tab) with no events must offer buttons that lead somewhere. The empty card said "Nothing here yet."
   and nothing else.
2. The tabs should carry a title under them, in the same shape as a picked type's heading on Browse by type.
3. The water-drop animation was expected on the page numbers while a page is swiped.

## What changed

### 1. Empty Browse lists offer real next steps

- The no-events card (`EndCard` in `src/screens/Browse.jsx`, `emptyCard` in `BrowseView.swift`) now carries actions
  instead of an empty list:
  - a tab screen (For You / Tonight): primary "See this weekend" (or "See every type" on Weekend), then "Browse by type"
    and "Open the map";
  - `/browse` with a picked type: primary "See every type", then the map;
  - `/browse` with every type: primary "Open the map", then "Host a night".
  - Its body line now adds "Meanwhile, try somewhere else." so the card reads as an invitation rather than a dead end.
- New actions are wired through `onEnd`: `scope:<tab>` switches tab in place, `browse-types` opens the every-event list and Back
  returns to the tab.

### 2. Titles under the tabs

- `titleText` (type name, else the open tab, else "Browse by type") is now a heading on every Browse screen, in the same
  30px line and 13px count line a picked type has always had (`browse-title` / `browse-scope-count`, `browse.title` /
  `browse.scopeCount`). The count is now the list's own filtered count.
- The nav row no longer repeats the screen name: it carries only the running search (`browse-nav-title` is the query or empty), so
  "Browse by type" appears once, not twice.
- Type-chip changes (`type:<key>`) scroll back to that heading.

### 3. The page-number drop

- `Pager`'s indicator is a bead of water, not a pill: an asymmetric rounded edge with a faint highlight (`DROP_RADIUS` /
  `DROP_FILL` in `src/components/list/Pager.jsx`). On a page turn it presses in (`scale(.9, 1.1)`), stretches across to the
  next number and settles with one small wobble, keyed on the same 250ms settle the screens use.
- Second pass (the first one only moved the drop AFTER the page had already committed, which read as no animation
  under the finger): while the track is scrolling, `onScroll` calls `liveInk`, which reads the fractional scroll
  position, finds the two nearest number boxes and paints the drop between them, pressed and squashed hardest halfway
  between them. `live` keeps a mid-drag page change from animating the drop a second time, and a 220ms idle timer calls
  `settleInk`, which releases the press onto the number the track landed on with a short spring. The same timer is what
  resets `data-swiping`, so the edge tabs and the drop settle together.
- iOS's `V23Pager` background uses the same idea: a gradient capsule with a water highlight, squashed while a page
  changes (0.14 / -0.2 on `dropPress`, played from `onChange(of: page)`) and held pressed for as long as `swiping`
  (iOS 18 scroll phase) lasts, so the number visibly gathers and moves to the next one.
- Both are decorative: no layout change, nothing announced, still under Reduce Motion.

## Files

- Web: `src/screens/Browse.jsx`, `src/components/list/Pager.jsx`, `tests/public/browse-v23.spec.js`.
- iOS: `apps/ios/BanbeApp/Views/BrowseView.swift`, `apps/ios/BanbeApp/Views/HomeV23Views.swift`.

## Checks

- **Web:** `publish_preview` green (the bundle builds and the preview is published). The Playwright cases were updated (heading instead
  of nav title, the empty-tab actions, the page-number drop) but not run: chromium crashes on the build machine.
- **iOS:** not built; the Swift changes mirror the web ones and were reviewed by hand.

## Open

- The page-number drop's press/squash is tuned by eye; worth a look on the preview at phone width.
- Whether the `scope:weekend` empty action should also appear on Home's hero tab row is a product call; Home's own empty states already have
  their own "See this weekend" call to action.

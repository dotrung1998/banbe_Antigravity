# 96 · Picking from the band returns you to the events (web + iOS)

Status (2026-11-23): IMPLEMENTED (web + iOS). No migration, no switch. Not built or run: no Xcode here and
`publish_preview` still refuses (2001 files, cap 2000).

## What the owner reported

"In Home, when I scroll down, open the folded band's button and choose an option, the view does not automatically return
to the events." With the tabs folded (note 95) the view/area pill is the only way to switch, and it is reachable from
anywhere in a very long feed — so the choice was applied to a list that changed far above the reader's viewport, which
reads as "nothing happened". The same screenshot showed the web's frosted view menu still hanging over content that had
scrolled underneath it.

Then, with the first fix in: "Options remain available here and in other instances where clicking again while already
inside an option should automatically return to events during scrolling." The option the reader is already on (the open
tab, the checked area, the selected Browse tab or type chip) was still a dead tap.

## The fix

- **One action, "return to the events", runs on every pick — including the one already on.** Web: `returnToEvents()` in
  Home.jsx sets `homeScrollTopToken`, which App.jsx owns (it zeroes the app scroller; area picks go through the same
  token from `pickArea` in BanBeContext, so the expanded chip, the folded pill's Area row and the area list all agree).
  iOS: `app.resetHomeScrollToTop()` in `selectGoerTab` (now called for every tab, not only a change), in `openHosting`,
  and in `AppState.pickArea` when the screen is Home. `resetHomeScrollToTop` also unfolds the band, so the reader lands
  on the events with the tabs back — the visible acknowledgement of the pick.
- **No double scroll.** The earlier version watched a `host|tab|area` key and scrolled on change; the token replaces
  it, so a changed pick and a re-pick travel exactly the same path and the first render never moves a restored scroll.
- **Area picks only reset on Home.** Everywhere else an area is a filter on another screen, not a place to return to.
- **The frosted menu closes on any scroll** (`GlassMenu.jsx`, one capture-phase scroll listener while open), so a menu
  opened from the pinned band can no longer float over content the reader has moved to. It still closes on a tap
  outside, on Escape, and after an item is chosen. iOS's native `Menu` dismisses itself the same way.
- **The same idea in Browse, "another instance" of the pattern:** on web, re-tapping the open scope tab or the open type
  chip scrolls the list back to its heading; on iOS the scope tabs and type chips bump `browseTopToken`, which scrolls
  to the now-anchored `browse.listTop` (the anchor existed in a `scrollTo` call but was never attached, so the end card's
  "see this type" jump had been a no-op too).

## Files

- `src/screens/Home.jsx` — `returnToEvents()` (homeScrollTopToken) passed to the band.
- `src/components/home/HomeShellV5.jsx` — view menu rows, Hosting row and the tab row all call `onReturnToEvents`.
- `src/state/BanBeContext.jsx` — `pickArea` bumps the token when the screen is Home (updater form, so it sees the screen).
- `src/components/GlassMenu.jsx` — close on scroll, listener cleaned up.
- `src/screens/Browse.jsx` — an active scope tab or type chip scrolls to the list head.
- `apps/ios/BanbeApp/Views/HomeShellV5Views.swift` — `selectGoerTab` always resets; `openHosting` already did.
- `apps/ios/BanbeApp/State/AppState.swift` — `pickArea` resets on Home.
- `apps/ios/BanbeApp/Views/BrowseView.swift` — same-tap scroll on scope tabs/type chips, `browse.listTop` anchored.

No test ids changed and no spec was touched. Not verified in a browser or on a device; the behaviour to confirm is:
scroll deep, open the pill, pick Tonight → the page returns to the top with the tabs shown and Tonight selected; pick an
area → same, and the list is for that area; **pick the option already on → same again**; open the menu and scroll → the
menu closes; on Browse, tap the open tab or chip → the list jumps back to its heading.

## Follow-up (2026-11-23): the iOS menus stayed open while scrolling

Two screenshots of the same area menu at two scroll positions (the page at the top, then at "Next up") showed the native
`Menu` still open after the reader had scrolled the feed. The web menu closes on any scroll, but a SwiftUI `Menu` has no
`isPresented` binding and stays until a tap outside or a selection.

`HomeHeaderCompact` now bumps a `menuGeneration` on the rising edge of each scroll gesture (a movement after 200 ms of
quiet), and both middle controls — the expanded area chip and the folded view + area pill, which also carries the nested
area submenu — carry `.id(compact.menuGeneration)`. A new identity rebuilds them, which dismisses the open menu; the
gesture-edge guard means normal scrolling rebuilds nothing.


## Follow-up 2 (2026-11-23): the web area menu did not close on scroll

The same screenshots after the web preview was publishing again: the band's **area** menu (All locations / Vietnam / United
States / Use my location / Search locations…) hung over the feed while it scrolled. `GlassMenu` (the folded view pill)
already closed on any scroll, but the area menu is not a `GlassMenu` — it is `AreaMenu`, a fixed backdrop plus a card
positioned from `areaMenuAnchor`, and it only listened for Escape and an outside tap. `SortMenu` is built the same way and
had the same gap.

Both now listen for scroll in the capture phase on `document` (the app's own scroll viewport included), armed 120 ms after
opening so a browser's scroll-into-view of the trigger cannot dismiss them on arrival. `AreaMenu` ignores scrolls whose
target is inside its own card: the card is capped at 70 vh and scrolls itself when a country has a long area list, and that
is not the feed moving.

Files: `src/screens/sheets/AreaMenu.jsx`, `src/screens/sheets/SortMenu.jsx`. Not verified in a browser — the preview built.
iOS is unchanged: the band's native menus use the `menuGeneration` identity rule from the follow-up above.

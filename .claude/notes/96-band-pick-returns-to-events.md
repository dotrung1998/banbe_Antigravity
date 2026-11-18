# 96 · Picking from the band returns you to the events (web + iOS)

Status (2026-11-23): IMPLEMENTED (web + iOS). No migration, no switch. Not built or run: no Xcode here and
`publish_preview` still refuses (2001 files, cap 2000).

## What the owner reported

"In Home, when I scroll down, open the folded band's button and choose an option, the view does not automatically return
to the events." With the tabs folded (note 95) the view/area pill is the only way to switch, and it is reachable from
anywhere in a very long feed — so the choice was applied to a list that changed far above the reader's viewport, which
reads as "nothing happened". The same screenshot showed the web's frosted view menu still hanging over content that had
scrolled underneath it.

## The fix

- **The feed goes back to the top whenever what it shows changes**: another tab, the host view, or another area. On web
  that is one derived key (`host|tab|area`) guarded by a ref so the first render is not treated as a change (a restored
  scroll position is never overridden); on iOS `selectGoerTab` now resets for goer-to-goer switches too (it already did
  when leaving Hosting) and the band resets on `app.area`.
  Both resets are the app's existing ones (`scrollTo` on `[data-testid="app-scroll-viewport"]` with Reduce Motion going
  instant; `app.resetHomeScrollToTop()`, which also unfolds the band), so the reader lands on the events with the tabs
  back — the band unfolding is the visible acknowledgement of the pick.
- **The frosted menu closes on any scroll** (`GlassMenu.jsx`, one capture-phase scroll listener while open), so a menu
  opened from the pinned band can no longer float over content the reader has moved to. It already closed on a tap
  outside, on Escape, and after an item was chosen. iOS's native `Menu` dismisses itself the same way.
- Choosing an option that changes nothing (the tab you are on, the area you are in) still closes the menu and does not
  move the page.

## Files

- `src/screens/Home.jsx` — the `feedKey` effect ("a new view or area puts the feed back at the events").
- `src/components/GlassMenu.jsx` — close on scroll, with the listener cleaned up.
- `apps/ios/BanbeApp/Views/HomeShellV5Views.swift` — `selectGoerTab` resets on every tab change; `HomeHeroPinnedHeader`
  resets on `app.area` (the chip and the folded pill both go through it).

No test ids changed and no spec was touched. Not verified in a browser or on a device; the behaviour to confirm is:
scroll deep, open the pill, pick Tonight → the page returns to the top with the tabs shown and Tonight selected; pick an
area → same, and the list is for that area; open the menu and scroll → the menu closes.

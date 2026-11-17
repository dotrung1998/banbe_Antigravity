# 95 · Home's band folds on scroll, and keeps Hosting one tap away

Status (2026-11-22): IMPLEMENTED (web + iOS). No migration, no switch. Web preview NOT published (the publisher still
counts 2001 files, cap 2000); iOS NOT built here.

## What the owner asked

With the new band (note 94) the tab row stays pinned forever, even far down the feed where no hero events are on screen
("khi kéo xuống đây thì tab ẩn đi vì không còn nhìn thấy events nữa"). But Hosting is a *separate view*, not a filter:
once the tabs are gone the owner must still see that it exists ("cũng phải để hosting như nào đấy để vẫn biết vẫn có
hosting tab là riêng").

## The design

**The band folds to one row.** Past 72 px of scroll the 44 pt tab row folds up into the bar (height + opacity animate over
240 ms); it unfolds only back at the very top (below 24 px), so it never flaps mid-scroll. The bar keeps its 58 pt row of
wordmark / middle / search, Map, account, and the feed gets the 44 pt back.

**The middle becomes the view pill.** While the tabs show, the middle is the area chip. Once they fold, the same cell
cross-fades to a two-line pill — the open view over the area, e.g. "For You" / "pin Everywhere" — the Airbnb
"Homes in Lisbon / Anytime" pattern. One tap opens a menu with:

1. For You · Tonight · Weekend (radio, check on the open one),
2. a divider and **Hosting**, labelled as the host view (only when signed in — the same condition that shows the
   Hosting tab),
3. a divider and the area ("Area · Everywhere"), which opens the existing area picker.

So the open view is always named, every view including Hosting is one tap away, and the area stays reachable — the three
things the tabs used to carry, in 44 pt of bar instead of 44 pt of page.

The two middle controls share one grid cell (web) / ZStack (iOS), so the bar never reflows when they cross-fade. Ids:
web keeps `home-search-row`, `home-area-toggle`, `home-area-label` and the tabs; adds `home-view-pill`, `home-view-menu`,
`home-view-<tab>`; iOS adds `header.view`. The area chip and the tabs drop out of the focus/screen-reader order while
folded.

## Files

- Web: `src/components/home/HomeShellV5.jsx` (compact state with hysteresis, the grid-stacked middle, the `GlassMenu`
  view menu), `src/index.css` (mid slot, view pill, tab fold; `--bb-home-head-h` is 58 while folded so scrolling to a
  section clears the bar).
- iOS: `apps/ios/BanbeApp/Views/HomeShellV5Views.swift` (`HomeHeaderCompact` observable with the same 72/24 thresholds
  and a Reduce Motion switch, the folded pill with its native `Menu`, animated tab fold and height), `HomeView.swift`
  (feeds the scroll offset), `AppState.swift` (reset unfolds the band).

## Checks

- NOT run: `vite build`, Playwright, Xcode build, device. `publish_preview` still refuses before building (2001 files).
- The web fold changes the header's layout height, so the feed shifts 44 pt with the 240 ms fold — intentional (the
  content takes the space back), but it is the thing to eyeball on a device.
- iOS: the hero spacer follows via the header's `height` binding, written inside the same animation.

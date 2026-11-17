# 93 · Home header: one premium band for the wordmark + search (web + iOS)

Status (2026-11-21): IMPLEMENTED (web + iOS). No migration, no switch. Web preview NOT published (the repo is
over the preview build's 2000-file cap, 2001 — see Checks); iOS NOT built here.

## What was wrong

Owner's screenshot of the compact Home header: the wordmark sat jammed against the search pill, the pill's contents
(placeholder half, divider, pin, area, chevron) were squeezed into ~180 px, the Map and avatar circles hugged the right
edge with the gear badge half outside the bar, and nothing on the line shared a common centre — the logo's middle, the
circles' middle and the pill's middle were three different heights.

Root causes:

1. **The wordmark box is not the wordmark.** `/banbe-wordmark.png` is 1206 × 544 with a transparent margin: the drawn
   mark is ~76 % of the box's width and ~68 % of its height. The compact geometry spent 55 px for a logo whose drawn
   edge was further right, so the iOS pill started at `left = 94` while the drawn mark ended at ~100: the two overlapped
   on every phone (web: the same 6 px, since `.bb-home-head__wordmark` reserves `2.217 × height`).
2. **One ramp for three movements.** `--hm`/`compact` drove the brand shrink, the pill's rise *and* the bar's fade
   together, so half-way through the scroll the pill passed straight over the wordmark's lower half.
3. **No shared centre.** The brand shrank its own way (top +6 px), the quick panel shrank another (top −12 px) and the
   pill's box was 46 → 40 px, so the compact bar's three groups sat at 24/8/8.
4. The compact bar was 56 px with a 20 px radius while the pill inside it was 40 px: a pill in a pill, with 8 px of
   dead space around a 12 px inset.

## The design now (identical numbers both platforms)

One floating espresso bar, 62 px tall, 12 px in from each side, radius 24, a clay cast top-left, a hairline and a soft
shadow. Its three groups share one centre line — **y 31**, the bar's own middle:

| group | compact | at rest |
| --- | --- | --- |
| wordmark | box 22 px tall (≈15 px drawn), left 22, top 20 | box 45 px, left 20, top 18, date under it |
| search pill | `left 78` / `right w−120` (192 px on a 390 phone, up from ~182), y 9, 44 px tall | full second row, y 96, 46 px |
| Map + avatar | 40 px discs, gap 6, right 26 | 42 px discs, gap 8, right 20 |

Three ramps on the one scroll progress `--hp` (= `HomeHeaderFade.progress`), in this order, so nothing can cross:

- `--hs` (0 → .5): the wordmark settles to its compact size, the date leaves, the quick panel tightens to its centre;
- `--hx` (.35 → .6): the pill narrows from the full row to the 192 px it will keep — while it is still on row 2;
- `--hu` (.55 → 1): the scrim hands over to the bar and the pill rises into it (96 → 9).

Pill: paper gradient `#FCFAF6 → #F1ECE2`, 10 % ink hairline, inset highlight + `0 10px 24px` shadow; the magnifier is
the field's one warm accent (`--bb-clay`) and the pin stays quiet ink; the placeholder fades with the narrowing
(`1 − 1.7 × --hx`) instead of being cut off by the divider. The avatar keeps its clay disc, a tighter 1 px gear badge
that now sits fully inside the bar, and the Map circle gains an inset highlight and a soft shadow.

`data-compact` (the final hint `display:none` / area flex swap) moved from `p > 0.8` to `p > 0.9`, where the
placeholder's opacity has already reached 0 — no visible snap.

## Files

- Web: `src/index.css` (`.bb-home-head*`, the whole block), `src/components/home/HomeShellV5.jsx` (compact threshold,
  wordmark shadow — `filter: invert(1) drop-shadow(…)`), `src/components/PersistentSearchBar.jsx` (the glide now starts
  from the whole paper row — `[data-testid="home-search-row"]` — not just the search half).
- iOS: `apps/ios/BanbeApp/Views/HomeShellV5Views.swift` — `HomeHeaderFade.progress` (was `compact`), the night wash
  hands over on the rise, `HomeHeaderCompactSurface` (62/24/12), and `HomeHeroPinnedHeader`'s brand / quickRow /
  wordmark / glassCircleButton / avatarButton / searchRow, all derived from `shrink` / `slide` / `rise`.
  `HomeHeroPinnedHeader.fallbackHeight` stays 142 and the rest-state geometry is unchanged apart from the quick
  panel now centring on the wordmark (34.5 instead of 45).

Test ids and accessibility ids are untouched: `home-title`, `home-date`, `home-map-button`, `home-avatar-button`,
`home-search-row`, `home-search-bar`, `home-area-toggle`, `home-area-label` (web) and `home.title`, `home.date`,
`home.searchBar`, `header.area(_label)`, `home.mapButton`, `home.avatarButton` (iOS).

## Checks

- NOT run: `vite build`, `test:unit`, Playwright, Xcode build, device. `publish_preview` refused before building —
  "This web app has 2001 files; a published site can have at most 2000" (the repo itself is being counted, i.e. the
  preview takes it as a plain-files site, so nothing here can be rendered through Run either).
- Geometry was derived by hand (the table above) and every rest-state offset stays within the 142/152 px header, so
  `tests/public/home-hero.spec.js`'s "sticky header after scrolling" (title/quick/search within y 0…200) still holds:
  compact y is 20 / 11 / 9.

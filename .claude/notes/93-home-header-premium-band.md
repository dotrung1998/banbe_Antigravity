# 93 · Home header: a Liquid-Glass nav bar instead of a floating slab (web + iOS)

**SUPERSEDED by note 94 (2026-11-22).** The morphing band described below is gone: Home's band is now one static paper
app bar with the tabs inside it. Kept as the record of what the owner rejected and why.

Status (2026-11-21): IMPLEMENTED (web + iOS). No migration, no switch. Web preview NOT published (the publisher counts
2001 files, cap 2000 — see Checks); iOS NOT built here.

## What the owner saw

Two passes on the same band, after the owner sent a screenshot of the condensed Home header: "vẫn cục mịch" — still
clunky. The first pass only tuned spacing; the second threw the arrangement out.

## Why it read as clunky

1. **Five shapes fighting on one line.** A rounded slab, a pill inside it, two glass circles and an avatar with a badge:
   three radii (24 / 999 / 50 %) and two materials (espresso dark + paper white) inside 390 pt.
2. **A dark floating slab over light paper.** Once scrolled the hero is gone and the band floated a near-black capsule
   over the cream feed — an object that belongs to nothing, with a heavy shadow under it.
3. **A split field.** Search half | divider | area half read as two controls and cost the field ~10 pt for a hairline.
4. **A redundant shortcut.** The header's Map circle did what the dock's Map tab already does; its 48 pt was exactly the
   room the field needed.
5. **Three heights.** Logo middle, circle middle and pill middle were three different numbers, so the row never composed.

## The design now

**At rest** (over the hero): the wordmark with the date under it as a small tracked kicker (11.5 / 600 / .14em,
uppercase, white 64 %), the avatar top-right, and **one** search card across the second row — 52 pt, capsule, the
theme's own paper with a rim highlight and a soft shadow, the magnifier in clay, and the area as a **chip inside the
field** (34 pt capsule, 7 % ink): one shape to look at, two things to use.

**Condensed** (after 96 pt of scroll): the app's own **Liquid-Glass nav bar** — the v2.3 Event Detail material
(`rgba(var(--bb-bg-rgb), .84)` + `blur(30px) saturate(1.7)`, `--bb-rt-*` under Reduce Transparency), full width, 64 pt,
one bottom hairline, one soft shadow. iOS uses the system `.bar` material, which follows the theme and Reduce
Transparency by itself. Inside it: the small wordmark, the same field as an **inset capsule** (6 % ink, so the bar's
material reads through instead of a second bright surface), and the avatar.

The wordmark runs one drawing twice — white over the hero, then the theme's logo ink (dark mode's amber on iOS) — a
cross-fade on the tail of the bar's ramp, so it is never crisp white on a paper bar.

Geometry (identical numbers both platforms, 390 pt): bar 64 tall at the safe-area top · field 74 in from the left and
64 in from the right (192 → 252 pt wide) · wordmark box 40 → 20 pt tall (drawn width 88 → 44; the artwork is
1206 × 544 with a transparent margin) · avatar 40 → 34 · at rest every group centres on y 36, in the bar on y 32.

Ramps on one scroll progress `--hp` (= `HomeHeaderFade.progress`): `--hs` 0 → .5 the brand settles · `--hx` .35 → .6 the
field narrows to the bar's room · `--hu` .55 → 1 the bar condenses and the field rises into it · `--hb`, the wordmark's
swap. Nothing crosses anything; Reduce Motion jumps between the two ends.

**The Map shortcut left the header**, on both platforms, because Map is a dock tab. That is the one behaviour change,
and it is what let the field grow from ~182 to ~252 pt. It can come back as a third element in the bar on request.

## Files

- Web: `src/index.css` (the `.bb-home-head*` block, rewritten), `src/components/home/HomeShellV5.jsx` (mark with two
  inks, area chip, no divider, no Map button, shorter placeholder), `src/screens/Home.jsx` (drops the unused `onMap`
  prop). `src/components/PersistentSearchBar.jsx` is unchanged: its glide still starts from `home-search-row`.
- iOS: `apps/ios/BanbeApp/Views/HomeShellV5Views.swift` — `HomeHeaderNavBar` (was `HomeHeaderCompactSurface`),
  `HomeHeroPinnedHeader` (`fallbackHeight` 142 → 152, `shrink` / `slide` / `rise` / `swap`, brand + `mark`, the single
  `avatarButton`, `searchRow(tight:)` with the card layer → inset field and the area chip); the Map button and
  `glassCircleButton` are gone.
- Test: `tests/public/home-hero.spec.js` no longer expects `home-map-button` (it still asserts the sticky header keeps
  `home-title`, `home-avatar-button`, `home-search-row`).

Ids kept: `home-title` (now on the mark's box), `home-date`, `home-avatar-button`, `home-search-row`, `home-search-bar`,
`home-area-toggle`, `home-area-label`; iOS `home.title`, `home.date`, `home.searchBar`, `header.area(_label)`,
`home.avatarButton`, plus the tour targets `tour.home.headerBottom` / `tour.home.search`.

## Checks

- NOT run: `vite build`, `test:unit`, Playwright, Xcode build, device. `publish_preview` refuses before building
  ("This web app has 2001 files; a published site can have at most 2000"), so nothing here was rendered through Run.
- Geometry derived by hand (numbers above); the condensed groups sit at y 22 (mark) / 15 (avatar) / 10 (field), inside
  the 152 px header, so the sticky-header assertion still holds.
- Two details to eyeball on a device: `rgba(255,255,255,var(--bb-pill-hi))` (a CSS var inside an alpha) and the
  `::before` card layer's paint order — above the field's own fill, under its children via explicit z-index 0 / 1.

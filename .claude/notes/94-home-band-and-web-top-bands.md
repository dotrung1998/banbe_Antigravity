# 94 · Home's band is one paper app bar; web top bands clear the status strip

Status (2026-11-22): IMPLEMENTED (web + iOS). No migration, no switch. Web preview NOT published (the publisher counts
2001 files, cap 2000 — see Checks); iOS NOT built here.

## What the owner saw

Two screenshots after note 93: Home's condensed band still read as clunky, and its bar **straddled the tabs** ("For You
Tonight Weekend Hosting" half-hidden under it). The owner's own proposal: make search a round button beside Map and the
quick panel, and put the area in the middle of the band. Also: on the web, other screens' top band covers a bit of the
buttons below it.

## Design research (web inspector, airbnb.com / apple.com / music.apple.com / instagram.com, phone viewport)

The patterns worth copying, as reported:

- **Airbnb home**: one search pill, then a category row — **both rows inside the pinned header**; content hard-clips at
  the band's edge; no divider and no shadow on the sticky bar (the blur is the separation); 16–25 pt side insets.
- **Airbnb search results**: back arrow · a centred white pill ("Homes in Lisbon / Anytime · Add guests") · a filters
  glyph — the "one centred object, quiet edges" recipe applied to a filter.
- **Apple / Apple Music**: extreme negative space; 3 bare 17 pt glyphs with 30 pt between centres; exactly one filled
  pill; the wordmark is the only loud mark.
- **Instagram**: wordmark left, one text link + one filled pill right, separation by a 1 px line, never a shadow.
- Composite: band 56 pt, 16 pt insets, round controls 40–44 pt diameter (18 pt glyph, 5–6 % ink fill, 1 px hairline),
  an area/filter chip 32–36 pt tall and **centred**, tabs either inside the band (Airbnb) or at the bottom — never both.

The owner's instinct matched the research exactly: round controls on the right, the filter in the middle, the tabs
inside the band.

## The design now (both apps)

**One paper app bar, two rows, no morph.** 58 pt of controls + 44 pt of tabs + one hairline. It is the first element of
Home's scroller (`position: sticky`, in flow), so nothing can ever be cut by it.

- Row 1: the wordmark (30 pt box, theme logo ink) · the **area chip** centred between brand and controls (32 pt capsule,
  pin + 13/600 label + chevron, 5 % ink fill, 1 px divider; "Everywhere" in `fg-3`) · three **40 pt circles**: search
  (clay magnifier), Map, account (clay disc with initials).
- Row 2: For You · Tonight · Weekend · Hosting — 15.5 pt, 600 when selected, 2 px ink underline, 600 weight inactive at
  `fg-3`; the row scrolls horizontally only as the fallback.
- The date is no longer a second line in the band: it is the hero's kicker (11 / 600 / .14em, white 58 %), so the band
  keeps one row and Home's first screen is shorter, not taller.
- Nothing morphs: no scroll-linked CSS variables, no `HomeHeaderFade`, no night wash, no cross-faded wordmark, no card
  shadow. `stuck` only adds a 1 px-tall lift once the feed is under it.

Search is still one search: the circle calls the same `openSearch`, and `PersistentSearchBar` measures
`home-search-row` — now the whole 58 pt bar row — so the field still glides out of Home's own band. The Map shortcut is
back in the band (owner 2026-11-22), beside search and account.

Home also stopped being a **full-bleed** web screen (`App.jsx`): its band is paper, so the status strip is paper and the
scroller starts below it, exactly like Browse/Account/Schedule. The dark hero begins under the band.

## Web top bands on other screens

1. **One variable owns the status strip**: `--bb-strip-h` (index.css) is `--bb-safe-top` on fine pointers and its
   `max(…, 12px)` on coarse ones. `body::before` paints that height, `SAFE_TOP` (`src/lib/viewport.js`) resolves to it,
   and App's scroll viewport offsets by `SAFE_TOP`. Before this, on a phone whose `env()` inset is smaller than the
   strip's 12 px minimum, the strip **clipped the first row of every sticky web band** by a few pixels — the "band covers
   a bit of the buttons below" the owner saw.
2. **Browse / See all** (`src/screens/Browse.jsx`): the nav row is a fixed 58 pt, the tabs 44 pt with the same type
   rhythm as Home's band, one `--bb-divider` hairline, `z-index 30`, and the content's scroll margin (112) clears the
   band's full height, so a jumped-to heading can never land under it.

## Files

- Web: `src/index.css` (the `.bb-home-head*` block rewritten: strip variable, app bar, area chip, round buttons, tabs),
  `src/components/home/HomeShellV5.jsx` (new header markup, date kicker in the hero, no morph effect, no `setThemeColor`,
  `onMap` back), `src/screens/Home.jsx` (passes `onMap`), `src/screens/Browse.jsx` (web band), `src/App.jsx` (Home no
  longer full-bleed; comments), `src/lib/viewport.js` (`SAFE_TOP`).
- iOS: `apps/ios/BanbeApp/Views/HomeShellV5Views.swift` (`HomeHeroPinnedHeader` rewritten: bar row + tabs row, area Menu
  chip, `roundButton`, tabs moved in from the hero, 102 pt, paper with `.ignoresSafeArea(.top)`; `HomeHeaderFade`,
  `HomeHeaderNightWash`, `HomeHeaderNavBar` and the hero's `tabsRow` deleted; avatar gear badge dropped, date kicker
  moved to `HomeHeroSection`), `HomeView.swift` (`tab: $heroTab` into the header, no fade update), `AppState.swift` (no
  fade reset).
- Ids kept: `home-sticky-header`, `home-title`, `home-date` (hero), `home-avatar-button`, `home-search-row` (bar row),
  `home-search-bar` (circle), `home-area-toggle`, `home-area-label`, `home-hero-tabs`, `home-hero-tab-*`, plus the new
  `home-map-button`; iOS `home.title`, `home.date`, `home.searchBar`, `home.mapButton`, `header.area(_label)`,
  `home.avatarButton`, and the tour targets `tour.home.search` (bar row) / `tour.home.headerBottom` / `tour.home.tonight`.

## Checks

- NOT run: `vite build`, `test:unit`, Playwright, Xcode build, device. `publish_preview` refuses before building ("This
  web app has 2001 files; a published site can have at most 2000"), so nothing here was rendered through Run.
- Geometry derived by hand (390 pt): row 1 = 16 + mark box ~66 + chip (≤ 56 %, shrinks) + 3×40 + 2×8 + two 10 pt gaps
  + 16; the chip shrinks to ~142 on a 390 pt screen, so "Everywhere" still fits with its pin and chevron.
- Watch on a device: the area `Menu`'s intrinsic width inside a `Spacer` sandwich (iOS) and the 56 % cap under long area
  names (web); both truncate rather than push the circles.

# 97 — Tonight's empty card knows where the weekend leads, and "Browse all events" opens all events

Status (2026-11-18): IMPLEMENTED (web + iOS). Web `vite build` green. iOS edited by hand and not built (no Xcode in
this VM). No migration. Refines notes 91 (empty tab actions) and 88 (Browse by type IS the every-event list).

## What was asked

1. Tapping "See this weekend" on an empty Tonight can land on a Weekend that is empty too, where the card then offers
   "Browse all events". Tonight's card must offer "Browse all events" by itself — while keeping "See this weekend" when
   the weekend really has events.
2. That "Browse all events" (and iOS's "Show all events in <area>") scrolled Home down to the By type section, which
   only ever holds a handful of events. It must show every event.

## What changed

### 1. Tonight reads the weekend rail before promising it

- Home already builds the three hero rails from the same discovery items, area and filters (only the date differs), so
  the Weekend rail is an honest answer to "does See this weekend lead anywhere?".
  - Web: `weekendHasEvents` in `src/components/home/HomeShellV5.jsx` (`lists.weekend`).
  - iOS: `weekendHasEvents` in `HomeHeroSection.emptyCard` (`lists[.weekend]`), `HomeShellV5Views.swift`.
- Weekend empty: Tonight's primary action becomes **Browse all events** (the weekend card itself still has it).
- Weekend has events: the current approach stands — **See this weekend** stays primary — and **Browse all events** is
  added as the second pill, so it is on Tonight either way. When an area/filter narrows Home the card already carries
  Change area + Show all events + the underlined action, so the extra pill only appears in the un-narrowed layout
  (web `home-hero-empty-more`, iOS `home.hero.empty.more`).

### 2. Browse all events is the every-event list

- Web: `onBrowseAll` (src/screens/Home.jsx) now runs `browseTypesFrom(heroTab)` — the same path as Browse by type: a
  fresh Browse list with scope `all`, type `all`, default filters, and `browseFrom` = the open tab so Back returns to
  its See all. It no longer sets `homeFilters.date = 'any'` and scrolls to `home-browse` / `home-by-type`.
- iOS: the same action, `app.openBrowse(type: "all", scope: "all", from: tab.rawValue)`. The
  `homeBrowseScrollRequest` plumbing it used to bump is removed (`AppState.swift`, HomeView's `onChange`), and the
  area-only "Show all events in <place>" clear action now opens the same list instead of scrolling.

## Files

- Web: `src/components/home/HomeShellV5.jsx`, `src/screens/Home.jsx`.
- iOS: `apps/ios/BanbeApp/Views/HomeShellV5Views.swift`, `Views/HomeView.swift`, `State/AppState.swift`.

## Checks

- Web: `npx vite build` green. Not opened in a browser this pass.
- iOS: source only — no compiler here; the change is two view-level branches plus one removed state property.
- Not run: `tests/public/home-hero.spec.js` (its fixtures put all three mocked events in the coming weekend, so it still
  sees "See this weekend"; Playwright's chromium cannot start in this VM because `libnspr4.so` is missing).

## Open

- Whether Browse's own Weekend empty card should also offer the whole catalogue (it currently offers "See every type",
  which stays inside the weekend scope) is a product call.

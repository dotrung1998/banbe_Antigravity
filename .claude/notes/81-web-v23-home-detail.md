# 81 · Web v2.3 Home + Browse by type + Event Detail (behind `home_v23`)

Status: IN PROGRESS. Phase 0 (test data) COMPLETE, groups A–F APPLIED to production 2026-11-13. Phases a (Shortlist pager, end cards, rows), b (Browse by type / See all), c (live line) and d (Event Detail tear-off strip, compact/full bar, 4+ stepper) IMPLEMENTED LOCALLY, not committed. Migration 218 APPLIED to production 2026-11-13 (switch OFF). Phases e–f not started (e needs migration 219 written first).

Source of truth: `docs/prototypes/homescreen-event-detail-motion-v2-3.html` (v2.3.2, commit 1daec2a), side-panel notes + Motion spec.
Plan: `~/.claude/plans/ethereal-crunching-tulip.md` (approved 2026-11-13).

## Decisions (owner, 2026-11-13)
- Web only. iOS out of scope (only the switch key goes into `FeatureFlagCategories.swift`, because the unit test parses it).
- Everything behind one admin switch `home_v23` (migration 218, seeded OFF, OFF_UNLESS_SET). v2.3 builds on `simple_shell` (HomeShellV5), not on the legacy Home.
- Add tickets after a hold = a SECOND booking via `hold_seats_with_attendees` (no backend change). The bar sums the viewer's seat-holding bookings and caps the total at 6.
- 6 per person across bookings: migration 219 to be written and tested locally, applied only on a separate yes. Today the server enforces 1–6 per booking only (`hold_seats_with_attendees`); `hold_seats` allows 20 per call and `claim_seats` has no bound and is still granted to `authenticated`.
- Wide split view (prototype Duo/iPad) deferred to phase f.

## Phase a · Shortlist pager, end cards, rows (2026-11-13, IMPLEMENTED LOCALLY)
- Switch: `home_v23` in `FLAG_KEYS` + `OFF_UNLESS_SET` (`src/lib/featureFlags.js`), category `layout` (`featureFlagCategories.js`), row in `AdminFeatures.jsx`. iOS got the key only (`FeatureFlags.swift`, `FeatureFlagCategories.swift`, `AdminFeaturesView.swift`) because `featureFlagCategories.test.mjs` checks parity. iOS does nothing with it.
- Migration file `20261231000218_218_home_v23_switch.sql` + rollback `supabase/rollbacks/20261231000218_218_revert_home_v23_switch.sql` (217's pattern). **APPLIED 2026-11-13 16:31 UTC, seeded OFF** (see the production log).
- Reading: `v23 = simpleShell && flagOn(flags, 'home_v23')` in `Home.jsx`. Switch off = Home unchanged (By type sections, Browse above them).
- Pure rules: `src/lib/pager.js` (paginate 4 a page, `pageRange` "5–8 of 18" / "5–8 trên 18", `endCardRoom` solo/slim/mid/fill, `showPageNav`, `inkFrames`, `pageAt`, `pageWindow` at most 5 numbers around the current page) and `src/lib/listEnd.js` (`shortlistEnd`, `slimmed`). Tests: `tests/unit/pager.test.mjs` + `tests/fixtures/pager.json`.
- Components: `src/components/list/Pager.jsx` (scroll-snap track with `data-hscroll`, numbers + arrows 44 px, ink stretch via WAAPI, rows slide in from the travel side with a 45 ms stagger, inactive pages `inert` + `aria-hidden`, range line `aria-live="polite"`, reduced motion = no slide and the ink jumps), `EndCard.jsx`, `EventRowV23.jsx` (kicker type · when, title, place or status, price centred, no chevron, keeps `home-event-<key>` and `data-zoom-src`), `src/components/home/ShortlistV23.jsx`.
- Home: the Shortlist is the WHOLE tab in the tab's order (For You ranked or soonest, Tonight `today`, Weekend `weekend`), narrowed by Home's filters. `total` = before the filters. The rail stays the tab's picks. With v2.3 the Browse grid moves under the Shortlist (`HomeShellV5` prop `shortlist`), and the By type sections are not shown.
- End card actions are real only: Show all N (clear filters), Browse every type (opens the category sheet until phase b's Browse screen), Open the map (`goMapExplore` with Home's filters). "Notify me" from the prototype is NOT built (no backend: follow_alerts and push are off). "New tables open on Thursdays" was dropped because it is not true.
- Tour targets kept: `home-filter-summary` (the "31 events · picked for you" line, opens Filters), `home-filters-button` (the Filters chip with the badge), `home-browse`, `home-hero-*`.
- Found: with `simple_shell` on and dark mode, the content under the hero inherits the body's light-theme ink, so the Browse labels are dark on dark. This also happens with the switch OFF. Fixed only under v2.3 (`HomeShellV5` root gets `color: var(--bb-fg)` when the Shortlist is present). The switch-off bug is left as it is.
- Checks: `npm run test:unit` 984/984. `vite build` green. `tests/public/home-v23-pager.spec.js` 4/4 (mocked; the demo catalogue is merged into Home, so the For You total is not fixed). `tests/public/home-hero.spec.js` 2/2 (switch off). Visual: a Playwright script against real production data (guest, read-only, only `get_feature_flags` answered locally) at 390×844 in light and dark. For You 31 events, 8 pages, numbers windowed to 5. Weekend 10 events, 3 pages, a "mid" end card on the last page. Tonight was empty at 23:40 venue time (the shared `today` filter drops started events, same as the rail). Console clean.
- Not done in a: the Browse strip restyle and the See all card (phase b), the live line (phase c).

## Phase b · Browse by type / See all (2026-11-13, IMPLEMENTED LOCALLY)
- One screen `browse` for both. Routes (`src/lib/routes.js`): `/browse[/<type>]` = the whole catalogue, `/see-all/<foryou|tonight|weekend>[/<type>]` = one Home tab. `pathToRoute` opens it through `openBrowse({ type, scope, keep: true })`, so browser back/forward into the same list keeps its search and filters. Opening from Home always starts fresh. Tests: `tests/unit/routesBrowse.test.mjs`.
- Guests may browse it (`GUEST_BROWSE_SCREENS` gains 'browse', `guestAccess.test.mjs` updated). Host profiles were already guest-allowed (`GUEST_ALLOWED_SCREENS` has organizerProfile).
- State (BanBeContext): `browseType`, `browseScope`, `browseQuery`, `browseFilters`, plus `openBrowse`, `setBrowse`, `backFromBrowse`. This is public browsing state like `homeFilters`, so it is deliberately NOT in `PRIVATE_STATE_KEYS` / `signedOutState()`.
- **Built by Home:** `SCREENS.browse = BrowseScreen = () => <Home browse />` (`src/screens/Home.jsx`). Home runs its normal hooks and returns `<Browse>` early, so the list reads the very same discovery items, tab lists (`tabItems`, shared with the Shortlist) and filter function as Home (no second filter path, note 50). Like any Home mount, opening Browse refetches Home's public data.
- View `src/screens/Browse.jsx`:
  - sticky nav: Back, title, magnifier (left of Map), Map
  - kicker + title, host deck, "N events · area"
  - type chips with counts (scope-local, All first, then biggest)
  - "N events" + its own Filters with a badge
  - Pager with `hints`, end card from `browseEnd`
- Search: the magnifier swaps the title for a native `<input type="search" enterkeyhint="done">` (no drawn keyboard). Enter/Done keeps the query as the list's filter and the nav title reads “jazz” · Music. × (the same button while searching) or Escape clears it. Matching is accent-insensitive over title, host, area and type (`matchesQuery`, reusing `foldText` from `mapDiscovery.js`).
- Filters: `HomeFilterSheet` gains `browseMode` + `title` ("Filter Music"). When, Price and Seats only (no For You, Location, Category, Sort). Counts are over that list (type + search). `browseFilters()` always clears `cats` / `typeFilters`.
- Host deck `src/components/browse/HostDeck.jsx`: four overlapping faces, then +N, "X, Y and N more hosts". It turns over every 3.2 s unless Reduced motion or the page is hidden.
  - Faces are the hosts' real photos: the discovery query now also selects `organizers.avatar_path` (anon-readable since 185) → `organizerAvatarUrl` on each real event.
  - Fallback is a monogram on `--bb-clay` / `--bb-update` / `--bb-honey` / `--bb-plum` with the letter in `--bb-bg`, readable in both themes.
  - **Gotcha:** catalogue events that share a key with a real row (bepnho, jazzgac …) are the static `EVENTS` entries merged with the live row and carry no organizer id. Browse reads the host from `realEventsById[key]` instead. Hosts without an organizer id (pure demo events) are left out of the deck.
- Host list `src/screens/sheets/HostListSheet.jsx`: searchable by name, "N events here". A tap runs `openOrganizerProfile(id, 'browse')` → the real `/org/<id>`. Its Back (`organizerProfileBack`) and Event Detail's Back (`eventBackScreen`, label "List") both return to Browse.
- Swipe signs (Pager `hints`, CSS in the component):
  - right edge tab pulses, a hop when the next page is the last (`data-last`), quieter left tab after page 1
  - "Swipe to see more ⟶" fades after the first turn (`data-gone`)
  - a one-time peek 650 ms after a multi-page list opens
  - Reduced: tabs and the cue line stay, nothing moves
- Rows: `EventRowV23`. Its kicker now uses the type's own name from `eventTypeProfiles.json` (the catalogue's raw "NHẠC ▪ SUPPER CLUB" label showed in English mode).
- Home under v2.3:
  - The rail shows at most 4 frames, then `SeeAllFanCard` ("See all 31"), which plays the Welcome fan entrance (side photos from their edges, middle rises, tab chip rises and glows gold once) each time it comes into view (IntersectionObserver), still under Reduced. A tap opens `/see-all/<tab>`.
  - The Browse strip is titled "Browse by type", with "See all N" (whole catalogue) and type tiles → `/browse/<type>`. "Find a type" also opens Browse.
  - The Shortlist end card "Browse every type" opens `/browse`.
- End cards (`browseEnd`): filters hide some → Show all N; search → Clear search (+ Search every type); all types → Host a night (opens the dock "+" sheet, which handles guests) + Open the map; one type → the next biggest types + All types. No "Notify me". "this week" wording dropped (the catalogue spans 3 weeks).
- Map from Browse: `goMapExplore({ source: 'browse', filters: Browse's filters + the type })`. **Limitation:** the Map's Back (`backFromMapExplore`) still goes to Home, not back to Browse.
- No dock on Browse (`BAR_SCREENS` unchanged).
- Hard-coded colours, deliberately: the fan card's gold (#CC9E29, the same constant as Welcome's For You chip) and white text on the dark hero card, as the existing rail cards do.
- Checks: `npm run test:unit` 991/991. `vite build` green. `tests/public/browse-v23.spec.js` 7/7 (deep link + Back, See all + back/forward, deck +2 → host list search → `/org/<id>` → back, search Done/×, own Filters + badge + count, swipe signs, reduced motion deck still). `home-v23-pager` 4/4, `home-hero` 2/2. Visual on real production data (guest, read-only, switch answered locally), light + dark, 390×844, console clean:
  - rail of 4 then the fan card "See all 31"
  - /browse/music: 8 events, 2 pages, 6 hosts shown as 4 faces + "+2"
  - host search "gac" → Gác (real photo) → `/org/org_jazzgac` → back to `/browse/music`
  - "jazz" → 1 event with the search end card

## Phase c · Live line (2026-11-13, IMPLEMENTED LOCALLY)
- Where: under the guest banner / hero banners, above the Shortlist (inside the v2.3 `shortlist` slot in `HomeShellV5`). Only with v2.3. The legacy `PulseTicker` (switch off, non-shell Home) is untouched.
- **Data, real only** (`src/lib/liveLine.js`, `liveUpdates`):
  - First, a summary from Home's own tabs: "N events on tonight", else "N events this weekend".
  - Then today's Banbe Pulse (`goc_pulse_ranked('daily')`, already loaded for guests too), only for events Home lists (every update can be opened), max 8. Each is one of:
    - "Only N seats left at X" (real fill, N ≤ 5)
    - "N bookings for X today" (Pulse `booking_count`)
    - "X by Host is getting attention" (the host is dropped when named like the event)
  - Each update's small label is WHEN THE EVENT IS (its start badge).
- **What the prototype faked and is NOT built:** per-update times ("2 min ago") and people's names ("Linh took 2 tickets"). Neither exists in the data. "Live" means the ticker is running, not a server push.
- "Down to N seats" was reworded to "Only N seats left": bepnho has capacity 3 and no bookings, so "down to" would claim bookings that never happened.
- `src/components/home/LiveLine.jsx`:
  - Full motion: a seamless marquee (two copies, `translateX(-50%)`), duration by text length (`liveSeconds`), the moving text `aria-hidden`.
  - Live / Paused button (44 px, `aria-pressed`, "Pause live updates" / "Resume live updates") pauses it (WCAG 2.2.2), and hover / keyboard focus on the line pause it too.
  - Reduced motion: one whole update at a time with its when, `aria-live="polite"`, ‹ n/N › (44 px) steps by a 200 ms dissolve, nothing changes on its own.
  - The update index lives in Home so the sheet can mark it.
- `src/screens/sheets/LiveNowSheet.jsx` "Live now":
  - Every update in line order, the first with a red dot. In Reduced the shown one is marked "showing on Home". Event rows have Open ›.
  - History: opening pushes one same-URL entry, so browser Back closes it. A tap-close pops it.
  - Open REPLACES that entry before navigating, because an async `history.back()` could land after `goEvent` and undo it.
- Tests: `tests/unit/liveLine.test.mjs` (4). `tests/public/home-live-line.spec.js` 4/4 (switch off none; ticker two copies + Live/Paused → `animation-play-state: paused` and back; Live now → browser Back closes, Open → `/event/…`; reduced one-at-a-time, nothing moves in 2.5 s, next → 2/N, sheet marks it).
- Visual on real data (light, dark, reduced), console clean. Example line: "10 events this weekend · Only 3 seats left at Bếp Nhỏ №12 · Compound: Sân Thượng by Compound Garment is getting attention · Only 1 seat left at Fanci: Đêm Thử Đồ …".
- **Found (existing, not changed):** catalogue events that share a key with a real row (bepnho, fanci, bandai …) show their start in the BROWSER's zone, because Home treats them as demo items with no `tz`. Real-only rows (aeie-2, the group F events) use the venue zone. In a CET browser Bếp Nhỏ shows 13:00 instead of 19:00 venue time. Viewers in Vietnam see the right time. This affects Home cards, the Shortlist, Browse and the live line alike.

## Phase d · Event Detail: the prototype's layout, stub, bar and motion (2026-11-13/14, IMPLEMENTED LOCALLY)
The first pass only changed the stub and the bar inside the V8 page. The owner looked at the screenshots and asked for the Event Detail to mirror v2.3's design AND motion, so the second pass (2026-11-14) gives it the prototype's whole page. The first pass's `TicketStub` `v23` prop was removed again (TicketStub is back to HEAD).
- `v23` in `EventDetail.jsx` = `simple_shell && home_v23`. With it on (and not in the create preview), `EventDetail` returns `src/components/event/EventDetailV23View.jsx`: same data, same refs, same zoom / pull-down / return-position / tab-spy logic. The create preview and switch off keep the V8 page (the V8 path is unchanged apart from shared JSX moved into consts: `shareConfirmEl`, `includedSheetEl`, `menuItemsEl`, `criteriaEl`, `afterHostEl`).
- **Look** (`src/components/event/v23Style.js`, all CSS scoped under `.bbv23`): the prototype's serif (Iowan / Palatino / Georgia, system faces, no download) for the hero title, the date numeral, the prices and the 01 02 03; Liquid-Glass nav and bar (`rgba(--bb-bg-rgb, .84)` + blur 30, glass line/shadow with a dark twin; Reduce Transparency's `--bb-rt-bar` / `--bb-rt-blur` make them opaque). Colours are the app tokens only.
- **Page** (top to bottom): 392 px hero (photo 140 % tall, vignette + shade, monogram plate when there is no photo, category / age / invite pills, serif 40 px title); the ticket stub `TicketStubV23.jsx` riding 22 px over it (cream calendar page behind one hairline, time, honey countdown, place · distance with Directions, perforation with page-colour notches, the price band = tear-off strip `event-price-strip` with the seat pill, perforation, "Save the date" row `event-stub-lip` with two chips); then sections with small-caps headings and hairlines: Good to know as a label / value list (`knowRows` in `src/lib/eventDetailV23.js`: alcohol, all dietary choices in one row, age, the type's facts, Refund when paid and open), About (3 lines, Read more / Read less with a turning chevron, More › for the sheet), the included items numbered 01 02 03, Hosted by as one plain row with Message, photos 196×142, the protected-booking steps.
- **Chrome**: over the photo only one glass Back (44 px). Past 140 px (`navOn`) the glass nav slides down with Back, the title, Save, Share, ⋯ (the same menu), text tabs with an underline, and a clay reading-progress line. The nav covers the status-bar zone itself, so its top is `V23_TOP` (safe area + 6 px), not the V8 fixed 66 px band. `sectionTops` measures the nav with offsets (they ignore its slide-in transform).
- **Calendar chips** (`EventPlanButtons chips`, replaces the first pass's `row`): "banbe" (bell; moss with a check once added, pops) and "Calendar" (the .ics / Google menu), 30 px pills in 44 px hit areas. The stub has no overflow clip so these menus can open out of it.
- **Bar** `ReserveBarV23.jsx`, floating glass, only for bar state 'reserve' (every other state shows its single action in the same floating pill):
  - Compact on arrival: one pill row, the 1 · 2 · 3 · 4+ chips in a tinted track with ONE sliding ink, then a plain Reserve. No total in the compact bar (prototype 2.3.2).
  - Past 40 px: the full card (chips, guest dots + line when 4+, serif total + "per ticket" / "Total · 2 × 850.000₫", Reserve, trust line). Back at ≤ 24 px compact again (`nextCompact`). The height morphs (280 ms spring) and the contents fade in.
  - 4+ turns its own slot into − N + (ink hands over to the slot); in the compact bar 1 · 2 · 3 fold away. Cap `maxQty(remaining)`. 3 or fewer seats: 4+ quiet, a tap shakes it and a toast says "Only 3 tickets left for this one" (floats above the bar, so the bar keeps its height).
  - Chips are 44 px tall (the prototype's 34 px is below the 44 px rule).
- **Motion**: card photo zooms into the hero (the existing zoom, now onto the v2.3 hero), page fades in, the stub rises (520 ms spring, 380 ms in), the bar slides up (460 ms spring), sections reveal on scroll 40 ms after they enter (IntersectionObserver on the scroller), hero parallax 0.2× + slow scale, the title sinks and fades (`--dp`), number roll and total bob on quantity changes, press scales. A return visit (`bbv23-noent`) and OS Reduce Motion skip every entrance; Reduced also drops the parallax and the title sink.
- **Contrast**: the prototype's shade is kept, but its lower band is held at ≥ 0.7 black so the white title keeps 4.5:1 on a white photo (HERO_SCRIM's floor).
- Measured on real data (390×844): compact bar 70 px, full 172 px (195 px with the guest line), Back / nav buttons / stepper buttons / chips all ≥ 44 px. jazzgac and bepnho, light and dark, console clean; opening from a Home card zooms and rises as in the prototype; nav Back returns Home.
- Tests: `tests/public/event-detail-v23.spec.js` 5/5 on Chromium, Firefox and WebKit (switch off V8; strip + lip, compact (no total) → full past 40 → compact at 0, ≤ 21 %; totals, 4+ stepper, dots, cap 6, back to chips, 44 px; 3 seats refusal; NEW: serif title, nav hand-off at 140, Back hides, progress, tab jump, 44 px nav buttons). `tests/unit/eventDetailV23.test.mjs` new. `npm run test:unit` 1003/1003. `vite build` green.
- **Failing specs: NOT caused by v2.3**:
  - `tests/public/home-hero.spec.js` (2) and `tests/public/signin-morph-tour.spec.js` (1) depend on the time of day (checked on a clean HEAD worktree in the first pass). Home merges the built-in demo catalogue, whose "today" events make Tonight non-empty once the venue day rolls over.
  - `tests/event-detail-compact.spec.js` and `tests/event-detail-tabs.spec.js` time out on the guest Welcome / onboarding preview (note 80) before reaching Event Detail (stale setup, checked on clean HEAD).
  - `tests/public-profile-card.spec.js` (2) stalls in the same onboarding helper (`helpers.js:94`) on the profile page, which this work does not touch. Not re-run on a clean HEAD.
- HEAD moved to `6e3d0aa` during this work (the owner's v2.4 prototype commits). Phases a–e were committed on top on 2026-11-14 and pushed to main and to branch `v23-web-2026-11-14`.

## Phase e · Stamps and adding tickets after a hold (2026-11-14, IMPLEMENTED LOCALLY; migration 219 APPLIED TO PRODUCTION 2026-11-14 20:47 UTC, see the production log)
- **Bookings state** (`BanBeContext`): the booking loader now fetches ALL of the signed-in user's bookings on the open event (`myEventBookings`, newest first; `booking` stays the newest). A successful hold is prepended. Event Detail merges `s.booking` (freshest copy) into that list.
- **Rules** (`src/lib/reserveBarV23.js`, unit-tested): `holdsSeat` mirrors the server's `booking_holds_seat()`; `bookedQty` sums seat-holding qty; `stampState` = null / `held` (earliest open deadline: `hold_expires_at` while holding = phase 'hold', `verify_due_at` while pending verification = phase 'verify') / `confirmed` (every seat-holding booking is a ticket; a confirmed booking plus a newer hold reads Held); `stampText` "Held · 25 min" / "Held · 1 h" / "Confirmed"; `addControl` (never below what you hold, max = min(6, held + seats free)); `heldCopy`; `addGuestLine` "4 held · adding 1 · up to 6".
- **Stamp** (`TicketStubV23` `stamp` + `stampPlay`): takes the seat pill's place on the price strip. Held = honey with a clock, Confirmed = moss with a check, and the strip tints moss. It slams in (rotate -16° scale 1.9 → -6°, 520 ms), the stub gives 2 px under it, and a confirmation sends one sheen across the strip. Reduce Motion: a fade. It plays once per CHANGE (module map `stampSeen` per event: null → held on the return from Reserve, held → confirmed on the next booking refresh), never on a plain open. From further down, the page scrolls the stub back into view first (460 ms). The held time left refreshes every 30 s. The stamp has a paper fill (a departure from the prototype's transparent stamp): moss on the moss-tinted strip was 4.18:1 in light; on the paper fill it is 5.78:1 (honey 5.21:1, dark ≥ 9:1).
- **Stub while holding**: the price shows the total for the seats held, "1.700.000₫ · 2 tickets".
- **Held bar** (`ReserveBarV23` `booked`/`confirmed`/`phase`/`onHeld`/`onAdd`), whenever the viewer holds seats on an open event:
  - At what they hold: "Seats held" with a check (opens the booking that still needs something, the newest open hold) or "View your ticket" once confirmed; trust line says what is happening ("held while you pay" / "the host has 1 hour" / "your QR is ready", moss).
  - Above it: "+850.000₫", "1 more · 3 in all" (honey), "Add 1 ticket", trust "A new booking · the host confirms it too". Chips below what they hold are disabled; the stepper's − stops at what they hold.
  - Add → `goReserveAdd(booked, extra)`: Reserve in "add tickets" mode (`reserveAdding`): title "Add tickets", a note that this is a new booking with its own hold and host confirmation, no row pre-filled with the buyer's name or profile birthday (every ticket gets a date picker and an optional email), stepper max 6 − held, button "Hold 1 more seat ▪︎ 30 min". It creates a SECOND booking through `hold_seats_with_attendees` (no migration needed for that).
- **Migration 219** `supabase/migrations/20261231000219_219_per_person_cap.sql` (rollback `supabase/rollbacks/20261231000219_219_revert_per_person_cap.sql`), **APPLIED 2026-11-14** (production log below):
  - Built from the LIVE production bodies (read-only `pg_get_functiondef`, 2026-11-14; md5-identical to the throwaway stack's).
  - `hold_seats()`: one added block after the criteria check: `PER_PERSON_LIMIT` when the caller's seat-holding qty on the event + p_qty > 6 (the event row lock serialises it). Applies to everyone, the host's own bookings included.
  - `claim_seats()`: found to be a full legacy insert again (162 rewrote it: no payment state, no hold timer, no seat rule, no cap), executable by PUBLIC. Now a thin wrapper around `hold_seats()`; EXECUTE revoked from PUBLIC/anon, kept for authenticated. No client calls it.
  - Tests `supabase/tests/219_per_person_cap/run.sh` on the throwaway stack: 17/17 (4+2 allowed, 7th refused, other people unaffected, the attendee path refused past 6, lapsed / cancelled holds free the allowance, pending verification and confirmed count, a single 7 refused, SOLD_OUT unchanged, timed holds unchanged, claim_seats holds like hold_seats and inherits the cap, anon denied, rollback restores, applies twice).
  - The client maps `PER_PERSON_LIMIT` to a message in `submitReserve`. The server now enforces the 6 cap across bookings too.
- **Two bookings on one event, checked**: Confirmed and its stub pager show ONE booking at a time (`s.booking`, its own attendees). The held bar opens the booking that needs action; the other one is reachable from Account › Payments (lists every booking). Not built: one ticket screen that pages across both bookings.
- Tests: `tests/public/event-detail-v23-held.spec.js` 5/5 (held stamp + total held + Seats held; adding copy and Reserve's add mode; holding 5 → stops at 6 with the reason; held → confirmed slams in moss + View your ticket; cancelled booking = no stamp). Both v2.3 detail specs 30/30 on Chromium, Firefox and WebKit. `npm run test:unit` 1006/1006. `vite build` green. Public suite on Chromium: 44 passed, the same 3 known failures (sign-in tour time of day, the two profile-card onboarding stalls).
- Not verified: a real successful hold against production after 219 (only refusals were checked there; the allowed path was proven on the throwaway stack). iOS has no PER_PERSON_LIMIT message yet (it shows its generic hold error).

## Follow-up 2026-11-14 · Next up, pager signs, cover zoom, end cards, host profile (IMPLEMENTED, committed 2026-11-14)
- **Next up** (`src/components/home/NextUpV23.jsx`, rules `src/lib/nextUp.js`, tests `tests/unit/nextUp.test.mjs`, `tests/public/home-nextup-v23.spec.js`), from the owner's mock-up: a ticket card per upcoming EVENT (photo, date badge, countdown chip, type · area, name, perforation with pressed notches, Starts / Tickets / Status, the main button + Directions). Built from the bookings Home already loads (no new query; booked events Home hasn't loaded are fetched with `loadRealEventsById`). For people with several tickets (patterns from Ticketmaster/DICE grouping a party, Apple Wallet's stack, Airbnb's upcoming trips):
  - one card per event, people counted across bookings ("3 people" + "2 bookings");
  - soonest first, swipeable with the next card peeking, "1 of 3" and dots;
  - the button follows what the event needs: Show ticket (all confirmed), Pay now (a hold runs, "Payment due · 20 min left"), View status (host confirming); a mixed event says "1 ready" + "2 waiting";
  - Starts shows the start with "to 22:30" or "(+1)" after midnight, or "open-ended" (note 82). The chip: Happening now / Tonight / Today / Tomorrow / In N days in the venue's zone. Gifted, cancelled and lapsed bookings and events past their end (or start + 12 h) are left out.
  - Replaces the 24 h reminder banner while home_v23 is on (the banner still shows when there are no upcoming tickets). "Doors" in the mock-up is "Starts" (there is no doors data).
- **Pager swipe signs** (`Pager.jsx`): the right tab nudges ONCE, the first time this browser ever opens a list with hints (`localStorage banbe.v23.pagerNudgeSeen`); both tabs darken while the list is swiped (`data-swiping`) and fade back; tabs are 18 px wide (were 28) so they stay clear of the prices; the pages no longer lean/bounce at the edge and the "last page" hop is gone. The tabs are below 44 px wide on purpose (the page numbers under the list stay the 44 px way to turn pages). Lists now remember their page for the session (`savedPages`), so coming back from an event lands on the same page.
- **Cover expand / collapse**: rows mark their thumbnail `data-zoom-photo` and `zoomOrigin.js` measures that, so the hero grows out of the thumbnail and shrinks back into it on close (Home Shortlist, Browse, profile rows, Next up photo). Root cause of "no zoom": the origin was the whole 390 px row, and in dev React's double effect run measured the hero mid-zoom and restarted it from full size; running animations are now cancelled before measuring. Closing after scrolling far down fades instead of flying in from off screen.
- **End and empty cards** (`EndCard.jsx`): the prototype's `.endCard`: dashed paper card with a faint honey glow, three clay dots that bob twice, eyebrow, serif line, body, centred actions (first primary); rises in; slim/mid variants as in the prototype. The Shortlist and Browse empty states now use the same card (testids kept via `action.testId`).
- **Host profile** (`src/components/profile/OrganizerProfileV23.jsx`, behind home_v23): the prototype's profile: centred face with a clay ring that springs in, serif name, role line, tags (areas of upcoming events, "N coming up"), stats block, two actions (Follow for a visitor or a guest, Edit profile for the owner; Share beside it), About (+ long intro and links), Coming up as v2.3 rows, Past collapsed, Photos. The rarer actions (QR code, Team, Copy link) moved into a ⋯ menu next to Share at the top right. Also fixed on the old layout: upcoming/past rows showed no photo (they read `e.img`; the shape has `photoUrl`).
- Tests: unit 1013/1013; `browse-v23.spec.js` 9/9 (new: one-time nudge + swipe darkening, slim tab, dashed end/empty card); `home-nextup-v23.spec.js` 1/1; public suite on Chromium 44 passed + the same 3 known failures. Checked on real data at 390×844 in light and dark (Next up with injected bookings only; nothing written).

## Follow-up 2026-11-14 (2) · Cover collapse as an overlay, profile back route (IMPLEMENTED, committed 2026-11-14)
- **Collapse**: closing an event now switches back to the previous screen AT ONCE and flies a copy of the cover, fixed
  on top of everything, from the hero to the card it came from (`flyBack` in `src/lib/zoomOrigin.js`). The card is found
  again in the returned screen (visible `[data-zoom-src=<key>]` nearest to where it was tapped, its `[data-zoom-photo]`)
  and hidden until the cover lands; then the copy fades. The returned screen's CSS entrance animations are held off
  (`html[data-zoom-return]`) until the NEXT screen change (App `noteScreenChange`, a layout effect), because removing
  them earlier restarts them (seen as a late 6 px push-in on Browse). Works on Home, Browse and the host profile. Scrolled
  far down or Reduce Motion: the old shrink-and-fade.
- **Event → host profile → event → Back** now returns to the PROFILE (it used to jump to Home: the anti-loop rule kept
  the old back target). One-step memory `profileEventReturn`: the profile's Back then returns to the FIRST event with
  that event's own back target; reopening the same profile from an event that came from it keeps the memory, so
  profile ↔ event never loops. Walked on real data: /event/vaicu → /org → /event/giayin → Back /org (the cover lands in
  the profile's row) → Back /event/vaicu → Back /browse.
- Tests: `browse-v23.spec.js` "flies the cover back" (overlay present while the list is already back, no late shift).

## Follow-up 2026-11-14 (3) · About without the sheet, the create preview on the v2.3 page (IMPLEMENTED, committed 2026-11-14)
- The "More ›" links on About and on the included heading (they opened the About & Included sheet) are gone: the page
  already shows the included items numbered with their detail lines, and the one thing only the sheet had, the host's
  longer introduction (their font and colour, note 69), now opens inline under "Read more" (`event-intro-section`).
- The create-event **Public preview** now renders the v2.3 page too (it kept the V8 page before): same hero, stub (with
  the end time, note 82), sections and nav; every guest control is shown but inert (Save, Share, ⋯, Directions, the
  host row, photos, the calendar chips as static pills since a draft is not a real event); at the bottom the compact
  reserve bar guests will see (inert) sits above the host's own footer ("Preview: this is exactly what guests will see"
  + Confirm & submit). Back returns to the Private tab. Checked by filling the form (dev state + 3 photos), Review,
  Public: "19:00 – 22:30", intro under Read more, no More links, Reserve inert, Back → Private.
- Test: `event-detail-v23.spec.js` 6/6 (new: no More link, intro under Read more).

## Facts checked on production (read-only, 2026-11-13)
- Migrations applied up to 217, except 182–184 (held back on purpose). 167 hourly `goc_mark_past_events` is live: it ends `live` events with `starts_at < now() - 12h`.
- `seats_remaining` always equals `capacity` (never decremented, note 50). Availability is `get_public_event_fill`.
- **Seeded events had `starts_at` = the wall-clock time stored as UTC (7 h late).** Migration 195's rule is `starts_at = (event_date + event_time) AT TIME ZONE tz`. The group A+B script writes the correct value.
- Triggers on `events` status changes: `events_queue_follow_alerts` is gated by `app_flag('follow_alerts')` (off), and `rewards_trg_event_status` refreshes host badges when leaving `ended` (count unchanged, 4 → 4).
- `banrieng` is `visibility='invite'` (note 21), so guests do not see it. That is intentional and was left as is.

## Production log

### 2026-11-13 · backup
- `supabase db dump --linked --data-only` and the schema dump to `~/banbe-backups/2026-11-13-pre-v23-testdata/` (chmod 700/600): `data.sql` sha256 `684d3e39fea458e1…`, `schema.sql` `2f716b7451b7b41a…`.
- Row exports: `events.json`, `organizers.json` (all rows, taken before any change).

### 2026-11-13 15:35 UTC · groups A+B applied (owner yes in chat)
- Script: `supabase/drafts/v23-testdata/group-ab-revive.sql` (ends in ROLLBACK = dry run; applied as a copy ending in COMMIT). Run with `supabase db query --linked -f`.
- Rollback: `supabase/rollbacks/v23_testdata_group_ab_rollback.sql` (exact old `event_date`, `starts_at`, `status` per id, generated from `events.json`).
- Dry run first (rolled back, verified nothing persisted), then applied. The same diff printed both times.
- Changed: only `event_date`, `starts_at`, `status` on 18 rows. No bookings, refunds, disputes, chats, attendees or photos touched. No DELETE.

| grp | key | before (venue time) | after (venue time) |
|---|---|---|---|
| A | modular | ended · Mon 10 Aug 04:30 | live · Fri 13 Nov 21:30 |
| A | phokhuya | ended · Thu 20 Aug 06:00 | live · Fri 13 Nov 23:00 |
| A | compound | ended · Mon 21 Sep 00:00 | live · Sat 14 Nov 17:00 |
| B | vungtrang | ended · Fri 02 Oct 01:00 | live · Sat 14 Nov 18:00 |
| B | vuonsau | ended · Sat 12 Sep 01:00 | live · Sat 14 Nov 18:00 |
| A | orbit | ended · Mon 07 Sep 03:00 | live · Sat 14 Nov 20:00 |
| A | bangcoi | ended · Sat 17 Oct 03:00 | live · Sat 14 Nov 20:00 |
| A | chieucham | ended · Fri 09 Oct 22:00 | live · Sun 15 Nov 15:00 |
| A | khongnguoi | ended · Fri 06 Nov 00:00 | live · Sun 15 Nov 17:00 |
| A | jazzgac | ended · Mon 21 Sep 04:00 | live · Sun 15 Nov 21:00 |
| A | fanci | ended · Thu 24 Sep 02:00 | live · Mon 16 Nov 19:00 |
| A | motlop | ended · Tue 29 Sep 02:30 | live · Tue 17 Nov 19:30 |
| B | pianomuon | ended · Sat 05 Sep 05:00 | live · Wed 18 Nov 22:00 |
| B | noigiay | ended · Thu 29 Oct 02:00 | live · Thu 19 Nov 19:00 |
| B | bepnho | ended · Thu 05 Nov 02:00 | live · Sat 21 Nov 19:00 |
| A | banrieng | ended · Fri 02 Oct 02:30 | live · Sat 21 Nov 19:30 |
| A | phong302 | live · Mon 23 Nov 22:00 | live · Sun 22 Nov 15:00 |
| A | comnha | live · Mon 23 Nov 02:30 | live · Mon 23 Nov 19:30 |

- After: 18 live (17 public), 2 cancelled (bandai, sonmai), 2 ended (aeie, test-s-ki-n-8444c8). `get_public_event_fill` sample: bepnho 0/3, fanci 0/1, vungtrang 1/41, noigiay 2/20 (old confirmed test tickets now count as upcoming).
- Group B note: the confirmed test tickets on vungtrang (1) and noigiay (2) show as upcoming again for those test accounts.
- Tonight decays: phokhuya and modular are "Tonight" only on 2026-11-13. Group F should add evening events across the coming days so Tonight keeps items.

### 2026-11-13 15:41 UTC · group C applied (owner chose the recommendations, then said yes)
- Script: `supabase/drafts/v23-testdata/group-c-revive-clone.sql` (dry run, ROLLBACK). Applied as a copy ending in COMMIT.
- Rollback: `supabase/rollbacks/v23_testdata_group_c_rollback.sql`. It restores bandai exactly, and deletes the two clones and their photo rows ONLY if no bookings, dispute threads, refund send requests, favorites or threads hang off them. Otherwise it refuses, and the clones must go through admin removal (note 54).
- First two dry runs failed on NOT NULL text columns (`withdrawal_reason`, `removal_reason`). The clones now keep the source's values for those columns.

| key | what | before | after |
|---|---|---|---|
| test-s-ki-n-8444c8 | (b) left as it is | ended | ended (untouched: 5 refund claims, 6 closed disputes) |
| bandai | (a) row revived (no bookings, `cancelled_at` was never set) | cancelled · Sun 15 Nov 02:00 (wrong UTC) | live · Wed 18 Nov 19:00 |
| aeie-2 | (c) clone of aeie, same host/details, 4 photo rows reusing the same storage paths | (new) | live · Fri 20 Nov 16:00 |
| sonmai-2 | (c) clone of sonmai, same host/details, 4 photo rows reusing the same storage paths | (new) | live · Tue 24 Nov 18:30 |

- aeie stays ended (with its refund claim), sonmai stays cancelled (with its cancelled bookings). Neither original was touched.
- After: 24 events (21 live), 94 event_photos rows. Anon sees bandai, aeie-2 and sonmai-2, plus the clones' photos.
- Cleanup caveat: the clones share storage files with aeie/sonmai. `scripts/cleanup-orphaned-media.mjs` or a photo delete on one row must not remove a file still referenced by the other.

### Found 2026-11-13: dated intros
- All 22 original events have the OLD date written into `intro` (e.g. aeie "Thứ 2, 9 tháng 11 lúc …"), from `scripts/backfill-event-intros.mjs`. Fixed by group D with date-free intros.

### 2026-11-13 15:45 UTC · group D applied (owner yes in chat)
- Content source: `supabase/drafts/v23-testdata/group-d-content.json`. Generated script: `group-d-content.sql` (dry run, ROLLBACK), applied as a COMMIT copy.
- Rollback: `supabase/rollbacks/v23_testdata_group_d_rollback.sql` (exact old description, intro, included_items, details per event, and Gác's about). Pre-change rows also saved to `~/banbe-backups/2026-11-13-pre-v23-testdata/pre-group-d-live-content.json`.
- Changed on the 21 live events:
  - `description`: 59–118 → 255–297 characters, VI only. Seat counts were removed from the text (bandai, bepnho, banrieng and comnha contradicted their capacity).
  - `intro`: date-free, two short paragraphs. 0 intros contain a date afterwards.
  - `included_items`: same labels and order, each gains a short `detail`.
  - `details`: merged (`||`), never replaced. `alcohol_note` on 11 events, `dietary_note` on 6 supper clubs. All passed the `validate_event_details` CHECK.
- `organizers.about` for Gác (`org_jazzgac`): '' → 141 characters.
- Not touched: prices, seats, dates, photos, bookings, the legacy `included` text column. `chat_greeting_en` was already set on every event. The test event's coordinates were skipped (it was left as is in group C).
- Checked after: anon read of bepnho/jazzgac returns the new intro, description and alcohol_note.

### 2026-11-13 15:51 UTC · group E applied (owner yes in chat)
- Script: `supabase/drafts/v23-testdata/group-e-avatars.mjs` (`dry` = SQL rolled back and no upload, `apply`, `rollback`). Images: `supabase/drafts/v23-testdata/avatars/<organizer id>.jpg` (512 px square JPEG).
- Selection: all 64 own-event photos of the 16 hosts without a photo were viewed. Most are street photos of real people and were rejected. Crops were taken only from people-free images. Dropped: crops with shop lettering, rail-company branding (DSCF4423), a K-pop poster with a face (noigiay collage), political flags (DSCF5780).
- Uploaded to bucket `organizer-photos` at `org_<id>/v23-avatar-20261113.jpg` (no upsert, cache 1 year). Then `organizers.avatar_path` '' → that path, only where it was '' and `avatar_r2_ref` was NULL.
- Set (10): org_aeie (rooftops, DSCF4864), org_bandai (apples, DSCF6107), org_bepnho (watermelon, DSCF6107), org_sonmai (crates, DSCF6107), org_fanci (white rooftop, DSCF5973), org_modular (white wall, DSCF5973), org_jazzgac (red dot, DSCF6022), org_orbit (window view, DSCF6022), org_motlop (bicycles, DSCF5586), org_noigiay (wooden door, DSCF2539).
- Left on the monogram fallback (6): comnha, khongnguoi, pianomuon, vungtrang, bangcoi, phong302.
- Rollback: `node supabase/drafts/v23-testdata/group-e-avatars.mjs rollback`. It sets those 10 paths back to '' (only if still ours) and deletes the 10 uploaded objects.
- Checked after: all 10 public URLs return 200, and anon reads the new `avatar_path`.
- Three hosts share one source photo (fruit stall), so the host deck can look related when they sit together.

### 2026-11-13 15:59 UTC · group F applied (owner yes in chat)
- Content: `supabase/drafts/v23-testdata/group-f-events.json`. Generator: `group-f-generate.mjs`, which writes `group-f-events.sql` (dry run, ROLLBACK) and the rollback. Applied as a COMMIT copy.
- Rollback: `supabase/rollbacks/v23_testdata_group_f_rollback.sql`. It deletes the 12 events and their photo rows ONLY while no bookings, dispute threads, refund send requests, favorites, threads or check-ins hang off them. Otherwise it refuses (use admin removal, note 54). It also restores the organizer name "Test".
- 12 new live public events, all owned by the test admin's organizer `org_a96236c5`. Each copies a same-type template's structural columns (bepnho, jazzgac, orbit, vungtrang, and orbit for pop-up) with all content new. Photos are 3 per event, reusing existing `event-photos` paths (no uploads).
  - vaicu (fashion, Sat 14 Nov 14:00), giayin (gallery, Sun 15 Nov 16:00, free)
  - canhchua (supper, Wed 25 Nov), dembass (music, Thu 26 Nov 22:00), aodaimoi (fashion, Fri 27 Nov)
  - chophien (pop-up, Sat 28 Nov 16:00, free, first pop-up event), bunchay (supper, Sat 28 Nov)
  - saxsang (music, Sun 29 Nov 10:00), tranhtoi (music, Mon 30 Nov), gomxanh (gallery, Tue 1 Dec)
  - phimcu (gallery, Wed 2 Dec), maydo (fashion, Thu 3 Dec)
- Organizer `org_a96236c5` renamed "Test" → "Nhà Chung". This also shows on the old test event with refunds and disputes.

### Phase 0 result (inventory re-run 2026-11-13 after group F)
- 36 events: 33 live (32 public, banrieng is invite-only), 1 cancelled (sonmai), 2 ended (aeie, test-s-ki-n-8444c8).
- Public live per type: fashion 8, gallery 8, music 8, supper 7, pop-up 1. Each of the four main types has 6 hosts, so the host deck shows 4 faces then "+2".
- At least one live event every day from 13 Nov to 3 Dec, so Tonight keeps items. Weekend 14–15 Nov has 10 events.
- Nhà Chung hosts 12 live events. `goc_pulse_ranked('daily')` returns 21 items (all live events with photos, one per host).
- Phase 0 complete. These dates will pass: after 3 Dec the test data needs another revive.

### 2026-11-13 16:31 UTC · migration 218 applied (owner yes in chat)
- Method (note 61): one-file workdir = production's applied set + 218 (182–184 left out on purpose), in the scratchpad. `supabase db push --workdir <dir> --linked --include-all --dry-run` listed exactly `20261231000218_218_home_v23_switch.sql`, then the same push without `--dry-run`.
- Verified: `app_feature_flags` home_v23 = false, defs row added_in 218. `supabase migration list --linked` shows 218 local = remote. Anon `get_feature_flags` returns `home_v23: false` (simple_shell true). Nobody sees v2.3 until an admin turns it on in Account > Admin > Feature switches > App layout.
- Rollback: `supabase/rollbacks/20261231000218_218_revert_home_v23_switch.sql` (two DELETEs, and clients treat a missing key as off).

### 2026-11-14 20:47 UTC · migration 219 applied (owner yes in chat: "Apply 219")
- Before: `supabase migration list --linked` showed 219 local only (182–184 still held back on purpose). Live `hold_seats` / `claim_seats` bodies re-read: md5 identical to the ones 219 and its rollback were built from (5137de86…, 919cb7cc…).
- Backup: `~/banbe-backups/2026-11-14-pre-219/` (chmod 700): `schema.sql` (sha256 2f716b7451b7b41a…, same as the 2026-11-13 schema dump: 218 was data only) plus the two live function bodies.
- Method (note 61): workdir in the scratchpad = every migration except 182–184. `supabase db push --workdir <dir> --linked --include-all --dry-run` listed exactly `20261231000219_219_per_person_cap.sql`, then the same push without `--dry-run`.
- Verified on production:
  - migration list: 219 local = remote.
  - `hold_seats` body contains PER_PERSON_LIMIT; `claim_seats` is the wrapper (`RETURN public.hold_seats`); `hold_seats_with_attendees` unchanged.
  - `claim_seats` EXECUTE grantees now authenticated, postgres, service_role (PUBLIC gone).
  - In a rolled-back transaction as the test admin host (org_a96236c5's owner): `hold_seats('vaicu', 7)` → `PER_PERSON_LIMIT` (raised before any insert or sequence use). As anon: `claim_seats` → `permission denied`. Bookings on vaicu created in the last 15 minutes: 0.
- Rollback: `supabase/rollbacks/20261231000219_219_revert_per_person_cap.sql` (restores both bodies verbatim and claim_seats' PUBLIC grant).

### Pending
- UI phases a–f (plan in `~/.claude/plans/ethereal-crunching-tulip.md`). Migration 218 (`home_v23` switch) and 219 (per-person cap) to be written, NOT applied without a yes.

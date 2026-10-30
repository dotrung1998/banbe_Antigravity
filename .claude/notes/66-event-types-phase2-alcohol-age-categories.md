# 66 — Event types phase 2: all five types, alcohol & minimum age, per-type recipe, Home category row + Show all

Phase 1 is note 65. Status: IMPLEMENTED (web + iOS), committed locally, NOT pushed. Migration 204 APPLIED TO
PRODUCTION 2026-10-30 together with the backfill (log below). Switch `event_type_profiles` was already ON in
production, turned on by someone else before this pass. It was left untouched.

## Owner decisions (2026-10-30)
- Alcohol and minimum age are REQUIRED for all five types.
  - alcohol: none / included / paid / byo.
  - min age: 16 / 18 / 21. There is no "all ages", because the platform minimum is 16.
- The recipe is per type: its own ingredient list and denominator.
- The "Book again" shelf is deferred and not built.

## What each type has (`src/data/eventTypeProfiles.json`, version 2)
- **Shared block:** a `common` block (alcohol, min_age) is merged into every type, both as fields and as
  required.
  - Web: `withCommon` in `eventTypes.js`. iOS: `EventTypes.all`.
- **Per type** (required beyond the base fields, then optional; card line):

| Type | Required | Optional | Card line |
|---|---|---|---|
| supper | included ("On the menu") | dietary, dress_code | "Bàn N người · first dietary · alcohol · age" |
| music | lineup (list ≤6) | genre (multi), format (seated / standing / mixed); Included optional ("Ticket includes") | format · genre · age |
| gallery | artists (list ≤8) | medium (multi); Included optional ("Entry includes") | medium · "N nghệ sĩ" · age |
| fashion | brands (list ≤8) | experience (show / fitting / sale / talk), price_range (budget / mid / premium) | — |
| popup | brands | entry_mode (drop_in / timed), price_range | — |

- **New field kind `list`:** names kept in order, trimmed, blanks and repeats dropped, each ≤60 characters.
  - Card lines show a list's count (`countLabel`) or its first item.
  - Choices can carry a `short` label, used on cards.
- **Removed:** 203's supper `byo` field is gone, folded into `alcohol = byo`. No event had it.
- **Search:** detail option labels (VI + EN), list items and text join the search document.
  - Web: `detailSearchTerms` in `search.js`. iOS: `SearchMatch.buildDoc`.
- **Bundled catalogue events:** catalogue-keyed events (all 24 seeded ones) now show their real row's facts.
  `capacity` and `details` travel through the live-status overlay:
  - web `loadHomeLiveEvents`, `liveEventOverrides`, the single-event fetch;
  - iOS `LiveEventStatus`, `applyingLiveStatus`, both fetches.
  - iOS Event Detail falls back to the Home overlay until its own row arrives.

## Create form
- **Progress:** `FIELD_ORDER` gains `lineup`, `artists`, `brands`, `alcohol`, `min_age`. Every detail id is anchored
  in Basics (createFieldGuide on both platforms).
  - Required facts feed the ring, steps left, Still needed chips and the Review gate.
  - `DEFAULT_REQUIRED` is the original 10 (unknown types are unchanged).
- **Included** is required only where the type says so.
- **Editors:** each type field is its own `Guided` / `guided(id)` anchor, so a Still-needed chip lands on it.
  - Lists have add/remove rows.
  - Errors show after a Review attempt.

## Recipe (`eventRecipe.js` ⇄ `EventRecipe.swift`)
- **Signature:** `recipeChecks(draft, bench, goal, now, profile)`. The profile's `recipe.ingredients` picks the
  checks and is the denominator.
- **New check `facts`:** missing until the required type fields are in; improve while optional ones are empty; fix
  lands on the first empty field.
- **Data rule:** a check stays for a type when at least half of that type's current events use it. Counts on
  2026-10-30 (production, live or ended):

| Type | Events | Organizers | Included | Greeting |
|---|---|---|---|---|
| fashion | 5 | 5 | 5 | 5 |
| gallery | 4 | 4 | 4 | 4 |
| music | 5 | 5 | 5 | 5 |
| supper | 6 | 6 | 5 | 6 |

  - So supper, music, gallery and fashion = all 10 + facts (11).
  - Popup has no events: no included / seats / greeting checks, so title, photos, description, keywords, price,
    timing, lead, facts (8).
- **Benchmarks:** they stay per category through `get_host_benchmarks(p_cat_key)`, with its k-limits unchanged.
  Gallery (4 events) is under the 5-event floor, so it gets labelled tips (`source: 'tip'`).
- **No ranking claims** anywhere.

## Home category row + Show all (web + iOS)
- **Logic:** `categoryCounts(items, filters, keys)` returns what tapping each category would show. It uses the same
  `applyDiscoveryFilters` / `apply` as the feed, with type chips dropped (picking a category clears them) and every
  other filter kept, area included through the feed.
- **Row:** All first, then categories with events, most first. A selected empty one stays.
- **Sheet:** every category A–Z by its folded label in the current language. Zero ones are dimmed; picking one
  applies it and closes the sheet.
- **Layout:** the row is tighter (48pt tiles, 2pt gaps, labels wrap, Dynamic Type safe up to accessibility2). Music
  is no longer clipped.
- **Ids:** existing ids kept: `home-category-<key>` (web), `filter.<key>` (iOS).
  - New: `home-category-count-<key>`, `home-category-show-all`, `home-category-sheet[-<key>|-close]`;
    iOS `home.categoryCount.<key>`, `home.category.showAll`, `home.categorySheet.<key>`.
  - The iOS sheet uses `.hidesDock`.
- **e2e caution:** a category with no events in the area is no longer in the row, so an e2e that taps a category
  with no events must use Show all.

## Terms (A10, content key `event_types`)
- **Text:** A10 "Alcohol and minimum age" covers what hosts declare, that the platform minimum is 16, and that hosts
  are responsible for accuracy and for not serving alcohol under 18. Guests book only if they meet the age, hosts
  may check ID, and banbe removes false declarations when reported.
- **Where:** web `Policy.jsx` ⇄ iOS `PolicyView`, shown only while `event_type_profiles` is on
  (`contentFlags` `event_types`). Parity is tested in `ContentFlagsTests.testPolicyAlcoholAgeTextMatchesTheWeb`.
- **Not done:** no policy version bump and no re-consent, as instructed.
- **Open question:** the Terms' own A8 says changes "affecting your rights" need renewed agreement. A10 adds host
  duties and an age expectation for guests. Whether that counts is a legal call for the owner.

## Migration 204 + rollback
- **What it changes:** only `event_details_fields` and `event_details_value_ok`, plus new helpers
  `event_details_multi_ok` and `event_details_list_ok`. The 203 CHECK and `set_event_details` pick them up.
- **Guard:** refuses to run if any event still has `details.byo`.
- **Rollback:** `supabase/rollbacks/…204_revert…`. It clears phase-2 details first.
- **Local suite 28:** extended (byo gone, no all-ages, list trim / distinct / length / count, music facts on a music
  event).
- **All local suites** ALL PASS on a fresh container: 197 migrations.

## Backfill (`scripts/backfill-event-details.mjs`)
- **Input:** a production row snapshot.
- **Output:** a dry-run list, plus with `--sql` ONE transaction. For each event it acts as that event's own host
  (`request.jwt.claim.sub`) and calls `set_event_details(new || existing)`.
- **Safety:** existing values always win, and a re-run is a no-op.
- **Values:** hand-read from each seeded event's title, description and included items (alcohol from "rượu / vang /
  cocktail / welcome drink", age 18 with alcohol); lists use sample names where the text gives none.
- **Local rehearsal:** the 24 events copied into a container. Run 1 set=24; run 2 set=0 unchanged=24; a pre-set
  `alcohol=paid` was kept.

## Production log (UTC, 2026-10-30)
- **Snapshot (read-only):** 24 events, all test data, every one with a host. By type: fashion 5, gallery 5, music 5,
  supper 9, popup 0. All `details` were {}.
- **Switches before:** admin_event_wipe=true, event_reminders=true, event_type_profiles=true, onboarding_v3=true,
  all others false.
- **Backup:** `supabase db dump --linked` (schema + data-only) to `~/banbe-backups/2026-10-30-pre-204/`.
  - schema SHA-256 prefix 9871aaf8d649f978, data 78b7fe2443ad23b1; mode 600, outside the repo, personal data.
- **Pre-check:** production 203 functions present, CHECK present, 0 events with details.
- **15:52:31 — 204 applied alone:** one-file workdir = applied set without 182–184 (deliberately never pushed,
  note 58) + 204. The dry run listed only 204.
  - Verified: music/supper field lists; `byo` and `min_age:"0"` rejected; music facts accepted; anon cannot execute
    `set_event_details`; 204 recorded.
- **15:52:50 — backfill run (one transaction).** Verified:
  - 24/24 events have details, and 24/24 have alcohol + min_age.
  - music 5/5 lineup, gallery 5/5 artists, fashion 5/5 brands.
  - Cơm Nhà Mai: vegetarian / no alcohol / 16+ / "Thoải mái".
  - AEIE: Mở Xưởng: AEIE / show / premium / none / 16+.
- **Switches after:** identical to before.

## Known limits
- **Pop-up has no event anywhere** (catalogue or production): Pop-up chips and its sheet row stay at 0 (dimmed).
- **Home counts only live, upcoming events:**
  - Music has none live, so it shows 0 in the area unless a demo catalogue event is upcoming.
  - Fashion has only AEIE live, so only `experience:show` and `price_range:premium` are non-zero.
  - Gallery (2 live) covers photography, painting, print and lacquer.
- **Not pushed:** the new client code isn't deployed, so production web still runs phase 1 against the new data. The
  supper card/filter keys that phase-1 clients know (dietary) still work; `byo` chips show 0.
- **e2e:** not run (real production accounts).

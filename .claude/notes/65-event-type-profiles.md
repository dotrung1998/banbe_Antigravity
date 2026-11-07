# 65 — Event type profiles (create form, Event Detail, Home adapt to the kind of event)

Status: IMPLEMENTED (web + iOS, commit d00e6b0). Migration 203 APPLIED to production (by another session, found
applied 2026-10-30) and switch `event_type_profiles` is ON there. Phase 2 (all five types, alcohol + minimum age,
per-type recipe, Home category row + Show all, migration 204, production backfill) is note 66, which supersedes the
supper `byo` field and the fixed "Recipe N/10" described below.

## Owner decisions (2026-10-27)
- The first picked category is the PRIMARY type and the only one that shapes anything. A second pick stays a
  discovery tag, saved as a keyword as before. There are no merge rules.
- Supper club is the pilot. Music, Gallery, Fashion and Pop-up have identity only (label, icon, aliases, keyword seeds).
- The type picker stays in Basics.
- New types (workshop, tasting, market…) were evaluated only; adding them is a later decision.

## What the code did before (verified, the brief's screenshots were partly wrong)
- Only `createCats[0]` is saved (`events.category/cat_key`, plain text, no CHECK). There is no categories array.
- Ring %, "N steps left", "Still needed here" and the Review summary were 4 hand-kept lists per platform. iOS never
  required a valid price. Fixed by `createProgress`.
- Recipe N/10 never affects ranking (no SQL, Home sort or For You reads it). Its copy makes no ranking claim.
- "+ 5 mon / + binh thanh" keyword suggestions did not exist. Only benchmark keywords existed, and nothing showed on
  a cold start.
- Pop-up had no search aliases on either platform.

## Shape
- **ONE data file:** `src/data/eventTypeProfiles.json`.
  - Web imports it.
  - iOS bundles the same file (`apps/ios/project.yml` resource, so run `xcodegen generate` after pulling).
  - Fields: identity, aliases, keywordSeeds, wizard (required, includedTitle/Placeholder, details), detailFields
    (multi | enum | text), detail.facts, card.line, home.filters.
  - A type without wizard/detail/card/home behaves exactly like today.
- **Logic:** `src/lib/eventTypes.js` ⇄ `Lib/EventTypes.swift` (clean, detailFacts, cardLine, homeFilters/typeFilter,
  matches, keywordSuggestions, droppedDetailTypes, searchAliases, categoryDefs).
  - Every scattered category list now derives from it: create, Home, prefs/emoji, search.
  - Map still has its own 4-key list, because Pop-up has no Map dot colour yet.
- **Progress:** `src/lib/createProgress.js` ⇄ `Lib/CreateProgress.swift`. One result drives the ring, the steps
  left, per-step gaps, the Review summary and Review-with-gaps. "Still needed" items are tappable chips calling the
  existing `guideTo`.
- **Data:** migration 203.
  - Adds `events.details jsonb` ({} or {"v":1,…}).
  - The CHECK validates against every type's fields, so a category change never fails.
  - `set_event_details` is the only writer: owner or admin, current type's fields only. Called after
    create/resubmit like `set_event_keywords`, and only while the switch is on.
  - Field list per type: `event_details_fields()`. Keep it in step with the JSON; suite 28 checks it.
- **Drafts:** `createDetails` is kept PER TYPE, so switching category loses nothing. Review warns when another type's
  answers won't be published.
  - Web: `DRAFT_FIELDS`.
  - iOS: `HostEventDraft.details`/`kwDismissed`, optional so old drafts decode.
- **Home:** `typeFilters` is a new discovery dimension (counts, badge, "relax" hint `type`). The chip row shows only
  with exactly one category picked, and picking a category clears it. Real events get a card line ("Bàn 8 người ·
  Có món chay · BYO").
- **Read path:** `details` is added to event selects with the same "column may not exist yet" retry as tz/currency.
  - Web: `detailsColumnList` in `mediaUrls.js`.
  - iOS: `EventDetailsColumns`.
- **Analytics:** `create_event_type_selected{type}` and `create_event_still_needed_tapped{field}`. The fixture,
  web, iOS and 203 all agree.
- **Admin:** new category "Event types" in Feature switches, key `types` (lowercase: the parity test's regex).

## Also in this pass (no switch)
- Dock clearance is derived from the dock constants: web `DOCK_CLEARANCE` in App.jsx, iOS
  `BottomTabBar.contentClearance`. Same values as before.
- The overlap in the owner's screenshot is the floating dock mid-scroll, which is by design. The last card was
  already reachable.
- iOS Home chips, category labels and filter pills now scale with Dynamic Type (`@ScaledMetric`, capped).
- Web capsules use minHeight, and category labels can wrap.

## Tests
- **Shared fixtures:** `tests/fixtures/create-progress.json` and `tests/fixtures/event-types.json` (incl. discovery
  type-filter vectors and search aliases).
- **Web:** `tests/unit/createProgress.test.mjs`, `tests/unit/eventTypes.test.mjs`.
- **iOS:** `CreateProgressTests`, `EventTypesTests`, plus UI `EventTypesUITests`. The UI tests use
  `-uiFixtureEventTypes YES` and screenshot Basics fields, a still-needed chip landing on its field, Review facts and
  the public preview.
- **SQL:** `supabase/_localtest/28_event_details_assert.sql`, wired into `retention_suites_run.sh`. All suites
  passed on a private container, and the rollback applied cleanly.
- **Pre-existing, unrelated failure:** `GiftTicketPDFTests.testPDFLinksPointAtRealDestinations`. It still forbids
  banbe.app links after the note-41 domain switch.

## Not done / next
- Phase 2: Music (lineup, genre, seated/standing, age), Gallery, Fashion, Pop-up. Each needs JSON entries plus a new
  migration extending `event_details_fields`/`event_details_value_ok`.
- Detail option labels are not yet in the search document; only the aliases are.
- No web e2e run: the specs use real accounts on production.
- Owner questions:
  - Alcohol/age as required fields (policy version bump, note 09)?
  - Confirm the Supper Home chips.
  - "Book again" shelf (recommended deferring).
  - Fixed 10 recipe items per type?

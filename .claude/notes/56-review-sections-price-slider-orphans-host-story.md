# 56 — Review sections, draggable price slider, Manage events rows + orphaned events, host pages in "How banbe works"

Status: IMPLEMENTED LOCALLY (web + iOS), not committed. No migration.
- iOS is checked through `ReviewRetentionUITests` (new cases below) and their screenshots.
- Web passes its unit tests and build, but is unchecked by eye: these screens need a signed-in host or admin (note 49).

Source: the owner's 3 screenshots and 4 requests (2026-10-21). Plan: `~/.claude/plans/calm-booping-hanrahan.md`.

## 1. Review › Private tab
- The header ends with a 12pt gap and a hairline (`palette.rule`, web `borderBottom`). Scrolling content starts 18pt
  below it and never runs into the tab capsule.
- Small uppercase section headings via `reviewHeading`: Event name / Recipe for success / Event details / Included /
  Photo order. There are 26pt gaps between sections.
- The recipe card's first line is now just "x/10 · never required to submit".
- iOS bug fixed: the fields and Included cards applied `.padding(.top, …)` before `.background`, which put the gap
  INSIDE the card. The fields card touched the recipe card with 0pt between them. The outer padding now sits outside
  the background.
- Identifiers: `create.reviewName`, `create.reviewDetails`; web `create-review-details`.

## 2. Price slider (Tickets step, needs host benchmarks)
- Domain is `bench.price.min…max`, snapped to 10,000₫.
  - Helpers: `priceToFraction` / `fractionToPrice` / `PRICE_SLIDER_STEP` in `src/lib/eventRecipe.js`, and
    `EventRecipe.priceToFraction` / `fractionToPrice` in Swift.
  - A market narrower than one step keeps the raw value. Typed prices outside the domain pin the knob to the edge.
- Visual:
  - A clay knob with a ‹ › grip, a value bubble while dragging, and bars up to the price filled in clay.
  - The caption "‹ Kéo để chọn giá ›" / "‹ Drag to set your price ›".
  - With no price yet, the knob rests dimmed on the median.
- Web: a single native `<input type=range class="bb-range bb-price">` under the bars. Bars and marker are inset by half
  a knob, so the marker sits on the thumb's centre. It works by keyboard and with `aria-valuetext`.
- iOS (`PriceMarketView`, `Views/RecipeSheet.swift`):
  - Dragging works on the knob row only, so a vertical swipe over the bars still scrolls the page. Tapping a bar jumps
    the price there.
  - `Haptics.selection()` fires when the price crosses p25, the median or p75.
  - VoiceOver uses an adjustable action in ±10k steps.
  - Identifier: `create.priceSlider`.
- Quick picks, the typed field and the slider all write `createPrice`.

## 3. Manage events
- **Orphaned events** (host account deleted).
  - Finding: the list query never excluded them, but nothing marked them, and a `.limit(200)` cut off older rows.
  - Rule (`isOrphanEvent` / `AdminManagedEvents.isOrphan`): an event is orphaned when any of these holds:
    - `organizer_id` is null;
    - the organizer row is missing;
    - the organizer has neither `owner_id` nor `user_id` (profiles cascade SET NULL);
    - the organizer's name is "Deleted organizer" (`api/_lib/organizerCleanup.js`).
  - The "Host đã xoá" / "Host deleted" filter chip works on the client: it loads all events and keeps the orphans.
  - Badge: "Host account deleted".
  - Orphans are selectable like any row.
  - Owner decision: removal stays blocked while money is in play. The blocker reads "the host account was deleted;
    banbe must contact the guests to settle refunds first".
- **Loading.** 500-row pages via `.range()` until a short page comes back, with a hard cap of 5,000.
  - `needsAnotherPage` is in both libs.
  - Ordering: `starts_at desc nulls last`, then `id`. iOS now also sorts nulls last.
  - Extra columns: `created_at, submitted_at, price_vnd, capacity, seats_remaining, area`, plus the organizer's
    `owner_id, user_id`.
- **Rows.** The circle selects (keeps `adminManage.row.<id>` / web `admin-manage-select-<id>`); the rest of the row
  expands. Expand all / Collapse all; rows start collapsed.
  - Details: host and account state, start, price, seats, area, created/submitted, bookings (active/ever),
    refunds/disputes, removed-at, and ID.
  - Actions:
    - "Review now" for `review` events. It opens Pending Events with that event expanded (iOS
      `openAdminEvents(focusID:)` / `adminEventsFocusID`; web `openAdminEvents(id)` / `adminEventsFocusId`).
    - "View event page" for live, ended and cancelled events.
    - "Copy ID".
- **iOS fixture.** It adds `fx-ev-review`, `fx-ev-orphan-refund` (cancelled, 1 unsettled refund, so blocked) and
  `fx-ev-orphan-draft`.
- No migration is needed. `events_select_admin` already shows every row, and the 189 RPCs skip the notification when
  there is no owner.

## 4. "How banbe works" (public Welcome story)
- The story now has 4 pages: For You, Hold a seat, then **Host your own events** and **Create an event in 5 steps**.
- The copy comes from `src/data/help/host.js` (free hosting, guests pay the host directly) and the submit screen
  (banbe reviews before going live).
- Web: the `pages`, `STORY_EMOJI` and `STORY_TILE_BG` arrays.
- iOS: `WelcomeView.storyPages` / `storyTileBackground`, and `PublicStoryState.pageCount = 4`. `PublicEntryTests` and
  `PublicEntryScheduleUITests` ("1 of 4") were updated.

## Tests
- **Web:** `npm run test:unit` is 337/337.
  - `adminEvents.test.mjs` covers orphans, the orphan blocker wording and paging.
  - `eventRecipe.test.mjs` covers the slider maths.
- **Web:** `npm run build` passes.
- **iOS unit:** `AdminOrphanPriceSliderTests`.
- **iOS UI** (`ReviewRetentionUITests`):
  - `testPriceSliderDrags`
  - `testManageEventsOrphansAndExpand`
  - `testReviewPrivateTabHasSections`
  - `testHowBanbeWorksHasHostPages`

## Follow-up (2026-10-22): story pages as emoji lists
- Owner: the 4 pages had too much text. Each page now has a short title and 3 emoji point rows instead of a paragraph.
  - iOS: `StoryPageContent` / `StoryPointsView`.
  - Web: `pages[].points`.
- Entrance plays once per page: the emoji tile pops (scale + slight tilt), then the rows rise in 80 ms apart.
  - iOS: spring 0.42s.
  - Web: `.bb-story-pop` / `.bb-story-rise`.
  - Reduce Motion gets a plain fade (iOS) or no animation (web).
- Page 2's title is now "Giữ chỗ trong vài chạm" / "Hold a seat in a few taps". Its "30 minutes" point matches note 01.
- Checked in the simulator (`testHowBanbeWorksHasHostPages` screenshots). Not checked on a device.

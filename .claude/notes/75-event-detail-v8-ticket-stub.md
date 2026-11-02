# 75 — Event Detail V8: ticket stub, tabs, 1·2·3 presets back, host-written notes (web + iOS)

Status: IMPLEMENTED (web + iOS), committed on `main` 2026-11-02, NOT pushed. Migration 209 is applied on the local
harness only, NOT on production. Plan: `~/.claude/plans/pasted-content-id-8996-plan-mode-warm-sedgewick.md`.

**This note supersedes two note-70 decisions:**
- the one-row bar under 12% of the screen;
- the removal of the 1·2·3 presets.

The owner made both non-negotiable (2026-11-02).

## Owner decisions (2026-11-02)
1. **Host-written sub-lines.** `alcohol_note` and `dietary_note`, optional, 1–120 characters. Without a note there is no sub-line.
2. **No menu icons.** There is no data for them.
3. **"Bring a photo ID".** A host-set option, `id_required = 'yes'`. Without it, the age row has no sub-line.
4. **Protection step 2 wording:** "The host has 1 hour to confirm; banbe reminds them" / "Chủ nhà có 1 giờ để xác nhận; banbe sẽ nhắc nếu chậm".
   - Note 02: there is no auto-confirm, only reminders.
5. **Seat chip wording:** "Còn N vé" / "N tickets left". "of M" and the thin booked bar are gone.
6. **Date block month:** VI "THG 11", EN "NOV".
7. **Free events:** the chips show only "1 vé / 2 vé / 3 vé", with no price.
8. **Protection section and tab** are hidden for these bar states: ended, endedAttended, cancelled, ticket, pending.

## Layout
**Hero.** Unchanged: 320 high, with the pills and title on the photo. The title band is shorter by `STUB_RISE` / `stubRise` = 104.

**Ticket stub.** Web `src/components/event/TicketStub.jsx`; iOS `ticketStub` with the `TicketStubHalf` shape. It is two halves, each with notches at the perforation.
- Web cuts the notches with radial masks; iOS uses `Path.subtracting`.
- Colours: `surface1` for the stub, `surface2` for the place row, a dashed clay perforation, and a hairline plus drop shadow.

**Top of the stub:** the date block, then the time and countdown, then the place row.
- Date block: clay, from `dateBlock(when-text)`. It never uses `startDate`, because of note 70's seeded offset.
- Countdown: `daysUntilInZone`. It counts in the VENUE zone and is hidden for ended or cancelled events.
- Place row: the area, then the distance if it is ≤ 50 km, else "Area · {cities.json short name}", then an ink "Directions" pill (44pt).

**Bottom of the stub:** price "/ vé" and the seat pill. The pill colours per state are unchanged.

**Sheet, in order:**
1. Overview: who can reserve, then "Good to know" rows (`needToKnowRows`), then About.
2. Menu cards: up to 3, label over detail.
3. Host card with an outlined "Message" pill.
4. Photos at 242×172.
5. Protected booking, 4 steps.

Section headings are small caps.

**Bar.** Preset chips `event-qty-1..3` ⇄ `event.qty.1..3` sit over the stepper and CTA, then the trust line.
- One `qty` drives both: qty 1–3 lights its chip, 4 and up lights none.
- A chip above `maxQty(remaining)` is disabled.
- `event.actionBar` stays on the CTA only.

**Tabs:** Overview / Menu / Host / Photos / Protection.
- **When they show:** only in the collapsed nav bar, and only for sections with content (`visibleTabs`).
- **Which one is active:** `activeTab` in `eventDetailTabs.js` ⇄ `EventDetailTabs.swift`. Sections that can't scroll to the top get thresholds spread over the remaining scroll, and the bottom of the page always selects the last tab.
- **Tapping a tab:** the tab stays selected while the page scrolls to it. The lock ends on the reader's own scroll or touch (web `wheel`/`touchstart`/`pointerdown`, iOS the probe's user-driven flag), or after 1.1 s.
- **Collapsed controls:** back / ⋯ / share / save are 44pt hit areas with no gaps.

**iOS scroll offset.** It now comes from `ScaffoldScrollProbe.onScrollMetrics` (KVO) on every iOS version.
- The iOS 17 `PreferenceKey` path and the iOS 18-only `onScrollGeometryChange` are removed.
- Section tops are read through a preference in the content's own coordinate space (`eventContent`), which only changes on layout.
- Tab taps use the new additive `ScaffoldScrollProbe.scrollRequest`.

## Data (what the host enters)
**Existing fields used as they are:** area, city, coordinates, `when`, price, capacity (live fill), alcohol, dietary, min age, dress code, included items `{label, detail}` (max 3), host stats and photos.

**New in migration 209** (`supabase/migrations/20261231000209_209_event_detail_notes.sql`):
- **Keys:**
  - `alcohol_note`: every type;
  - `dietary_note`: supper only;
  - `id_required`: every type.
- **SQL changes:** only `event_details_fields` and `event_details_value_ok` change.
- **Rollback:** `supabase/rollbacks/…209…`.
- **Local test:** harness E7.

**In the profile JSON** (`eventTypeProfiles.json`), the three fields carry `"subline": true`. Because of that flag:
- the recipe's `facts` check ignores them;
- the save drops them and retries while 209 is not applied (`withoutSublines`, web BanBeContext ⇄ `AppState+Data.swift`);
- the retry order is: everything → without sub-lines → first type without sub-lines.

**Create (Basics › Details):** each note shows right under its fact. The ID option shows under min age, and a second tap clears it. Field anchors are in `createFieldGuide`.

## Tests
- **Shared fixtures:**
  - `event-detail-presentation.json` (dateBlock, ticketsLeft, needToKnowRows, menuCards);
  - `event-detail-tabs.json`;
  - `countdown-zone.json`;
  - `reserve-bar-presets.json`.
- **JS:** `npm run test:unit` gives 713/713.
- **iOS unit:**
  - New: `EventDetailTabsTests`, `CountdownZoneTests`, presets in `ReserveBarTests`, V8 in `EventDetailPresentationTests`, `EventTypesCombinedTests.testSublineKeys`.
  - The whole suite passes except `GiftTicketPDFTests.testPDFLinksPointAtRealDestinations`. That test is pre-existing and unrelated: it flags `www.banbe.app` links, which became the real domain in note 41.
- **Web e2e:**
  - `tests/event-detail-compact.spec.js` was rewritten for V8:
    - the stub sits above the bar;
    - the bar is ≤ 21% of 844;
    - chips and stepper stay in sync;
    - the seat chip reads "N tickets left".
  - New `tests/event-detail-tabs.spec.js`.
  - Both pass with `event-detail-intro-included` in Chromium, Firefox and WebKit.
- **iOS UI:** `EventDetailCompactUITests` has three tests: stub/presets, good-to-know/protection, and tabs. All pass.
- **SQL:** `CONTAINER=<throwaway> ./supabase/_localtest/retention_suites_run.sh` gives DETAILS ALL PASS, with all 202 migrations applied.
  - This runner DROPS the public schema. Never point it at `supabase_db_banbe`.
- **Pre-existing failures, unchanged by this work** (checked with these changes stashed):
  - `chat-photo.spec.js` and `story-viewer.spec.js` (note 30);
  - `EventTypesUITests.testLongFieldsExpandClearAndTwoCategories`;
  - `ReserveButtonRegressionUITests`, which stops at login focus.

## Open
- **Applying 209 in production** is the owner's call. Until then, hosts can type notes but the server won't store them; the saves retry without them.
- **Cards and copy:** the Included `detail` placeholder still says "Detail (optional)", and a long detail is clamped to one line on the menu card.
- **Not checked:** VI screenshots; Dynamic Type XXXL on the stub; an iOS 17 runtime drag test of the spy.

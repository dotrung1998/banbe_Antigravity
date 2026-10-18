# 49 — Web parity with the iOS passes of notes 43–48 (2026-10-18)

Status: IMPLEMENTED LOCALLY (web), NOT committed/deployed. Migration 185 is written and tested against a local
Postgres, NOT applied. Scope chosen by the owner: Reports, Onboarding, Schedule + calendar, guest browsing, plus a fix for the organizer bank-column leak (write it, don't apply it).
Note 47 (event zoom, haptics, dock shrink) and note 45's native glass are iOS-only mechanics with no web counterpart. They were not ported.

## 1. Reports (notes 43 + 46)
- `src/lib/reportsPresentation.js` is a 1:1 port of `ReportsPresentation.swift`: role layout, needs-attention rules (`targetKey`: overdue opens the owed claims), breakdowns, meaning lines, symbols, formatting (fixed VI/EN separators, not the browser locale), tolerant timestamp parsing, UTC day buckets, daily average, localized rows.
  - Tests: `tests/unit/reportsPresentation.test.mjs`, 20 tests with the same fixtures and expectations as the iOS tests.
- `src/screens/Reports.jsx` was rewritten:
  - Header with an overflow menu (Refresh / PDF / JSON).
  - Segmented range track; Custom shows two date inputs.
  - Hero card: moss wash, 46px value, meaning line, SVG daily bars with the first peak labelled, and a peak / active days / daily average strip.
  - KPI grid (CSS grid, rows share a height; long values step down a size and never wrap "₫").
  - Needs attention, Breakdown (ring and segmented bar), Trends, and All metrics as one grouped card.
  - Details sheet with localized row cards, CSV, and "Save chart image".
  - Skeleton, stale banner, error and empty states.
- Context: a request-sequence guard (a quick 7→30→90 switch can't land an older response); a failed refresh keeps the data and shows it as stale (`reportsLoadedAt`); `openReportDetail`/`closeReportDetail`.
- **Exports unchanged.** `exportReportCardCsv`/`exportReportsJson`/`exportReportsPdf` were not touched. The chart PNG still comes from the same `MiniChart` canvas, fed the exact legacy range string.
- `tests/account-reports.spec.js` now drives the details sheet and the menu instead of expand/collapse-all.

## 2. Onboarding (note 43)
- `src/lib/onboardingFlow.js` ports `OnboardingFlow.swift`: the reducer, the per-account draft store (localStorage `banbe.onboardingDraft.v1.<uid>`, the server wins), impact lines, and the reveal match set using the same `forYouRankEvents` as Home.
- `src/lib/analytics.js` is a no-op `track()` that records ids, counts and buckets only.
- `src/lib/activationChecklist.js` is the Home "Get started" checklist (open an event, save an event; no Face ID on web).
- Tests: `tests/unit/onboardingFlow.test.mjs`, 21 tests.
- `src/screens/EventOnboarding.jsx`:
  - Welcome → five questions, one per screen ("n of 5", Back, Skip, named steps with a head start).
  - Then saving, an honest save-failed screen (Retry / Edit answers / Skip for now), and the reveal (impacts; loading, offline, zero-match and "all areas" states; the top 3 real events).
  - Then the settings step, unchanged and with promo OFF. Its only change is that it hands off to the flow.
  - `onboardingFlowActive` keeps the overlay up through the reveal after the server markers clear.
  - `finishOnboardingFlow` turns on For You only when there are real matches, switches on the checklist when questions were answered, and opens a tapped event.
- New: `src/screens/ActivationChecklistCard.jsx`, shown on Home under the Action Center. `discoveryEventsLoadFailed` was added.

## 3. Schedule + calendar (notes 44/45)
- `src/lib/schedulePresentation.js`:
  - Sources: booked > awaiting > holding > hosting > added.
  - Gifted-away tickets are honoured only when the row carries `gifted_at`. The web bookings select does NOT load the migration-151 columns, which might not exist in production.
  - Undated events are counted, never silently dropped. Discover, `canAdd`, week (first weekday: Monday for VI, the browser locale for EN), busy days.
  - Month grid and agenda.
  - Proximity: "Starts within 2 hours" unless real end times exist (they never do today).
  - Venue-time note.
  - `scheduleStore`: localStorage `banbe.schedule.added.v1.<uid>`, **this browser only; no sync with iOS or other devices**.
- `src/lib/calendarExport.js`: an honest draft (no start → nothing exported; no end → 2h plus a note saying so), an RFC 5545 .ics (escaped, folded) and a Google Calendar link.
  - The Confirmed screen's existing `addToCalendarGoogle/ICS` now use it. They used to invent "now" as the start when an event had none.
- Tests: `tests/unit/schedule.test.mjs`, 12 tests.
- `src/screens/Schedule.jsx`:
  - Header (wordmark, title, month button, Today).
  - My schedule / Discover segments.
  - Week strip: arrows, or swipe (`data-hscroll`, so it changes the WEEK, not the dock tab).
  - Day agenda: source cards and dashed Discover cards, each with Add to banbe Schedule / Remove (manual adds only) / Add to calendar.
  - Month sheet; error/empty/loading states.
- `src/screens/EventPlanActions.jsx` sits under the event title: In My schedule · source, Add/Remove, Add to calendar.
- **Dock:** Schedule replaces Notifications (still five: Home, Map, Schedule, Messages, Account).
  - Notifications became a pushed screen with Back (`notificationsBack`), reached from the new Home bell (unread badge plus a spoken count), a new Account row and Action Center "See all".
  - The Home header budget (`homeHeaderLayout.js`) now counts the bell and steps the wordmark down 80→70→58 before dropping the title, with no wordmark as a last resort (iOS note 45 order). The layout tests were updated.
  - `dock-interaction.spec.js` and `root-tab-swipe.spec.js` now use `tab-schedule`.
- `paymentBookingsLoadFailed` was added (the loader used to empty silently).

## 4. Guest browsing and public welcome (notes 44 + 48) — reverses note 09's "no guest browsing" on web too
- `src/lib/guestAccess.js`: guest screens = home, mapExplore, event; prompt copy and benefits; `makePrompt` (Reserve and Message resume); `loginBackTarget`. Tests: `tests/unit/guestAccess.test.mjs`, 5 tests.
- `src/screens/Welcome.jsx`:
  - The signed-out landing page after splash, plus language/theme on a first visit.
  - Explore events / Create an account / Already have an account? Log in.
  - An optional two-page "How banbe works" that never auto-advances.
- `src/screens/GuestPromptSheet.jsx`:
  - "Save this event", "Hold your seat"… with Continue (sign up) / Log in / Not now.
  - `GuestBrowseBanner` on Home.
- Routing:
  - `GUEST_ALLOWED_SCREENS` adds welcome/home/mapExplore/event.
  - A signed-out visitor lands on Welcome, not a forced Login; `logout` lands on Welcome.
  - The guard sends personal screens (Schedule, Messages, Account…) to Login with **a real Back** (`authMandatory: false`, back = the last browse screen). Before, Back vanished forever after the first forced gate.
  - `openAuth(mode, from)` / `browseAsGuest` / `promptSignIn` / `continueFromGuestPrompt`.
  - Resume after sign-in goes through sessionStorage `banbe.authResume.v1` (it survives the OAuth reload): Reserve rebuilds attendee drafts; Message re-runs `openChatFor`. Both used to land on a broken screen.
  - Deep links: a guest's `/event/<id>` or `/map` now opens on reaching Welcome/Home (`useUrlSync`); before, it was never applied. `/welcome` route.
- Actions now ask a guest first instead of failing silently or misrouting:
  - **save**: used to flip locally and vanish.
  - **follow** (Pulse, host profile): used to be a silent no-op.
  - **reserve** and **message**.
  - **photo like**: used to open Account under the still-open viewer; it now closes the viewer/Pulse first.
- **Audit-driven fixes (would otherwise leak the previous account to a guest on a shared browser):**
  - One `signedOutState()` resets ~80 per-account keys (bookings, tickets, booking/hold, organizer identity, stories with signed URLs, survey discovery, admin invite, verifications, chats/inbox, refunds, roles…). `realEventsById` keeps only public live/ended/cancelled rows.
  - It runs on logout **and** on `onAuthStateChange` with no session (token expiry, another tab, account deletion), which used to clear only `user`.
- Home for a guest: the banner replaces the Action Center and checklist; the survey row is hidden (authenticated-only RPC; it also showed "Loading…" forever for a guest). Pulse stays (public).
- Verified signed out against real public data: Welcome → Explore → guest Home → Save prompt → Not now → event → Reserve prompt → Log in → Back to the event → Map → Schedule → Login → Back to Map. **Zero console errors or permission denials.**

## 5. Migration 185 — organizers bank-column leak (NOT APPLIED)
`supabase/migrations/20261223000185_185_organizers_anon_public_columns_only.sql`
- **Problem (note 48):** anon holds table-level SELECT on `organizers` and the policy is `USING (true)`, so anyone with the shipped anon key could read every organizer's bank account, MoMo phone, payment QR, tax code, alert phone and owner/user ids.
- **Fix:** `REVOKE SELECT ON organizers FROM anon`, then grant only public profile columns:
  - id, name, verified, organizer_type, hosting_since, about, bio, intro_long, social_links, ig_handle, instagram, avatar_path, avatar_r2_ref.
  - New columns are hidden from anon by default (fail closed).
- **Required companion change, in the same file:** `events_select_public` read `organizers.owner_id/user_id` in a subquery. A naive revoke would make every signed-out events/event_photos read fail. It now calls `public.is_event_host(events.id)`, the identical condition (already SECURITY DEFINER, anon-callable, used by 113's other policies).
- **Verified in a throwaway local Postgres 16** with the real 001/113 policies and Supabase-style grants:
  - Before: anon reads the bank number.
  - Naive revoke: "permission denied for table organizers" on events, photos and embeds.
  - With 185: public event, photo, id/name and events→organizers(name) embed all work; bank and `select *` are denied; host and other-user visibility are unchanged.
- An inventory of every organizers read (web, iOS, api, RPCs) found no anon wildcard select and no anon need beyond those columns.
- **Not changed:** `authenticated` still reads all columns. Guest payment screens read the host's bank/QR this way, which is a product decision.
- **To apply:** `supabase db push`, then run the REST checks at the bottom of the file.

## Verification
- `npm run test:unit`: 278/278 (58 new: reports 20, onboarding 21, schedule 12, guest 5; header layout 5 updated).
- `vite build`: OK.
- Screenshots in a scratch harness: Reports (host EN light, admin VI dark, details sheet, VI tiles), onboarding walk (welcome → question → budget → reveal → settings), Schedule (mine, Discover VI dark, month).
- Real dev server signed out: the guest walk above.
- **Not run:** the Playwright e2e suites. The shared test account is held at the server's date-of-birth gate (same blocker as note 44), so `account-reports.spec.js` cannot get past setup. Clearing it needs a permanent DOB written to a production test account, which needs owner approval.
- **Not verified:** the signed-in paths end to end on a real account (onboarding save, schedule with real bookings, resume after a real sign-in, logout reset). The code paths are the existing RPCs/loaders, but they haven't been exercised live here.

## 6. Mirror of the later iOS passes (note 48 follow-ups), 2026-10-18 afternoon
- **Create event = 5 steps** (`CreateEvent.jsx`): Host / Basics (name, description, intro, opening message, categories with emoji, keywords, Included) / When & where (address search + date/time with 4-across date and 5-across time tiles) / Tickets (price tiles + field + similar-price hint, seats box stepper + tiles, privacy tiles, criteria) / Photos + Review. Sticky numbered `StepProgress` with % + encouraging line, tap a step to jump; Back/Next under every page, "Still needed here" per step, Next never blocks; Review jumps to the first incomplete step. Starts on Basics when the host profile is filled or when editing. Large icon form style: local `FormLabel`/`Icon` (inline SVG set)/`BigField`/`PickTile`/`StepCard`, 16px rounded outlined inputs. **Seats never pre-filled** (`lib/smartDefaults.js`), defaults notice only on steps 3–4 and no longer mentions seats.
- **`StepProgress` (components/ui/FormControls.jsx)** is now the numbered stepper (connector lines, ✓ when done, halo on current, `showBar` prop) — used by Create event, Reserve/Confirmed booking journey, onboarding indicator.
- **Booking journey on Confirmed** (Hold → Pay → Ticket; hidden for expired/disputed).
- **Schedule** (`Schedule.jsx`): whole screen is `data-hscroll` (never a dock swipe). Week strip: left/right = week (month when expanded), down/up = unfold/fold the month inline (grabber toggles too); list area (`touch-action: pan-y`): left/right = day, with a slide-in from the matching side. A capture-phase click guard swallows the click after a swipe, so a swipe never opens an event/selects a day. Mode changes dispatch `bb:section-change`.
- **Dock** (`App.jsx`): back to full size on any section change (screen, `accountTab`, `inboxView`, Schedule mode via `bb:section-change`), with a 600ms scroll-collapse pause.
- **Cute empty states** (`components/ui/EmptyState.jsx`, keyframes in `index.css`, reduced-motion safe): Home feed (ticket·bear·star, See all events + Look on the map), Schedule mine (cup·cat·moon → Discover), Schedule discover (cloud·compass·plane → next day with events, else Open the map). Art = `public/keychains/*.png`.
- Verified: `vite build` OK; `npm run test:unit` 278/278; guest Home empty state screenshotted in a real browser (390×844) with zero console errors. **Not verified visually:** Create event steps and Schedule gestures (both need a signed-in session; the shared test account is still held at the DOB gate).

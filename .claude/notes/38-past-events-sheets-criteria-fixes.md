# 38 — Past events, ended-event handling, criteria-on-demo-ids, X-close sheets (commits f561739, ce9915e, aa17fe8, df3e72e)

Status: IMPLEMENTED (web + iOS), pushed to main. Not device/browser-verified. **Migration 167 NOT APPLIED.**

## Ended events (root cause + fix)
- Events have NO end time. "Ended" = `events.status = 'ended'`, set only by cron `goc_mark_past_events` (migration 008): once a day at 00:05 UTC, for live events started >12h ago. So an event could stay `live` (reservable, tagged "Going") for up to ~36h after it was over.
- Client fix: a `live` real event whose `starts_at` is 12h+ old is treated as ended (`endedHoursAgo` set). iOS `CatalogEvent.fromReal`; web `shapeRealEventAsCurEvent` (BanBeContext.jsx). Keep both in sync with the 12h rule in `EventReminder` (note 37).
- **Migration 167** (`20261214000167_167_hourly_end_past_events.sql`): ends all lapsed events immediately and reschedules the job hourly (`5 * * * *`). Until applied, the SERVER still accepts reservations for a lapsed-but-`live` event; only the client hides/blocks. Apply with `supabase db push`.

## Home feed / host profile
- Ended events never appear in the Home feed (iOS `AppState.feed`, web `Home.jsx` feed). The "Ended" filter chip was removed on both. "Your events" strip (48h expiry), Account > Completed are unchanged.
- Host profile (OrganizerProfile web + iOS) has a collapsed-by-default "Past events" dropdown (count badge, newest first, max 30). One query fetches live+ended (limit 200) and splits client-side: past = `ended` OR live started >12h ago; upcoming = the rest (max 5). State: iOS `organizerProfilePast`, web `organizerProfilePast`.

## Reservation criteria on web (note 34 follow-up)
- Root cause of "web doesn't show/block like iOS": `EventDetail`/`Reserve` passed `isReal: !EVENTS.some(key)`, skipping the criteria load for any id in the static demo catalogue — but `bepnho`/`comnha` are ALSO real DB rows with criteria. The gate is removed; a key with no row resolves to Everyone.
- Web now also has a local fallback `evaluateCriteria(criteria, prefs)` (src/lib/eventPrefs.js, mirrors SQL `event_criteria_check` ANY/ALL) used by `useReservationCriteria` when the server pre-check has no answer. Server answer wins; `hold_seats` stays the authority. The exact reason the server pre-check wasn't blocking on web was never found (no DevTools data) — if it recurs, look for a console warn from `check_my_reservation_eligibility`.
- Event detail web: "Message host" is now a "Contact | Message X ›" row like iOS (test id `organizer-message` kept).

## iOS fixes
- Back label: `AppState.backLabel(for:)` gained `.event` ("Event"), so Event preferences opened from an event says "Event" not "Account".
- Home scroll: `.scrollPosition(id:)` reports the first feed card even at offset 0, so returning to Home jumped past "Your events"/Pulse. `HomeView.homeScrollAnchorBinding` ignores the id anchor when `homeScrollOffsetY <= 1` (left at top), and `retryScrollRestoreIfNeeded` skips too.

## Sheets with an X (share-card style)
- Design: system sheet, grab handle, centred inline title, X on the RIGHT (no Close/Cancel). Applies to: About & Included (iOS + web, also the create-event preview on iOS), Pulse (iOS + web), Share profile card (iOS + web).
- iOS: reusable `CardSheet` in Views/Sheets.swift. In a NavigationStack toolbar use `Button(role: .close)` on iOS 26 (renders the system glass X); fallback = `.ultraThinMaterial` circle. GOTCHA: `Button(role: .close)` OUTSIDE a toolbar renders the word "Close", not an X — Pulse (no nav bar) draws its own 44pt `glassEffect` circle with a 22pt xmark instead, sized by eye to match the system one; not pixel-identical. Exact match would need Pulse's header in a real toolbar (overlays would then sit under the bar).
- `.presentationDragIndicator(.visible)` added to Pulse (RootView) and Share card sheets.
- Web X = 36px frosted circle (`rgba(120,120,128,.16)` + blur + hairline), used in EventDetail About sheet, ProfileShareSheet, PulseViewer.

## Not done / follow-ups
- Migration 167 unapplied (see above). Existing tests mentioning the Ended filter chip or the old Close pill (`share-card-close` kept as test id) were not run.
- Cron job name `goc_mark_past_events` is re-created via `cron.unschedule` + `cron.schedule` in 167; verify it exists before applying.

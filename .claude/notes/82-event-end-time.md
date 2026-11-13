# 82 · When an event ends: end time or open-ended (web)

Status (2026-11-14): IMPLEMENTED (web), committed and pushed to main. Migration 220 and the data for all 36 production events
APPLIED TO PRODUCTION 2026-11-14 21:58 UTC (owner: "Apply both"); see the production log at the end.

## What
- Every event can say when it ends: an end time on the venue's wall clock (like `event_time`; an end at or before the
  start means the next day, e.g. 22:00 → 02:00) or "open-ended". Neither = not stated (rows before 220); the page then
  shows the start time alone, as before.
- Rules: `src/lib/eventEnd.js` (`endMode`, `endsNextDay`, `defaultEndTime` = start + 3 h, `endError`, `timeRange`,
  `durationMinutes`), unit tests `tests/unit/eventEnd.test.mjs`.

## Database (migration 220, `supabase/migrations/20261231000220_220_event_end_time.sql`, APPLIED 2026-11-14)
- `events.end_time time NULL`, `events.end_open boolean NOT NULL DEFAULT false`, CHECK `events_end_one_mode` (never both).
- No RPC change: the create flow writes them with the host's own `events_update_own` update after `create_event_draft` /
  `resubmit_event_for_review`, like `chat_greeting`. Readable through the existing table grants (anon included).
- Only guard triggers fire on a plain events UPDATE (`guard_r2_ref`, `events_guard_removal`); follow alerts, rewards and
  `events_on_ended` fire on status changes only.
- Rollback `supabase/rollbacks/20261231000220_220_revert_event_end_time.sql` (drops the columns).
- Throwaway stack: applies twice, a time and open-ended each save, both at once is refused by the CHECK, the rollback
  removes the columns.
- Migration 167 (end live events 12 h after `starts_at`) is unchanged; it does not read the end time.

## Data for all production events (`supabase/drafts/event-end-data/`, APPLIED 2026-11-14)
- `dry-run.sql` (ends in ROLLBACK) and `apply.sql` (COMMIT): one UPDATE … FROM (VALUES …) over 36 ids, then a count.
  26 get an end time (jazzgac 21:00–00:00, pianomuon 22:00–01:00, phokhuya 23:00–02:00 run past midnight; galleries
  close 19:00–21:30; suppers 21:00–22:30; morning sax 10:00–12:00) and 10 are open-ended (aeie, aeie-2, fanci, orbit,
  khongnguoi, vungtrang, modular, dembass, chophien, bandai). Cancelled and ended rows are included (only the event row
  changes; no payment, refund, dispute or chat row is touched).
- Rollback `supabase/rollbacks/event_end_data_rollback.sql` (back to not stated, which every row was).
- The built-in catalogue (`src/data/events.js` `END`) carries the same values for its 20 keys, so a key shown from either
  source agrees.

## App (web)
- Reading: `endColumnList()` in `src/lib/mediaUrls.js` adds `end_time, end_open` to the real-event select, and
  `withR2Columns` drops them on a missing-column error (so the app works before 220). `shapeRealEvent` → `endTime`,
  `endOpen`.
- Create form (`CreateEvent.jsx`, When & where step, under Date & time): "Ends" with two tiles, "At a set time" (fills
  start + 3 h, a time input and "4h · next day") and "Open-ended". Required (`fieldErrors.end`, counted in the step's
  progress); an end equal to the start is refused. Kept in saved drafts (`DRAFT_FIELDS`), prefilled on edit, shown in
  Review ("21:00 – 01:00 (next day)").
- Save: best-effort update `{ end_time, end_open }` after the create/resubmit RPC; skipped with a dev warning while the
  columns are missing.
- Event Detail (v2.3 stub, note 81): the time line reads "21:00 – 00:00 (next day)", "19:00 · open-ended", or the start
  alone. The start is the real row's venue wall clock (`event_time`), not the browser-zone `when` text, so start and
  end always agree (a catalogue-only event keeps its `when`).

## Not done / open
- The V8 page (switch `home_v23` off) and the create preview still show the start only.
- iOS: no Ends field and no display yet (it ignores the new columns).
- Home cards, the Map, Schedule and calendar exports do not use the end yet (calendar exports keep their own default
  length).

## Production log
### 2026-11-14 21:58 UTC · migration 220 + end-time data applied (owner yes in chat: "Apply both")
- Before: `supabase migration list --linked` showed 220 local only. Backup `~/banbe-backups/2026-11-14-pre-220/` (chmod 700):
  `schema.sql` (sha256 145fe7eb248cef42…) and `events-before.json` (all 36 rows' id, event_time, status). The end columns
  did not exist, so "before" for the data is not stated on every row.
- 220: one-file workdir (every migration except 182–184) in the scratchpad; `--dry-run` listed exactly
  `20261231000220_220_event_end_time.sql`, then the real push. Verified: `end_time` time (no default), `end_open` boolean
  default false; migration list 220 local = remote.
- Data: `dry-run.sql` returned with_end_time 26, open_ended 10, not_stated 0, next_day 3, and left 0 rows changed; then
  `apply.sql` returned the same counts and they persisted (26 / 10 / 0).
- Checks: anon REST reads `end_time`/`end_open` (phokhuya 23:00→02:00, jazzgac 21:00→00:00, bepnho 22:30, bandai open);
  0 notifications created in the 10 minutes around the run; the local web app against production shows
  "21:00 – 00:00 (next day)", "19:00 · open-ended", "23:00 – 02:00 (next day)", "16:00 · open-ended", "10:00 – 12:00".
- Rollbacks: data `supabase/rollbacks/event_end_data_rollback.sql`; schema
  `supabase/rollbacks/20261231000220_220_revert_event_end_time.sql`.


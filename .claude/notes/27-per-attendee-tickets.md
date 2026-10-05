# Per-attendee tickets (migration 151) — 2026-10-05

Buying up to 6 tickets now requires a **name + date of birth per attendee**; each attendee gets their own QR, entry code (`<booking code>-<seat>`) and PDF.

- **DB:** `booking_attendees` (own `admission_token`, `checked_in_at`). RLS: buyer/admin only — hosts get a DOB only through `get_checkin_guest_info()` (rate-limited, logged). `hold_seats_with_attendees(p_event, p_attendees jsonb)` validates, calls the unchanged `hold_seats()` and inserts the rows in one transaction.
- **Check-in:** scanning an attendee token admits that one person (second scan: "already checked in"); booking becomes `attended` on the first. Scanning the *booking-level* id of a named-attendee booking is refused (`Scan each attendee's own QR`); manual list tap admits everyone not yet in. Bookings made before 151 have no attendee rows and behave as before.
- **Gifting is blocked** for named-attendee bookings (trigger `bookings_guard_named_attendees`; UI hides the row). Wallet pass and the single-PDF row are hidden too — they carry the booking-level credential the door now refuses. A Wallet pass per attendee is not built.
- **iOS:** `ReserveView` attendee cards, `ConfirmedView.attendeeTickets` (per-row download, tick several, "Download selected" / "Download all" → one share sheet with N PDFs), `AppState.exportAttendeeTicketPDFs`.
- **NOT done:** web (purchase form, ticket list, PDF); the host's guest list still shows one row per booking (no per-attendee "2 of 3 in"); no age-restriction rule — age is only displayed at the door.
- **Verified:** `supabase/_localtest/11_attendees_assert.sql` (13 assertions incl. host can't read the table directly) and 55/55 iOS unit tests. Not applied to any deployed DB; no device click-through.

## Import into another account (migration 152)
- Each attendee has a `claim_code` (`ATT-…`), carried by THEIR PDF's "Open in banbe" link (`banbe://gift/claim?code=…`) and typeable in the existing import screen. `claim_ticket(code)` dispatches to `claim_attendee_ticket` (ATT-) or the old `claim_gift_ticket` (CLAIM-); the client now calls `claim_ticket`.
- No email was collected per attendee, so the CODE is the proof (like holding the QR). Importer needs a verified email; a code works for one account; repeat import by the same account is idempotent; unpaid/cancelled/ended events are refused (`NOT_PAID_YET` etc.). The booking, payment and refunds stay with the buyer; the QR is unchanged, so the buyer's copy keeps working.
- Importer sees the ticket under Account → Tickets → "Imported tickets" (`get_my_imported_tickets()`, `ImportedTicketView`: QR, code, PDF). Check-in credits the importer's `attended_count` + a notification (trigger; **not covered by the harness**).
- Not done: the buyer's card doesn't yet show "imported by an account" and there's no revoke/re-issue of a code; web.

## Web parity pass (2026-10-06)
Web now has: attendee cards on Reserve (`hold_seats_with_attendees`), per-attendee ticket list on Confirmed (QR, per-ticket PDF, tick several → ZIP, "Download all"), single-ticket "Download PDF" for pre-151 bookings, claim import (`claim_ticket`; `?claim=CODE` link in the PDF, parked across sign-in; `ImportSheet`, imported-ticket list + `ImportedTicketSheet` under Account → Tickets), top-left Back + icon rows + glass calendar popover on Confirmed, Pulse as a bottom sheet with a glass close button, and the profile share card (`sheets/ProfileShareSheet.jsx`).
- PDFs are drawn on a canvas then wrapped by jsPDF (`src/lib/ticketPdf.js`) because jsPDF's fonts have no Vietnamese; verified in Chromium (118 KB, correct glyphs, links present).
- Desktop shows the app in a 393pt phone frame (`.bb-device`/`.bb-screen` in `index.css`; `src/lib/viewport.js` for anything that sizes from the screen).
- Needs migrations 151/152 applied. Not verified end-to-end against a database; `tests/pulse-viewer.spec.js` was edited for the sheet but not run.
- STILL web-less (iOS-only): ticket gifting (132/133) and gift PDFs, Apple Wallet pass (needs the signed .pkpass; no web equivalent), refund-dispute close / transcript export / goer delete-my-copy, dispute attachments, the not-found "Transfer not found" card in Chat.jsx, phone + DOB enrollment gate, host promo consent, payment-QR uploads, Account search, QR-scanner redesign, event-review tracking.

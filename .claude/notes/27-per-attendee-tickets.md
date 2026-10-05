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

// TASK B (2026-10-01 UX foundation pass) — the ONE shared rule for "does a
// real ticket exist yet". A held/pending-verification/disputed booking is
// NOT a ticket: no QR, no "Xem vé", no check-in code, no ticket-details CTA
// — only `Confirmed.jsx`'s own phase-specific "awaiting payment" UI. Every
// screen that wants to gate ticket UI must use this, not re-derive its own
// condition (this codebase already had one screen — EventDetail.jsx's
// reserve bar — check only `status` and skip `payment_state` entirely,
// which is exactly the bug this ticket asks to fix).
export function isBookingTicket(booking) {
  return !!booking && booking.status === 'confirmed' && booking.payment_state === 'confirmed';
}

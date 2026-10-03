// Refund MVP — the ONE shared mapper for "what can a host actually do with
// this claim", used by every host-facing refund surface (Attendance's
// Refund Center AND Account > Verifications' refund queue). Before this,
// each screen computed its own eligibility rules independently — Attendance
// checked for a valid recipient snapshot before allowing "Xác nhận đã
// chuyển tiền"; Verifications did not check this at all, so a claim with no
// valid destination still showed an active "Đã hoàn tiền" CTA there. A
// single shared function makes that kind of drift structurally impossible:
// there is exactly one place that decides "actionable or not," not one per
// screen.
export function refundClaimPresentation(c) {
  const hasDestination = !!c.selected_destination_id
    && !!c.recipient_snapshot?.bank_name
    && !!c.recipient_snapshot?.account_number
    && !!c.recipient_snapshot?.account_holder_name;
  const isActive = c.status === 'owed' || c.status === 'disputed';
  const now = Date.now();
  const overdue = (c.status === 'owed' && c.refund_due_at && new Date(c.refund_due_at).getTime() < now)
    || (c.status === 'disputed' && c.host_response_due_at && new Date(c.host_response_due_at).getTime() < now);
  return {
    hasDestination,
    // Stale-badge fix pass — `get_host_refund_claims()` returns EVERY claim
    // ever created for a host's events, with no status filter at all (by
    // design — Verifications.jsx's own activeRows/pendingRows filter what's
    // DISPLAYED). `isActive` was already computed here but never exposed on
    // the returned object, so every caller that needed "is this claim
    // actually outstanding" ended up re-deriving the same
    // `status === 'owed' || status === 'disputed'` check independently —
    // exactly the copy-the-check-into-each-view drift this module exists to
    // prevent. Exposed now so `src/lib/badges.js`'s host/refund badge counts
    // (previously a raw, unfiltered `refundQueue.length` — the actual cause
    // of a badge surviving after every claim was marked sent/confirmed/
    // waived/resolved) and Verifications.jsx's own row filters can both
    // read this ONE field instead of each keeping their own copy.
    isActive,
    // "eligible" — can be included in a batch/bulk selection right now.
    // Matches create_and_confirm_refund_batch()'s own accepted statuses
    // exactly (owed OR disputed — a disputed claim can still be resolved by
    // a batch confirm, same as a plain owed one).
    eligible: hasDestination && isActive,
    // "needsDestination" — active (owed/disputed) but has nothing a host
    // can act on yet; never render a Mark-refund-sent CTA for these.
    needsDestination: isActive && !hasDestination,
    overdue,
    // "actionable" — the single-claim "Đã hoàn tiền"/mark-sent CTA may be
    // shown. Disputed claims are handled by their own resend/response flow,
    // never this CTA (matches Attendance's existing rule).
    actionable: c.status === 'owed' && hasDestination,
    // "pendingConfirmation" — sent, waiting on the guest; never actionable
    // again from here.
    pendingConfirmation: c.status === 'host_marked_sent',
  };
}


// A host_marked_sent claim settles itself as confirmed this many days after
// the host marked it, if the guest neither confirms nor disputes. Enforced
// server-side by goc_auto_confirm_refunds() (migration 127) and stated in the
// Terms — change all three together.
export const REFUND_AUTO_CONFIRM_DAYS = 7;

/** Date the claim auto-confirms, or null unless host_marked_sent. */
export function refundAutoConfirmAt(claim) {
  if (!claim || claim.status !== 'host_marked_sent' || !claim.host_marked_at) return null;
  return new Date(new Date(claim.host_marked_at).getTime() + REFUND_AUTO_CONFIRM_DAYS * 86400000);
}

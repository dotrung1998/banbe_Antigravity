// TASK A (2026-10-01 UX foundation pass) — the ONE shared "what does this
// account need to act on right now" builder, consumed by Home, Account and
// Dashboard. Every item here comes from an already-loaded canonical server
// array (s.paymentBookings, s.myRefunds, s.verifications, s.refundQueue) —
// nothing here invents state of its own, so an item disappears the instant
// its source array no longer contains it (rule 2: "automatically remove an
// item when its canonical server condition is resolved").
//
// Ordering (rule 4): overdue -> deadline soon -> payment/refund/dispute ->
// normal action. `severityRank` encodes that; items are stable-sorted by it,
// ties broken by whichever has the soonest deadline (or none).
const SEVERITY_RANK = { overdue: 0, deadlineSoon: 1, money: 2, normal: 3 };

function msUntilSafe(iso, now) {
  if (!iso) return null;
  const t = new Date(iso).getTime() - now;
  return t > 0 ? t : 0;
}

/** Exported so a caller merging goer + host items (both roles on the same
 * account, e.g. Home.jsx) can re-sort the combined list the same way each
 * individual call already sorts its own — see buildActionCenterItems()'s
 * own call below. */
export function sortActionCenterItems(items) {
  return [...items].sort((a, b) => {
    const r = SEVERITY_RANK[a.severity] - SEVERITY_RANK[b.severity];
    if (r !== 0) return r;
    const da = a.deadline ? new Date(a.deadline).getTime() : Infinity;
    const db = b.deadline ? new Date(b.deadline).getTime() : Infinity;
    return da - db;
  });
}

/**
 * @param {object} p
 * @param {'goer'|'host'} p.role
 * @param {function} p.T - the app's bilingual copy helper
 * @param {number} p.now
 * @param {object|null} p.myHolding - soonest-expiring held booking (goer)
 * @param {object|null} p.myPendingVerification - soonest pending-verification booking (goer)
 * @param {Array} p.myRefunds - goer's own refund_claims (loadMyRefunds())
 * @param {Array} p.verifications - host's payment verification queue
 * @param {Array} p.refundQueue - host's refund queue (get_host_refund_claims(), all events)
 * @param {object|null} p.orgHolding - organizerHoldingSummary (host, pre-existing signal, folded in here rather than living in a second parallel banner system)
 * @param {function} p.onOpenPayment - (bookingId) => void
 * @param {function} p.onOpenMyRefunds - () => void
 * @param {function} p.onOpenVerifications - () => void
 * @param {function} p.onOpenRefundCenter - () => void (host, whole-account refund queue — routes to Verifications, the only cross-event host refund surface)
 * @param {function} p.onOpenDashboard - () => void
 */
export function buildActionCenterItems({
  role, T, now,
  myHolding, myPendingVerification, myRefunds = [], verifications = [], refundQueue = [], orgHolding = null,
  onOpenPayment, onOpenMyRefunds, onOpenVerifications, onOpenRefundCenter, onOpenDashboard,
}) {
  const items = [];

  if (role === 'goer') {
    // Source: unpaid held booking nearing expiry.
    if (myHolding) {
      const msLeft = msUntilSafe(myHolding.hold_expires_at, now);
      items.push({
        id: 'hold-' + myHolding.id,
        severity: msLeft === 0 ? 'overdue' : (msLeft != null && msLeft < 5 * 60000) ? 'deadlineSoon' : 'money',
        deadline: myHolding.hold_expires_at,
        label: T('Đang giữ chỗ', 'Holding a seat'),
        detail: (myHolding.events?.name || '') + T(' ▪︎ Chờ xác nhận thanh toán', ' ▪︎ Awaiting payment confirmation'),
        ctaLabel: T('Xem trạng thái thanh toán', 'View payment status'),
        onClick: () => onOpenPayment(myHolding.id),
        testId: 'action-center-hold',
      });
    }
    // Source: refund destination required — an owed/disputed claim with no
    // valid recipient snapshot yet (same rule as refundClaimPresentation()).
    myRefunds.filter(c => (c.status === 'owed' || c.status === 'disputed') && !c.selected_destination_id)
      .forEach(c => items.push({
        id: 'refund-dest-' + c.id,
        severity: 'money',
        deadline: c.refund_due_at,
        label: T('Cần chọn tài khoản nhận hoàn tiền', 'Refund destination required'),
        detail: c.eventName || '',
        ctaLabel: T('Chọn tài khoản', 'Choose account'),
        onClick: onOpenMyRefunds,
        testId: 'action-center-refund-destination',
      }));
    // Source: refund awaiting guest (this user's own) confirmation.
    myRefunds.filter(c => c.status === 'host_marked_sent')
      .forEach(c => items.push({
        id: 'refund-confirm-' + c.id,
        severity: 'money',
        deadline: null,
        label: T('Xác nhận đã nhận hoàn tiền', 'Confirm refund received'),
        detail: c.eventName || '',
        ctaLabel: T('Xem', 'View'),
        onClick: onOpenMyRefunds,
        testId: 'action-center-refund-confirm',
      }));
    // Pre-existing signal (not one of this ticket's own 4 goer sources, but
    // folded in here rather than kept as a second parallel banner system —
    // "clock stopped, seat locked" reassurance while an organizer verifies).
    if (myPendingVerification) {
      items.push({
        id: 'pending-verify-' + myPendingVerification.id,
        severity: 'normal',
        deadline: null,
        label: T('Đang chờ xác nhận', 'Awaiting confirmation'),
        detail: (myPendingVerification.events?.name || '') + T(' ▪︎ đồng hồ đã dừng, chỗ được khoá', ' ▪︎ clock stopped, seat locked'),
        ctaLabel: T('Xem', 'View'),
        onClick: () => onOpenPayment(myPendingVerification.id),
        testId: 'action-center-pending-verification',
      });
    }
    // Source: active dispute requiring a response.
    myRefunds.filter(c => c.status === 'disputed')
      .forEach(c => items.push({
        id: 'refund-dispute-' + c.id,
        severity: 'overdue',
        deadline: c.host_response_due_at,
        label: T('Tranh chấp hoàn tiền đang chờ', 'Refund dispute open'),
        detail: c.eventName || '',
        ctaLabel: T('Xem', 'View'),
        onClick: onOpenMyRefunds,
        testId: 'action-center-refund-dispute',
      }));
  }

  if (role === 'host') {
    // Source: payment verification queue (also covers "pending approval" —
    // this codebase has no separate approval workflow beyond payment
    // verification today).
    if (verifications.length) {
      const soonest = verifications.map(v => v.verify_due_at).filter(Boolean).sort()[0];
      const msLeft = msUntilSafe(soonest, now);
      items.push({
        id: 'verify-queue',
        severity: msLeft === 0 ? 'overdue' : (msLeft != null && msLeft < 5 * 60000) ? 'deadlineSoon' : 'money',
        deadline: soonest,
        label: T('Chờ bạn xác nhận thanh toán', 'Payments awaiting your OK'),
        detail: verifications.length + T(' khoản', verifications.length === 1 ? ' payment' : ' payments'),
        ctaLabel: T('Xem', 'View'),
        onClick: onOpenVerifications,
        testId: 'action-center-verify-queue',
      });
    }
    // Source: owed/overdue refunds.
    const owed = refundQueue.filter(c => c.status === 'owed');
    if (owed.length) {
      const anyOverdue = owed.some(c => c.refund_due_at && new Date(c.refund_due_at).getTime() < now);
      items.push({
        id: 'refund-owed',
        severity: anyOverdue ? 'overdue' : 'money',
        deadline: owed.map(c => c.refund_due_at).filter(Boolean).sort()[0] || null,
        label: T('Khoản hoàn tiền cần xử lý', 'Refunds you owe'),
        detail: owed.length + T(' khoản', owed.length === 1 ? ' refund' : ' refunds'),
        ctaLabel: T('Xem', 'View'),
        onClick: onOpenRefundCenter,
        testId: 'action-center-refund-owed',
      });
    }
    // Source: refund dispute response due.
    const disputed = refundQueue.filter(c => c.status === 'disputed');
    if (disputed.length) {
      items.push({
        id: 'refund-dispute-queue',
        severity: 'overdue',
        deadline: disputed.map(c => c.host_response_due_at).filter(Boolean).sort()[0] || null,
        label: T('Tranh chấp hoàn tiền cần phản hồi', 'Refund disputes need a response'),
        detail: disputed.length + T(' khoản', disputed.length === 1 ? ' claim' : ' claims'),
        ctaLabel: T('Xem', 'View'),
        onClick: onOpenRefundCenter,
        testId: 'action-center-refund-dispute-queue',
      });
    }
    // Pre-existing signal (organizerHoldingSummary) — guests currently
    // holding seats on this host's events, folded in here too.
    if (orgHolding && orgHolding.count) {
      items.push({
        id: 'org-holding',
        severity: 'normal',
        deadline: orgHolding.soonestHoldExpiresAt || null,
        label: T('Khách đang giữ chỗ', 'Guests holding seats'),
        detail: orgHolding.count + T(' chỗ', orgHolding.count === 1 ? ' seat' : ' seats'),
        ctaLabel: T('Xem', 'View'),
        onClick: onOpenDashboard,
        testId: 'action-center-org-holding',
      });
    }
  }

  return sortActionCenterItems(items);
}

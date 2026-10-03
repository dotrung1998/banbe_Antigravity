// FIX PASS (2026-09-30) — ONE centralized module deriving every numeric
// badge shown anywhere in the app's navigation chain (child row -> group
// card -> account tab -> dock icon), so a count is computed in exactly one
// place per source instead of scattered per-view arithmetic drifting apart.
//
// Every function here reads ONLY already-loaded canonical arrays/counts
// this codebase already fetches for other real purposes (the same sources
// `src/lib/actionCenter.js`/`AccountGroup.jsx`/`Account.jsx` already read):
// `pendingEventsCount` (admin moderation queue, loadPendingEventsCount()),
// `verifications` (host payment-verification queue, loadVerifications()),
// `refundQueue` (host refund queue, loadRefundQueue()). No new "unread"
// concept is invented, and nothing here fabricates a count for a screen
// with no real underlying source (Home/Map/static settings/the "+" create
// action never get a badge from this module).
//
// Dedup rule: every number here is either (a) the length of ONE distinct
// canonical array, or (b) the sum of two-or-more canonical arrays that are
// structurally guaranteed to never share an item (a `verifications` row and
// a `refundQueue` row are different Postgres tables with different primary
// keys — summing their lengths counts each real row exactly once). Nothing
// here ever sums an ALREADY-AGGREGATED badge into another sum (that would
// double count) — each level below recomputes from the same base arrays,
// it never re-adds a sibling's own already-computed badge.
//
// Permissions: `computeAdminModerationCount` returns 0 (and the caller
// hides the badge entirely, per this app's own "0 = hidden" convention)
// for anything other than a server-confirmed `accountType === 'admin'` —
// the same gate `Account.jsx`'s own Admin tab/`AccountGroup.jsx`'s
// `adminReview` redirect-guard already use. `computeHostActionCount`
// mirrors the equivalent `organizerMode` gate the Host tab itself uses.
// Both naturally return 0 (hidden) right after logout/account-switch,
// since the arrays they read are already cleared then (GocContext's own
// sign-out `set({ verifications: [], refundQueue: [], pendingEventsCount: 0, ... })`).

/** Admin's one real moderation queue today (`admin.events` row / "Review &
 * moderation" group card / Admin tab / Account dock icon all derive from
 * this SAME number — see `Account.jsx`'s admin tab, `AccountGroup.jsx`'s
 * "Sự kiện chờ duyệt" row, and this module's own `computeAccountDockBadge`). */
export function computeAdminModerationCount({ accountType, pendingEventsCount }) {
  if (accountType !== 'admin') return 0;
  return pendingEventsCount || 0;
}

// Stale-badge fix pass — `refundQueue` (from `get_host_refund_claims()`) is
// every claim ever created for a host's events, not just outstanding ones;
// `host_marked_sent`/`guest_confirmed`/`waived`/`resolved` all stay in that
// array forever. Counting `refundQueue.length` directly (what this module
// used to do) is exactly why a host could see every claim already resolved
// — the Refunds/Verifications screen genuinely empty of actionable rows —
// while the badge still showed a leftover positive count from old history.
// `c.isActive` (`refundClaimPresentation()`, already spread onto every
// loaded claim) is the SAME canonical "owed or disputed" check
// Verifications.jsx's own active-rows filter uses — reused here, not
// copied, so the two can never drift apart.
function countActionableRefunds(refundQueue) {
  return (refundQueue || []).filter(c => c.isActive).length;
}

/** Host's real outstanding duties: the payment-verification queue and the
 * refund queue both ultimately route to the SAME "Verifications" screen
 * (see `onOpenRefundCenter: () => openVerifications(...)` in Home/Account/
 * Dashboard) — summing them here is exactly what that shared destination
 * actually contains, not an invented aggregate. */
export function computeHostActionCount({ organizerMode, verifications = [], refundQueue = [] }) {
  if (!organizerMode) return 0;
  return (verifications?.length || 0) + countActionableRefunds(refundQueue);
}

/** Refund-discoverability fix — a dedicated "Refunds" row (AccountGroup.jsx/
 * AccountGroupView.swift's `hostOps` section) needs its OWN badge, same
 * actionable-refund count `computeHostActionCount` already sums in — never
 * a second, differently-defined count, so the two badges can never silently
 * drift apart. */
export function computeRefundActionCount({ organizerMode, refundQueue = [] }) {
  if (!organizerMode) return 0;
  return countActionableRefunds(refundQueue);
}

/** Account (dock/profile) icon badge — the top of the whole chain. Sums
 * the admin, host and personal counts (never each other's own already-summed value,
 * and never a per-row count a second time) because a real admin queue item
 * and a real host queue item are always distinct underlying rows; an
 * account that is neither admin nor currently in organizer mode gets 0
 * from both terms, so the dock icon is correctly hidden rather than
 * showing a stale/leftover number. */
export function computeAccountDockBadge(state) {
  return computeAdminModerationCount(state) + computeHostActionCount(state) + computePersonalActionCount(state);
}

/** Personal-tab "Tickets & Bookings" group badge (Account IA reorg,
 * 2026-09-30) — real bookings this account itself needs to act on: a
 * still-holding/awaiting-payment/pending-verification booking (active
 * status, not yet a real ticket per `isBookingTicket`). Reads the SAME
 * `paymentBookings` array `Account.jsx`'s own `myHolding`/
 * `myPendingVerification` ActionCenter items already load (no new query),
 * so this is a third view of one already-loaded array, not a new source.
 * Part of `computePersonalActionCount`, which the dock badge sums in. */
export function computeMyTicketsActionCount({ paymentBookings = [] } = {}) {
  return (paymentBookings || []).filter(b => (
    ['pending', 'confirmed', 'attended'].includes(b.status)
    && !(b.status === 'confirmed' && b.payment_state === 'confirmed')
  )).length;
}

/** Goer-side refunds needing action (pick a destination, confirm receipt, or
 * an open dispute) — the SAME three conditions `actionCenter.js` turns into
 * goer items, counted once per distinct claim. */
export function computeMyRefundActionCount({ myRefunds = [] } = {}) {
  return (myRefunds || []).filter(c => (
    c.status === 'host_marked_sent'
    || c.status === 'disputed'
    || (c.status === 'owed' && !c.selected_destination_id)
  )).length;
}

/** Personal tab = every personal action: bookings + own refunds. */
export function computePersonalActionCount(state) {
  return computeMyTicketsActionCount(state) + computeMyRefundActionCount(state);
}

/** Shared "99+" cap — the exact count is still always available to the
 * caller for its own accessibility label; this only bounds the digits
 * actually painted into the small badge shape. */
export function formatBadgeCount(n) {
  return n > 99 ? '99+' : String(n);
}

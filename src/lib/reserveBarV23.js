// v2.3 reserve bar rules (note 81, switch home_v23), on top of src/lib/reserveBar.js (which keeps the cap, the seats
// clamp, the totals and the bar state). Web only for now: iOS keeps ReserveBar.swift's V8 bar until it ports v2.3.
//
// - The bar opens COMPACT (quantity + Reserve, the total once beside it) so the whole ticket stub is readable on
//   arrival. Past ~40 px of scrolling it grows into the full card, and back near the top it compacts again. Two
//   thresholds (hysteresis) so it never flickers at the line.
// - Quantity is 1 · 2 · 3 · 4+. 4+ turns into an in-place − N + stepper up to MAX_QTY (6 per person, you included) or
//   the seats left if fewer. Back down to 3 returns to the chips.
// Copy: { vi, en } pairs, note 57.
import { MAX_QTY, maxQty } from './reserveBar.js';

export const GROW_AT = 40; // px of scroll past which the bar grows into the full card
export const COMPACT_AT = 24; // px from the top at which it compacts again
export const MORE_AT = 4; // the fourth slot: "4+"
const L = (vi, en) => ({ vi, en });

/** Next compact state from the scroll position and the current state. */
export function nextCompact(scrollTop, compact) {
  const t = Math.max(0, Number(scrollTop) || 0);
  if (compact) return t <= GROW_AT;
  return t <= COMPACT_AT;
}

/**
 * The quantity control for `qty` with `remaining` seats free (null = unknown).
 * stepper: the 4+ slot is a − N + stepper; moreEnabled: 4+ can be picked; canMinus / canPlus: the stepper's buttons.
 */
export function qtyControl(qty, remaining = null) {
  const max = maxQty(remaining);
  const stepper = qty >= MORE_AT;
  return { max, stepper, moreEnabled: max >= MORE_AT, canMinus: qty > 1, canPlus: qty < max };
}

/** Six seats: you first, then guests, then empty, for the dots under the stepper. */
export function seatDots(qty) {
  return Array.from({ length: MAX_QTY }, (_, i) => (i === 0 ? 'me' : i < qty ? 'guest' : 'empty'));
}

/**
 * "You + 3 guests · up to 6". At the cap it says why it stops: "only 4 left" when the seats run out first,
 * "6 is the most per person" otherwise.
 */
export function guestLine(qty, remaining = null) {
  const max = maxQty(remaining);
  const g = Math.max(0, qty - 1);
  const who = g === 0 ? L('Chỉ mình bạn', 'Just you') : L(`Bạn + ${g} khách`, `You + ${g} ${g === 1 ? 'guest' : 'guests'}`);
  let cap;
  if (qty < max) cap = L(`tối đa ${max}`, `up to ${max}`);
  else if (max < MAX_QTY) cap = L(`chỉ còn ${max} chỗ`, `only ${max} left`);
  else cap = L(`tối đa ${MAX_QTY} vé mỗi người`, `${MAX_QTY} is the most per person`);
  return L(`${who.vi} · ${cap.vi}`, `${who.en} · ${cap.en}`);
}

/** What a tap on 4+ says when the event has 3 seats or fewer left. */
export function moreRefusal(remaining) {
  const n = Math.max(0, remaining | 0);
  return n === 1 ? L('Sự kiện này chỉ còn 1 vé', 'Only 1 ticket left for this one') : L(`Sự kiện này chỉ còn ${n} vé`, `Only ${n} tickets left for this one`);
}

/** The line under the total: "per ticket" for one, "Total · 2 × 850.000₫" for more, "no charge" when free. */
export function totalSub(qty, unitText, free) {
  if (free) return L('không mất phí', 'no charge');
  if (qty <= 1) return L('mỗi vé', 'per ticket');
  return L(`Tổng · ${qty} × ${unitText}`, `Total · ${qty} × ${unitText}`);
}

// ---- Phase e: stamps and adding tickets after a hold (note 81) ----
// The viewer's bookings on the event come from bookings rows (newest first). Only the ones that still hold a seat count,
// with the same rule as the server's booking_holds_seat() (migration 026), so the client never disagrees with
// hold_seats about how many seats a person has.

/** booking_holds_seat(): attended/no-show always, cancelled/expired never, confirmed / pending verification /
 *  disputed yes, holding only until hold_expires_at. */
export function holdsSeat(b, now = Date.now()) {
  if (!b) return false;
  if (b.status === 'attended' || b.status === 'no_show') return true;
  if (b.status === 'cancelled' || b.status === 'expired') return false;
  if (['confirmed', 'pending_verification', 'disputed'].includes(b.payment_state)) return true;
  if (b.payment_state === 'holding') return !b.hold_expires_at || new Date(b.hold_expires_at).getTime() > now;
  return false;
}
const isTicket = (b) => b.status === 'attended' || (b.status === 'confirmed' && b.payment_state === 'confirmed');

/** Seats this person holds on the event, across bookings. */
export function bookedQty(bookings = [], now = Date.now()) {
  return (bookings || []).filter(b => holdsSeat(b, now)).reduce((n, b) => n + (Number(b.qty) || 0), 0);
}

/**
 * The stamp on the stub: null (nothing held), { kind: 'confirmed' } when every seat-holding booking is a ticket, else
 * { kind: 'held', until, phase } for the earliest open one: 'hold' (the buyer's 30 min, hold_expires_at) or 'verify'
 * (the host's 1 h, verify_due_at). A confirmed booking plus a newer held one reads Held (the added tickets wait).
 */
export function stampState(bookings = [], now = Date.now()) {
  const seat = (bookings || []).filter(b => holdsSeat(b, now));
  if (!seat.length) return null;
  const open = seat.filter(b => !isTicket(b));
  if (!open.length) return { kind: 'confirmed', until: null, phase: null };
  const deadline = (b) => {
    const t = b.payment_state === 'holding' ? b.hold_expires_at : b.payment_state === 'pending_verification' ? b.verify_due_at : null;
    const ms = t ? new Date(t).getTime() : NaN;
    return Number.isFinite(ms) ? ms : null;
  };
  const withTimes = open.map(b => ({ b, t: deadline(b) })).sort((x, y) => (x.t ?? Infinity) - (y.t ?? Infinity));
  const first = withTimes[0];
  return { kind: 'held', until: first.t, phase: first.b.payment_state === 'holding' ? 'hold' : 'verify' };
}

/** "Held · 25 min" / "Held · 1 h" (time left, rounded up), "Confirmed". */
export function stampText(stamp, now = Date.now()) {
  if (!stamp) return null;
  if (stamp.kind === 'confirmed') return L('Đã xác nhận', 'Confirmed');
  const mins = stamp.until == null ? null : Math.ceil((stamp.until - now) / 60000);
  if (mins == null || mins <= 0) return L('Đã giữ', 'Held');
  if (mins >= 60) { const h = Math.ceil(mins / 60); return L(`Đã giữ · ${h} giờ`, `Held · ${h} h`); }
  return L(`Đã giữ · ${mins} phút`, `Held · ${mins} min`);
}

/**
 * The quantity control once the viewer holds `booked` seats: the total can't go below what they hold, and can reach
 * 6 per person or what they hold plus the seats still free. `adding` = more than they hold.
 */
export function addControl(qty, remaining = null, booked = 0) {
  const max = Math.min(MAX_QTY, booked + (remaining == null ? MAX_QTY : Math.max(0, remaining)));
  const min = Math.max(1, booked);
  const q = Math.min(max, Math.max(min, qty));
  return { qty: q, min, max, extra: Math.max(0, q - booked), adding: q > booked, stepper: q >= MORE_AT, moreEnabled: max >= MORE_AT && booked < max, canMinus: q > min, canPlus: q < max };
}

/** Bar copy while the viewer holds seats. */
export function heldCopy({ booked, extra, confirmed, phase }) {
  if (extra > 0) {
    return {
      button: L(`Thêm ${extra} vé`, `Add ${extra} ${extra === 1 ? 'ticket' : 'tickets'}`),
      sub: L(`thêm ${extra} · tổng ${booked + extra} vé`, `${extra} more · ${booked + extra} in all`),
      trust: L('Lượt đặt mới · chủ nhà cũng xác nhận', 'A new booking · the host confirms it too'),
    };
  }
  return {
    button: confirmed ? L('Xem vé của bạn', 'View your ticket') : L('Đã giữ chỗ', 'Seats held'),
    sub: L(`${booked} vé của bạn`, `${booked} ${booked === 1 ? 'ticket' : 'tickets'} yours`),
    trust: confirmed ? L('Chủ nhà đã xác nhận · mã QR đã sẵn sàng', 'Confirmed by the host · your QR is ready')
      : phase === 'verify' ? L('Chủ nhà có 1 giờ để xác nhận · banbe sẽ nhắc', 'The host has 1 hour to confirm · banbe reminds them')
        : L('Chỗ được giữ trong lúc bạn chuyển khoản', 'Your seats are held while you pay'),
  };
}

/** "2 booked · adding 1 · up to 6" under the stepper while adding; the plain guest line otherwise. */
export function addGuestLine(qty, booked, max) {
  if (booked > 0 && qty > booked) {
    const cap = qty >= max ? (max < MAX_QTY ? L(`chỉ còn ${max - booked} chỗ`, `only ${max - booked} more free`) : L(`tối đa ${MAX_QTY} vé mỗi người`, `${MAX_QTY} is the most per person`)) : L(`tối đa ${max}`, `up to ${max}`);
    return L(`${booked} đã giữ · thêm ${qty - booked} · ${cap.vi}`, `${booked} held · adding ${qty - booked} · ${cap.en}`);
  }
  return null;
}

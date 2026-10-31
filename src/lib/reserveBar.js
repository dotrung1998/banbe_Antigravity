// Event Detail's sticky action bar: which state it is in, how many seats the stepper allows, and the total shown in
// the CTA. One row since note 70: stepper + "Reserve · total" (the 1·2·3 presets were dropped).
// Pure logic so Event Detail and Reserve agree on the total. Mirrored by apps/ios/BanbeApp/Lib/ReserveBar.swift
// (tests: tests/unit/reserveBar.test.mjs and apps/ios/BanbeAppTests/ReserveBarTests.swift) — change both together.
//
// Money follows the event's own currency (migration 195): real events carry `priceAmount` (minor units: dong,
// or cents for USD) and `currency`; the demo catalogue only has its Vietnamese price text, which is VND.

import { formatMoney, parsePriceInput, paidBookingAvailable } from './eventMarket.js';

export const MAX_QTY = 6; // same cap as Reserve's stepper and qtyPlus

// Why the bar is disabled for a paid event whose currency cannot be booked yet (owner decision 2026-10-22).
export const CURRENCY_UNAVAILABLE_REASON = ['Đặt vé trả phí cho sự kiện tại Mỹ sẽ sớm mở', 'Paid booking for US events opens soon'];

// "200.000₫" / "$12.50" / "Miễn phí" / "Free" -> { free, unit } (unit in the currency's minor unit, 0 when free or
// unparseable). `currency` says how to read the text; VND (the default) ignores dots, USD reads cents.
export function parsePrice(price, currency = 'VND') {
  const text = String(price || '');
  if (/Miễn phí|Free/i.test(text)) return { free: true, unit: 0 };
  if (currency === 'USD') return { free: false, unit: parsePriceInput(text, 'USD') ?? 0 };
  const m = text.match(/[\d.]+/);
  const unit = m ? (parseInt(m[0].replace(/\./g, ''), 10) || 0) : 0;
  return { free: false, unit };
}

/** { free, unit, currency } of an Event Detail shape: the raw amount when the event carries one, else its text. */
export function eventPrice(ev) {
  const currency = ev?.currency === 'USD' ? 'USD' : 'VND';
  if (ev && Number.isFinite(ev.priceAmount)) return { free: !(ev.priceAmount > 0), unit: Math.max(0, ev.priceAmount), currency };
  return { ...parsePrice(ev?.price, currency), currency };
}

// Total for `qty` seats ("400.000₫", "$25" or "Miễn phí"); translate with trStatus.
export function totalPrice(price, qty, currency = 'VND') {
  const { free, unit } = parsePrice(price, currency);
  if (free) return 'Miễn phí';
  return formatMoney(unit * Math.max(1, qty | 0), currency);
}

/** Same total from an Event Detail shape (see eventPrice). */
export function eventTotal(ev, qty) {
  const { free, unit, currency } = eventPrice(ev);
  if (free) return 'Miễn phí';
  return formatMoney(unit * Math.max(1, qty | 0), currency);
}

/** True when the event is paid in a currency that cannot be booked yet (paid USD, migration 195). */
export function currencyUnavailable(ev) {
  const { unit, currency } = eventPrice(ev);
  return !paidBookingAvailable(currency, unit);
}

// First match wins. An event that is over says so first (Phase 1 Q3, tests/fixtures/quick-wins.json
// `endedPrecedence`): 'endedAttended' ("You went ✓") for a confirmed ticket, else 'ended', and a cancellation still
// wins over both. Before that, a booking beats every closed state (a cancelled event keeps its payment status
// reachable for the refund), cancelled beats sold out (a cancelled event's stale seats_remaining can say either), a
// paid event nobody can book yet (currencyUnavailable) comes next, and the criteria block applies only when nothing
// else does.
export function reserveBarState({ booking, ticket, cancelled, ended, soldOut, currencyUnavailable: noCurrency, blocked }) {
  if (ended) return cancelled ? 'cancelled' : (booking && ticket ? 'endedAttended' : 'ended');
  if (booking) return ticket ? 'ticket' : 'pending';
  if (cancelled) return 'cancelled';
  if (soldOut) return 'soldOut';
  if (noCurrency) return 'currencyUnavailable';
  if (blocked) return 'blocked';
  return 'reserve';
}

/** The stepper's ceiling: the cap, and never more than the seats still free when they are known (note 70). */
export function maxQty(remaining = null) {
  return remaining != null && Number.isFinite(remaining) ? Math.max(1, Math.min(MAX_QTY, remaining | 0)) : MAX_QTY;
}

// 1…max (max defaults to the cap). hold_seats still refuses more than the seats left; this keeps the UI honest.
export function clampQty(n, max = MAX_QTY) {
  return Math.min(Math.max(1, max | 0), Math.max(1, n | 0));
}

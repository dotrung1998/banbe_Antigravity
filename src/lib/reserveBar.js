// Event Detail's sticky action bar: which state it is in, the seat presets, and the total shown in the CTA.
// Pure logic so Event Detail and Reserve agree on the total. Mirrored by apps/ios/BanbeApp/Lib/ReserveBar.swift
// (tests: tests/unit/reserveBar.test.mjs and apps/ios/BanbeAppTests/ReserveBarTests.swift) — change both together.

export const MAX_QTY = 6; // same cap as Reserve's stepper and qtyPlus
export const QTY_PRESETS = [1, 2, 3]; // "1 vé · 2 vé · 3 vé" (note 52 mockup); the stepper covers 4–6

// "200.000₫" / "Miễn phí" / "Free" -> { free, unit } (unit in VND, 0 when free or unparseable).
export function parsePrice(price) {
  const text = String(price || '');
  if (/Miễn phí|Free/i.test(text)) return { free: true, unit: 0 };
  const m = text.match(/[\d.]+/);
  const unit = m ? (parseInt(m[0].replace(/\./g, ''), 10) || 0) : 0;
  return { free: false, unit };
}

const vnd = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, '.') + '₫';

// Total for `qty` seats in the catalogue's own Vietnamese form ("400.000₫" or "Miễn phí"); translate with trStatus.
export function totalPrice(price, qty) {
  const { free, unit } = parsePrice(price);
  if (free) return 'Miễn phí';
  return vnd(unit * Math.max(1, qty | 0));
}

// First match wins, in the order the old inline label chain used: a booking beats every closed state, cancelled
// beats ended/sold out (a cancelled event's stale seats_remaining can say either), and the criteria block applies
// only when nothing else does.
export function reserveBarState({ booking, ticket, cancelled, ended, soldOut, blocked }) {
  if (booking) return ticket ? 'ticket' : 'pending';
  if (cancelled) return 'cancelled';
  if (ended) return 'ended';
  if (soldOut) return 'soldOut';
  if (blocked) return 'blocked';
  return 'reserve';
}

// Presets never offer more than the cap; a value outside the presets (e.g. 3 from the stepper) is still valid.
export function clampQty(n) {
  return Math.min(MAX_QTY, Math.max(1, n | 0));
}

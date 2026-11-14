// "Next up" on the v2.3 Home (note 81): the viewer's upcoming tickets as ticket cards, soonest first. Pure, unit-tested
// (tests/unit/nextUp.test.mjs). Built from the bookings Home already loads (loadPaymentBookings), so it needs no new
// query. Patterns it follows for people with several tickets:
// - one card per EVENT, not per booking (Ticketmaster / DICE group a party's tickets; a hold plus added tickets is still
//   one night out), with the people counted across bookings;
// - soonest first and swipeable, the next card peeking (Apple Wallet's stack, Airbnb's upcoming trips), "1 of 3";
// - the main button follows what that event needs now: Show ticket when every seat is confirmed, Pay now while a hold
//   runs, View status while the host confirms. A mixed event says so ("2 ready · 1 waiting").
// Copy: { vi, en } pairs, no dash/semicolon idea separators (note 57).
import { holdsSeat } from './reserveBarV23.js';

const L = (vi, en) => ({ vi, en });
const H = 3600000;
const isTicket = (b) => b.status === 'attended' || (b.status === 'confirmed' && b.payment_state === 'confirmed');
const ms = (t) => { const v = t ? new Date(t).getTime() : NaN; return Number.isFinite(v) ? v : null; };

/**
 * bookings: rows from loadPaymentBookings; eventsById: { [eventId]: { startMs, endMs|null, cancelled } }.
 * Returns [{ eventId, bookings, seats, ready, open, state: 'ready'|'pay'|'waiting', mixed, holdUntil, primaryId, live,
 * startMs }] for events not over yet (end, else start + 12 h), soonest first. Gifted tickets (recipient_name) and
 * bookings that no longer hold a seat are left out.
 */
export function nextUpGroups(bookings = [], eventsById = {}, now = Date.now()) {
  const by = new Map();
  for (const b of bookings || []) {
    if (!b || b.recipient_name || !holdsSeat(b, now)) continue;
    const id = b.event_id || b.events?.id;
    if (!id) continue;
    if (!by.has(id)) by.set(id, []);
    by.get(id).push(b);
  }
  const out = [];
  for (const [eventId, list] of by) {
    const ev = eventsById[eventId];
    if (!ev || !Number.isFinite(ev.startMs) || ev.cancelled) continue;
    const over = Number.isFinite(ev.endMs) ? ev.endMs : ev.startMs + 12 * H;
    if (now > over) continue;
    const readyB = list.filter(isTicket);
    const openB = list.filter(b => !isTicket(b));
    const holding = openB.filter(b => b.payment_state === 'holding');
    const seats = list.reduce((n, b) => n + (Number(b.qty) || 0), 0);
    const ready = readyB.reduce((n, b) => n + (Number(b.qty) || 0), 0);
    const state = !openB.length ? 'ready' : holding.length ? 'pay' : 'waiting';
    const holdUntil = holding.map(b => ms(b.hold_expires_at)).filter(Number.isFinite).sort((a, c) => a - c)[0] ?? null;
    const primary = state === 'pay' ? holding[0] : state === 'waiting' ? openB[0] : readyB.sort((a, c) => (ms(c.created_at) || 0) - (ms(a.created_at) || 0))[0];
    out.push({ eventId, bookings: list, seats, ready, open: seats - ready, state, mixed: ready > 0 && openB.length > 0, holdUntil,
      primaryId: primary?.id || list[0].id, live: now >= ev.startMs, startMs: ev.startMs });
  }
  return out.sort((a, c) => a.startMs - c.startMs);
}

/** Calendar days from today to the event's day, in the venue's zone. */
export function dayDiffInZone(startMs, now, timeZone) {
  const day = (t) => {
    const p = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(t));
    return Date.parse(`${p}T00:00:00Z`) / 86400000;
  };
  return Math.round(day(startMs) - day(now));
}

/** The chip on the photo: Happening now / Tonight / Today / Tomorrow / In N days. */
export function nextUpChip(g, now, timeZone) {
  if (g.live) return L('Đang diễn ra', 'Happening now');
  const d = dayDiffInZone(g.startMs, now, timeZone);
  if (d <= 0) {
    const hour = Number(new Intl.DateTimeFormat('en-GB', { timeZone, hour: '2-digit', hourCycle: 'h23' }).format(new Date(g.startMs)));
    return hour >= 17 ? L('Tối nay', 'Tonight') : L('Hôm nay', 'Today');
  }
  if (d === 1) return L('Ngày mai', 'Tomorrow');
  return L(`Còn ${d} ngày`, `In ${d} days`);
}

/** { main: "2 people", note: "2 bookings" | null } (the note only when the party is split over several bookings). */
export function peopleLine(g) {
  const n = g.seats;
  const k = g.bookings.length;
  return { main: L(`${n} người`, n === 1 ? '1 person' : `${n} people`), note: k > 1 ? L(`${k} lượt đặt`, `${k} bookings`) : null };
}

/** Status cell + its tone, and the main button. */
export function nextUpStatus(g, now) {
  if (g.state === 'ready') return { text: L('Sẵn sàng', 'Ready'), note: null, tone: 'moss', icon: 'check', action: 'ticket', button: L('Hiện vé', 'Show ticket') };
  const mins = g.state === 'pay' && g.holdUntil != null ? Math.max(0, Math.ceil((g.holdUntil - now) / 60000)) : null;
  const act = g.state === 'pay'
    ? { action: 'pay', button: L('Thanh toán', 'Pay now') }
    : { action: 'status', button: L('Xem trạng thái', 'View status') };
  if (g.mixed) return { text: L(`${g.ready} sẵn sàng`, `${g.ready} ready`), note: L(`${g.open} đang chờ`, `${g.open} waiting`), tone: 'honey', icon: 'clock', ...act };
  if (g.state === 'pay') return { text: L('Chờ thanh toán', 'Payment due'), note: mins == null ? null : L(`còn ${mins} phút`, `${mins} min left`), tone: 'honey', icon: 'clock', ...act };
  return { text: L('Chờ chủ nhà', 'Host confirming'), note: null, tone: 'honey', icon: 'clock', ...act };
}

/** The date badge in the venue's zone: { weekday: 'SUN', day: '22', month: 'NOV' } (VI: 'CN', '22', 'TH 11'). */
export function dateBadge(startMs, timeZone, en) {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone, weekday: 'short', day: 'numeric', month: 'numeric' })
    .formatToParts(new Date(startMs)).map(x => [x.type, x.value]));
  const wd = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(p.weekday);
  const MONTHS = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  return en
    ? { weekday: ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'][wd], day: p.day, month: MONTHS[Number(p.month) - 1] }
    : { weekday: ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'][wd], day: p.day, month: `TH ${p.month}` };
}

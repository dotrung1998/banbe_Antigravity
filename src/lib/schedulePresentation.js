// banbe Schedule — pure mapping from real app state to the in-app agenda. Web port of iOS
// `Lib/SchedulePresentation.swift` (notes 44/45). Tested in tests/unit/schedule.test.mjs.
//
// Sources, highest priority first (one row per event; the strongest wins):
//   1. booked   — booking status pending/confirmed/attended AND payment confirmed.
//   2. awaiting — active booking whose payment is pending host verification.
//   3. holding  — active booking still inside its seat-hold window (an EXPIRED hold is not a plan).
//   4. hosting  — the account's own organizer's event.
//   5. added    — put on the banbe Schedule by hand (this browser only, scheduleStore below).
// Never included: cancelled events, cancelled bookings, expired holds, tickets gifted to someone else, events with no
// start time (counted separately so nothing silently disappears). Saved/favorited events are NOT a source.
//
// Time honesty: events carry NO end time today (note 38). "Overlap" is only claimed when both items have a real end;
// otherwise the only statement made is "starts within 2 hours of a plan". Dates are the browser's local calendar.

export const SOURCES = ['booked', 'awaiting', 'holding', 'hosting', 'added'];
const rank = (s) => SOURCES.indexOf(s);
export const NEAR_WINDOW_MS = 2 * 3600 * 1000;

export function sourceLabel(source, T) {
  return {
    booked: T('Đã đặt chỗ', 'Booked'),
    awaiting: T('Chờ host xác nhận', 'Awaiting host confirmation'),
    holding: T('Đang giữ chỗ', 'Seat on hold'),
    hosting: T('Bạn tổ chức', "You're hosting"),
    added: T('Bạn đã thêm', 'Added by you'),
  }[source];
}

/** booking: { eventKey, status, paymentState, holdExpiresAt (ms|null), giftedAway } */
export function bookingSource(b, now) {
  if (b.giftedAway || !['pending', 'confirmed', 'attended'].includes(b.status)) return null;
  if (b.paymentState === 'confirmed') return 'booked';
  if (b.paymentState === 'pending_verification') return 'awaiting';
  if (b.paymentState === 'holding') return b.holdExpiresAt != null && b.holdExpiresAt > now ? 'holding' : null;
  return null;
}

/**
 * events: { [key]: { key, title, start (ms|null), end (ms|null), timeZone, location, cancelled, ended, inviteOnly, soldOut } }
 * Returns { items: [{ id, event, source, sources }], undatedCount }.
 */
export function mySchedule({ bookings = [], hostedKeys = [], addedKeys = [], events = {}, now = Date.now() }) {
  const byKey = new Map();
  const add = (key, src) => {
    const list = byKey.get(key) || [];
    if (!list.includes(src)) list.push(src);
    byKey.set(key, list);
  };
  for (const b of bookings) { const src = bookingSource(b, now); if (src) add(b.eventKey, src); }
  for (const k of hostedKeys) add(k, 'hosting');
  for (const k of addedKeys) add(k, 'added');

  const items = [];
  let undatedCount = 0;
  for (const [key, sources] of byKey) {
    // Past (ended) plans stay on their own day as history; only a cancelled event leaves the agenda.
    const e = events[key];
    if (!e || e.cancelled) continue;
    const sorted = [...sources].sort((a, b) => rank(a) - rank(b));
    if (e.start == null) { undatedCount += 1; continue; }
    items.push({ id: key, event: e, source: sorted[0], sources: sorted });
  }
  items.sort((a, b) => (a.event.start - b.event.start) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return { items, undatedCount };
}

/** Discover: upcoming, reservable, public events not already in My schedule. */
export function discover(events, mineKeys, now = Date.now()) {
  const mine = mineKeys instanceof Set ? mineKeys : new Set(mineKeys);
  return events
    .filter(e => e.start != null && e.start > now && !e.cancelled && !e.ended && !e.inviteOnly && !e.soldOut && !mine.has(e.key))
    .sort((a, b) => (a.start - b.start) || (a.key < b.key ? -1 : 1));
}

/** Can this event be put on the banbe Schedule by hand? */
export function canAdd(e, now = Date.now()) {
  return !!e && e.start != null && !e.cancelled && !e.ended && e.start > now;
}

// MARK: days (local calendar)

export const startOfDay = (d) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
export const addDays = (d, n) => { const x = new Date(d); return new Date(x.getFullYear(), x.getMonth(), x.getDate() + n); };
export const sameDay = (a, b) => startOfDay(a).getTime() === startOfDay(b).getTime();

/** True when the event happens (at least partly) on `day`'s calendar day. */
export function occurs(e, day) {
  if (e.start == null) return false;
  const dayStart = startOfDay(day).getTime();
  const dayEnd = addDays(dayStart, 1).getTime();
  if (e.end != null && e.end > e.start) return e.start < dayEnd && e.end > dayStart;
  return e.start >= dayStart && e.start < dayEnd;
}

export const itemsOn = (items, day) => items.filter(i => occurs(i.event, day));
export const eventsOn = (events, day) => events.filter(e => occurs(e, day));

/** First weekday for the language: Monday (1) for Vietnamese; the browser locale's own rule for English. */
export function firstWeekday(lang, locale) {
  if (lang !== 'en') return 1;
  try {
    const info = new Intl.Locale(locale || (typeof navigator !== 'undefined' ? navigator.language : 'en-US')).weekInfo
      ?? new Intl.Locale(locale || 'en-US').getWeekInfo?.();
    if (info?.firstDay) return info.firstDay % 7; // Intl: 1=Mon..7=Sun -> JS 0=Sun..6=Sat
  } catch { /* older browsers */ }
  return 0;
}

/** The 7 days of the week containing `date`, starting on `firstDay` (0=Sunday … 6=Saturday). */
export function week(date, firstDay = 1) {
  const day = startOfDay(date);
  const offset = (day.getDay() - firstDay + 7) % 7;
  const first = addDays(day, -offset);
  return Array.from({ length: 7 }, (_, i) => addDays(first, i));
}

export function busyDays(weekDays, items) {
  return new Set(weekDays.filter(d => items.some(i => occurs(i.event, d))).map(d => d.getTime()));
}

// MARK: month view

export const monthStart = (d) => { const x = new Date(d); return new Date(x.getFullYear(), x.getMonth(), 1); };
export const addMonths = (d, n) => { const m = monthStart(d); return new Date(m.getFullYear(), m.getMonth() + n, 1); };

/** Whole weeks covering the month of `date`; days outside the month are flagged, not dropped. */
export function monthGrid(date, firstDay = 1) {
  const first = monthStart(date);
  const last = new Date(first.getFullYear(), first.getMonth() + 1, 0);
  const lastWeekStart = week(last, firstDay)[0].getTime();
  const rows = [];
  for (let cursor = week(first, firstDay)[0]; cursor.getTime() <= lastWeekStart; cursor = addDays(cursor, 7)) {
    rows.push(week(cursor, firstDay).map(d => ({ date: d, inMonth: d.getMonth() === first.getMonth() })));
  }
  return rows;
}

/** How many of `events` happen on each day of `grid` (keyed by start-of-day ms). */
export function dayCounts(events, grid) {
  const out = new Map();
  for (const row of grid) for (const d of row) {
    const n = events.filter(e => occurs(e, d.date)).length;
    if (n > 0) out.set(d.date.getTime(), n);
  }
  return out;
}

/** Events of `date`'s month grouped by day, in time order — the month's agenda. */
export function monthAgenda(events, date, firstDay = 1) {
  return monthGrid(date, firstDay).flat().filter(d => d.inMonth).map(d => ({
    day: d.date,
    events: events.filter(e => occurs(e, d.date)).sort((a, b) => (a.start - b.start) || (a.key < b.key ? -1 : 1)),
  })).filter(g => g.events.length);
}

// MARK: proximity (banbe data only)

/** { kind: 'none' | 'overlaps' | 'startsNear', count } */
export function proximity(candidate, plans) {
  if (candidate.start == null) return { kind: 'none', count: 0 };
  let overlaps = 0, near = 0;
  for (const p of plans) {
    if (p.event.key === candidate.key || p.event.start == null) continue;
    const cs = candidate.start, ce = candidate.end, ps = p.event.start, pe = p.event.end;
    if (ce != null && pe != null && ce > cs && pe > ps) { if (cs < pe && ps < ce) overlaps += 1; }
    else if (Math.abs(cs - ps) < NEAR_WINDOW_MS) near += 1;
  }
  if (overlaps) return { kind: 'overlaps', count: overlaps };
  if (near) return { kind: 'startsNear', count: near };
  return { kind: 'none', count: 0 };
}

export function proximityText(p, T) {
  if (p.kind === 'overlaps') return T(`Trùng với ${p.count} kế hoạch`, `Overlaps with ${p.count} plan${p.count === 1 ? '' : 's'}`);
  if (p.kind === 'startsNear') return T(`Bắt đầu cách ${p.count} kế hoạch dưới 2 giờ`, `Starts within 2 hours of ${p.count} plan${p.count === 1 ? '' : 's'}`);
  return null;
}

// MARK: formatting

export function timeText(ms, vi, timeZone) {
  return new Date(ms).toLocaleTimeString(vi ? 'vi-VN' : 'en-US', { hour: vi ? '2-digit' : 'numeric', minute: '2-digit', hour12: !vi, ...(timeZone ? { timeZone } : {}) });
}

/** When the event's own zone differs from the browser's, its local time — e.g. "19:00 at the venue". */
export function venueTimeNote(e, vi, agendaZone = Intl.DateTimeFormat().resolvedOptions().timeZone) {
  if (e.start == null || !e.timeZone || e.timeZone === agendaZone) return null;
  const venue = timeText(e.start, vi, e.timeZone), local = timeText(e.start, vi, agendaZone);
  if (venue === local) return null;
  return vi ? `${venue} giờ tại nơi tổ chức` : `${venue} at the venue`;
}

/** Event Detail shows an event's date/time in the venue's zone (migration 195); when the viewer's zone reads it
 * differently, the same note style gives the viewer's own clock — e.g. "Venue time · 10:00, Sun 7/3 your time". */
export function viewerTimeNote(start, venueZone, vi, viewerZone = Intl.DateTimeFormat().resolvedOptions().timeZone) {
  if (start == null || !venueZone || venueZone === viewerZone) return null;
  const venue = timeText(start, vi, venueZone), local = timeText(start, vi, viewerZone);
  const dayOf = (timeZone) => new Date(start).toLocaleDateString(vi ? 'vi-VN' : 'en-US', { weekday: 'short', day: 'numeric', month: 'numeric', timeZone });
  const sameDay = dayOf(venueZone) === dayOf(viewerZone);
  if (venue === local && sameDay) return null;
  const localText = sameDay ? local : `${local}, ${dayOf(viewerZone)}`;
  return vi ? `Giờ tại nơi tổ chức · ${localText} giờ của bạn` : `Venue time · ${localText} your time`;
}

export function monthTitle(d, vi) {
  return vi ? `Tháng ${d.getMonth() + 1}, ${d.getFullYear()}` : d.toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
}

export function dayTitle(d, vi) {
  if (vi) {
    const wd = ['Chủ nhật', 'Thứ hai', 'Thứ ba', 'Thứ tư', 'Thứ năm', 'Thứ sáu', 'Thứ bảy'][d.getDay()];
    return `${wd}, ${d.getDate()} tháng ${d.getMonth() + 1}`;
  }
  return d.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
}

export function weekdayLetter(d, vi) {
  return vi ? ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'][d.getDay()] : d.toLocaleDateString('en-US', { weekday: 'narrow' });
}

/** Analytics-safe relative-day bucket for a selected date. */
export function dayBucket(d, today = new Date()) {
  const days = Math.round((startOfDay(d) - startOfDay(today)) / 864e5);
  if (days < 0) return 'past';
  if (days === 0) return 'today';
  if (days <= 7) return 'next7';
  return 'later';
}

// MARK: manual adds (this browser only, per account)

const storeKey = (uid) => `banbe.schedule.added.v1.${uid}`;
const ls = () => (typeof localStorage !== 'undefined' ? localStorage : null);

/**
 * "Add to banbe Schedule" — kept in this browser for this account only (event ids + addedAt). Does NOT sync across
 * devices or with the iOS app (that needs a backend table; see note 44).
 */
export const scheduleStore = {
  entries(uid, storage = ls()) {
    if (!uid || !storage) return [];
    try { const v = JSON.parse(storage.getItem(storeKey(uid)) || '[]'); return Array.isArray(v) ? v.filter(x => x && typeof x.key === 'string') : []; } catch { return []; }
  },
  keys(uid, storage = ls()) { return this.entries(uid, storage).map(e => e.key); },
  /** 'added' | 'alreadyAdded' */
  add(key, uid, storage = ls(), now = Date.now()) {
    const list = this.entries(uid, storage);
    if (list.some(e => e.key === key)) return 'alreadyAdded';
    try { storage?.setItem(storeKey(uid), JSON.stringify([...list, { key, addedAt: now }])); } catch { /* ignore */ }
    return 'added';
  },
  remove(key, uid, storage = ls()) {
    const list = this.entries(uid, storage).filter(e => e.key !== key);
    try { storage?.setItem(storeKey(uid), JSON.stringify(list)); } catch { /* ignore */ }
  },
};

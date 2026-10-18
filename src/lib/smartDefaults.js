// Smart defaults (note 48, principle 1 "decision fatigue") — the web twin of
// iOS Lib/SmartDefaults.swift. Pure functions; never default consent, never
// invent a price the host didn't choose, and every default stays visible and
// editable before submit.

export const COMMON_BANKS = [
  'Vietcombank', 'Techcombank', 'MB Bank', 'BIDV', 'VietinBank',
  'ACB', 'VPBank', 'TPBank', 'Agribank', 'Sacombank',
];

export const FIRST_EVENT_SEATS = 14;
export const FIRST_EVENT_TIME = '19:00';
export const PRICE_QUICK_PICKS = [0, 200000, 300000, 500000];
export const SEAT_QUICK_PICKS = [10, 20, 30, 50];
export const TIME_QUICK_PICKS = ['18:00', '18:30', '19:00', '19:30', '20:00'];
const SATURDAY = 6; // JS getUTCDay numbering, 0 = Sunday
const VN_OFFSET_MS = 7 * 60 * 60 * 1000; // Asia/Ho_Chi_Minh has no DST

/** "yyyy-MM-dd" of `now` in Vietnam. */
export function vnToday(now = new Date()) {
  return new Date(now.getTime() + VN_OFFSET_MS).toISOString().slice(0, 10);
}

function addDays(iso, n) {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** Next "yyyy-MM-dd" (Vietnam) on `weekday` (0 = Sun), at least `minDaysAhead` out. */
export function nextWeekday(weekday, now = new Date(), minDaysAhead = 2) {
  const start = addDays(vnToday(now), minDaysAhead);
  const current = new Date(`${start}T00:00:00Z`).getUTCDay();
  return addDays(start, (weekday - current + 7) % 7);
}

/**
 * Defaults for a NEW event draft. `last` = the host's most recent event
 * ({ name, event_date, event_time, price_vnd, capacity, cat_key }) or null.
 * Location is never copied: a new address must be re-confirmed via search.
 */
export function eventDraftDefaults(last, now = new Date()) {
  if (!last) {
    return { date: nextWeekday(SATURDAY, now), time: FIRST_EVENT_TIME, price: '', seats: String(FIRST_EVENT_SEATS), cats: [], sourceName: null };
  }
  const weekday = last.event_date ? new Date(`${last.event_date}T00:00:00Z`).getUTCDay() : SATURDAY;
  return {
    date: nextWeekday(weekday, now),
    time: (last.event_time || FIRST_EVENT_TIME).slice(0, 5),
    price: last.price_vnd != null ? String(last.price_vnd) : '',
    seats: String(last.capacity && last.capacity > 0 ? Math.min(last.capacity, 500) : FIRST_EVENT_SEATS),
    cats: last.cat_key ? [last.cat_key] : [],
    sourceName: last.name || null,
  };
}

export function dateQuickPicks(now = new Date()) {
  const today = vnToday(now);
  const thisSat = nextWeekday(SATURDAY, now, 0);
  return [
    { vi: 'Ngày mai', en: 'Tomorrow', date: addDays(today, 1) },
    { vi: 'Thứ Sáu này', en: 'This Fri', date: nextWeekday(5, now, 0) },
    { vi: 'Thứ Bảy này', en: 'This Sat', date: thisSat },
    { vi: 'Thứ Bảy tới', en: 'Next Sat', date: addDays(thisSat, 7) },
  ];
}

/** Middle half of paid prices of similar events; null with too few samples. */
export function similarPriceRange(prices, minSamples = 5) {
  const paid = prices.filter((p) => p > 0).sort((a, b) => a - b);
  if (paid.length < minSamples) return null;
  const lo = paid[Math.floor(paid.length / 4)];
  const hi = paid[Math.floor((paid.length * 3) / 4)];
  return [lo, Math.max(lo, hi)];
}

/** BanBeContext state patch for a set of draft defaults. */
export function createDefaultsPatch(d) {
  return {
    createEventDate: d.date, createEventTime: d.time, createPrice: d.price, createSeats: d.seats,
    createCats: d.cats, createDefaultsSource: d.sourceName, createAppliedDefaults: d,
  };
}

/** True while every defaulted field still holds its applied default. */
export function createDraftMatchesDefaults(st) {
  const d = st.createAppliedDefaults;
  if (!d) return false;
  return st.createEventDate === d.date && st.createEventTime === d.time && st.createPrice === d.price
    && st.createSeats === d.seats && JSON.stringify(st.createCats || []) === JSON.stringify(d.cats);
}

// Smart defaults (note 48, principle 1 "decision fatigue") — the web twin of
// iOS Lib/SmartDefaults.swift. Pure functions; never default consent, never
// invent a price the host didn't choose, and every default stays visible and
// editable before submit.

import { VN_TIME_ZONE, todayInZone, priceQuickPicks, priceInputText, rowCurrency } from './eventMarket.js';

export const COMMON_BANKS = [
  'Vietcombank', 'Techcombank', 'MB Bank', 'BIDV', 'VietinBank',
  'ACB', 'VPBank', 'TPBank', 'Agribank', 'Sacombank',
];

// Seats are never pre-filled (note 48 follow-up; note 50): the Tickets step shows how many guests similar events
// welcome instead of guessing a number for the host. The old FIRST_EVENT_SEATS = 14 constant was unused and is gone.
export const FIRST_EVENT_TIME = '19:00';
// VND picks; the form uses priceQuickPicks(currency) from eventMarket.js (USD picks are cents).
export const PRICE_QUICK_PICKS = priceQuickPicks('VND');
export const SEAT_QUICK_PICKS = [10, 20, 30, 50];
export const TIME_QUICK_PICKS = ['18:00', '18:30', '19:00', '19:30', '20:00'];
const SATURDAY = 6; // JS getUTCDay numbering, 0 = Sunday

/** "yyyy-MM-dd" of `now` in the event's zone (Vietnam unless the form's venue says otherwise, migration 195). */
export function vnToday(now = new Date(), timeZone = VN_TIME_ZONE) {
  return todayInZone(timeZone, now.getTime());
}

function addDays(iso, n) {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** Next "yyyy-MM-dd" (in `timeZone`, default Vietnam) on `weekday` (0 = Sun), at least `minDaysAhead` out. */
export function nextWeekday(weekday, now = new Date(), minDaysAhead = 2, timeZone = VN_TIME_ZONE) {
  const start = addDays(vnToday(now, timeZone), minDaysAhead);
  const current = new Date(`${start}T00:00:00Z`).getUTCDay();
  return addDays(start, (weekday - current + 7) % 7);
}

/**
 * Defaults for a NEW event draft. `last` = the host's most recent event
 * ({ name, event_date, event_time, price_vnd, capacity, cat_key }) or null.
 * Location is never copied: a new address must be re-confirmed via search.
 * `currency`/`timeZone` are the form's (migration 195): the last price is copied
 * only when it was in the same currency (a VND amount is never shown as dollars).
 */
export function eventDraftDefaults(last, now = new Date(), { currency = 'VND', timeZone = VN_TIME_ZONE } = {}) {
  if (!last) {
    // Seats are never pre-filled (iOS parity, note 48): the host always sets capacity.
    return { date: nextWeekday(SATURDAY, now, 2, timeZone), time: FIRST_EVENT_TIME, price: '', seats: '', cats: [], sourceName: null };
  }
  const weekday = last.event_date ? new Date(`${last.event_date}T00:00:00Z`).getUTCDay() : SATURDAY;
  const lastCurrency = rowCurrency(last);
  const samePriceCurrency = lastCurrency === (currency === 'USD' ? 'USD' : 'VND');
  return {
    date: nextWeekday(weekday, now, 2, timeZone),
    time: (last.event_time || FIRST_EVENT_TIME).slice(0, 5),
    price: last.price_vnd != null && samePriceCurrency
      ? (lastCurrency === 'USD' ? priceInputText(last.price_vnd, 'USD') : String(last.price_vnd)) : '',
    seats: '',
    cats: last.cat_key ? [last.cat_key] : [],
    sourceName: last.name || null,
  };
}

export function dateQuickPicks(now = new Date(), timeZone = VN_TIME_ZONE) {
  const today = vnToday(now, timeZone);
  const thisSat = nextWeekday(SATURDAY, now, 0, timeZone);
  return [
    { vi: 'Ngày mai', en: 'Tomorrow', date: addDays(today, 1) },
    { vi: 'Thứ Sáu này', en: 'This Fri', date: nextWeekday(5, now, 0, timeZone) },
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

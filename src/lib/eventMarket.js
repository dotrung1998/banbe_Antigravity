// Per-event market rules (migration 195): an event's own IANA time zone and its currency.
// Mirrors apps/ios/BanbeApp/Lib/EventMarket.swift and SQL event_tz_for / event_currency_for /
// resolve_event_tz; shared vectors: tests/fixtures/event-market.json. Pure module: no React.
//
// Money amounts are integers in the currency's MINOR unit: dong for VND, cents for USD
// (the `events.price_vnd` column keeps its old name but follows `events.currency`).
// Paid USD booking is not available yet (owner decision 2026-10-22); free USD events are.

import { formatVnd } from './paymentDocument.js';

export const VN_TIME_ZONE = 'Asia/Ho_Chi_Minh';

const US_STATE_ZONES = (() => {
  const m = {};
  const add = (zone, states) => { for (const [code, name] of states) { m[code.toLowerCase()] = zone; m[name.toLowerCase()] = zone; } };
  add('America/New_York', [['CT','Connecticut'],['DE','Delaware'],['DC','District of Columbia'],['FL','Florida'],['GA','Georgia'],['ME','Maine'],['MD','Maryland'],['MA','Massachusetts'],['NH','New Hampshire'],['NJ','New Jersey'],['NY','New York'],['NC','North Carolina'],['OH','Ohio'],['PA','Pennsylvania'],['RI','Rhode Island'],['SC','South Carolina'],['VT','Vermont'],['VA','Virginia'],['WV','West Virginia'],['MI','Michigan'],['IN','Indiana'],['KY','Kentucky']]);
  add('America/Chicago', [['AL','Alabama'],['AR','Arkansas'],['IL','Illinois'],['IA','Iowa'],['LA','Louisiana'],['MN','Minnesota'],['MS','Mississippi'],['MO','Missouri'],['OK','Oklahoma'],['TX','Texas'],['WI','Wisconsin'],['KS','Kansas'],['NE','Nebraska'],['SD','South Dakota'],['ND','North Dakota'],['TN','Tennessee']]);
  add('America/Denver', [['CO','Colorado'],['MT','Montana'],['NM','New Mexico'],['UT','Utah'],['WY','Wyoming'],['ID','Idaho']]);
  add('America/Phoenix', [['AZ','Arizona']]);
  add('America/Los_Angeles', [['CA','California'],['NV','Nevada'],['OR','Oregon'],['WA','Washington']]);
  add('America/Anchorage', [['AK','Alaska']]);
  add('Pacific/Honolulu', [['HI','Hawaii']]);
  return m;
})();

const countryOf = (c) => (String(c ?? '').trim() || 'VN').toUpperCase();

/** VN (or no country) -> Asia/Ho_Chi_Minh; US -> by state code/name; anything else -> null. */
export function eventTimeZone(countryCode, stateProvince) {
  switch (countryOf(countryCode)) {
    case 'VN': return VN_TIME_ZONE;
    case 'US': return US_STATE_ZONES[String(stateProvince ?? '').trim().toLowerCase()] || null;
    default: return null;
  }
}

function isValidZone(tz) {
  try { new Intl.DateTimeFormat('en-US', { timeZone: tz }); return true; } catch { return false; }
}

/** The zone the server will store: a real US zone from the client wins for US (multi-zone states). */
export function resolveEventTimeZone(countryCode, stateProvince, clientTz) {
  const tz = String(clientTz ?? '').trim();
  if (countryOf(countryCode) === 'US' && tz && (tz.startsWith('America/') || tz === 'Pacific/Honolulu') && isValidZone(tz)) return tz;
  return eventTimeZone(countryCode, stateProvince);
}

/** VN (or no country) -> VND, US -> USD, anything else -> null (unsupported). */
export function eventCurrency(countryCode) {
  const c = countryOf(countryCode);
  return c === 'VN' ? 'VND' : c === 'US' ? 'USD' : null;
}

/** A row's own currency: the stored column, else VND (every row before 195). */
export const rowCurrency = (row) => (row?.currency === 'USD' ? 'USD' : 'VND');
/** A row's own zone: the stored column, else derived from its location. */
export const rowTimeZone = (row) => row?.tz || eventTimeZone(row?.country_code ?? row?.countryCode, row?.state_province ?? row?.stateProvince) || VN_TIME_ZONE;

const groupUs = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');

/** 1250 USD -> "$12.50", 1200 -> "$12", 125000 -> "$1,250"; VND -> "150.000₫". */
export function formatMoney(amount, currency) {
  const n = Math.round(Number(amount) || 0);
  if (currency !== 'USD') return formatVnd(n);
  const dollars = Math.floor(Math.abs(n) / 100), cents = Math.abs(n) % 100;
  return `${n < 0 ? '-' : ''}$${groupUs(dollars)}${cents ? '.' + String(cents).padStart(2, '0') : ''}`;
}

/** Compact form for chips/sliders: VND "150k₫" / "1,5M₫"; USD is already short. */
export function formatMoneyShort(amount, currency) {
  if (currency === 'USD') return formatMoney(amount, 'USD');
  const v = Math.round(Number(amount) || 0);
  if (v >= 1e6) return `${(v / 1e6).toFixed(v % 1e6 === 0 ? 0 : 1).replace('.', ',')}M₫`;
  if (v >= 1000) return `${Math.round(v / 1000)}k₫`;
  return `${v}₫`;
}

/** Host-typed price -> minor units, or null when it isn't a price. VND ignores separators; USD allows 2 decimals. */
export function parsePriceInput(text, currency) {
  const s = String(text ?? '').trim();
  if (currency === 'USD') {
    const t = s.replace(/[$\s]/g, '').replace(/,/g, '');
    if (!/^\d+(\.\d{1,2})?$/.test(t)) return null;
    const [whole, frac = ''] = t.split('.');
    return parseInt(whole, 10) * 100 + parseInt((frac + '00').slice(0, 2), 10);
  }
  const digits = s.replace(/\D/g, '');
  return digits ? parseInt(digits, 10) : null;
}

/** Minor units -> what the price field shows when editing ("450.000", "12", "12.50"). */
export function priceInputText(amount, currency) {
  const n = Math.max(0, Math.round(Number(amount) || 0));
  if (currency === 'USD') return `${Math.floor(n / 100)}${n % 100 ? '.' + String(n % 100).padStart(2, '0') : ''}`;
  return n.toLocaleString('vi-VN');
}

export const PRICE_QUICK_PICKS = { VND: [0, 200000, 300000, 500000], USD: [0, 1000, 2000, 3000] };
export const priceQuickPicks = (currency) => PRICE_QUICK_PICKS[currency === 'USD' ? 'USD' : 'VND'];

/** Major units for comparing with a budget (USD budgets are whole dollars, VND budgets are dong). */
export const majorAmount = (amount, currency) => (currency === 'USD' ? (Number(amount) || 0) / 100 : Number(amount) || 0);

/** Paid booking only runs in VND today; free events book in any currency. */
export const paidBookingAvailable = (currency, amount) => currency !== 'USD' || !(Number(amount) > 0);

const partsCache = new Map();
/** {year, month, day, hour, minute, weekday (0 = Sunday)} of an instant in an IANA zone. */
export function zonedParts(ms, timeZone) {
  let f = partsCache.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', { timeZone, year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', weekday: 'short', hourCycle: 'h23' });
    partsCache.set(timeZone, f);
  }
  const p = Object.fromEntries(f.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  const hour = parseInt(p.hour, 10);
  return {
    year: parseInt(p.year, 10), month: parseInt(p.month, 10), day: parseInt(p.day, 10),
    hour: hour === 24 ? 0 : hour, minute: parseInt(p.minute, 10),
    weekday: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(p.weekday),
  };
}

/** Wall clock in a zone -> epoch ms ("2027-03-06", "19:00", "America/Los_Angeles"). Same as SQL AT TIME ZONE. */
export function wallClockToMs(date, time, timeZone) {
  const [y, mo, d] = String(date).split('-').map(Number);
  const [h, mi] = String(time).split(':').map(Number);
  if (![y, mo, d, h, mi].every(Number.isFinite)) return null;
  const guess = Date.UTC(y, mo - 1, d, h, mi);
  // Two passes handle the zone offset (and a DST boundary near the guess).
  let ms = guess;
  for (let i = 0; i < 2; i++) {
    const p = zonedParts(ms, timeZone);
    const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute);
    ms += guess - asUtc;
  }
  return ms;
}

/** "yyyy-mm-dd" of today in a zone (date-picker minimum for that venue). */
export function todayInZone(timeZone, now = Date.now()) {
  const p = zonedParts(now, timeZone);
  return `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
}

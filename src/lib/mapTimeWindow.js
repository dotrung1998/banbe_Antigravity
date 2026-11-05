// Map E+ (note 79): the day + hour window that bolds the events inside it and dims the rest. Pure, no network: the
// slider recomputes `inWindow` over the loaded rows on every step. Shared with iOS (Lib/MapTimeWindow.swift) through
// tests/fixtures/map-time-window.json.
//
// An event belongs to a SERVICE DAY: the venue's calendar day, except that 00:00 to 03:59 still counts toward the night
// before (the same rule as Home's "Tonight", dateWindowInZone). Its time is `min`, minutes since that day's 00:00, so
// 01:30 after a Friday night is Friday 25:30 (1530). The slider runs RANGE_MIN to RANGE_MAX hours in the same units.
import { zonedParts } from './eventMarket.js';

export const RANGE_MIN = 10; // slider start, 10:00
export const RANGE_MAX = 26; // slider end, 02:00 the next morning
export const RANGE_STEP = 1; // hours
export const SERVICE_DAY_START_MIN = 4 * 60; // before 04:00 is still the night before
export const TODAY_GRACE_MS = 2 * 3600 * 1000; // an event today stays in until two hours after it began
export const LATER_FROM = 17; // default start for any day that is not today

const pad = (n) => String(n).padStart(2, '0');
const ymdOf = (y, m, d) => `${y}-${pad(m)}-${pad(d)}`;
const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n));

/** "yyyy-mm-dd" shifted by `n` days (calendar arithmetic, no time zone involved). */
export function addDays(ymd, n) {
  const [y, m, d] = ymd.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + n));
  return ymdOf(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate());
}
/** 0 = Sunday … 6 = Saturday, of a "yyyy-mm-dd". */
export function weekdayOf(ymd) {
  const [y, m, d] = ymd.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

/** { dayKey, min, ms } of an instant in the venue's zone, with 00:00 to 03:59 folded into the previous day. */
export function eventSlot(ms, tz) {
  const p = zonedParts(ms, tz);
  let dayKey = ymdOf(p.year, p.month, p.day);
  let min = p.hour * 60 + p.minute;
  if (min < SERVICE_DAY_START_MIN) { dayKey = addDays(dayKey, -1); min += 1440; }
  return { dayKey, min, ms };
}

/** "19:00" for hour 19, "02:00" for hour 26. */
export const hourLabel = (n) => `${pad(n % 24)}:00`;

const WD_VI = ['Chủ nhật', 'Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy'];
const WD_EN = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const WD_VI_SHORT = ['CN', 'Th 2', 'Th 3', 'Th 4', 'Th 5', 'Th 6', 'Th 7'];
const WD_EN_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const dm = (ymd) => `${ymd.slice(8, 10)}.${ymd.slice(5, 7)}`;

/**
 * The day menu, in order: today · tomorrow · the next weekend day (the first Saturday or Sunday after tomorrow) ·
 * next week (Monday to Sunday of the week that starts after today) · all days. "Today" is the venue's service day, so
 * at 01:30 it is still last night. `days` is what `inWindow` matches; "all days" has none and switches the filter off.
 * `tz` is the zone of the place being viewed (each EVENT is still judged in its own zone through `eventSlot`).
 */
export function dayOptions(nowMs, tz, en = false) {
  const today = eventSlot(nowMs, tz).dayKey;
  const wd = weekdayOf(today);
  const short = (ymd) => (en ? WD_EN_SHORT : WD_VI_SHORT)[weekdayOf(ymd)];
  const tomorrow = addDays(today, 1);
  let weekend = addDays(today, 2);
  for (let k = 2; k <= 8; k++) {
    const d = addDays(today, k);
    if (weekdayOf(d) === 6 || weekdayOf(d) === 0) { weekend = d; break; }
  }
  const untilMonday = (8 - wd) % 7 || 7;
  const monday = addDays(today, untilMonday);
  const week = Array.from({ length: 7 }, (_, i) => addDays(monday, i));
  return [
    { key: 'today', label: en ? 'Today' : 'Hôm nay', sub: short(today), days: [today] },
    { key: 'tomorrow', label: en ? 'Tomorrow' : 'Mai', sub: short(tomorrow), days: [tomorrow] },
    { key: 'weekend', label: (en ? WD_EN : WD_VI)[weekdayOf(weekend)], sub: dm(weekend), days: [weekend] },
    { key: 'nextWeek', label: en ? 'Next week' : 'Tuần sau', sub: `${dm(week[0])}–${dm(week[6])}`, days: week },
    { key: 'all', label: en ? 'All days' : 'Tất cả ngày', sub: '', days: [] },
  ];
}

/** The window a day choice starts with: today from the next full hour, other days 17:00, always to 02:00; all days is off. */
export function defaultWindow(key, nowMs, tz) {
  const todayKey = eventSlot(nowMs, tz).dayKey;
  const opt = dayOptions(nowMs, tz).find((o) => o.key === key) || dayOptions(nowMs, tz)[4];
  if (opt.key === 'all') return { on: false, key: 'all', days: [], from: RANGE_MIN, to: RANGE_MAX, todayKey };
  const from = opt.key === 'today' ? clamp(Math.ceil(eventSlot(nowMs, tz).min / 60), RANGE_MIN, RANGE_MAX - 1) : LATER_FROM;
  return { on: true, key: opt.key, days: opt.days, from, to: RANGE_MAX, todayKey };
}

/** Moves one knob to `hour` (whole hours), keeping the range at least one step wide and inside RANGE_MIN to RANGE_MAX. */
export function moveKnob(win, which, hour) {
  const h = clamp(Math.round(hour / RANGE_STEP) * RANGE_STEP, RANGE_MIN, RANGE_MAX);
  return which === 'from' ? { ...win, from: Math.min(h, win.to - RANGE_STEP) } : { ...win, to: Math.max(h, win.from + RANGE_STEP) };
}

/** Is the slot inside the window? Off = everything is. Today's events stay in until TODAY_GRACE_MS after they began. */
export function inWindow(slot, win, nowMs) {
  if (!win || !win.on) return true;
  if (!win.days.includes(slot.dayKey)) return false;
  if (slot.min < win.from * 60 || slot.min >= win.to * 60) return false;
  if (slot.dayKey === win.todayKey && slot.ms < nowMs - TODAY_GRACE_MS) return false;
  return true;
}

/** Home's date filter ("today", "tonight", "tomorrow", "weekend", anything else) as the Map's window. */
export function windowFromHomeDate(date, nowMs, tz) {
  if (date === 'today') return defaultWindow('today', nowMs, tz);
  if (date === 'tonight') return { ...defaultWindow('today', nowMs, tz), from: LATER_FROM };
  if (date === 'tomorrow') return defaultWindow('tomorrow', nowMs, tz);
  if (date === 'weekend') return defaultWindow('weekend', nowMs, tz);
  return defaultWindow('all', nowMs, tz);
}

/** "Hôm nay · 19:00–02:00", or "Mọi ngày" when off. `dayLabel` is the chosen option's label. */
export function windowSummary(win, dayLabel, en = false) {
  if (!win || !win.on) return en ? 'Any day' : 'Mọi ngày';
  return `${dayLabel} · ${hourLabel(win.from)}–${hourLabel(win.to)}`;
}

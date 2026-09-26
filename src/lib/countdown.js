import { useEffect, useState } from 'react';

// Shared countdown formatting + a ticking clock, used everywhere a payment
// deadline is shown: Home's banners, the ticket screen, the payment screen,
// and the organizer's verification queue. One implementation so a PHASE 1
// hold and a PHASE 2 SLA never render their remaining time slightly
// differently from one screen to the next.

/** ms -> "12:04" (or "1:02:04" past an hour). Never negative. */
export function formatCountdown(ms) {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const mm = String(h > 0 ? m : m).padStart(2, '0');
  const ss = String(s).padStart(2, '0');
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

/**
 * Ticks a `now` timestamp once a second while `active` is true, and freezes
 * (stops re-rendering) as soon as it isn't — a countdown that isn't showing
 * has no business waking the component tree every second.
 */
export function useTicking(active) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!active) return undefined;
    setNow(Date.now());
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [active]);
  return now;
}

/** Milliseconds remaining until `iso`, floored at 0. */
export function msUntil(iso, now = Date.now()) {
  if (!iso) return 0;
  return Math.max(0, new Date(iso).getTime() - now);
}

// Retention roadmap P1 ("Cuối tuần này") — the applicable weekend window,
// computed against Asia/Ho_Chi_Minh wall-clock time specifically (the
// roadmap's own requirement), not the browser's local zone, since a host or
// guest could load Home from anywhere. ICT has no DST and a fixed +07:00
// offset year-round, so this is a plain millisecond shift rather than a
// full Intl/timezone dependency.
const ICT_OFFSET_MS = 7 * 3600 * 1000;

/** `nowMs`'s wall-clock date/day-of-week in Asia/Ho_Chi_Minh. */
function ictDateParts(nowMs) {
  const shifted = new Date(nowMs + ICT_OFFSET_MS);
  return { y: shifted.getUTCFullYear(), mo: shifted.getUTCMonth(), d: shifted.getUTCDate(), dow: shifted.getUTCDay() };
}

/** An Asia/Ho_Chi_Minh wall-clock instant -> the real UTC epoch ms it
 * denotes (the inverse of ictDateParts' shift). `Date.UTC` normalizes an
 * out-of-range day (e.g. day 32) into the next month on its own. */
function ictWallToUtcMs(y, mo, d, h, mi, s) {
  return Date.UTC(y, mo, d, h, mi, s) - ICT_OFFSET_MS;
}

/**
 * "This weekend" (Sat 00:00 -> Sun 23:59:59, Asia/Ho_Chi_Minh), as an ISO
 * range for a `starts_at` query: Mon–Fri resolves to the upcoming Sat/Sun;
 * Sat/Sun itself resolves to the CURRENT one still under way, per the
 * roadmap's "next applicable weekend" (a weekend already in progress is
 * still applicable, not skipped to the following one). `start` is clamped
 * to `nowMs` so a Saturday afternoon load never lists a Saturday-morning
 * slot as still upcoming.
 */
export function thisWeekendWindow(nowMs = Date.now()) {
  const { y, mo, d, dow } = ictDateParts(nowMs);
  const daysToSat = dow === 6 ? 0 : dow === 0 ? -1 : 6 - dow;
  const satStartMs = ictWallToUtcMs(y, mo, d + daysToSat, 0, 0, 0);
  const sunEndMs = ictWallToUtcMs(y, mo, d + daysToSat + 1, 23, 59, 59);
  return {
    start: new Date(Math.max(satStartMs, nowMs)).toISOString(),
    end: new Date(sunEndMs).toISOString(),
  };
}

/**
 * Out of a list of bookings in a given payment_state, the one whose
 * `dateField` deadline is soonest AND still in the future. A booking whose
 * deadline has already lapsed is excluded rather than sorted last — it is
 * moments away from being swept to 'expired' by the cron job, and showing a
 * banner for a hold that is effectively already gone is worse than showing
 * none.
 */
export function pickSoonest(bookings, phase, dateField) {
  const now = Date.now();
  return (bookings || [])
    .filter(b => b.payment_state === phase && msUntil(b[dateField], now) > 0)
    .sort((a, b) => new Date(a[dateField]) - new Date(b[dateField]))[0] || null;
}

function hoursSince(iso, now) {
  if (!iso) return null;
  return Math.max(0, (now - new Date(iso).getTime()) / 3600000);
}

// 2026-09-25 fix pass — root cause of "wrong displayed months": every
// event's `when`/`where`/`meta`/`until`/`untilLabel`/`startDate` came
// ONLY from `src/data/events.js`'s static demo catalogue (hardcoded
// July-2026 strings, computed once against a hardcoded `TODAY` constant)
// — `liveEventOverrides` only ever patched `cancelled`/`endedHoursAgo`,
// never the DISPLAY date itself, so the real `events.starts_at` row this
// app already fetches (`loadHomeLiveEvents`/`loadLiveEventStatus`) was
// driving live/ended status correctly while every VISIBLE date string
// stayed frozen at the catalogue's own July dates, regardless of what the
// real row actually said. Fixed here, not by touching the catalogue's
// cosmetic fields (photos/galleries/descriptions stay static by design —
// see events.js's own top comment) — only the parts that are genuinely
// DATA, not decoration.
const VN_WEEKDAY_SHORT = ['CN', 'Th 2', 'Th 3', 'Th 4', 'Th 5', 'Th 6', 'Th 7'];
const VN_WEEKDAY_LONG = ['Chủ Nhật', 'Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy'];

function pad2(n) { return String(n).padStart(2, '0'); }

/** A real Date -> the same three fragments events.js's own ROWS baked in
 * by hand (dayShort/dayLong/time), computed from the ACTUAL instant
 * instead of a hardcoded string — so a real September/November
 * `starts_at` reads as September/November, not whatever month the demo
 * catalogue happened to hardcode for that event key. Exported for Home's
 * "Cuối tuần này" section (retention roadmap P1) — those cards have no
 * static catalogue counterpart to merge onto, so they call this directly
 * instead of going through liveEventOverrides below. */
export function formatVnEventDate(date) {
  const dow = date.getDay();
  return {
    weekdayShort: VN_WEEKDAY_SHORT[dow],
    dayMonth: `${pad2(date.getDate())}.${pad2(date.getMonth() + 1)}`,
    dayLong: `${VN_WEEKDAY_LONG[dow]}, ${date.getDate()} tháng ${date.getMonth() + 1}`,
    time: `${pad2(date.getHours())}:${pad2(date.getMinutes())}`,
  };
}

/** Whole-day difference between two instants, compared at local midnight
 * — same semantics `data/events.js`'s own (now-removed-from-the-critical-
 * path) `relDays()` already used, just against the REAL current date
 * instead of a hardcoded `TODAY`. */
function relDaysFromNow(target, now) {
  const startOfTarget = new Date(target); startOfTarget.setHours(0, 0, 0, 0);
  const startOfNow = new Date(now); startOfNow.setHours(0, 0, 0, 0);
  return Math.round((startOfTarget - startOfNow) / 86400000);
}

function untilLabelText(n) {
  return n === 0 ? 'Hôm nay' : n === 1 ? 'Ngày mai' : n < 0 ? '' : 'Còn ' + n + ' ngày';
}

/** Replaces the trailing ` ▪︎ `-joined segment(s) of a static catalogue
 * string with live values, keeping everything before them (area/km/etc,
 * which have no live equivalent and aren't the bug here) untouched. */
function replaceTrailingSegments(str, count, replacements) {
  if (typeof str !== 'string') return str;
  const parts = str.split(' ▪︎ ');
  if (parts.length < count) return str;
  parts.splice(parts.length - count, count, ...replacements);
  return parts.join(' ▪︎ ');
}

/** The live-date portion of `liveEventOverrides`' return value — `null`
 * when `liveEvent.starts_at` isn't set (an event created before that
 * column was wired up), in which case the caller keeps the static
 * catalogue's own date text exactly as before. */
function liveDateOverrides(liveEvent, staticEv, now) {
  if (!liveEvent?.starts_at) return {};
  const startsAt = new Date(liveEvent.starts_at);
  if (Number.isNaN(startsAt.getTime())) return {};
  const { weekdayShort, dayMonth, dayLong, time } = formatVnEventDate(startsAt);
  const until = relDaysFromNow(startsAt, now);
  const overrides = {
    startDate: startsAt,
    when: `${weekdayShort}, ${dayMonth} ▪︎ ${time}`,
    until,
    untilLabel: untilLabelText(until),
  };
  if (staticEv?.meta) overrides.meta = replaceTrailingSegments(staticEv.meta, 1, [`${weekdayShort}, ${time}`]);
  if (staticEv?.where) overrides.where = replaceTrailingSegments(staticEv.where, 2, [dayLong, time]);
  return overrides;
}

/**
 * Reconciles a real `events` row's own status against the current clock,
 * overriding the static demo catalogue's hardcoded cancelled/ended flags
 * with a live read — so an organizer cancelling an event, or the daily
 * `goc_mark_past_events` sweep marking one 'ended' 12h after its start, is
 * reflected the moment this client re-fetches the row instead of never
 * (the static catalogue is fixed at build time and can't otherwise learn
 * about either).
 *
 * `staticEv` (the same event's row from the static catalogue) is only used
 * as a cosmetic fallback for the "N hours ago" text when the real row has
 * no timestamp of its own to compute one from (starts_at/cancelled_at are
 * both optional columns, unset for events created before either was wired
 * up) — never for the cancelled/ended booleans themselves, which always
 * come from the live `status` column so a change to it is never missed.
 *
 * Returns null when there is no real row to read at all (e.g. a
 * client-side-only event preview mid-creation) — the caller should leave
 * the static catalogue untouched in that case rather than treat "no data"
 * as "not ended".
 */
export function liveEventOverrides(liveEvent, staticEv, now = Date.now()) {
  if (!liveEvent) return null;
  // 2026-09-25 fix pass — the live DATE (when/where/meta/until/startDate),
  // merged in regardless of cancelled/ended/live branch below: a
  // cancelled or ended event still has a real `starts_at` worth showing
  // correctly, same as a live one. See `liveDateOverrides`'s own comment
  // for the full root-cause writeup.
  const dateOverrides = liveDateOverrides(liveEvent, staticEv, now);
  if (liveEvent.status === 'cancelled') {
    return {
      ...dateOverrides,
      cancelled: true,
      cancelledHoursAgo: hoursSince(liveEvent.cancelled_at, now) ?? staticEv?.cancelledHoursAgo ?? 0,
      endedHoursAgo: null,
    };
  }
  if (liveEvent.status === 'ended') {
    return {
      ...dateOverrides,
      cancelled: false,
      cancelledHoursAgo: null,
      endedHoursAgo: hoursSince(liveEvent.starts_at, now) ?? staticEv?.endedHoursAgo ?? 0,
    };
  }
  // 'live' (or 'draft'/'review', which shouldn't be publicly reachable at
  // all) — the organizer hasn't cancelled it and no sweep has marked it
  // ended, so as far as this row is concerned, neither has happened.
  return { ...dateOverrides, cancelled: false, cancelledHoursAgo: null, endedHoursAgo: null };
}

// When an event ends (migration 220, note 82): a host-set end time (events.end_time, wall clock in the venue's zone
// like event_time; an end at or before the start means the next day) or "open-ended" (events.end_open). Neither set
// = not stated (events created before 220), and the page shows the start time alone. Pure, unit-tested
// (tests/unit/eventEnd.test.mjs). Copy: { vi, en } pairs, no dash/semicolon idea separators (note 57).

import { zonedParts, wallClockToMs, VN_TIME_ZONE } from './eventMarket.js';

const L = (vi, en) => ({ vi, en });
const hm = (t) => {
  const m = /^(\d{1,2}):(\d{2})/.exec(String(t || ''));
  return m ? Number(m[1]) * 60 + Number(m[2]) : null;
};
const fmt = (mins) => `${String(Math.floor(mins / 60) % 24).padStart(2, '0')}:${String(mins % 60).padStart(2, '0')}`;

/** 'time' | 'open' | null from a row's end_time / end_open. */
export function endMode(endTime, endOpen) {
  if (endOpen) return 'open';
  return hm(endTime) != null ? 'time' : null;
}

/** True when the end time is at or before the start, i.e. after midnight. */
export function endsNextDay(start, end) {
  const s = hm(start), e = hm(end);
  return s != null && e != null && e <= s;
}

/** The create form's default end: three hours after the start. */
export function defaultEndTime(start) {
  const s = hm(start);
  return s == null ? '' : fmt(s + 180);
}

/** Validation for the create form: an end time is needed in 'time' mode, and it can't equal the start. */
export function endError(mode, start, end) {
  if (mode === 'open') return null;
  if (mode !== 'time') return 'missing';
  if (hm(end) == null) return 'missing';
  if (hm(start) != null && hm(start) === hm(end)) return 'same';
  return null;
}

/**
 * The time line: "16:00 – 22:00", "22:00 – 02:00 (next day)", "16:00 · open-ended", or "16:00" when the end is not
 * stated. Returns { vi, en }.
 */
export function timeRange(start, endTime, endOpen) {
  const s = String(start || '').slice(0, 5);
  if (!s) return null;
  const mode = endMode(endTime, endOpen);
  if (mode === 'open') return L(`${s} · chưa có giờ kết thúc`, `${s} · open-ended`);
  if (mode === 'time') {
    const e = String(endTime).slice(0, 5);
    const next = endsNextDay(s, e);
    return L(`${s} – ${e}${next ? ' (hôm sau)' : ''}`, `${s} – ${e}${next ? ' (next day)' : ''}`);
  }
  return L(s, s);
}

/** The note 38 window used when an event states no end: 12 hours after its start. */
export const OVER_FALLBACK_MS = 12 * 3600000;

const pad2 = (n) => String(n).padStart(2, '0');

/**
 * The instant an event is over, in ms — ONE rule for every surface (audit 2026-11-19 row 6):
 *   * a host-set `endTime` (events.end_time, wall clock in the venue's zone; at or before the start means the next
 *     venue day), or
 *   * the note 38 fallback, 12 h after the start, when the end is open-ended or not stated.
 * `ev` may carry `startsAt`/`starts_at` (ms, ISO string or Date), `tz`, `endTime`/`end_time` and `endOpen`/`end_open`.
 * Null when the start is unknown (then nothing claims the event is over).
 */
export function eventEndsAt(ev) {
  const raw = ev?.startsAt ?? ev?.starts_at ?? ev?.startDate;
  const startMs = raw instanceof Date ? raw.getTime() : typeof raw === 'number' ? raw : Date.parse(raw);
  if (!Number.isFinite(startMs)) return null;
  const rawEnd = ev?.endTime ?? ev?.end_time;
  const endText = rawEnd != null ? String(rawEnd).slice(0, 5) : '';
  if (endMode(rawEnd, ev?.endOpen ?? ev?.end_open) === 'time') {
    const tz = ev?.tz || VN_TIME_ZONE;
    const p = zonedParts(startMs, tz);
    const day = [p.year, p.month, p.day];
    const startHm = `${pad2(p.hour)}:${pad2(p.minute)}`;
    const at = ([y, mo, d]) => `${y}-${pad2(mo)}-${pad2(d)}`;
    const same = wallClockToMs(at(day), endText, tz);
    if (same == null) return startMs + OVER_FALLBACK_MS;
    if (!endsNextDay(startHm, endText)) return same;
    const next = new Date(Date.UTC(day[0], day[1] - 1, day[2] + 1));
    return wallClockToMs(at([next.getUTCFullYear(), next.getUTCMonth() + 1, next.getUTCDate()]), endText, tz) ?? same;
  }
  return startMs + OVER_FALLBACK_MS;
}

/** True once the event is past its end (status 'ended' counts regardless of the clock). */
export function isEventOver(ev, now = Date.now()) {
  if (!ev) return false;
  const status = ev.status ?? ev.eventStatus;
  if (status === 'ended') return true;
  if (status === 'cancelled' || status === 'removed' || status === 'draft' || status === 'review') return false;
  const end = eventEndsAt(ev);
  return end != null && now >= end;
}

/** Length in minutes (crossing midnight), or null. */
export function durationMinutes(start, end) {
  const s = hm(start), e = hm(end);
  if (s == null || e == null) return null;
  return e > s ? e - s : e + 1440 - s;
}

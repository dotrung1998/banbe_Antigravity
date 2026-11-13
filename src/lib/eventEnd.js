// When an event ends (migration 220, note 82): a host-set end time (events.end_time, wall clock in the venue's zone
// like event_time; an end at or before the start means the next day) or "open-ended" (events.end_open). Neither set
// = not stated (events created before 220), and the page shows the start time alone. Pure, unit-tested
// (tests/unit/eventEnd.test.mjs). Copy: { vi, en } pairs, no dash/semicolon idea separators (note 57).

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
  if (mode === 'open') return L(`${s} · không giờ kết thúc`, `${s} · open-ended`);
  if (mode === 'time') {
    const e = String(endTime).slice(0, 5);
    const next = endsNextDay(s, e);
    return L(`${s} – ${e}${next ? ' (hôm sau)' : ''}`, `${s} – ${e}${next ? ' (next day)' : ''}`);
  }
  return L(s, s);
}

/** Length in minutes (crossing midnight), or null. */
export function durationMinutes(start, end) {
  const s = hm(start), e = hm(end);
  if (s == null || e == null) return null;
  return e > s ? e - s : e + 1440 - s;
}

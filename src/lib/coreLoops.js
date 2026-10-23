// Phase 2-3 core loops (docs/impl/phase2-core-loops.md, phase3-extras.md L5): the pure rules behind notification
// routing, the guest's private feedback, the host recap and "Run it again". Mirrored by
// apps/ios/BanbeApp/Lib/CoreLoops.swift; shared vectors in tests/fixtures/core-loops.json
// (tests/unit/coreLoops.test.mjs and BanbeAppTests/CoreLoopsTests.swift) — change all three together.
//
// The server (migrations 199/200) owns every decision that matters: who may answer, for how long, when the host may
// see anything. These helpers only shape what the screen says, never a public rating, never a countdown.

/**
 * Where a tapped notification goes: { route, id } or null for a kind this file doesn't own.
 * route: 'ticket' (booking id) | 'eventRecap' | 'hostRecap' | 'event' (event id) | 'following' | 'thisWeekend'.
 */
export function notificationRoute(kind, data = {}) {
  const d = data || {};
  switch (kind) {
    case 'event_reminder_day':
    case 'event_reminder_soon':
      return d.booking_id ? { route: 'ticket', id: String(d.booking_id) } : null;
    case 'event_recap':
      return d.event_id ? { route: 'eventRecap', id: String(d.event_id) } : null;
    case 'host_event_recap':
      return d.event_id ? { route: 'hostRecap', id: String(d.event_id) } : null;
    case 'follow_alert': {
      // One new event opens it; a bundle of several opens the list of hosts you follow.
      const n = Number(d.count ?? 1);
      if (Number.isFinite(n) && n > 1) return { route: 'following', id: null };
      return d.event_id ? { route: 'event', id: String(d.event_id) } : { route: 'following', id: null };
    }
    case 'weekly_digest':
      return { route: 'thisWeekend', id: null };
    default:
      return null;
  }
}

/** Kinds this file routes (the notification list gives them their own icons). */
export const CORE_LOOP_KINDS = ['event_reminder_day', 'event_reminder_soon', 'event_recap', 'host_event_recap', 'follow_alert', 'weekly_digest'];

// ---------------------------------------------------------------- Run it again

const addDays = (iso, n) => {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};
const weekdayOf = (iso) => new Date(`${iso}T00:00:00Z`).getUTCDay();
const isIsoDate = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(`${s}T00:00:00Z`));

/** Same rule as smart defaults (note 48): a new date is at least this many days out, so there is time to promote. */
export const RUN_AGAIN_MIN_DAYS_AHEAD = 2;

/**
 * "Run it again": the new event's date and time. One week after the original; when that is already too close or in
 * the past, the first same weekday at least 2 days after `today`. Time is kept. All dates are "yyyy-MM-dd" in the
 * event's own zone (`today` too), so the rule never depends on the device clock's zone.
 */
export function runItAgainDate({ eventDate, eventTime, today }) {
  const time = (eventTime || '').slice(0, 5) || null;
  if (!isIsoDate(today)) return { date: null, time };
  const earliest = addDays(today, RUN_AGAIN_MIN_DAYS_AHEAD);
  if (!isIsoDate(eventDate)) return { date: earliest, time };
  const weekLater = addDays(eventDate, 7);
  if (weekLater >= earliest) return { date: weekLater, time };
  return { date: addDays(earliest, (weekdayOf(eventDate) - weekdayOf(earliest) + 7) % 7), time };
}

// ---------------------------------------------------------------- feedback (L2, private to the host)

export const FEEDBACK = { noteMax: 500, ratings: [1, -1], openDays: 14, hostMinResponses: 3 };

/** Characters as Postgres length() counts them (code points), so the counter and the server agree. */
export function noteLength(note) {
  return [...String(note ?? '')].length;
}

/** Cuts a note to the limit, by code point (never splits an emoji in half). */
export function clampNote(note) {
  const chars = [...String(note ?? '')];
  return chars.length > FEEDBACK.noteMax ? chars.slice(0, FEEDBACK.noteMax).join('') : String(note ?? '');
}

export function canSaveFeedback(rating, note) {
  return FEEDBACK.ratings.includes(rating) && noteLength(note) <= FEEDBACK.noteMax;
}

/** The answer window the server applies (14 days after the start). The server still decides; this only avoids
 *  offering a form that can't be saved. Unknown start = open (let the server say). */
export function feedbackWindowOpen(startsAt, now = Date.now()) {
  const t = startsAt == null ? NaN : new Date(startsAt).getTime();
  if (!Number.isFinite(t)) return true;
  return now - t <= FEEDBACK.openDays * 86400000;
}

export const FEEDBACK_PRIVACY = {
  vi: 'Chỉ host thấy, dưới dạng số đếm và ghi chú không kèm tên, khi có từ 3 người trả lời.',
  en: 'Only the host sees this, as counts and unnamed notes, once 3 or more guests have answered.',
};

/** submit_event_feedback's error codes -> what the guest reads. */
export function feedbackErrorText(code) {
  switch (code) {
    case 'NOT_OPEN': return { vi: 'Đã đóng phần cảm nhận cho sự kiện này.', en: 'Feedback for this event is closed.' };
    case 'NO_TICKET': return { vi: 'Chỉ khách có vé mới gửi được cảm nhận.', en: 'Only guests with a ticket can send feedback.' };
    case 'INVALID_VALUE': return { vi: 'Chọn 👍 hoặc 👎, ghi chú tối đa 500 ký tự.', en: 'Pick 👍 or 👎, and keep the note to 500 characters.' };
    case 'NOT_AVAILABLE': return { vi: 'Tính năng này đang tạm tắt.', en: 'This is turned off for now.' };
    case 'AUTH_REQUIRED': return { vi: 'Hãy đăng nhập lại.', en: 'Please sign in again.' };
    default: return { vi: 'Không lưu được. Thử lại nhé.', en: "Couldn't save. Try again." };
  }
}

// ---------------------------------------------------------------- host recap (L3)

/**
 * The host's view of feedback (get_event_feedback_summary / get_host_event_recap.feedback): hidden below 3 answers,
 * otherwise counts and notes without names. Anything malformed reads as hidden.
 */
export function hostFeedbackView(fb) {
  const responses = Number(fb?.responses) || 0;
  if (!fb || fb.hidden !== false || responses < FEEDBACK.hostMinResponses) return { hidden: true, responses };
  const notes = Array.isArray(fb.notes) ? fb.notes.filter(n => typeof n === 'string' && n.trim()).map(n => n.trim()) : [];
  return { hidden: false, responses, up: Number(fb.up) || 0, down: Number(fb.down) || 0, notes };
}

export const HOST_FEEDBACK_HIDDEN = {
  vi: 'Cảm nhận hiện khi có từ 3 khách trả lời.',
  en: 'Feedback appears once 3 guests have answered.',
};

/** get_host_event_recap's numbers, defensively (a missing key is 0, capacity may be unknown). */
export function hostRecapStats(r) {
  const n = (v) => (Number.isFinite(Number(v)) ? Number(v) : 0);
  const cap = r?.capacity == null || !Number.isFinite(Number(r.capacity)) ? null : Number(r.capacity);
  return {
    confirmedSeats: n(r?.confirmed_seats), capacity: cap, checkedIn: n(r?.checked_in),
    newFollowers: n(r?.new_followers), repeatGuests: n(r?.repeat_guests), photos: n(r?.photos),
  };
}

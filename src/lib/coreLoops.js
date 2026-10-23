// Phase 2-3 core loops (docs/impl/phase2-core-loops.md, phase3-extras.md L5): the pure rules behind notification
// routing, the guest's private feedback, the host recap and "Run it again". Mirrored by
// apps/ios/BanbeApp/Lib/CoreLoops.swift; shared vectors in tests/fixtures/core-loops.json
// (tests/unit/coreLoops.test.mjs and BanbeAppTests/CoreLoopsTests.swift) — change all three together.
//
// The server (migrations 199/200) owns every decision that matters: who may answer, for how long, when the host may
// see anything. These helpers only shape what the screen says, never a public rating, never a countdown.

import { zonedParts, VN_TIME_ZONE } from './eventMarket.js';

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

// ---------------------------------------------------------------- L6 intent For You (switch intent_foryou)

/**
 * Home's For You title and its one "because you said…" line, from the goals the person STATED in onboarding (their
 * own answers in the owner-only preferences, never inferred from behaviour, never a match score). Ranking is not
 * touched. Shared vectors: core-loops.json `intentTitles`.
 */
export const INTENT_TITLES = {
  meet_people: { vi: 'Gặp gỡ mọi người', en: 'Meet new people', whyVi: 'Vì bạn muốn gặp gỡ mọi người', whyEn: 'Because you said you want to meet people' },
  learn: { vi: 'Học điều mới', en: 'Learn something new', whyVi: 'Vì bạn muốn học hỏi', whyEn: 'Because you said you want to learn something' },
  experiences: { vi: 'Trải nghiệm đáng nhớ', en: 'Experiences to enjoy', whyVi: 'Vì bạn muốn tận hưởng trải nghiệm', whyEn: 'Because you said you want to enjoy experiences' },
  networking: { vi: 'Kết nối nghề nghiệp', en: 'Grow your network', whyVi: 'Vì bạn muốn kết nối nghề nghiệp', whyEn: 'Because you said you want professional networking' },
};
export const DEFAULT_FOR_YOU_TITLE = { vi: 'Dành cho bạn', en: 'For You', whyVi: null, whyEn: null };

/** `goals` = declaredGoals(prefs) (stored order). The first goal this table knows wins; none -> plain "For You". */
export function intentTitle(goals) {
  const goal = (Array.isArray(goals) ? goals : []).find(g => typeof g === 'string' && Object.hasOwn(INTENT_TITLES, g));
  return goal ? { goal, ...INTENT_TITLES[goal] } : { goal: null, ...DEFAULT_FOR_YOU_TITLE };
}

// ---------------------------------------------------------------- L7 day-of card (switch live_activity)

/** True on the event's own calendar day in the VENUE's zone (not the viewer's), the day the ticket is one tap away. */
export function isEventLocalDay(startMs, nowMs, timeZone) {
  if (!Number.isFinite(startMs) || !Number.isFinite(nowMs)) return false;
  const tz = timeZone || VN_TIME_ZONE;
  const a = zonedParts(startMs, tz), b = zonedParts(nowMs, tz);
  return a.year === b.year && a.month === b.month && a.day === b.day;
}

// ---------------------------------------------------------------- L8 market sharing (switch market_share)

/** Which extra share action an event gets: 'VN' (copy for Zalo), 'US' (Text a friend) or null (system share only). */
export function shareMarket(countryCode) {
  const c = String(countryCode || '').trim().toUpperCase();
  return c === 'VN' || c === 'US' ? c : null;
}

const pad2 = (n) => String(n).padStart(2, '0');
const VN_WD = ['CN', 'Th 2', 'Th 3', 'Th 4', 'Th 5', 'Th 6', 'Th 7'];
const EN_WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const EN_MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/**
 * The `when` of an invite, in the venue's zone. VN: the event card's own "Th 7, 06.03 ▪︎ 19:00"; US: "Sat, Mar 6 ▪︎
 * 7:00 PM" (the card has no US format, so this is the US reading of the same two parts).
 */
export function shareWhen(startMs, timeZone, market) {
  if (!Number.isFinite(startMs)) return '';
  const p = zonedParts(startMs, timeZone || VN_TIME_ZONE);
  if (market === 'US') {
    const h = p.hour % 12 || 12;
    return `${EN_WD[p.weekday]}, ${EN_MON[p.month - 1]} ${p.day} ▪︎ ${h}:${pad2(p.minute)} ${p.hour < 12 ? 'AM' : 'PM'}`;
  }
  return `${VN_WD[p.weekday]}, ${pad2(p.day)}.${pad2(p.month)} ▪︎ ${pad2(p.hour)}:${pad2(p.minute)}`;
}

/** "name ▪︎ when" + newline + url (core-loops.json `shareText`). An unknown `when` leaves just the name. */
export function shareInviteText({ name, when, url }) {
  const head = [String(name || '').trim(), String(when || '').trim()].filter(Boolean).join(' ▪︎ ');
  return `${head}\n${url || ''}`;
}

/** `sms:` link with the invite as its body (no recipient, so the person picks who). */
export function smsInviteHref(text) {
  return `sms:&body=${encodeURIComponent(String(text || ''))}`;
}

/** Toast after "Copy invite for Zalo". There is no verified Zalo share URL, so the person pastes it. */
export const ZALO_COPIED = { vi: 'Đã chép. Dán vào Zalo nhé.', en: 'Copied. Paste it in Zalo.' };

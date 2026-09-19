// Notification-bell presentation helpers — kept separate from GocContext.jsx
// so the row renderer (Notifications.jsx) doesn't need per-kind branching
// scattered through its JSX. Mirrors apps/ios/BanbeApp/Lib/NotificationPresentation.swift.
import { EVENTS } from '../data/events.js';

// Kinds where the notification is fundamentally ABOUT A SPECIFIC GUEST from
// the organizer's own perspective — these prefer the guest's own avatar
// (profiles.avatar_url, joined via data.booking_id -> bookings.user_id) over
// the event's cover photo. Every other kind (about an event from the
// guest's own perspective, or with no specific actor at all) prefers the
// event's cover photo, falling back to a plain glyph when neither resolves.
const GUEST_AVATAR_KINDS = new Set([
  'booking_requested',
  'payment_awaiting_verification',
  'receipt_requested',
  'payment_verification_nudge',
  'guest_renamed',
]);

/**
 * Resolves what a notification row's left-side circle should show.
 * `maps` = { bookingById, eventPhotoByEventId, avatarByUserId } — the three
 * lookup tables loadNotifications() batch-fetches once per screen-open
 * (see GocContext.jsx). Returns `{ type: 'image', url }` or `{ type: 'fallback' }`
 * — the caller decides how to render the fallback (this never returns a
 * broken/missing image URL).
 */
export function avatarSourceFor(n, { bookingById, eventPhotoByEventId, avatarByUserId }, accountType) {
  const booking = n.data?.booking_id ? bookingById?.[n.data.booking_id] : null;
  // dispute_message goes to whichever party didn't send it — an organizer
  // receiving one is being told about a specific guest's message, so the
  // guest's avatar reads the same way booking_requested's does; a guest
  // receiving one is being told about their own event, so it falls through
  // to the ordinary event-photo case below like everything else.
  const wantsGuestAvatar = GUEST_AVATAR_KINDS.has(n.kind) || (n.kind === 'dispute_message' && accountType === 'organizer');
  if (wantsGuestAvatar && booking?.user_id && avatarByUserId?.[booking.user_id]) {
    return { type: 'image', url: avatarByUserId[booking.user_id] };
  }
  const eventId = n.data?.event_id || booking?.event_id;
  if (eventId && eventPhotoByEventId?.[eventId]) {
    return { type: 'image', url: eventPhotoByEventId[eventId] };
  }
  // 2026-09-18 follow-up (BUG 1): `event_photos` has never had a single
  // real row written to it by any code path in this app — confirmed by
  // repo-wide grep, the only inserts anywhere are migration 010's one-time
  // seed for 4 demo events (evt_001-evt_004). Every real event a real
  // account books against is a catalogue event (findEvent()/EVENTS,
  // src/data/events.js) — the same photo shown on Home/EventDetail/
  // Dashboard everywhere else in the app — so that's the fallback that
  // actually has real data for a real account, not a second empty table.
  // findEvent() itself falls back to EVENTS[0] for an unrecognized key
  // (deliberate elsewhere, so a screen always has something to render) —
  // wrong for this use: showing a random OTHER event's photo for a
  // genuinely non-catalogue event_id would be misleading, worse than the
  // honest bell fallback. Matched directly against EVENTS instead.
  const catalogImg = eventId ? EVENTS.find(e => e.key === eventId)?.img : null;
  if (catalogImg) {
    return { type: 'image', url: catalogImg };
  }
  return { type: 'fallback' };
}

/**
 * Instagram/Facebook-style bucketing: unread always lands in 'new'
 * regardless of age (checked by the caller, not here — this only buckets
 * by age), everything else buckets by created_at relative to now. Extends
 * agoLabel()'s "hours ago" concept with the coarser buckets a long
 * notification list actually needs to stay scannable.
 */
export function notificationAgeBucket(createdAt, now = Date.now()) {
  const ageMs = now - new Date(createdAt).getTime();
  const hours = ageMs / 3600000;
  if (hours < 24) return 'today';
  if (hours < 24 * 7) return 'week';
  return 'older';
}

// 2026-09-19 follow-up: within "7 ngày qua"/"Cũ hơn", a finer per-calendar-
// day header — "Thứ Năm, 18 Thg 9"/"Thursday, Sep 18" — instead of one flat
// block for the whole range. Local calendar day (not UTC), so a
// notification just after local midnight starts a new group rather than
// staying lumped with the previous day's items.
const VI_WEEKDAYS = ['Chủ Nhật', 'Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy'];

export function notificationDayKey(createdAt) {
  const d = new Date(createdAt);
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

export function notificationDayLabel(createdAt, lang = 'vi') {
  const d = new Date(createdAt);
  if (lang === 'en') return d.toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' });
  return `${VI_WEEKDAYS[d.getDay()]}, ${d.getDate()} Thg ${d.getMonth() + 1}`;
}

/**
 * Groups an already newest-first-sorted list into per-day buckets (also
 * newest-day-first, since insertion order follows the input). Pure
 * grouping — collapsing is a separate concern, see collapseDayGroups().
 */
export function groupNotificationsByDay(items, lang) {
  const byKey = new Map();
  for (const n of items) {
    const key = notificationDayKey(n.created_at);
    if (!byKey.has(key)) byKey.set(key, { key, label: notificationDayLabel(n.created_at, lang), items: [] });
    byKey.get(key).items.push(n);
  }
  return [...byKey.values()];
}

/**
 * Collapses whole day-groups at a time, never mid-day — accumulates full
 * days until adding the next one would cross `limit` total items, then
 * cuts there. The first day is always kept in full even if it alone
 * exceeds `limit` (a single very active day still isn't split in half).
 */
export function collapseDayGroups(dayGroups, limit) {
  let count = 0;
  let cutIndex = dayGroups.length;
  for (let i = 0; i < dayGroups.length; i++) {
    if (count > 0 && count + dayGroups[i].items.length > limit) { cutIndex = i; break; }
    count += dayGroups[i].items.length;
    if (count >= limit) { cutIndex = i + 1; break; }
  }
  return { visible: dayGroups.slice(0, cutIndex), hidden: dayGroups.slice(cutIndex) };
}

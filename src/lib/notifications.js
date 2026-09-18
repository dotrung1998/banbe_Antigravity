// Notification-bell presentation helpers — kept separate from GocContext.jsx
// so the row renderer (Notifications.jsx) doesn't need per-kind branching
// scattered through its JSX. Mirrors apps/ios/BanbeApp/Lib/NotificationPresentation.swift.

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

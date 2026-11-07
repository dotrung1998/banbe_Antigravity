// Phase 1 quick wins (docs/impl/phase1-quick-wins.md): the pure rules behind the ticket reveal, the honest wait,
// the check-in moment, the host "You're live" card and Home's "Saved, coming up" row. Mirrored by
// apps/ios/BanbeApp/Lib/QuickWins.swift; shared vectors in tests/fixtures/quick-wins.json
// (tests/unit/quickWins.test.mjs and BanbeAppTests/QuickWinsTests.swift) — change all three together.
//
// No countdowns, no "hurry", no loss framing: every text here states a real fact or nothing at all.

import { zonedParts, VN_TIME_ZONE } from './eventMarket.js';

// Once per milestone per device. `<id>` is the booking id (ticket, check-in) or the event id (live).
export const ONCE_KEYS = {
  ticketReveal: 'banbe.moment.ticketReveal.v1.<bookingId>',
  checkIn: 'banbe.moment.checkIn.v1.<bookingId>',
  eventLive: 'banbe.moment.eventLive.v1.<eventId>',
};

export function onceKey(kind, id) {
  const tpl = ONCE_KEYS[kind];
  if (!tpl || !id) return null;
  return tpl.replace(/<[^>]+>/, String(id).toLowerCase());
}

/** Already shown on this device? Storage that throws counts as shown (a celebration never repeats by accident). */
export function seenOnce(kind, id, storage = globalThis.localStorage) {
  const key = onceKey(kind, id);
  if (!key) return true;
  try { return storage.getItem(key) != null; } catch { return true; }
}

/** True exactly once per key per device: records the key and says whether this is the first time. */
export function claimOnce(kind, id, storage = globalThis.localStorage) {
  const key = onceKey(kind, id);
  if (!key) return false;
  try {
    if (storage.getItem(key) != null) return false;
    storage.setItem(key, '1');
    return true;
  } catch { return false; }
}

const unit = (n, vi, en) => ({ vi: `${n} ${vi}`, en: `${n} ${en}${n === 1 ? '' : 's'}` });

/**
 * "This host usually confirms within about 30 minutes." from get_host_confirmation_time's median (migration 198;
 * null below 5 confirmations -> nothing). Rounded to what a person would say: 5-minute steps under an hour, whole
 * hours under a day, whole days after that.
 */
export function typicalWaitText(minutes) {
  if (minutes == null || !Number.isFinite(Number(minutes)) || Number(minutes) < 0) return null;
  const m = Number(minutes);
  let span;
  if (m < 60 && Math.max(5, Math.round(m / 5) * 5) < 60) span = unit(Math.max(5, Math.round(m / 5) * 5), 'phút', 'minute');
  else if (m < 1440 && Math.max(1, Math.round(m / 60)) < 24) span = unit(Math.max(1, Math.round(m / 60)), 'giờ', 'hour');
  else span = unit(Math.max(1, Math.round(m / 1440)), 'ngày', 'day');
  return {
    vi: `Host này thường xác nhận trong khoảng ${span.vi}.`,
    en: `This host usually confirms within about ${span.en}.`,
  };
}

/** "12 of 20 taken" from the live fill (get_public_event_fill). Nothing when capacity is unknown or nobody booked. */
export function fillText(capacity, booked) {
  const cap = Number(capacity);
  const b = Number(booked);
  if (capacity == null || !Number.isFinite(cap) || cap <= 0 || !Number.isFinite(b) || b <= 0) return null;
  const n = Math.min(b, cap);
  return { vi: `Đã có ${n}/${cap} chỗ`, en: `${n} of ${cap} taken` };
}

export const SAVED_ROW = { maxItems: 5, withinDays: 30 };

const toMs = (v) => (v == null ? NaN : v instanceof Date ? v.getTime() : typeof v === 'number' ? v : Date.parse(v));

/**
 * Home "Saved, coming up": saved events that are live and start after now, within 30 days, soonest first, at most 5.
 * `events`: [{ key, status, startsAt }] (startsAt an ISO string, Date or ms).
 */
export function savedComingUp(events, now = Date.now(), { maxItems = SAVED_ROW.maxItems, withinDays = SAVED_ROW.withinDays } = {}) {
  const t0 = toMs(now);
  const t1 = t0 + withinDays * 86400000;
  return (events || [])
    .map(e => ({ e, t: toMs(e.startsAt) }))
    .filter(({ e, t }) => e.status === 'live' && Number.isFinite(t) && t > t0 && t <= t1)
    .sort((a, b) => a.t - b.t)
    .slice(0, maxItems)
    .map(({ e }) => e);
}

/** Ended page "Next from this host": the host's other live events still ahead, soonest first, at most 3. */
export function nextFromHost(rows, now = Date.now(), excludeKey = null, max = 3) {
  const t0 = toMs(now);
  return (rows || [])
    .map(r => ({ r, t: toMs(r.startsAt) }))
    .filter(({ r, t }) => r.status === 'live' && r.key !== excludeKey && Number.isFinite(t) && t > t0)
    .sort((a, b) => a.t - b.t)
    .slice(0, max)
    .map(({ r }) => r);
}

/** Checked in at the door: the booking became 'attended', or one of its named tickets was scanned (migration 151). */
export function isCheckedIn(booking, attendees = []) {
  if (!booking) return false;
  return booking.status === 'attended' || (attendees || []).some(a => a.booking_id === booking.id && !!a.checked_in_at);
}

// How long after approval a host's dashboard still celebrates a newly live event (the notification path has no limit).
export const LIVE_CELEBRATION_DAYS = 7;

/** A host's own event that banbe approved recently and that hasn't happened yet. */
export function isNewlyLive(ev, now = Date.now()) {
  if (!ev || ev.status !== 'live') return false;
  const reviewed = toMs(ev.reviewedAt);
  const start = toMs(ev.startsAt);
  const t0 = toMs(now);
  return Number.isFinite(reviewed) && t0 - reviewed <= LIVE_CELEBRATION_DAYS * 86400000 && (!Number.isFinite(start) || start > t0);
}

const pad2 = (n) => String(n).padStart(2, '0');
const WD_VI = ['CN', 'Th 2', 'Th 3', 'Th 4', 'Th 5', 'Th 6', 'Th 7'];
const WD_EN = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/** "Th 4, 05.03 · 19:00" / "Wed, 05.03 · 19:00" in the venue's zone (Vietnam when unknown); iOS discoveryWhenLabel. */
export function whenLabel(startsAt, timeZone, en = false) {
  const ms = toMs(startsAt);
  if (!Number.isFinite(ms)) return '';
  const p = zonedParts(ms, timeZone || VN_TIME_ZONE);
  return `${(en ? WD_EN : WD_VI)[p.weekday]}, ${pad2(p.day)}.${pad2(p.month)} · ${pad2(p.hour)}:${pad2(p.minute)}`;
}

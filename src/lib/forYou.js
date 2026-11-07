// Deterministic "For You" matching. Web port of apps/ios/BanbeApp/Lib/ForYou.swift.
// No network, no AI, no randomness: the same preferences + events + `now` always
// give the same ordered list. Rules: .claude/notes/34-onboarding-for-you-criteria.md
// (keep the iOS file, this file and the note in sync). Pure: no React imports.
//
// Candidate shape (already normalized):
//   { key, categories: string[], priceAmount: number|null, priceCurrency: 'VND'|'USD'|null,
//     isFree: boolean, startsAt: Date|number|null, timeZone: IANA string|null, isBookable: boolean }
// `priceCurrency == null` means "cannot compare" (never invent an FX rate).

import {
  INTERESTS, NO_PREFERENCE, budgetCap, budgetRegionForCurrency, budgetRegionCurrency,
  declaredInterests, declaredGoals, declaredAvailability,
} from './eventPrefs.js';
import { eventTimeZone, eventCurrency, rowCurrency, majorAmount } from './eventMarket.js';

/** Documented category affinity for each goal (soft signal, +10 each, capped at +20). */
export const GOAL_AFFINITY = {
  meet_people: ['supper', 'popup', 'music'],
  learn: ['gallery', 'fashion'],
  experiences: ['supper', 'fashion', 'gallery', 'music', 'popup'],
  networking: ['popup', 'fashion', 'supper'],
};

// ---- time zone (events are normalized to THEIR timezone, not the device's) ----
// The country/state -> zone map lives in eventMarket.js (shared with SQL event_tz_for, migration 195).

/** VN -> Asia/Ho_Chi_Minh; US -> by state code/name; anything else -> null (unknown). */
export function forYouTimeZone(countryCode, stateProvince) {
  return eventTimeZone(countryCode, stateProvince);
}

/** Kept for older callers: the currency an event in this country is priced in (VND / USD), else null. */
export function forYouPriceCurrency(countryCode) {
  return eventCurrency(countryCode);
}

const fmtCache = new Map();
/** { weekday: 0..6 (0 = Sunday), hour: 0..23 } of an instant in an IANA zone; null if the zone is invalid. */
export function zonedParts(ms, timeZone) {
  try {
    let f = fmtCache.get(timeZone);
    if (!f) {
      f = new Intl.DateTimeFormat('en-US', { timeZone, weekday: 'short', hour: 'numeric', hourCycle: 'h23' });
      fmtCache.set(timeZone, f);
    }
    const parts = f.formatToParts(new Date(ms));
    const wd = parts.find(p => p.type === 'weekday')?.value;
    const hour = parseInt(parts.find(p => p.type === 'hour')?.value, 10);
    const weekday = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(wd);
    if (weekday < 0 || Number.isNaN(hour)) return null;
    return { weekday, hour: hour === 24 ? 0 : hour };
  } catch { return null; }
}

const toMs = (d) => (d == null ? null : (d instanceof Date ? d.getTime() : Number(d)));

// ---- matching ----
/** null = excluded (a hard rule failed) or no positive signal at all. */
export function forYouMatch(e, p, now = Date.now()) {
  const nowMs = toMs(now);
  if (!e || !e.isBookable) return null;
  const startMs = toMs(e.startsAt);
  if (startMs != null && startMs < nowMs) return null;

  let score = 0;
  const reasons = [];
  const categories = e.categories || [];

  // 1. Interests: HARD when explicitly chosen; an unknown category passes.
  const interests = declaredInterests(p);
  const known = categories.filter(c => INTERESTS.some(o => o.id === c));
  if (interests.length && known.length) {
    if (!known.some(c => interests.includes(c))) return null;
    score += 50; reasons.push('interest');
  }

  // 2. Budget: HARD cap only when currencies are comparable.
  const b = p?.budget;
  if (b) {
    if (b.tier === 'free') {
      if (!e.isFree) return null;
      score += 20; reasons.push('budget');
    } else if (e.isFree) {
      if (b.tier !== NO_PREFERENCE) { score += 10; reasons.push('budget'); }
    } else {
      const region = budgetRegionForCurrency(b.currency);
      const cap = budgetCap(region, b.tier);
      if (cap != null && e.priceAmount != null && e.priceCurrency != null && e.priceCurrency === budgetRegionCurrency(region)) {
        if (e.priceAmount > cap) return null;
        score += 20; reasons.push('budget');
      }
      // flexible / no_preference / currency not comparable -> neutral
    }
  }

  // 3. Goals: soft affinity.
  const catSet = new Set(categories);
  const goalHits = declaredGoals(p).filter(g => (GOAL_AFFINITY[g] || []).some(c => catSet.has(c))).length;
  if (goalHits > 0) { score += Math.min(goalHits, 2) * 10; reasons.push('goal'); }

  // 4. Availability: soft, in the EVENT's timezone; only when both time and zone are known.
  const avail = declaredAvailability(p);
  if (avail.length && startMs != null && e.timeZone) {
    const parts = zonedParts(startMs, e.timeZone);
    if (parts) {
      const isWeekend = parts.weekday === 0 || parts.weekday === 6;
      const isDaytime = parts.hour < 17;
      const dayPicked = avail.filter(a => a === 'weekdays' || a === 'weekends');
      const timePicked = avail.filter(a => a === 'daytime' || a === 'evening');
      let fit = 0, miss = 0;
      if (dayPicked.length) { if (dayPicked.includes(isWeekend ? 'weekends' : 'weekdays')) fit++; else miss++; }
      if (timePicked.length) { if (timePicked.includes(isDaytime ? 'daytime' : 'evening')) fit++; else miss++; }
      if (miss > 0) score -= 15; else if (fit > 0) { score += 10; reasons.push('time'); }
    }
  }

  // 5. Languages: events carry no language field yet, deliberately neutral.

  // Recency tie-break: events within 14 days get up to +5.
  if (startMs != null) {
    const days = (startMs - nowMs) / 86400000;
    if (days <= 14) score += Math.max(0, 5 - Math.trunc(days / 3));
  }

  // Needs at least one affirmative signal besides the recency nudge.
  if (!reasons.length || score <= 0) return null;
  return { key: e.key, score, reasons };
}

/** Ordered matches: score desc, then soonest start, then key (total order, stable). */
export function forYouRank(events, p, now = Date.now()) {
  const byKey = new Map();
  for (const e of events) if (!byKey.has(e.key)) byKey.set(e.key, e);
  const start = (k) => { const s = toMs(byKey.get(k)?.startsAt); return s == null ? Infinity : s; };
  return events.map(e => forYouMatch(e, p, now)).filter(Boolean).sort((a, b) => {
    if (a.score !== b.score) return b.score - a.score;
    const sa = start(a.key), sb = start(b.key);
    if (sa !== sb) return sa < sb ? -1 : 1;
    return a.key < b.key ? -1 : a.key > b.key ? 1 : 0;
  });
}

// ---- shared candidate builder (Home feed + Map) ----
// ONE place that turns an app event into a For You candidate, so Home and Map can never
// score differently. Input is the normalized event both surfaces already have:
//   { key, catKey, cat2Key?, priceVnd, currency?, tz?, isFree?, countryCode, stateProvince,
//     startsAtRaw|startsAt, status, soldOut, cancelled, endedHoursAgo, inviteOnly }
// `priceVnd` is in the minor unit of `currency` (migration 195); budgets compare in major units.
export function forYouCandidateFromEvent(e) {
  const startsAt = e.startsAtRaw ?? e.startsAt ?? null;
  const currency = rowCurrency(e);
  return {
    key: e.key,
    categories: [e.catKey, e.cat2Key].filter(c => c && c !== 'all'),
    priceAmount: e.isFree === true || !e.priceVnd ? 0 : majorAmount(e.priceVnd, currency),
    priceCurrency: currency,
    isFree: !e.priceVnd,
    startsAt: startsAt ? new Date(startsAt).getTime() : null,
    timeZone: e.tz || forYouTimeZone(e.countryCode, e.stateProvince),
    isBookable: e.status === 'live' && !e.cancelled && e.endedHoursAgo == null && !e.soldOut && !e.inviteOnly,
  };
}

/** Ranked matches for already-area-filtered events. `hasPrefs` false -> []. */
export function forYouRankEvents(events, prefs, hasPrefs, now = Date.now()) {
  if (!prefs || !hasPrefs) return [];
  return forYouRank(events.map(forYouCandidateFromEvent), prefs, now);
}

// ---- Map composition (pure, so Home/Map parity and filter composition are testable) ----
/** Match set for Map's loaded events under the shared area rule (`areaMatch` null = all areas). */
export function mapForYouSet(events, areaMatch, prefs, hasPrefs, now = Date.now()) {
  const pool = events.filter(e => !areaMatch || areaMatch(e)).map(e => ({ ...e, key: e.id }));
  const ranked = forYouRankEvents(pool, prefs, hasPrefs, now);
  return { ranked, order: new Map(ranked.map((m, i) => [m.key, i])) };
}

/** AND the For You set onto an already-filtered list; rank order unless the caller sorts by distance. */
export function applyForYouFilter(list, active, order, { keepOrder = false } = {}) {
  if (!active) return list;
  const out = list.filter(e => order.has(e.id));
  return keepOrder ? out : out.sort((a, b) => order.get(a.id) - order.get(b.id));
}

// The v2.3 live line on Home (note 81, switch home_v23): one list of updates feeds the scrolling ticker, the
// one-at-a-time Reduced form and the "Live now" sheet, so all three say the same things.
//
// Everything comes from real data, never invented:
// - the daily Banbe Pulse ranking (goc_pulse_ranked: event, host, that period's confirmed booking_count),
// - real seat fill (get_public_event_fill) for "only N seats left",
// - Home's own tab lists for the "N events on tonight" summary.
// The prototype's per-update times ("2 min") and people's names ("Linh took 2 tickets") do not exist in the data, so
// each update carries WHEN THE EVENT IS (its start badge) instead of a fake "ago".
// Copy: { vi, en } pairs, note 57 (no dash or semicolon between ideas).

import { foldText } from './mapDiscovery.js';

export const MAX_UPDATES = 8;
const L = (vi, en) => ({ vi, en });
export const FEW_SEATS = 5;

/**
 * @param {object} p
 * @param {Array} p.pulse  goc_pulse_ranked items, server order (best first)
 * @param {(eventId: string) => ({ seatsLeft: number|null, when: string } | null)} p.lookup  live facts for an event
 * @param {number} p.tonight  events on tonight (Home's Tonight tab)
 * @param {number} p.weekend  events this weekend (Home's Weekend tab)
 * @returns {Array<{ id: string, eventId: string|null, text: {vi,en}, when: string|null, kind: string }>}
 */
export function liveUpdates({ pulse, lookup, tonight = 0, weekend = 0, max = MAX_UPDATES }) {
  const out = [];
  if (tonight > 0) out.push({ id: 'sum-tonight', eventId: null, kind: 'summary', when: null,
    text: tonight === 1 ? L('1 sự kiện diễn ra tối nay', '1 event on tonight') : L(`${tonight} sự kiện diễn ra tối nay`, `${tonight} events on tonight`) });
  else if (weekend > 0) out.push({ id: 'sum-weekend', eventId: null, kind: 'summary', when: null,
    text: weekend === 1 ? L('1 sự kiện cuối tuần này', '1 event this weekend') : L(`${weekend} sự kiện cuối tuần này`, `${weekend} events this weekend`) });
  for (const p of pulse || []) {
    if (out.length >= max) break;
    const name = typeof p?.event_name === 'string' ? p.event_name.trim() : '';
    if (!name || !p.event_id) continue;
    const facts = lookup?.(p.event_id) || null;
    if (!facts) continue; // not listed on Home (ended, other area, removed): nothing to open, so not shown
    const seats = facts.seatsLeft;
    const booked = Number(p.booking_count) || 0;
    let text, kind;
    if (seats != null && seats > 0 && seats <= FEW_SEATS) {
      kind = 'seats';
      // "Only N left" is true whether seats were booked or the event is just small ("down to" would claim bookings).
      text = seats === 1 ? L(`Chỉ còn 1 chỗ ở ${name}`, `Only 1 seat left at ${name}`) : L(`Chỉ còn ${seats} chỗ ở ${name}`, `Only ${seats} seats left at ${name}`);
    } else if (booked > 0) {
      kind = 'booked';
      text = booked === 1 ? L(`1 lượt đặt ${name} hôm nay`, `1 booking for ${name} today`) : L(`${booked} lượt đặt ${name} hôm nay`, `${booked} bookings for ${name} today`);
    } else {
      kind = 'trending';
      const raw = typeof p.organizer_name === 'string' ? p.organizer_name.trim() : '';
      // A host named like the event ("Băng Cối by Băng Cối") says nothing new: leave the host out.
      const host = raw && foldText(raw) !== foldText(name) ? raw : null;
      text = host ? L(`${name} của ${host} đang được quan tâm`, `${name} by ${host} is getting attention`) : L(`${name} đang được quan tâm`, `${name} is getting attention`);
    }
    out.push({ id: `ev-${p.event_id}`, eventId: p.event_id, kind, text, when: facts.when || null });
  }
  return out;
}

/** One pass of the ticker at a fixed reading speed: longer lines scroll for longer, never faster. */
export function liveSeconds(texts) {
  const chars = (texts || []).reduce((n, t) => n + String(t || '').length + 5, 0);
  return Math.max(16, Math.round(chars * 0.26));
}

/** Reduced form: step back and forward, clamped (nothing changes on its own). */
export const stepIndex = (i, dir, n) => Math.max(0, Math.min(Math.max(0, n - 1), i + dir));

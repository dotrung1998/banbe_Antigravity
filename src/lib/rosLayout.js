// Event Project Hub, Day-of tab (note 76): where each run-of-show item sits on the time grid "now".
// iOS twin: apps/ios/BanbeApp/Lib/RosLayout.swift. Shared vectors: tests/fixtures/ros-layout.json.
//
// A port of layoutDay() in banbe_hosting_project_hub_v6.html, rule for rule:
// - An unticked item whose predecessor is ticked (or the first item) stretches along the clock once the clock passes
//   its planned end.
// - Only the very next item is squeezed: it starts at min(previous end, its planned end - 10 min). Later items keep
//   their planned times; anything still overlapped is flagged, never moved.
// - Ticking freezes the end at max(planned end, done at).
// Overrun and squeeze are derived here and never stored; the server only stores starts_at, ends_at and done_at.
// Everything is absolute epoch milliseconds, so items crossing midnight or a DST change need no zone logic. The axis
// is rounded to UTC half hours, which are local half hours in every zone whose offset is a whole or half hour (all
// VN and US zones).
import LIMITS from '../data/projectLimits.json' with { type: 'json' };

const MIN = 60_000;
const HALF_HOUR = 30 * MIN;

/**
 * items: [{ id, startsAt, endsAt, doneAt }] in epoch ms (doneAt null while unticked; ticked = doneAt !== null).
 * Returns { items, chips, axis } where items are sorted by planned start (then id) and axis is null for no items.
 */
export function rosLayout(items, nowMs, minMinutes = LIMITS.rosMinMinutes) {
  const minLen = minMinutes * MIN;
  const plan = [...(items || [])]
    .map(it => ({
      id: String(it.id),
      s: it.startsAt,
      // A zero or negative planned length gets the minimum (the server CHECK makes this impossible for saved rows).
      e: Math.max(it.endsAt, it.startsAt + minLen),
      done: it.doneAt !== null && it.doneAt !== undefined,
      doneAt: it.doneAt ?? null,
    }))
    .sort((a, b) => a.s - b.s || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

  const out = [];
  plan.forEach((b, i) => {
    const prev = out[i - 1];
    const canRun = i === 0 || plan[i - 1].done;
    let end = b.e;
    if (b.done) end = Math.max(b.e, b.doneAt ?? b.e);
    else if (canRun && nowMs > b.e) end = nowMs;
    let start = b.s;
    if (prev && prev.end > b.s) start = Math.min(prev.end, b.e - minLen);
    const latestEnd = out.reduce((m, o) => Math.max(m, o.end), -Infinity);
    const overlap = i > 0 && latestEnd > start;
    if (end < start + minLen) end = start + minLen;
    const overrunMin = Math.round((end - b.e) / MIN);
    const squeezedMin = Math.round((start - b.s) / MIN);
    out.push({
      id: b.id,
      plannedStart: b.s,
      plannedEnd: b.e,
      start,
      end,
      done: b.done,
      overrunMin,
      squeezedMin,
      overlap,
      active: !b.done && nowMs >= start && nowMs < end,
      overrun: !b.done && overrunMin > 0,
      squeezed: squeezedMin > 0 && !overlap,
    });
  });

  // "Versus the plan" chips, in the prototype's order.
  const chips = [];
  for (const l of out) {
    if (l.overrun) chips.push({ id: l.id, kind: 'overrun', minutes: l.overrunMin });
    if (l.squeezed) chips.push({ id: l.id, kind: 'squeezed', minutes: l.squeezedMin });
    if (l.overlap) chips.push({ id: l.id, kind: 'overlap', minutes: 0 });
  }

  const axis = out.length
    ? {
        start: Math.floor((Math.min(...out.map(l => l.start)) - HALF_HOUR) / HALF_HOUR) * HALF_HOUR,
        end: Math.ceil((Math.max(...out.map(l => l.end)) + HALF_HOUR) / HALF_HOUR) * HALF_HOUR,
      }
    : null;

  return { items: out, chips, axis };
}

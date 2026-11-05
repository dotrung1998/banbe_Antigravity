// Event Project Hub (note 76): what the Overview, Tasks and Hosting Home show, derived from one get_event_project
// snapshot. iOS twin: apps/ios/BanbeApp/Lib/ProjectPresentation.swift. Shared vectors: tests/fixtures/project-presentation.json
// over tests/fixtures/project-snapshot.json. Days are always counted in the EVENT's zone, never the browser's.
import { canProject } from './projectPermissions.js';
import { parseInvite } from './projectInviteLink.js';

/** "yyyy-MM-dd" of an instant in `tz`. */
export function ymd(date, tz) {
  const d = date instanceof Date ? date : new Date(date);
  return new Intl.DateTimeFormat('en-CA', { timeZone: tz || 'Asia/Ho_Chi_Minh', year: 'numeric', month: '2-digit', day: '2-digit' }).format(d);
}

const dayNumber = (s) => {
  const [y, m, d] = String(s).split('-').map(Number);
  return Number.isFinite(y) && Number.isFinite(m) && Number.isFinite(d) ? Date.UTC(y, m - 1, d) / 86400000 : null;
};

/** Whole days from today (in `tz`) to a "yyyy-MM-dd" day: 0 today, 1 tomorrow, -2 two days late. */
export function dayDelta(day, now, tz) {
  if (!day) return null;
  const a = dayNumber(ymd(now, tz)), b = dayNumber(day);
  return a == null || b == null ? null : b - a;
}

/** { kind: 'today' | 'tomorrow' | 'late' | 'date', days?, day? } or null. */
export function dueLabel(day, now, tz) {
  const n = dayDelta(day, now, tz);
  if (n == null) return null;
  if (n < 0) return { kind: 'late', days: -n };
  if (n === 0) return { kind: 'today' };
  if (n === 1) return { kind: 'tomorrow' };
  return { kind: 'date', day };
}

export function readiness(tasks = []) {
  const done = tasks.filter(t => t.status === 'done').length;
  const total = tasks.length;
  return { done, total, percent: total === 0 ? 0 : Math.round((done * 100) / total) };
}

export function laneProgress(lanes = [], tasks = []) {
  return [...lanes].sort((a, b) => a.position - b.position).map(l => {
    const mine = tasks.filter(t => t.lane_id === l.id);
    return { laneId: l.id, name: l.name, done: mine.filter(t => t.status === 'done').length, total: mine.length };
  });
}

/** Days until the event day (negative once it has passed). */
export function daysToGo(event, now) {
  if (!event) return null;
  const day = event.event_date || (event.starts_at ? ymd(event.starts_at, event.tz) : null);
  return dayDelta(day, now, event.tz);
}

/** Open first by due day (no due day last), keeping the server's order among equals. */
export function byDue(tasks = []) {
  return tasks.map((t, i) => [t, i]).sort(([a, i], [b, j]) => {
    if (a.due_date && b.due_date && a.due_date !== b.due_date) return a.due_date < b.due_date ? -1 : 1;
    if (!a.due_date && b.due_date) return 1;
    if (a.due_date && !b.due_date) return -1;
    return i - j;
  }).map(([t]) => t);
}

export const openTasks = (tasks = []) => tasks.filter(t => t.status !== 'done');

export function myOpenTasks(tasks = [], me) {
  if (!me) return [];
  const uid = String(me).toLowerCase();
  return byDue(openTasks(tasks).filter(t => String(t.assignee_id || '').toLowerCase() === uid));
}

/** Blocked tasks first, then the late ones (due before today in the event's zone), each by due day. */
export function attention(tasks = [], now, tz) {
  const blocked = byDue(tasks.filter(t => t.status === 'blocked'));
  const late = byDue(openTasks(tasks).filter(t => t.status !== 'blocked' && (dayDelta(t.due_date, now, tz) ?? 0) < 0));
  return [...blocked, ...late];
}

export const comingUp = (tasks = [], limit = 4) => byDue(openTasks(tasks)).slice(0, limit);

/** What waits on me: (Host) proposals to review, then open posts newest first: a question to me, a proposal I have
 * not voted on, an update I have not seen. My own posts never wait on me. */
export function awaiting(snap, me) {
  const uid = me ? String(me).toLowerCase() : null;
  const out = [];
  if (snap?.is_host === true) {
    for (const c of snap.change_requests || []) if (c.status === 'pending') out.push({ kind: 'laneReview', id: c.id });
  }
  for (const p of snap?.posts || []) {
    if (p.state !== 'open' || String(p.author_id || '').toLowerCase() === uid) continue;
    if (p.type === 'question' && uid && String(p.addressee_id || '').toLowerCase() === uid) out.push({ kind: 'question', id: p.id });
    else if (p.type === 'proposal' && p.my_vote == null) out.push({ kind: 'vote', id: p.id });
    else if (p.type === 'update' && !p.seen_by_me) out.push({ kind: 'unseen', id: p.id });
  }
  return out;
}

export const decisions = (posts = []) => posts.filter(p => p.type === 'decision');

/** canProject() for the snapshot's viewer. The snapshot says whether I am the Host (is_host); the rules need an
 * organizer to compare with, so the Host's own id stands in for it, as on iOS. The server re-checks every call. */
export function projectCan(snap, action, target = {}, { userId, flags = {}, now = Date.now() } = {}) {
  if (!snap) return false;
  const uid = userId ? String(userId).toLowerCase() : null;
  const me = snap.me;
  const lower = (v) => (v == null ? v : String(v).toLowerCase());
  return canProject(action, {
    actor: {
      userId: uid,
      member: me ? { role: me.role, laneId: me.lane_id, caps: { money: !!me.cap_money, checkin: !!me.cap_checkin }, status: 'active', grantExpiresAt: me.grant_expires_at } : undefined,
    },
    organizer: { ownerId: snap.is_host === true ? uid : null, userId: null },
    flags, now,
    project: { readOnlyAt: snap.project?.read_only_at, refundApproval: snap.project?.refund_approval || 'host' },
    target: { ...target, assigneeId: lower(target.assigneeId), authorId: lower(target.authorId), addresseeId: lower(target.addresseeId), createdBy: lower(target.createdBy) },
  });
}

/** Hosts, then active members: everyone a task, question or item can be given to. */
export function projectPeople(snap) {
  return [...(snap?.hosts || []).map(h => ({ ...h, role: 'host' })), ...(snap?.members || [])];
}

/** A link, token or typed code -> the bare value peek/redeem accept (210's project_invite_value takes no URLs). */
export function projectInviteValue(input) {
  const inv = parseInvite(input);
  return inv ? (inv.kind === 'token' ? inv.token : inv.code) : null;
}

/** Pure: the Host's Money & door numbers (same rules as AppState.projectMoneySummary on iOS). */
export function moneySummary(bookings, refunds, now) {
  const s = { confirmedSeats: 0, confirmedAmount: 0, awaiting: 0, refunds: 0, refundsOverdue: 0, checkedIn: 0, seats: 0 };
  const t = now instanceof Date ? now.getTime() : now;
  for (const b of bookings) {
    if (b.status === 'confirmed' || b.status === 'attended') {
      s.confirmedSeats += b.qty; s.confirmedAmount += b.total_vnd || 0; s.seats += b.qty;
      if (b.status === 'attended') s.checkedIn += b.qty;
    } else if (b.status === 'pending') {
      const live = !b.expires_at || Date.parse(b.expires_at) > t;
      if (!live && !b.paid_marked_at) continue;
      s.seats += b.qty;
      if (b.paid_marked_at) s.awaiting += 1;
    }
  }
  const active = refunds.filter(r => r.active);
  s.refunds = active.length;
  s.refundsOverdue = active.filter(r => r.overdue).length;
  return s;
}

/** Phase 9a: get_event_checkin_names rows grouped by booking (named attendees count one each; a booking without names
 * counts its party), first-seen order. Same as AppState.projectDoorGuests on iOS. */
export function doorGuests(rows = []) {
  const order = [], map = new Map();
  for (const r of rows) {
    if (!map.has(r.booking_id)) { order.push(r.booking_id); map.set(r.booking_id, { bookingId: r.booking_id, names: [], party: 0, inside: 0 }); }
    const g = map.get(r.booking_id);
    g.names.push(r.name);
    g.party += r.party;
    if (r.checked_in) g.inside += r.party;
  }
  return order.map(id => map.get(id));
}

/** Phase 9c (migration 215): what one get_event_refund_view claim offers a refund delegate.
 * state: 'waiting' (a record waits for the Host: no action), 'noAccount' (the guest has no refund account yet: the
 * button is off), 'ready'. cta: 'request' (Host approves) or 'markSent' (finance_alone). declined: the Host's reason on my
 * last record, shown so I can record again. Same as AppState.projectRefundRowState on iOS. */
export function refundRowState(claim, mode = 'host') {
  const declined = claim?.last_declined?.reason || null;
  if (claim?.request) return { state: 'waiting', mine: claim.request.mine === true, cta: null, declined: null };
  const cta = mode === 'finance_alone' ? 'markSent' : 'request';
  if (!claim?.account) return { state: 'noAccount', mine: false, cta, declined };
  return { state: 'ready', mine: false, cta, declined };
}

/** The Host's "Refunds from the team": claims with a pending record, in the server's order. */
export const teamRefundRequests = (claims = []) => claims.filter(c => c && c.request);

/** Who can be given one disputed refund: active members holding money access (Finance & door, or the money capability). */
export const refundDelegates = (snap) => (snap?.members || []).filter(m => m.role === 'finance' || m.cap_money === true);

/** True once the team's money access is over by default: the project is read-only, or the default grant (event end +
 * grantDays) has passed. A per-member extension is not in the snapshot; the server decides either way. */
export function teamGrantsOver(snap, now, grantDays = 7) {
  const t = now instanceof Date ? now.getTime() : (typeof now === 'number' ? now : Date.parse(now));
  const p = snap?.project || {};
  if (p.read_only === true || (p.read_only_at && t >= Date.parse(p.read_only_at))) return true;
  return !!p.event_end_at && t >= Date.parse(p.event_end_at) + grantDays * 86400e3;
}

/** Tasks lane navigator (2026-11-05, iOS `ProjectLaneNav.current`): the lane being looked at = the last heading above a
 *  reading line. `tops` = each lane heading's top in px below the navigator strip; `viewport` = visible height below the
 *  strip; `remaining` = px of scrolling left to the bottom. The line sits 60 px down for most of the list and, over the
 *  last 60% of a screen of scrolling, slides down toward the bottom, so short lanes at the end each become current in
 *  order. A list that fits on screen (first heading below the line) keeps its first lane. */
export function currentLane(tops = {}, { viewport = 0, remaining = null } = {}) {
  const entries = Object.entries(tops);
  if (!entries.length) return null;
  const min = Math.min(...entries.map(([, y]) => y));
  let line = 60;
  if (remaining != null && viewport > 0 && min <= 60) {
    const t = Math.min(1, Math.max(0, 1 - remaining / (viewport * 0.6)));
    line = 60 + t * Math.max(0, viewport - 60 - 120);
  }
  const above = entries.filter(([, y]) => y <= line);
  const pick = above.length ? above.reduce((a, b) => (b[1] > a[1] ? b : a)) : entries.reduce((a, b) => (b[1] < a[1] ? b : a));
  return pick[0];
}

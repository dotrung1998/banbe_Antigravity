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

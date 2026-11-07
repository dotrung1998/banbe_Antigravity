import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as P from '../../src/lib/projectPresentation.js';

// tests/fixtures/project-presentation.json over project-snapshot.json: the same vectors the iOS twin runs.
const fx = JSON.parse(readFileSync(new URL('../fixtures/project-presentation.json', import.meta.url), 'utf8'));
const snapFile = JSON.parse(readFileSync(new URL('../fixtures/project-snapshot.json', import.meta.url), 'utf8'));
const pad = (n) => String(n).padStart(2, '0');
const id = (s) => {
  const v = String(s);
  if (v.startsWith('post:')) return `00000000-0000-4000-8000-0000000004${pad(Number(v.slice(5)))}`;
  if (v.length > 4) return v;
  return `00000000-0000-4000-8000-0000000003${pad(Number(v))}`;
};
const label = (l) => !l ? null : l.kind === 'late' ? `late:${l.days}` : l.kind === 'date' ? `date:${l.day}` : l.kind;

test('shared presentation vectors', () => {
  const snap0 = snapFile.snapshot;
  const tasks = snap0.tasks, tz = snap0.event.tz;
  for (const c of fx.cases) {
    const now = new Date(c.now || fx.now);
    const snap = { ...snap0, is_host: c.isHost };
    const e = c.expect, name = c.case;
    assert.deepEqual(P.readiness(tasks), e.readiness, name);
    assert.deepEqual(P.laneProgress(snap.lanes, tasks).map(l => [l.done, l.total]), e.lanes, name);
    assert.deepEqual(P.myOpenTasks(tasks, c.me).map(t => t.id), e.myOpenTasks.map(id), name);
    assert.deepEqual(P.attention(tasks, now, tz).map(t => t.id), e.attention.map(id), name);
    assert.deepEqual(P.comingUp(tasks).map(t => t.id), e.comingUp.map(id), name);
    assert.deepEqual(P.awaiting(snap, c.me).map(a => `${a.kind}|${a.id}`), e.awaiting.map(([k, v]) => `${k}|${id(v)}`), name);
    assert.deepEqual(P.decisions(snap.posts).map(p => p.id), e.decisions.map(n => id(`post:${n}`)), name);
    assert.equal(P.daysToGo(snap.event, now), e.daysToGo, name);
    for (const [t, n] of Object.entries(e.dayDeltas || {})) {
      assert.equal(P.dayDelta(tasks.find(x => x.id === id(t)).due_date, now, tz), n, `${name} task ${t}`);
    }
    for (const [t, l] of Object.entries(e.dueLabels || {})) {
      assert.equal(label(P.dueLabel(tasks.find(x => x.id === id(t)).due_date, now, tz)), l, `${name} task ${t}`);
    }
  }
});

test('projectCan follows the snapshot: the Host edits channels, a member does not; nothing while the switch is off', () => {
  const snap = snapFile.snapshot;
  const me = '00000000-0000-4000-8000-00000000f1f0';
  const on = { event_project_hub: true };
  const now = new Date('2026-11-03T10:00:00+07:00');
  assert.equal(P.projectCan(snap, 'channels.edit', {}, { userId: me, flags: on, now }), true);
  assert.equal(P.projectCan(snap, 'channels.edit', {}, { userId: me, flags: {}, now }), false);
  const helper = { ...snap, is_host: false, me: { member_id: 'm', role: 'helper', lane_id: null, cap_money: false, cap_checkin: false } };
  assert.equal(P.projectCan(helper, 'channels.edit', {}, { userId: me, flags: on, now }), false);
  assert.equal(P.projectCan(helper, 'post.question', {}, { userId: me, flags: on, now }), true);
  assert.equal(P.projectCan(helper, 'money.view', {}, { userId: me, flags: on, now }), false, 'money stays with the organizer accounts');
  assert.equal(P.projectCan(null, 'project.read'), false);
});

test('moneySummary counts what the Host acts on (same rules as iOS)', () => {
  const now = new Date(1_800_000_000_000);
  const later = new Date(now.getTime() + 600e3).toISOString(), earlier = new Date(now.getTime() - 600e3).toISOString(), at = now.toISOString();
  const s = P.moneySummary([
    { qty: 2, status: 'confirmed', total_vnd: 980000 },
    { qty: 1, status: 'attended', total_vnd: 490000 },
    { qty: 1, status: 'pending', total_vnd: 490000, expires_at: later, paid_marked_at: at },
    { qty: 2, status: 'pending', total_vnd: 980000, expires_at: later },
    { qty: 1, status: 'pending', total_vnd: 490000, expires_at: earlier },
    { qty: 1, status: 'pending', total_vnd: 490000, expires_at: earlier, paid_marked_at: earlier },
    { qty: 3, status: 'cancelled', total_vnd: 1470000 },
  ], [{ active: true, overdue: false }, { active: true, overdue: true }, { active: false, overdue: false }], now);
  assert.deepEqual(s, { confirmedSeats: 3, confirmedAmount: 1470000, awaiting: 2, refunds: 2, refundsOverdue: 1, checkedIn: 1, seats: 7 });
});

test('projectInviteValue turns links and typed codes into the bare value', () => {
  assert.equal(P.projectInviteValue('https://www.banbe.app/join/bb-h3qd?src=qr'), 'BB-H3QD');
  assert.equal(P.projectInviteValue('banbe://join/Fx7kQ2mN9pR4sT6vW8yZ1a'), 'Fx7kQ2mN9pR4sT6vW8yZ1a');
  assert.equal(P.projectInviteValue('https://evil.example/join/BB-H3QD'), null);
});

test('doorGuests groups the names-only rows by booking (same as iOS)', () => {
  const g = P.doorGuests([
    { booking_id: 'b1', attendee_id: 'a1', name: 'Anh', party: 1, checked_in: true },
    { booking_id: 'b2', attendee_id: null, name: 'Ha', party: 3, checked_in: false },
    { booking_id: 'b1', attendee_id: 'a2', name: 'Binh', party: 1, checked_in: false },
  ]);
  assert.deepEqual(g, [{ bookingId: 'b1', names: ['Anh', 'Binh'], party: 2, inside: 1 }, { bookingId: 'b2', names: ['Ha'], party: 3, inside: 0 }]);
});

test('refundRowState (9c): waiting on a record, no account, ready; the CTA follows the approval mode', () => {
  const acct = { bank_name: 'VCB', account_number: '1', account_holder_name: 'A' };
  assert.deepEqual(P.refundRowState({ account: acct, request: null }, 'host'), { state: 'ready', mine: false, cta: 'request', declined: null });
  assert.deepEqual(P.refundRowState({ account: acct, request: null }, 'finance_alone'), { state: 'ready', mine: false, cta: 'markSent', declined: null });
  assert.equal(P.refundRowState({ account: acct }).cta, 'request', 'host approval is the default');
  assert.deepEqual(P.refundRowState({ account: acct, request: { mine: true } }, 'host'), { state: 'waiting', mine: true, cta: null, declined: null });
  assert.deepEqual(P.refundRowState({ account: acct, request: { mine: false } }, 'finance_alone'), { state: 'waiting', mine: false, cta: null, declined: null });
  assert.deepEqual(P.refundRowState({ account: null, request: null }, 'host'), { state: 'noAccount', mine: false, cta: 'request', declined: null });
  const again = P.refundRowState({ account: acct, request: null, last_declined: { reason: 'Wrong amount', at: 'x' } }, 'host');
  assert.equal(again.state, 'ready', 'a declined record can be recorded again');
  assert.equal(again.declined, 'Wrong amount');
});

test('teamRefundRequests and refundDelegates (9c)', () => {
  assert.deepEqual(P.teamRefundRequests([{ claim_id: 'a', request: null }, { claim_id: 'b', request: { id: 'r' } }, null]).map(c => c.claim_id), ['b']);
  const snap = snapFile.snapshot;
  const ids = P.refundDelegates(snap).map(m => m.role);
  assert.deepEqual(ids, ['finance'], 'only Finance holds money access in the fixture');
  assert.equal(P.refundDelegates({ members: [{ role: 'helper', cap_money: true }, { role: 'helper', cap_money: false }] }).length, 1);
  assert.deepEqual(P.refundDelegates(null), []);
});

test('teamGrantsOver (9c): read-only, or past event end + grantDays', () => {
  const snap = snapFile.snapshot; // event end 2026-11-14T17:00Z, read-only 2026-12-14T17:00Z
  assert.equal(P.teamGrantsOver(snap, new Date('2026-11-21T16:59:00Z'), 7), false);
  assert.equal(P.teamGrantsOver(snap, new Date('2026-11-21T17:00:00Z'), 7), true);
  assert.equal(P.teamGrantsOver({ project: { read_only: true } }, new Date('2026-01-01T00:00:00Z'), 7), true);
  assert.equal(P.teamGrantsOver({ project: {} }, new Date(), 7), false);
});

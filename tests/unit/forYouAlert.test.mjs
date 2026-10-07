import test from 'node:test';
import assert from 'node:assert/strict';
import {
  emptyAlertState, observe, acknowledge, hasPending, pendingIds, forYouEventVersion,
  loadAlertState, saveAlertState, alertStorageKey,
} from '../../src/lib/forYouAlert.js';

const m = (id, version = 'v1', extra = {}) => ({ id, version, ...extra });
const opts = { prefsVersion: 1 };
const memStorage = () => { const d = {}; return { getItem: k => (k in d ? d[k] : null), setItem: (k, v) => { d[k] = v; }, d }; };

test('first observation baselines silently (no burst)', () => {
  const s = observe(emptyAlertState(), [m('a'), m('b')], opts);
  assert.equal(s.baselined, true);
  assert.equal(hasPending(s), false);
  assert.deepEqual(Object.keys(s.seen).sort(), ['a', 'b']);
});

test('only new matching events become pending afterwards; repeat polls do not replay', () => {
  let s = observe(emptyAlertState(), [m('a')], opts);
  s = observe(s, [m('a'), m('b')], opts);
  assert.deepEqual(pendingIds(s), ['b']);
  const again = observe(s, [m('a'), m('b')], opts);
  assert.deepEqual(pendingIds(again), ['b']);
  assert.deepEqual(again.seen, s.seen);
});

test('non-matching new events never alert (they are simply not in the match set)', () => {
  let s = observe(emptyAlertState(), [m('a')], opts);
  s = observe(s, [m('a')], opts); // a new non-matching event "z" exists in discovery but is not passed in
  assert.equal(hasPending(s), false);
});

test('version bump re-alerts a seen event', () => {
  let s = observe(emptyAlertState(), [m('a', 'v1')], opts);
  s = observe(s, [m('a', 'v2')], opts);
  assert.deepEqual(pendingIds(s), ['a']);
  assert.notEqual(forYouEventVersion({ status: 'draft', visibility: 'invite' }), forYouEventVersion({ status: 'live', visibility: 'public' }));
  assert.equal(forYouEventVersion({ reviewedAt: 'r', status: 'live', visibility: 'public' }), forYouEventVersion({ reviewedAt: 'r', status: 'live', visibility: 'public' }));
});

test('drafts / inaccessible are ignored and dropped from pending', () => {
  let s = observe(emptyAlertState(), [m('a')], opts);
  s = observe(s, [m('a'), m('b'), m('d', 'v1', { draft: true }), m('x', 'v1', { accessible: false }), m('y', 'v1', { status: 'draft' })], opts);
  assert.deepEqual(pendingIds(s), ['b']);
  s = observe(s, [m('a'), m('b', 'v1', { accessible: false })], opts);
  assert.equal(hasPending(s), false);
  s = observe(s, [m('a')], opts); // b no longer matches
  assert.equal(hasPending(s), false);
});

test('pending entry that stops matching is dropped', () => {
  let s = observe(emptyAlertState(), [m('a')], opts);
  s = observe(s, [m('a'), m('b')], opts);
  s = observe(s, [m('a')], opts);
  assert.equal(hasPending(s), false);
});

test('persistence round trip and relaunch does not replay', () => {
  const st = memStorage();
  let s = observe(emptyAlertState(), [m('a')], opts);
  s = observe(s, [m('a'), m('b')], opts);
  saveAlertState('u1', s, st);
  assert.ok(alertStorageKey('u1').endsWith(':u1'));
  const back = loadAlertState('u1', st);
  assert.deepEqual(back, s);
  const relaunched = observe(back, [m('a'), m('b')], opts);
  assert.deepEqual(pendingIds(relaunched), ['b']); // still pending, not re-added/duplicated
  const acked = acknowledge(relaunched, ['b']);
  saveAlertState('u1', acked, st);
  assert.equal(hasPending(observe(loadAlertState('u1', st), [m('a'), m('b')], opts)), false);
});

test('storage failures and corrupt data fall back to empty', () => {
  const bad = { getItem() { throw new Error('x'); }, setItem() { throw new Error('x'); } };
  assert.equal(loadAlertState('u', bad).baselined, false);
  saveAlertState('u', emptyAlertState(), bad); // must not throw
  const st = memStorage(); st.setItem(alertStorageKey('u'), '{nope');
  assert.equal(loadAlertState('u', st).baselined, false);
});

test('per-account isolation', () => {
  const st = memStorage();
  const s1 = observe(emptyAlertState(), [m('a')], opts);
  saveAlertState('u1', s1, st);
  const s2 = loadAlertState('u2', st);
  assert.equal(s2.baselined, false);
  assert.deepEqual(s2.seen, {});
});

test('prefsVersion change rebaselines silently', () => {
  let s = observe(emptyAlertState(), [m('a')], { prefsVersion: 1 });
  s = observe(s, [m('a'), m('b')], { prefsVersion: 1 });
  assert.equal(hasPending(s), true);
  s = observe(s, [m('a'), m('b'), m('c')], { prefsVersion: 2 });
  assert.equal(hasPending(s), false);
  assert.equal(s.prefsVersion, 2);
  assert.ok('c' in s.seen);
});

test('acknowledge clears only loaded ids; later arrivals remain pending', () => {
  let s = observe(emptyAlertState(), [m('a')], opts);
  s = observe(s, [m('a'), m('b'), m('c')], opts);
  s = acknowledge(s, ['a', 'b', 'c']);
  assert.equal(hasPending(s), false);
  s = observe(s, [m('a'), m('b'), m('c'), m('d')], opts);
  const partial = acknowledge(s, ['x']);
  assert.deepEqual(pendingIds(partial), ['d']);
  s = observe(s, [m('a'), m('b'), m('c'), m('d'), m('e')], opts);
  s = acknowledge(s, ['d']);
  assert.deepEqual(pendingIds(s), ['e']);
});

test('loading skips observation entirely', () => {
  const s0 = emptyAlertState();
  assert.equal(observe(s0, [m('a')], { prefsVersion: 1, loading: true }), s0);
  let s = observe(s0, [m('a')], opts);
  assert.equal(observe(s, [], { prefsVersion: 1, loading: true }), s);
});

test('seen is bounded, dropping oldest', () => {
  let s = observe(emptyAlertState(), [m('a0')], { prefsVersion: 1, limit: 5 });
  s = observe(s, Array.from({ length: 8 }, (_, i) => m('n' + i)), { prefsVersion: 1, limit: 5 });
  assert.equal(Object.keys(s.seen).length, 5);
  assert.equal(s.order.length, 5);
  assert.ok(!('a0' in s.seen));
  assert.ok('n7' in s.seen);
});

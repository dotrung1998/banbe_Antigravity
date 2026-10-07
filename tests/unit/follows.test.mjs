import test from 'node:test';
import assert from 'node:assert/strict';
import { applyFollowChange, buildFollowedHosts, filterFollowedHosts, followWriteOk } from '../../src/lib/follows.js';
import { createFollowSync } from '../../src/lib/followSync.js';

const org = (id, name, extra = {}) => ({ id, name, avatar_path: '', avatar_r2_ref: '', verified: false, ...extra });

// A fake backend holding per-user follow rows, with controllable latency/failures.
function fakeApi({ follows = {}, orgs = [], failWrites = false, gate = null } = {}) {
  const calls = [];
  const wait = async () => { if (gate) await gate.promise; };
  return {
    calls, follows,
    listFollows: async (uid) => { calls.push(['list', uid]); await wait(); return { data: (follows[uid] || []).map(id => ({ organizer_id: id })), error: null }; },
    listOrganizers: async (ids) => ({ data: orgs.filter(o => ids.includes(o.id)), error: null }),
    insertFollow: async (uid, id) => { calls.push(['ins', uid, id]); await wait(); if (failWrites) return { error: { message: 'boom' } }; (follows[uid] ||= []).push(id); return { error: null }; },
    deleteFollow: async (uid, id) => { calls.push(['del', uid, id]); await wait(); if (failWrites) return { error: { message: 'boom' } }; follows[uid] = (follows[uid] || []).filter(x => x !== id); return { error: null }; },
  };
}
const harness = (api, uid0 = 'u1') => {
  let uid = uid0; const snaps = []; const changes = [];
  const sync = createFollowSync({ api, getUid: () => uid, onState: s => snaps.push(s), onFollowChange: (id, f) => changes.push([id, f]) });
  return { sync, setUid: (u) => { uid = u; }, snaps, changes };
};

test('pure helpers: idempotent membership, alphabetical rows, unavailable hosts kept last, name-only search', () => {
  assert.deepEqual(applyFollowChange(['a'], 'a', true), ['a']);
  assert.deepEqual(applyFollowChange(['a'], 'b', true), ['a', 'b']);
  assert.deepEqual(applyFollowChange(['a', 'b'], 'a', false), ['b']);
  const rows = buildFollowedHosts([{ organizer_id: 'z' }, { organizer_id: 'gone' }, { organizer_id: 'a' }, { organizer_id: 'a' }], [org('a', 'Álpha'), org('z', 'Zed')]);
  assert.deepEqual(rows.map(r => r.organizerId), ['a', 'z', 'gone']);
  assert.equal(rows[2].available, false);
  assert.deepEqual(filterFollowedHosts(rows, 'alpha').map(r => r.organizerId), ['a']); // accent-insensitive
  assert.deepEqual(filterFollowedHosts(rows, 'gone'), []);                               // unavailable never matches a name
  assert.equal(followWriteOk({ code: '23505' }, true), true);
  assert.equal(followWriteOk({ code: '23505' }, false), false);
});

test('loads only the signed-in user\'s own rows', async () => {
  const api = fakeApi({ follows: { u1: ['a'], u2: ['b'] }, orgs: [org('a', 'A'), org('b', 'B')] });
  const h = harness(api);
  await h.sync.load();
  assert.deepEqual(h.sync.getState().ids, ['a']);
  assert.deepEqual(api.calls.filter(c => c[0] === 'list').map(c => c[1]), ['u1']);
});

test('account switch clears the previous account state immediately and a late response cannot leak into it', async () => {
  let release; const gate = { promise: new Promise(r => { release = r; }) };
  const api = fakeApi({ follows: { u1: ['a'], u2: ['b'] }, orgs: [org('a', 'A'), org('b', 'B')], gate });
  const h = harness(api);
  const pending = h.sync.load();      // u1's read is in flight
  h.setUid('u2');                     // account switches meanwhile
  h.sync.sync();
  assert.deepEqual(h.sync.getState(), { ids: [], hosts: [], status: 'idle', error: '', writeError: '' });
  release(); await pending;           // u1's response lands late
  assert.deepEqual(h.sync.getState().ids, []); // not applied to u2
  await h.sync.load();
  assert.deepEqual(h.sync.getState().ids, ['b']);
});

test('sign-out clears; nothing is requested without a user', async () => {
  const api = fakeApi({ follows: { u1: ['a'] }, orgs: [org('a', 'A')] });
  const h = harness(api);
  await h.sync.load();
  h.setUid(null); h.sync.sync();
  assert.equal(h.sync.getState().status, 'idle');
  const n = api.calls.length;
  await h.sync.load(); assert.equal(await h.sync.setFollowing('a', true), false);
  assert.equal(api.calls.length, n);
});

test('follow writes through, patches other views, and re-reads the truth', async () => {
  const api = fakeApi({ follows: { u1: [] }, orgs: [org('a', 'A')] });
  const h = harness(api);
  await h.sync.load();
  assert.equal(await h.sync.setFollowing('a', true), true);
  assert.deepEqual(h.sync.getState().ids, ['a']);
  assert.deepEqual(h.sync.getState().hosts.map(r => r.name), ['A']); // real name from the re-read
  assert.deepEqual(h.changes, [['a', true]]);
  assert.equal(await h.sync.setFollowing('a', false), true);
  assert.deepEqual(h.sync.getState().ids, []);
  assert.deepEqual(api.follows.u1, []);
});

test('a failed write reverts honestly and reports it (follow and unfollow)', async () => {
  const api = fakeApi({ follows: { u1: ['a'] }, orgs: [org('a', 'A'), org('b', 'B')], failWrites: true });
  const h = harness(api);
  await h.sync.load();
  assert.equal(await h.sync.setFollowing('b', true), false);
  assert.deepEqual(h.sync.getState().ids, ['a']);
  assert.match(h.sync.getState().writeError, /follow/i);
  assert.equal(await h.sync.setFollowing('a', false), false);
  assert.deepEqual(h.sync.getState().ids, ['a']);
  assert.deepEqual(h.sync.getState().hosts.map(r => r.organizerId), ['a']); // row restored
  assert.deepEqual(h.changes.slice(-2), [['a', false], ['a', true]]);       // views patched, then reverted
});

test('double tap is ignored: one write per host at a time', async () => {
  let release; const gate = { promise: new Promise(r => { release = r; }) };
  const api = fakeApi({ follows: { u1: [] }, orgs: [org('a', 'A')], gate });
  const h = harness(api);
  const first = h.sync.setFollowing('a', true);
  const second = await h.sync.setFollowing('a', true);
  assert.equal(second, false);
  release(); assert.equal(await first, true);
  assert.equal(api.calls.filter(c => c[0] === 'ins').length, 1);
});

test('a write finishing after an account switch does not touch the new account', async () => {
  let release; const gate = { promise: new Promise(r => { release = r; }) };
  const api = fakeApi({ follows: { u1: [], u2: [] }, orgs: [org('a', 'A')], gate });
  const h = harness(api);
  const w = h.sync.setFollowing('a', true);
  h.setUid('u2'); h.sync.sync();
  release(); await w;
  assert.deepEqual(h.sync.getState().ids, []);
  assert.equal(h.sync.getState().writeError, '');
});

test('server-fresh flag (another device) is folded in; unknown until loaded', async () => {
  const api = fakeApi({ follows: { u1: [] }, orgs: [org('a', 'A')] });
  const h = harness(api);
  assert.equal(h.sync.reconcile('a', true), false); // not loaded yet: ignore
  await h.sync.load();
  assert.equal(h.sync.reconcile('a', true), true);
  assert.deepEqual(h.sync.getState().ids, ['a']);
  assert.equal(h.sync.reconcile('a', true), false);
});

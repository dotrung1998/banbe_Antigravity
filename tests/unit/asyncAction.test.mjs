import test from 'node:test';
import assert from 'node:assert/strict';
import { reduceAction, initialAction, isLocked, runOperation } from '../../src/lib/asyncAction.js';

// Mirrored by apps/ios/BanbeAppTests/AsyncActionTests.swift — change both together.
const run = (events, from = initialAction) => events.reduce(reduceAction, from);

test('happy path: idle → pending → success → completed, callback flag fires once', () => {
  let s = run([{ type: 'start' }]);
  assert.equal(s.phase, 'pending');
  s = reduceAction(s, { type: 'resolve', ok: true });
  assert.equal(s.phase, 'success');
  assert.equal(s.fired, false);
  s = reduceAction(s, { type: 'animDone' });
  assert.equal(s.phase, 'completed');
  assert.equal(s.fired, true);
  const again = reduceAction(s, { type: 'animDone' });
  assert.equal(again, s, 'a second animDone changes nothing, so the callback cannot fire twice');
});

test('duplicate start while pending or after success is ignored', () => {
  const p = run([{ type: 'start' }]);
  assert.equal(reduceAction(p, { type: 'start' }), p);
  const ok = run([{ type: 'start' }, { type: 'resolve', ok: true }]);
  assert.equal(reduceAction(ok, { type: 'start' }), ok);
  assert.ok(isLocked('pending') && isLocked('success') && isLocked('completed'));
  assert.ok(!isLocked('idle') && !isLocked('failure'));
});

test('failure never reaches success and resets to idle keeping the error', () => {
  let s = run([{ type: 'start' }, { type: 'resolve', ok: false, error: 'NETWORK' }]);
  assert.equal(s.phase, 'failure');
  assert.equal(reduceAction(s, { type: 'animDone' }), s);
  s = reduceAction(s, { type: 'reset' });
  assert.deepEqual(s, { phase: 'idle', error: 'NETWORK', fired: false });
  assert.equal(reduceAction(s, { type: 'start' }).error, null);
});

test('resolve outside pending and reset while pending are ignored', () => {
  assert.equal(reduceAction(initialAction, { type: 'resolve', ok: true }), initialAction);
  const p = run([{ type: 'start' }]);
  assert.equal(reduceAction(p, { type: 'reset' }), p);
});

test('a completed stay-and-update button resets for the next use', () => {
  const s = run([{ type: 'start' }, { type: 'resolve', ok: true }, { type: 'animDone' }, { type: 'reset' }]);
  assert.deepEqual(s, initialAction);
});

test('runOperation: only an explicit success is a success', async () => {
  assert.deepEqual(await runOperation(async () => true), { ok: true, error: null });
  assert.deepEqual(await runOperation(async () => ({ ok: true })), { ok: true, error: null });
  assert.deepEqual(await runOperation(async () => ({ ok: false, error: 'X' })), { ok: false, error: 'X' });
  assert.deepEqual(await runOperation(async () => false), { ok: false, error: null });
  assert.deepEqual(await runOperation(async () => undefined), { ok: false, error: null });
  assert.deepEqual(await runOperation(async () => { throw new Error('boom'); }), { ok: false, error: 'boom' });
});

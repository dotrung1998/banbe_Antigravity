import test from 'node:test';
import assert from 'node:assert/strict';
import * as P from '../../src/lib/keychainPhysics.js';

test('damping converges and settles; values stay bounded', () => {
  const st = P.createState();
  P.swing(st, 1);
  let max = 0, frames = 0;
  while (!P.isSettled(st) && frames < 10000) {
    P.step(st, 1 / 60); frames++;
    max = Math.max(max, Math.abs(st.theta));
    assert.ok(Math.abs(st.theta) <= P.MAX_ANGLE + 1e-9);
    assert.ok(st.stretch <= P.MAX_STRETCH && st.stretch >= P.MIN_STRETCH);
  }
  assert.ok(P.isSettled(st), 'settles');
  assert.ok(frames < 1200, `settled in ${frames} frames`);
  assert.ok(max > 0.05, 'swing actually moved');
});

test('settled state is detected and rest() zeroes it', () => {
  const st = P.createState();
  assert.ok(P.isSettled(st));
  st.theta = 0.01;
  assert.ok(!P.isSettled(st));
  P.rest(st);
  assert.equal(st.theta, 0);
});

test('drag clamps stretch and angle', () => {
  const st = P.createState();
  P.dragTo(st, 1e6, 1e6, 100);
  assert.equal(st.stretch, P.MAX_STRETCH);
  assert.equal(st.theta, P.MAX_ANGLE);
  P.dragTo(st, -1e6, -1e6, 100);
  assert.equal(st.stretch, P.MIN_STRETCH);
  assert.equal(st.theta, -P.MAX_ANGLE);
  P.dragTo(st, NaN, Infinity * 0, 100);
  assert.equal(st.theta, 0);
});

test('impulse is capped; sensor impulse capped and rate limited', () => {
  const st = P.createState();
  assert.equal(P.applyImpulse(st, 100), P.SENSOR_IMPULSE_CAP);
  assert.equal(P.applyImpulse(st, -100), -P.SENSOR_IMPULSE_CAP);
  const s2 = P.createState();
  assert.ok(Math.abs(P.swing(s2, 1)) <= P.MAX_SWING_IMPULSE);
  const s3 = P.createState();
  let r = P.sensorImpulse(s3, 1e6, 1000, null);
  assert.equal(Math.abs(r.applied), P.SENSOR_IMPULSE_CAP);
  const before = s3.omega;
  r = P.sensorImpulse(s3, 1e6, 1050, r.lastAt);
  assert.equal(r.applied, 0);
  assert.equal(s3.omega, before);
  r = P.sensorImpulse(s3, 1e6, 1130, r.lastAt);
  assert.notEqual(r.applied, 0);
});

test('huge dt is clamped and never blows up', () => {
  const st = P.createState();
  P.swing(st, 1);
  P.step(st, 1e9);
  assert.ok(Number.isFinite(st.theta) && Math.abs(st.theta) <= P.MAX_ANGLE);
  P.step(st, NaN);
  assert.ok(Number.isFinite(st.theta));
});

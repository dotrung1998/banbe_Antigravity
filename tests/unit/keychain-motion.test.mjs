import test from 'node:test';
import assert from 'node:assert/strict';
import { createKeychainController } from '../../src/lib/keychainMotion.js';

function makeEnv({ reduced = false, vibrate = true, DME = 'plain', secure = true } = {}) {
  const raf = { id: 0, cbs: new Map(), t: 0 };
  const listeners = { doc: {}, win: {} };
  const add = (bag) => (n, f) => { (bag[n] ||= new Set()).add(f); };
  const rem = (bag) => (n, f) => { bag[n]?.delete(f); };
  const mqlL = new Set();
  const mql = { matches: reduced, addEventListener: (_, f) => mqlL.add(f), removeEventListener: (_, f) => mqlL.delete(f) };
  const document = { visibilityState: 'visible', addEventListener: add(listeners.doc), removeEventListener: rem(listeners.doc) };
  const win = { isSecureContext: secure, matchMedia: () => mql, addEventListener: add(listeners.win), removeEventListener: rem(listeners.win) };
  const vib = [];
  const navigator = vibrate ? { vibrate: (n) => { vib.push(n); return true; } } : {};
  let DeviceMotionEvent;
  if (DME === 'plain') DeviceMotionEvent = {};
  if (DME === 'granted') DeviceMotionEvent = { requestPermission: async () => 'granted' };
  if (DME === 'denied') DeviceMotionEvent = { requestPermission: async () => 'denied' };
  if (DME === 'throws') DeviceMotionEvent = { requestPermission: async () => { throw new Error('x'); } };
  const env = {
    raf: (cb) => { const id = ++raf.id; raf.cbs.set(id, cb); return id; },
    caf: (id) => raf.cbs.delete(id),
    now: () => raf.t,
    document, window: win, navigator, DeviceMotionEvent,
  };
  const frame = (ms = 16) => { raf.t += ms; const cbs = [...raf.cbs]; raf.cbs.clear(); cbs.forEach(([, cb]) => cb(raf.t)); };
  const count = (bag, n) => (bag[n]?.size || 0);
  return { env, raf, listeners, mql, mqlL, document, win, vib, frame, count };
}

const mk = (e, extra = {}) => createKeychainController({ env: e.env, lengthPx: 100, onFrame: () => {}, ...extra });

test('no loop at idle; swing starts it; settles then stops', () => {
  const e = makeEnv(); const c = mk(e);
  assert.equal(e.raf.cbs.size, 0);
  c.swing(1);
  assert.equal(e.raf.cbs.size, 1);
  let n = 0;
  while (e.raf.cbs.size && n++ < 5000) e.frame();
  assert.equal(e.raf.cbs.size, 0);
  assert.ok(!c.running);
  c.destroy();
});

test('hidden document stops loop; visible resumes', () => {
  const e = makeEnv(); const c = mk(e);
  c.swing(1);
  e.document.visibilityState = 'hidden';
  e.listeners.doc.visibilitychange.forEach(f => f());
  assert.equal(e.raf.cbs.size, 0);
  e.document.visibilityState = 'visible';
  e.listeners.doc.visibilitychange.forEach(f => f());
  assert.equal(e.raf.cbs.size, 1);
  c.destroy();
});

test('reduced motion: no loop, swing only highlights; live change stops loop', () => {
  let lit = 0;
  const e = makeEnv({ reduced: true }); const c = mk(e, { onHighlight: () => lit++ });
  c.swing(1);
  assert.equal(e.raf.cbs.size, 0);
  assert.equal(lit, 1);
  c.destroy();

  const e2 = makeEnv(); const c2 = mk(e2);
  c2.swing(1);
  assert.equal(e2.raf.cbs.size, 1);
  e2.mql.matches = true; e2.mqlL.forEach(f => f({ matches: true }));
  assert.equal(e2.raf.cbs.size, 0);
  c2.destroy();
});

test('disabled motion never loops', () => {
  const e = makeEnv(); const c = mk(e, { enabled: false });
  c.swing(1); assert.equal(e.raf.cbs.size, 0);
  c.setEnabled(true); c.swing(1); assert.equal(e.raf.cbs.size, 1);
  c.setEnabled(false); assert.equal(e.raf.cbs.size, 0);
  c.destroy();
});

test('destroy cancels raf and removes all listeners', () => {
  const e = makeEnv(); const c = mk(e);
  c.swing(1);
  c.destroy();
  assert.equal(e.raf.cbs.size, 0);
  assert.equal(e.count(e.listeners.doc, 'visibilitychange'), 0);
  assert.equal(e.mqlL.size, 0);
  c.swing(1);
  assert.equal(e.raf.cbs.size, 0);
});

test('no devicemotion listener before permission; granted attaches; hide/destroy detach', async () => {
  const e = makeEnv({ DME: 'granted' }); const c = mk(e);
  assert.equal(e.count(e.listeners.win, 'devicemotion'), 0);
  assert.equal(await c.enableTilt(), 'granted');
  assert.equal(e.count(e.listeners.win, 'devicemotion'), 1);
  e.document.visibilityState = 'hidden';
  e.listeners.doc.visibilitychange.forEach(f => f());
  assert.equal(e.count(e.listeners.win, 'devicemotion'), 0);
  e.document.visibilityState = 'visible';
  e.listeners.doc.visibilitychange.forEach(f => f());
  assert.equal(e.count(e.listeners.win, 'devicemotion'), 1);
  // rate limited + capped impulse
  const h = [...e.listeners.win.devicemotion][0];
  h({ accelerationIncludingGravity: { x: 1e6 } });
  const w1 = c.state.omega;
  e.raf.t += 50; h({ accelerationIncludingGravity: { x: 1e6 } });
  assert.equal(c.state.omega, w1);
  c.destroy();
  assert.equal(e.count(e.listeners.win, 'devicemotion'), 0);
});

test('permission denied / throws / unsupported / insecure are silent', async () => {
  for (const [DME, want] of [['denied', 'denied'], ['throws', 'denied'], ['none', 'unsupported']]) {
    const e = makeEnv({ DME }); const c = mk(e);
    assert.equal(await c.enableTilt(), want);
    assert.equal(e.count(e.listeners.win, 'devicemotion'), 0);
    c.destroy();
  }
  const e = makeEnv({ DME: 'granted', secure: false }); const c = mk(e);
  assert.equal(await c.enableTilt(), 'insecure');
  assert.equal(e.count(e.listeners.win, 'devicemotion'), 0);
});

test('vibrate absent does not throw; present at most grab+release', () => {
  const e = makeEnv({ vibrate: false }); const c = mk(e);
  assert.doesNotThrow(() => { c.grab(0, 0); c.move(0, 50); c.release(); });
  c.destroy();
  const e2 = makeEnv(); const c2 = mk(e2);
  c2.grab(0, 0);
  for (let i = 0; i < 50; i++) c2.move(i, i);
  c2.release();
  assert.equal(e2.vib.length, 2);
  c2.destroy();
});

test('drag emits frames without a loop; release starts loop and returns to rest', () => {
  let last;
  const e = makeEnv(); const c = mk(e, { onFrame: (s) => { last = { ...s }; } });
  c.grab(0, 0); c.move(0, 1e5);
  assert.equal(e.raf.cbs.size, 0);
  assert.ok(last.stretch > 0);
  c.release();
  assert.equal(e.raf.cbs.size, 1);
  let n = 0; while (e.raf.cbs.size && n++ < 5000) e.frame();
  assert.equal(last.stretch, 0);
  assert.equal(last.theta, 0);
  c.destroy();
});

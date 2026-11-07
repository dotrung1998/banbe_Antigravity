import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import {
  APP_EVENT_PROPS, filterAppEvent, createAppEventsSink, installAppEventsSink, track, setAnalyticsSink,
  claimAppOpenedToday, localDayKey, eventOpenSource, ticketDayBucket,
} from '../../src/lib/analytics.js';
import { flagOn, normalizeFlags } from '../../src/lib/featureFlags.js';

// First-party measurement (migration 196). Shared contract: tests/fixtures/app-events.json, also read by
// apps/ios/BanbeAppTests/AppEventsTests.swift and the server's app_event_names whitelist.
const fixture = JSON.parse(readFileSync(new URL('../fixtures/app-events.json', import.meta.url), 'utf8')).events;

test('the client whitelist is exactly the shared fixture', () => {
  assert.deepEqual(Object.keys(APP_EVENT_PROPS).sort(), Object.keys(fixture).sort());
  for (const [name, props] of Object.entries(fixture)) assert.deepEqual([...APP_EVENT_PROPS[name]].sort(), [...props].sort(), name);
});

// Every track('<name>', { keys }) / { type: 'track', name, props } literal in src/ must be in the fixture.
function sourceFiles(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    return statSync(p).isDirectory() ? sourceFiles(p) : /\.(js|jsx)$/.test(f) ? [p] : [];
  });
}
const propKeys = (body) => (body || '').split(',').map(x => x.trim()).filter(Boolean)
  .map(x => (x.match(/^([A-Za-z_$][\w$]*)\s*(?::|$)/) || [])[1]).filter(Boolean);

test('every event the web app emits is in the fixture, with only allowed prop keys', () => {
  const root = new URL('../../src/', import.meta.url).pathname;
  const seen = new Set();
  for (const file of sourceFiles(root)) {
    const src = readFileSync(file, 'utf8');
    const calls = [
      ...[...src.matchAll(/\btrack\('([a-z0-9_]+)'(?:\s*,\s*\{([^{}]*)\})?/g)].map(m => [m[1], m[2]]),
      ...[...src.matchAll(/type: 'track', name: '([a-z0-9_]+)'(?:, props: \{([^{}]*)\})?/g)].map(m => [m[1], m[2]]),
    ];
    for (const [name, body] of calls) {
      seen.add(name);
      assert.ok(fixture[name], `${file}: '${name}' is not in tests/fixtures/app-events.json`);
      for (const k of propKeys(body)) assert.ok(fixture[name].includes(k), `${file}: '${name}' sends '${k}', not allowed`);
    }
  }
  for (const name of ['app_opened', 'event_opened', 'ticket_opened', 'notification_opened', 'share_completed', 'follow_tapped']) {
    assert.ok(seen.has(name), `the web app never emits ${name}`);
  }
});

test('filter keeps whitelisted keys only, stringifies scalars, drops unknown names and long/odd values', () => {
  assert.equal(filterAppEvent('made_up', { a: 1 }), null);
  assert.deepEqual(filterAppEvent('app_opened', { email: 'x@y.z' }), { name: 'app_opened', props: {} });
  assert.deepEqual(filterAppEvent('event_opened', { event_id: 'abc', source: 'home', name: 'Supper', email: 'a@b' }),
    { name: 'event_opened', props: { event_id: 'abc', source: 'home' } });
  assert.deepEqual(filterAppEvent('onboarding_completed', { answered_questions: 3, skipped_all: false }),
    { name: 'onboarding_completed', props: { answered_questions: '3', skipped_all: 'false' } });
  assert.deepEqual(filterAppEvent('follow_tapped', { context: 'x'.repeat(65) }).props, {});
  assert.deepEqual(filterAppEvent('follow_tapped', { context: { nested: 1 } }).props, {});
  assert.deepEqual(filterAppEvent('rewards_goal_set', { goal: NaN }).props, {});
  assert.deepEqual(filterAppEvent('follow_tapped', null).props, {});
  assert.equal(filterAppEvent('constructor', {}), null);
});

function harness({ on = true, signedIn = true, batchSize = 20 } = {}) {
  const calls = [];
  const gate = { on, signedIn };
  let tick = null;
  const listeners = {};
  const target = { addEventListener: (t, f) => { listeners[t] = f; }, removeEventListener: (t) => { delete listeners[t]; } };
  const doc = { visibilityState: 'visible', addEventListener: (t, f) => { listeners[t] = f; }, removeEventListener: (t) => { delete listeners[t]; } };
  const sink = createAppEventsSink({
    rpc: (fn, args) => { calls.push({ fn, args }); return Promise.resolve({ data: { success: true, stored: args.p_events.length } }); },
    isEnabled: () => gate.on, isSignedIn: () => gate.signedIn, batchSize,
    timers: { setInterval: (f) => { tick = f; return 1; }, clearInterval: () => { tick = null; } }, target, doc,
  });
  return { calls, gate, sink, fire: (t) => listeners[t]?.(), tick: () => tick?.(), doc, listeners };
}

test('nothing is queued or sent while the switch is off or nobody is signed in', async () => {
  const off = harness({ on: false });
  off.sink.push({ name: 'app_opened' });
  off.tick(); await off.sink.flush();
  assert.equal(off.sink.size(), 0);
  assert.equal(off.calls.length, 0);

  const out = harness({ signedIn: false });
  out.sink.push({ name: 'app_opened' });
  await out.sink.flush();
  assert.equal(out.calls.length, 0);
});

test('switch turning off or sign-out before a flush drops the queue unsent', async () => {
  const h = harness();
  h.sink.push({ name: 'app_opened' });
  h.sink.push({ name: 'schedule_opened' });
  h.gate.signedIn = false;
  await h.sink.flush();
  assert.equal(h.calls.length, 0);
  assert.equal(h.sink.size(), 0);
  h.gate.signedIn = true;
  h.sink.push({ name: 'app_opened' });
  h.gate.on = false;
  h.tick();
  assert.equal(h.calls.length, 0);
});

test('batches: flushes at 20 queued, on the timer, on hidden and pagehide; platform web; props filtered', async () => {
  const h = harness();
  for (let i = 0; i < 19; i++) h.sink.push({ name: 'event_opened', props: { event_id: `e${i}`, source: 'home', title: 'secret' } });
  assert.equal(h.calls.length, 0);
  h.sink.push({ name: 'made_up_event' }); // unknown names never enter the queue
  assert.equal(h.sink.size(), 19);
  h.sink.push({ name: 'app_opened' });
  assert.equal(h.calls.length, 1);
  const { fn, args } = h.calls[0];
  assert.equal(fn, 'log_app_events');
  assert.equal(args.p_platform, 'web');
  assert.equal(args.p_events.length, 20);
  assert.deepEqual(args.p_events[0], { name: 'event_opened', props: { event_id: 'e0', source: 'home' } });
  assert.equal(h.sink.size(), 0);

  h.sink.push({ name: 'app_opened' });
  h.tick();
  assert.equal(h.calls.length, 2);
  h.tick(); // empty queue: no call
  assert.equal(h.calls.length, 2);

  h.sink.push({ name: 'app_opened' });
  h.doc.visibilityState = 'hidden';
  h.fire('visibilitychange');
  assert.equal(h.calls.length, 3);
  h.sink.push({ name: 'app_opened' });
  h.fire('pagehide');
  assert.equal(h.calls.length, 4);
});

test('a rejecting or throwing rpc never throws out of the sink', async () => {
  const sink = createAppEventsSink({
    rpc: () => { throw new Error('boom'); }, isEnabled: () => true, isSignedIn: () => true, batchSize: 1,
    timers: { setInterval: () => 0, clearInterval: () => {} }, target: null, doc: null,
  });
  assert.doesNotThrow(() => sink.push({ name: 'app_opened' }));
  const sink2 = createAppEventsSink({
    rpc: () => Promise.reject(new Error('offline')), isEnabled: () => true, isSignedIn: () => true, batchSize: 1,
    timers: { setInterval: () => 0, clearInterval: () => {} }, target: null, doc: null,
  });
  sink2.push({ name: 'app_opened' });
  await sink2.flush();
  const sink3 = createAppEventsSink({
    rpc: () => Promise.resolve({ data: { success: true } }), isEnabled: () => { throw new Error('x'); }, isSignedIn: () => true,
    timers: { setInterval: () => 0, clearInterval: () => {} }, target: null, doc: null,
  });
  assert.doesNotThrow(() => sink3.push({ name: 'app_opened' }));
});

test('install routes track() to the sink; uninstall drops the queue and goes back to the no-op', async () => {
  const calls = [];
  const uninstall = installAppEventsSink({
    rpc: (fn, args) => { calls.push(args); return Promise.resolve({ data: { success: true } }); },
    isEnabled: () => true, isSignedIn: () => true, batchSize: 2,
    timers: { setInterval: () => 0, clearInterval: () => {} }, target: null, doc: null,
  });
  track('app_opened');
  uninstall();
  track('app_opened');
  track('app_opened');
  assert.equal(calls.length, 0);
  setAnalyticsSink(null);
});

test('the app_events switch is off unless the server says true', () => {
  assert.equal(flagOn({}, 'app_events'), false);
  assert.equal(flagOn({ app_events: false }, 'app_events'), false);
  assert.equal(flagOn({ app_events: true }, 'app_events'), true);
  assert.deepEqual(normalizeFlags({ app_events: true }), { app_events: true });
});

test('app_opened is claimed once per local day per device', () => {
  const m = new Map();
  const store = { getItem: k => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, v) };
  const d1 = new Date(2026, 9, 23, 8, 0), d1b = new Date(2026, 9, 23, 23, 59), d2 = new Date(2026, 9, 24, 0, 1);
  assert.equal(localDayKey(d1), '2026-10-23');
  assert.equal(claimAppOpenedToday(store, d1), true);
  assert.equal(claimAppOpenedToday(store, d1b), false);
  assert.equal(claimAppOpenedToday(store, d2), true);
  assert.equal(claimAppOpenedToday({ getItem() { throw new Error('blocked'); } }, d1), true);
});

test('event_opened source buckets (same as iOS EventOpenSource)', () => {
  assert.equal(eventOpenSource({ screen: 'home' }), 'home');
  assert.equal(eventOpenSource({ screen: 'home', searchOverlayOpen: true }), 'search');
  assert.equal(eventOpenSource({ screen: 'search' }), 'search');
  assert.equal(eventOpenSource({ screen: 'mapExplore' }), 'map');
  assert.equal(eventOpenSource({ screen: 'schedule' }), 'schedule');
  assert.equal(eventOpenSource({ screen: 'organizerProfile' }), 'other');
  assert.equal(eventOpenSource(null), 'other');
});

// Same vectors as AppEventsTests.testTicketDayBucket (iOS).
test('ticket_opened day bucket compares calendar days in the venue zone', () => {
  const at = (iso) => Date.parse(iso);
  const hcm = 'Asia/Ho_Chi_Minh';
  // 2026-10-23 20:00 in HCMC is 13:00Z.
  assert.equal(ticketDayBucket(at('2026-10-23T13:00:00Z'), at('2026-10-23T01:00:00Z'), hcm), 'day_of');
  assert.equal(ticketDayBucket(at('2026-10-23T13:00:00Z'), at('2026-10-22T16:59:00Z'), hcm), 'before'); // 23:59 on the 22nd
  assert.equal(ticketDayBucket(at('2026-10-23T13:00:00Z'), at('2026-10-23T17:00:00Z'), hcm), 'after'); // 00:00 on the 24th
  // Los Angeles: 2026-10-23 19:00 PDT is 02:00Z on the 24th.
  assert.equal(ticketDayBucket(at('2026-10-24T02:00:00Z'), at('2026-10-23T16:00:00Z'), 'America/Los_Angeles'), 'day_of');
  assert.equal(ticketDayBucket(NaN, Date.now(), hcm), null);
});

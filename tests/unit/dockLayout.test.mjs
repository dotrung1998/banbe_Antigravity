import test from 'node:test';
import assert from 'node:assert/strict';
import { dockOrder, dockSlots, dockHighlightFor, dockNeighbor, CREATE_SLOT } from '../../src/lib/dockLayout.js';

test('switch off: the dock is unchanged', () => {
  assert.deepEqual(dockOrder(false), ['home', 'mapExplore', 'schedule', 'inbox', 'profile']);
  assert.deepEqual(dockSlots(false), dockOrder(false));
  assert.equal(dockHighlightFor('mapExplore', false), 'mapExplore');
  assert.equal(dockNeighbor('home', 1, false), 'mapExplore');
});

test('switch on: map leaves, "+" sits in the centre slot', () => {
  assert.deepEqual(dockOrder(true), ['home', 'schedule', 'inbox', 'profile']);
  const slots = dockSlots(true);
  assert.equal(slots.length, 5);
  assert.equal(slots[2], CREATE_SLOT);
  assert.ok(!dockOrder(true).includes(CREATE_SLOT));
  assert.ok(!slots.includes('mapExplore'));
});

test('switch on: map highlights Home, non-dock screens highlight nothing', () => {
  assert.equal(dockHighlightFor('mapExplore', true), 'home');
  assert.equal(dockHighlightFor('schedule', true), 'schedule');
  assert.equal(dockHighlightFor('event', true), null);
  assert.equal(dockHighlightFor('event', false), null);
});

test('switch on: swipe neighbours skip the "+" and stop at the ends', () => {
  assert.equal(dockNeighbor('schedule', 1, true), 'inbox');
  assert.equal(dockNeighbor('inbox', -1, true), 'schedule');
  assert.equal(dockNeighbor('home', -1, true), null);
  assert.equal(dockNeighbor('profile', 1, true), null);
  assert.equal(dockNeighbor('mapExplore', 1, true), null);
});

// Note 66 follow-up: the scrub target sees the centre "+" (shared fixture with iOS DockLayoutTests).
import { readFileSync } from 'node:fs';
import { scrubTarget } from '../../src/lib/dockLayout.js';
const scrubFx = JSON.parse(readFileSync(new URL('../fixtures/dock-scrub.json', import.meta.url), 'utf8'));

test('scrubTarget: every slot boundary and the centre "+" (switch on)', () => {
  for (const c of scrubFx.simpleShell) assert.deepEqual(scrubTarget(c.fraction, true), c.expect, `fraction ${c.fraction}`);
});

test('scrubTarget: switch off has no "+" slot', () => {
  for (const c of scrubFx.legacy) assert.deepEqual(scrubTarget(c.fraction, false), c.expect, `fraction ${c.fraction}`);
});

test('scrubTarget: drags release on the slot under the finger, "+" included', () => {
  for (const d of scrubFx.drags) assert.deepEqual(scrubTarget(d.path[d.path.length - 1], d.simpleShell), d.release, d._comment);
});

test('scrubTarget: never a tab id for the "+" and never NaN-driven', () => {
  assert.deepEqual(scrubTarget(NaN, true), { kind: 'tab', id: 'home' });
  for (let f = 0; f <= 1; f += 0.01) {
    const t = scrubTarget(f, true);
    if (t.kind === 'tab') assert.ok(dockOrder(true).includes(t.id));
  }
});

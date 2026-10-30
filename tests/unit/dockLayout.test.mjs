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

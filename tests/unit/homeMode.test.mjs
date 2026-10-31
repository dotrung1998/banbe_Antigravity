// Simple Shell Home view (note 66 follow-up). Shared fixture with iOS HomeModeTests.swift.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { effectiveHomeView, homeViewAfterSync, hostSegmentLocked, startHostingStep } from '../../src/lib/homeMode.js';

const fx = JSON.parse(readFileSync(new URL('../fixtures/home-mode.json', import.meta.url), 'utf8'));

test('effective view: organizer mode off is always Going out', () => {
  for (const c of fx.effective) assert.equal(effectiveHomeView(c.organizerMode, c.homeView), c.expect, JSON.stringify(c));
});

test('after a sync: coming on opens Hosting, staying on keeps the pick, off is Going out', () => {
  for (const c of fx.afterSync) assert.equal(homeViewAfterSync(c.prevOrganizerMode, c.prevHomeView, c.organizerMode), c.expect, JSON.stringify(c));
});

test('sign-out resets to Going out (and a stale host view never shows without organizer mode)', () => {
  assert.equal(fx.signOut.homeView, 'goer');
  assert.equal(effectiveHomeView(false, fx.signOut.homeView), 'goer');
});

test('Hosting segment is locked while organizer mode is off', () => {
  for (const c of fx.locked) assert.equal(hostSegmentLocked(c.organizerMode), c.locked, JSON.stringify(c));
});

test('start hosting: guest signs in first, off invites, on lands', () => {
  for (const c of fx.startHosting) assert.equal(startHostingStep(c), c.step, JSON.stringify(c));
});

test('homeView is session-only: never persisted, never read from a route', () => {
  const ctx = readFileSync(new URL('../../src/state/BanBeContext.jsx', import.meta.url), 'utf8');
  const routes = readFileSync(new URL('../../src/lib/routes.js', import.meta.url), 'utf8');
  const urlSync = readFileSync(new URL('../../src/lib/useUrlSync.js', import.meta.url), 'utf8');
  assert.ok(!/localStorage[^\n]*homeView/.test(ctx), 'homeView must not be written to localStorage');
  assert.ok(!routes.includes('homeView') && !urlSync.includes('homeView'), 'homeView must not come from routes');
  assert.ok(/PRIVATE_STATE_KEYS = \[[\s\S]*'homeView'/.test(ctx), 'homeView is reset on sign-out');
});

test('Home renders host content only through effectiveHomeView', () => {
  const home = readFileSync(new URL('../../src/screens/Home.jsx', import.meta.url), 'utf8');
  assert.ok(/effectiveHomeView\(s\.organizerMode, s\.homeView\)/.test(home));
  assert.ok(!/hostView = simpleShell && !!s\.organizerMode/.test(home), 'Home must not read organizerMode as the view');
});

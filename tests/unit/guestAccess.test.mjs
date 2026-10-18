// Web mirror of iOS GuestAccessTests (note 48): prompt copy, benefits order, resume and Back targets.
import test from 'node:test';
import assert from 'node:assert/strict';
import { GUEST_BROWSE_SCREENS, PROMPT_CONTEXTS, promptCopy, promptBenefits, makePrompt, loginBackTarget } from '../../src/lib/guestAccess.js';

const en = (_v, e) => e;

test('guests browse Home, Map and an event only', () => {
  assert.deepEqual([...GUEST_BROWSE_SCREENS].sort(), ['event', 'home', 'mapExplore', 'search']);
  for (const personal of ['profile', 'inbox', 'schedule', 'reserve', 'chat', 'notifications', 'reports', 'dashboard']) {
    assert.equal(GUEST_BROWSE_SCREENS.has(personal), false, personal);
  }
});

test('every prompt names what the guest was doing and never says "Sign up"', () => {
  for (const c of PROMPT_CONTEXTS) {
    const { title, body } = promptCopy(c, en);
    assert.ok(title && body, c);
    assert.ok(!/sign up/i.test(title + body), c);
  }
  assert.equal(promptCopy('reserve', en).title, 'Hold your seat');
});

test('the matching benefit comes first; follow swaps in its own row', () => {
  assert.equal(promptBenefits('message', en)[0].id, 'message');
  assert.equal(promptBenefits('reserve', en)[0].id, 'reserve');
  assert.deepEqual(promptBenefits('follow', en).map(r => r.id), ['save', 'reserve', 'follow']);
});

test('reserve and message resume after sign-in; save/follow/like just come back', () => {
  assert.deepEqual(makePrompt('reserve', { screen: 'event', eventKey: 'e1' }), { context: 'reserve', returnTo: 'event', resume: { type: 'reserve', eventKey: 'e1' } });
  assert.deepEqual(makePrompt('message', { screen: 'event', eventKey: 'e1' }).resume, { type: 'chat', eventKey: 'e1', back: 'event' });
  assert.equal(makePrompt('save', { screen: 'home', eventKey: 'e1' }).resume, null);
  assert.equal(makePrompt('like', { screen: 'login' }).returnTo, 'home', 'never returns to a non-browse screen');
});

test("Login's Back returns to the browse screen, else Welcome", () => {
  assert.equal(loginBackTarget('mapExplore'), 'mapExplore');
  assert.equal(loginBackTarget('event'), 'event');
  assert.equal(loginBackTarget('splash'), 'welcome');
  assert.equal(loginBackTarget(undefined), 'welcome');
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { reminderPhase } from '../../src/lib/eventReminder.js';

const now = Date.parse('2026-10-07T12:00:00Z');
const at = (h) => new Date(now + h * 3600000);

test('more than 24h away: no reminder', () => assert.equal(reminderPhase(at(24.5), { now }), null));
test('within 24h: soon', () => { assert.equal(reminderPhase(at(24), { now }), 'soon'); assert.equal(reminderPhase(at(1), { now }), 'soon'); });
test('started and still live: live', () => { assert.equal(reminderPhase(at(0), { now }), 'live'); assert.equal(reminderPhase(at(-5), { now }), 'live'); });
test('started more than 12h ago: no reminder', () => assert.equal(reminderPhase(at(-12.5), { now }), null));
test('ended / cancelled / missing date: no reminder', () => {
  assert.equal(reminderPhase(at(-1), { now, status: 'ended' }), null);
  assert.equal(reminderPhase(at(2), { now, status: 'cancelled' }), null);
  assert.equal(reminderPhase(null, { now }), null);
  assert.equal(reminderPhase('garbage', { now }), null);
});

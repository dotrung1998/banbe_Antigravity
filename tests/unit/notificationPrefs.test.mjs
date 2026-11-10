import test from 'node:test';
import assert from 'node:assert/strict';
import { NOTIF_PREF_GROUPS, groupOn, toggleGroup, notifPrefsSummary } from '../../src/lib/notificationPrefs.js';

const T = (_vi, en) => en;
const byKey = Object.fromEntries(NOTIF_PREF_GROUPS.map(g => [g.key, g]));

test('groups never contain disputes, new messages or the opt-in digest', () => {
  const all = NOTIF_PREF_GROUPS.flatMap(g => g.kinds);
  for (const k of ['dispute_message', 'dispute_resolved', 'payment_disputed', 'new_message', 'weekly_digest']) assert.ok(!all.includes(k), k);
  assert.equal(new Set(all).size, all.length, 'a kind belongs to one group only');
});

test('holds are Tickets, reminders are Events', () => {
  assert.ok(byKey.tickets.kinds.includes('hold_created'));
  assert.ok(!byKey.payments.kinds.includes('hold_created'));
  assert.ok(byKey.events.kinds.includes('event_reminder_day'));
});

test('toggling a group mutes all its kinds, toggling again restores the rest of the list', () => {
  const start = ['something_else'];
  const off = toggleGroup(start, byKey.payments);
  assert.equal(groupOn(off, byKey.payments), false);
  assert.ok(off.includes('something_else'));
  const on = toggleGroup(off, byKey.payments);
  assert.deepEqual(on, ['something_else']);
});

test('a partly muted group reads as off and turns fully on', () => {
  const partial = [byKey.tickets.kinds[0]];
  assert.equal(groupOn(partial, byKey.tickets), false);
  assert.deepEqual(toggleGroup(partial, byKey.tickets), []);
});

test('summary', () => {
  assert.equal(notifPrefsSummary([], T), 'All on');
  assert.equal(notifPrefsSummary(null, T), 'All on');
  assert.equal(notifPrefsSummary(byKey.events.kinds, T), '2 of 3 on');
  assert.equal(notifPrefsSummary(NOTIF_PREF_GROUPS.flatMap(g => g.kinds), T), 'All off');
});

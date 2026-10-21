import test from 'node:test';
import assert from 'node:assert/strict';
import { DELETE_REASONS, QUIETED_NOTIFICATION_KINDS, lossRows, retentionOffer } from '../../src/lib/accountRetention.js';

test('every leaving reason maps to exactly one fix; no reason, no offer', () => {
  assert.equal(retentionOffer('too_many_notifications'), 'quieterNotifications');
  assert.equal(retentionOffer('not_using'), 'retuneForYou');
  assert.equal(retentionOffer('privacy'), 'reviewPrivacy');
  for (const r of ['found_alternative', 'other', 'prefer_not_say']) assert.equal(retentionOffer(r), 'takeABreak');
  assert.equal(retentionOffer(''), null);
  assert.equal(retentionOffer(undefined), null);
  for (const r of DELETE_REASONS) assert.ok(retentionOffer(r.code), `${r.code} has an offer`);
});

test('reason codes match the server delete_account contract', () => {
  assert.deepEqual(DELETE_REASONS.map(r => r.code),
    ['not_using', 'privacy', 'found_alternative', 'too_many_notifications', 'other', 'prefer_not_say']);
});

test('quieter notifications never mutes transactional kinds', () => {
  for (const k of ['payment_confirmed', 'hold_created', 'refund_marked_sent', 'dispute_message', 'booking_cancelled', 'checked_in']) {
    assert.ok(!QUIETED_NOTIFICATION_KINDS.includes(k), `${k} stays on`);
  }
});

test('loss rows: zero rows hidden, most valuable first, coins only with Rewards on', () => {
  assert.deepEqual(lossRows({}), []);
  assert.deepEqual(lossRows({ bookedEvents: 2, savedEvents: 0, followedHosts: 3, coins: 40, rewardsEnabled: false, hostedEvents: 1 }),
    [{ kind: 'bookedEvents', count: 2 }, { kind: 'hostedEvents', count: 1 }, { kind: 'followedHosts', count: 3 }]);
  assert.deepEqual(lossRows({ savedEvents: 1, coins: 40, rewardsEnabled: true }),
    [{ kind: 'savedEvents', count: 1 }, { kind: 'coins', count: 40 }]);
  assert.deepEqual(lossRows({ coins: 0, rewardsEnabled: true }), [], 'zero coins hidden');
  assert.deepEqual(lossRows({ coins: null, rewardsEnabled: true }), [], 'unknown balance hidden');
});

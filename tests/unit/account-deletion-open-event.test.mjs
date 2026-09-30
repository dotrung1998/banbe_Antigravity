import test from 'node:test';
import assert from 'node:assert/strict';
import { findOpenEventsBlockingDeletion, isDeletionBlockedByOpenEvents } from '../../api/_lib/accountDeletion.js';

// Pure-function eligibility check for account deletion's open-event
// refusal (Task 2, Account/Settings pass) — this is the one piece of the
// delete_account endpoint testable without a live DB/auth session, per
// this ticket's own "no destructive integration test" constraint.

test('a live event blocks deletion', () => {
  const events = [{ id: 'e1', name: 'Live show', status: 'live' }];
  assert.equal(isDeletionBlockedByOpenEvents(events), true);
  assert.deepEqual(findOpenEventsBlockingDeletion(events).map(e => e.id), ['e1']);
});

test('a pending-review event blocks deletion', () => {
  const events = [{ id: 'e1', name: 'Awaiting approval', status: 'review' }];
  assert.equal(isDeletionBlockedByOpenEvents(events), true);
});

test('draft/cancelled/ended events never block deletion', () => {
  const events = [
    { id: 'e1', name: 'Draft', status: 'draft' },
    { id: 'e2', name: 'Cancelled', status: 'cancelled' },
    { id: 'e3', name: 'Ended', status: 'ended' },
  ];
  assert.equal(isDeletionBlockedByOpenEvents(events), false);
  assert.deepEqual(findOpenEventsBlockingDeletion(events), []);
});

test('a mix of open and closed events reports only the open ones', () => {
  const events = [
    { id: 'e1', name: 'Ended', status: 'ended' },
    { id: 'e2', name: 'Live', status: 'live' },
    { id: 'e3', name: 'Review', status: 'review' },
  ];
  const blocking = findOpenEventsBlockingDeletion(events);
  assert.deepEqual(blocking.map(e => e.id).sort(), ['e2', 'e3']);
});

test('no events at all never blocks deletion', () => {
  assert.equal(isDeletionBlockedByOpenEvents([]), false);
  assert.equal(isDeletionBlockedByOpenEvents(null), false);
  assert.equal(isDeletionBlockedByOpenEvents(undefined), false);
});

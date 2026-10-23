import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  notificationRoute, runItAgainDate, FEEDBACK, noteLength, clampNote, canSaveFeedback, feedbackWindowOpen,
  feedbackErrorText, hostFeedbackView, hostRecapStats,
} from '../../src/lib/coreLoops.js';

// Phase 2-3 core loops. Every vector in tests/fixtures/core-loops.json is shared with
// apps/ios/BanbeAppTests/CoreLoopsTests.swift — change both together.
const V = JSON.parse(readFileSync(new URL('../fixtures/core-loops.json', import.meta.url), 'utf8'));

test('notification routes match the contract (shared vectors)', () => {
  assert.ok(V.notificationRoutes.length >= 7);
  for (const v of V.notificationRoutes) {
    assert.deepEqual(notificationRoute(v.kind, v.data), { route: v.route, id: v.id }, `${v.kind} ${JSON.stringify(v.data)}`);
  }
});

test('notification routes: unknown kinds and missing ids route nowhere', () => {
  assert.equal(notificationRoute('new_message', { thread_id: 't' }), null);
  assert.equal(notificationRoute('event_reminder_day', { event_id: 'e1' }), null);
  assert.equal(notificationRoute('event_recap', {}), null);
  assert.equal(notificationRoute('host_event_recap', null), null);
  // A bundle without an event id still has a home; a count sent as a string still counts.
  assert.deepEqual(notificationRoute('follow_alert', { count: 2 }), { route: 'following', id: null });
  assert.deepEqual(notificationRoute('follow_alert', { event_id: 'e9', count: '3' }), { route: 'following', id: null });
  assert.deepEqual(notificationRoute('follow_alert', { event_id: 'e9' }), { route: 'event', id: 'e9' });
});

test('run it again: date and time (shared vectors)', () => {
  for (const v of V.runItAgain) {
    assert.deepEqual(runItAgainDate({ eventDate: v.eventDate, eventTime: v.eventTime, today: v.today }),
      { date: v.expectDate, time: v.expectTime }, v.case);
  }
});

test('run it again: never in the past, never sooner than 2 days, time kept', () => {
  // Event tomorrow: one week after it.
  assert.deepEqual(runItAgainDate({ eventDate: '2027-03-09', eventTime: '09:15:00', today: '2027-03-08' }), { date: '2027-03-16', time: '09:15' });
  // Event 6 days ago (a Tuesday): one week later is tomorrow, too soon -> next Tuesday at least 2 days ahead.
  assert.deepEqual(runItAgainDate({ eventDate: '2027-03-02', eventTime: '19:00', today: '2027-03-08' }), { date: '2027-03-16', time: '19:00' });
  // No original date: the earliest allowed day.
  assert.deepEqual(runItAgainDate({ eventDate: null, eventTime: null, today: '2027-03-08' }), { date: '2027-03-10', time: null });
  for (let i = 0; i < 40; i++) {
    const d = new Date(Date.UTC(2027, 0, 1 + i)).toISOString().slice(0, 10);
    const r = runItAgainDate({ eventDate: d, eventTime: '18:00', today: '2027-01-20' });
    assert.ok(r.date >= '2027-01-22', `${d} -> ${r.date}`);
    assert.equal(new Date(`${r.date}T00:00:00Z`).getUTCDay(), new Date(`${d}T00:00:00Z`).getUTCDay(), d);
  }
});

test('feedback limits match the contract', () => {
  assert.deepEqual(FEEDBACK, V.feedback);
  assert.equal(canSaveFeedback(1, ''), true);
  assert.equal(canSaveFeedback(-1, 'x'.repeat(V.feedback.noteMax)), true);
  assert.equal(canSaveFeedback(-1, 'x'.repeat(V.feedback.noteMax + 1)), false);
  assert.equal(canSaveFeedback(0, ''), false);
  assert.equal(canSaveFeedback(null, ''), false);
  // Counted like Postgres length(): one emoji is one character.
  assert.equal(noteLength('👍🏽ok'), 4);
  assert.equal(noteLength('😀'.repeat(500)), 500);
  assert.equal(noteLength(clampNote('😀'.repeat(501))), 500);
  assert.equal(clampNote('short'), 'short');
});

test('feedback window: 14 days after the start; unknown start leaves it to the server', () => {
  const start = Date.parse('2027-03-01T12:00:00Z');
  assert.equal(feedbackWindowOpen(start, start + 14 * 86400000), true);
  assert.equal(feedbackWindowOpen(start, start + 14 * 86400000 + 1), false);
  assert.equal(feedbackWindowOpen(null, start), true);
  assert.equal(feedbackErrorText('NOT_OPEN').en, 'Feedback for this event is closed.');
  assert.ok(feedbackErrorText('WHATEVER').en);
});

test('host feedback view: nothing below 3 answers, counts and unnamed notes from 3', () => {
  assert.deepEqual(hostFeedbackView({ responses: 2, hidden: true }), { hidden: true, responses: 2 });
  assert.deepEqual(hostFeedbackView(null), { hidden: true, responses: 0 });
  // A server that ever said hidden:false below the minimum is still not shown.
  assert.equal(hostFeedbackView({ responses: 2, hidden: false, up: 2, down: 0, notes: ['x'] }).hidden, true);
  assert.deepEqual(hostFeedbackView({ responses: V.feedback.hostMinResponses, hidden: false, up: 2, down: 1, notes: ['  Great ', '', 3] }),
    { hidden: false, responses: 3, up: 2, down: 1, notes: ['Great'] });
});

test('host recap stats read defensively', () => {
  assert.deepEqual(hostRecapStats({ confirmed_seats: 12, capacity: 20, checked_in: 9, new_followers: 3, repeat_guests: 2, photos: 5 }),
    { confirmedSeats: 12, capacity: 20, checkedIn: 9, newFollowers: 3, repeatGuests: 2, photos: 5 });
  assert.deepEqual(hostRecapStats({}), { confirmedSeats: 0, capacity: null, checkedIn: 0, newFollowers: 0, repeatGuests: 0, photos: 0 });
});

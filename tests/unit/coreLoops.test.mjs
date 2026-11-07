import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  notificationRoute, runItAgainDate, FEEDBACK, noteLength, clampNote, canSaveFeedback, feedbackWindowOpen,
  feedbackErrorText, hostFeedbackView, hostRecapStats,
  intentTitle, INTENT_TITLES, isEventLocalDay, shareMarket, shareWhen, shareInviteText, smsInviteHref, ZALO_COPIED,
} from '../../src/lib/coreLoops.js';
import { wallClockToMs } from '../../src/lib/eventMarket.js';
import { declaredGoals } from '../../src/lib/eventPrefs.js';

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

// ---------------------------------------------------------------- Phase 3 extras (L6-L8)

test('L6 intent titles match the contract (shared vectors)', () => {
  assert.equal(V.intentTitles.length, 5);
  for (const v of V.intentTitles) {
    const got = intentTitle(v.goal ? [v.goal] : []);
    assert.deepEqual(got, { goal: v.goal, vi: v.vi, en: v.en, whyVi: v.whyVi, whyEn: v.whyEn }, String(v.goal));
  }
  // Every onboarding goal id has a title (no goal silently falls back).
  assert.deepEqual(Object.keys(INTENT_TITLES).sort(), V.intentTitles.filter(v => v.goal).map(v => v.goal).sort());
});

test('L6 intent title: the FIRST stated goal wins; nothing stated or "no preference" -> plain For You', () => {
  assert.equal(intentTitle(['networking', 'meet_people']).goal, 'networking');
  assert.equal(intentTitle(declaredGoals({ goals: ['learn', 'experiences'] })).en, 'Learn something new');
  const none = V.intentTitles.find(v => v.goal === null);
  for (const g of [null, undefined, [], ['no_preference']]) {
    const t = intentTitle(declaredGoals({ goals: g }));
    assert.deepEqual([t.goal, t.en, t.whyEn], [null, none.en, null], JSON.stringify(g));
  }
  // An id this build doesn't know is skipped, never shown raw.
  assert.equal(intentTitle(['someday_new_goal', 'learn']).goal, 'learn');
  assert.equal(intentTitle(['someday_new_goal']).goal, null);
});

test('L7 the ticket is one tap away on the event day in the VENUE zone', () => {
  const start = wallClockToMs('2027-03-06', '19:00', 'America/New_York');
  assert.equal(isEventLocalDay(start, wallClockToMs('2027-03-06', '00:00', 'America/New_York'), 'America/New_York'), true);
  assert.equal(isEventLocalDay(start, wallClockToMs('2027-03-06', '23:59', 'America/New_York'), 'America/New_York'), true);
  assert.equal(isEventLocalDay(start, wallClockToMs('2027-03-05', '23:59', 'America/New_York'), 'America/New_York'), false);
  assert.equal(isEventLocalDay(start, wallClockToMs('2027-03-07', '00:00', 'America/New_York'), 'America/New_York'), false);
  // A Saigon event at 23:00 on the 6th, read at 01:00 on the 7th Saigon time (still the 6th in New York): the venue's
  // day decides, not the viewer's.
  const vn = wallClockToMs('2027-03-06', '23:00', 'Asia/Ho_Chi_Minh');
  const later = wallClockToMs('2027-03-07', '01:00', 'Asia/Ho_Chi_Minh');
  assert.equal(isEventLocalDay(vn, later, 'America/New_York'), true);
  assert.equal(isEventLocalDay(vn, later, 'Asia/Ho_Chi_Minh'), false);
  assert.equal(isEventLocalDay(NaN, Date.now(), 'Asia/Ho_Chi_Minh'), false);
});

test('L8 share text and sms link match the contract (shared vectors)', () => {
  const zones = { VN: 'Asia/Ho_Chi_Minh', US: 'America/New_York' };
  for (const v of V.shareText) {
    assert.equal(shareMarket(v.market.toLowerCase()), v.market);
    // `when` comes from the event's own start in the venue zone (2027-03-06 19:00 is a Saturday).
    assert.equal(shareWhen(wallClockToMs('2027-03-06', '19:00', zones[v.market]), zones[v.market], v.market), v.when, v.market);
    const text = shareInviteText({ name: v.name, when: v.when, url: v.url });
    assert.equal(text, v.text, v.market);
    if (v.sms) assert.equal(smsInviteHref(text), v.sms);
  }
});

test('L8 market, time formats and toast', () => {
  assert.equal(shareMarket(''), null);
  assert.equal(shareMarket('FR'), null);
  assert.equal(shareMarket(null), null);
  const ny = 'America/New_York';
  assert.equal(shareWhen(wallClockToMs('2027-03-07', '00:05', ny), ny, 'US'), 'Sun, Mar 7 ▪︎ 12:05 AM');
  assert.equal(shareWhen(wallClockToMs('2027-03-07', '12:30', ny), ny, 'US'), 'Sun, Mar 7 ▪︎ 12:30 PM');
  assert.equal(shareWhen(wallClockToMs('2027-12-28', '09:00', 'Asia/Ho_Chi_Minh'), 'Asia/Ho_Chi_Minh', 'VN'), 'Th 3, 28.12 ▪︎ 09:00');
  assert.equal(shareWhen(NaN, ny, 'US'), '');
  assert.equal(shareInviteText({ name: 'Jazz', when: '', url: 'https://x' }), 'Jazz\nhttps://x');
  assert.deepEqual(ZALO_COPIED, { vi: 'Đã chép. Dán vào Zalo nhé.', en: 'Copied. Paste it in Zalo.' });
});

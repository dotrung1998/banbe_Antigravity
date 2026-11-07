// Map E+ (note 79): the day + hour window. Shared fixture with iOS MapTimeWindowTests.swift.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  eventSlot, dayOptions, defaultWindow, moveKnob, inWindow, windowFromHomeDate, windowSummary, hourLabel,
  RANGE_MIN, RANGE_MAX, RANGE_STEP,
} from '../../src/lib/mapTimeWindow.js';

const fx = JSON.parse(readFileSync(new URL('../fixtures/map-time-window.json', import.meta.url), 'utf8'));
const ms = (iso) => Date.parse(iso);

test('the slider runs 10:00 to 02:00 in one-hour steps', () => {
  assert.deepEqual([RANGE_MIN, RANGE_MAX, RANGE_STEP], [10, 26, 1]);
});

test('eventSlot: the venue zone decides, and 00:00 to 03:59 belongs to the night before', () => {
  for (const c of fx.eventSlot) {
    const s = eventSlot(ms(c.startsAt), c.tz);
    assert.deepEqual({ dayKey: s.dayKey, min: s.min }, c.expect, c.name);
    assert.equal(s.ms, ms(c.startsAt), c.name);
  }
});

test('dayOptions: today, tomorrow, the next weekend day, next week, all days, in both languages', () => {
  for (const c of fx.dayOptions) {
    for (const en of [false, true]) {
      const got = dayOptions(ms(c.now), c.tz, en).map((o) => ({ key: o.key, days: o.days, [en ? 'en' : 'vi']: [o.label, o.sub] }));
      const want = c.expect.map((o) => ({ key: o.key, days: o.days, [en ? 'en' : 'vi']: en ? o.en : o.vi }));
      assert.deepEqual(got, want, `${c.name} (${en ? 'en' : 'vi'})`);
    }
  }
});

test('defaultWindow: today from the next full hour, other days from 17:00, all days off', () => {
  for (const c of fx.defaultWindow) assert.deepEqual(defaultWindow(c.key, ms(c.now), c.tz), c.expect, c.name);
});

test('moveKnob keeps the range one step wide and inside the slider', () => {
  for (const c of fx.moveKnob) assert.deepEqual(moveKnob(c.win, c.which, c.hour), c.expect, c.name);
});

test('inWindow: from inclusive, to exclusive, today grace, other days, off', () => {
  const now = ms(fx.inWindow.now);
  for (const c of fx.inWindow.cases) assert.equal(inWindow(eventSlot(ms(c.startsAt), c.tz), c.win, now), c.expect, c.name);
});

test('windowFromHomeDate maps Home’s date filter onto the Map’s day', () => {
  for (const c of fx.windowFromHomeDate) assert.deepEqual(windowFromHomeDate(c.date, ms(c.now), c.tz), c.expect, c.name);
});

test('windowSummary and hourLabel', () => {
  for (const c of fx.windowSummary) assert.equal(windowSummary(c.win, c.label, c.en), c.expect, c.name);
  for (const c of fx.hourLabel) assert.equal(hourLabel(c.hour), c.expect);
});

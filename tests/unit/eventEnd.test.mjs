import test from 'node:test';
import assert from 'node:assert/strict';
import { endMode, endsNextDay, defaultEndTime, endError, timeRange, durationMinutes } from '../../src/lib/eventEnd.js';

test('mode from the row, open-ended wins, nothing = not stated', () => {
  assert.equal(endMode('22:00:00', false), 'time');
  assert.equal(endMode(null, true), 'open');
  assert.equal(endMode(null, false), null);
  assert.equal(endMode('', undefined), null);
});

test('time line: range, next day, open-ended, start only', () => {
  assert.deepEqual(timeRange('16:00:00', '22:00:00', false), { vi: '16:00 – 22:00', en: '16:00 – 22:00' });
  assert.equal(timeRange('22:00', '02:00', false).en, '22:00 – 02:00 (next day)');
  assert.equal(timeRange('22:00', '02:00', false).vi, '22:00 – 02:00 (hôm sau)');
  assert.equal(timeRange('16:00', null, true).en, '16:00 · open-ended');
  assert.equal(timeRange('16:00', null, true).vi, '16:00 · không giờ kết thúc');
  assert.equal(timeRange('16:00', null, false).en, '16:00');
  assert.equal(timeRange('', '22:00', false), null);
});

test('create form: default +3h (wraps), errors, next day, duration', () => {
  assert.equal(defaultEndTime('19:00'), '22:00');
  assert.equal(defaultEndTime('22:30'), '01:30');
  assert.equal(defaultEndTime(''), '');
  assert.equal(endError('open', '19:00', ''), null);
  assert.equal(endError('time', '19:00', ''), 'missing');
  assert.equal(endError(null, '19:00', '22:00'), 'missing');
  assert.equal(endError('time', '19:00', '19:00'), 'same');
  assert.equal(endError('time', '19:00', '23:00'), null);
  assert.equal(endsNextDay('19:00', '19:00'), true);
  assert.equal(durationMinutes('22:00', '02:00'), 240);
  assert.equal(durationMinutes('16:00', '22:00'), 360);
});

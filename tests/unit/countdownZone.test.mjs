import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { daysUntilInZone, countdownChipText } from '../../src/lib/countdown.js';

// Mirrored by apps/ios/BanbeAppTests/CountdownZoneTests.swift through tests/fixtures/countdown-zone.json (note 75).
const F = JSON.parse(readFileSync(new URL('../fixtures/countdown-zone.json', import.meta.url), 'utf8'));

test('days until the event, counted in the venue zone', () => {
  for (const c of F.daysUntil) assert.equal(daysUntilInZone(c.raw, c.startMs ?? NaN, c.tz, c.nowMs), c.out, c.name);
});

test('countdown chip text', () => {
  for (const c of F.chipText) assert.equal(countdownChipText(c.days, c.en), c.out);
});

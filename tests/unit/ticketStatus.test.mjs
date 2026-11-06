import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { ticketCase, ticketQrShowsToken, formatEntryCode, showDistance, doorWatchOpen, inDoorWindow } from '../../src/lib/ticketStatus.js';

// Note 78. Every vector in tests/fixtures/ticket-status.json is shared with
// apps/ios/BanbeAppTests/TicketStatusTests.swift — change both together.
const V = JSON.parse(readFileSync(new URL('../fixtures/ticket-status.json', import.meta.url), 'utf8'));

test('ticket case precedence (shared vectors)', () => {
  for (const v of V.cases) assert.deepEqual(ticketCase(v.in), v.expect, v.case);
});

test('only ok/in may draw the real admission token', () => {
  for (const [qr, want] of Object.entries(V.qrShowsToken)) assert.equal(ticketQrShowsToken(qr), want, qr || '(empty)');
});

test('entry code groups 3-3 and leaves other lengths alone', () => {
  for (const v of V.entryCode) assert.equal(formatEntryCode(v.in), v.out, JSON.stringify(v.in));
});

test('distance shows only when located and within 50 km', () => {
  for (const v of V.distance) assert.equal(showDistance(v.km, v.located, v.en), v.out, JSON.stringify(v));
});

test('door watch: window edges, single tickets unchanged, named tickets done only when all are scanned', () => {
  for (const v of V.doorWatch) assert.equal(doorWatchOpen(v.in), v.expect, v.case);
  assert.equal(inDoorWindow(0, 2 * 3600000), true);
  assert.equal(inDoorWindow(NaN, 0), false);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { ticketCopy } from '../../src/lib/ticketCopy.js';
import { TICKET_CASES } from '../../src/lib/ticketStatus.js';

// Note 78: the approved strip copy. Every case has both languages, no empty heading, and only invents nothing the data lacks.
const FULL = { eventCancelled: true, dateText: 'Sat 28 Oct', timeText: '20:00', areaText: 'Quận 1', daysUntil: 3,
  typicalWait: { vi: 'Host này thường xác nhận trong khoảng 1 giờ.', en: 'This host usually confirms within about 1 hour.' },
  hasReceipt: true, hasRefund: true, hasDirections: true };

test('every ticket case has copy in both languages', () => {
  for (const key of Object.keys(TICKET_CASES)) {
    for (const en of [false, true]) {
      const c = ticketCopy(key, { ...FULL, en });
      assert.ok(c, `${key} ${en}`);
      assert.ok(c.label && c.heading, `${key} ${en} label/heading`);
    }
    assert.notEqual(ticketCopy(key, { ...FULL, en: false }).heading, ticketCopy(key, { ...FULL, en: true }).heading, `${key} vi != en`);
  }
  assert.equal(ticketCopy('nope'), null);
});

test('links exist only when their data does', () => {
  const none = { hasReceipt: false, hasRefund: false, hasDirections: false };
  assert.equal(ticketCopy('cancelled', none).link, null);
  assert.equal(ticketCopy('ended', none).link, null);
  assert.equal(ticketCopy('checkedIn', none).link, null);
  assert.equal(ticketCopy('today', none).link, null);
  assert.equal(ticketCopy('cancelled', { hasRefund: true }).link.kind, 'refunds');
  assert.equal(ticketCopy('today', { hasDirections: true }).link.kind, 'directions');
  assert.equal(ticketCopy('expired').link.kind, 'reserve');
  assert.equal(ticketCopy('holding').link.kind, 'pay');
  assert.equal(ticketCopy('awaiting').link.kind, 'chat');
  assert.equal(ticketCopy('upcoming').link.kind, 'calendar');
});

test('refund responsibility is said only when the host cancelled the event', () => {
  assert.match(ticketCopy('cancelled', { eventCancelled: true, en: true }).detail, /organizer is responsible for your refund/);
  assert.equal(ticketCopy('cancelled', { eventCancelled: false, en: true }).detail, null);
  assert.equal(ticketCopy('cancelled', { eventCancelled: false, en: true }).heading, 'This booking was cancelled');
});

test('no time, door or reply-speed claims beyond the data', () => {
  assert.equal(ticketCopy('today', { timeText: '', en: true }).heading, 'Today');
  assert.equal(ticketCopy('today', { timeText: '19:00', en: false }).heading, 'Hôm nay lúc 19:00');
  assert.equal(ticketCopy('awaiting', { typicalWait: null }).detail, null);
  assert.equal(ticketCopy('upcoming', { daysUntil: 1, en: true }).heading, '1 day to go');
  assert.equal(ticketCopy('upcoming', { daysUntil: null, en: true }).heading, 'Upcoming');
  assert.equal(ticketCopy('upcoming', { dateText: 'Sat 28 Oct', timeText: '20:00' }).sub, 'Sat 28 Oct ▪︎ 20:00');
  for (const key of Object.keys(TICKET_CASES)) {
    const c = ticketCopy(key, { ...FULL, en: true });
    assert.doesNotMatch(`${c.heading} ${c.sub} ${c.detail}`, /doors? (are |is )?open|arrive by|within an hour|valid until/i, key);
  }
});

// Every approved string, per case, language and data availability. Shared with the iOS port
// (apps/ios/BanbeAppTests/TicketCopyTests.swift), so a copy change is made in both or neither.
const FIXTURE = JSON.parse(readFileSync(new URL('../fixtures/ticket-copy.json', import.meta.url), 'utf8'));
test('strip copy matches the shared fixture (the iOS twin reads the same file)', () => {
  assert.ok(FIXTURE.cases.length > 40);
  for (const c of FIXTURE.cases) assert.deepEqual(ticketCopy(c.key, c.ctx), c.expect, c.name);
});

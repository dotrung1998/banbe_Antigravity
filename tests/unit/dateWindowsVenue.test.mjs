// Venue-time date windows (Map redesign phase 3). Shared fixture with iOS DateWindowsVenueTests.swift.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dateWindowInZone, applyDiscoveryFilters } from '../../src/lib/homeDiscovery.js';

const fx = JSON.parse(readFileSync(new URL('../fixtures/date-windows-venue.json', import.meta.url), 'utf8'));
const ms = (iso) => Date.parse(iso);

test('windows are computed in the venue zone, DST included', () => {
  for (const c of fx.windows) {
    const w = dateWindowInZone(c.option, ms(c.now), c.tz);
    assert.deepEqual(w.map(x => new Date(x).toISOString().replace('.000', '')), c.expect, c.name);
  }
});

test('each event is judged in its own venue zone, never the viewer’s; started events are not offered', () => {
  const p = fx.perVenue;
  const items = p.items.map(i => ({ ...i, startsAt: ms(i.startsAt), catKeys: [] }));
  const got = applyDiscoveryFilters(items, { date: 'tonight' }, ms(p.now)).map(i => i.key);
  assert.deepEqual(got, p.tonight, p.name);
});

test('items without a zone keep the fixed Vietnam offset (Home unchanged for VN)', () => {
  const now = ms('2026-11-04T13:00:00Z');
  const items = [{ key: 'a', startsAt: ms('2026-11-04T15:00:00Z'), catKeys: [] }, { key: 'b', startsAt: ms('2026-11-04T18:00:00Z'), catKeys: [] }];
  assert.deepEqual(applyDiscoveryFilters(items, { date: 'today' }, now).map(i => i.key), ['a']);
});

// Unit-level coverage for the map cover-photo fallback fix (2026-10-19).
//
// Root cause recap: `findEvent(key)` (src/data/events.js) ALWAYS returns
// something — it falls back to `EVENTS[0]` for any key that isn't a real
// static demo-catalogue entry. `MapExplore.jsx`'s `fetchLiveEvents()` used
// to call `findEvent(row.id)` unconditionally for every REAL (organizer-
// created) event too, silently painting `EVENTS[0]`'s own cover photo onto
// every one of them. The fix (both platforms) is to only ever treat
// `findEvent`'s result as real cosmetic data when `isCosmeticCatalogMatch`
// is true, never as a wildcard fallback for a real event's own fields.
//
// This is pure, dependency-free logic (`src/data/events.js` has no
// Supabase/DOM import), so it can run under Node's own built-in test
// runner with no live database, no browser, and no new dependency added to
// this repo — `node --test tests/unit/`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EVENTS, findEvent, isCosmeticCatalogMatch } from '../../src/data/events.js';

test('isCosmeticCatalogMatch is true for every real static demo-catalogue key', () => {
  assert.ok(EVENTS.length > 0, 'sanity check: the static catalogue is non-empty');
  for (const e of EVENTS) {
    assert.equal(isCosmeticCatalogMatch(e.key), true, `expected ${e.key} to be a genuine catalogue match`);
  }
});

test('isCosmeticCatalogMatch is false for a real organizer-created event id', () => {
  // Shaped exactly like create_event_draft's own generated id
  // (migration 085): `lower(regexp_replace(trim(name), ...)) || '-' ||
  // substr(md5(gen_random_uuid()::text), 1, 6)` — structurally can never
  // collide with a hand-authored catalogue key.
  const realEventId = 'event-new-a1b2c3';
  assert.equal(isCosmeticCatalogMatch(realEventId), false);
});

test('isCosmeticCatalogMatch is false for an unrelated/garbage id', () => {
  assert.equal(isCosmeticCatalogMatch(''), false);
  assert.equal(isCosmeticCatalogMatch('does-not-exist-at-all'), false);
});

test('findEvent still falls back to EVENTS[0] for a non-catalogue key (documents the exact behavior isCosmeticCatalogMatch exists to guard against)', () => {
  const realEventId = 'event-new-a1b2c3';
  const fallback = findEvent(realEventId);
  assert.equal(fallback, EVENTS[0], 'findEvent must fall back to the first catalogue event for an unmatched key');
  // The actual regression this whole fix pass addresses: naively using
  // `findEvent(row.id)`'s result for a REAL event's own cover photo would
  // silently render EVENTS[0]'s photo — confirmed here so a future change
  // to findEvent's fallback behavior doesn't silently un-fix this without
  // a test noticing.
  assert.notEqual(fallback.key, realEventId);
});

test('a genuine catalogue key resolves to its OWN entry, not the fallback', () => {
  const first = EVENTS[0];
  // Pick a key that is NOT EVENTS[0] itself, so a false "pass" via the
  // fallback path would be caught.
  const other = EVENTS.find(e => e.key !== first.key);
  assert.ok(other, 'the catalogue needs at least two distinct events for this assertion to be meaningful');
  assert.equal(findEvent(other.key), other);
  assert.equal(isCosmeticCatalogMatch(other.key), true);
});

// Unit-level coverage for the keyword-search fix (migration 108).
//
// Root cause recap: Map's own search box (MapExplore.jsx) only ever
// matched an event's literal name/district. This adds a `keywords` field
// (real events via a new migration/RPC, the static demo catalogue via a
// pure, dependency-free derivation) so a search term can also match on
// category, host, and "Bao gồm" item words. This test only covers the
// demo-catalogue side — the real-event backfill/RPC needs a live database
// this environment doesn't have (see migration 108's own doc comment).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EVENTS } from '../../src/data/events.js';

test('every demo catalogue event has at least one derived keyword', () => {
  for (const e of EVENTS) {
    assert.ok(Array.isArray(e.keywords), `${e.key} has no keywords array`);
    assert.ok(e.keywords.length > 0, `${e.key} has zero keywords`);
  }
});

test('a demo event\'s keywords include its own category and district', () => {
  const e = EVENTS[0];
  assert.ok(e.keywords.includes(e.cat), `expected category "${e.cat}" among keywords`);
  const district = e.meta.split(' ▪︎ ')[0];
  assert.ok(e.keywords.includes(district), `expected district "${district}" among keywords`);
});

test('a demo event\'s keywords are deduplicated', () => {
  for (const e of EVENTS) {
    assert.equal(new Set(e.keywords).size, e.keywords.length, `${e.key} has duplicate keywords`);
  }
});

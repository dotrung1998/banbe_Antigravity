// Map v6 (note 74): recent Map searches (src/lib/mapRecentSearches.js).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addRecentSearch, loadRecentSearches, MAP_RECENT_MAX } from '../../src/lib/mapRecentSearches.js';

test('newest first, trimmed, case-insensitive duplicates dropped, capped at five', () => {
  assert.deepEqual(addRecentSearch(['Supper club', 'da lat'], '  supper   CLUB '), ['supper CLUB', 'da lat']);
  assert.deepEqual(addRecentSearch(['a'], '   '), ['a']);
  assert.deepEqual(addRecentSearch(null, 'x'), ['x']);
  let l = [];
  for (const q of ['1', '2', '3', '4', '5', '6']) l = addRecentSearch(l, q);
  assert.equal(l.length, MAP_RECENT_MAX);
  assert.equal(l[0], '6');
});

test('no storage (node, private window) gives an empty list, never a throw', () => {
  assert.deepEqual(loadRecentSearches(), []);
});

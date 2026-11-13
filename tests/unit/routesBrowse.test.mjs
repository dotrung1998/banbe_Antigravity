import test from 'node:test';
import assert from 'node:assert/strict';
import { screenToPath, pathToRoute } from '../../src/lib/routes.js';

// Note 81: Browse by type (/browse[/<type>]) and See all (/see-all/<tab>[/<type>]) round-trip through the URL.
test('Browse paths', () => {
  assert.equal(screenToPath({ screen: 'browse', browseType: 'all', browseScope: 'all' }), '/browse');
  assert.equal(screenToPath({ screen: 'browse', browseType: 'supper', browseScope: 'all' }), '/browse/supper');
  assert.equal(screenToPath({ screen: 'browse', browseType: 'all', browseScope: 'weekend' }), '/see-all/weekend');
  assert.equal(screenToPath({ screen: 'browse', browseType: 'music', browseScope: 'foryou' }), '/see-all/foryou/music');
});

test('Browse routes open the list and keep its search on back/forward', () => {
  assert.deepEqual(pathToRoute('/browse'), { screen: 'browse', params: {}, open: 'openBrowse', openArgs: [{ type: 'all', scope: 'all', keep: true }] });
  assert.deepEqual(pathToRoute('/browse/gallery/').openArgs, [{ type: 'gallery', scope: 'all', keep: true }]);
  assert.deepEqual(pathToRoute('/see-all/tonight').openArgs, [{ type: 'all', scope: 'tonight', keep: true }]);
  assert.deepEqual(pathToRoute('/see-all/foryou/music').openArgs, [{ type: 'music', scope: 'foryou', keep: true }]);
  assert.equal(pathToRoute('/see-all/someday'), null);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  combinedProfile, profileFor, requiredFields, detailOwner, mergedDraft, publishDetails, secondCategory, eventProfile, introStyle,
} from '../../src/lib/eventTypes.js';

// Note 69 (migration 207). Same cases as apps/ios/BanbeAppTests/EventTypesCombinedTests.swift.
test('one key is that type unchanged', () => {
  assert.deepEqual(combinedProfile(['supper']).wizard.details, profileFor('supper').wizard.details);
});
test('two keys merge fields, shared ones once at the end', () => {
  const p = combinedProfile(['supper', 'music']);
  assert.equal(p.key, 'supper');
  assert.deepEqual(p.wizard.details, ['dietary', 'dress_code', 'lineup', 'genre', 'format', 'alcohol', 'min_age']);
  const req = requiredFields(p);
  assert.ok(req.includes('included') && req.includes('lineup'));
  assert.equal(req.filter(f => f === 'alcohol').length, 1);
  assert.equal(p.detail.facts.filter(f => f === 'min_age').length, 1);
});
test('a shared type field belongs to the first type that has it', () => {
  assert.equal(detailOwner('brands', ['fashion', 'popup']), 'fashion');
  assert.equal(detailOwner('entry_mode', ['fashion', 'popup']), 'popup');
  assert.equal(detailOwner('alcohol', ['music', 'supper']), 'music');
  assert.equal(detailOwner('dietary', ['music', 'supper']), 'supper');
});
test('merged draft reads each field from its owner', () => {
  const draft = { supper: { dietary: ['vegan'], alcohol: 'byo', lineup: ['stale'] }, music: { lineup: ['Trio Hà'], alcohol: 'paid' }, _style: { intro_font: 'serif' } };
  const m = mergedDraft(['supper', 'music'], draft);
  assert.deepEqual(m.dietary, ['vegan']);
  assert.deepEqual(m.lineup, ['Trio Hà']);
  assert.equal(m.alcohol, 'byo');
  assert.equal(m.intro_font, undefined);
});
test('publish adds the second category and a non-default style only', () => {
  const out = publishDetails({ keys: ['supper', 'music'], draft: { supper: { dietary: ['vegan'] }, music: { lineup: ['A'] } }, introFont: 'serif', introColor: 'ink' });
  assert.equal(out.v, 1);
  assert.equal(out.cat2, 'music');
  assert.equal(out.intro_font, 'serif');
  assert.equal(out.intro_color, undefined);
  assert.deepEqual(publishDetails({ keys: ['supper'], draft: {}, introFont: 'sans', introColor: 'ink' }), {});
  assert.deepEqual(publishDetails({ keys: ['supper'], draft: {}, introFont: 'comic', introColor: '#ff0000' }), {});
});
test('a published event reads back its second category', () => {
  const d = { cat2: 'music', lineup: ['A'], intro_color: 'clay' };
  assert.equal(secondCategory(d, 'supper'), 'music');
  assert.equal(secondCategory(d, 'music'), null);
  assert.equal(secondCategory({ cat2: 'karaoke' }, 'supper'), null);
  assert.ok(eventProfile('supper', d).wizard.details.includes('lineup'));
  assert.deepEqual(introStyle(d), { font: null, color: 'clay' });
});

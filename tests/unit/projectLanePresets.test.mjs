import test from 'node:test';
import assert from 'node:assert/strict';
import { PRESETS, CUSTOM_ICON, key, presetNamed, iconFor, search } from '../../src/lib/projectLanePresets.js';
import { currentLane } from '../../src/lib/projectPresentation.js';

test('36 presets, same order as iOS', () => {
  assert.equal(PRESETS.length, 36);
  assert.equal(PRESETS[0].en, 'Venue');
  assert.equal(PRESETS[35].en, 'Clean-up');
});

test('key folds case, accents and đ', () => {
  assert.equal(key('  Truyền Thông '), 'truyen thong');
  assert.equal(key('ĐỊA ĐIỂM'), 'dia diem');
  assert.equal(key('Đối tác'), key('doi tac'));
});

test('iconFor: Vietnamese or English, any case; custom gets the grid glyph', () => {
  assert.equal(iconFor('truyen thong'), iconFor('Marketing'));
  assert.equal(iconFor('MARKETING'), '📣');
  assert.equal(presetNamed('địa điểm').en, 'Venue');
  assert.equal(iconFor('Our own lane'), CUSTOM_ICON);
  assert.equal(presetNamed(''), null);
});

test('search matches either language without accents; empty = all', () => {
  assert.equal(search('').length, 36);
  assert.deepEqual(search('am thanh').map(p => p.en), ['Sound & light']);
  assert.ok(search('cafe').length === 0);
  assert.ok(search('coffee').some(p => p.vi === 'Cà phê & trà'));
  assert.ok(search('nhac').some(p => p.en === 'DJ & music'));
});

test('currentLane: last heading above the reading line', () => {
  assert.equal(currentLane({ a: -300, b: -20, c: 400 }, { viewport: 700, remaining: 2000 }), 'b');
});

test('currentLane: a list that fits on screen keeps its first lane', () => {
  assert.equal(currentLane({ a: 80, b: 300, c: 500 }, { viewport: 700, remaining: 0 }), 'a');
});

test('currentLane: near the end the line slides down so short last lanes become current', () => {
  const tops = { a: -600, b: 40, c: 260, d: 420 };
  assert.equal(currentLane(tops, { viewport: 700, remaining: 1000 }), 'b');
  assert.equal(currentLane(tops, { viewport: 700, remaining: 200 }), 'c');
  assert.equal(currentLane(tops, { viewport: 700, remaining: 0 }), 'd');
});

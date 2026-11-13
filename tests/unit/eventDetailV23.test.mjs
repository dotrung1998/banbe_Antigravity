import test from 'node:test';
import assert from 'node:assert/strict';
import { knowRows, listNo, heroMotion, navOn, NAV_AT, readProgress } from '../../src/lib/eventDetailV23.js';
import { needToKnowRows } from '../../src/lib/eventDetailPresentation.js';

test('Good to know: alcohol, every dietary choice in one row, age, facts, refund last', () => {
  const rows = needToKnowRows([
    { id: 'alcohol', value: 'Included' },
    { id: 'dietary', values: ['Vegetarian', 'No pork'] },
    { id: 'min_age', value: '18+' },
    { id: 'dress', label: 'Dress code', value: 'Smart casual' },
    { id: 'empty', label: 'Nothing', value: '' },
  ], { alcohol: 'Rice wine all night', dietary: 'Tell us 24 h ahead' }, true);
  const out = knowRows(rows, { refund: 'Automatic full refund if the event is cancelled' });
  assert.deepEqual(out.map(r => r.key), ['alcohol', 'dietary', 'min_age-row', 'dress', 'refund']);
  assert.equal(out[0].text, 'Included · Rice wine all night');
  assert.equal(out[1].text, 'Vegetarian, No pork · Tell us 24 h ahead');
  assert.equal(out[1].label.en, 'Dietary');
  assert.equal(out[2].text, 'Ages 18 and up');
  assert.equal(out[3].label, 'Dress code');
  for (const r of out) assert.doesNotMatch(`${r.text}`, /—|;/);
});

test('no refund row for free or closed events, nothing invented', () => {
  assert.deepEqual(knowRows([], {}), []);
  assert.deepEqual(knowRows([{ id: 'x', key: 'x', icon: 'fact', title: 'Label', sub: null }]), []);
});

test('editorial numbers, hero parallax, nav hand-off, reading progress', () => {
  assert.deepEqual([0, 1, 9].map(listNo), ['01', '02', '10']);
  assert.equal(heroMotion(0).dp, 0);
  assert.equal(heroMotion(600).dp, 1);
  assert.equal(heroMotion(100).art, 'translate3d(0, 20px, 0) scale(1.025)');
  assert.equal(navOn(NAV_AT), false);
  assert.equal(navOn(NAV_AT + 1), true);
  assert.equal(readProgress(50, 1100, 1000), 0.5);
  assert.equal(readProgress(10, 500, 600), 0);
});

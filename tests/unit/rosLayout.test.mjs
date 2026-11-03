import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { rosLayout } from '../../src/lib/rosLayout.js';

// Mirrored by apps/ios/BanbeAppTests/RosLayoutTests.swift through the same fixture.
const fx = JSON.parse(readFileSync(new URL('../fixtures/ros-layout.json', import.meta.url), 'utf8'));
const ms = iso => Date.parse(iso);

function inputOf(c) {
  let rows = c.items ?? fx.base;
  if (c.shuffle) rows = c.shuffle.map(id => rows.find(r => r.id === id));
  return rows.map(r => ({
    id: r.id,
    startsAt: ms(r.startsAt),
    endsAt: ms(r.endsAt),
    doneAt: (c.done?.[r.id] ?? r.doneAt) ? ms(c.done?.[r.id] ?? r.doneAt) : null,
  }));
}

for (const c of fx.cases) {
  test(`ros layout: ${c.case}`, () => {
    const r = rosLayout(inputOf(c), ms(c.now));
    assert.deepEqual(
      r.items.map(l => ({ id: l.id, start: l.start, end: l.end, overrunMin: l.overrunMin, squeezedMin: l.squeezedMin, overlap: l.overlap, active: l.active })),
      c.expect.items.map(e => ({ ...e, start: ms(e.start), end: ms(e.end) })),
    );
    assert.deepEqual(r.chips, c.expect.chips);
    assert.deepEqual(r.axis, c.expect.axis && { start: ms(c.expect.axis.start), end: ms(c.expect.axis.end) });
  });
}

test('derived flags follow the prototype: overrun only while unticked, squeeze hidden when overlapped', () => {
  for (const c of fx.cases) {
    for (const l of rosLayout(inputOf(c), ms(c.now)).items) {
      assert.equal(l.overrun, !l.done && l.overrunMin > 0, c.case);
      assert.equal(l.squeezed, l.squeezedMin > 0 && !l.overlap, c.case);
      assert.ok(l.end - l.start >= 10 * 60_000, `${c.case}: ${l.id} keeps the 10-minute minimum`);
      assert.ok(l.squeezedMin >= 0, `${c.case}: a squeeze never moves an item earlier`);
    }
  }
});

test('the input array is not mutated', () => {
  const input = inputOf(fx.cases[1]);
  const copy = structuredClone(input);
  rosLayout(input, ms(fx.cases[1].now));
  assert.deepEqual(input, copy);
});

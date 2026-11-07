import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dockCollapseStep, DOCK_COLLAPSE_THRESHOLD } from '../../src/lib/dockLayout.js';

const fx = JSON.parse(readFileSync(new URL('../fixtures/dock-collapse.json', import.meta.url)));

test('threshold matches the shared fixture', () => assert.equal(DOCK_COLLAPSE_THRESHOLD, fx.threshold));

for (const c of fx.cases) {
  test(c.name, () => {
    let s = { collapsed: false, travel: 0 };
    for (const [offsetY, delta, expected] of c.steps) {
      s = dockCollapseStep(s, offsetY, delta);
      assert.equal(s.collapsed, expected, `at offset ${offsetY}`);
    }
  });
}

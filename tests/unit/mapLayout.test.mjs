import test from 'node:test';
import assert from 'node:assert/strict';
import { computeMapLayout, bottomStackFraction, ATTRIB_RESERVE, CARD_GAP } from '../../src/lib/mapLayout.js';

// topControlsBottom ~ safe-area + the shared controls (search row + chips); stackPx ~ the dock + the buttons above it.
const VIEWPORTS = {
  'iPhone SE (375x667 Safari)': { containerH: 667, topControlsBottom: 110, stackPx: 170 },
  'iPhone 15 (390x844 Safari)': { containerH: 844, topControlsBottom: 150, stackPx: 180 },
  'iPhone landscape (844x390)': { containerH: 390, topControlsBottom: 100, stackPx: 120 },
  'desktop phone frame (390x760)': { containerH: 760, topControlsBottom: 160, stackPx: 180 },
};

for (const [name, v] of Object.entries(VIEWPORTS)) {
  test(`${name}: camera padding keeps a pin between the controls and the bottom stack`, () => {
    const l = computeMapLayout({ containerH: v.containerH, topControlsBottom: v.topControlsBottom, stripFraction: bottomStackFraction(v.containerH, v.stackPx) });
    assert.ok(Math.abs(l.sheetTopPx - (v.containerH - v.stackPx)) < 1 || l.sheetTopPx >= v.containerH * 0.5, 'the stack top follows the stack height');
    assert.equal(l.visibleBottom, l.sheetTopPx - ATTRIB_RESERVE, 'attribution strip stays free');
    assert.ok(l.cameraPadding.top >= v.topControlsBottom + CARD_GAP - 0.5, 'clears the controls');
    assert.ok(l.cameraPadding.top + l.cameraPadding.bottom <= v.containerH - 90 + 0.5, 'padding leaves map room');
  });
}

test('camera padding never exceeds the container', () => {
  const l = computeMapLayout({ containerH: 300, topControlsBottom: 110, stripFraction: bottomStackFraction(300, 250) });
  assert.ok(l.cameraPadding.top + l.cameraPadding.bottom <= 300);
});

test('bottomStackFraction: the stack top as a fraction, bounded, and safe with no height yet', () => {
  assert.equal(bottomStackFraction(800, 200), 0.75);
  assert.equal(bottomStackFraction(800, 10), 0.98);   // never past the bottom edge
  assert.equal(bottomStackFraction(800, 700), 0.5);   // never swallows the map
  assert.equal(bottomStackFraction(0, 200), 0.8);
});

// ---- Map E+ (note 79): dimming, the list pull, the dock -------------------------------------------------------------
import { readFileSync } from 'node:fs';
import { MAP_DIM, LIST_PULL, pullOutcome, veilOpacity, dockVisible } from '../../src/lib/mapLayout.js';
const eplus = JSON.parse(readFileSync(new URL('../fixtures/map-discovery.json', import.meta.url), 'utf8'));

test('E+: dim values are the shared ones', () => assert.deepEqual(MAP_DIM, eplus.dim));
test('E+: a long or fast pull closes the list, a short one springs back', () => {
  assert.deepEqual(LIST_PULL, { closePx: 110, flickPxPerMs: 0.6, flickMinPx: 50, veilPx: 130, slopPx: 6 });
  for (const c of eplus.pullOutcome) assert.equal(pullOutcome(c.dy, c.velocity), c.expect, `${c.dy}px @ ${c.velocity}`);
});
test('E+: the veil fades with the pull', () => {
  for (const c of eplus.veilOpacity) assert.ok(Math.abs(veilOpacity(c.dy) - c.expect) < 1e-9, `${c.dy}px`);
});
test('E+: the dock hides only while the area panel is open', () => {
  for (const c of eplus.dockVisible) assert.equal(dockVisible(c.panelOpen), c.expect);
});

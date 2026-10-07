import test from 'node:test';
import assert from 'node:assert/strict';
import { computeMapLayout, snapFits, snapForSelection, SHEET_SNAPS, ATTRIB_RESERVE, CARD_GAP } from '../../src/lib/mapLayout.js';

// topControlsBottom ~ safe-area + controls row; card ~150px tall.
const VIEWPORTS = {
  'iPhone SE (375x667 Safari)': { containerH: 667, topControlsBottom: 56 },
  'iPhone 15 (390x844 Safari)': { containerH: 844, topControlsBottom: 96 },
  'iPhone landscape (844x390)': { containerH: 390, topControlsBottom: 56 },
  'desktop phone frame (390x760)': { containerH: 760, topControlsBottom: 106 },
};

for (const [name, v] of Object.entries(VIEWPORTS)) {
  test(`${name}: card never overlaps controls or sheet; attribution strip stays free`, () => {
    for (const snap of Object.keys(SHEET_SNAPS)) {
      const l = computeMapLayout({ ...v, cardHeight: 150, stripFraction: SHEET_SNAPS[snap] });
      if (!l.cardFits) continue; // hidden instead of overlapping
      const cardTop = v.containerH - l.cardBottomPx - 150;
      const cardBottom = v.containerH - l.cardBottomPx;
      assert.ok(cardTop >= v.topControlsBottom + CARD_GAP - 0.5, `${snap}: card top clears controls`);
      assert.ok(cardBottom <= l.sheetTopPx - ATTRIB_RESERVE + 0.5, `${snap}: card clears sheet + attribution`);
      assert.ok(l.cameraPadding.top + l.cameraPadding.bottom <= v.containerH - 90 + 0.5, `${snap}: padding leaves map room`);
    }
  });

  test(`${name}: selection always lands on a snap with room, or peek`, () => {
    const dims = { ...v, cardHeight: 150 };
    for (const start of Object.keys(SHEET_SNAPS)) {
      const snap = snapForSelection(start, dims);
      assert.ok(snap === 'peek' || snapFits(snap, dims));
      // never moves UP the sheet order
      assert.ok(['tall', 'mid', 'peek'].indexOf(snap) >= ['tall', 'mid', 'peek'].indexOf(start));
    }
  });
}

test('tall viewport keeps the user-chosen snap when it fits; short viewport steps down', () => {
  assert.equal(snapForSelection('mid', { containerH: 844, topControlsBottom: 96, cardHeight: 150 }), 'mid');
  assert.equal(snapForSelection('tall', { containerH: 844, topControlsBottom: 96, cardHeight: 150 }), 'mid');
  assert.equal(snapForSelection('mid', { containerH: 390, topControlsBottom: 56, cardHeight: 150 }), 'peek');
});

test('card hides (not overlaps) when the sheet is dragged too high', () => {
  const l = computeMapLayout({ containerH: 667, topControlsBottom: 56, cardHeight: 150, stripFraction: 0.2 });
  assert.equal(l.cardFits, false);
});

test('camera padding never exceeds the container', () => {
  const l = computeMapLayout({ containerH: 300, topControlsBottom: 56, cardHeight: 150, stripFraction: 0.86 });
  assert.ok(l.cameraPadding.top + l.cameraPadding.bottom <= 300);
});

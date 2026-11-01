import test from 'node:test';
import assert from 'node:assert/strict';
import { computeMapLayout, snapAfterSelect, snapAfterUserPan, dockShown, SHEET_SNAPS, ATTRIB_RESERVE, CARD_GAP } from '../../src/lib/mapLayout.js';

// topControlsBottom ~ safe-area + controls row.
const VIEWPORTS = {
  'iPhone SE (375x667 Safari)': { containerH: 667, topControlsBottom: 56 },
  'iPhone 15 (390x844 Safari)': { containerH: 844, topControlsBottom: 96 },
  'iPhone landscape (844x390)': { containerH: 390, topControlsBottom: 56 },
  'desktop phone frame (390x760)': { containerH: 760, topControlsBottom: 106 },
};

for (const [name, v] of Object.entries(VIEWPORTS)) {
  test(`${name}: camera padding keeps a pin between the controls and the sheet`, () => {
    for (const snap of Object.keys(SHEET_SNAPS)) {
      const l = computeMapLayout({ ...v, stripFraction: SHEET_SNAPS[snap] });
      assert.equal(l.sheetTopPx, SHEET_SNAPS[snap] * v.containerH);
      assert.equal(l.visibleBottom, l.sheetTopPx - ATTRIB_RESERVE, `${snap}: attribution strip stays free`);
      assert.ok(l.cameraPadding.top >= v.topControlsBottom + CARD_GAP - 0.5, `${snap}: clears controls`);
      assert.ok(l.cameraPadding.top + l.cameraPadding.bottom <= v.containerH - 90 + 0.5, `${snap}: padding leaves map room`);
    }
  });
}

test('camera padding never exceeds the container', () => {
  const l = computeMapLayout({ containerH: 300, topControlsBottom: 56, stripFraction: 0.84 });
  assert.ok(l.cameraPadding.top + l.cameraPadding.bottom <= 300);
});

test('Map v5: selection goes to mid, a pan drops mid to peek, tall stays tall', () => {
  for (const s of ['tall', 'mid', 'peek']) assert.equal(snapAfterSelect(s), 'mid');
  assert.equal(snapAfterUserPan('mid'), 'peek');
  assert.equal(snapAfterUserPan('peek'), 'peek');
  assert.equal(snapAfterUserPan('tall'), 'tall');
});

test('Map v5: the dock shows only at tall', () => {
  assert.deepEqual(['tall', 'mid', 'peek'].map(dockShown), [true, false, false]);
});

// ---- Map v6 (note 74): full height and peek → full ----
import { snapAfterDrag, tallFraction, snapFractions } from '../../src/lib/mapLayout.js';

test('Map: full height covers the whole screen; mid covers about two thirds', () => {
  assert.equal(tallFraction(844, 96), 0);
  assert.equal(tallFraction(0, 96), SHEET_SNAPS.tall);
  assert.ok(Math.abs((1 - SHEET_SNAPS.mid) - 2 / 3) < 0.01);
  const f = snapFractions(844, 96);
  assert.ok(f.tall < f.mid && f.mid < f.peek);
  // The reference rect uses peek, which full height never changes.
  assert.equal(f.peek, SHEET_SNAPS.peek);
});

test('Map v6: from peek, an upward pull past 40 px or a flick goes straight to full', () => {
  const H = 844;
  const f = snapFractions(H, 96);
  assert.equal(snapAfterDrag('peek', -41, H, 0, f), 'tall');
  assert.equal(snapAfterDrag('peek', -20, H, -0.8, f), 'tall'); // short but fast
  assert.equal(snapAfterDrag('peek', -20, H, -0.2, f), 'peek'); // short and slow: stays
  assert.equal(snapAfterDrag('peek', 30, H, 0, f), 'peek'); // down from peek: nowhere lower
});

test('Map v6: from mid and tall the sheet lands on the nearest snap (unchanged)', () => {
  const H = 844;
  const f = snapFractions(H, 96);
  assert.equal(snapAfterDrag('mid', -20, H, 0, f), 'mid');
  assert.equal(snapAfterDrag('mid', -(f.mid - f.tall) * H + 10, H, 0, f), 'tall');
  assert.equal(snapAfterDrag('mid', (f.peek - f.mid) * H - 10, H, 0, f), 'peek');
  assert.equal(snapAfterDrag('tall', 30, H, 0, f), 'tall');
  assert.equal(snapAfterDrag('tall', (f.mid - f.tall) * H, H, 0, f), 'mid');
  assert.equal(snapAfterDrag('mid', -30, H, -2, f), 'mid'); // only peek treats a flick as "go to full"
  assert.equal(snapAfterDrag('mid', 0, H), 'mid'); // default fractions
});

test('Map v6: peek fits the two-row strip on a short screen and stays below mid', async () => {
  const { peekFraction, PEEK_MIN_PX } = await import('../../src/lib/mapLayout.js');
  assert.equal(peekFraction(844), SHEET_SNAPS.peek);
  assert.ok((1 - peekFraction(667)) * 667 >= PEEK_MIN_PX - 0.5);
  assert.ok(peekFraction(390) > SHEET_SNAPS.mid);
});

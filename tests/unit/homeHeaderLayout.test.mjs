import test from 'node:test';
import assert from 'node:assert/strict';
import { HEADER, estimateHeaderWidth, headerFits, buttonWidth, titleFits } from '../../src/lib/homeHeaderLayout.js';
import { compactCoins } from '../../src/lib/rewards.js';

const WIDTHS = [320, 360, 375, 390, 393, 402, 430, 440];

test('every control keeps a 44pt touch target', () => {
  assert.ok(HEADER.search >= HEADER.minTouch);
  for (const chars of [1, 2, 3, 5]) assert.ok(buttonWidth(chars) >= HEADER.minTouch);
});

test('the header fits on every iPhone width for realistic and worst-case numbers', () => {
  for (const w of WIDTHS) {
    for (const { streak, coins } of [{ streak: 0, coins: 0 }, { streak: 7, coins: 120 }, { streak: 365, coins: 9999 }, { streak: 999, coins: 12500 }, { streak: 12, coins: -40 }]) {
      const streakChars = String(streak).length, coinChars = compactCoins(coins).length;
      assert.ok(headerFits(w, { streakChars, coinChars }), `${w}px streak=${streak} coins=${coins} needs ${Math.round(estimateHeaderWidth({ streakChars, coinChars, showTitle: titleFits(w, { streakChars, coinChars }) }))}`);
    }
  }
});

test('the title is the first thing dropped, then nothing else: narrow phones keep every control', () => {
  assert.equal(titleFits(320, { streakChars: 1, coinChars: 3 }), false);
  assert.equal(titleFits(430, { streakChars: 2, coinChars: 3 }), true);
  // worst-case numbers on the narrowest phone still fit without the title
  assert.ok(estimateHeaderWidth({ streakChars: 3, coinChars: 5, showTitle: false }) <= 320);
  // dropping the title is monotonic: if it fits at a width it fits at every wider width
  let seen = false;
  for (let w = 300; w <= 460; w += 4) { const f = titleFits(w, { streakChars: 2, coinChars: 4 }); if (seen) assert.ok(f, `flapped at ${w}`); seen = seen || f; }
});

test('without the shortcuts (feature unavailable) the header is no wider than before', () => {
  assert.ok(estimateHeaderWidth({ showShortcuts: false, showTitle: true }) <= 360);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  recipeChecks, recipeScore, estimateOutcome, pricePosition, hasBenchmarks, recipeCopy, formatVndShort,
} from '../../src/lib/eventRecipe.js';

// Mirrored 1:1 by apps/ios/BanbeAppTests/EventRecipeTests.swift — change both together.
const NOW = Date.parse('2026-10-21T03:00:00Z'); // Wed 10:00 in Vietnam
const ict = (iso) => Date.parse(iso + '+07:00');
const T = (vi, en) => en;

// Same shape get_host_benchmarks returns (verified against migration 186 on Postgres 16).
const BENCH = {
  success: true, level: 'category_city', n: 13, free_share: 0,
  price: { n: 13, p25: 280000, median: 320000, p75: 380000, min: 220000, max: 440000, histogram: [2, 1, 1, 2, 1, 1, 1, 1, 1, 2] },
  fill: { n: 12, median_fill: 0.6, median_capacity: 20, median_booked: 12 },
  slots: [
    { dow: 6, slot: 'evening', n: 8, median_fill: 0.85 },
    { dow: 3, slot: 'evening', n: 5, median_fill: 0.5 },
  ],
  well_filled: { n: 6, median_photos: 6, intro_share: 0.5, included_share: 1, median_lead_days: 16.4 },
  others: { n: 6, median_photos: 2, intro_share: 0.5, included_share: 0.33, median_lead_days: 8 },
  keywords: ['wine', 'rooftop', 'chef'],
};
const COLD = { success: true, level: null, n: 0 };

const GOOD_DRAFT = {
  name: 'Six-course supper club in District 3', description: 'x'.repeat(150), intro: '', includedCount: 2,
  keywords: ['wine', 'dinner', 'rooftop'], priceVnd: 300000, seats: 16, startsAt: ict('2026-11-07T19:00:00'),
  photos: 6, chatGreeting: 'Hi! Ask me anything.',
};
const byId = (checks) => Object.fromEntries(checks.map(c => [c.id, c]));

test('a well-prepared draft scores 10/10 against real benchmarks', () => {
  const checks = recipeChecks(GOOD_DRAFT, BENCH, null, NOW);
  assert.equal(checks.length, 10);
  assert.deepEqual(checks.filter(c => c.status !== 'good').map(c => c.id), []);
  assert.deepEqual(recipeScore(checks), { good: 10, total: 10 });
});

test('an empty draft: objective gaps are missing, nothing is judged on a guess', () => {
  const c = byId(recipeChecks({}, null, null, NOW));
  for (const id of ['title', 'photos', 'description', 'included', 'keywords', 'seats', 'timing', 'lead']) {
    assert.equal(c[id].status, 'missing', id);
  }
  assert.equal(c.price.status, 'good'); // free is a valid choice
  assert.equal(c.greeting.status, 'improve');
  assert.ok(Object.values(c).every(x => x.source === 'tip'));
});

test('cold start (level null) behaves like no benchmarks: tips only, no numbers', () => {
  assert.equal(hasBenchmarks(COLD), false);
  assert.equal(hasBenchmarks(BENCH), true);
  const c = byId(recipeChecks({ ...GOOD_DRAFT, photos: 5, startsAt: ict('2026-11-03T14:00:00') }, COLD, null, NOW));
  assert.equal(c.photos.target, 5);
  assert.equal(c.photos.status, 'good');
  assert.equal(c.timing.status, 'good'); // a Tuesday afternoon is not judged without data
  assert.equal(c.timing.source, 'tip');
  assert.equal(c.price.source, 'tip');
  assert.equal(c.lead.target, 14);
});

test('title rules', () => {
  const t = (name) => byId(recipeChecks({ name }, null, null, NOW)).title;
  assert.equal(t('Jazz').status, 'improve');
  assert.equal(t('LIVE JAZZ NIGHT TONIGHT').status, 'improve');
  assert.equal(t('LIVE JAZZ NIGHT TONIGHT').shouting, true);
  assert.equal(t('Live jazz night at Saigon Social').status, 'good');
  assert.equal(t('Đêm nhạc jazz ở Quận 1').status, 'good');
});

test('photos target follows well-filled events, floored at 3', () => {
  assert.equal(byId(recipeChecks({ ...GOOD_DRAFT, photos: 5 }, BENCH, null, NOW)).photos.status, 'improve');
  assert.equal(byId(recipeChecks({ ...GOOD_DRAFT, photos: 2 }, BENCH, null, NOW)).photos.status, 'missing');
  const low = { ...BENCH, well_filled: { ...BENCH.well_filled, median_photos: 1 } };
  assert.equal(byId(recipeChecks({ ...GOOD_DRAFT, photos: 3 }, low, null, NOW)).photos.target, 3);
});

test('price band and the premium goal', () => {
  assert.equal(pricePosition(200000, BENCH.price), 'below');
  assert.equal(pricePosition(320000, BENCH.price), 'typical');
  assert.equal(pricePosition(500000, BENCH.price), 'premium');
  assert.equal(pricePosition(0, BENCH.price), 'free');
  const pricey = { ...GOOD_DRAFT, priceVnd: 600000 };
  assert.equal(byId(recipeChecks(pricey, BENCH, null, NOW)).price.status, 'improve');
  assert.equal(byId(recipeChecks(pricey, BENCH, 'small_premium', NOW)).price.status, 'good');
  assert.equal(byId(recipeChecks({ ...GOOD_DRAFT, priceVnd: 150000 }, BENCH, null, NOW)).price.status, 'good');
});

test('seats vs typical guests; "fill every seat" is stricter', () => {
  // typical 12: default limit max(24, 22) = 24; fill_seats limit max(18, 17) = 18
  assert.equal(byId(recipeChecks({ ...GOOD_DRAFT, seats: 20 }, BENCH, null, NOW)).seats.status, 'good');
  assert.equal(byId(recipeChecks({ ...GOOD_DRAFT, seats: 20 }, BENCH, 'fill_seats', NOW)).seats.status, 'improve');
  assert.equal(byId(recipeChecks({ ...GOOD_DRAFT, seats: 30 }, BENCH, null, NOW)).seats.status, 'improve');
  assert.equal(byId(recipeChecks({ ...GOOD_DRAFT, seats: 30 }, null, null, NOW)).seats.status, 'good');
});

test('timing compares this slot with the best slot only when the cell exists', () => {
  const wed = byId(recipeChecks({ ...GOOD_DRAFT, startsAt: ict('2026-11-04T19:30:00') }, BENCH, null, NOW)).timing;
  assert.equal(wed.status, 'improve');
  assert.deepEqual([wed.dow, wed.slot, wed.ownFill], [3, 'evening', 0.5]);
  assert.deepEqual(wed.best, { dow: 6, slot: 'evening', fill: 0.85 });
  const sat = byId(recipeChecks(GOOD_DRAFT, BENCH, null, NOW)).timing;
  assert.equal(sat.status, 'good');
  assert.equal(sat.best, null);
  const mon = byId(recipeChecks({ ...GOOD_DRAFT, startsAt: ict('2026-11-02T22:00:00') }, BENCH, null, NOW)).timing;
  assert.equal(mon.slot, 'late');
  assert.equal(mon.status, 'good'); // no cell for Monday late: not judged
  assert.equal(mon.source, 'tip');
});

test('lead time uses the well-filled median (rounded), else 14 days', () => {
  const soon = byId(recipeChecks({ ...GOOD_DRAFT, startsAt: ict('2026-10-30T19:00:00') }, BENCH, null, NOW)).lead;
  assert.deepEqual([soon.status, soon.days, soon.target], ['improve', 9, 16]);
  assert.equal(byId(recipeChecks(GOOD_DRAFT, BENCH, null, NOW)).lead.status, 'good');
});

test('keyword suggestions exclude what the host already has', () => {
  const k = byId(recipeChecks({ ...GOOD_DRAFT, keywords: ['Wine'] }, BENCH, null, NOW)).keywords;
  assert.equal(k.status, 'improve');
  assert.deepEqual(k.suggestions, ['rooftop', 'chef']);
});

test('outcome estimate: similar-event fill when known, else the honest full-house figure', () => {
  assert.deepEqual(estimateOutcome(300000, 16, 0.6), { guests: 10, revenueVnd: 3000000, basis: 'similar', fill: 0.6 });
  assert.deepEqual(estimateOutcome(300000, 16, null), { guests: 16, revenueVnd: 4800000, basis: 'full', fill: null });
  assert.deepEqual(estimateOutcome(0, 10, 0.5), { guests: 5, revenueVnd: 0, basis: 'similar', fill: 0.5 });
  assert.equal(estimateOutcome(300000, 0, 0.6), null);
  assert.equal(estimateOutcome(300000, 2, 0.1).guests, 1);
});

test('copy names its evidence and never shows a number from a tip', () => {
  const checks = recipeChecks(GOOD_DRAFT, BENCH, null, NOW);
  for (const c of checks) {
    const { title, detail } = recipeCopy(c, T);
    assert.ok(title.length > 0, c.id);
    assert.ok(detail.length > 0, c.id);
  }
  const price = recipeCopy(byId(checks).price, T);
  assert.match(price.detail, /280k₫–380k₫/);
  assert.match(price.detail, /Based on 13 similar events/);
  const coldPrice = recipeCopy(byId(recipeChecks(GOOD_DRAFT, null, null, NOW)).price, T);
  assert.doesNotMatch(coldPrice.detail, /\d/);
  assert.equal(formatVndShort(3300000), '3,3M₫');
  assert.equal(formatVndShort(3000000), '3M₫');
  assert.equal(formatVndShort(250000), '250k₫');
});

// Draggable price slider (2026-10-21).
import { priceToFraction, fractionToPrice } from '../../src/lib/eventRecipe.js';
test('price slider maps the market range both ways, snapped to 10k', () => {
  const p = { min: 250000, max: 600000 };
  assert.equal(priceToFraction(250000, p), 0);
  assert.equal(priceToFraction(600000, p), 1);
  assert.equal(priceToFraction(100000, p), 0, 'below the market pins to the left edge');
  assert.equal(priceToFraction(900000, p), 1);
  assert.equal(fractionToPrice(0.5, p), 430000);
  assert.equal(fractionToPrice(0, p), 250000);
  assert.equal(fractionToPrice(1, p), 600000);
  assert.equal(fractionToPrice(0.123, p) % 10000, 0);
  assert.equal(priceToFraction(5, { min: 100000, max: 100000 }), 0.5, 'flat market sits in the middle');
  assert.equal(priceToFraction(5, null), null);
  assert.equal(fractionToPrice(0.5, { min: 251000, max: 259000 }), 255000, 'market narrower than a step');
});

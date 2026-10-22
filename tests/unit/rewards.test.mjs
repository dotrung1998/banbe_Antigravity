import test from 'node:test';
import assert from 'node:assert/strict';
import { compactCoins, shortcutLabels, isRewardsUnavailable, normalizeSummary, historyLabel, ruleLines, shortfall, redemptionTermsLines, noCoinLines } from '../../src/lib/rewards.js';

const T = (vi, en) => en;

test('compactCoins keeps the header stable on narrow screens', () => {
  assert.equal(compactCoins(0), '0');
  assert.equal(compactCoins(9999), '9999');
  assert.equal(compactCoins(10000), '10k');
  assert.equal(compactCoins(12500), '12.5k');
  assert.equal(compactCoins(-40), '-40');          // a balance can go negative after a reversal
  assert.equal(compactCoins(NaN), '0');
});

test('accessible labels carry the numbers and the destination', () => {
  const l = shortcutLabels(T, { streak: 5, balance: 120 });
  assert.match(l.streak, /5-day streak/);
  assert.match(l.coins, /120 coins/);
  assert.match(l.coins, /Open rewards/);
});

test('a missing RPC hides the feature instead of faking numbers', () => {
  assert.equal(isRewardsUnavailable({ code: 'PGRST202' }), true);
  assert.equal(isRewardsUnavailable({ code: '42883' }), true);
  assert.equal(isRewardsUnavailable({ message: 'Could not find the function public.get_my_rewards' }), true);
  assert.equal(isRewardsUnavailable({ code: '500', message: 'boom' }), false);
  assert.equal(normalizeSummary(null), null);
  assert.equal(normalizeSummary({ success: false }), null);
  assert.deepEqual(normalizeSummary({ success: true, balance: 20, streak: 2, active_today: true }), { balance: 20, streak: 2, activeToday: true });
});

test('history labels are readable and never expose raw codes', () => {
  assert.equal(historyLabel({ reason: 'attendance', event_name: 'Jazz' }, T), 'Attended an event ▪︎ Jazz');
  assert.match(historyLabel({ reason: 'attendance_reversed' }, T), /undone/);
  assert.equal(historyLabel({ reason: 'something_new' }, T), 'Activity');
});

test('earning rules are built from the server values', () => {
  const lines = ruleLines({ onboarding_coins: 10, attendance_coins: 20, attendance_coin_cap_per_month: 10 }, T);
  assert.equal(lines.length, 3);
  assert.match(lines[0], /\+10 coins/);
  assert.match(lines[1], /\+20 coins/);
  assert.match(lines[2], /10 events pay coins per month \(200 coins\)/);
  assert.equal(ruleLines({ onboarding_coins: 5, attendance_coins: 7 }, T).length, 2); // no cap line without a cap
});

test('terms state the non-negotiables', () => {
  const all = [...redemptionTermsLines(T), ...noCoinLines(T)].join(' ');
  for (const must of [/cannot be bought, transferred or cashed out/, /no random prizes/i, /never affect booking, priority or eligibility/, /free charms always stay available/, /negative/, /never costs coins/, /claimed the ticket/]) {
    assert.match(all, must);
  }
});

test('shortfall is exact and never negative', () => {
  assert.equal(shortfall(60, 80), 20);
  assert.equal(shortfall(100, 80), 0);
  assert.equal(shortfall(-40, 40), 80);
});

test('streakLines names the zone in force and no longer calls it fixed', async () => {
  const { streakLines } = await import('../../src/lib/rewards.js');
  const T = (vi, en) => en;
  assert.match(streakLines(T, 1, 'America/New_York')[1], /America\/New_York/);
  assert.doesNotMatch(streakLines(T, 1, 'America/New_York')[1], /fixed/);
  assert.match(streakLines(T, 1, undefined)[1], /Asia\/Ho_Chi_Minh/);
});

test('timezone settings normalise and tolerate an older server without the key', async () => {
  const { normalizeTzSettings, deviceTimezoneHint, SUGGESTED_TIMEZONES } = await import('../../src/lib/rewards.js');
  assert.equal(normalizeTzSettings(undefined), null);
  assert.deepEqual(normalizeTzSettings({ effective_tz: 'America/Chicago', chosen: true, pending_tz: null, changes_left: 1 }),
    { effective: 'America/Chicago', chosen: true, pending: null, pendingFrom: null, changesLeft: 1, nextChangeAt: null });
  assert.equal(deviceTimezoneHint(() => 'America/New_York'), 'America/New_York');
  assert.equal(deviceTimezoneHint(() => 'Europe/Paris'), null);
  assert.equal(deviceTimezoneHint(() => { throw new Error('x'); }), null);
  assert.equal(SUGGESTED_TIMEZONES[0][0], 'Asia/Ho_Chi_Minh');
});

// ---- migration 179: catalog split (designs vs offers) ----
const OLD_PAYLOAD = { success: true, balance: 60, catalog: [
  { code: 'rwd-comet', kind: 'keychain_design', design_id: 'rwd-comet', price: 40, unlocked: false },
  { code: 'rwd-lantern', kind: 'keychain_design', design_id: 'rwd-lantern', price: 80, unlocked: true } ] };           // pre-179 server
const NEW_PAYLOAD_NO_OFFERS = { ...OLD_PAYLOAD, offers: [], catalog: OLD_PAYLOAD.catalog.map(c => ({ ...c, title_vi: null, title_en: null, desc_vi: null, desc_en: null, status: c.unlocked ? 'unlocked' : 'available' })) };
const OFFER = { code: 'offer-x', kind: 'partner_offer', price: 50, title_vi: 'Ưu đãi X', title_en: 'Offer X', desc_vi: 'mô tả', desc_en: 'description', status: 'unavailable' };

test('splitRewardCatalog: a server without migration 179 (no kind-split, no offers) still shows every design and no Offers section', async () => {
  const { splitRewardCatalog } = await import('../../src/lib/rewards.js');
  const s = splitRewardCatalog({ success: true, catalog: [{ code: 'a', design_id: 'a', price: 1, unlocked: false }] });  // not even `kind`
  assert.equal(s.designs.length, 1); assert.deepEqual(s.offers, []); assert.equal(s.showOffers, false);
  assert.equal(splitRewardCatalog(OLD_PAYLOAD).designs.length, 2);
});

test('splitRewardCatalog: 179 with the flag off (offers = []) hides the Offers section and keeps the designs', async () => {
  const { splitRewardCatalog } = await import('../../src/lib/rewards.js');
  const s = splitRewardCatalog(NEW_PAYLOAD_NO_OFFERS);
  assert.equal(s.designs.length, 2); assert.equal(s.showOffers, false);
});

test('splitRewardCatalog: offers are read from `offers`, never mixed into the keychain list', async () => {
  const { splitRewardCatalog } = await import('../../src/lib/rewards.js');
  const s = splitRewardCatalog({ ...NEW_PAYLOAD_NO_OFFERS, offers: [OFFER] });
  assert.equal(s.showOffers, true); assert.equal(s.offers[0].code, 'offer-x'); assert.equal(s.offers[0].status, 'unavailable');
  assert.ok(s.designs.every(d => d.kind === 'keychain_design' && typeof d.design_id === 'string'));
  assert.ok(!s.designs.some(d => d.code === 'offer-x'));
});

test('splitRewardCatalog: an offer that leaks into `catalog` can never become a keychain row, and bad input does not throw', async () => {
  const { splitRewardCatalog } = await import('../../src/lib/rewards.js');
  const leaked = splitRewardCatalog({ catalog: [...OLD_PAYLOAD.catalog, { ...OFFER, design_id: null }, { ...OFFER, code: 'o2', design_id: undefined }] });
  assert.equal(leaked.designs.length, 2);
  for (const bad of [null, undefined, {}, { catalog: 'x', offers: 'y' }, { catalog: [null, 3], offers: [null, {}, { code: 5 }] }]) {
    const s = splitRewardCatalog(bad); assert.ok(Array.isArray(s.designs) && Array.isArray(s.offers) && s.showOffers === false);
  }
});

test('old client reading a 179 payload: every catalog row still has what the pre-179 screen reads', () => {
  for (const c of NEW_PAYLOAD_NO_OFFERS.catalog) {
    assert.equal(typeof c.code, 'string'); assert.equal(typeof c.design_id, 'string');
    assert.equal(typeof c.price, 'number'); assert.equal(typeof c.unlocked, 'boolean');
  }
});

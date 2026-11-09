// Port of iOS BanbeAppTests/OnboardingFlowTests.swift (notes 43, 80): same flow rules, same server payloads.
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  reduce, initialState, draftStore, impactLines, revealMatches, QUESTIONS, currentConsent, consentAsksSystem,
  typeCounts, tileTypes, matchCount, optionCount, revealPlan, MIN_FOR_YOU, TILE_MAX, onboardingCandidates,
} from '../../src/lib/onboardingFlow.js';
import { matchBucket } from '../../src/lib/analytics.js';
import { loadChecklist, saveChecklist, checklistVisible } from '../../src/lib/activationChecklist.js';
import { NO_PREFERENCE } from '../../src/lib/eventPrefs.js';

const fresh = (settings = false, consents = []) => initialState({ needsPreferences: true, needsSettings: settings, region: 'VN', consents });
/** Runs actions in order; returns the final state and the LAST action's effects. */
function run(s, ...actions) {
  let effects = [];
  for (const a of actions) ({ state: s, effects } = reduce(s, a));
  return { s, effects };
}
const saves = (effects) => effects.filter(e => e.type === 'save').map(e => e.payload);
const tracked = (effects) => effects.filter(e => e.type === 'track');
const currentQuestion = (s) => (s.stage === 'question' ? QUESTIONS[s.index] : null);
const music = { type: 'toggle', question: 'interests', id: 'music' };
/** Every remaining question with `next`, ending on 'saving'; returns the last effects. */
function finishQuestions(s) {
  let effects = [];
  while (currentQuestion(s)) ({ state: s, effects } = reduce(s, 'next'));
  return { s, effects };
}
const memoryStorage = () => {
  const m = new Map();
  return { getItem: k => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), removeItem: k => m.delete(k) };
};

test('initial stage follows the server flags', () => {
  assert.equal(initialState({ needsPreferences: true, needsSettings: true }).stage, 'welcome');
  assert.equal(initialState({ needsPreferences: false, needsSettings: true, consents: ['hosting'] }).stage, 'consent');
  assert.equal(initialState({ needsPreferences: false, needsSettings: true }).stage, 'settingsSaving', 'nothing to ask: only the marker');
  assert.equal(initialState({ needsPreferences: false, needsSettings: false }).stage, 'finished');
});

test('three questions, in order', () => {
  let { s } = run(fresh(), 'start');
  const seen = [];
  while (currentQuestion(s)) { seen.push(currentQuestion(s)); s = reduce(s, 'next').state; }
  assert.deepEqual(seen, ['interests', 'availability', 'budget'], 'goals and languages are no longer asked');
  assert.equal(s.stage, 'saving');
});

test('back walks to welcome and keeps answers', () => {
  let { s } = run(fresh(), 'start', music, 'next');
  assert.equal(currentQuestion(s), 'availability');
  s = reduce(s, 'back').state;
  assert.equal(currentQuestion(s), 'interests');
  assert.deepEqual(s.draft.interests, ['music'], 'Back never discards an answer');
  s = reduce(s, 'back').state;
  assert.equal(s.stage, 'welcome');
});

test('skip question clears only that answer', () => {
  const { s, effects } = run(fresh(), 'start', music, 'next', { type: 'toggle', question: 'availability', id: 'weekends' }, 'skipQuestion');
  assert.equal(s.draft.availability, undefined);
  assert.deepEqual(s.draft.interests, ['music']);
  assert.deepEqual(tracked(effects)[0], { type: 'track', name: 'onboarding_question_skipped', props: { question_id: 'availability' } });
});

test('"no preference" is exclusive and multi-select works', () => {
  const t = (id) => ({ type: 'toggle', question: 'interests', id });
  let { s } = run(fresh(), 'start', t('music'), t('gallery'));
  assert.deepEqual(s.draft.interests, ['music', 'gallery']);
  s = reduce(s, t(NO_PREFERENCE)).state;
  assert.deepEqual(s.draft.interests, [NO_PREFERENCE]);
  s = reduce(s, t('music')).state;
  assert.deepEqual(s.draft.interests, ['music']);
  s = reduce(s, t('music')).state;
  assert.equal(s.draft.interests, undefined, 'deselecting the last option means skipped');
});

test('budget keeps VND/USD behaviour', () => {
  let { s } = run(fresh(), 'start', { type: 'pickBudget', tier: 'low' });
  assert.deepEqual(s.draft.budget, { tier: 'low', currency: 'VND' });
  s = reduce(s, { type: 'setRegion', region: 'US' }).state;
  assert.deepEqual(s.draft.budget, { tier: 'low', currency: 'USD' });
  s = reduce(s, { type: 'pickBudget', tier: 'free' }).state;
  assert.deepEqual(s.draft.budget, { tier: 'free' });
  s = reduce(s, { type: 'pickBudget', tier: 'free' }).state;
  assert.equal(s.draft.budget, undefined);
});

test('finishing saves normalized answers, then reveals', () => {
  let { s, effects } = finishQuestions(run(fresh(), 'start', music).s);
  assert.deepEqual(saves(effects), [{ version: 1, interests: ['music'] }]);
  ({ state: s, effects } = reduce(s, 'saveSucceeded'));
  assert.equal(s.stage, 'reveal');
  assert.equal(s.needsPreferences, false);
  assert.deepEqual(tracked(effects), [{ type: 'track', name: 'onboarding_completed', props: { answered_questions: 1, skipped_all: false } }]);
});

test('all questions skipped saves the marker only and skips the reveal', () => {
  let { s, effects } = run(fresh(true, ['hosting']), 'start', 'skipQuestion', 'skipQuestion', 'skipQuestion');
  assert.deepEqual(saves(effects), [null], 'nothing answered = marker only, no invented answers');
  s = reduce(s, 'saveSucceeded').state;
  assert.equal(currentConsent(s), 'hosting');
});

test('skip all from welcome ends on the recap', () => {
  let { s, effects } = run(fresh(), 'skipAll');
  assert.deepEqual(saves(effects), [null]);
  s = reduce(s, 'saveSucceeded').state;
  assert.equal(s.stage, 'recap', 'the recap still offers the tour');
  s = reduce(s, 'skipTour').state;
  assert.equal(s.stage, 'finished');
  assert.equal(s.tourRequested, false);
});

test('skip all discards draft answers from the payload', () => {
  const { effects } = run(fresh(), 'start', music, 'skipAll');
  assert.deepEqual(saves(effects), [null]);
});

test('save failure: retry, back and skip for now', () => {
  let { s } = finishQuestions(run(fresh(), 'start', music).s);
  s = reduce(s, 'saveFailed').state;
  assert.equal(s.stage, 'saveFailed');
  assert.equal(s.needsPreferences, true, 'a failed save never counts as done');
  let effects;
  ({ state: s, effects } = reduce(s, 'retrySave'));
  assert.deepEqual(saves(effects), [{ version: 1, interests: ['music'] }]);
  s = run(s, 'saveFailed', 'back').s;
  assert.equal(currentQuestion(s), 'budget');
  assert.deepEqual(s.draft.interests, ['music']);
  s = run(s, 'next', 'saveFailed', 'skipForNow').s;
  assert.equal(s.stage, 'recap');
});

test('late or duplicate actions are ignored', () => {
  let { s } = run(fresh(), 'skipAll');
  assert.deepEqual(reduce(s, 'skipAll').effects, [], 'double tap cannot save twice');
  s = reduce(s, 'saveSucceeded').state;
  const before = s;
  s = run(s, 'saveFailed', 'back', { type: 'consentAnswered', kind: 'hosting', on: true }).s;
  assert.deepEqual(s, before, 'nothing moves backwards past a successful save');
});

// MARK: reveal → choices → recap

test('reveal, then one choice per screen, then the recap', () => {
  let { s } = finishQuestions(run(fresh(true, ['digest', 'hosting']), 'start', music).s);
  s = reduce(s, 'saveSucceeded').state;
  assert.equal(s.stage, 'reveal');
  s = reduce(s, 'revealContinue').state;
  assert.equal(currentConsent(s), 'digest');
  assert.deepEqual(reduce(s, { type: 'consentAnswered', kind: 'hosting', on: true }).state, s, 'an answer for another screen is ignored');
  s = reduce(s, { type: 'consentAnswered', kind: 'digest', on: false }).state;
  const last = reduce(s, { type: 'consentAnswered', kind: 'hosting', on: true });
  assert.deepEqual(last.effects, [{ type: 'completeSettings' }], 'the settings marker follows the last choice');
  s = last.state;
  assert.deepEqual(s.choices, { digest: false, hosting: true });
  s = reduce(s, 'settingsSucceeded').state;
  assert.equal(s.needsSettings, false);
  assert.equal(s.stage, 'recap');
  s = reduce(s, 'startTour').state;
  assert.equal(s.stage, 'finished');
  assert.equal(s.tourRequested, true);
});

test('only the system-asked choice has one action', () => {
  assert.equal(consentAsksSystem('push'), true);
  assert.equal(consentAsksSystem('digest'), false);
  assert.equal(consentAsksSystem('hosting'), false);
});

test('settings owed with nothing to ask writes the marker', () => {
  const { s, effects } = run(fresh(true), 'skipAll', 'saveSucceeded');
  assert.deepEqual(effects.filter(e => e.type === 'completeSettings'), [{ type: 'completeSettings' }]);
  assert.equal(s.stage, 'settingsSaving');
});

test('settings failure: retry and skip for now', () => {
  let { s, effects } = run(initialState({ needsPreferences: false, needsSettings: true, consents: ['hosting'] }), { type: 'consentAnswered', kind: 'hosting', on: false });
  assert.deepEqual(effects, [{ type: 'completeSettings' }]);
  s = reduce(s, 'settingsFailed').state;
  assert.equal(s.stage, 'settingsFailed');
  assert.deepEqual(reduce(s, 'retrySettings').effects, [{ type: 'completeSettings' }]);
  s = run(s, 'retrySettings', 'settingsFailed', 'skipSettingsForNow').s;
  assert.equal(s.stage, 'recap');
  assert.equal(s.needsSettings, true, 'a failed marker never counts as done');
});

test('"change my answers" from the reveal keeps them to edit', () => {
  let { s } = finishQuestions(run(fresh(), 'start', music).s);
  s = run(s, 'saveSucceeded', 'redoAnswers').s;
  assert.equal(currentQuestion(s), 'interests');
  assert.deepEqual(s.draft.interests, ['music']);
  s = reduce(s, { type: 'toggle', question: 'interests', id: 'gallery' }).state;
  assert.deepEqual(saves(finishQuestions(s).effects), [{ version: 1, interests: ['music', 'gallery'] }]);
});

test('analytics carries ids and counts, never values', () => {
  const { effects } = run(fresh(), 'start', music, { type: 'toggle', question: 'interests', id: 'gallery' }, 'next');
  const answered = tracked(effects)[0];
  assert.deepEqual(answered.props, { question_id: 'interests', answer_count: 2 });
  assert.ok(!JSON.stringify(effects).includes('music'));
});

test('match buckets', () => {
  assert.deepEqual([0, 1, 2, 3, 5, 6, 10, 11, 99].map(matchBucket), ['0', '1-2', '1-2', '3-5', '3-5', '6-10', '6-10', '11+', '11+']);
});

// MARK: draft (this browser, per account)

test('draft resumes while owed; the server wins', () => {
  const st = memoryStorage();
  const { s } = run(fresh(), 'start', music, 'next');
  draftStore.save(s, 'u1', st);
  const resumed = draftStore.resume('u1', { needsPreferences: true, needsSettings: false, region: 'VN' }, st);
  assert.equal(resumed.stage, 'question');
  assert.equal(resumed.index, 1);
  assert.deepEqual(resumed.draft.interests, ['music']);
  // Questions no longer owed (answered on another device): the draft is ignored.
  assert.equal(draftStore.resume('u1', { needsPreferences: false, needsSettings: true, region: 'VN', consents: ['hosting'] }, st).stage, 'consent');
  // Per account.
  assert.equal(draftStore.resume('u2', { needsPreferences: true, needsSettings: false, region: 'VN' }, st).stage, 'welcome');
  draftStore.clear('u1', st);
  assert.equal(draftStore.load('u1', st), null);
});

test('a save-failed draft resumes at the last question', () => {
  const st = memoryStorage();
  const s = reduce(finishQuestions(run(fresh(), 'start').s).s, 'saveFailed').state;
  draftStore.save(s, 'u1', st);
  const resumed = draftStore.resume('u1', { needsPreferences: true, needsSettings: false, region: 'VN' }, st);
  assert.equal(resumed.stage, 'question');
  assert.equal(resumed.index, 2);
});

// MARK: live counts and the reveal plan (twin of the iOS OnboardingCounts tests)

const NOW = Date.UTC(2027, 0, 13, 3); // a Wednesday, 10:00 in Ho Chi Minh City
const cand = (key, cat, days, { price = 0, bookable = true } = {}) => ({
  key, categories: [cat], priceAmount: price, priceCurrency: 'VND', isFree: price === 0,
  startsAt: NOW + days * 864e5, timeZone: 'Asia/Ho_Chi_Minh', isBookable: bookable,
});

test('tiles are only types with events, most first, at most five', () => {
  const events = [cand('a', 'music', 1), cand('b', 'music', 2), cand('c', 'gallery', 3), cand('d', 'fashion', 1, { bookable: false }), cand('e', 'supper', -1)];
  const counts = typeCounts(events, NOW);
  assert.deepEqual(counts, { music: 2, gallery: 1 }, 'sold out / past events never count');
  assert.deepEqual(tileTypes(counts), ['music', 'gallery']);
  const many = Object.fromEntries(Array.from({ length: 9 }, (_, i) => [`t${i}`, 9 - i]));
  assert.equal(tileTypes(many).length, TILE_MAX);
});

test('option counts follow the matcher rules', () => {
  const events = [cand('a', 'music', 1), cand('b', 'music', 2, { price: 500000 }), cand('c', 'gallery', 3)];
  const p = { interests: ['music'] };
  assert.equal(matchCount(events, p, NOW), 2);
  assert.equal(optionCount(events, p, 'budget', 'free', 'VN', NOW), 1);
  assert.equal(optionCount(events, p, 'budget', 'flexible', 'VN', NOW), 2);
  assert.equal(optionCount(events, p, 'budget', 'low', 'VN', NOW), 1, 'low caps at 200.000₫');
});

test('the reveal is never empty', () => {
  const events = [cand('a', 'music', 1), cand('b', 'music', 2), cand('c', 'music', 3), cand('d', 'gallery', 4), cand('e', 'supper', 5)];
  const picked = revealPlan(events, { interests: ['music'] }, NOW);
  assert.equal(picked.mode, 'picked');
  assert.equal(picked.exact, 3);
  assert.deepEqual(new Set(picked.keys), new Set(['a', 'b', 'c']));

  const topped = revealPlan(events, { interests: ['gallery'] }, NOW);
  assert.equal(topped.mode, 'topped');
  assert.equal(topped.keys[0], 'd', 'exact matches stay first');
  assert.equal(topped.keys.length, MIN_FOR_YOU + 2);

  const soon = revealPlan(events, { interests: ['film'] }, NOW);
  assert.equal(soon.mode, 'soon');
  assert.deepEqual(soon.waiting, ['film']);
  assert.equal(soon.keys[0], 'a', 'the soonest events fill in');

  const popular = revealPlan(events, {}, NOW);
  assert.equal(popular.mode, 'popular');
  assert.ok(popular.keys.length > 0);

  assert.deepEqual(revealPlan([], { interests: ['music'] }, NOW).keys, [], 'only empty when nothing is on at all');
});

test('onboarding candidates: live + public, inside the area', () => {
  const soon = new Date(Date.now() + 3 * 864e5).toISOString();
  const ev = (key, over = {}) => ({ key, catKey: 'music', priceVnd: 0, countryCode: 'VN', stateProvince: 'Hồ Chí Minh', startsAt: soon, status: 'live', visibility: 'public', ...over });
  const events = [ev('m'), ev('hn', { stateProvince: 'Hà Nội' }), ev('x', { status: 'ended' }), ev('inv', { visibility: 'invite' })];
  assert.deepEqual(onboardingCandidates(events, null).map(c => c.key), ['m', 'hn']);
  assert.deepEqual(onboardingCandidates(events, e => e.stateProvince === 'Hà Nội').map(c => c.key), ['hn']);
});

// MARK: reveal

test('impact lines mirror the matcher rules', () => {
  const lines = impactLines({ interests: ['music'], goals: ['learn'], availability: ['evening'], budget: { tier: 'low', currency: 'VND' }, languages: ['en'] }, false);
  assert.deepEqual(lines.map(l => l.kind), ['filter', 'filter', 'ranking', 'ranking', 'savedOnly']);
  assert.equal(lines[0].text, 'Only suggests: Music');
  assert.ok(lines[1].text.includes('200.000₫'));
  assert.ok(lines[4].text.includes("doesn't filter"));
});

test('"no preference" answers produce no impact lines', () => {
  assert.deepEqual(impactLines({ interests: [NO_PREFERENCE], budget: { tier: NO_PREFERENCE } }, true), []);
});

test('reveal uses the real matcher: zero matches when interests exclude, area limits, live+public only', () => {
  const soon = new Date(Date.now() + 3 * 864e5).toISOString();
  const ev = (key, over = {}) => ({ key, catKey: 'music', priceVnd: 0, countryCode: 'VN', stateProvince: 'Hồ Chí Minh', startsAt: soon, status: 'live', visibility: 'public', soldOut: false, ...over });
  const events = [ev('f', { catKey: 'fashion' }), ev('m'), ev('hn', { stateProvince: 'Hà Nội' }), ev('x', { status: 'ended' }), ev('inv', { visibility: 'invite' })];
  const prefs = { interests: ['music'] };
  assert.deepEqual(revealMatches([ev('f', { catKey: 'fashion' })], prefs, null).matches, []);
  const all = revealMatches(events, prefs, null);
  assert.deepEqual(all.matches.map(m => m.key).sort(), ['hn', 'm']);
  const hcm = revealMatches(events, prefs, e => e.stateProvince === 'Hồ Chí Minh');
  assert.deepEqual(hcm.matches.map(m => m.key), ['m']);
  assert.equal(hcm.everywhereCount, 2, 'offers "all areas" only when matches exist elsewhere');
  assert.deepEqual(revealMatches(events, null, null).matches, [], 'no answers, no picks');
});

// MARK: activation checklist

test('checklist visibility', () => {
  const st = memoryStorage();
  let c = loadChecklist('u1', st);
  assert.equal(checklistVisible(c, false), false);
  c = { ...c, enabled: true };
  assert.equal(checklistVisible(c, false), true);
  assert.equal(checklistVisible({ ...c, openedEvent: true }, true), true, 'stays up once done, for the one-time celebration');
  assert.equal(checklistVisible({ ...c, openedEvent: true, celebrated: true }, true), false, 'hides after the celebration');
  assert.equal(checklistVisible({ ...c, dismissed: true }, false), false);
  saveChecklist({ ...c, openedEvent: true }, 'u1', st);
  assert.deepEqual(loadChecklist('u1', st), { enabled: true, dismissed: false, openedEvent: true, celebrated: false });
  st.setItem('banbe.activation.v1.u3', JSON.stringify({ enabled: true, dismissed: false, openedEvent: true }));
  assert.equal(loadChecklist('u3', st).celebrated, false, 'states saved before `celebrated` still load');
  assert.equal(loadChecklist('u2', st).enabled, false, 'per account');
});

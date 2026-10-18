// Port of iOS BanbeAppTests/OnboardingFlowTests.swift (note 43): same flow rules, same server payloads.
import test from 'node:test';
import assert from 'node:assert/strict';
import { reduce, initialState, draftStore, impactLines, revealMatches, QUESTIONS } from '../../src/lib/onboardingFlow.js';
import { matchBucket } from '../../src/lib/analytics.js';
import { loadChecklist, saveChecklist, checklistVisible } from '../../src/lib/activationChecklist.js';
import { NO_PREFERENCE } from '../../src/lib/eventPrefs.js';

const fresh = (settings = false) => initialState({ needsPreferences: true, needsSettings: settings, region: 'VN' });
/** Runs actions in order; returns the final state and the LAST action's effects. */
function run(s, ...actions) {
  let effects = [];
  for (const a of actions) ({ state: s, effects } = reduce(s, a));
  return { s, effects };
}
const saves = (effects) => effects.filter(e => e.type === 'save').map(e => e.payload);
const tracked = (effects) => effects.filter(e => e.type === 'track');
const currentQuestion = (s) => (s.stage === 'question' ? QUESTIONS[s.index] : null);
const memoryStorage = () => {
  const m = new Map();
  return { getItem: k => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), removeItem: k => m.delete(k) };
};

test('initial stage follows the server flags', () => {
  assert.equal(initialState({ needsPreferences: true, needsSettings: true }).stage, 'welcome');
  assert.equal(initialState({ needsPreferences: false, needsSettings: true }).stage, 'settings');
  assert.equal(initialState({ needsPreferences: false, needsSettings: false }).stage, 'finished');
});

test('one question per screen, in order', () => {
  let { s } = run(fresh(), 'start');
  const seen = [];
  while (currentQuestion(s)) { seen.push(currentQuestion(s)); s = reduce(s, 'next').state; }
  assert.deepEqual(seen, ['goals', 'interests', 'availability', 'budget', 'languages']);
  assert.equal(s.stage, 'saving');
});

test('back walks to welcome and keeps answers', () => {
  let { s } = run(fresh(), 'start', { type: 'toggle', question: 'goals', id: 'learn' }, 'next');
  assert.equal(currentQuestion(s), 'interests');
  s = reduce(s, 'back').state;
  assert.equal(currentQuestion(s), 'goals');
  assert.deepEqual(s.draft.goals, ['learn'], 'Back never discards an answer');
  s = reduce(s, 'back').state;
  assert.equal(s.stage, 'welcome');
});

test('skip question clears only that answer', () => {
  const { s, effects } = run(fresh(), 'start', { type: 'toggle', question: 'goals', id: 'learn' }, 'next',
    { type: 'toggle', question: 'interests', id: 'music' }, 'skipQuestion');
  assert.equal(s.draft.interests, undefined);
  assert.deepEqual(s.draft.goals, ['learn']);
  assert.deepEqual(tracked(effects)[0], { type: 'track', name: 'onboarding_question_skipped', props: { question: 'interests' } });
});

test('"no preference" is exclusive and multi-select works', () => {
  const t = (id) => ({ type: 'toggle', question: 'goals', id });
  let { s } = run(fresh(), 'start', t('learn'), t('meet_people'));
  assert.deepEqual(s.draft.goals, ['learn', 'meet_people']);
  s = reduce(s, t(NO_PREFERENCE)).state;
  assert.deepEqual(s.draft.goals, [NO_PREFERENCE]);
  s = reduce(s, t('learn')).state;
  assert.deepEqual(s.draft.goals, ['learn']);
  s = reduce(s, t('learn')).state;
  assert.equal(s.draft.goals, undefined, 'deselecting the last option means skipped');
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
  let { s, effects } = run(fresh(), 'start', { type: 'toggle', question: 'goals', id: 'learn' }, 'next', 'next', 'next', 'next', 'next');
  assert.deepEqual(saves(effects), [{ version: 1, goals: ['learn'] }]);
  ({ state: s, effects } = reduce(s, 'saveSucceeded'));
  assert.equal(s.stage, 'reveal');
  assert.equal(s.needsPreferences, false);
  assert.deepEqual(tracked(effects), [{ type: 'track', name: 'onboarding_completed', props: { answeredQuestions: 1, skippedAll: false } }]);
});

test('all questions skipped saves the marker only and skips the reveal', () => {
  let { s, effects } = run(fresh(true), 'start', 'skipQuestion', 'skipQuestion', 'skipQuestion', 'skipQuestion', 'skipQuestion');
  assert.deepEqual(saves(effects), [null], 'nothing answered = marker only, no invented answers');
  s = reduce(s, 'saveSucceeded').state;
  assert.equal(s.stage, 'settings');
});

test('skip all from welcome', () => {
  let { s, effects } = run(fresh(), 'skipAll');
  assert.deepEqual(saves(effects), [null]);
  s = reduce(s, 'saveSucceeded').state;
  assert.equal(s.stage, 'finished');
});

test('skip all discards draft answers from the payload', () => {
  const { effects } = run(fresh(), 'start', { type: 'toggle', question: 'goals', id: 'learn' }, 'skipAll');
  assert.deepEqual(saves(effects), [null]);
});

test('save failure: retry, back and skip for now', () => {
  let { s } = run(fresh(), 'start', { type: 'toggle', question: 'interests', id: 'music' }, 'next', 'next', 'next', 'next', 'next', 'saveFailed');
  assert.equal(s.stage, 'saveFailed');
  assert.equal(s.needsPreferences, true, 'a failed save never counts as done');
  let effects;
  ({ state: s, effects } = reduce(s, 'retrySave'));
  assert.deepEqual(saves(effects), [{ version: 1, interests: ['music'] }]);
  s = run(s, 'saveFailed', 'back').s;
  assert.equal(currentQuestion(s), 'languages');
  assert.deepEqual(s.draft.interests, ['music']);
  s = run(s, 'next', 'saveFailed', 'skipForNow').s;
  assert.equal(s.stage, 'finished');
});

test('late or duplicate actions are ignored', () => {
  let { s } = run(fresh(), 'skipAll');
  assert.deepEqual(reduce(s, 'skipAll').effects, [], 'double tap cannot save twice');
  s = reduce(s, 'saveSucceeded').state;
  const before = s;
  s = run(s, 'saveFailed', 'back').s;
  assert.deepEqual(s, before, 'nothing moves backwards past a successful save');
});

test('reveal, then settings, then finished', () => {
  let { s } = run(fresh(true), 'start', { type: 'toggle', question: 'goals', id: 'learn' }, 'next', 'next', 'next', 'next', 'next', 'saveSucceeded');
  assert.equal(s.stage, 'reveal');
  s = reduce(s, 'revealContinue').state;
  assert.equal(s.stage, 'settings');
  s = reduce(s, 'settingsDone').state;
  assert.equal(s.stage, 'finished');
});

test('analytics carries ids and counts, never values', () => {
  const { effects } = run(fresh(), 'start', { type: 'toggle', question: 'goals', id: 'learn' }, 'next');
  const answered = tracked(effects)[0];
  assert.deepEqual(answered.props, { question: 'goals', answerCount: 1 });
  assert.ok(!JSON.stringify(effects).includes('learn'));
});

test('match buckets', () => {
  assert.deepEqual([0, 1, 2, 3, 5, 6, 10, 11, 99].map(matchBucket), ['0', '1-2', '1-2', '3-5', '3-5', '6-10', '6-10', '11+', '11+']);
});

// MARK: draft (this browser, per account)

test('draft resumes while owed; the server wins', () => {
  const st = memoryStorage();
  const { s } = run(fresh(), 'start', { type: 'toggle', question: 'goals', id: 'learn' }, 'next');
  draftStore.save(s, 'u1', st);
  const resumed = draftStore.resume('u1', { needsPreferences: true, needsSettings: false, region: 'VN' }, st);
  assert.equal(resumed.stage, 'question');
  assert.equal(resumed.index, 1);
  assert.deepEqual(resumed.draft.goals, ['learn']);
  // Questions no longer owed (answered on another device): the draft is ignored.
  assert.equal(draftStore.resume('u1', { needsPreferences: false, needsSettings: true, region: 'VN' }, st).stage, 'settings');
  // Per account.
  assert.equal(draftStore.resume('u2', { needsPreferences: true, needsSettings: false, region: 'VN' }, st).stage, 'welcome');
  draftStore.clear('u1', st);
  assert.equal(draftStore.load('u1', st), null);
});

test('a save-failed draft resumes at the last question', () => {
  const st = memoryStorage();
  const { s } = run(fresh(), 'start', 'next', 'next', 'next', 'next', 'next', 'saveFailed');
  draftStore.save(s, 'u1', st);
  const resumed = draftStore.resume('u1', { needsPreferences: true, needsSettings: false, region: 'VN' }, st);
  assert.equal(resumed.stage, 'question');
  assert.equal(resumed.index, 4);
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
  assert.equal(checklistVisible({ ...c, openedEvent: true }, true), false, 'hides once everything is done');
  assert.equal(checklistVisible({ ...c, dismissed: true }, false), false);
  saveChecklist({ ...c, openedEvent: true }, 'u1', st);
  assert.deepEqual(loadChecklist('u1', st), { enabled: true, dismissed: false, openedEvent: true });
  assert.equal(loadChecklist('u2', st).enabled, false, 'per account');
});

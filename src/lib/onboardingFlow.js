// Post-signup personalization flow — the pure part. Web port of iOS `Lib/OnboardingFlow.swift` (note 43):
// welcome → five questions, one per screen (n of 5, Back, Skip, Continue) → save → reveal → settings (only if
// owed) → Home. No React, no network: tests/unit/onboardingFlow.test.mjs.
//
// Server contract unchanged (migration 162, note 34): finishing calls complete_preferences_onboarding(p)
// (null = skipped everything, marker only); the settings step still calls complete_settings_onboarding.
// Answers stay owner-only.

import {
  GOALS, INTERESTS, AVAILABILITY, LANGUAGES, NO_PREFERENCE, normalizeForSave, prefsIsEmpty, toggleMulti,
  pickBudgetTier, budgetRegionCurrency, budgetRegionForCurrency, budgetCap, formatBudgetMoney, prefLabel,
  declaredInterests, declaredGoals, declaredAvailability, optionEmoji,
} from './eventPrefs.js';
import { forYouRankEvents } from './forYou.js';

export const QUESTIONS = ['goals', 'interests', 'availability', 'budget', 'languages'];

export function questionOptions(q) {
  return { goals: GOALS, interests: INTERESTS, availability: AVAILABILITY, languages: LANGUAGES }[q] || [];
}

/** How many values were chosen (1 for a budget tier). Never the values themselves. */
export function answerCount(q, p) {
  if (q === 'budget') return p?.budget ? 1 : 0;
  return Array.isArray(p?.[q]) ? p[q].length : 0;
}

function clearAnswer(q, draft) {
  const next = { ...draft };
  delete next[q];
  return next;
}

/** "Switching VND/USD re-labels a currency-bound tier; free/no-preference stay as they are." */
function switchRegion(budget, region) {
  if (!budget || !budget.currency) return budget;
  return { ...budget, currency: budgetRegionCurrency(region) };
}

export function payload(state) {
  const p = normalizeForSave(state.draft);
  return state.skippedAll || isEmptyPayload(p) ? null : p;
}
const isEmptyPayload = (p) => prefsIsEmpty(p);

export function answeredQuestionCount(state) {
  const p = normalizeForSave(state.draft);
  return QUESTIONS.filter(q => answerCount(q, p) > 0).length;
}

/**
 * stage: 'welcome' | 'question' (with `index`) | 'saving' | 'saveFailed' | 'reveal' | 'settings' | 'finished'
 */
export function initialState({ needsPreferences, needsSettings, region = 'VN' }) {
  const stage = needsPreferences ? 'welcome' : needsSettings ? 'settings' : 'finished';
  return { stage, index: 0, draft: {}, region, needsPreferences, needsSettings, skippedAll: false, lastQuestion: QUESTIONS.length - 1 };
}

const afterPreferences = (s) => (s.needsSettings ? 'settings' : 'finished');
const viewed = (i) => ({ type: 'track', name: 'onboarding_question_viewed', props: { question: QUESTIONS[i] } });

/**
 * Applies `action`; returns { state, effects } (effects in order: { type: 'save', payload } | { type: 'track', ... }).
 * Actions that don't apply to the current stage are ignored (double taps, a late callback), so the state never
 * moves backwards past a successful save.
 */
export function reduce(s, action) {
  const a = typeof action === 'string' ? { type: action } : action;
  const same = { state: s, effects: [] };
  switch (s.stage) {
    case 'welcome':
      if (a.type === 'start') return { state: { ...s, stage: 'question', index: 0 }, effects: [{ type: 'track', name: 'onboarding_started' }, viewed(0)] };
      if (a.type === 'skipAll') return { state: { ...s, skippedAll: true, stage: 'saving' }, effects: [{ type: 'save', payload: null }] };
      return same;

    case 'question': {
      const i = s.index;
      const q = QUESTIONS[i];
      if (a.type === 'toggle' && q !== 'budget') return { state: { ...s, draft: { ...s.draft, [a.question]: toggleMulti(s.draft[a.question], a.id) } }, effects: [] };
      if (a.type === 'pickBudget') return { state: { ...s, draft: { ...s.draft, budget: pickBudgetTier(s.draft.budget, a.tier, s.region) } }, effects: [] };
      if (a.type === 'setRegion') return { state: { ...s, region: a.region, draft: { ...s.draft, budget: switchRegion(s.draft.budget, a.region) } }, effects: [] };
      if (a.type === 'next' || a.type === 'skipQuestion') {
        let next = a.type === 'skipQuestion' ? { ...s, draft: clearAnswer(q, s.draft) } : { ...s };
        const n = answerCount(q, next.draft);
        const effects = [n > 0
          ? { type: 'track', name: 'onboarding_question_answered', props: { question: q, answerCount: n } }
          : { type: 'track', name: 'onboarding_question_skipped', props: { question: q } }];
        if (i + 1 < QUESTIONS.length) {
          next = { ...next, index: i + 1 };
          effects.push(viewed(i + 1));
        } else {
          next = { ...next, lastQuestion: i, stage: 'saving' };
          effects.push({ type: 'save', payload: payload(next) });
        }
        return { state: next, effects };
      }
      if (a.type === 'back') {
        return i === 0 ? { state: { ...s, stage: 'welcome' }, effects: [] } : { state: { ...s, index: i - 1 }, effects: [viewed(i - 1)] };
      }
      if (a.type === 'skipAll') return { state: { ...s, skippedAll: true, stage: 'saving' }, effects: [{ type: 'save', payload: null }] };
      return same;
    }

    case 'saving':
      if (a.type === 'saveSucceeded') {
        const p = payload(s);
        return {
          state: { ...s, needsPreferences: false, stage: p == null ? afterPreferences(s) : 'reveal' },
          effects: [{ type: 'track', name: 'onboarding_completed', props: { answeredQuestions: s.skippedAll ? 0 : answeredQuestionCount(s), skippedAll: p == null } }],
        };
      }
      if (a.type === 'saveFailed') return { state: { ...s, stage: 'saveFailed' }, effects: [] };
      return same;

    case 'saveFailed':
      if (a.type === 'retrySave') return { state: { ...s, stage: 'saving' }, effects: [{ type: 'save', payload: payload(s) }] };
      // Edit an answer after a failure; "Skip all" is undone by going back.
      if (a.type === 'back') return { state: { ...s, skippedAll: false, stage: 'question', index: s.lastQuestion }, effects: [viewed(s.lastQuestion)] };
      // Leave for this session only (the server marker stays unset).
      if (a.type === 'skipForNow') return { state: { ...s, stage: afterPreferences(s) }, effects: [] };
      return same;

    case 'reveal':
      if (a.type === 'revealContinue') return { state: { ...s, stage: afterPreferences(s) }, effects: [] };
      return same;

    case 'settings':
      if (a.type === 'settingsDone') return { state: { ...s, needsSettings: false, stage: 'finished' }, effects: [] };
      return same;

    default:
      return same;
  }
}

// MARK: draft persistence (this browser only, per account)

const draftKey = (uid) => `banbe.onboardingDraft.v1.${uid}`;
const defaultStorage = () => (typeof localStorage !== 'undefined' ? localStorage : null);

/**
 * Keeps an unfinished questionnaire across reloads. localStorage only, keyed per account, cleared on completion
 * and sign-out; never synced. Only answers and position are stored.
 */
export const draftStore = {
  save(state, uid, storage = defaultStorage()) {
    if (!uid || !storage) return;
    if (state.stage !== 'question' && state.stage !== 'saveFailed') return; // only an in-progress questionnaire is worth resuming
    try {
      storage.setItem(draftKey(uid), JSON.stringify({ stage: state.stage, index: state.index, lastQuestion: state.lastQuestion, draft: state.draft, region: state.region }));
    } catch { /* storage full or blocked: resuming is a nicety */ }
  },
  load(uid, storage = defaultStorage()) {
    if (!uid || !storage) return null;
    try { const raw = storage.getItem(draftKey(uid)); return raw ? JSON.parse(raw) : null; } catch { return null; }
  },
  clear(uid, storage = defaultStorage()) {
    if (!uid || !storage) return;
    try { storage.removeItem(draftKey(uid)); } catch { /* ignore */ }
  },
  /** Fresh state from the SERVER flags, with a saved draft folded in only while the questions are still owed (the server always wins). */
  resume(uid, { needsPreferences, needsSettings, region }, storage = defaultStorage()) {
    const s = initialState({ needsPreferences, needsSettings, region });
    if (!needsPreferences) return s;
    const saved = this.load(uid, storage);
    if (!saved || typeof saved !== 'object') return s;
    const out = { ...s, draft: saved.draft && typeof saved.draft === 'object' ? saved.draft : {}, region: saved.region === 'US' ? 'US' : 'VN' };
    if (saved.stage === 'question' && Number.isInteger(saved.index) && saved.index >= 0 && saved.index < QUESTIONS.length) return { ...out, stage: 'question', index: saved.index };
    if (saved.stage === 'saveFailed' && Number.isInteger(saved.lastQuestion)) return { ...out, stage: 'question', index: Math.min(Math.max(saved.lastQuestion, 0), QUESTIONS.length - 1) };
    return out;
  },
};

// MARK: live feedback under a question (note 53)

/**
 * One short line that answers each tap ("🎵 🍽️ · only these kinds get the ★"), so picking feels like it does
 * something before the reveal. Says no more than impactLines() will at the end. null when nothing is picked.
 */
export function selectionFeedback(question, picked, vi) {
  const ids = question === 'budget' ? (picked?.tier ? [picked.tier] : []) : (picked || []);
  if (!ids.length) return null;
  if (ids.includes(NO_PREFERENCE)) return vi ? '🤷 · Câu này không lọc gì cả' : '🤷 · Nothing filtered here';
  const faces = ids.map(optionEmoji).join(' ');
  switch (question) {
    case 'interests': return `${faces} · ${vi ? 'chỉ những loại này được gắn ★' : 'only these kinds get the ★'}`;
    case 'goals': return `${faces} · ${vi ? 'sự kiện hợp sẽ được xếp lên trước' : "we'll rank events like this higher"}`;
    case 'availability': return `${faces} · ${vi ? 'giờ khác vẫn hiện, chỉ xếp sau' : 'other times still show, just lower'}`;
    case 'budget': return `${faces} · ${ids[0] === 'flexible' ? (vi ? 'không giới hạn giá' : 'no price limit') : ids[0] === 'free' ? (vi ? 'chỉ sự kiện miễn phí' : 'free events only') : (vi ? 'ẩn sự kiện vượt mức này' : 'hides events above this')}`;
    case 'languages': return `${faces} · ${vi ? 'đã lưu, chưa dùng để lọc' : "saved, doesn't filter yet"}`;
    default: return faces;
  }
}

// MARK: what the answers change (reveal copy, derived from forYou.js's own rules)

/** One line per answered question, stating exactly what the For You matcher does with it — no more, no less. */
export function impactLines(p, vi) {
  const names = (ids, opts) => ids.map(id => prefLabel(id, opts, vi)).join(', ');
  const out = [];
  const interests = declaredInterests(p);
  if (interests.length) out.push({ kind: 'filter', text: vi ? `Chỉ gợi ý: ${names(interests, INTERESTS)}` : `Only suggests: ${names(interests, INTERESTS)}` });
  if (p?.budget) {
    const region = budgetRegionForCurrency(p.budget.currency);
    if (p.budget.tier === 'free') out.push({ kind: 'filter', text: vi ? 'Chỉ sự kiện miễn phí' : 'Free events only' });
    else if (p.budget.tier === 'low' || p.budget.tier === 'medium') {
      const money = formatBudgetMoney(region, budgetCap(region, p.budget.tier));
      out.push({ kind: 'filter', text: vi
        ? `Ẩn sự kiện giá trên ${money} (khi so được cùng loại tiền)`
        : `Hides events over ${money} (when the price is in the same currency)` });
    }
  }
  const goals = declaredGoals(p);
  if (goals.length) out.push({ kind: 'ranking', text: vi ? `Ưu tiên sự kiện hợp với: ${names(goals, GOALS)}` : `Ranks higher what suits: ${names(goals, GOALS)}` });
  const avail = declaredAvailability(p);
  if (avail.length) out.push({ kind: 'ranking', text: vi
    ? `Ưu tiên giờ ${names(avail, AVAILABILITY)}, giờ khác vẫn hiện nhưng xếp sau`
    : `Prefers ${names(avail, AVAILABILITY)}; other times still show, just lower` });
  if ((p?.languages || []).some(l => l !== NO_PREFERENCE)) out.push({ kind: 'savedOnly', text: vi
    ? 'Ngôn ngữ đã lưu. Sự kiện chưa ghi ngôn ngữ nên chưa dùng để lọc.'
    : "Languages saved. Events don't list a language yet, so this doesn't filter." });
  return out;
}

// MARK: reveal matches (the same For You ranking Home uses)

/** Turns a shaped discovery event (BanBeContext's shapeRealEvent) into forYou.js's candidate input. */
export function discoveryCandidate(e) {
  return {
    key: e.key, catKey: e.catKey, priceVnd: e.priceVnd || 0, countryCode: e.countryCode, stateProvince: e.stateProvince,
    startsAt: e.startsAt, status: e.status, soldOut: !!e.soldOut, cancelled: e.status === 'cancelled',
    endedHoursAgo: e.status === 'ended' ? 0 : null, inviteOnly: e.visibility !== 'public',
  };
}

/** { matches (ranked, area-filtered), everywhereCount } — real discoverable events only. */
export function revealMatches(discoveryEvents, prefs, areaMatch, now = Date.now()) {
  const hasPrefs = !!prefs && !prefsIsEmpty(prefs);
  const live = (discoveryEvents || []).filter(e => e.status === 'live' && e.visibility === 'public');
  const everywhere = forYouRankEvents(live.map(discoveryCandidate), prefs, hasPrefs, now);
  const matches = areaMatch ? forYouRankEvents(live.filter(areaMatch).map(discoveryCandidate), prefs, hasPrefs, now) : everywhere;
  return { matches, everywhereCount: everywhere.length };
}

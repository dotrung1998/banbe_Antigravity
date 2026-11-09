// Post-signup personalization flow, onboarding v5 — the pure part. Web twin of iOS `Lib/OnboardingFlow.swift`
// (note 80; prototype docs/prototypes/banbe-onboarding-v5-standalone.html):
// welcome → 3 questions (interests, when, budget) → save → your For You (never empty) → one choice per screen (only
// when the settings step is owed) → recap with the tour offer → Home, or the chaptered tour.
// No React, no network: tests/unit/onboardingFlow.test.mjs.
//
// Server contract unchanged (migration 162, note 34): finishing the questions calls complete_preferences_onboarding(p)
// (null = skipped everything, marker only); the choices end with complete_settings_onboarding. Answers stay owner-only.

import {
  GOALS, INTERESTS, AVAILABILITY, LANGUAGES, NO_PREFERENCE, normalizeForSave, prefsIsEmpty, toggleMulti,
  pickBudgetTier, budgetRegionCurrency, budgetRegionForCurrency, budgetCap, formatBudgetMoney, prefLabel,
  declaredInterests, declaredGoals, declaredAvailability, optionEmoji,
} from './eventPrefs.js';
import { forYouRank, forYouRankEvents, forYouCandidateFromEvent, zonedParts } from './forYou.js';

/** The questions onboarding asks, in order. Goals and languages stay in Account › Event preferences. */
export const QUESTIONS = ['interests', 'availability', 'budget'];

/**
 * One choice per screen. Each writes a real setting; a choice that couldn't take effect right now is never shown.
 * Web has no push permission, so its choices are the weekly digest and Hosting mode.
 */
export const CONSENTS = ['push', 'digest', 'hosting'];
/** The screen before a system prompt offers one action (Apple HIG); banbe's own switches get Continue / Not now. */
export const consentAsksSystem = (kind) => kind === 'push';

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
  return state.skippedAll || prefsIsEmpty(p) ? null : p;
}

export function answeredQuestionCount(state) {
  const p = normalizeForSave(state.draft);
  return QUESTIONS.filter(q => answerCount(q, p) > 0).length;
}

/** The current choice screen's kind, or null. */
export const currentConsent = (s) => (s.stage === 'consent' ? s.consents[s.index] ?? null : null);

/**
 * stage: 'welcome' | 'question' (with `index`) | 'saving' | 'saveFailed' | 'reveal' | 'consent' (with `index`) |
 * 'settingsSaving' | 'settingsFailed' | 'recap' | 'finished'
 */
export function initialState({ needsPreferences, needsSettings, region = 'VN', consents = [] }) {
  const stage = needsPreferences ? 'welcome' : needsSettings ? (consents.length ? 'consent' : 'settingsSaving') : 'finished';
  return {
    stage, index: 0, draft: {}, region, needsPreferences, needsSettings, consents, choices: {},
    skippedAll: false, lastQuestion: QUESTIONS.length - 1, tourRequested: false,
  };
}

const viewed = (i) => ({ type: 'track', name: 'onboarding_question_viewed', props: { question_id: QUESTIONS[i] } });

/** After the questions (and the reveal): the choice screens when the settings step is owed, else the recap. */
function toChoices(s) {
  if (!s.needsSettings) return { state: { ...s, stage: 'recap' }, effects: [] };
  if (!s.consents.length) return { state: { ...s, stage: 'settingsSaving' }, effects: [{ type: 'completeSettings' }] };
  return { state: { ...s, stage: 'consent', index: 0 }, effects: [] };
}

/**
 * Applies `action`; returns { state, effects } (effects in order: { type: 'save', payload } | { type: 'completeSettings' }
 * | { type: 'track', ... }). Actions that don't apply to the current stage are ignored (double taps, a late callback),
 * so the state never moves backwards past a successful save.
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
      if (a.type === 'toggle' && a.question !== 'budget') return { state: { ...s, draft: { ...s.draft, [a.question]: toggleMulti(s.draft[a.question], a.id) } }, effects: [] };
      if (a.type === 'pickBudget') return { state: { ...s, draft: { ...s.draft, budget: pickBudgetTier(s.draft.budget, a.tier, s.region) } }, effects: [] };
      if (a.type === 'setRegion') return { state: { ...s, region: a.region, draft: { ...s.draft, budget: switchRegion(s.draft.budget, a.region) } }, effects: [] };
      if (a.type === 'next' || a.type === 'skipQuestion') {
        let next = a.type === 'skipQuestion' ? { ...s, draft: clearAnswer(q, s.draft) } : { ...s };
        const n = answerCount(q, next.draft);
        const effects = [n > 0
          ? { type: 'track', name: 'onboarding_question_answered', props: { question_id: q, answer_count: n } }
          : { type: 'track', name: 'onboarding_question_skipped', props: { question_id: q } }];
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
        const track = { type: 'track', name: 'onboarding_completed', props: { answered_questions: s.skippedAll ? 0 : answeredQuestionCount(s), skipped_all: p == null } };
        const done = { ...s, needsPreferences: false };
        if (p != null) return { state: { ...done, stage: 'reveal' }, effects: [track] };
        const r = toChoices(done);
        return { state: r.state, effects: [track, ...r.effects] };
      }
      if (a.type === 'saveFailed') return { state: { ...s, stage: 'saveFailed' }, effects: [] };
      return same;

    case 'saveFailed':
      if (a.type === 'retrySave') return { state: { ...s, stage: 'saving' }, effects: [{ type: 'save', payload: payload(s) }] };
      // Edit an answer after a failure; "Skip all" is undone by going back.
      if (a.type === 'back') return { state: { ...s, skippedAll: false, stage: 'question', index: s.lastQuestion }, effects: [viewed(s.lastQuestion)] };
      // Leave for this session only (the server marker stays unset).
      if (a.type === 'skipForNow') return toChoices(s);
      return same;

    case 'reveal':
      if (a.type === 'revealContinue') return toChoices(s);
      // "Change my answers": back to the first question, answers kept.
      if (a.type === 'redoAnswers') return { state: { ...s, skippedAll: false, stage: 'question', index: 0 }, effects: [viewed(0)] };
      return same;

    case 'consent': {
      if (a.type !== 'consentAnswered' || s.consents[s.index] !== a.kind) return same;
      const choices = { ...s.choices, [a.kind]: !!a.on };
      if (s.index + 1 < s.consents.length) return { state: { ...s, choices, index: s.index + 1 }, effects: [] };
      return { state: { ...s, choices, stage: 'settingsSaving' }, effects: [{ type: 'completeSettings' }] };
    }

    case 'settingsSaving':
      if (a.type === 'settingsSucceeded') return { state: { ...s, needsSettings: false, stage: 'recap' }, effects: [] };
      if (a.type === 'settingsFailed') return { state: { ...s, stage: 'settingsFailed' }, effects: [] };
      return same;

    case 'settingsFailed':
      if (a.type === 'retrySettings') return { state: { ...s, stage: 'settingsSaving' }, effects: [{ type: 'completeSettings' }] };
      // After a failed marker: on to the recap for this session only.
      if (a.type === 'skipSettingsForNow') return { state: { ...s, stage: 'recap' }, effects: [] };
      return same;

    case 'recap':
      if (a.type === 'startTour') return { state: { ...s, tourRequested: true, stage: 'finished' }, effects: [] };
      if (a.type === 'skipTour') return { state: { ...s, stage: 'finished' }, effects: [] };
      return same;

    default:
      return same;
  }
}

// MARK: draft persistence (this browser only, per account)

// v2: question indices changed with the 3-question flow, so a 5-question draft is never resumed.
const draftKey = (uid) => `banbe.onboardingDraft.v2.${uid}`;
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
  resume(uid, { needsPreferences, needsSettings, region, consents = [] }, storage = defaultStorage()) {
    const s = initialState({ needsPreferences, needsSettings, region, consents });
    if (!needsPreferences) return s;
    const saved = this.load(uid, storage);
    if (!saved || typeof saved !== 'object') return s;
    const out = { ...s, draft: saved.draft && typeof saved.draft === 'object' ? saved.draft : {}, region: saved.region === 'US' ? 'US' : 'VN' };
    if (saved.stage === 'question' && Number.isInteger(saved.index) && saved.index >= 0 && saved.index < QUESTIONS.length) return { ...out, stage: 'question', index: saved.index };
    if (saved.stage === 'saveFailed' && Number.isInteger(saved.lastQuestion)) return { ...out, stage: 'question', index: Math.min(Math.max(saved.lastQuestion, 0), QUESTIONS.length - 1) };
    return out;
  },
};

// MARK: live counts and the reveal plan (For You is never empty). Twin of iOS `OnboardingCounts`.

export const MIN_FOR_YOU = 3;
export const TILE_MAX = 5;
const knownInterest = (c) => INTERESTS.some(o => o.id === c);

/** forYou.js candidates for the discovery events onboarding counts: live, public, inside the Home area. */
export function onboardingCandidates(discoveryEvents, areaMatch) {
  return (discoveryEvents || [])
    .filter(e => e.status === 'live' && e.visibility === 'public' && (!areaMatch || areaMatch(e)))
    .map(e => forYouCandidateFromEvent(discoveryCandidate(e)));
}

/** Discoverable, not started yet, soonest first (key breaks ties, so the order is total). */
export function upcoming(cands, now = Date.now()) {
  return (cands || []).filter(e => e.isBookable && (e.startsAt == null || e.startsAt >= now))
    .sort((a, b) => {
      const sa = a.startsAt ?? Infinity, sb = b.startsAt ?? Infinity;
      if (sa !== sb) return sa < sb ? -1 : 1;
      return a.key < b.key ? -1 : a.key > b.key ? 1 : 0;
    });
}

/** Upcoming events per interest id (an event with two types counts for both). */
export function typeCounts(cands, now = Date.now()) {
  const out = {};
  for (const e of upcoming(cands, now)) {
    for (const c of new Set(e.categories)) if (knownInterest(c)) out[c] = (out[c] || 0) + 1;
  }
  return out;
}

/** The question's tiles: only types with events on now, most first, at most five (no placeholders). */
export function tileTypes(counts, label = (k) => k) {
  return Object.entries(counts).filter(([, n]) => n > 0)
    .sort(([ka, a], [kb, b]) => (a !== b ? b - a : label(ka).localeCompare(label(kb))))
    .slice(0, TILE_MAX).map(([k]) => k);
}

function fitsInterests(e, interests) {
  if (!interests.length) return true;
  const known = e.categories.filter(knownInterest);
  return !known.length || known.some(c => interests.includes(c));
}

function fitsBudget(e, b) {
  if (!b) return true;
  if (b.tier === 'free') return e.isFree;
  if (e.isFree) return true;
  const region = budgetRegionForCurrency(b.currency);
  const cap = budgetCap(region, b.tier);
  if (cap == null || e.priceAmount == null || e.priceCurrency !== budgetRegionCurrency(region)) return true;
  return e.priceAmount <= cap;
}

/** Day (weekdays/weekends) and time (daytime/evening) are separate groups; each picked group must fit. */
function fitsAvailability(e, ids) {
  const picked = (ids || []).filter(x => x !== NO_PREFERENCE);
  if (!picked.length || e.startsAt == null || !e.timeZone) return true;
  const parts = zonedParts(e.startsAt, e.timeZone);
  if (!parts) return true;
  const isWeekend = parts.weekday === 0 || parts.weekday === 6;
  const isDaytime = parts.hour < 17;
  const days = picked.filter(x => x === 'weekdays' || x === 'weekends');
  const times = picked.filter(x => x === 'daytime' || x === 'evening');
  if (days.length && !days.includes(isWeekend ? 'weekends' : 'weekdays')) return false;
  if (times.length && !times.includes(isDaytime ? 'daytime' : 'evening')) return false;
  return true;
}

/** Upcoming events that fit every answer so far (the same rules as forYouMatch: interests and budget exclude). */
export function matchCount(cands, p, now = Date.now()) {
  const interests = declaredInterests(p);
  return upcoming(cands, now).filter(e => fitsInterests(e, interests) && fitsBudget(e, p?.budget) && fitsAvailability(e, p?.availability)).length;
}

/** The count next to one option: the answers so far with this option as the question's only answer. */
export function optionCount(cands, p, question, option, region, now = Date.now()) {
  const q = { ...(p || {}) };
  if (question === 'availability') q.availability = [option];
  else if (question === 'budget') q.budget = pickBudgetTier(null, option, region);
  else if (question === 'interests') q.interests = [option];
  return matchCount(cands, q, now);
}

/**
 * What the reveal shows: { mode, keys, exact, live, waiting }. Never empty while any upcoming event exists.
 * mode: picked (3+ fit) | topped (fewer: exact first, then more of the same types, then the soonest) |
 *       soon (every picked type has nothing on: the soonest, those types watched) | popular (interests skipped).
 */
export function revealPlan(cands, prefs, now = Date.now()) {
  const up = upcoming(cands, now);
  const counts = typeCounts(up, now);
  const chosen = declaredInterests(prefs);
  const live = chosen.filter(k => (counts[k] || 0) > 0);
  const waiting = chosen.filter(k => !(counts[k] > 0));
  const filled = (first, n) => {
    const keys = [...first];
    for (const e of up) { if (keys.length >= n) break; if (!keys.includes(e.key)) keys.push(e.key); }
    return keys.slice(0, n);
  };
  if (!live.length) {
    const rest = { ...(prefs || {}) };
    delete rest.interests;
    const ranked = forYouRank(up, rest, now).map(m => m.key);
    return { mode: chosen.length ? 'soon' : 'popular', keys: filled(ranked, TILE_MAX), exact: 0, live: [], waiting };
  }
  const exact = forYouRank(up, prefs, now).map(m => m.key);
  if (exact.length >= MIN_FOR_YOU) return { mode: 'picked', keys: exact.slice(0, TILE_MAX), exact: exact.length, live, waiting };
  const same = forYouRank(up, { interests: live }, now).map(m => m.key).filter(k => !exact.includes(k));
  return { mode: 'topped', keys: filled([...exact, ...same], MIN_FOR_YOU + 2), exact: exact.length, live, waiting };
}

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
    key: e.key, catKey: e.catKey, priceVnd: e.priceVnd || 0, currency: e.currency, tz: e.tz, countryCode: e.countryCode, stateProvince: e.stateProvince,
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

// Event type profiles: what changes per kind of event (supper club, music…) in the create flow, Event Detail
// and Home. The data lives in src/data/eventTypeProfiles.json, which iOS bundles as-is; this file is the
// logic on top of it. The first picked category is the PRIMARY type (benchmarks, card line, Home filters). Note 69
// (migration 207): a second pick now shapes the form and the detail page too: `combinedProfile` merges both types'
// fields, required list and facts (shared alcohol / minimum age once). The second key is stored as `details.cat2`.
// iOS twin: apps/ios/BanbeApp/Lib/EventTypes.swift. Shared vectors: tests/fixtures/event-types.json.
// Pure module: no React, no network.
import PROFILES from '../data/eventTypeProfiles.json' with { type: 'json' };
import { DEFAULT_REQUIRED } from './createProgress.js';

export const DETAILS_VERSION = 1;
// `common` (alcohol + minimum age) is merged into every type: its fields, its form block and its required list.
const COMMON = PROFILES.common || { required: [], detailFields: {} };
const withCommon = (t) => ({
  ...t,
  detailFields: { ...(t.detailFields || {}), ...COMMON.detailFields },
  wizard: t.wizard ? { ...t.wizard, required: [...t.wizard.required, ...COMMON.required],
    details: [...(t.wizard.details || []), ...Object.keys(COMMON.detailFields)] } : t.wizard,
});
export const EVENT_TYPES = PROFILES.types.map(withCommon);
/** Every detail field id any type uses (for the create form's field anchors). */
export const DETAIL_FIELD_IDS = [...new Set(EVENT_TYPES.flatMap(t => Object.keys(t.detailFields || {})))];
export const TYPE_KEYS = EVENT_TYPES.map(t => t.key);

const BY_KEY = Object.fromEntries(EVENT_TYPES.map(t => [t.key, t]));

/** The profile for a cat_key; unknown or legacy keys get the generic event (today's behaviour). */
export function profileFor(key) {
  return BY_KEY[key] || { key: key || '', label: null, aliases: [], keywordSeeds: {} };
}

/** True when the type changes the form, the detail page or Home (it has more than an identity). */
export function isShaped(profile) {
  return !!(profile && (profile.wizard || profile.detail || profile.card || profile.home));
}

/** [{ key, vi, en }] in display order, optionally with the leading "All". */
export function categoryDefs({ withAll = false } = {}) {
  const defs = EVENT_TYPES.map(t => ({ key: t.key, vi: t.label.vi, en: t.label.en }));
  return withAll ? [{ key: 'all', vi: 'Tất cả', en: 'All' }, ...defs] : defs;
}

export const CATEGORY_EMOJI = Object.fromEntries(EVENT_TYPES.map(t => [t.key, t.emoji]));

/** Search synonyms per category key (already accent-free, as the matcher folds accents). */
export function searchAliases() {
  return { all: [], ...Object.fromEntries(EVENT_TYPES.map(t => [t.key, t.aliases || []])) };
}

// ---- Two categories + introduction style (note 69, migration 207). Twin of EventTypes.swift. -------------------
/** Keys stored in `events.details` that are not type facts: the second category and the introduction's style. */
export const EXTRA_DETAIL_KEYS = ['cat2', 'intro_font', 'intro_color'];
export const INTRO_FONTS = ['sans', 'serif', 'rounded', 'mono'];
export const INTRO_COLORS = ['ink', 'ink2', 'clay', 'honey', 'alert'];
const COMMON_KEYS = Object.keys(COMMON.detailFields || {});
const uniq = (a) => [...new Set(a)];

/**
 * One profile for one or two picked categories. One key = that type unchanged. Two = the first type's identity (key,
 * card, Home filters, benchmarks) with both types' fields, form blocks, required fields, facts and recipe; the shared
 * fields (alcohol, minimum age) appear once, after both types' own fields.
 */
export function combinedProfile(keys) {
  const p = profileFor(keys?.[0]);
  if (!keys || keys.length < 2 || keys[1] === keys[0]) return p;
  const q = profileFor(keys[1]);
  if (!isShaped(q)) return p;
  const fields = { ...(q.detailFields || {}), ...(p.detailFields || {}) };
  let wizard = p.wizard || q.wizard;
  if (p.wizard && q.wizard) {
    const own = (w) => (w.details || []).filter(f => !COMMON_KEYS.includes(f));
    wizard = {
      ...p.wizard,
      details: uniq([...own(p.wizard), ...own(q.wizard), ...(p.wizard.details || []).filter(f => COMMON_KEYS.includes(f))]),
      required: uniq([...p.wizard.required, ...q.wizard.required]),
    };
  }
  const detail = (p.detail || q.detail)
    ? { ...(p.detail || {}), includedTitle: p.detail?.includedTitle || q.detail?.includedTitle, facts: uniq([...(p.detail?.facts || []), ...(q.detail?.facts || [])]) }
    : undefined;
  const recipe = (p.recipe || q.recipe)
    ? { ...(p.recipe || {}), ingredients: uniq([...(p.recipe?.ingredients || []), ...(q.recipe?.ingredients || [])]) }
    : undefined;
  return { ...p, detailFields: fields, wizard, detail, recipe };
}

/** The second category stored on a published event (`details.cat2`), when it is a known type other than the first. */
export function secondCategory(details, primary) {
  const k = details?.cat2;
  return typeof k === 'string' && k !== primary && BY_KEY[k] ? k : null;
}

/** A published event's profile: its own type plus the second category, if any. */
export function eventProfile(catKey, details) {
  return combinedProfile([catKey, secondCategory(details, catKey)].filter(Boolean));
}

/**
 * Which picked type a field's draft value is kept under: the first type that has it as its OWN field, the first type
 * for shared fields (alcohol, minimum age).
 */
export function detailOwner(field, keys) {
  if (!keys?.length) return null;
  if (COMMON_KEYS.includes(field)) return keys[0];
  return keys.find(k => profileFor(k).detailFields?.[field] !== undefined) || keys[0];
}

/** The create form's draft as one set of values for the picked types (each field read from its owner). */
export function mergedDraft(keys, draft) {
  const out = {};
  for (const id of Object.keys(combinedProfile(keys).detailFields || {})) {
    const k = detailOwner(id, keys);
    const v = draft?.[k]?.[id];
    if (v !== undefined) out[id] = v;
  }
  return out;
}

/** The introduction's stored style; null parts when unset or unknown. */
export function introStyle(details) {
  return {
    font: INTRO_FONTS.includes(details?.intro_font) ? details.intro_font : null,
    color: INTRO_COLORS.includes(details?.intro_color) ? details.intro_color : null,
  };
}

/** What `set_event_details` gets for a create draft: both types' facts cleaned, plus `cat2` and the intro style. */
export function publishDetails({ keys, draft, introFont, introColor }) {
  const out = { ...cleanDetails(combinedProfile(keys), mergedDraft(keys, draft)) };
  delete out.v;
  if (keys?.length > 1 && keys[1] !== keys[0] && BY_KEY[keys[1]]) out.cat2 = keys[1];
  if (INTRO_FONTS.includes(introFont) && introFont !== 'sans') out.intro_font = introFont;
  if (INTRO_COLORS.includes(introColor) && introColor !== 'ink') out.intro_color = introColor;
  return Object.keys(out).length ? { v: DETAILS_VERSION, ...out } : {};
}

/** The fields this type requires before Review. */
export function requiredFields(profile) {
  return profile?.wizard?.required || DEFAULT_REQUIRED;
}

const pick = (pair, lang) => (pair ? (lang === 'vi' ? pair.vi : pair.en) : null);
export const localized = pick;

/**
 * The details a host can publish for this type, cleaned the same way the server validates them
 * (validate_event_details, migration 204): known keys only, known option ids only, text and list items trimmed and
 * capped (a list keeps its order, drops blanks and repeats, at most `max` items).
 * Returns {} when nothing is set, so an untouched form stores nothing.
 */
export function cleanDetails(profile, raw) {
  const fields = profile?.detailFields;
  if (!fields || !raw || typeof raw !== 'object') return {};
  const out = {};
  for (const [id, def] of Object.entries(fields)) {
    const v = raw[id];
    const ids = (def.options || []).map(o => o.id);
    if (def.kind === 'multi' && Array.isArray(v)) {
      const kept = ids.filter(o => v.includes(o));
      if (kept.length) out[id] = kept;
    } else if (def.kind === 'enum' && typeof v === 'string' && ids.includes(v)) {
      out[id] = v;
    } else if (def.kind === 'text' && typeof v === 'string') {
      const t = v.trim().slice(0, def.max || 80);
      if (t) out[id] = t;
    } else if (def.kind === 'list' && Array.isArray(v)) {
      const items = [];
      for (const x of v) {
        const t = typeof x === 'string' ? x.trim().slice(0, def.itemMax || 60) : '';
        if (t && !items.includes(t)) items.push(t);
      }
      if (items.length) out[id] = items.slice(0, def.max || 6);
    }
  }
  return Object.keys(out).length ? { v: DETAILS_VERSION, ...out } : {};
}

/** Draft details that would NOT be published: values kept for other types the host tried earlier. */
export function droppedDetailTypes(primaryKey, draftDetails) {
  return Object.keys(draftDetails || {}).filter(k => k !== primaryKey && Object.keys(cleanDetails(profileFor(k), draftDetails[k])).length > 0);
}

function optionLabel(def, id, lang, short = false) {
  const o = (def.options || []).find(x => x.id === id);
  if (!o) return null;
  return short && o.short ? pick(o.short, lang) : pick(o, lang);
}

/** Required detail fields still empty for this type: { id: true } (the create form's progress reads it). */
export function missingDetails(profile, raw) {
  const clean = cleanDetails(profile, raw);
  const fields = profile?.detailFields || {};
  const out = {};
  for (const id of requiredFields(profile)) if (fields[id]) out[id] = clean[id] == null;
  return out;
}

/**
 * [{ id, label, value, values? }] for Event Detail, in the order the profile lists them; empty values are skipped. A
 * multi choice also carries `values` (one label per choice) so a chip fact can show one chip per choice (note 70).
 */
export function detailFacts(profile, details, lang) {
  const fields = profile?.detailFields || {};
  const out = [];
  for (const id of profile?.detail?.facts || []) {
    const def = fields[id];
    const v = details?.[id];
    if (!def || v == null) continue;
    let value = null, values = null;
    if (def.kind === 'multi' && Array.isArray(v)) {
      values = v.map(x => optionLabel(def, x, lang)).filter(Boolean);
      value = values.join(', ');
    }
    else if (def.kind === 'enum') value = optionLabel(def, v, lang);
    else if (def.kind === 'text') value = String(v);
    else if (def.kind === 'list' && Array.isArray(v)) value = v.join(', ');
    if (value) out.push(values ? { id, label: pick(def.label, lang), value, values } : { id, label: pick(def.label, lang), value });
  }
  return out;
}

/**
 * The short type-aware line under a Home card, or null. `ev` needs { capacity, details }. From the profile's
 * `card`: an optional table size, then each listed field (a choice's short label, a list's count or first item).
 */
export function cardLine(profile, ev, lang) {
  const card = profile?.card;
  if (!card) return null;
  const parts = [];
  const n = Number(ev?.capacity) || 0;
  if (card.capacity === 'table' && n > 0) parts.push(lang === 'vi' ? `Bàn ${n} người` : `Table for ${n}`);
  const d = ev?.details || {};
  for (const id of card.fields || []) {
    const def = profile.detailFields?.[id];
    const v = d[id];
    if (!def || v == null) continue;
    if (def.kind === 'multi' && Array.isArray(v) && v.length) parts.push(optionLabel(def, v[0], lang, true));
    else if (def.kind === 'enum') parts.push(optionLabel(def, v, lang, true));
    else if (def.kind === 'list' && Array.isArray(v) && v.length) {
      parts.push(def.countLabel ? pick(def.countLabel, lang).replace('{n}', String(v.length)) : v[0]);
    }
  }
  const out = parts.filter(Boolean);
  return out.length ? out.join(' · ') : null;
}

/** Words an event's facts add to its search document: option labels in both languages, list items, text. */
export function detailSearchTerms(profile, details) {
  const fields = profile?.detailFields || {};
  const out = [];
  for (const [id, v] of Object.entries(details || {})) {
    const def = fields[id];
    if (!def) continue;
    const ids = Array.isArray(v) ? v : [v];
    if (def.kind === 'multi' || def.kind === 'enum') {
      for (const x of ids) { const o = (def.options || []).find(op => op.id === x); if (o) out.push(o.vi, o.en); }
    } else if (def.kind === 'list' || def.kind === 'text') {
      for (const x of ids) if (typeof x === 'string') out.push(x);
    }
  }
  return out;
}

/** Type-specific Home chips for one selected category. */
export function homeFilters(profile) {
  return profile?.home?.filters || [];
}

const FILTER_BY_ID = Object.fromEntries(EVENT_TYPES.flatMap(t => homeFilters(t)).map(f => [f.id, f]));
/** A Home type chip by id (ids are unique across types), or null. */
export function typeFilterDef(id) {
  return FILTER_BY_ID[id] || null;
}

/** Whether an event's details satisfy one Home chip. */
export function matchesHomeFilter(filter, details) {
  const v = details?.[filter.field];
  if (v == null) return false;
  const wanted = Array.isArray(filter.value) ? filter.value : [filter.value];
  return Array.isArray(v) ? v.some(x => wanted.includes(x)) : wanted.includes(v);
}

/**
 * Keyword ideas for the create form: the type's own seeds, the area, then what other hosts use. Already-typed
 * and dismissed ones are skipped; at most `limit`.
 */
export function keywordSuggestions({ profile, lang, area, benchmark = [], typed = [], dismissed = [], limit = 5 }) {
  const fold = (x) => String(x || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D').toLowerCase().trim();
  const skip = new Set([...typed, ...dismissed].map(fold));
  const out = [];
  const seen = new Set();
  const seeds = profile?.keywordSeeds?.[lang === 'vi' ? 'vi' : 'en'] || [];
  for (const k of [...seeds, area, ...benchmark]) {
    const f = fold(k);
    if (!f || skip.has(f) || seen.has(f)) continue;
    seen.add(f);
    out.push(f);
    if (out.length >= limit) break;
  }
  return out;
}

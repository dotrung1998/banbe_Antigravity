// Event type profiles: what changes per kind of event (supper club, music…) in the create flow, Event Detail
// and Home. The data lives in src/data/eventTypeProfiles.json, which iOS bundles as-is; this file is the
// logic on top of it. The first picked category is the PRIMARY type and the only one that shapes anything;
// a second pick stays a discovery tag (it is saved as a keyword).
// iOS twin: apps/ios/BanbeApp/Lib/EventTypes.swift. Shared vectors: tests/fixtures/event-types.json.
// Pure module: no React, no network.
import PROFILES from '../data/eventTypeProfiles.json' with { type: 'json' };
import { DEFAULT_REQUIRED } from './createProgress.js';

export const DETAILS_VERSION = 1;
export const EVENT_TYPES = PROFILES.types;
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

/** The fields this type requires before Review. */
export function requiredFields(profile) {
  return profile?.wizard?.required || DEFAULT_REQUIRED;
}

const pick = (pair, lang) => (pair ? (lang === 'vi' ? pair.vi : pair.en) : null);
export const localized = pick;

/**
 * The details a host can publish for this type, cleaned the same way the server validates them
 * (validate_event_details, migration 202): known keys only, known option ids only, text trimmed and capped.
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
    }
  }
  return Object.keys(out).length ? { v: DETAILS_VERSION, ...out } : {};
}

/** Draft details that would NOT be published: values kept for other types the host tried earlier. */
export function droppedDetailTypes(primaryKey, draftDetails) {
  return Object.keys(draftDetails || {}).filter(k => k !== primaryKey && Object.keys(cleanDetails(profileFor(k), draftDetails[k])).length > 0);
}

function optionLabel(def, id, lang) {
  const o = (def.options || []).find(x => x.id === id);
  return o ? pick(o, lang) : null;
}

/** [{ id, label, value }] for Event Detail, in the order the profile lists them; empty values are skipped. */
export function detailFacts(profile, details, lang) {
  const fields = profile?.detailFields || {};
  const out = [];
  for (const id of profile?.detail?.facts || []) {
    const def = fields[id];
    const v = details?.[id];
    if (!def || v == null) continue;
    let value = null;
    if (def.kind === 'multi' && Array.isArray(v)) value = v.map(x => optionLabel(def, x, lang)).filter(Boolean).join(', ');
    else if (def.kind === 'enum') value = optionLabel(def, v, lang);
    else if (def.kind === 'text') value = String(v);
    if (value) out.push({ id, label: pick(def.label, lang), value });
  }
  return out;
}

/** The short type-aware line under a Home card, or null. `ev` needs { capacity, details }. */
export function cardLine(profile, ev, lang) {
  if (profile?.card?.line !== 'table_for_n_price') return null;
  const parts = [];
  const n = Number(ev?.capacity) || 0;
  if (n > 0) parts.push(lang === 'vi' ? `Bàn ${n} người` : `Table for ${n}`);
  const d = ev?.details || {};
  const diet = profile.detailFields?.dietary;
  if (Array.isArray(d.dietary) && d.dietary.length && diet) parts.push(optionLabel(diet, d.dietary[0], lang));
  if (d.byo === 'wine' || d.byo === 'any') parts.push('BYO');
  return parts.length ? parts.join(' · ') : null;
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

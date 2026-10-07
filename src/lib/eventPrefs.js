// Event preferences ("For You") + host reservation criteria: shared taxonomy and
// pure helpers. Web port of apps/ios/BanbeApp/Models/EventPreferences.swift.
// Server contract: supabase/migrations/..._162_event_preferences_and_reservation_criteria.sql
// (ids MUST match event_pref_ids()). Rules: .claude/notes/34-onboarding-for-you-criteria.md.
// Pure module: no React, no network.

/** Server sentinel meaning "I have no preference" (stored as ["no_preference"]). */
export const NO_PREFERENCE = 'no_preference';

export const INTERESTS = [
  { id: 'supper', vi: 'Supper club', en: 'Supper club' },
  { id: 'fashion', vi: 'Thời trang', en: 'Fashion' },
  { id: 'gallery', vi: 'Phòng tranh', en: 'Gallery' },
  { id: 'music', vi: 'Nhạc', en: 'Music' },
  { id: 'popup', vi: 'Pop-up', en: 'Pop-up' },
];
export const GOALS = [
  { id: 'meet_people', vi: 'Gặp gỡ mọi người', en: 'Meet people' },
  { id: 'learn', vi: 'Học hỏi', en: 'Learn something' },
  { id: 'experiences', vi: 'Tận hưởng trải nghiệm', en: 'Enjoy experiences' },
  { id: 'networking', vi: 'Kết nối nghề nghiệp', en: 'Professional networking' },
];
export const AVAILABILITY = [
  { id: 'weekdays', vi: 'Ngày thường', en: 'Weekdays' },
  { id: 'weekends', vi: 'Cuối tuần', en: 'Weekends' },
  { id: 'daytime', vi: 'Ban ngày', en: 'Daytime' },
  { id: 'evening', vi: 'Buổi tối', en: 'Evening' },
];
export const LANGUAGES = [
  { id: 'vi', vi: 'Tiếng Việt', en: 'Vietnamese' },
  { id: 'en', vi: 'Tiếng Anh', en: 'English' },
  { id: 'other', vi: 'Ngôn ngữ khác', en: 'Other' },
];
export const BUDGET_TIERS = ['free', 'low', 'medium', 'flexible'];

/** Localized label for an id within an option list (falls back to the id). */
export function prefLabel(id, options, vi) {
  const o = options.find(x => x.id === id);
  return o ? (vi ? o.vi : o.en) : id;
}

// ---- Budget (explicit local-currency ranges) ----
export const BUDGET_REGIONS = ['VN', 'US'];
const REGION = {
  VN: { currency: 'VND', lowMax: 200000, mediumMax: 600000 },
  US: { currency: 'USD', lowMax: 25, mediumMax: 75 },
};

export const budgetRegionCurrency = (region) => (region === 'US' ? 'USD' : 'VND');
export const budgetRegionForCurrency = (currency) => (currency === 'USD' ? 'US' : 'VN');
/** navigator.language region decides the default; the user can switch in the UI. */
export function budgetRegionDefault(locale) {
  let loc = locale;
  if (loc == null && typeof navigator !== 'undefined') loc = navigator.language;
  const m = String(loc || '').match(/[-_]([A-Za-z]{2})\b/);
  return m && m[1].toUpperCase() === 'US' ? 'US' : 'VN';
}
export const budgetLowMax = (region) => REGION[region === 'US' ? 'US' : 'VN'].lowMax;
export const budgetMediumMax = (region) => REGION[region === 'US' ? 'US' : 'VN'].mediumMax;

/** "200.000₫" for VND, "$25" for USD. */
export function formatBudgetMoney(region, n) {
  if (region === 'US') return `$${n}`;
  return `${String(n).replace(/\B(?=(\d{3})+(?!\d))/g, '.')}₫`;
}

/** Explicit label for a tier, e.g. "Low · up to 200.000₫". */
export function budgetTierLabel(region, tier, vi) {
  const low = formatBudgetMoney(region, budgetLowMax(region));
  const med = formatBudgetMoney(region, budgetMediumMax(region));
  switch (tier) {
    case 'free': return vi ? 'Chỉ sự kiện miễn phí' : 'Free events only';
    case 'low': return vi ? `Thấp · đến ${low}` : `Low · up to ${low}`;
    case 'medium': return vi ? `Trung bình · ${low} – ${med}` : `Medium · ${low} – ${med}`;
    case 'flexible': return vi ? 'Linh hoạt · không giới hạn' : 'Flexible · no limit';
    default: return vi ? 'Không ưu tiên' : 'No preference';
  }
}

/** Highest price (whole units) a tier tolerates; null = no cap. */
export function budgetCap(region, tier) {
  switch (tier) {
    case 'free': return 0;
    case 'low': return budgetLowMax(region);
    case 'medium': return budgetMediumMax(region);
    default: return null;
  }
}

// ---- The user's declarations ----
const concrete = (values) => (Array.isArray(values) ? values : []).filter(v => v !== NO_PREFERENCE);
export const declaredInterests = (p) => concrete(p?.interests);
export const declaredGoals = (p) => concrete(p?.goals);
export const declaredAvailability = (p) => concrete(p?.availability);

/** True when nothing was answered at all (all skipped / nothing stored). */
export function prefsIsEmpty(p) {
  return !p || (p.interests == null && p.goals == null && p.availability == null && p.budget == null && p.languages == null);
}

/**
 * Value for the server: empty arrays are omitted (skipped), "no_preference" is
 * exclusive in its array, free/no_preference budgets carry no currency, version 1.
 */
export function normalizeForSave(prefs) {
  const p = prefs || {};
  const fix = (a) => {
    if (!Array.isArray(a) || a.length === 0) return undefined;
    return a.includes(NO_PREFERENCE) ? [NO_PREFERENCE] : [...a];
  };
  const out = { version: 1 };
  const interests = fix(p.interests); if (interests) out.interests = interests;
  const goals = fix(p.goals); if (goals) out.goals = goals;
  const availability = fix(p.availability); if (availability) out.availability = availability;
  if (p.budget && p.budget.tier) {
    const b = { tier: p.budget.tier };
    if (b.tier !== 'free' && b.tier !== NO_PREFERENCE && p.budget.currency) b.currency = p.budget.currency;
    out.budget = b;
  }
  const languages = fix(p.languages); if (languages) out.languages = languages;
  return out;
}

/** Order-insensitive structural equality of two normalized values. */
export function prefsEqual(a, b) {
  return JSON.stringify(normalizeForSave(a)) === JSON.stringify(normalizeForSave(b));
}

/** Toggle one chip in a multi-select answer ("no preference" is exclusive; empty = skipped = undefined). */
export function toggleMulti(current, id) {
  const cur = Array.isArray(current) ? current : [];
  if (id === NO_PREFERENCE) return cur.length === 1 && cur[0] === id ? undefined : [id];
  const arr = cur.filter(v => v !== NO_PREFERENCE);
  const i = arr.indexOf(id);
  if (i >= 0) arr.splice(i, 1); else arr.push(id);
  return arr.length ? arr : undefined;
}

/** Budget single-select: tapping the selected tier clears it. */
export function pickBudgetTier(current, tier, region) {
  if (current?.tier === tier) return undefined;
  const noCurrency = tier === 'free' || tier === NO_PREFERENCE;
  return noCurrency ? { tier } : { tier, currency: budgetRegionCurrency(region) };
}

// ---- Host reservation criteria (eligibility, NOT recommendation) ----
export const everyone = () => ({ version: 1, mode: 'everyone' });
export const criteriaIsEveryone = (c) => !c || c.mode !== 'declared';

/** Groups with no values are dropped; a declared set with no groups collapses to Everyone. */
export function normalizeCriteria(criteria) {
  const c = criteria || everyone();
  if (c.mode !== 'declared') return everyone();
  const group = (g) => (g && Array.isArray(g.values) && g.values.length ? { rule: g.rule === 'all' ? 'all' : 'any', values: [...g.values] } : null);
  const interests = group(c.interests);
  const goals = group(c.goals);
  if (!interests && !goals) return everyone();
  const out = { version: 1, mode: 'declared' };
  if (interests) out.interests = interests;
  if (goals) out.goals = goals;
  return out;
}

/** Plain-language rule, e.g. "Interests: Any of: Music, Gallery  ▪︎  Goals: All of: Learn". */
export function criteriaSummary(criteria, vi) {
  if (criteriaIsEveryone(criteria)) return vi ? 'Mọi người' : 'Everyone';
  const part = (g, opts) => {
    if (!g || !g.values || !g.values.length) return null;
    const names = g.values.map(v => prefLabel(v, opts, vi)).join(', ');
    const head = g.rule === 'all' ? (vi ? 'Tất cả: ' : 'All of: ') : (vi ? 'Một trong: ' : 'Any of: ');
    return head + names;
  };
  const i = part(criteria.interests, INTERESTS);
  const g = part(criteria.goals, GOALS);
  return [i && (vi ? 'Sở thích: ' : 'Interests: ') + i, g && (vi ? 'Mục tiêu: ' : 'Goals: ') + g].filter(Boolean).join('  ▪︎  ');
}

/**
 * Exact guidance lines from a check_my_reservation_eligibility / CRITERIA_NOT_MET
 * payload, e.g. "Interests: Pick at least one: Music, Gallery" / "Goals: Add: Learn".
 */
export function eligibilityGuidance(elig, vi) {
  const line = (missing, rule, opts, kind) => {
    if (!missing || !missing.length) return null;
    const names = missing.map(v => prefLabel(v, opts, vi)).join(', ');
    const head = rule === 'any' ? (vi ? 'Chọn ít nhất một' : 'Pick at least one') : (vi ? 'Thêm' : 'Add');
    return `${kind}: ${head}: ${names}`;
  };
  return [
    line(elig?.missing_interests, elig?.interest_rule, INTERESTS, vi ? 'Sở thích' : 'Interests'),
    line(elig?.missing_goals, elig?.goal_rule, GOALS, vi ? 'Mục tiêu' : 'Goals'),
  ].filter(Boolean);
}

/** A missing-function error (migration not applied) means "feature off", never a blocker. */
export function isMissingFunctionError(error) {
  return !!error && (error.code === 'PGRST202' || error.code === '42883'
    || /could not find the function/i.test(error.message || ''));
}

// Web Dynamic Island (note 101, migration 232, switch `island_toasts`).
//
// What this is: iOS does not let a web page draw inside the physical Dynamic Island. dynaura draws a web-native
// island at the same place and with the same motion: in a Safari tab it sits at the top of the page, and in a Home
// Screen app it sits at the top of the app, just below the system's island. The system island itself is always
// painted on top by iOS; no web API can put content inside it.
//
// This file owns the *display* side only (the person's own preference, per browser): which of the curated themes,
// top or bottom, full or title-only, spring or calm, swipe and haptics. It is deliberately independent of the
// feature switch (`src/lib/featureFlags.js`): the switch says whether the feature exists at all, this says how it
// looks when it does.
//
// Theme values must keep the island readable on its own fill: `foreground` and `muted` are the text, `success` /
// `error` / `warning` / `info` are the state accents, and `button` is every pill's fill. Themed through dynaura's
// own CSS variables (dynaura maps the camelCase keys to `--dynaura-*` itself).
import { flagOn } from './featureFlags.js';

export const ISLAND_PREFS_KEY = 'banbe.island.v1';
export const ISLAND_PREFS_EVENT = 'bb:island-prefs';

const MIDNIGHT_ACCENTS = {
  success: '#30D158', error: '#FF453A', warning: '#FFD60A', info: '#64A8FF', loading: '#A0A0A6', live: '#FF9F0A',
};
const PAPER_ACCENTS = {
  success: '#1F6B3A', error: '#A83226', warning: '#8A5A00', info: '#1D5FA8', loading: '#6B665C', live: '#A65300',
};

export const ISLAND_THEMES = [
  {
    id: 'midnight', vi: 'Đảo đêm', en: 'Midnight', stage: '#09090B',
    theme: {
      background: '#000000', foreground: '#FFFFFF', muted: 'rgba(255,255,255,0.66)',
      ring: 'rgba(255,255,255,0.12)', button: 'rgba(255,255,255,0.14)', ...MIDNIGHT_ACCENTS,
    },
  },
  {
    id: 'paper', vi: 'Giấy ấm', en: 'Warm paper', stage: '#EFEBE0',
    theme: {
      background: '#FBF8F1', foreground: '#1B1916', muted: 'rgba(27,25,22,0.64)',
      ring: 'rgba(27,25,22,0.13)', button: 'rgba(27,25,22,0.07)', ...PAPER_ACCENTS,
    },
  },
  {
    id: 'glass', vi: 'Sương mờ', en: 'Frosted', stage: '#242A31', glass: true,
    theme: {
      background: 'rgba(12,14,18,0.72)', foreground: '#FFFFFF', muted: 'rgba(255,255,255,0.82)',
      ring: 'rgba(255,255,255,0.22)', button: 'rgba(255,255,255,0.16)', ...MIDNIGHT_ACCENTS,
    },
  },
  {
    id: 'clay', vi: 'Đất nung', en: 'Clay', stage: '#2B1C15',
    theme: {
      background: '#2B1C15', foreground: '#FFF1E4', muted: 'rgba(255,241,228,0.66)',
      ring: 'rgba(255,241,228,0.16)', button: 'rgba(255,241,228,0.12)',
      success: '#B7D48A', error: '#FF8A73', warning: '#FFC46B', info: '#8FC7E8', loading: '#B9A79A', live: '#FFB37A',
    },
  },
  {
    id: 'moss', vi: 'Rêu sâu', en: 'Deep moss', stage: '#14231B',
    theme: {
      background: '#14231B', foreground: '#ECF5EE', muted: 'rgba(236,245,238,0.64)',
      ring: 'rgba(236,245,238,0.16)', button: 'rgba(236,245,238,0.12)',
      success: '#98D6A6', error: '#FF8B7A', warning: '#F3C969', info: '#9BC8E8', loading: '#9FAFA4', live: '#C6E08A',
    },
  },
  {
    id: 'plum', vi: 'Mận chín', en: 'Plum', stage: '#24152B',
    theme: {
      background: '#24152B', foreground: '#F8EFFB', muted: 'rgba(248,239,251,0.64)',
      ring: 'rgba(248,239,251,0.16)', button: 'rgba(248,239,251,0.12)',
      success: '#B5E3A8', error: '#FF93A8', warning: '#FFD07A', info: '#B6B4FF', loading: '#B9A6C0', live: '#F0A0D0',
    },
  },
  {
    id: 'signal', vi: 'Tương phản', en: 'High contrast', stage: '#000000',
    theme: {
      background: '#000000', foreground: '#FFFFFF', muted: '#D8D8D8',
      ring: '#FFFFFF', button: '#2B2B2B',
      success: '#7CFF6B', error: '#FF6259', warning: '#FFE45C', info: '#7AC8FF', loading: '#FFFFFF', live: '#FFB000',
    },
  },
  {
    id: 'mono', vi: 'Một màu', en: 'Mono', stage: '#1B1916',
    theme: {
      background: '#1B1916', foreground: '#F5F1E6', muted: 'rgba(245,241,230,0.62)',
      ring: 'rgba(245,241,230,0.18)', button: 'rgba(245,241,230,0.12)',
      success: '#F5F1E6', error: '#F5F1E6', warning: '#F5F1E6', info: '#F5F1E6', loading: '#B8B2A5', live: '#F5F1E6',
    },
  },
];

export const ISLAND_THEME_IDS = ISLAND_THEMES.map(t => t.id);

export const DEFAULT_ISLAND_PREFS = Object.freeze({
  theme: 'midnight', position: 'top', detail: 'full', motion: 'spring', swipe: true, haptics: true,
});

const bool = (v, fallback) => (typeof v === 'boolean' ? v : fallback);

/** Missing or unknown values fall back to the default; extra keys from a newer build are dropped. */
export function normalizeIslandPrefs(raw) {
  const r = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
  return {
    theme: ISLAND_THEME_IDS.includes(r.theme) ? r.theme : DEFAULT_ISLAND_PREFS.theme,
    position: r.position === 'bottom' ? 'bottom' : 'top',
    detail: r.detail === 'title' ? 'title' : 'full',
    motion: r.motion === 'calm' ? 'calm' : 'spring',
    swipe: bool(r.swipe, DEFAULT_ISLAND_PREFS.swipe),
    haptics: bool(r.haptics, DEFAULT_ISLAND_PREFS.haptics),
  };
}

let cached = null;

export function readIslandPrefs() {
  if (cached) return cached;
  let raw = null;
  try { raw = JSON.parse(localStorage.getItem(ISLAND_PREFS_KEY) || 'null'); } catch { /* private mode */ }
  cached = normalizeIslandPrefs(raw);
  return cached;
}

/** Merge + save + tell every listener on this page (IslandHost re-themes without a reload). */
export function writeIslandPrefs(patch) {
  cached = normalizeIslandPrefs({ ...readIslandPrefs(), ...(patch || {}) });
  try { localStorage.setItem(ISLAND_PREFS_KEY, JSON.stringify(cached)); } catch { /* private mode: this visit only */ }
  if (typeof window !== 'undefined') window.dispatchEvent(new Event(ISLAND_PREFS_EVENT));
  return cached;
}

export function subscribeIslandPrefs(listener) {
  if (typeof window === 'undefined') return () => {};
  const local = () => listener();
  const storage = (e) => { if (e.key === ISLAND_PREFS_KEY) { cached = null; listener(); } };
  window.addEventListener(ISLAND_PREFS_EVENT, local);
  window.addEventListener('storage', storage);
  return () => {
    window.removeEventListener(ISLAND_PREFS_EVENT, local);
    window.removeEventListener('storage', storage);
  };
}

export function islandTheme(id) {
  return ISLAND_THEMES.find(t => t.id === id) || ISLAND_THEMES[0];
}

/** The same theme as inline `--dynaura-*` variables, for one demo toast that previews a theme other than the saved one. */
export function islandThemeVars(id) {
  const t = islandTheme(id).theme;
  return {
    '--dynaura-bg': t.background,
    '--dynaura-fg': t.foreground,
    '--dynaura-muted': t.muted,
    '--dynaura-ring': t.ring,
    '--dynaura-btn': t.button,
    '--dynaura-success': t.success,
    '--dynaura-error': t.error,
    '--dynaura-warning': t.warning,
    '--dynaura-info': t.info,
    '--dynaura-loading': t.loading,
    '--dynaura-live': t.live,
  };
}

/** The one gate every surface uses: the admin switch is on. Missing switch = off (OFF_UNLESS_SET). */
export function islandEnabled(flags) {
  return flagOn(flags || {}, 'island_toasts');
}

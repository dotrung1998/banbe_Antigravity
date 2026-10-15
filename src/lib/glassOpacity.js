// Liquid Glass opacity (iOS: AppState.glassOpacity, Preferences slider, default 0.82). Stored per browser and
// exposed as the CSS variable --bb-glass (0..1) so every glass surface follows it with no React re-render.
const KEY = 'banbe.glassOpacity';
export const DEFAULT_GLASS = 0.82;

export function getGlassOpacity() {
  try {
    const v = parseFloat(localStorage.getItem(KEY));
    if (Number.isFinite(v)) return Math.min(1, Math.max(0, v));
  } catch { /* storage unavailable */ }
  return DEFAULT_GLASS;
}

export function setGlassOpacity(v) {
  const value = Math.min(1, Math.max(0, v));
  document.documentElement.style.setProperty('--bb-glass', String(value));
  try { localStorage.setItem(KEY, String(value)); } catch { /* ignore */ }
  return value;
}

export function applyGlassOpacity() {
  if (typeof document !== 'undefined') document.documentElement.style.setProperty('--bb-glass', String(getGlassOpacity()));
}

// The inactive (non-selected) glass capsule, same maths as iOS homeGlassCapsule: ink fill alpha
// (0.04 + 0.20*g) with the whole layer at opacity g, hairline at 0.7*g. Active capsules ignore it.
const G = 'var(--bb-glass, 0.82)';
export const glassCapsuleInactive = {
  background: `linear-gradient(180deg, rgba(255,255,255,calc(0.35 * ${G})), rgba(255,255,255,calc(0.05 * ${G}))), rgba(var(--bb-fg-rgb), calc((0.04 + 0.2 * ${G}) * ${G}))`,
  backdropFilter: 'blur(14px) saturate(1.1)', WebkitBackdropFilter: 'blur(14px) saturate(1.1)',
  border: `1px solid rgba(var(--bb-fg-rgb), calc(0.17 * ${G}))`,
  boxShadow: `0 2px 8px rgba(27,25,22,calc(0.1 * ${G})), inset 0 1px 0 rgba(255,255,255,calc(0.6 * ${G}))`,
};

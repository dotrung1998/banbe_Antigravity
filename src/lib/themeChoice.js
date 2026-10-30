// Theme choice vs. the theme actually shown (note 66). The choice is 'light', 'dark' or 'system'; 'system' follows the
// device (prefers-color-scheme). New installs start on 'system'; a saved light/dark choice is kept as it was.
// Mirrors apps/ios/BanbeApp/Lib/ThemeChoice.swift.
export const THEME_CHOICES = ['system', 'light', 'dark'];

/** Normalises a stored value. `fresh` = nothing saved yet on this device (new install) → 'system'. */
export function normalizeThemeChoice(value, fresh = false) {
  if (value === 'dark' || value === 'light' || value === 'system') return value;
  return fresh ? 'system' : 'light';
}

/** The theme to render: 'light' or 'dark'. */
export function resolveTheme(choice, systemDark) {
  if (choice === 'system') return systemDark ? 'dark' : 'light';
  return choice === 'dark' ? 'dark' : 'light';
}

export function systemPrefersDark() {
  try { return typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-color-scheme: dark)').matches; } catch { return false; }
}

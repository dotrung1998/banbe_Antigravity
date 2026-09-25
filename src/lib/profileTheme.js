// TASK D (2026-10-01 UX foundation pass) — the shared profile palette
// definition, used by EditProfile.jsx (picker), Account.jsx (own card wash)
// and PublicProfile.jsx (shared card wash) so all three always agree on
// what each `profile_theme` key actually looks like.
export const PROFILE_PALETTES = [
  { key: 'default', vi: 'Mặc định', en: 'Default', color: '#EDE7D9' },
  { key: 'rose', vi: 'Hồng đất', en: 'Rose', color: '#E7C9C2' },
  { key: 'moss', vi: 'Rêu', en: 'Moss', color: '#C8CBB2' },
  { key: 'ink', vi: 'Mực', en: 'Ink', color: '#3A3630' },
  { key: 'sand', vi: 'Cát', en: 'Sand', color: '#E3D3B4' },
];

export const PROFILE_PALETTE_COLORS = Object.fromEntries(PROFILE_PALETTES.map(p => [p.key, p.color]));

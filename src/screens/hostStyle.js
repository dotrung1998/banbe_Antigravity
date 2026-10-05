// Flat iOS-style surfaces for the host/admin screens: apps/ios BanbeApp's
// `app.palette.field` fill in a continuous rounded rect (no glass gradient,
// no blur) and the solid ink `InkButton` (15pt semibold, 18pt radius).
// Drop-in replacements for theme.js's fieldGlass/cardGlass/inkButton.
export const fieldGlass = (extra) => ({ background: 'var(--bb-field)', borderRadius: 14, ...extra });
export const cardGlass = fieldGlass;
export const inkButton = (extra) => ({
  background: 'var(--bb-fg)', color: 'var(--bb-bg)', borderRadius: 18,
  fontSize: 15, fontWeight: 600, textAlign: 'center', cursor: 'pointer', padding: '15px 0', ...extra,
});
// A field nested inside a field-filled card: paper fill so it stays visible.
export const insetField = (extra) => ({ background: 'var(--bb-bg)', borderRadius: 12, ...extra });

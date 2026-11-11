// Browser chrome colour (iPhone status bar / Dynamic Island tint in Safari, standalone PWA status area).
// The whole app uses the dark "night" colour (same as the Home hero) so the area above the content never shows a pale
// band: in a Safari tab the system tints the top bar with it, and in a standalone app `body::before` in index.css paints
// the safe-area strip with the same colour. The `dark` argument is kept so existing callers keep working.
const NIGHT = '#16140f';
function meta() {
  if (typeof document === 'undefined') return null;
  let m = document.querySelector('meta[name="theme-color"]:not([media])');
  if (!m) { m = document.createElement('meta'); m.setAttribute('name', 'theme-color'); document.head.appendChild(m); }
  return m;
}
export function paperColor() { return NIGHT; }
export function setThemeColor() {
  const m = meta();
  if (m) m.setAttribute('content', NIGHT);
}

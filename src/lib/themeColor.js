// Browser chrome colour (iPhone status bar / Dynamic Island tint in Safari, standalone PWA status area).
// Home's dark photo hero sets the night colour while it is at the top; everything else falls back to the page paper
// colour (light/dark aware via --bb-bg), so the strip above the content never shows a mismatched band.
const NIGHT = '#16140f';
function meta() {
  if (typeof document === 'undefined') return null;
  let m = document.querySelector('meta[name="theme-color"]:not([media])');
  if (!m) { m = document.createElement('meta'); m.setAttribute('name', 'theme-color'); document.head.appendChild(m); }
  return m;
}
export function paperColor() {
  try {
    const v = getComputedStyle(document.documentElement).getPropertyValue('--bb-bg').trim();
    const stage = document.querySelector('.bb-stage [data-bb-theme], .bb-stage');
    const sv = stage ? getComputedStyle(stage).getPropertyValue('--bb-bg').trim() : '';
    return sv || v || '#F7F4EC';
  } catch { return '#F7F4EC'; }
}
export function setThemeColor(dark) {
  const m = meta();
  if (m) m.setAttribute('content', dark ? NIGHT : paperColor());
}

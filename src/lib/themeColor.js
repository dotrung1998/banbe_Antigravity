// Browser chrome colour (iPhone status bar / Dynamic Island tint in Safari, standalone PWA status area, the strip
// `body::before` paints in index.css).
//
// iOS style (note 90): the band above the page takes the colour of the screen's OWN top edge, like a transparent iOS
// status bar, instead of one fixed black strip. An ordinary paper screen shows the paper — cream in light, near-black
// in dark — and only a full-bleed screen whose top edge is the night hero or a photo (Home's hero, Event Detail, Map)
// keeps the night colour. One value drives the strip, the body behind it and `theme-color`, so they can never disagree.
const NIGHT = '#16140f';
const PAPER_LIGHT = '#f7f4ec';
const PAPER_DARK = '#0f0e0b';

function meta() {
  if (typeof document === 'undefined') return null;
  let m = document.querySelector('meta[name="theme-color"]:not([media])');
  if (!m) { m = document.createElement('meta'); m.setAttribute('name', 'theme-color'); document.head.appendChild(m); }
  return m;
}

function currentTheme() {
  if (typeof document === 'undefined') return 'light';
  return document.querySelector('[data-bb-theme]')?.getAttribute('data-bb-theme') || 'light';
}

/** The paper of a theme: what an ordinary screen's top edge is. */
export function paperColor(theme = currentTheme()) { return theme === 'dark' ? PAPER_DARK : PAPER_LIGHT; }

/** The band's colour: night only over a full-bleed dark edge, the theme's paper everywhere else. */
export function bandColor(dark = false, theme = currentTheme()) { return dark ? NIGHT : paperColor(theme); }

/**
 * Paint the top band. `dark` = this screen's top edge is the night hero / a photo; leave it out for paper.
 * Writes `--bb-band` (body::before and body) and the `theme-color` meta in one place.
 */
export function setThemeColor(dark = false) {
  const color = bandColor(dark);
  const m = meta();
  if (m) m.setAttribute('content', color);
  if (typeof document !== 'undefined') document.documentElement.style.setProperty('--bb-band', color);
  return color;
}

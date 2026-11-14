// The app's typeface (note 83), chosen at Account › Personal › Settings › "Font & more display" (the Font section of
// Language & Appearance), stored per browser and applied as `<html data-bb-font>` + CSS variables before the first
// render, so no component needs a fork. Two options (owner, 2026-11-14), each ONE typeface for the whole app:
//   vietnam  Be Vietnam Pro for titles, accents and text (the default)
//   serif    the serif of the v2.3 cards (Iowan Old Style / Palatino / Georgia, system faces) for titles, accents
//            and text
// Readers: body text and theme.js FACE read --bb-face; theme.js DISPLAY_FACE / display() read --bb-font-display and
// --bb-font-display-weight; the v2.3 SERIF reads --bb-font-accent; the Home hero-card titles read --bb-font-title.
// An older stored 'current' (Jost titles) reads as the default now.
export const FONT_KEY = 'banbe.font.v1';
export const FONT_CHOICES = ['serif', 'vietnam'];
export const DEFAULT_FONT = 'vietnam';
const SERIF_STACK = "'Iowan Old Style', 'Palatino Linotype', Palatino, Georgia, 'Times New Roman', serif";
const VIETNAM_STACK = "'Be Vietnam Pro', system-ui, sans-serif";
export const FONT_SAMPLE = { serif: SERIF_STACK, vietnam: VIETNAM_STACK };

const vars = (stack, weight) => `--bb-face: ${stack}; --bb-font-display: ${stack}; --bb-font-display-weight: ${weight}; --bb-font-accent: ${stack}; --bb-font-title: ${stack};`;
const CSS = `
:root { ${vars(VIETNAM_STACK, 600)} }
:root[data-bb-font="serif"] { ${vars(SERIF_STACK, 400)} }
`;

export function getFont() {
  try { const v = localStorage.getItem(FONT_KEY); return FONT_CHOICES.includes(v) ? v : DEFAULT_FONT; } catch { return DEFAULT_FONT; }
}

function ensureCss() {
  if (typeof document === 'undefined' || document.getElementById('bb-font-css')) return;
  const st = document.createElement('style');
  st.id = 'bb-font-css';
  st.textContent = CSS;
  document.head.appendChild(st);
}

export function setFont(v) {
  const value = FONT_CHOICES.includes(v) ? v : DEFAULT_FONT;
  ensureCss();
  if (typeof document !== 'undefined') document.documentElement.setAttribute('data-bb-font', value);
  try { localStorage.setItem(FONT_KEY, value); } catch { /* private mode: this visit only */ }
  return value;
}

export function applyFont() {
  ensureCss();
  if (typeof document !== 'undefined') document.documentElement.setAttribute('data-bb-font', getFont());
}

// The app's typeface (note 83), chosen in Account › App Preferences › Font, stored per browser and applied as
// `<html data-bb-font>` + CSS variables before the first render, so no component needs a fork:
//   current  Jost for titles, Be Vietnam Pro for text, the serif for v2.3 accents (today's look, the default)
//   serif    the serif of the v2.3 cards (Iowan Old Style / Palatino / Georgia) for every title and accent,
//            Be Vietnam Pro for text (exactly the end-of-list card's pairing)
//   vietnam  Be Vietnam Pro for everything (titles, accents and text)
// Big light photo-card titles (Home hero rail) read --bb-font-title (unset = the body face). theme.js `DISPLAY_FACE` reads --bb-font-display (+ display() reads --bb-font-display-weight); the v2.3 SERIF reads
// --bb-font-accent; body text stays Be Vietnam Pro in every option (full Vietnamese diacritics at every size).
export const FONT_KEY = 'banbe.font.v1';
export const FONT_CHOICES = ['current', 'serif', 'vietnam'];
const SERIF_STACK = "'Iowan Old Style', 'Palatino Linotype', Palatino, Georgia, 'Times New Roman', serif";
const VIETNAM_STACK = "'Be Vietnam Pro', system-ui, sans-serif";
export const FONT_SAMPLE = {
  current: "'Jost', 'Be Vietnam Pro', system-ui, sans-serif",
  serif: SERIF_STACK,
  vietnam: VIETNAM_STACK,
};

const CSS = `
:root { --bb-font-display: 'Jost', 'Be Vietnam Pro', system-ui, sans-serif; --bb-font-display-weight: 600; --bb-font-accent: ${SERIF_STACK}; }
:root[data-bb-font="serif"] { --bb-font-display: ${SERIF_STACK}; --bb-font-display-weight: 400; --bb-font-accent: ${SERIF_STACK}; --bb-font-title: ${SERIF_STACK}; }
:root[data-bb-font="vietnam"] { --bb-font-display: ${VIETNAM_STACK}; --bb-font-display-weight: 600; --bb-font-accent: ${VIETNAM_STACK}; }
`;

export function getFont() {
  try { const v = localStorage.getItem(FONT_KEY); return FONT_CHOICES.includes(v) ? v : 'current'; } catch { return 'current'; }
}

function ensureCss() {
  if (typeof document === 'undefined' || document.getElementById('bb-font-css')) return;
  const st = document.createElement('style');
  st.id = 'bb-font-css';
  st.textContent = CSS;
  document.head.appendChild(st);
}

export function setFont(v) {
  const value = FONT_CHOICES.includes(v) ? v : 'current';
  ensureCss();
  if (typeof document !== 'undefined') document.documentElement.setAttribute('data-bb-font', value);
  try { localStorage.setItem(FONT_KEY, value); } catch { /* private mode: this visit only */ }
  return value;
}

export function applyFont() {
  ensureCss();
  if (typeof document !== 'undefined') document.documentElement.setAttribute('data-bb-font', getFont());
}

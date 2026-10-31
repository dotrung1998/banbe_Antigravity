// Note 69 (migration 207): the event introduction's whole-text look. One of four fonts and one of five theme colours,
// so it reads in light and dark mode. Stored as details.intro_font / intro_color; "sans" + "ink" are the defaults and
// are not stored. iOS twin: IntroStyle in apps/ios/BanbeApp/Views/FormControls.swift.
import { ink, ink2, clay, honey, alert } from '../theme.js';

const FONTS = {
  serif: 'ui-serif, "New York", Georgia, "Times New Roman", serif',
  rounded: 'ui-rounded, "SF Pro Rounded", "Nunito", system-ui, sans-serif',
  mono: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
};
const COLORS = { ink, ink2, clay, honey, alert };

/** CSS font-family for a stored key; undefined (inherit) for the default. */
export const introFontFamily = (key) => FONTS[key];
/** CSS colour (a theme variable) for a stored key; ink for the default. */
export const introColorValue = (key) => COLORS[key] || ink;

export const INTRO_FONT_NAMES = {
  sans: ['Mặc định', 'Default'], serif: ['Có chân', 'Serif'], rounded: ['Tròn', 'Rounded'], mono: ['Đơn cách', 'Mono'],
};
export const INTRO_COLOR_NAMES = {
  ink: ['Mặc định', 'Default'], ink2: ['Xám', 'Grey'], clay: ['Đất nung', 'Clay'], honey: ['Mật ong', 'Honey'], alert: ['Đỏ', 'Red'],
};

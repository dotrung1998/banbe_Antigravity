# 83 · App font choice (web)

Status (2026-11-14): IMPLEMENTED (web), committed and pushed to main. No migration (a per-browser setting, like the map
surface).

- Where: **Account › Personal tab › Settings group › "Font & more display"** (row under Appearance, its sub-line names
  the current font; it opens the Language & Appearance screen, Font is the section under Appearance). Found 2026-11-14:
  that screen had NO entry in Account (the old "Settings" row was defined but never rendered, and the search button
  was gone), so the row was added and the Account **search button** is back in the header (magnifier beside Share,
  × closes and clears); searching "font" / "phông chữ" / "serif" finds a Font entry (`AccountSearch.jsx`).
- **Revised 2026-11-14 (owner): two options, each ONE typeface for the whole app** (titles, accents AND text):
  - **Serif**: the serif of the v2.3 cards (Iowan Old Style / Palatino / Georgia, system faces, no download), titles
    at weight 400.
  - **Be Vietnam Pro** (the default): Be Vietnam Pro everywhere. The old "Current" (Jost titles) is gone; a stored
    'current' reads as Be Vietnam Pro.
- `src/lib/fontPref.js`: `getFont` / `setFont` / `applyFont` (localStorage `banbe.font.v1`), applied in `main.jsx`
  before the first render as `<html data-bb-font>` + CSS variables `--bb-face` (body text, theme.js `FACE`, index.css),
  `--bb-font-display` + `--bb-font-display-weight` (theme.js `DISPLAY_FACE` / `display()`), `--bb-font-accent` (v2.3
  `SERIF`), `--bb-font-title` (Home hero-card titles). 18 screens/components that hard-coded 'Be Vietnam Pro' for
  inputs and labels now read `var(--bb-face, 'Be Vietnam Pro')`; canvas and PDF drawings (share card, reports, ticket
  PDF, dispute export) keep their own font strings.
- `index.html` loads Be Vietnam Pro 300–800 + italic 400 (the Google Fonts embed).
- Test: `tests/public/browse-v23.spec.js` "font choice" (attribute, title face and body face for Serif, Be Vietnam Pro and an old stored "current").
- Not done: the setting is per browser (not synced to the account), and iOS has no font choice.

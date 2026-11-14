# 83 · App font choice (web)

Status (2026-11-14): IMPLEMENTED (web), committed and pushed to main. No migration (a per-browser setting, like the map
surface).

- Where: **Account › Personal tab › Settings group › "Font & more display"** (row under Appearance, its sub-line names
  the current font; it opens the Language & Appearance screen, Font is the section under Appearance). Found 2026-11-14:
  that screen had NO entry in Account (the old "Settings" row was defined but never rendered, and the search button
  was gone), so the row was added and the Account **search button** is back in the header (magnifier beside Share,
  × closes and clears); searching "font" / "phông chữ" / "serif" finds a Font entry (`AccountSearch.jsx`).
- The **Font** section, three rows, each previewed in its own face (`Preferences.jsx`):
  - **Current** (default): Jost for titles, Be Vietnam Pro for text, the serif for the v2.3 accents.
  - **Serif**: the serif of the v2.3 end-of-list card (Iowan Old Style / Palatino / Georgia, system faces, no download)
    for every title and accent at weight 400, Be Vietnam Pro for text (the end card's own pairing).
  - **Be Vietnam Pro**: one face for titles, accents and text.
- `src/lib/fontPref.js`: `getFont` / `setFont` / `applyFont` (localStorage `banbe.font.v1`), applied in `main.jsx` before
  the first render as `<html data-bb-font>` + CSS variables: `--bb-font-display`, `--bb-font-display-weight`,
  `--bb-font-accent`, `--bb-font-title`.
- Wiring, no per-component forks: `theme.js` `DISPLAY_FACE` = `var(--bb-font-display, 'Jost', …)` and `display()` weight
  = `var(--bb-font-display-weight, 600)`; the v2.3 `SERIF` (`v23Style.js`) = `var(--bb-font-accent, serif…)`; the Home
  hero-rail card titles (body face, weight 300) read `--bb-font-title` (serif in Serif mode).
- Body text stays Be Vietnam Pro in every option (full Vietnamese diacritics). `index.html` now loads Be Vietnam Pro
  300–800 + italic 400 (the Google Fonts embed). Canvas drawings (share card, reports) keep their own font strings.
- Test: `tests/public/browse-v23.spec.js` "font choice" (attribute + computed title face for all three).
- Not done: the setting is per browser (not synced to the account), and iOS has no font choice.

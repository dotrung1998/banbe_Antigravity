# 90 — Modern Web Guidance pass over the web app

**Date:** 2026-11-17 · **Scope:** browser-facing code only (`index.html`, `src/index.css`, `src/**`, `public/sw.js`,
`package.json`). Not touched: `api/` (Vercel functions), `apps/ios`, `docs/prototypes`, design tokens or any visual
redesign.

## What Modern Web Guidance is, and where it lives

Chrome/Edge/Firefox/MDN "Modern Web Guidance" — a set of agent skills that ship vetted, Baseline-aware guidance for
web platform features. Installed with:

```bash
npx modern-web-guidance@latest install --agent claude-code -y   # non-interactive; needs the agent slug
```

It installed `modern-web-guidance` into `.claude/skills/modern-web-guidance/` (project-local, versioned) and updated
`skills-lock.json`. The CLI is the usable part day to day:

```bash
npx modern-web-guidance@latest legacy-scan src --json   # deterministic legacy-pattern scan
npx modern-web-guidance@latest search "<what you want>"
npx modern-web-guidance@latest retrieve <guide-id>
```

The scanner is a pre-screen, not a fixer: every hit carries a `keepWhen`/`dropWhen` rubric, and the agent has to check
the surrounding code before changing anything. `legacy-scan` covers roughly 20% of the guides (the ones that can be
matched deterministically); the rest are retrieved per use case.

## Baseline target (pinned in CLAUDE.md)

**Baseline Widely available**, with the app's own stricter floor: **Safari 16.2 / iOS 16.2**, the oldest engine the web
app already requires (`color-mix()`). So a feature that is "Baseline Widely available" but needs Safari 17.4+ (or is
Chrome/Firefox only) is NOT adopted on the label alone — it needs a real fallback or it waits. This rule is what
decided most of the "deliberately not applied" list below.

## Scan results

`legacy-scan src` found **31** items. All were checked against their rubric:

| Guide | Found | Applied | Kept / dropped |
| --- | --- | --- | --- |
| `ime-safe-enter-submit` | 10 | 10 | See "IME" below |
| `js` — `toSorted` | 12 | 12 | All receivers were plain arrays |
| `js` — `findLast` | 2 | 2 | `WEEK_MILESTONES` is ascending; badges are sorted ascending |
| `js` — `structuredClone` | 1 | 1 | MapLibre style is plain JSON |
| `js` — `Promise.withResolvers` | 1 | **0** | Safari 17.4+ (see below) |
| `switch` (`<input switch>`) | 3 | **0** | Safari-only, see below |

`legacy-scan` on `index.html`, `index.css`, `public/sw.js` and `package.json` returned 0 findings; those parts were
covered from the targeted guides instead.

## Applied

### A — platform wins, no intended visual change

- **Fonts:** `index.html` loaded Be Vietnam Pro **and** Jost as a render-blocking third-party stylesheet. Jost stopped
  being a title face in note 83 (`fontPref.js` writes `--bb-font-display` before first render), so the family is gone;
  `&subset=vietnamese` also went (not a CSS2-API parameter — the API serves unicode-range subsets itself).
  *Not done:* preloading a specific woff2. Google serves several per-unicode-range files whose URLs are not stable
  enough to hand-write, and preloading the wrong one is worse than the current `preconnect`. A future self-hosted
  font pipeline is the clean way to get that.
- **Viewport:** the 3 `100vh` sites (`body`, `#root`, the desktop phone frame) use `100dvh` with the `100vh` line kept
  as the fallback. On a phone with browser chrome or a keyboard up, `100vh` is the tallest height, not the current one.
- **Typography:** `h1–h3 { text-wrap: balance }`, `p { text-wrap: pretty }`. Unsupported values fall back to normal
  wrapping, so this is pure progressive enhancement. (The prototypes already used `text-wrap: balance`; the app
  stylesheet did not.)
- **Theme for native UI:** `.bb-stage { color-scheme: light }` + `[data-bb-theme="dark"] { color-scheme: dark }`, so
  scrollbars, carets, date pickers and other UA-painted UI follow the app's theme instead of always painting light.
- **Forced Colors:** a `@media (forced-colors: active)` block keeps dialog/sheet edges and focus rings visible
  (`1px solid CanvasText`, `outline`), since forced-colors strips the glass backgrounds and shadows everything in this
  design relies on.
- **Images:** `loading="lazy" decoding="async"` on repeated list/thumbnail images (Following, TeamPage, EventDrafts,
  Home's host avatar, dispute/verification proofs); `decoding="async"` only on top-of-screen avatars (PublicProfile,
  OrganizerProfileV23). **No `fetchpriority="high"` was added**, and that is deliberate: the real LCP images here are
  CSS `background-image` (`data/events.js` `bg()`), not `<img>`; `PhotoPager` already does eager/lazy for the visible
  and next photo. Converting covers to `<img>` would be a redesign.
  *Not done:* `srcset`/`sizes`. Supabase image transforms are a separate project (note 22), and inventing widths
  without checking the transform endpoint would ship broken URLs.
- **IME:** all 10 Enter-to-submit handlers now guard on `e.isComposing || e.keyCode === 229`
  (`PersistentSearchBar`, `AccountGate` ×2, `AdminTestAccounts`, `DisputeChatPanel`, `Login`, `ProjectJoin`,
  `Security`, `ChatPhotoViewer`, `DeleteAccountSheet`). The `keyCode === 229` half is **required**: Safari resets
  `isComposing` before the confirming Enter keydown (WebKit bug 165004), so `isComposing` alone silently fails there.
  This matters for Vietnamese input, not just CJK.
- **Autofill:** `autoComplete="new-password"` on ResetPassword ×2, `autoComplete="email" inputMode="email"` on
  SurveyPublic and the Reserve attendee email. Login already had correct `username` / `current-password` /
  `new-password` / `one-time-code` tokens.
- **`:user-invalid`:** one global rule now paints a browser-known invalid field (after interaction only) with the same
  alert border as `aria-invalid`. Fields whose errors are business rules keep `aria-invalid`, which is set by JS.
  *Deliberately not* applying `:user-invalid` to empty required fields: this app's validation is server/business-rule
  driven (note 53's field states), and pre-empting it would turn warning states red too early.

### B — overlays on the native primitive

New `src/components/NativeSheet.jsx` + `dialog.bb-native-sheet` CSS. `<dialog>` + `showModal()` supplies top-layer
rendering, focus containment, page inertness, Esc/back dismissal and focus return. The component handles the one thing
the platform does not know about: **the desktop phone frame**. A top-layer box is laid out against the viewport, so
before `showModal()` it writes the frame rect (`src/lib/viewport.js`) as a `clip-path` inset and insets the body
wrapper to the same rect. On a phone those insets are 0 (frame == viewport).

Migrated: `GuestPromptSheet`, `StartHostingSheet`, `ProjectUI.Sheet` (the hub's shared sheet). Each lost its own
scrim `onClick`, Escape listener and — in StartHosting's case — a manual Tab-cycle trap and a manual return-focus
effect.

`role="dialog"` / `aria-modal` are kept on the native element on purpose: they are redundant, but this repo's
Playwright specs assert them, and dropping them would be an unrelated contract change.

Not migrated, on purpose:
- `EventDetailsSheet` — has a two-phase close animation and a manual opener capture; it is the next one to move, but
  it deserves its own pass plus its ticket spec.
- `HomeFilterSheet`, `AreaSheet`, `RecipeSheet`, `ProjectMoney`'s proof viewer, admin confirmations — same shape, not
  yet moved. Each is mechanical once the primitive is trusted.
- `OnboardingTour`, `PulseViewer`, `MapListSheet`, photo viewers — drag/swipe surfaces where the current absolute
  positioning is part of the gesture, not a modal that can be reparented to the top layer.

**`GlassMenu` was NOT moved to Popover + anchor positioning**, and this is the clearest example of the verification
rule: Popover only reached iOS Safari in **18.3**, and CSS anchor positioning needs **Safari 27** (and is unsupported
in Firefox). This app still runs on iOS 16.2+. The current menu already has correct light-dismiss and Escape handling;
moving it would either need a polyfill (a new dependency, out of scope) or a doubled code path used by almost nobody.

### C — scroll / INP: measured, not applied

No rewrite was made, because every candidate API sits above the floor:

| Technique | Support from the guides | Decision |
| --- | --- | --- |
| Scroll-driven animations (`animation-timeline`) | Safari 26 (Sep 2025), Baseline 2026-10-27 | Defer — would need the JS path kept forever for iOS 16–18 |
| `content-visibility: auto` | Safari 26 (Sep 2025) | Defer — no benefit on the target browsers, and it interacts with `Pager.jsx`/Event Detail's own top-edge measurement |
| `scheduler.yield()` | Chrome/Firefox only, **unsupported in Safari** | Defer — the existing handlers already coalesce with `requestAnimationFrame` |
| `fetchpriority` | Safari 17.2+ | Defer — LCP is a CSS background (see above) |

The JS scroll handlers were left as they are: they are rAF-throttled, and "no speedup without a measurement" applies.
Playwright **does** run on this machine now (12/12 pager spec across Chromium/Firefox/WebKit), so a future pass can
measure properly before touching them.

### D — correctness and security

- **UA sniffing → capability detection** in `paymentQr.isMobileBrowser()` and `PublicProfile`'s mobile banner:
  `(pointer: coarse)` + `navigator.maxTouchPoints > 0` describes a touch-first device, and correctly catches iPadOS
  desktop mode (which reports a Macintosh UA and needed a special case before). A desktop with a touchscreen stays
  desktop because its PRIMARY pointer is fine.
- **`giftTicket.isAppleWalletBrowser()` keeps its UA check** and should: downloading a `.pkpass` genuinely only works
  in Safari, and on iOS every browser is WebKit, so there is no honest feature to detect.
- **`document.write` in `BanBeContext.downloadDocument` is kept.** It targets a `window.open('', '_blank')` document
  it just created, which is the one sanctioned use; a Blob URL + iframe would be a behaviour change for the print
  pipeline with no benefit.
- **`rel`:** every `target="_blank"` link already has `rel="noreferrer"` or `rel="noopener noreferrer"`. No change.
- **`-webkit-` prefixes:** none were removable. `::-webkit-slider-*` (range styling), `-webkit-appearance`,
  `-webkit-backdrop-filter` (needed before Safari 18), `-webkit-tap-highlight-color` and `::-webkit-scrollbar`
  (hiding the scrollbars is a design decision) are all still load-bearing.
- **CSP: not added.** `vercel.json` exists, but a report-only policy without a violation baseline would flood the
  console (the app is built on inline React styles, Supabase, MapKit and R2). Worth doing as its own task, with a
  reporting endpoint and a real allowlist.

## Deliberately not done (whole list)

- `Promise.withResolvers()` for the sign-in hand-off — **Safari 17.4+**; on older iOS the promise would never settle
  and sign-in would hang for 20s and fail. `new Promise(r => { resolve = r })` stays.
- `<input type="checkbox" switch>` — Safari 17.4 only, unsupported in Chrome/Edge/Firefox. The three custom
  `role="switch"` checkboxes stay as they are (they also carry the app's own styling and motion).
- `oklch` conversion of the design tokens — they are hand-tuned and cross-checked against iOS (note 06).
- View Transitions on screen changes — would fight the app's own swipe/zoom gesture system.
- Container-query rework of the phone frame / card layouts.
- Any visual redesign.

## Verification

- `npm run build` — green.
- `npm run test:unit` — **1015/1015** green.
- `legacy-scan src` — **31 → 4**, and the remaining 4 are exactly the two deliberate drops documented above.
- `npx playwright test tests/public/home-v23-pager.spec.js` — 12/12 across Chromium, Firefox and WebKit.
- Visual check of `NativeSheet` in the running app (desktop phone frame): the dialog's box is the viewport, the body
  wrapper and the scrim clip to the frame (393×846 at 404,27), the panel sits inside it, and focus lands in the dialog.
  The first attempt exposed a real bug — the body wrapper was viewport-wide, so a 480px panel was centred in the
  1200px window and sliced by the phone edge; fixed by insetting the wrapper to the frame.
- **Blocked, pre-existing:** `tests/simple-shell-home.spec.js` and the Project Hub spec both fail in `guestToHome` /
  `openGuestShellHome` (waiting for `[data-screen-label="Home"]` as a guest). Confirmed identical on the unmodified
  base commit with `git stash`, so it is not from this pass. The migrated sheets therefore have build/unit/visual
  verification, but **not** spec verification. That guest-flow failure is worth its own ticket.

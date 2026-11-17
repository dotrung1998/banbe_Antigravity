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

Migrated in the first pass: `GuestPromptSheet`, `StartHostingSheet`, `ProjectUI.Sheet` (the hub's shared sheet). Each
lost its own scrim `onClick`, Escape listener and — in StartHosting's case — a manual Tab-cycle trap and a manual
return-focus effect.

**Rollout (second pass) — every remaining in-scope dialog is now on the primitive:**

- The four named candidates: `EventDetailsSheet`, `HomeFilterSheet`, `AreaSheet` (embedded variant), `RecipeSheet`.
  EventDetailsSheet keeps its two-phase close animation and its initial focus on Close; its Escape listener, manual
  Tab cycle and opener `useRef` are gone (`returnFocusTo` now goes to the primitive).
- `HostListSheet`, `LiveNowSheet`, `EventDrafts`, `ProfileShareSheet`, `DeleteAccountStaySheet`, `Following`'s unfollow
  confirm, `Rewards`' redeem confirm, `Reports`' metric detail, `Schedule`'s month sheet, `EventDetail`'s About &
  Included, `CreateEvent`'s long-text editor (and its clear-all confirm), `ProjectMoney`'s transfer proof,
  `AdminManageEvents`' reason sheet, `AdminFeatures`' requires-confirm, `AdminTestAccounts`' two confirms,
  `DockCreateCenter`, `EventOnboarding`'s types panel, `HomeDiscoveryParts.CategorySheet`, `QuickSheetV5`.
- Nested dialogs: `AreaSheet` inside `HomeFilterSheet`, and the clear-all confirm inside the long-text editor, both
  call `showModal()` above an already-open dialog. Escape/cancel closes the top one only and the parent keeps its
  state (verified live, including the filter sheet surviving the location sheet's Done).

Primitive additions this pass: `align`/`pad` for centred confirmations, `scrim`/`blur` for the surfaces that had their
own scrim colour or backdrop blur, and an opener captured when the dialog opens, so focus returns to the trigger even
when a caller does not pass `returnFocusTo` (Safari does not focus a button on click, so the browser's own restore
would land on the page body). Cleanup now closes the element captured in the effect (`el`) rather than reading
`dialogRef.current`: React detaches the ref before passive-effect cleanup, so the old code skipped `close()` and the
browser's focus-to-body after removal won the race against the focus call.

`role="dialog"` / `aria-modal` are kept on the native element on purpose: they are redundant, but this repo's
Playwright specs assert them, and dropping them would be an unrelated contract change.

Not migrated, on purpose (each is a written keep, not a silent skip):
- `OnboardingTour` (two cards, `role="dialog" aria-modal`) — it is a **tethered spotlight**, not a sheet. Its scrim is
  drawn with a cut-out around a real element and the card is positioned against that hole; a top-layer dialog would
  cover the cut-out and make the element the tour is pointing at inert, which defeats the tour. It has no scrim click
  to close and its Escape handler is part of the tour's own step machine.
- `EventDrafts`' delete confirmation — an inline `role="alertdialog"` card *inside* the Drafts sheet: no scrim, no
  `aria-modal`, no focus trap. It is a confirmation block in a scrolling list, not a modal overlay.
- Anchored Escape/outside-click layers that never claimed dialog semantics: `GlassMenu`, `SortMenu`, `AreaMenu`,
  `GiftTicketSheet`, `TicketImportSheet`, `DockCreateButton`, MapExplore's area/list panels. These are menus and
  popovers; the Popover API is above the floor (iOS 18.3+), and turning a menu into a modal dialog would be wrong.
- Non-embedded `AreaSheet` — an inline centred card absolutely positioned in a screen's own coordinate space (86 px
  above the dock). It has no dialog role, no Escape listener and no trap, and moving it to the top layer would detach
  it from the dock offset it was designed around. Its embedded sibling — the real modal — is migrated.
- Drag/swipe surfaces (`PulseViewer`, `MapListSheet`, photo viewers) carry no dialog semantics; their absolute
  positioning is part of the gesture and they were left alone.

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
- **`giftTicket.isAppleWalletBrowser()` no longer reads `navigator.userAgent`.** It checks Apple's WebKit
  (`navigator.vendor`), an Apple device (`maxTouchPoints > 1` also covers iPadOS desktop mode, or a Mac platform) and
  Apple Pay JS, which Safari exposes and the WebKit-based wrappers from other vendors do not. That is as close to a
  capability as a `.pkpass` handler gets — there is no API for "can this browser open a Wallet pass". If a future
  browser reports Apple's vendor and exposes Apple Pay JS without handing `.pkpass` to Wallet, the button would appear
  and the file would download; the endpoint also returns 503 until the pass certificate is configured (note 24).
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
- `npm run test:unit` — **1015/1015** green, no assertions changed.
- `legacy-scan src` — **31 → 4**, and the remaining 4 are exactly the deliberate drops documented above; the second
  pass introduced no new finding.
- `npx playwright test tests/public/home-v23-pager.spec.js` — 12/12 across Chromium, Firefox and WebKit (first pass).
- **Live check, desktop phone frame (1200×900 window, frame 393×846 at 403.5,27):**
  - `HomeFilterSheet`, the nested `AreaSheet`, and `QuickSheetV5` are each a real `<dialog>` (`tagName DIALOG`,
    `:modal`, `open`), the body wrapper measures exactly the frame, and the panel is 393 px wide with its bottom flush
    to the frame's 873 px after the entry animation (the preview throttles animations, so the settled state was measured
    with the animation disabled — a stuck mid-animation frame is an artifact of the preview tab being occluded).
  - Focus lands inside the dialog on open; a background trigger cannot be focused while it is open
    (`button.focus()` leaves focus in the dialog); closing returns focus to the trigger (`home-filters-button`,
    `home-avatar-button`, `home-filter-area` after the nested sheet's Done).
  - Nested: `filter-area-sheet` opens as a second modal inside the frame; Done closes only it, the filter sheet and its
    draft survive, and focus returns to the Location row. No dialogs are left behind.
  - Escape was verified through the dialog's `cancel` path in the preview (React `onCancel` → `preventDefault` → close),
    which is what the platform fires for Esc and the mobile back gesture. The preview tool's synthetic key events did
    not reach the page at all (a capture listener saw zero keydowns), so the preview cannot prove the physical key.
    The two sheets below were therefore driven in Playwright, where real key, pointer and wheel input does reach the
    page.
- **`EventDetailsSheet` and `RecipeSheet`, opened live in the same frame** (temporary probe page mounting the real
  components inside `.bb-device > .bb-screen`; probe files and screenshots removed afterwards. No app or server data
  was changed):
  - Both render as `DIALOG`, `open === true`, `:modal === true`; the panel is 393 px wide at the frame's x, 727.5 px
    tall, bottom at 873 — flush with the frame, clipped by the frame rect, not centred in the 1200 px window. The entry
    animation settles to `transform: none` here (Playwright's renderer is not occluded).
  - `EventDetailsSheet` opens with focus on its Close button (`event-details-close`); `RecipeSheet` on its Close button.
  - A background trigger cannot take focus (the `focus()` call leaves the close button focused). Tab walks only the
    dialog's own controls. At the wrap boundary Chromium moves sequential focus out of the document to the browser
    chrome (`document.activeElement` becomes `BODY`), **not** to a control behind the dialog; the next Tab returns to
    the dialog's first control. This is native dialog behaviour, and it replaces the old hand-written wrap trap; no
    background control is ever reached.
  - **Background scroll measured, not assumed:** with a 2000 px scroller behind the dialog, `scrollTop` / document /
    `scrollY` were `0 / 0 / 0` before, and `0 / 0 / 0` after a real wheel of 700 px over the scrim plus a real
    `PageDown`. Nothing scrolled, so `NativeSheet` needed no `overscroll`/`inert` change.
  - Real Escape closes both; focus returns to the trigger (`open-details`, `open-recipe`). Real pointer click on the
    scrim (5 px below the frame's top edge) closes both; focus returns to the trigger.
  - Nested: `EventDetailsSheet` opened from inside an open `NativeSheet` stacks as the second modal; Escape closes only
    it, the parent dialog stays open, and focus returns to the trigger inside the parent; a second Escape closes the
    parent and returns focus to its trigger.
  - The first visual attempt exposed the focus-return bug described above and it was fixed before these runs.
- **Spec attempts, still blocked (pre-existing):** `tests/home-quick-controls.spec.js`, `account-reports.spec.js`,
  `ticket-redesign.spec.js` all fail in their shared guest helper (`guestToHome` / `openGuestHome` waiting for
  `[data-screen-label="Home"]`), identical to the base commit. Driving the same sheets with the shared signed-in
  session is also unavailable: that account is gate-blocked server-side (`account_gate_status`), so every RLS read
  returns 403 and the app sits on its Splash. That is why `EventDetailsSheet` (normally reached from a real ticket) and
  `RecipeSheet` (normally reached from the review step) were exercised through the temporary probe rather than their
  product entry points. The probe and its spec were deleted; the checks above are the verification of record. The
  guest-flow failure deserves its own ticket.

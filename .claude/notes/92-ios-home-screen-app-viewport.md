# 92 — Home Screen web app: the unpainted strip at the bottom

Status (2026-11-17): IMPLEMENTED (web only; the iOS app is unaffected). `npx vite build` and `npm run test:unit`
(1015/1015) green. Not verifiable on the owner's phone from here — see "Checks".

## What was asked

Owner's screenshot: after "Add to Home Screen" in Safari, the web app opens with a status-bar-tall black strip at the
very bottom of the screen, below the dock, and the page reads as short/cropped. "It looks very poor like this."

## Root cause

iOS 26 lays a Home Screen site out on one of two native paths, chosen from the page's own markup:

- **Any PWA markup** — a web app manifest, `apple-mobile-web-app-capable`, `mobile-web-app-capable`, or
  `apple-mobile-web-app-status-bar-style` — selects a **legacy** frame: the web view is anchored at the very top of
  the screen (content under the status bar) but its height still leaves the status bar out. A 59-62 pt strip at the
  **bottom** of the display is therefore outside the page: no CSS height, viewport unit, safe-area inset or JS can
  paint into it, and every in-page metric (`innerHeight`, `dvh`, `visualViewport.height`,
  `getBoundingClientRect`) is internally consistent, so the page cannot even detect it.
- **No PWA markup** gets the correct frame: the page starts below an opaque status bar and reaches the screen's
  bottom edge, home indicator included.

`index.html` shipped both `mobile-web-app-capable` and `apple-mobile-web-app-capable`, so the owner's install took the
broken path. Evidence: WebKit bugs 313800 and 316008, and a controlled A/B on iOS 26.6 (pi-web issue #598) where the
identical page with and without that markup differs exactly this way. WebKit 316008 also notes the mode is fixed at
install time, so an already-installed icon can need to be deleted and re-added.

The black colour of the strip came from `body`: `--bb-band` is the night colour over Home's hero, and the body
(min-height 100dvh) is taller than the mis-sized fixed stage, so the leftover showed as `#16140f`.

## Fix

- `index.html`: **removed** `mobile-web-app-capable` and `apple-mobile-web-app-capable` (there was never a manifest
  or a status-bar-style), with a comment explaining why they must not come back. iOS 26 opens a Home Screen site as a
  web app on its own, so nothing is lost there; on iOS 16-25 such an install would now open with Safari's chrome.
  That trade is deliberate: the alternative is a permanently unpaintable 59-62 pt band on the owner's device.
- `src/App.jsx`: the dock row's `bottom` and `DOCK_CLEARANCE` (the scroller's bottom padding) now add
  `env(safe-area-inset-bottom, 0px)`. In the correct frame the home indicator is part of the page, so the dock has to
  step over it; in a Safari tab (browser bar) and on desktop the inset is 0, so nothing moves.
- `src/screens/DockCreateButton.jsx`: the create tray's fixed `bottom` gets the same inset, so it still sits just
  above the dock.

`body::before` (the iOS-style top band, note 90) needed no change: in the correct frame `env(safe-area-inset-top)` is
0, so the strip is the 12 px coarse-pointer fallback painted in `--bb-band` — paper on paper screens, night on Home's
hero, i.e. invisible either way.

## Checks

- `npx vite build` → exit 0. `npm run test:unit` → 1015/1015.
- **Not checked:** the standalone frame itself. It cannot be reproduced in Chromium (display-mode standalone cannot
  be forced by `emulateMedia`), and there is no Safari/Web Inspector on this machine; the fix is the documented
  markup route rather than a DOM-observable change. Safe-area offsets resolve to 0 in every browser check, so the
  desktop/phone-frame layout is unchanged by construction.
- **Owner action if the band persists:** delete the Home Screen icon and add it again — WebKit fixes the frame mode
  at install time, and the already-saved web clip was created while the markup was still present.

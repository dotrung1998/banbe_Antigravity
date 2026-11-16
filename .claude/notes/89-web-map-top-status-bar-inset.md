# 89 — Map top controls on web sat under the iOS status-bar strip

Status: FIXED (web), 2026-11-15. iOS checked by source, not affected. No migration.

## Symptom
On a phone, the Map's search row was invisible: the chip row ("Ho Chi Minh City ▾", "Seats left", "Free", …)
sat glued to the top of the screen and there was no back button, field or filter button. A fresh browser check (430×932
viewport, `env(safe-area-inset-top)` ≈ 35 pt) proved the bar existed, was hit-testable (a click at its centre opened
map search) and was painted over by `body::before` — `src/index.css`'s `#16140f` strip, `z-index: 2147483000`, whose
height IS the safe-area inset. On a Dynamic Island phone (~59 pt) the whole 44 pt row is hidden.

## Cause
The Map is a full-bleed screen (`App.jsx`'s `fullBleed`: Home hero / event / mapExplore), so the root scroll viewport
does not get `marginTop: SAFE_TOP`. Two things still measured from the very top of the window:
- `MapExplore.jsx`'s `topInset` was `0` on a phone (only the desktop frame's 50), so `map-top` started at y = 8.
- `PersistentSearchBar.jsx`'s `searchBarTop()` returns 8 (58 in the frame) and never added the inset. The Search
  overlay (a `position: fixed` root) had the same gap in its own header padding.

## Fix
`SAFE_TOP` (`var(--bb-safe-top, env(safe-area-inset-top, 0px))`) now lives in `src/lib/viewport.js` (App.jsx imports it)
and is added wherever something is placed from the window top:
- `MapExplore.jsx`: `topInset = calc(<0|50>px + SAFE_TOP)`. The measured `topControlsBottom` that drives the camera
  padding, the reference rect, the list top and maplibre's zoom-control offset follows it automatically.
- `PersistentSearchBar.jsx`: the bar's offset is `calc(searchBarTop()px + SAFE_TOP)` unless it is gliding over Home's
  own bar (that path uses Home's measured window frame as is), so the field lands in the map's reserved 44 px slot.
- `Search.jsx`: the overlay header adds `SAFE_TOP`; as a root screen it keeps 8 px because the scroll viewport already
  starts below the inset.

## iOS
Not affected. `PersistentSearchBar.swift` offsets by `keyWindow?.safeAreaInsets.top + 8` inside an
`.ignoresSafeArea()` GeometryReader, and `MapExploreView`'s `layers` respect the safe area (only `Map()` itself ignores
it), with `MapTopControls`' `.padding(.top, 8)` under its own 44 pt row. Verified by reading the Swift sources in this
pass, not run on a device.

# 39 — Web photo viewer pinning + page indicator, Rewards back target (commits db5b755, 4f564ab)

Status: IMPLEMENTED (web + iOS where noted), pushed to main. Not device/browser-verified.

## Web photo viewer pinned to the visible area
- Symptom: opening a photo on a scrolled event page showed only the bottom edge of the viewer (caption + heart/save/share over dark blur) at the top of the screen.
- Root cause: overlays are mounted inside App.jsx's scroll container (`position: relative; overflow-y: auto`). An `absolute; inset: 0` child there is anchored to the top of the SCROLLED CONTENT (content y 0..clientHeight), not to what is visible, so it sits above the viewport on any scrolled page.
- Fix: `src/lib/usePinnedOverlay.js` — on mount sets `top = scroller.scrollTop`, `height = scroller.clientHeight`, `bottom: auto`, and sets the scroller's `overflowY: hidden` until unmount. Used by `sheets/PhotoViewer.jsx` and `sheets/ChatPhotoViewer.jsx`. Usage: `const { ref, pin } = usePinnedOverlay()`; put `ref` on the overlay root and spread `...pin` AFTER `inset: 0`.
- NOT checked: other `absolute; inset: 0` overlays in App.jsx (StoryViewer, QrScanSheet, AreaSheet, LocationSheet, ReasonSheet, import sheets) may have the same bug on a scrolled page. Pulse/ProfileShare use `position: fixed` and are unaffected.

## Web photo position indicator (iOS parity)
- `PhotoViewer.jsx` renders, under the photo and above the "banbe ▪︎ bạn mới mỗi tuần"/actions row: dots for 2–8 photos (current 7px/0.95 alpha, others 6px/0.35), "n / N" for >8, nothing for 1 (height 10px still reserved). Mirrors iOS `PhotoViewerView.pageIndicator`. `role="img"` + aria-label "Photo n of N". Test id `photo-viewer-page-indicator`. The photo's max height budget went from 64px to 84px to make room.

## Rewards & badges Back target
- Before: Back always went to Account (`.profile`), even when opened from Home's coin/streak shortcuts.
- Now: origin is remembered. iOS: `AppState.rewardsBackScreen` + `openRewards(from:)` (goBack, `backTargetScreen` and `RewardsView`'s BackLink label all read it); Home -> `.home`, Account/search/keychain-locked-design -> `.profile`. Web: `state.rewardsBack` ('home' | 'profile'), set by Home.jsx / Account.jsx / AccountSearch.jsx / KeychainSettings.jsx; `Rewards.jsx` back link + label read it.
- "Exact spot" relies on existing Home scroll memory (iOS `homeScrollOffsetY`, see note 38; web `scrollPositions` per screen in App.jsx).
- `.following` still always returns to Account (unchanged). Any NEW entry point to Rewards must go through `openRewards(from:)` / set `rewardsBack`, otherwise iOS keeps the previous origin.

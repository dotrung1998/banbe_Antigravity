# 90 — Browse by type is a tab, the iOS-style top band, and a water drop on page swipes

Status (2026-11-15): IMPLEMENTED (web + iOS). Web `publish_preview` green
(https://banbe-antigravity-xu2e--preview.freemilk.app). iOS edited by hand, not built: the repository is tagged as a web
app (needed for the preview), which is why `xcode_build` is not offered in this chat. No migration. Same `home_v23`
switch. Refines notes 86, 88 and 89.

## What was asked

1. "Browse by type" should be a tab alongside For You / Tonight / Weekend, not the quiet link under the chips.
2. The web app's black status-bar band should take the iOS style and colour on every screen.
3. A water-drop-like animation while page swiping.

## What changed

### 1. Browse by type is the fourth tab

- The `scope` tab row now always renders and holds four tabs: For You, Tonight, Weekend and Browse by type
  (`browse-scope-all`). It shows on `/browse[/<type>]` too, with that fourth tab selected, so the destination it leads
  to still reads as the tab it is instead of the row vanishing.
- Tapping it runs the old link's path (`browseOpenTypes` / `browseTypesFrom`): the every-event list opens in place and
  `browseFrom` remembers the tab, so Back returns to that tab. Tapping a Home tab still goes through the scope switch.
- The `browse-browse-types` link under the chips and its grid/chevron glyphs are gone on both platforms.
- Tab labels are 16pt with a 16px gap so four fit a phone's width; the row still scrolls if a locale needs it.

### 2. The top band follows the screen (web)

- `body::before` and `body` now paint `var(--bb-band)` instead of a fixed `#16140f`. `src/lib/themeColor.js` writes
  `--bb-band` (and the `theme-color` meta) in one place: the theme's paper (`#f7f4ec` light, `#0f0e0b` dark) by
  default, the night colour only where the screen's own top edge is dark — Home's hero, Event Detail, Map, and the
  full-screen dark viewers (photo viewer, chat photo viewer, story viewer, the post-sign-up intro).
- `App.jsx` runs that from `fullBleed` plus those overlay flags on every screen and theme change, after the child
  effect, so the incoming screen's edge wins. `HomeShellV5` keeps its own finer rule (night while the hero is at the
  top, paper once scrolled past it).
- `index.html`'s `theme-color` default is the paper colour, so Safari's own bar matches before the app mounts.
- iOS is unchanged: its status bar is already transparent over the page, which is the look being copied.

### 3. Water drop on page swipes

- New `src/components/SwipeDroplet.jsx`: a glass bead with a trailing wake at the leading edge of a root tab swipe. It
  follows the finger with no transition, stretches along the travel and thins across it, rolls off and leaves a short
  ripple (`bbSwipeRipple` in `index.css`) when the swipe commits, and settles back into the page when it does not.
  Purely decorative: no layout, no hit-testing, `aria-hidden`, and nothing rendered under Reduce Motion.
- `App.jsx` owns the gesture numbers: `swipeCommit` ('next' | 'prev' | null) marks the settle, so the component can
  tell "still dragging" from "committed"; it is cleared with the rest of the settle state and on cancel.
- iOS has the same effect as `tabSwipeDroplet` in `RootView.swift`: a radial-gradient capsule with a highlight, sized,
  stretched, drifted and faded from `tabSwipeTranslation`, rolling off when `tabSwipeCommittingTarget` is set. Hidden
  from VoiceOver, never hit-testable, absent under Reduce Motion, below the search bar (zIndex 3) and notifications
  overlay (4).

## Files

- Web: `src/screens/Browse.jsx`, `src/components/SwipeDroplet.jsx` (new), `src/App.jsx`, `src/index.css`,
  `src/lib/themeColor.js`, `index.html`, `tests/public/browse-v23.spec.js`.
- iOS: `apps/ios/BanbeApp/Views/BrowseView.swift`, `apps/ios/BanbeApp/Views/RootView.swift`.

## Checks

- **Web:** `publish_preview` green — the bundle builds and the preview is published. The Playwright cases were updated
  (`browse-scope-tabs` now expected on `/browse`, the fourth-tab flow replaces the link flow) but not run: chromium
  crashes on the build machine.
- **iOS:** not built. The Swift edits mirror the web ones and were reviewed by hand; `xcode_build` needs the repository
  tagged as an iOS app again.
- **Not checked visually:** the tab row's fit on a narrow phone with Vietnamese labels, the drop's size over the two
  themes, and the band's exact match to iOS on a Dynamic Island phone.

## Open

- Whether the fourth tab should also appear in Home's own hero tab row (it is the same three tabs). Not done: the
  request and the screenshot are the See all screen, and Home has no Browse by type link there today.
- `StoryCreateOverlay` owns its own black preview state and cannot be read from `App.jsx`, so the band stays paper
  above that one transient overlay.

# Photo viewer tap-to-close bug + shrink-back dismiss (2026-09-16)

## Status: WORKING (web + iOS), first pass

## Follow-up (unify dismiss + live drag tracking, this session)

- **Backdrop-tap vs swipe-past-threshold dismiss were NOT actually two
  separate implementations — verified by reading, not assumed.** A ticket
  asked to "make backdrop-tap use the exact same shrink-back animation as
  swipe-past-threshold, instead of whatever plain dismiss it currently
  does." Both `src/screens/sheets/PhotoViewer.jsx`'s `onBackdropClick` and
  `apps/ios/BanbeApp/Views/PhotoViewerView.swift`'s backdrop
  `.onTapGesture` already called the exact same `dismiss()`/`dismiss()`
  function the swipe-past-threshold branch calls — this was already true
  as of the original first pass documented above ("Dismissing (either
  path) shrinks the photo back to the exact thumbnail rect it was opened
  from"). No code changed for this part; it's flagged here so a future
  pass doesn't re-"fix" something that was never actually broken.
- **Live drag-follow WAS genuinely missing — this part of the ticket's
  premise was correct.** Before this pass, both platforms only evaluated
  `dx`/`dy` once, at release (`onPhotoPointerUp` / the `DragGesture`'s
  `onEnded`) — the photo and backdrop gave zero visual feedback while a
  finger was still down mid-drag. Added on both platforms:
  - The photo's transform now follows the finger 1:1 (translateY web /
    `.offset` iOS) once a drag is clearly vertical-and-downward (gated so
    a horizontal swipe-browse drag is never affected).
  - The backdrop (blurred copy + dim layer) fades opacity linearly with
    drag progress over a fixed reveal distance (200px/pt, independent of
    the much smaller existing dismiss threshold), so continuing to hold a
    drag past the threshold without releasing keeps revealing more.
  - Release logic is UNCHANGED: past threshold still calls the same
    `dismiss()`, short of it now springs back to the open position with
    the same easing/duration as dismiss itself (previously: nothing
    visually happened at all pre-release, so there was no "spring back"
    state to preserve).
  - **"Continue from the current dragged position" needed no special-case
    code on either platform** — it falls out of how each platform's
    existing dismiss computation already works: web's `dismiss()` reads
    `el.getBoundingClientRect()`, which reflects whatever inline
    `transform` the live drag already applied; iOS's `dismiss()` computes
    a target `dismissTransform` and assigns it inside `withAnimation`,
    which SwiftUI animates from the CURRENTLY-RENDERED `.offset()`/
    `.scaleEffect()` value (`dragTranslation`, applied unanimated) to the
    new target, regardless of which `@State` produced the starting value.
  - Web implementation is ref-driven (direct `.style.transform`/`.opacity`
    writes in `onPhotoPointerMove`), not React-state-driven — deliberately
    reusing the exact pattern this session's bottom-tab-bar scrub gesture
    already established, for the same reason: a state update per pixel of
    drag would be needless re-render churn for a purely visual, per-frame
    value. iOS's `dragTranslation`/`isDraggingDown` ARE plain `@State`,
    which is the normal, correct SwiftUI idiom for a live `DragGesture`
    follow (not the same footgun as the earlier GeometryReader/
    PreferenceKey scroll-tracking issue — that was a RunLoop-mode timing
    bug specific to that mechanism, unrelated to `DragGesture.onChanged`).
- File:line — web: `src/screens/sheets/PhotoViewer.jsx` (`dismiss()`,
  `onPhotoPointerDown`/`onPhotoPointerMove`/`onPhotoPointerUp`,
  `backdropRef`/`dimRef`, `DRAG_REVEAL_DISTANCE`). iOS:
  `apps/ios/BanbeApp/Views/PhotoViewerView.swift` (`dismiss()`,
  `dragTranslation`/`isDraggingDown`/`dragProgress`, the `DragGesture`'s
  `.onChanged`, the backdrop's `.opacity(1 - dragProgress)`).
- Verification: `npx vite build` clean; `xcodebuild build` →
  **BUILD SUCCEEDED**. No live-drag/visual verification was performed on
  either platform (no simulator touch-drag injection tool available in
  this sandbox for iOS, no Playwright run for web in this pass) — the
  release-time decision logic (past-threshold dismiss, short-of-threshold
  snap-back) is unchanged from the already-tested original implementation,
  and the live-tracking additions were verified by reading the resulting
  code's data flow (see the "needed no special-case code" bullet above),
  not by watching it drag on a real device/simulator.

Numbered 14, not 13 — `.claude/notes/13-policy-accuracy-review.md` already claimed 13 in this same session, right before this ticket arrived.

## 2026-09-21 cross-reference — two NEW, deliberately separate viewers added (chat photos, stories)

Full writeup lives in `07-notifications.md`'s "chat-image aspect ratio + fullscreen viewer ... real Stories system" entry — noted here only so a future reader of THIS file knows they exist. `ChatPhotoViewer.jsx`/`ChatPhotoViewerView.swift` (a chat attachment's own fullscreen viewer — Save/Share/Forward, not Like/Save-event) and `StoryViewer.jsx`/`StoryViewerView.swift` (a host's 24h story progression) both reuse this file's established backdrop/dismiss CONVENTIONS but are intentionally separate components/state from `PhotoViewer.jsx`/`PhotoViewerView.swift` — three viewer kinds now exist in this app (`photoViewer`, `chatPhotoViewer`, `storyViewer`), each with its own origin/back semantics, per this file's own prior instruction not to conflate them. Neither retrofits this file's gallery-prev/next or live-drag-follow machinery — both dismiss via a single eased transform computed once, not a per-frame pointer tracker, since neither is browsing a multi-photo gallery the same way an event's own photos are.

## 2026-09-22 update — ChatPhotoViewer DOES now use live drag-follow

The paragraph above (written when `ChatPhotoViewer.jsx`/`ChatPhotoViewerView.swift` were first added) is now partly out of date for that ONE viewer: a real-device report asked for this file's actual live-drag-follow convention (photo tracks the finger, chrome/backdrop fade with drag progress, release short of threshold springs back) instead of the single-eased-transform dismiss described above, AND for backdrop/photo taps to toggle chrome visibility rather than dismiss at all. Both are now implemented in the chat photo viewer — see `07-notifications.md`'s "revised chat-image interaction" entry for the full writeup. `StoryViewer.jsx`/`StoryViewerView.swift` (the story progression viewer) is UNCHANGED — still a single eased transform, no drag-dismiss at all, since it has its own tap-to-advance/auto-advance model instead.

## 2026-09-22 update — StoryViewer now DOES have drag-dismiss + hold-to-pause too, and a horizontal swipe

The paragraph above is now out of date for `StoryViewer.jsx`/`StoryViewerView.swift` specifically (a later real-device pass added the SAME live-drag-follow/hold-to-pause conventions `ChatPhotoViewer` already had, plus a new horizontal-swipe cross-host navigation gesture) — full writeup in `07-notifications.md`'s "five real-device bugs found in 344ce80" entry (BUG 2/3/5). `PhotoViewer.jsx`/`PhotoViewerView.swift` (event-gallery photos) remain the only viewer that has never needed this convention retrofitted, since it already had its own live-drag-follow from the original 2026-09-16 pass documented above.

## Audit findings

**The gallery is NOT queried from `public.event_photos`, on either platform** — the ticket's own framing ("public.event_photos") is aspirational, confirmed wrong: `public.event_photos` is a real table (schema in `001_core_schema.sql`, storage bucket in `005_storage_buckets.sql`, seeded in `010_seed_data.sql`) but grepped every client file for `event_photos`: zero hits in `src/` or `apps/ios/`. The photo viewer's `gallery` array is the static demo catalogue's own `ev.gallery`/`ev.orgGallery` (`src/data/events.js`, built deterministically from `LOCAL_PHOTOS`) — the same static-catalogue-vs-real-DB duality note 11 already documented for the Home feed and the map screen. `sort_order` never enters into it; array order is just the catalogue's own fixed order. This doesn't change the fix (navigation is still "the array's current order," whatever populates it), just corrects the premise.

**The bug, confirmed exactly as described, same root cause on both platforms**: a single gesture recognizer covering the *entire screen* (not just the photo) treats any short tap — including one landing squarely on the photo — as "not a swipe," and closes the viewer.
- Web: `src/screens/sheets/PhotoViewer.jsx:96-105` (`onPointerDown`/`onPointerUp` on the full-screen `position:absolute inset:0` stage `<div>`, wrapping the credit/photo/tagline column) — `else { closePhoto(); }` at line 104 fires for any release where `Math.abs(dx) <= SWIPE_THRESHOLD` (44px), which is every plain tap anywhere on screen, photo included.
- iOS: `apps/ios/BanbeApp/Views/PhotoViewerView.swift:79-91` — `DragGesture(minimumDistance: 0)` attached via `.gesture(...)` to the outer `ZStack` (full screen, `.contentShape(Rectangle())` at line 78), `.onEnded`'s `else { app.closePhoto() }` at line 90, same "any non-swipe release closes it" logic.

**Existing swipe-to-browse, kept**: both platforms already support a horizontal drag past `SWIPE_THRESHOLD`/`swipeThreshold` (44px/pt) to move to the next/previous photo (`showPhotoAt`/`app.showPhoto(at:)`, both already clamp at the array's ends — **no-op, not loop** — kept as-is for consistency, so the new tap-to-navigate zones don't introduce a different end-of-gallery behavior than the swipe gesture already has).

**No existing shared-element/hero/origin-rect animation pattern anywhere in the app** — grepped for `getBoundingClientRect` (web, zero hits anywhere in `src/`) and `matchedGeometryEffect`/`@Namespace` (iOS, zero hits anywhere in `apps/ios/BanbeApp/`). The shrink-back-to-origin dismiss is new territory on both platforms; built as a small, self-contained addition to the photo viewer specifically (a manual FLIP-style transform computed from a captured origin rect), not a new general animation system, and not `matchedGeometryEffect` on iOS — that needs a `@Namespace` shared between the thumbnail's view hierarchy and the viewer overlay's, which this app's `NavigationStack`-free, plain-ZStack `RootView` (no shared ancestor closer than `RootView` itself) makes more invasive to wire correctly than a manual rect capture-and-animate, and a manual rect keeps both platforms' implementations symmetric and easy to verify by inspection.

**Existing gesture-precedence convention reused (iOS)**: the project's own swipe-back fix (note 09) already established the pattern of a child view's gesture taking priority over a parent's via `.highPriorityGesture` rather than plain `.gesture`, specifically so a broader-area gesture doesn't swallow input meant for something more specific inside it. Reused here: the photo's own drag/tap gesture is attached via `.highPriorityGesture`, so it always wins over the backdrop's plain `.onTapGesture` dismiss handler for anything that starts on the photo itself.

## Implementation

**Tap/gesture zones, both platforms** — the drag/tap gesture moved off the full-screen container and onto the photo element only:
- A release with `|dy| > |dx|` and a downward `dy` past the swipe threshold → dismiss (shrink-back).
- A release with `|dx| > |dy|` past the threshold → existing prev/next swipe (unchanged).
- A release with neither past threshold (a plain tap) → which half of the *photo's own width* the tap/release landed in decides prev (left half) vs next (right half) — not the full screen width, so a tap in the dimmed margin beside a photo narrower than the screen still falls through to the backdrop's dismiss handler, not a nav zone.
- The backdrop (everything outside the photo — credit line, tagline/actions row, and the blurred/dimmed surround) keeps a separate, plain tap-to-dismiss handler.

**Shrink-back-to-origin dismiss, both platforms**: the thumbnail's `getBoundingClientRect()` (web) / `GeometryProxy.frame(in: .global)` (iOS) is captured at the moment it's tapped and threaded through `openPhoto(...)` into the viewer's state (`photoViewer.originRect` / `PhotoViewerItem.originRect`). Dismissing (either path above) does not call `closePhoto()`/`app.closePhoto()` immediately — it computes the delta between the photo's current on-screen rect and that origin rect, animates the photo element's transform (translate + non-uniform scale) from identity to that delta over ~280ms (same `cubic-bezier(.22,.61,.36,1)` easing this app already uses for its entrance animations), fades the backdrop concurrently, and only then clears the viewer state.

### File:line

**Web**:
- `src/screens/EventDetail.jsx:126`, `src/screens/Organizer.jsx:73` — thumbnail `onClick` now captures `e.currentTarget.getBoundingClientRect()` and passes it as a 5th `openPhoto` argument.
- `src/state/GocContext.jsx` `openPhoto(gallery, index, organizer, eventKey, originRect)` — stores `originRect` on `photoViewer`.
- `src/screens/sheets/PhotoViewer.jsx` — rewritten: backdrop gets `onClick={dismiss}`; the photo element gets its own `onPointerDown`/`onPointerUp` (stopping propagation) implementing the axis-priority decision above; a local `closing` state holds the computed transform and defers the real `closePhoto()` until the CSS transition ends.

**iOS**:
- `apps/ios/BanbeApp/Views/EventDetailView.swift:180-186`, `apps/ios/BanbeApp/Views/OrganizerView.swift` gallery `Button` — each thumbnail wrapped in a `GeometryReader` so its action closure can read `geo.frame(in: .global)` at tap time.
- `apps/ios/BanbeApp/State/AppState.swift` `PhotoViewerItem` gains `let originRect: CGRect`; `openPhoto(...)` takes and stores it.
- `apps/ios/BanbeApp/Views/PhotoViewerView.swift` — rewritten: outer `ZStack` gets a plain `.onTapGesture` dismiss; the photo view gets its own `.highPriorityGesture(DragGesture(minimumDistance: 0)...)` with the same axis-priority tap/swipe logic; a `targetRect` is captured once (via the same `GeometryReader` pattern) for the photo's natural in-place position, and dismissal animates `.scaleEffect`/`.offset` from that to the stored `originRect` before calling `app.closePhoto()`.

## New facts found while implementing

**Real bug caught by testing, not just reading the CSS (web)**: the first version of the shrink-back dismiss looked correct by inspection — `transition: 'transform 280ms cubic-bezier(...)'` set alongside the new `transform` value the instant `closing` turns on — but sampling the element's live `getComputedStyle(...).transform` frame-by-frame via `requestAnimationFrame` inside the page (not just waiting a fixed time and checking once, which would have missed this) showed it snapping straight to the final matrix on the very next frame, never interpolating. Root cause: the photo element still had `animation: gocIn ... both` assigned (the entrance keyframe, held at its last frame by `both`) right up until the same render that introduced the dismiss `transform`/`transition` — a CSS Animation still assigned to a property blocks a same-property CSS Transition on that element from taking effect, even when both changes are only one browser paint apart. Fixed by decoupling them in time: a `entered` flag (`useState` + a 240ms `setTimeout`, reset per `index` via a `useEffect`) removes `animation` from the photo/backdrop's style in its own, earlier render, well before any dismiss can plausibly start — confirmed fixed by re-running the same rAF sampling, which then showed a real, smooth 17-sample interpolation from `matrix(1,0,0,1,0,0)` down to the origin thumbnail's exact scale/offset matrix over the full 280ms. Applied the same fix to the backdrop's `gocFade`-vs-opacity-transition pair for consistency (same underlying mechanism, not separately verified frame-by-frame but the reasoning is identical). Known minor edge case left unaddressed: dismissing within the first ~240ms of opening (before `entered` flips true) would hit the same snap, since `entered` and `closing` would then change in the same render — not fixed, since no realistic interaction dismisses that fast, and forcing `entered` true synchronously inside `dismiss()` would reintroduce the identical same-render problem.

**iOS mirrors the same fix**: `PhotoViewerView.swift`'s dismiss doesn't have an equivalent "CSS Animation vs Transition" conflict (SwiftUI's `.animation(.easeOut(duration:), value: item.index)` only fires on `item.index` changes, and the dismiss's `withAnimation(dismissAnimation) { dismissTransform = ... }` is an explicit transaction that isn't fighting a separate still-active implicit animation on the same properties) — no equivalent decoupling was needed there, but flagging that this class of bug is real and worth checking for on iOS too if a future dismiss/entrance animation pairing gets added to this view.

**Web click-vs-pointer subtlety**: the backdrop's dismiss handler had to be `onClick` (not `onPointerDown`/`onPointerUp` like the old single full-screen handler, and not like the photo's own gesture) — `onPointerUp` alone doesn't stop the browser's own subsequent synthetic `click` event from bubbling, so the photo element also needs a no-op `onClick` with `stopPropagation()` purely to swallow that follow-on click before it reaches the backdrop's `onClick` dismiss handler one level up.

## Follow-up (real-device report: backdrop-tap-to-dismiss STILL not working, iOS only) + fade caption/buttons during drag

- **Root cause, confirmed by comparing platforms line-for-line, not
  guessed**: `PhotoViewerView.swift`'s "stage" VStack (credit + photo +
  tagline/actions) only ever had `.frame(maxWidth: .infinity, alignment:
  .leading)` — no `maxHeight`. Its OWN height was therefore just its
  content's natural height, vertically CENTERED by the enclosing `ZStack`
  (default `.center` alignment) — leaving real, empty backdrop space above
  and below it. The blurred backdrop layer directly behind it has
  `.allowsHitTesting(false)` (correct and deliberate — otherwise it would
  steal taps meant for the stage), so a tap landing in that dead zone
  (above the credit line, or below the tagline row, but still visually
  "the dimmed backdrop") reached NEITHER handler and fell through to
  whatever's behind the entire `PhotoViewerView`. **This was NOT the same
  mechanism the earlier "Task 2a" writeup checked** — that pass confirmed
  the backdrop's tap handler and the swipe-past-threshold path call the
  same `dismiss()` function, which is true and unrelated to this — it
  never verified that the backdrop's tap-catching AREA actually covers the
  whole screen. Fixed by adding `maxHeight: .infinity` to that same
  `.frame()` (paired with `alignment: .leading`, whose vertical component
  is `.center` — `Alignment.leading == .init(horizontal: .leading,
  vertical: .center)` — so the visible content's own on-screen position is
  unchanged, only the invisible hit-testable box grows to fill the screen).
- **Web never had this bug** — confirmed by re-reading `PhotoViewer.jsx`'s
  equivalent "stage" div: it already uses `position: 'absolute', inset: 0`
  (full-bleed, not sized to its own content), so its `onClick={onBackdropClick}`
  already covered the true full screen from the start. This is a genuine,
  narrow iOS-only gap, not a cross-platform one — flagging so a future
  "port this fix to web too" doesn't get attempted on a working
  implementation.
- **Task 4 (fade caption/buttons during drag, restore on snap-back)**:
  added on both platforms, tied to the SAME `dragProgress`/`progress`
  value already driving the backdrop's own fade — not a second, parallel
  progress tracker. iOS: `caption(_:)` (used for both the credit line and
  the tagline text) and the `actions` HStack each got
  `.opacity(1 - dragProgress)`. Web: new `creditRef`/`taglineRowRef`,
  faded imperatively in `onPhotoPointerMove` alongside `backdropRef`/
  `dimRef`, and restored (with a transition) in the same snap-back branch
  of `onPhotoPointerUp` and reset in `dismiss()` — mirrors the existing
  ref-driven pattern for `backdropRef`/`dimRef` exactly, not a new
  mechanism. On iOS, snap-back needed NO extra code for the "fade back in"
  half: `dragProgress` is a plain computed property of `dragTranslation`/
  `isDraggingDown`, both of which the existing snap-back branch already
  resets inside `withAnimation(dismissAnimation)` — SwiftUI animates every
  dependent value that changed within that transaction, not just the ones
  explicitly named, so the caption/buttons' opacity comes back in sync
  automatically.
- File:line — iOS: `apps/ios/BanbeApp/Views/PhotoViewerView.swift` (the
  stage `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment:
  .leading)` fix; `caption(_:)`'s and `actions`'s new `.opacity(1 -
  dragProgress)`). Web: `src/screens/sheets/PhotoViewer.jsx`
  (`creditRef`/`taglineRowRef`, faded in `onPhotoPointerMove`, restored in
  `onPhotoPointerUp`'s snap-back branch and reset in `dismiss()`).
- Verification: `xcodebuild build` → **BUILD SUCCEEDED**; `npx vite build`
  clean. The backdrop-tap fix itself was NOT verified with an executed tap
  in this pass (no UI test written for it, given the session's iOS UI-test
  budget went toward the tab-bar/Reserve regression instead) — the root
  cause and fix are reasoned from SwiftUI's own layout/hit-testing
  semantics and the direct platform comparison above, not confirmed via a
  real simulator tap the way Tasks 2/3's iOS fixes elsewhere in this
  session's notes were. Flagging this as the next thing to verify with a
  real tap if it's still reported as broken.

## 2026-09-22 update — StoryViewer's iOS view-lifecycle bug (`.onAppear` fires once) + gallery-drift transition, full details in 07-notifications.md

Two things worth cross-referencing here since they're general SwiftUI-view/gesture lessons that could recur in this file's own viewers (`PhotoViewerView`/`ChatPhotoViewerView`), not because either changed this file's own code this pass:

1. **A real iOS regression, worth remembering for any future `TimelineView`/state-swap viewer**: `StoryViewerView.swift`'s `.onAppear` only ever fires the FIRST time a view enters the hierarchy — swapping which story/photo is showing by mutating `@Published` state that the SAME view instance re-renders from (not a fresh `NavigationLink`/sheet presentation) does NOT re-trigger `.onAppear`. `StoryViewerView` had a bug from exactly this: only the very first story in a deck ever got its "mark viewed" side effect, because that call lived solely in `.onAppear`. Fixed by also firing it from `.onChange(of:)` on whichever state value actually changes between items (`groupIndex`/`storyIndex`). `PhotoViewerView`/`ChatPhotoViewerView` don't have an equivalent per-item side effect today, but if one is ever added (e.g. a "mark opened" call, or per-photo analytics), it needs to be wired the same way — `.onAppear` alone is NOT enough for a multi-item swap within one persistent view instance.
2. **Gallery-drift transition (Feature 3)** — StoryViewer's horizontal swipe-between-stories now has a live drag-follow + a soft glass "companion" card peeking in from the edge (web: `cardGlass()` token; iOS: `.ultraThinMaterial`), settling via a short animated drift rather than an instant cut, respecting `prefers-reduced-motion`/`accessibilityReduceMotion`. This is StoryViewer-specific (cross-host/cross-story navigation, not photo-viewer's own single-gallery paging), so `PhotoViewer.jsx`/`PhotoViewerView.swift` and `ChatPhotoViewer.jsx`/`ChatPhotoViewerView.swift` are unchanged — noted here only as a candidate visual pattern if either of THIS file's own viewers ever grows multi-item horizontal paging.

Full root cause, fix, file:line, and test results for both items: `07-notifications.md`'s "2026-09-22 ninth follow-up" entry.

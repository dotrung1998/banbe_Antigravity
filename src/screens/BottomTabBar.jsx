import { useEffect, useMemo, useRef, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { ink, alert, barGlass, dockHighlight } from '../theme.js';

// FEATURE follow-up (623ec1e real-device report): Map/Notifications/Inbox
// were still hard to tell apart at a glance despite 64f2719's stroke-count
// trim, so these three moved to unambiguous, differently-shaped silhouettes
// — a pin/marker for Map, a bell for Notifications, an envelope for Inbox —
// instead of iterating further on the shared ring/diagonal-stroke/dot
// vocabulary those three used before (that vocabulary is what made them
// hard to distinguish: they all read as "a ring plus a stroke"). Account
// is deliberately UNCHANGED (user confirmed it already reads fine) and the
// new three match its stroke weight (2.4-2.6) and rounded joins/caps so the
// set still reads as one family. See 06-design-tokens.md for the fuller
// rationale and why this isn't a copy of any IG/FB/Twitter glyph (none of
// the three use a map pin, a bell, or a flap-top envelope for these slots).
// Stage 3 (2026-09-27 nav/discovery pass) — each glyph now has a real
// filled (selected) and outline (unselected) variant, matching iOS's own
// SF Symbol filled/outline convention this app's icon set already read as
// belonging to. The bell used to be a solid shape UNCONDITIONALLY (no
// outline variant existed at all), which is the actual "bell stays filled
// even when Notifications isn't the active tab" bug this fixes.
// Refresh-indicator fix pass (2026-09-27, follow-up A) — the dominant,
// single traceable outline for each root tab's icon (same coordinates as
// that icon's own dominant shape in ICONS below, just exported standalone
// so App.jsx's pull-to-refresh indicator can `.trim()`-style travel a
// stroke around the REAL icon shape instead of a generic circle). Keyed
// by screen name (App.jsx's own DOCK_ORDER values), not by the icon id
// ICONS itself uses. Each is either a single `<path d>` or a basic shape
// SVG already supports a `pathLength` attribute on, so the same
// stroke-dasharray/dashoffset trick works for all five without a manual
// arc-length calculation.
export const TAB_OUTLINE_SHAPES = {
  home: { path: 'M6 19.5 V10 L4 11.5 L12 4 L20 11.5 L18 10 V19.5 Z' },
  mapExplore: { path: 'M12 3c-3.3 0-6 2.6-6 6.1C6 13.4 12 21 12 21s6-7.6 6-11.9C18 5.6 15.3 3 12 3z' },
  notifications: { path: 'M12 3.5c-2.8 0-5 2.2-5 5v4.6l-1.6 2.7c-.3.5.1 1.2.7 1.2h11.8c.6 0 1-.7.7-1.2L17 13.1V8.5c0-2.8-2.2-5-5-5z' },
  // Refresh-indicator fix pass (2026-09-27, follow-up B) — a bare rect/
  // circle read as a generic box/dot, not the dock's own envelope/person;
  // each is now the real glyph's full outline (body + V flap; head +
  // shoulders) as one combined path, so RootRefreshIndicator's travel
  // stroke actually reads as that icon.
  inbox: { path: 'M6.9 7 H17.1 A2.4 2.4 0 0 1 19.5 9.4 V15.6 A2.4 2.4 0 0 1 17.1 18 H6.9 A2.4 2.4 0 0 1 4.5 15.6 V9.4 A2.4 2.4 0 0 1 6.9 7 Z M5.5 8.2 L12 13.5 L18.5 8.2' },
  profile: { path: 'M8.2 8a3.8 3.8 0 1 1 7.6 0a3.8 3.8 0 1 1 -7.6 0 M5 19.2c1.3-3.9 4.2-5.8 7-5.8s5.7 1.9 7 5.8' },
};

const ICONS = {
  map: (c, filled) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <path d="M12 3c-3.3 0-6 2.6-6 6.1C6 13.4 12 21 12 21s6-7.6 6-11.9C18 5.6 15.3 3 12 3z" fill={filled ? c : 'none'} stroke={c} strokeWidth="2.4" strokeLinejoin="round" strokeLinecap="round" />
      <circle cx="12" cy="9.3" r="2.3" fill={filled ? 'var(--bb-bg)' : c} />
    </svg>
  ),
  notifications: (c, filled) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <path d="M12 3.5c-2.8 0-5 2.2-5 5v4.6l-1.6 2.7c-.3.5.1 1.2.7 1.2h11.8c.6 0 1-.7.7-1.2L17 13.1V8.5c0-2.8-2.2-5-5-5z" fill={filled ? c : 'none'} stroke={c} strokeWidth={filled ? 0 : 2.2} strokeLinejoin="round" />
      <path d="M9.6 18.6a2.4 2.4 0 0 0 4.8 0" stroke={c} strokeWidth="2" strokeLinecap="round" fill="none" />
    </svg>
  ),
  inbox: (c, filled) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <rect x="4.5" y="7" width="15" height="11" rx="2.4" fill={filled ? c : 'none'} stroke={c} strokeWidth="2.4" />
      <path d="M5.5 8.2 L12 13.5 L18.5 8.2" fill="none" stroke={filled ? 'var(--bb-bg)' : c} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  ),
  profile: (c, filled) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <circle cx="12" cy="8" r="3.8" fill={filled ? c : 'none'} stroke={c} strokeWidth="2.6" />
      <path d="M5 19.2c1.3-3.9 4.2-5.8 7-5.8s5.7 1.9 7 5.8" stroke={c} strokeWidth="2.6" strokeLinecap="round" fill={filled ? c : 'none'} />
    </svg>
  ),
  // Task 1b follow-up: a straightforward addition to the existing icon set
  // — same stroke weight (2.4-2.6) and rounded joins as the other four, a
  // plain house silhouette. Unlike the map icon's own earlier "avoid the
  // classic filled house outline" constraint (about not using a house FOR
  // a map glyph), a house for an actual Home tab is the universally
  // understood, semantically correct choice, not a borrowed IG/FB/Twitter
  // shape (none of those three put a house on a Home-equivalent tab).
  home: (c, filled) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <path d="M4 11.5 12 4l8 7.5" fill="none" stroke={c} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M6 10v9.5h12V10" fill={filled ? c : 'none'} stroke={c} strokeWidth="2.4" strokeLinejoin="round" />
    </svg>
  ),
};

// Top-level/primary screens only — flow screens that own the bottom of the
// viewport for their own CTA (Reserve's "Hold · 30 minutes", HostIntro's
// "Create your first event", etc.) are deliberately excluded so the two
// never collide.
const BAR_SCREENS = new Set(['home', 'mapExplore', 'notifications', 'inbox', 'profile']);

export function showsBottomBar(screen) {
  return BAR_SCREENS.has(screen);
}

// Stage 2 (2026-09-27 nav/discovery pass) — the ordered list root-tab
// swipe (App.jsx's Shell) navigates through; must match `items` above's
// own key order exactly (that array can't be reused directly — it's built
// from hooks inside the component below).
export const DOCK_ORDER = ['home', 'mapExplore', 'notifications', 'inbox', 'profile'];

// BUG 2 (64f2719) / BUG 3 (623ec1e) follow-ups: bumped from 22/19
// (expanded/collapsed) to one fixed, bigger size, then bumped again for
// BUG 3's "make the resting bar a bit bigger" ask. The shrink-on-scroll
// effect is a uniform CSS `transform: scale()` on the whole bar (see the
// outer style below), not a per-icon size change, so the icons themselves
// stay crisp at every scale factor.
// Task 5 follow-up (this session): flattened/elongated — 72→54 tall,
// 360→380 wide (see the outer style block's maxWidth below) — both to
// read as a slimmer, more refined pill and, more functionally, to leave
// more of the screen's bottom edge clear for MapExplore's own sheet list
// at its tallest detent (matches the iOS side's identical change; web has
// no separate-window hit-testing concern the way iOS's
// BottomTabBarOverlay does, so only the visual dimensions moved here).
// Task 5 (2026-09-21 follow-up): bumped 54→64 and icon size trimmed 24→20
// to make room for a small label under each icon (was icon-only, no
// on-screen text telling a first-time user what any of the five do) while
// keeping the same slim-pill proportions — the bar reads taller but not
// noticeably wider/heavier since the label text is small (9px) and the
// icon shrink offsets most of the added height visually.
// Exported so DockCreateButton.jsx (TASK C, 2026-10-03 fix pass) can align
// itself to the exact same vertical band as this bar — "adjacent to the
// existing dock" only reads as true if it shares these two numbers, not
// approximations of them.
export const BAR_HEIGHT = 64;
// Stage 3 (2026-09-27 nav/discovery pass) — bumped back up (20→26) now
// that the text labels below each icon are gone (see the removed
// `dockLabel` span) — the icon itself is the only thing left to read at a
// glance, so it gets the room the labels used to occupy.
const ICON_SIZE = 26;
// BUG 3: sits a little closer to the bottom edge than 64f2719/623ec1e's
// 18px — "shift its resting position lower."
export const BAR_BOTTOM_OFFSET = 10;

// TASK 1 (2026-10-05 fix pass) — the dock and the create-"+" button are now
// ONE laid-out row (see DockRow in App.jsx) sharing a single outer margin
// and gap, instead of each self-positioning independently the way
// `DOCK_MAX_WIDTH`'s own predecessor (a flat 400px `maxWidth` on this bar
// alone) and the button's own `right: 16` used to — on a ~390px iPhone
// viewport that left under 4px of real clearance between them, which is
// the actual overlap this ticket reports. `DOCK_MAX_WIDTH` is an upper
// bound the row's own flexbox can still shrink below on a narrower
// viewport (this bar's items are already `flex`-based, not fixed-width —
// see `items.map` below), not a fixed width.
// BUG 2 (2026-10-07 fix pass) — 300 read as cramped once the shared-
// material/scale fixes made the dock and "+" look properly related.
// Bumped moderately to 340 (still well short of 400, the old overlap-
// causing width) — each tab item already flexes equally
// (`flex: '1 1 0'`), so the extra width spreads evenly across all five
// instead of needing separate per-item spacing logic.
// Stage 3 — widened further (340→380) now that there's no label text to
// wrap/clip; larger icons (26px, up from 20) and 5 equally-flexed items
// both benefit from the extra room, and 380 is still comfortably short of
// the 400px that originally overlapped the "+" button.
export const DOCK_MAX_WIDTH = 380;
export const DOCK_MARGIN = 16;
export const DOCK_GAP = 10;
// Matches BAR_HEIGHT exactly — "shared vertical center" is then structural
// (both controls the same height, centered by the row's own
// `alignItems: 'center'`) instead of two independently-tuned paddings.
export const CREATE_SIZE = BAR_HEIGHT;

export default function BottomTabBar({ collapsed }) {
  const { state, T, goHome, goProfile, goInbox, goNotifications, goMapExplore } = useGoc();
  const s = state;

  // Notifications' badge is s.unreadNotifications (bell inbox, per-account
  // read_at), capped at "9+" — this app's existing convention. Inbox's
  // badge is s.unreadMessages — number of CONVERSATIONS with an unread
  // message (not raw message count, see the poll effect near
  // loadInboxThreads in GocContext.jsx), shown uncapped per this ticket's
  // own ask: unlike a raw message count, a conversation count naturally
  // stays small enough that "9+" would just be hiding real information.
  // Stage 3 (2026-09-27 nav/discovery pass) — visible dock text labels
  // removed entirely (see the icon-only render below); `label` remains
  // the sole source for the accessibility label/VoiceOver announcement.
  const items = useMemo(() => [
    { key: 'home', icon: 'home', onClick: goHome, label: T('Trang chính', 'Home'), testId: 'tab-home', badge: 0, badgeCapped: false },
    { key: 'mapExplore', icon: 'map', onClick: goMapExplore, label: T('Bản đồ', 'Map'), testId: 'tab-map', badge: 0, badgeCapped: false },
    { key: 'notifications', icon: 'notifications', onClick: goNotifications, label: T('Thông báo', 'Notifications'), testId: 'tab-notifications', badge: s.unreadNotifications || 0, badgeCapped: true },
    { key: 'inbox', icon: 'inbox', onClick: goInbox, label: T('Tin nhắn', 'Messages'), testId: 'tab-inbox', badge: s.unreadMessages || 0, badgeCapped: false },
    { key: 'profile', icon: 'profile', onClick: goProfile, label: T('Tài khoản', 'Account'), testId: 'tab-profile', badge: 0, badgeCapped: false },
  ], [goHome, goMapExplore, goNotifications, goInbox, goProfile, T, s.unreadNotifications, s.unreadMessages]);

  // FEATURE — scrub-to-select: press anywhere on the bar and drag; a soft
  // highlight blob follows the finger in real time and lands on whichever
  // icon is currently under it, navigating there on release. A plain tap
  // (pointerdown + pointerup with no meaningful move) resolves to the same
  // tab on both events, so it still works as an ordinary tap.
  const barRef = useRef(null);
  const itemRefs = useRef([]);
  const rectsRef = useRef([]);
  const highlightRef = useRef(null);
  const draggingRef = useRef(false);
  const activeIndexRef = useRef(null);
  const [activeIndex, setActiveIndex] = useState(null);

  // Liquid-glass droplet pass (2026-09-28 follow-up, real-iPhone report) —
  // the drag highlight used to be a SINGLE shape that widened/narrowed
  // ("bulge") as it moved — visually still "a plain oval sliding/
  // teleporting," not the intended liquid-glass metaball. This adds a real
  // two-blob gooey effect for the actual mid-drag state, layered UNDER the
  // existing single-shape highlight (`highlightRef`/`placeHighlight`/
  // `placeHighlightLive` above are untouched and still own: the pre-drag
  // "about to move" bulge before real movement is detected, the settled
  // at-rest state, and the entire Reduce-Motion path). The two blobs:
  // `anchorBlobRef`, pinned at the tab that was ACTIVE before this gesture
  // started (not the tab under the finger at pointerdown — the "neck"
  // needs to stretch back toward the PREVIOUSLY selected tab specifically),
  // and `dragBlobRef`, which tracks the finger continuously. Both are
  // opaque `ink` shapes rendered through a classic SVG "gooey" filter
  // (blur + contrast-boosting color matrix) — solid pixels close together
  // visually fuse into one droplet with a stretchy neck; pull them far
  // enough apart and the neck pinches off on its own, which is exactly the
  // "short elastic neck… before it detaches" behavior asked for, and it's
  // an emergent property of the filter, not something hand-animated frame
  // by frame. The filter's own translucency (matching `dockHighlight`) is
  // applied via a separate, non-filtered wrapper `opacity` — applying it
  // to the blobs themselves would break the filter's opaque-source trick.
  const gooLayerRef = useRef(null);
  const anchorBlobRef = useRef(null);
  const dragBlobRef = useRef(null);
  const pointerStartRef = useRef({ x: 0, y: 0 });
  const gooEngagedRef = useRef(false);
  const anchorIndexRef = useRef(null);
  // Below this many px of pointer travel, a press still reads as a plain
  // tap-in-progress — keeps a real tap instant/gooey-free (per this
  // ticket's own "a plain tap still selects immediately with no gooey
  // animation needed" instruction) without adding a separate tap/drag
  // branch to the existing commit logic below.
  const DRAG_MOVE_THRESHOLD = 4;

  const measure = () => {
    const bar = barRef.current;
    if (!bar) return;
    const barBox = bar.getBoundingClientRect();
    rectsRef.current = itemRefs.current.map((el) => {
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return { left: r.left - barBox.left, width: r.width };
    });
  };

  // BUG (2026-09-25 fix pass) — `measure()` used to only ever re-run on
  // mount and on a `window` `resize` event, so `rectsRef` (the scrub
  // gesture's own item-position cache) went stale any time the BAR ITSELF
  // reflowed for a reason other than the viewport resizing — most
  // concretely, DockRow (App.jsx) toggling `showCreate` off
  // `state.organizerMode`, which changes this bar's own available flex
  // width (the "+" button appearing/disappearing beside it) without ever
  // firing a `resize` event. A `ResizeObserver` on the bar's own element
  // catches every actual layout change to it directly, `resize` or not.
  useEffect(() => {
    measure();
    const bar = barRef.current;
    if (!bar || typeof ResizeObserver === 'undefined') {
      window.addEventListener('resize', measure);
      return () => window.removeEventListener('resize', measure);
    }
    const ro = new ResizeObserver(() => {
      measure();
      // Keep the highlight itself glued to the active tab through the
      // reflow — remeasuring alone only refreshes the cache the NEXT drag
      // reads from; without this it stays visually parked at its old
      // (now wrong) pixel offset until the next tap/drag.
      if (activeIndexRef.current != null) placeHighlight(activeIndexRef.current, false);
    });
    ro.observe(bar);
    return () => ro.disconnect();
  }, [items.length]);

  // BUG 1 fix (623ec1e real-device report): the highlight used to be purely
  // a drag-transient effect — shown only while `draggingRef` was true, and
  // explicitly hidden (opacity 0) the instant the pointer lifted. It needs
  // to sit behind whichever tab is ACTIVE at rest too: after a tap, after a
  // drag release, and on first paint/navigation-from-elsewhere (e.g. a deep
  // link, or a "View details" button that lands on `notifications` without
  // ever touching this bar). This resyncs it to `state.screen` any time
  // that changes, as long as a drag isn't already driving it live.
  useEffect(() => {
    if (draggingRef.current) return;
    const idx = items.findIndex((it) => it.key === s.screen);
    activeIndexRef.current = idx === -1 ? null : idx;
    setActiveIndex(idx === -1 ? null : idx);
    if (idx !== -1) placeHighlight(idx, true);
    else if (highlightRef.current) highlightRef.current.style.opacity = '0';
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [s.screen, items]);

  // Imperative, ref-driven — deliberately NOT React state on every pixel of
  // drag (that's exactly Bug 1's mistake, applied here it would make the
  // scrub gesture itself laggy). Only `transform`/`opacity`/`width` are
  // ever written directly to the DOM node; they're never present in this
  // element's JSX `style` object, so React's own re-renders (triggered by
  // the much rarer `activeIndex` state change below) can't stomp on them.
  // BUG (2026-09-25 fix pass) — root cause of "indicator misaligned after
  // the 340pt dock width change": this used to place the highlight from
  // `rectsRef`, raw `getBoundingClientRect()` pixel rects captured by
  // `measure()`. Two independent problems with that, both real:
  // 1. `rectsRef` only ever refreshed on mount/window-resize (see that
  //    effect's own comment) — any OTHER reflow of the bar itself (most
  //    concretely, DockRow's create-"+" button appearing/disappearing with
  //    `state.organizerMode`, which changes this bar's own flex width with
  //    no `resize` event) left it stale, so this drew the highlight at an
  //    old, wrong offset. Bumping `DOCK_MAX_WIDTH` 300→340 didn't cause
  //    this — it just made every stale-pixel error bigger and therefore
  //    visible.
  // 2. `getBoundingClientRect()` returns POST-transform (screen) rects.
  //    DockRow's collapse/expand `scale()` sits on an ANCESTOR of this bar,
  //    so `rect.left`/`rect.width` already have that scale factor baked in
  //    — applying them again as this (descendant) element's own
  //    `transform`/`width` double-applies the scale (a `scale(0.86)`
  //    ancestor turned into an effective 0.86² on the highlight alone),
  //    visibly drifting the indicator off-center specifically while the
  //    dock is collapsed/expanding.
  // Fixed by dropping pixel measurement for PLACEMENT entirely: every item
  // is an equal `flex: '1 1 0'` slice of the bar with zero gap between them
  // (see the items' own style below), so "item i's box" is exactly the i-th
  // 1/items.length share of the bar — expressed as CSS percentages, which
  // resolve against this element's own LOCAL (pre-transform, pre-ancestor-
  // scale) layout box. That's immune to both problems above: it needs no
  // measured rect at all (immune to stale `rectsRef`), and a percentage
  // `translateX`/`width` is computed before any ancestor `transform` is
  // applied (immune to the collapse-scale double-application). `rectsRef`
  // is kept only for `hitTest` below, which maps a real screen-space touch
  // point to an index — that one genuinely needs live pixel rects.
  const reduceMotionQuery = () => typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

  const placeHighlight = (index, animate) => {
    const el = highlightRef.current;
    if (!el || index == null || !items.length) return;
    const pct = 100 / items.length;
    // Stage 3 (2026-09-27 nav/discovery pass) — honors Reduce Motion: the
    // spring glide becomes a plain, near-instant snap (still fades in via
    // opacity, which isn't the kind of motion that setting asks to avoid).
    const reduceMotion = reduceMotionQuery();
    const glide = reduceMotion ? 'transform 0.01s linear' : 'transform 0.32s cubic-bezier(.34,1.56,.64,1)';
    el.style.transition = animate ? `${glide}, opacity 0.15s ease, width 0.28s cubic-bezier(.34,1.56,.64,1)` : 'opacity 0.15s ease';
    el.style.width = `${pct}%`;
    el.style.transform = `translateX(${index * 100}%)`;
    el.style.opacity = '1';
  };

  // Dock-drag fix pass (2026-09-27, follow-up B) — the actual root cause of
  // "dragging the selected region jumps from slot to slot": `onPointerMove`
  // used to run `hitTest` (nearest-ICON lookup) and only ever call
  // `placeHighlight(idx, true)` — a discrete, whole-slot placement that
  // animates via a fixed CSS transition. Nothing in that path reads the
  // finger's continuous x position; the highlight sits still until the
  // finger crosses a slot's midpoint, then springs to the next slot. This
  // is the replacement: a SEPARATE continuous placement path (no CSS
  // transition, no waiting for a slot boundary) that runs on every
  // `pointermove`, and interpolates a soft "droplet" bulge — the blob is at
  // its narrowest (resting width) exactly centered on a slot and at its
  // widest exactly halfway between two, so it visibly stretches through
  // the gap instead of teleporting. `placeHighlight` above is now used only
  // to SETTLE once, on release/tap.
  const BULGE = 0.5;
  const placeHighlightLive = (pct) => {
    const el = highlightRef.current;
    if (!el || !items.length) return;
    const slot = 100 / items.length;
    const clampedPct = Math.max(0, Math.min(100, pct));
    const idxFloat = Math.max(0, Math.min(items.length - 1, clampedPct / slot));
    // 0 exactly on a slot's own center, 0.5 exactly between two slots.
    const fracFromCenter = Math.abs(idxFloat - Math.round(idxFloat));
    const bulge = 1 + BULGE * Math.sin(Math.min(1, fracFromCenter / 0.5) * (Math.PI / 2));
    const width = slot * bulge;
    const centerPct = (idxFloat + 0.5) * slot;
    const left = Math.max(0, Math.min(100 - width, centerPct - width / 2));
    el.style.transition = 'opacity 0.15s ease';
    el.style.width = `${width}%`;
    el.style.transform = `translateX(${left}%)`;
    el.style.opacity = '1';
  };

  const setGooVisible = (visible) => {
    const el = gooLayerRef.current;
    if (!el) return;
    el.style.opacity = visible ? '1' : '0';
  };

  const placeAnchorBlob = (index) => {
    const el = anchorBlobRef.current;
    if (!el || index == null || !items.length) return;
    const slot = 100 / items.length;
    el.style.width = `${slot * 0.82}%`;
    el.style.left = `${(index + 0.5) * slot}%`;
    el.style.transform = 'translateX(-50%)';
  };

  const placeDragBlob = (pct) => {
    const el = dragBlobRef.current;
    if (!el || !items.length) return;
    const slot = 100 / items.length;
    const clampedPct = Math.max(slot * 0.32, Math.min(100 - slot * 0.32, pct));
    el.style.width = `${slot * 0.64}%`;
    el.style.left = `${clampedPct}%`;
    el.style.transform = 'translateX(-50%)';
  };

  const percentForClientX = (clientX) => {
    const bar = barRef.current;
    if (!bar) return 0;
    const box = bar.getBoundingClientRect();
    return ((clientX - box.left) / box.width) * 100;
  };

  const hitTest = (clientX) => {
    const bar = barRef.current;
    if (!bar) return 0;
    const x = clientX - bar.getBoundingClientRect().left;
    let closest = 0;
    let closestDist = Infinity;
    rectsRef.current.forEach((r, i) => {
      if (!r) return;
      const dist = Math.abs(r.left + r.width / 2 - x);
      if (dist < closestDist) { closestDist = dist; closest = i; }
    });
    return closest;
  };

  const onPointerDown = (e) => {
    measure();
    barRef.current?.setPointerCapture?.(e.pointerId);
    draggingRef.current = true;
    gooEngagedRef.current = false;
    pointerStartRef.current = { x: e.clientX, y: e.clientY };
    // Captured BEFORE this gesture's own hitTest overwrites
    // `activeIndexRef` — the tab that was selected going into this press,
    // i.e. where the droplet's neck anchors if this turns into a real
    // drag (see the goo-layer comment above `gooLayerRef`).
    anchorIndexRef.current = activeIndexRef.current;
    const idx = hitTest(e.clientX);
    activeIndexRef.current = idx;
    setActiveIndex(idx);
    if (reduceMotionQuery()) {
      placeHighlight(idx, false);
    } else {
      placeHighlightLive(percentForClientX(e.clientX));
    }
  };

  const onPointerMove = (e) => {
    if (!draggingRef.current) return;
    const idx = hitTest(e.clientX);
    if (idx !== activeIndexRef.current) {
      activeIndexRef.current = idx;
      setActiveIndex(idx);
    }
    // Reduce Motion: a plain non-bouncy snap between slots, never the
    // continuous stretch/goo (that IS the motion this setting asks to
    // avoid) — falls straight through to the pre-existing discrete path.
    if (reduceMotionQuery()) {
      placeHighlight(idx, true);
      return;
    }
    const dx = e.clientX - pointerStartRef.current.x;
    const dy = e.clientY - pointerStartRef.current.y;
    const movedEnough = Math.hypot(dx, dy) > DRAG_MOVE_THRESHOLD;
    if (movedEnough) {
      if (!gooEngagedRef.current) {
        gooEngagedRef.current = true;
        placeAnchorBlob(anchorIndexRef.current != null ? anchorIndexRef.current : idx);
        setGooVisible(true);
        // Hand off from the single-shape bulge to the two-blob droplet —
        // hidden, not unmounted, so it's already correctly positioned and
        // just needs an opacity fade back in once the gesture settles.
        if (highlightRef.current) highlightRef.current.style.opacity = '0';
      }
      placeDragBlob(percentForClientX(e.clientX));
    } else {
      placeHighlightLive(percentForClientX(e.clientX));
    }
  };

  // BUG 1 fix: no longer hides the highlight on release — it stays exactly
  // where the drag landed (the tab being navigated to), so it reads as
  // "this is now the active tab" instead of flashing away. If the tapped
  // tab is already the current screen, `state.screen` won't change and the
  // effect above won't refire, which is fine: the highlight is already
  // sitting in the right place from the drag/tap itself.
  const endDrag = () => {
    if (!draggingRef.current) return;
    draggingRef.current = false;
    const idx = activeIndexRef.current;
    if (gooEngagedRef.current) {
      // Droplet fully detaches and merges into the destination tab: fade
      // the two-blob layer out while the classic single-shape highlight
      // (already hidden, mid-drag) crossfades back in via `placeHighlight`
      // below — a settle, not a hard cut.
      setGooVisible(false);
      gooEngagedRef.current = false;
    }
    // Settles the SAME blob smoothly into the existing at-rest look — the
    // continuous drag placement above never uses this element's normal
    // transition, so without this final call it would stay stretched/
    // off-slot instead of visibly relaxing into the selected tab.
    placeHighlight(idx, true);
    if (idx != null && items[idx]) items[idx].onClick();
  };

  // Cancelled drag (pointercancel, e.g. an interrupting system gesture)
  // returns to the tab that was actually active before the drag started —
  // never commits a navigation.
  const cancelDrag = () => {
    if (!draggingRef.current) return;
    draggingRef.current = false;
    if (gooEngagedRef.current) {
      setGooVisible(false);
      gooEngagedRef.current = false;
    }
    const idx = items.findIndex((it) => it.key === s.screen);
    activeIndexRef.current = idx === -1 ? null : idx;
    setActiveIndex(idx === -1 ? null : idx);
    if (idx !== -1) placeHighlight(idx, true);
  };

  return (
    <div
      ref={barRef}
      data-testid="bottom-tab-bar"
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={endDrag}
      onPointerCancel={cancelDrag}
      style={{
        ...barGlass({}),
        position: 'relative',
        // TASK 1 (2026-10-05 fix pass) — flex child of DockRow (App.jsx)
        // now, not a self-positioned/self-sized element — `flex: 1 1 auto`
        // + `minWidth: 0` is what lets it actually shrink below
        // `DOCK_MAX_WIDTH` when the row (dock + gap + "+" button) doesn't
        // fit the viewport, instead of clipping/overflowing.
        flex: '1 1 auto', minWidth: 0, maxWidth: DOCK_MAX_WIDTH,
        borderRadius: 999,
        height: BAR_HEIGHT, boxShadow: '0 8px 24px rgba(27,25,22,0.18)',
        display: 'flex', justifyContent: 'space-around', alignItems: 'center',
        touchAction: 'none',
        // BUG (2026-10-06 fix pass) — the shrink-on-scroll `transform:
        // scale()` used to live HERE, scoped to just this pill's own div.
        // Since DockRow (App.jsx) lays this out as one flex row sibling of
        // DockCreateButton, scaling only THIS child meant the dock visibly
        // shrank on scroll while the "+" beside it stayed full size —
        // exactly the reported "dock changes size but + stays large."
        // Moved to DockRow's own outer div (App.jsx), so a single transform
        // scales both controls together as one unit — matches this
        // ticket's own "keep both in the same layout/animation state"
        // instruction. `collapsed` itself is now unused here but kept as a
        // prop for API compatibility with existing call sites/tests.
      }}
    >
        <svg width="0" height="0" style={{ position: 'absolute' }} aria-hidden="true" focusable="false">
          <filter id="bb-dock-goo" x="-60%" y="-60%" width="220%" height="220%">
            {/* Classic "gooey" filter: blur softens/merges nearby opaque
                shapes, the color matrix's steep alpha slope (20/-9) then
                sharpens the result back to a crisp edge everywhere except
                where two blurred shapes actually overlap — that overlap
                region is the elastic "neck." stdDeviation is tuned to
                connect across roughly one dock slot's width so the neck
                visibly pinches off once the finger travels much further
                than that, rather than staying connected across the whole
                bar. */}
            <feGaussianBlur in="SourceGraphic" stdDeviation="7" result="bb-goo-blur" />
            <feColorMatrix in="bb-goo-blur" mode="matrix" values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 20 -9" result="bb-goo-sharp" />
          </filter>
        </svg>
        <div
          ref={gooLayerRef}
          data-testid="dock-goo-layer"
          style={{
            position: 'absolute', top: 8, bottom: 8, left: 0, right: 0,
            opacity: 0, pointerEvents: 'none', zIndex: 0,
            transition: 'opacity 0.16s ease',
          }}
        >
          {/* Translucency (matches `dockHighlight`) is applied HERE, on a
              plain unfiltered wrapper — applying it directly to the blobs
              below would feed the goo filter semi-transparent source
              pixels and break its opaque-shape contrast trick. */}
          <div style={{ position: 'absolute', inset: 0, opacity: 0.16 }}>
            <div style={{ position: 'absolute', inset: 0, filter: 'url(#bb-dock-goo)', isolation: 'isolate' }}>
              <div
                ref={anchorBlobRef}
                data-testid="dock-goo-anchor"
                style={{ position: 'absolute', top: 0, height: '100%', borderRadius: 999, background: ink, willChange: 'left, width' }}
              />
              <div
                ref={dragBlobRef}
                data-testid="dock-goo-drag"
                style={{ position: 'absolute', top: 0, height: '100%', borderRadius: 999, background: ink, willChange: 'left, width' }}
              />
            </div>
          </div>
        </div>
        <div
          ref={highlightRef}
          data-testid="dock-highlight"
          style={{
            position: 'absolute', top: 8, bottom: 8, left: 0, borderRadius: 999,
            // Web "black blob" bug (2026-09-28 dock pass) — this used to be
            // solid `background: ink` at full element opacity: since the
            // ACTIVE tab's own icon is also drawn in `ink`, an opaque ink
            // backdrop roughly the icon's own size visually swallowed the
            // icon into itself instead of sitting as a subtle backdrop
            // behind it. `dockHighlight` is a translucent tint (matches
            // iOS's already-correct `ink.opacity(0.12)` — iOS never had
            // this bug). `zIndex: 0` (explicit, not relied-on `auto`) plus
            // each tab item's own `zIndex: 1` below is what keeps this
            // element BEHIND the icons regardless of DOM order.
            background: dockHighlight, opacity: 0, pointerEvents: 'none', zIndex: 0,
            boxShadow: 'inset 0 1px 2px rgba(0,0,0,0.1)', filter: 'blur(0.3px)',
            willChange: 'transform',
          }}
        />
        {items.map((item, i) => (
          <div
            key={item.key}
            ref={(el) => { itemRefs.current[i] = el; }}
            data-testid={item.testId}
            aria-label={item.label}
            role="tab"
            aria-selected={activeIndex === i}
            style={{
              position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center',
              flex: '1 1 0', minWidth: 44, minHeight: 44, height: '100%', zIndex: 1,
            }}
          >
            <div style={{ position: 'relative', width: ICON_SIZE, height: ICON_SIZE, opacity: activeIndex === i ? 1 : 0.72 }}>
              {ICONS[item.icon](ink, activeIndex === i)}
              {item.badge > 0 && (
                <span
                  style={{
                    position: 'absolute', top: -5, right: -7, minWidth: 14, height: 14, padding: '0 3px',
                    borderRadius: 7, background: alert, color: '#fff', fontSize: 9, fontWeight: 700,
                    lineHeight: '14px', textAlign: 'center',
                  }}
                >
                  {item.badgeCapped && item.badge > 9 ? '9+' : item.badge}
                </span>
              )}
            </div>
          </div>
        ))}
    </div>
  );
}

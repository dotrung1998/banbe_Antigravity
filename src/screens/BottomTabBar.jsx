import { useEffect, useMemo, useRef, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { ink, alert, barGlass } from '../theme.js';

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
const ICONS = {
  map: (c) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <path d="M12 3c-3.3 0-6 2.6-6 6.1C6 13.4 12 21 12 21s6-7.6 6-11.9C18 5.6 15.3 3 12 3z" fill="none" stroke={c} strokeWidth="2.4" strokeLinejoin="round" strokeLinecap="round" />
      <circle cx="12" cy="9.3" r="2.3" fill={c} />
    </svg>
  ),
  notifications: (c) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <path d="M12 3.5c-2.8 0-5 2.2-5 5v4.6l-1.6 2.7c-.3.5.1 1.2.7 1.2h11.8c.6 0 1-.7.7-1.2L17 13.1V8.5c0-2.8-2.2-5-5-5z" fill={c} />
      <path d="M9.6 18.6a2.4 2.4 0 0 0 4.8 0" stroke={c} strokeWidth="2" strokeLinecap="round" fill="none" />
    </svg>
  ),
  inbox: (c) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <rect x="4.5" y="7" width="15" height="11" rx="2.4" fill="none" stroke={c} strokeWidth="2.4" />
      <path d="M5.5 8.2 L12 13.5 L18.5 8.2" fill="none" stroke={c} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  ),
  profile: (c) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <circle cx="12" cy="8" r="3.8" fill="none" stroke={c} strokeWidth="2.6" />
      <path d="M5 19.2c1.3-3.9 4.2-5.8 7-5.8s5.7 1.9 7 5.8" stroke={c} strokeWidth="2.6" strokeLinecap="round" fill="none" />
    </svg>
  ),
  // Task 1b follow-up: a straightforward addition to the existing icon set
  // — same stroke weight (2.4-2.6) and rounded joins as the other four, a
  // plain house silhouette. Unlike the map icon's own earlier "avoid the
  // classic filled house outline" constraint (about not using a house FOR
  // a map glyph), a house for an actual Home tab is the universally
  // understood, semantically correct choice, not a borrowed IG/FB/Twitter
  // shape (none of those three put a house on a Home-equivalent tab).
  home: (c) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <path d="M4 11.5 12 4l8 7.5" fill="none" stroke={c} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M6 10v9.5h12V10" fill="none" stroke={c} strokeWidth="2.4" strokeLinejoin="round" />
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
const BAR_HEIGHT = 54;
const ICON_SIZE = 24;
// BUG 3: sits a little closer to the bottom edge than 64f2719/623ec1e's
// 18px — "shift its resting position lower."
const BAR_BOTTOM_OFFSET = 10;

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

  useEffect(() => {
    measure();
    window.addEventListener('resize', measure);
    return () => window.removeEventListener('resize', measure);
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
  const placeHighlight = (index, animate) => {
    const el = highlightRef.current;
    const rect = rectsRef.current[index];
    if (!el || !rect) return;
    el.style.transition = animate ? 'transform 0.18s cubic-bezier(.34,1.56,.64,1), opacity 0.15s ease' : 'opacity 0.15s ease';
    el.style.transform = `translateX(${rect.left}px)`;
    el.style.width = `${rect.width}px`;
    el.style.opacity = '1';
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
    const idx = hitTest(e.clientX);
    activeIndexRef.current = idx;
    setActiveIndex(idx);
    placeHighlight(idx, false);
  };

  const onPointerMove = (e) => {
    if (!draggingRef.current) return;
    const idx = hitTest(e.clientX);
    if (idx !== activeIndexRef.current) {
      activeIndexRef.current = idx;
      setActiveIndex(idx);
      placeHighlight(idx, true);
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
    if (idx != null && items[idx]) items[idx].onClick();
  };

  return (
    <div
      data-testid="bottom-tab-bar"
      style={{
        ...barGlass({}),
        position: 'absolute', left: '50%', bottom: BAR_BOTTOM_OFFSET,
        // Task 1b follow-up: widened from 320 (fit for 4 icons) to fit the
        // new Home tab without cramping the existing four. Task 5: widened
        // again (360→400) as part of the flatter/more-elongated shape,
        // margins narrowed 56→40 (28px/side → 20px/side) to match.
        width: 'calc(100% - 40px)', maxWidth: 400,
        borderRadius: 999,
        // BUG 2 follow-up (623ec1e real-device report): the bar was already
        // meant to paint above MapExplore's own content by plain document
        // order (BottomTabBar is a later sibling of the screen container in
        // Shell — see App.jsx), and MapExplore's own floating pills/sheet
        // never go above zIndex 3, so 20 already had headroom on paper. It
        // was still getting hidden on a real device — MapLibre's WebGL
        // canvas is the one part of this screen whose compositing isn't
        // guaranteed to respect ordinary DOM z-index the way plain HTML
        // layers do. Bumped to 25: comfortably clear of anything MapExplore
        // itself uses, but deliberately still under Notifications.jsx's own
        // full-screen action-sheet scrim (`zIndex: 30`) so that scrim still
        // dims the bar along with everything else while it's open.
        zIndex: 25,
        height: BAR_HEIGHT, boxShadow: '0 8px 24px rgba(27,25,22,0.18)',
        // BUG 1 follow-up: the shrink-on-scroll effect used to change
        // `height` and each icon's own `width`/`height` directly — layout
        // properties that force a reflow every time. A single `transform:
        // scale()` on the whole pill is compositor-only (no re-layout),
        // which is both cheaper and reads smoother; see App.jsx's Shell for
        // the matching rAF-throttled scroll handler that drives `collapsed`.
        transform: `translateX(-50%) scale(${collapsed ? 0.86 : 1})`,
        transformOrigin: 'center bottom',
        transition: 'transform 0.28s cubic-bezier(.22,.61,.36,1)',
      }}
    >
      <div
        ref={barRef}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={endDrag}
        onPointerCancel={endDrag}
        style={{ position: 'relative', display: 'flex', justifyContent: 'space-around', alignItems: 'center', width: '100%', height: '100%', touchAction: 'none' }}
      >
        <div
          ref={highlightRef}
          style={{
            position: 'absolute', top: 8, bottom: 8, left: 0, borderRadius: 999,
            background: ink, opacity: 0, pointerEvents: 'none',
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
            style={{ position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center', width: 44, height: '100%', zIndex: 1 }}
          >
            <div style={{ width: ICON_SIZE, height: ICON_SIZE, opacity: activeIndex === i ? 1 : 0.86 }}>
              {ICONS[item.icon](ink)}
            </div>
            {item.badge > 0 && (
              <span
                style={{
                  position: 'absolute', top: 4, right: 2, minWidth: 14, height: 14, padding: '0 3px',
                  borderRadius: 7, background: alert, color: '#fff', fontSize: 9, fontWeight: 700,
                  lineHeight: '14px', textAlign: 'center',
                }}
              >
                {item.badgeCapped && item.badge > 9 ? '9+' : item.badge}
              </span>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

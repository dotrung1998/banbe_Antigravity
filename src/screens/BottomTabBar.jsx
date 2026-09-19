import { useEffect, useMemo, useRef, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { ink, alert, barGlass } from '../theme.js';

// BUG 2 follow-up (64f2719 real-device report): each glyph dropped to at
// most 2-3 path elements (Notifications lost its faint secondary arc) and
// is drawn bigger relative to its own 24-unit box, so it reads at a glance
// instead of needing a second look. Same ring/diagonal-stroke/dot
// vocabulary as before (public/banbe-mark.png), not a new direction — see
// 06-design-tokens.md's "Bottom tab bar" section for the original rationale.
const ICONS = {
  map: (c) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <path d="M6.5 18 L15.5 7" stroke={c} strokeWidth="2.6" strokeLinecap="round" fill="none" />
      <circle cx="16.8" cy="5.6" r="2.7" fill={c} />
    </svg>
  ),
  notifications: (c) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <circle cx="12" cy="16.5" r="2.1" fill={c} />
      <path d="M7.3 12a6.6 6.6 0 0 1 9.4 0" fill="none" stroke={c} strokeWidth="2.6" strokeLinecap="round" />
    </svg>
  ),
  inbox: (c) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <circle cx="7" cy="9" r="2.4" fill={c} />
      <circle cx="17" cy="15" r="2.4" fill={c} />
      <path d="M9.3 10.8 Q13 12 14.7 13.2" stroke={c} strokeWidth="2.4" strokeLinecap="round" fill="none" />
    </svg>
  ),
  profile: (c) => (
    <svg viewBox="0 0 24 24" width="100%" height="100%">
      <circle cx="12" cy="8" r="3.8" fill="none" stroke={c} strokeWidth="2.6" />
      <path d="M5 19.2c1.3-3.9 4.2-5.8 7-5.8s5.7 1.9 7 5.8" stroke={c} strokeWidth="2.6" strokeLinecap="round" fill="none" />
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

// BUG 2: bumped from 22/19 (expanded/collapsed) to one fixed, bigger size —
// the shrink-on-scroll effect is now a uniform CSS `transform: scale()` on
// the whole bar (see the outer style below), not a per-icon size change, so
// the icons themselves stay crisp at every scale factor.
const BAR_HEIGHT = 64;
const ICON_SIZE = 27;

export default function BottomTabBar({ collapsed }) {
  const { state, T, goProfile, goInbox, goNotifications, goMapExplore } = useGoc();
  const s = state;

  // Inbox/messages has no unread-tracking concept anywhere in the schema
  // (no read_at on `messages`, no per-thread unread flag) — confirmed via
  // grep before writing this, so no badge is fabricated for it. Only
  // Notifications has a real unread count (s.unreadNotifications, already
  // used by the old header bell).
  const items = useMemo(() => [
    { key: 'mapExplore', icon: 'map', onClick: goMapExplore, label: T('Bản đồ', 'Map'), testId: 'tab-map', badge: 0 },
    { key: 'notifications', icon: 'notifications', onClick: goNotifications, label: T('Thông báo', 'Notifications'), testId: 'tab-notifications', badge: s.unreadNotifications || 0 },
    { key: 'inbox', icon: 'inbox', onClick: goInbox, label: T('Tin nhắn', 'Messages'), testId: 'tab-inbox', badge: 0 },
    { key: 'profile', icon: 'profile', onClick: goProfile, label: T('Tài khoản', 'Account'), testId: 'tab-profile', badge: 0 },
  ], [goMapExplore, goNotifications, goInbox, goProfile, T, s.unreadNotifications]);

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

  const endDrag = () => {
    if (!draggingRef.current) return;
    draggingRef.current = false;
    const idx = activeIndexRef.current;
    if (idx != null && items[idx]) items[idx].onClick();
    if (highlightRef.current) highlightRef.current.style.opacity = '0';
    activeIndexRef.current = null;
    setActiveIndex(null);
  };

  return (
    <div
      data-testid="bottom-tab-bar"
      style={{
        ...barGlass({}),
        position: 'absolute', left: '50%', bottom: 18,
        width: 'calc(100% - 56px)', maxWidth: 320,
        borderRadius: 999, zIndex: 20,
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
                {item.badge > 9 ? '9+' : item.badge}
              </span>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

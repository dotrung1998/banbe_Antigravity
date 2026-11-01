// Map v6 (note 74): one sideways photo pager for event cards (Map Large cards, Home's card layout). iOS twin:
// apps/ios/BanbeApp/Views/PhotoPager.swift.
//
// - A CSS scroll-snap track: touch and trackpads scroll it natively; a mouse can drag it (desktop); ‹ › buttons show
//   on hover / keyboard focus; ArrowLeft / ArrowRight move one photo. Reduce Motion = no smooth scrolling.
// - `data-hscroll="true"` on the track: App.jsx's root tab swipe never turns a photo swipe into a dock-tab switch.
//   `overscroll-behavior-x: contain` keeps the last photo's overscroll from scrolling anything behind it.
// - Bandwidth (notes 22 / 40): only the visible photo and the next one load eagerly, the rest lazily as you reach them.
// - A tap (no drag) calls `onOpen`; a drag never does. One photo = a plain image (no dots, no counter, no arrows).
import { useCallback, useEffect, useRef, useState } from 'react';

const reduceMotion = () => typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
const DRAG_PX = 6; // a mouse moving more than this is a drag, not a tap

export default function PhotoPager({ id, imgs, T, height = '100%', radius = 14, onOpen, label = '', children }) {
  const photos = (imgs || []).filter(Boolean);
  const n = photos.length;
  const trackRef = useRef(null);
  const [index, setIndex] = useState(0);
  const [hover, setHover] = useState(false);
  const [focusIn, setFocusIn] = useState(false);
  const drag = useRef(null); // { x, left, moved } while a mouse drags the track
  const suppressClick = useRef(false);

  const pageW = () => Math.max(1, trackRef.current?.clientWidth || 1);
  const go = useCallback((to) => {
    const el = trackRef.current;
    if (!el) return;
    const i = Math.max(0, Math.min(n - 1, to));
    el.scrollTo({ left: i * pageW(), behavior: reduceMotion() ? 'auto' : 'smooth' });
    setIndex(i);
  }, [n]);
  const onScroll = () => {
    const el = trackRef.current;
    if (!el) return;
    const i = Math.max(0, Math.min(n - 1, Math.round(el.scrollLeft / pageW())));
    if (i !== index) setIndex(i);
  };

  // Mouse drag (desktop): moves the track by hand, then snaps to the nearest photo (or the next one past 30 px).
  const onPointerDown = (e) => {
    if (e.pointerType !== 'mouse' || e.button !== 0 || n < 2) return;
    const el = trackRef.current;
    // `page` is the photo shown now, not one read from scrollLeft: a drag that starts while an arrow's smooth scroll
    // is still running would otherwise count from a half-way position and land back on the same photo.
    drag.current = { x: e.clientX, left: el.scrollLeft, page: index, moved: false };
    el.style.scrollSnapType = 'none';
  };
  useEffect(() => {
    if (n < 2) return undefined;
    const move = (e) => {
      const d = drag.current;
      if (!d) return;
      const dx = e.clientX - d.x;
      if (Math.abs(dx) > DRAG_PX) d.moved = true;
      if (trackRef.current) trackRef.current.scrollLeft = d.left - dx;
    };
    const up = (e) => {
      const d = drag.current;
      if (!d) return;
      drag.current = null;
      const el = trackRef.current;
      if (!el) return;
      el.style.scrollSnapType = '';
      if (d.moved) {
        suppressClick.current = true;
        const dx = e.clientX - d.x;
        const base = d.page;
        go(base + (Math.abs(dx) > 30 ? (dx < 0 ? 1 : -1) : 0));
      }
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
    return () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); };
  }, [n, go]);

  const onClick = (e) => {
    if (suppressClick.current) { suppressClick.current = false; e.stopPropagation(); e.preventDefault(); return; }
    if (onOpen) { e.stopPropagation(); onOpen(); }
  };
  const onKeyDown = (e) => {
    if (e.key === 'ArrowRight') { e.preventDefault(); e.stopPropagation(); go(index + 1); }
    else if (e.key === 'ArrowLeft') { e.preventDefault(); e.stopPropagation(); go(index - 1); }
  };

  if (!n) return null;
  const img = (src, i) => (
    <img src={src} alt={n > 1 ? T(`Ảnh ${i + 1} / ${n}`, `Photo ${i + 1} of ${n}`) : label}
      // The visible photo and the next one load now; the rest when the pager gets near them.
      loading={i <= index + 1 ? 'eager' : 'lazy'} decoding="async" draggable={false}
      style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block', pointerEvents: 'none', userSelect: 'none' }} />
  );
  if (n === 1) {
    return (
      <div data-testid={`photo-pager-${id}`} data-index={0} onClick={onClick} style={{ position: 'relative', width: '100%', height, borderRadius: radius, overflow: 'hidden' }}>
        {img(photos[0], 0)}
        {children}
      </div>
    );
  }
  const showArrows = hover || focusIn;
  const arrow = (dir) => ({
    position: 'absolute', top: '50%', [dir < 0 ? 'left' : 'right']: 8, transform: 'translateY(-50%)', width: 32, height: 32, borderRadius: 16,
    border: 'none', background: 'rgba(var(--bb-bg-rgb),0.86)', color: 'var(--bb-fg)', boxShadow: '0 1px 4px rgba(27,25,22,0.28)',
    display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', padding: 0,
    opacity: showArrows ? 1 : 0, pointerEvents: showArrows ? 'auto' : 'none', transition: 'opacity 0.15s ease',
  });
  return (
    <div data-testid={`photo-pager-${id}`} data-index={index}
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      onFocus={() => setFocusIn(true)} onBlur={(e) => { if (!e.currentTarget.contains(e.relatedTarget)) setFocusIn(false); }}
      style={{ position: 'relative', width: '100%', height, borderRadius: radius, overflow: 'hidden' }}>
      <div ref={trackRef} data-hscroll="true" className="bb-pager-track" tabIndex={0} role="group"
        aria-roledescription={T('bộ ảnh', 'carousel')}
        aria-label={(label ? label + ', ' : '') + T(`Ảnh ${index + 1} / ${n}`, `Photo ${index + 1} of ${n}`)}
        onScroll={onScroll} onPointerDown={onPointerDown} onClick={onClick} onKeyDown={onKeyDown}
        style={{
          display: 'flex', width: '100%', height: '100%', overflowX: 'auto', overflowY: 'hidden', scrollSnapType: 'x mandatory',
          overscrollBehaviorX: 'contain', scrollbarWidth: 'none', touchAction: 'pan-x pan-y', cursor: 'pointer', outline: 'none',
        }}>
        {photos.map((src, i) => (
          <div key={src + i} aria-hidden={i !== index ? true : undefined} style={{ flex: '0 0 100%', height: '100%', scrollSnapAlign: 'center', scrollSnapStop: 'always' }}>
            {img(src, i)}
          </div>
        ))}
      </div>
      {children}
      <span data-testid={`photo-pager-counter-${id}`} aria-hidden="true"
        style={{ position: 'absolute', right: 10, bottom: 10, padding: '3px 8px', borderRadius: 999, background: 'rgba(12,12,12,0.55)', color: '#fff', fontSize: 11, fontWeight: 600, fontVariantNumeric: 'tabular-nums', pointerEvents: 'none' }}>
        {index + 1}/{n}
      </span>
      <div aria-hidden="true" style={{ position: 'absolute', left: 0, right: 0, bottom: 5, display: 'flex', justifyContent: 'center', gap: 5, pointerEvents: 'none' }}>
        {photos.map((_, i) => (
          <i key={i} style={{ width: 6, height: 6, borderRadius: 3, background: '#fff', opacity: i === index ? 1 : 0.5, boxShadow: '0 0 2px rgba(0,0,0,0.45)', transition: 'opacity 0.15s ease' }} />
        ))}
      </div>
      <button type="button" data-testid={`photo-pager-prev-${id}`} aria-label={T('Ảnh trước', 'Previous photo')} disabled={index === 0}
        onClick={(e) => { e.stopPropagation(); go(index - 1); }} style={{ ...arrow(-1), ...(index === 0 ? { opacity: 0, pointerEvents: 'none' } : null) }}>
        <svg aria-hidden="true" width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round"><path d="m15 5-7 7 7 7" /></svg>
      </button>
      <button type="button" data-testid={`photo-pager-next-${id}`} aria-label={T('Ảnh tiếp theo', 'Next photo')} disabled={index === n - 1}
        onClick={(e) => { e.stopPropagation(); go(index + 1); }} style={{ ...arrow(1), ...(index === n - 1 ? { opacity: 0, pointerEvents: 'none' } : null) }}>
        <svg aria-hidden="true" width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round"><path d="m9 5 7 7-7 7" /></svg>
      </button>
    </div>
  );
}

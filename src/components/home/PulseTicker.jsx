import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { ink, fieldGlass, RADIUS } from '../../theme.js';
import { tickerItems, tickerSeconds } from '../../lib/pulseTicker.js';

// Banbe Pulse as one slim line at the top of Home (note 51), replacing the big Pulse tile that used to sit in the
// story row and left a tall empty band whenever there were no stories. A "✦ Pulse" chip (same gradient as the old
// ring) then today's top events scrolling past like a news ticker, then a chevron. Tapping anywhere opens the Pulse
// viewer, exactly like the old tile did. iOS twin: Views/PulseTickerView.swift.
//
// - Data is the daily Banbe Pulse ranking (goc_pulse_ranked, already loaded for the "Popular" sort): never invented.
//   With no ranking yet the line is a static invitation, not an empty box.
// - Motion: a CSS marquee over two identical copies (translateX 0 -> -50% loops with no jump). It pauses on hover /
//   keyboard focus, and `prefers-reduced-motion` turns it into a single static line with an ellipsis.
// - Speed is proportional to the text length (a fixed reading-speed feel), never faster for short lists.
//   The item list and the speed come from src/lib/pulseTicker.js (unit-tested; iOS twin in Lib/PulseTicker.swift).
export default function PulseTicker({ pulse, onOpen, T }) {
  const items = tickerItems(pulse);
  const trackRef = useRef(null);
  const [trackW, setTrackW] = useState(0);
  const [reduceMotion] = useState(() => typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches);
  useLayoutEffect(() => {
    const el = trackRef.current;
    if (!el) return undefined;
    setTrackW(el.clientWidth);
    if (typeof ResizeObserver === 'undefined') return undefined;
    const ro = new ResizeObserver(() => setTrackW(el.clientWidth));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  // Re-measure when the strip changes from placeholder to real content (its own width does not change, but be safe).
  useEffect(() => { if (trackRef.current) setTrackW(trackRef.current.clientWidth); }, [items.length]);

  const label = items.length
    ? T(`Banbe Pulse. Top sự kiện: ${items.map(i => i.name).join(', ')}. Mở`, `Banbe Pulse. Top events: ${items.map(i => i.name).join(', ')}. Open`)
    : T('Banbe Pulse. Xem điều gì đang hot. Mở', "Banbe Pulse. See what's trending. Open");

  const copy = (hidden) => (
    <span aria-hidden={hidden || undefined} style={{ display: 'inline-flex', alignItems: 'center', flex: 'none', minWidth: trackW || undefined, paddingRight: 28 }}>
      {items.map(it => (
        <span key={it.id} style={{ display: 'inline-flex', alignItems: 'baseline', gap: 6, marginRight: 22 }}>
          <b style={{ fontSize: 12, opacity: 0.55, fontVariantNumeric: 'tabular-nums' }}>{it.rank}</b>
          <span style={{ fontSize: 13.5, fontWeight: 500 }}>{it.name}</span>
        </span>
      ))}
    </span>
  );

  return (
    <button type="button" onClick={onOpen} className="bb-ticker" data-testid="home-pulse-ticker" data-items={items.length} aria-label={label}
      style={{ ...fieldGlass({ borderRadius: RADIUS.pill }), width: '100%', height: 38, display: 'flex', alignItems: 'center', gap: 10, padding: '0 12px 0 5px',
        border: 'none', cursor: 'pointer', color: ink, fontFamily: 'inherit', textAlign: 'left', overflow: 'hidden' }}>
      <span aria-hidden="true" style={{ flex: 'none', display: 'inline-flex', alignItems: 'center', gap: 5, height: 28, padding: '0 11px', borderRadius: RADIUS.pill, fontSize: 12, fontWeight: 700, letterSpacing: '0.02em', color: '#fff',
        textShadow: '0 0 6px rgba(255,255,255,0.45)', background: 'linear-gradient(150deg, #D9A89E, #CDA86A 52%, #A9B08E)' }}>
        ✦ Pulse
      </span>
      <span ref={trackRef} style={{ flex: 1, minWidth: 0, overflow: 'hidden', display: 'flex', alignItems: 'center', height: '100%',
        WebkitMaskImage: 'linear-gradient(90deg, transparent 0, #000 14px, #000 calc(100% - 22px), transparent 100%)',
        maskImage: 'linear-gradient(90deg, transparent 0, #000 14px, #000 calc(100% - 22px), transparent 100%)' }}>
        {items.length === 0 ? (
          <span data-testid="home-pulse-ticker-empty" style={{ fontSize: 13.5, opacity: 0.7, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
            {T('Xem điều gì đang hot tuần này', "See what's trending this week")}
          </span>
        ) : reduceMotion ? (
          <span style={{ display: 'block', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', fontSize: 13.5, fontWeight: 500 }}>
            {items.map(i => `${i.rank} ${i.name}`).join('   ·   ')}
          </span>
        ) : (
          <span className="bb-ticker-run" data-testid="home-pulse-ticker-run" style={{ '--bb-ticker-dur': `${tickerSeconds(items)}s` }}>
            {copy(false)}{copy(true)}
          </span>
        )}
      </span>
      <svg aria-hidden="true" width={14} height={14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round" style={{ flex: 'none', opacity: 0.5 }}><path d="M9 6l6 6-6 6" /></svg>
    </button>
  );
}

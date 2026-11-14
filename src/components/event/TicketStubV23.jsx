// v2.3 ticket stub (note 81, switch home_v23), from the prototype's `.dStub`: a paper ticket that rides 22 px up over
// the hero and rises into place on a fresh open. Top: a calendar page (serif month, numeral and weekday behind one
// hairline, not a tinted tile), the time, the countdown and the place with Directions. Perforation, then the price band
// (the tear-off strip: perforated above and below; the seat pill, or later the Held/Confirmed stamp, on the right),
// perforation, then one slim "Save the date" row with the two calendar chips. The notches are page-colour circles
// riding on each perforation. No overflow clip, so the calendar menus can open out of the stub. Real data only.
import { useEffect, useRef } from 'react';
import { SERIF } from './v23Style.js';

const ico = { fill: 'none', stroke: 'currentColor', strokeWidth: 1.6, strokeLinecap: 'round', strokeLinejoin: 'round', viewBox: '0 0 24 24', 'aria-hidden': true };
const IconUp = () => (<svg {...ico} width={12} height={12} strokeWidth={2}><path d="M12 3v18M12 3 7 8M12 3l5 5" /></svg>);
const IconHeld = () => (<svg {...ico} width={12} height={12} strokeWidth={2.4}><circle cx="12" cy="12" r="8" /><path d="M12 8v4l2.5 2" /></svg>);
const IconOk = () => (<svg {...ico} width={12} height={12} strokeWidth={2.4}><path d="m6 12.5 4 4 8-9" /></svg>);
const IconCal = () => (<svg {...ico} width={14} height={14}><rect x="3.5" y="5" width="17" height="15" rx="3" /><path d="M8 3v4M16 3v4M3.5 10h17" /><path d="M12 13v4M10 15h4" /></svg>);

// The bite reads as paper pressed in: a touch darker than the page, a soft shadow falling inside from the top (light
// from above), and a thin highlight on its lower lip (the glass line token: bright in light, faint in dark).
const notch = {
  position: 'absolute', top: -9, width: 9, height: 16, boxSizing: 'border-box',
  background: 'color-mix(in srgb, var(--bb-bg) 93%, #000)',
  boxShadow: 'inset 0 2px 3px rgba(0,0,0,.22), inset 0 -1px 0 var(--v23-line)',
};
const Perf = () => (
  <div aria-hidden style={{ position: 'relative', zIndex: 2, height: 0, margin: '0 16px', borderTop: '1.5px dashed var(--bb-rule)' }}>
    {/* A half-circle bite on each edge (only the inner half shows, like a real ticket): it covers the stub's own
        border at the edge and draws the card's hairline round its curve. */}
    <span style={{ ...notch, left: -17, borderRadius: '0 8px 8px 0' }} />
    <span style={{ ...notch, right: -17, borderRadius: '8px 0 0 8px' }} />
  </div>
);

/**
 * block { month, day, weekday } | null · time · countdown · placeLine · mapsUrl / onDirections / directionsLabel ·
 * price · perTicket · seat { text, kind: 'few' | 'going' | 'soldOut' | 'open' } | null · calendar (node) · saveLabel ·
 * stamp { kind: 'held' | 'confirmed', text } | null (phase e: takes the seat pill's place, so nothing overlaps the
 * price) · stampPlay: a counter; each increase slams the stamp in (Reduce Motion: a fade), the stub gives a millimetre
 * under it, and a confirmation sends one sheen across the strip.
 */
export default function TicketStubV23({ block, time, countdown, placeLine, mapsUrl, onDirections, directionsLabel, price, perTicket, seat, stamp = null, stampPlay = 0, calendar = null, saveLabel, inert = false }) {
  const few = seat?.kind === 'few';
  const going = seat?.kind === 'going';
  const confirmed = stamp?.kind === 'confirmed';
  const stubRef = useRef(null);
  const stampRef = useRef(null);
  const sheenRef = useRef(null);
  useEffect(() => {
    if (!stampPlay || !stampRef.current?.animate) return;
    if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) {
      stampRef.current.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 220, easing: 'ease-out' });
      return;
    }
    stampRef.current.animate([
      { opacity: 0, transform: 'rotate(-16deg) scale(1.9)' },
      { opacity: 1, transform: 'rotate(-5deg) scale(.93)', offset: 0.55 },
      { opacity: 1, transform: 'rotate(-6deg) scale(1)' },
    ], { duration: 520, easing: 'cubic-bezier(.2,1.25,.4,1)' });
    stubRef.current?.animate?.([{ transform: 'none' }, { transform: 'translateY(2px) scale(.994)' }, { transform: 'none' }], { duration: 240, delay: 260, easing: 'ease-out' });
    if (confirmed) sheenRef.current?.animate?.([{ opacity: 1, transform: 'translateX(-100%)' }, { opacity: 1, transform: 'translateX(100%)' }], { duration: 1000, delay: 320, easing: 'cubic-bezier(.4,0,.2,1)', fill: 'backwards' });
  }, [stampPlay]); // eslint-disable-line react-hooks/exhaustive-deps
  const stampEl = stamp && (
    <span ref={stampRef} data-testid="event-stub-stamp" data-kind={stamp.kind} role="status"
      style={{ position: 'relative', display: 'inline-flex', alignItems: 'center', gap: 5, height: 28, padding: '0 10px', border: '1.5px solid currentColor', borderRadius: 8, background: 'var(--bb-surface-1)', color: confirmed ? 'var(--bb-update)' : 'var(--bb-honey)',
        fontSize: 10.5, fontWeight: 800, letterSpacing: '0.16em', textTransform: 'uppercase', whiteSpace: 'nowrap', transform: 'rotate(-6deg)' }}>
      <span aria-hidden style={{ position: 'absolute', inset: 2, border: '1px solid currentColor', borderRadius: 5, opacity: 0.45 }} />
      {confirmed ? <IconOk /> : <IconHeld />}<b style={{ fontWeight: 800 }}>{stamp.text}</b>
    </span>
  );
  return (
    <div ref={stubRef} data-testid="event-ticket-stub" className="bbv23-stub"
      style={{ position: 'relative', zIndex: 2, margin: '-22px 14px 0', borderRadius: 26, background: 'var(--bb-surface-1)', border: '1px solid var(--v23-line)', boxShadow: 'var(--v23-stub-shadow), var(--v23-rim)' }}>
      <div style={{ display: 'flex', gap: 18, padding: 18, alignItems: 'stretch' }}>
        {block && (
          <div data-testid="event-fact-when" aria-label={`${block.weekday} ${block.day} ${block.month}`}
            style={{ flex: 'none', width: 72, display: 'flex', flexDirection: 'column', justifyContent: 'center', alignItems: 'center', padding: '2px 16px 2px 0', borderRight: '1px solid var(--bb-rule)', color: 'var(--bb-clay)' }}>
            <small style={{ fontFamily: SERIF, fontSize: 10.5, letterSpacing: '0.17em', fontWeight: 600, textTransform: 'uppercase', lineHeight: 1 }}>{block.month}</small>
            <b style={{ fontFamily: SERIF, fontSize: 38, fontWeight: 400, lineHeight: 1, margin: '5px 0 6px', color: 'var(--bb-fg)', letterSpacing: '-0.035em' }}>{block.day}</b>
            <span style={{ fontSize: 10, color: 'var(--bb-fg-3)', letterSpacing: '0.16em', fontWeight: 600, whiteSpace: 'nowrap', lineHeight: 1 }}>{block.weekday}</span>
          </div>
        )}
        <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
          {time && <div data-testid="event-fact-time" style={{ fontSize: 16, fontWeight: 600, letterSpacing: '-0.01em', lineHeight: 1.25 }}>{time}</div>}
          {countdown && (
            <div data-testid="event-countdown" style={{ display: 'inline-flex', alignItems: 'center', gap: 5, marginTop: 4, fontSize: 12, color: 'var(--bb-honey)', fontWeight: 600 }}>
              <i aria-hidden style={{ width: 5, height: 5, borderRadius: 99, background: 'currentColor' }} />{countdown}
            </div>
          )}
          <div data-testid="event-fact-where" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, marginTop: 4, fontSize: 13, color: 'var(--bb-fg-2)' }}>
            <span style={{ minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{placeLine}</span>
            {mapsUrl && (
              // 44 px hit area around the prototype's 30 px pill.
              <a href={mapsUrl} target="_blank" rel="noopener noreferrer" data-testid="event-maps-link" onClick={onDirections} className="bbv23-press"
                style={{ flex: 'none', minHeight: 44, display: 'inline-flex', alignItems: 'center', textDecoration: 'none', ...(inert ? { pointerEvents: 'none' } : null) }}>
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, height: 30, padding: '0 11px', borderRadius: 999, background: 'var(--bb-fg)', color: 'var(--bb-bg)', fontSize: 12, fontWeight: 700, whiteSpace: 'nowrap' }}>
                  <IconUp />{directionsLabel}
                </span>
              </a>
            )}
          </div>
        </div>
      </div>
      <Perf />
      <div data-testid="event-price-strip" style={{ position: 'relative', overflow: 'hidden', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '14px 18px', borderRadius: calendar ? 0 : '0 0 25px 25px', background: confirmed ? 'color-mix(in srgb, var(--bb-update) 14%, var(--bb-surface-2))' : 'var(--bb-surface-2)', transition: 'background-color .42s cubic-bezier(.22,.61,.36,1)' }}>
        <div data-testid="event-price" style={{ display: 'flex', alignItems: 'baseline', gap: 4, minWidth: 0 }}>
          {price && <b style={{ fontFamily: SERIF, fontSize: 24, fontWeight: 400, letterSpacing: '-0.02em', fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap' }}>{price}</b>}
          {perTicket && <span style={{ fontSize: 12, color: 'var(--bb-fg-3)' }}>{perTicket}</span>}
        </div>
        <span data-testid="event-fact-seats" style={{ display: 'grid', justifyItems: 'end', alignItems: 'center' }}>
          {stampEl || (seat && (
            <span data-testid="event-seat-status" style={{ display: 'inline-flex', alignItems: 'center', gap: 5, height: 28, padding: '0 11px', borderRadius: 999, fontSize: 12, fontWeight: 600, whiteSpace: 'nowrap',
              border: `1px solid ${few ? 'color-mix(in srgb, var(--bb-honey) 34%, transparent)' : going ? 'color-mix(in srgb, var(--bb-clay) 34%, transparent)' : 'var(--bb-rule)'}`,
              color: few ? 'var(--bb-honey)' : going ? 'var(--bb-clay)' : 'var(--bb-fg)',
              background: few ? 'color-mix(in srgb, var(--bb-honey) 10%, transparent)' : going ? 'color-mix(in srgb, var(--bb-clay) 10%, transparent)' : 'transparent' }}>
              <i aria-hidden style={{ width: 5, height: 5, borderRadius: 99, background: 'currentColor' }} />{seat.text}
            </span>
          ))}
        </span>
        <span ref={sheenRef} aria-hidden style={{ position: 'absolute', inset: 0, pointerEvents: 'none', opacity: 0, background: 'linear-gradient(105deg, transparent 28%, rgba(255,255,255,.55) 47%, rgba(255,255,255,0) 64%)' }} />
      </div>
      {calendar && (
        <>
          <Perf />
          <div data-testid="event-stub-lip" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, padding: '4px 12px 4px 18px', borderRadius: '0 0 25px 25px', background: 'var(--bb-surface-1)' }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, flex: 'none', fontSize: 12, fontWeight: 600, color: 'var(--bb-fg-2)', whiteSpace: 'nowrap' }}>
              <span style={{ color: 'var(--bb-clay)', display: 'inline-flex' }}><IconCal /></span>{saveLabel}
            </span>
            {calendar}
          </div>
        </>
      )}
    </div>
  );
}

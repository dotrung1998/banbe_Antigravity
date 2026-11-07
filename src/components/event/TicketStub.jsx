import { surface1, surface2, ink, ink2, clay, clayBg, display, RADIUS } from '../../theme.js';

// Event Detail V8 ticket stub (note 75): the date block, time + countdown, the place with Directions, a dashed
// perforation between two notches, then the price and one seat chip. iOS twin: EventDetailView `ticketStub`
// (TicketStubShape). The two halves are cut with a radial mask (one notch per side at the perforation); the edge is a
// drop-shadow hairline so it reads on paper in both themes. The stub is surface-1 and the place row surface-2 (V8's
// --paper / --block in both themes).

const NOTCH = 12.5; // notch radius
const RADIUS_STUB = 20;
const half = (at) => {
  const m = `radial-gradient(circle ${NOTCH}px at 0 ${at}, #0000 98%, #000) 0 0/51% 100% no-repeat, radial-gradient(circle ${NOTCH}px at 100% ${at}, #0000 98%, #000) 100% 0/51% 100% no-repeat`;
  return { background: surface1, WebkitMask: m, mask: m };
};

const ico = { width: 16, height: 16, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': true };
const IconClock = () => (<svg {...ico} width={14} height={14}><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></svg>);
const IconPin = () => (<svg {...ico} width={21} height={21}><path d="M12 21s7-6.2 7-11.5A7 7 0 0 0 5 9.5C5 14.8 12 21 12 21Z" /><circle cx="12" cy="9.5" r="2.5" /></svg>);
const IconDirections = () => (<svg {...ico} width={15} height={15}><path d="m3 11 18-8-8 18-2-8Z" /></svg>);

/**
 * block: { month, day, weekday } | null; time: "20:00" | null; countdown: text | null; place: area; placeSub: line under
 * it; mapsUrl / onDirections / directionsLabel: the Directions button (hidden without a URL); price + perTicket ("/ vé");
 * seatPill: { text, fg, bg } | null; calendar: the two calendar tiles (note 77) at the row's end. `inert` (create preview) keeps every control visible but inactive.
 */
export default function TicketStub({ block, time, countdown, place, placeSub, mapsUrl, onDirections, directionsLabel, price, perTicket, seatPill, calendar, inert }) {
  const hasTop = block || time;
  return (
    <div data-testid="event-ticket-stub" style={{ position: 'relative', filter: 'drop-shadow(0 0 0.6px rgba(var(--bb-fg-rgb),0.30)) drop-shadow(0 12px 18px rgba(0,0,0,0.22))' }}>
      <div style={{ ...half('100%'), borderRadius: `${RADIUS_STUB}px ${RADIUS_STUB}px 0 0`, paddingBottom: 1 }}>
        {hasTop && (
          <div style={{ display: 'flex', gap: 16, alignItems: 'center', padding: '18px 18px 14px' }}>
            {block && (
              <div data-testid="event-fact-when" className="bb-flip-in" aria-label={`${block.weekday} ${block.day} ${block.month}`}
                style={{ animationDelay: '360ms', flex: 'none', alignSelf: 'stretch', minWidth: 100, borderRadius: 16, background: clay, color: '#fff', padding: '14px 16px', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 4, textAlign: 'center' }}>
                <small style={{ fontSize: 13, fontWeight: 700, letterSpacing: '0.08em', lineHeight: 1 }}>{block.month}</small>
                <b style={{ ...display(46), fontWeight: 800, lineHeight: 1, color: '#fff' }}>{block.day}</b>
                <small style={{ fontSize: 12.5, fontWeight: 700, letterSpacing: '0.06em', lineHeight: 1, whiteSpace: 'nowrap' }}>{block.weekday}</small>
              </div>
            )}
            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: 8 }}>
              {time && <span data-testid="event-fact-time" style={{ ...display(31), fontWeight: 800, lineHeight: 1, letterSpacing: '-0.02em', color: ink }}>{time}</span>}
              {countdown && (
                <span data-testid="event-countdown" style={{ alignSelf: 'flex-start', display: 'inline-flex', alignItems: 'center', gap: 5, borderRadius: RADIUS.pill, background: clayBg, color: clay, fontSize: 12.5, fontWeight: 700, padding: '7px 12px', whiteSpace: 'nowrap' }}>
                  <IconClock />{countdown}
                </span>
              )}
            </div>
            {calendar && <div className="bb-rise-in" style={{ flex: 'none', animationDelay: '440ms', '--bb-rise-x': '14px', '--bb-rise-y': '0px' }}>{calendar}</div>}
          </div>
        )}
        <div data-testid="event-fact-where" style={{ margin: hasTop ? '0 18px 17px' : '18px 18px 17px', background: surface2, borderRadius: 15, padding: '10px 10px 10px 13px', display: 'flex', alignItems: 'center', gap: 11 }}>
          <span style={{ color: clay, display: 'inline-flex', flex: 'none' }}><IconPin /></span>
          <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
            <b style={{ fontSize: 16, fontWeight: 700, lineHeight: 1.2, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{place}</b>
            {placeSub && <small style={{ fontSize: 12.5, lineHeight: 1.25, color: ink2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{placeSub}</small>}
          </div>
          {mapsUrl && (
            <a href={mapsUrl} target="_blank" rel="noopener noreferrer" data-testid="event-maps-link" onClick={onDirections}
              style={{ flex: 'none', minHeight: 44, display: 'inline-flex', alignItems: 'center', gap: 6, borderRadius: RADIUS.pill, background: ink, color: 'var(--bb-bg)', fontSize: 13.5, fontWeight: 700, padding: '0 14px', textDecoration: 'none', whiteSpace: 'nowrap', ...(inert ? { pointerEvents: 'none' } : null) }}>
              <IconDirections />{directionsLabel}
            </a>
          )}
        </div>
      </div>
      <div style={{ ...half('0'), borderRadius: `0 0 ${RADIUS_STUB}px ${RADIUS_STUB}px` }}>
        <div aria-hidden style={{ margin: '0 25px', borderTop: `2px dashed ${clay}`, opacity: 0.55, height: 0 }} />
        {(price || seatPill) && (
          <div data-testid="event-fact-seats" style={{ padding: '16px 18px 19px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, flexWrap: 'wrap' }}>
            {price ? (
              <div data-testid="event-price" style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
                <span style={{ ...display(27), fontWeight: 800, letterSpacing: '-0.02em', color: ink }}>{price}</span>
                {perTicket && <span style={{ fontSize: 14, color: ink2 }}>{perTicket}</span>}
              </div>
            ) : <span />}
            {seatPill && (
              <span data-testid="event-seat-status" style={{ fontSize: 14, fontWeight: 700, color: seatPill.fg, background: seatPill.bg, padding: '9px 14px', borderRadius: RADIUS.pill, whiteSpace: 'nowrap' }}>{seatPill.text}</span>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

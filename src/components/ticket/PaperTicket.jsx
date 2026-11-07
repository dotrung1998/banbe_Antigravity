import { paper, ink, ink3, rule, display, block, blockInset } from '../../theme.js';

// The paper ticket (note 78, Ticket A): the event's name and three tiles on top, a perforation in the middle (two
// notches in the page colour and a dashed rule), and the stub underneath, which is the `children` slot (the QR and the
// 3-3 entry code, or the per-attendee pager). `strip` is the What's next strip, shown above the name.
// Tiles wrap onto their own rows when the screen is narrow or the text is large; long Vietnamese strings wrap too.
export default function PaperTicket({ strip, holderLabel, title, tiles, onOpenDetails, viewLabel, children }) {
  const shown = (tiles || []).filter(t => t.value);
  return (
    <div data-testid="confirmed-ticket" style={{ filter: 'drop-shadow(0 10px 24px rgba(27,25,22,.12))' }}>
      <div style={{ background: block, borderRadius: '24px 24px 0 0', padding: '12px 12px 18px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {strip}
        <div style={{ padding: '4px 8px 0' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
            <div style={{ flex: 1, minWidth: 0, fontSize: 10.5, fontWeight: 600, letterSpacing: '0.08em', textTransform: 'uppercase', color: ink3, overflowWrap: 'anywhere' }}>{holderLabel}</div>
            {/* The name and this pill both open the Event details sheet. */}
            {onOpenDetails && (
              <button type="button" className="bb-press" onClick={(e) => onOpenDetails(e.currentTarget)} aria-haspopup="dialog" data-testid="confirmed-view-event"
                style={{ flex: 'none', minHeight: 44, padding: 0, border: 'none', background: 'none', fontFamily: 'inherit', cursor: 'pointer' }}>
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, background: blockInset, color: ink, borderRadius: 999, padding: '6px 6px 6px 12px', fontSize: 13, fontWeight: 600 }}>
                  {viewLabel}
                  <span aria-hidden style={{ width: 20, height: 20, borderRadius: '50%', background: ink, color: paper, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
                    <svg width="6" height="10" viewBox="0 0 8 14" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M1.5 1.5 6.5 7l-5 5.5" /></svg>
                  </span>
                </span>
              </button>
            )}
          </div>
          <h2 data-testid="confirmed-ticket-title" style={{ ...display(27, { lineHeight: 1.15, margin: '4px 0 0', overflowWrap: 'anywhere' }) }}>
            {onOpenDetails ? (
              <button type="button" onClick={(e) => onOpenDetails(e.currentTarget)} aria-haspopup="dialog" data-testid="confirmed-open-details"
                style={{ display: 'block', width: '100%', padding: 0, border: 'none', background: 'none', font: 'inherit', color: 'inherit', letterSpacing: 'inherit', textAlign: 'left', cursor: 'pointer', overflowWrap: 'anywhere' }}>{title}</button>
            ) : title}
          </h2>
        </div>
        {shown.length > 0 && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            {shown.map(t => (
              <div key={t.key} data-testid={`confirmed-tile-${t.key}`} style={{ flex: '1 1 96px', minWidth: 0, boxSizing: 'border-box', background: blockInset, borderRadius: 14, padding: '9px 12px' }}>
                <div style={{ fontSize: 10.5, fontWeight: 600, letterSpacing: '0.06em', textTransform: 'uppercase', color: ink3 }}>{t.label}</div>
                <div style={{ marginTop: 2, fontSize: 14, fontWeight: 600, lineHeight: 1.3, color: ink, ...(t.key === 'date' ? { whiteSpace: 'nowrap' } : { overflowWrap: 'anywhere' }) }}>{t.value}</div>
              </div>
            ))}
          </div>
        )}
      </div>
      {/* Perforation: a dashed rule on the ticket fill, with a notch cut out of each edge in the page colour. */}
      <div aria-hidden style={{ position: 'relative', background: block, padding: '0 16px' }}>
        <span style={{ position: 'absolute', left: -11, top: -11, width: 22, height: 22, borderRadius: '50%', background: paper }} />
        <span style={{ position: 'absolute', right: -11, top: -11, width: 22, height: 22, borderRadius: '50%', background: paper }} />
        <div style={{ borderTop: `2px dashed ${rule}` }} />
      </div>
      <div style={{ background: block, borderRadius: '0 0 24px 24px', padding: '20px 20px 22px', display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }}>
        {children}
      </div>
    </div>
  );
}

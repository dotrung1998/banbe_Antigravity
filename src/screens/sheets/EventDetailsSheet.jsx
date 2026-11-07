import { useEffect, useRef, useState } from 'react';
import { paper, ink, ink2, ink3, rule, display, block, blockInset, clay, clayBg, surface2 } from '../../theme.js';
import { bg } from '../../data/events.js';

// "Event details" sheet opened from the ticket (note 78): the event's own facts without leaving the ticket, and one
// button to the full Event Detail page (whose Back returns to this same ticket). Everything shown comes from the real
// event; a section with no data is not drawn (no placeholder About, chips or host). The refund line is the app's
// existing policy paragraph, passed in unchanged. Presentational: the screen computes and wires everything.

const Chevron = ({ stroke }) => (
  <svg aria-hidden width="7" height="12" viewBox="0 0 8 14" fill="none" stroke={stroke} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1.5 1.5 6.5 7l-5 5.5" /></svg>
);

const sectionLabel = { fontSize: 11, fontWeight: 600, letterSpacing: '0.08em', textTransform: 'uppercase', color: ink3, margin: '22px 0 8px' };

export default function EventDetailsSheet({
  title, cover, tiles, about, included, orgName, onMessage, place, hostNote, distance, directionsUrl, policyNote, over,
  onOpenEvent, onClose, reduceMotion, returnFocusTo, T,
}) {
  const [closing, setClosing] = useState(false);
  const panel = useRef(null);
  const closeBtn = useRef(null);
  const opener = useRef(typeof document !== 'undefined' ? document.activeElement : null);
  const close = () => { setClosing(true); setTimeout(onClose, reduceMotion ? 0 : 220); };
  const closeRef = useRef(close);
  closeRef.current = close;

  // Focus goes into the dialog, stays in it while it is open, and returns to the control that opened it. `returnFocusTo` is
  // the clicked element: Safari does not focus a button on click, so document.activeElement alone would be the page body.
  useEffect(() => {
    closeBtn.current?.focus();
    const onKey = (e) => {
      if (e.key === 'Escape') { e.stopPropagation(); closeRef.current(); return; }
      if (e.key !== 'Tab' || !panel.current) return;
      const f = [...panel.current.querySelectorAll('button, a[href], [tabindex]:not([tabindex="-1"])')].filter(el => !el.disabled && el.offsetParent !== null);
      if (!f.length) return;
      // Cycle focus ourselves: WebKit's own Tab skips buttons (by default), which would drop focus onto the page behind.
      e.preventDefault();
      const i = f.indexOf(document.activeElement);
      const next = i < 0 ? (e.shiftKey ? f.length - 1 : 0) : (i + (e.shiftKey ? -1 : 1) + f.length) % f.length;
      f[next].focus();
    };
    window.addEventListener('keydown', onKey, true);
    const back = returnFocusTo || opener.current;
    return () => { window.removeEventListener('keydown', onKey, true); back?.focus?.(); };
  }, []);

  const shown = (tiles || []).filter(t => t.value);
  return (
    <div onClick={close} data-testid="event-details-sheet" style={{ position: 'fixed', inset: 0, zIndex: 80, background: 'rgba(27,25,22,0.4)', display: 'flex', alignItems: 'flex-end', opacity: closing ? 0 : 1, transition: reduceMotion ? 'none' : 'opacity .22s ease' }}>
      <div ref={panel} role="dialog" aria-modal="true" aria-labelledby="event-details-title" onClick={(e) => e.stopPropagation()}
        style={{
          width: '100%', height: '86%', background: paper, borderRadius: '30px 30px 0 0', boxSizing: 'border-box', display: 'flex', flexDirection: 'column', overflow: 'hidden',
          animation: closing ? 'none' : (reduceMotion ? 'banbeFade 0.2s ease both' : 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both'),
          transform: closing && !reduceMotion ? 'translateY(100%)' : 'none', transition: closing && !reduceMotion ? 'transform .22s ease-in' : 'none',
        }}>
        <div style={{ flex: 'none', position: 'relative', padding: '10px 22px 0' }}>
          <div aria-hidden style={{ width: 40, height: 5, background: rule, borderRadius: 3, margin: '0 auto' }} />
          <button ref={closeBtn} type="button" onClick={close} aria-label={T('Đóng', 'Close')} data-testid="event-details-close"
            style={{ position: 'absolute', right: 14, top: 4, width: 44, height: 44, border: 'none', background: 'none', padding: 0, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <span style={{ width: 32, height: 32, borderRadius: '50%', background: block, color: ink, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <svg aria-hidden width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round"><path d="M6 6l12 12M18 6 6 18" /></svg>
            </span>
          </button>
        </div>
        <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', padding: '14px 22px 22px' }}>
          {cover && <div data-testid="event-details-cover" style={bg(cover, { width: '100%', height: 130, borderRadius: 20, marginBottom: 16 })} />}
          <div style={{ fontSize: 12, fontWeight: 600, color: clay }}>{T('Chi tiết sự kiện', 'Event details')}</div>
          <h2 id="event-details-title" style={{ ...display(27, { margin: '4px 0 0', lineHeight: 1.15, overflowWrap: 'anywhere' }) }}>{title}</h2>

          {shown.length > 0 && (
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 14 }}>
              {shown.map(t => (
                <div key={t.key} data-testid={`event-details-tile-${t.key}`} style={{ flex: '1 1 96px', minWidth: 0, boxSizing: 'border-box', background: block, borderRadius: 14, padding: '9px 12px' }}>
                  <div style={{ fontSize: 10.5, fontWeight: 600, letterSpacing: '0.06em', textTransform: 'uppercase', color: ink3 }}>{t.label}</div>
                  <div style={{ marginTop: 2, fontSize: 14, fontWeight: 600, lineHeight: 1.3, color: ink, overflowWrap: 'anywhere' }}>{t.value}</div>
                </div>
              ))}
            </div>
          )}

          {about?.visible && (
            <>
              <div style={sectionLabel}>{T('Giới thiệu', 'About')}</div>
              <p data-testid="event-details-about" style={{ margin: 0, fontSize: 14, lineHeight: 1.55, color: ink, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{about.body}</p>
            </>
          )}

          {included?.visible && (
            <>
              <div style={sectionLabel}>{T('Bao gồm', 'Included')}</div>
              <div data-testid="event-details-included" style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                {included.items.map(it => (
                  <span key={it} style={{ background: block, color: ink, borderRadius: 999, padding: '7px 13px', fontSize: 13, fontWeight: 500, overflowWrap: 'anywhere' }}>{it}</span>
                ))}
              </div>
            </>
          )}

          {orgName && (
            <>
              <div style={sectionLabel}>{T('Chủ nhà', 'Host')}</div>
              <div data-testid="event-details-host" style={{ display: 'flex', alignItems: 'center', gap: 12, background: block, borderRadius: 17, padding: 12 }}>
                <span aria-hidden style={{ flex: 'none', width: 40, height: 40, borderRadius: '50%', background: surface2, color: ink, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, fontWeight: 600 }}>{orgName.trim().slice(0, 1).toUpperCase()}</span>
                <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                  <span style={{ ...display(17, { lineHeight: 1.25 }), overflowWrap: 'anywhere' }}>{orgName}</span>
                  <span style={{ fontSize: 12.5, color: ink2 }}>{T('Nhắn host nếu cần biết thêm', 'Message the host with questions')}</span>
                </span>
                <button type="button" onClick={onMessage} aria-label={T('Nhắn cho ', 'Message ') + orgName} data-testid="event-details-message"
                  style={{ flex: 'none', width: 44, height: 44, borderRadius: '50%', border: 'none', background: blockInset, color: ink, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  <svg aria-hidden width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M4 5h16v11H9l-5 4z" /></svg>
                </button>
              </div>
            </>
          )}

          {(place || hostNote || directionsUrl) && (
            <>
              <div style={sectionLabel}>{T('Địa điểm', 'Location')}</div>
              <div data-testid="event-details-location" style={{ display: 'flex', flexDirection: 'column', gap: 8, background: block, borderRadius: 17, padding: 14 }}>
                <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
                  <span aria-hidden style={{ flex: 'none', width: 34, height: 34, borderRadius: '50%', background: clayBg, color: clay, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0C18.5 15.4 12 21 12 21Z" /><circle cx="12" cy="10" r="2.3" /></svg>
                  </span>
                  <span style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                    {place && <span data-testid="event-details-place" style={{ fontSize: 14, fontWeight: 600, lineHeight: 1.4, color: ink, overflowWrap: 'anywhere' }}>{place}</span>}
                    {distance && <span data-testid="event-details-distance" style={{ fontSize: 12.5, color: ink2 }}>{distance}</span>}
                  </span>
                </div>
                {hostNote && (
                  <div data-testid="event-details-host-note" style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
                    <span style={{ fontSize: 11.5, fontWeight: 600, color: ink2 }}>{T('Lời nhắn từ host', 'Note from the host')}</span>
                    <span style={{ fontSize: 13, lineHeight: 1.5, color: ink, whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>{hostNote}</span>
                  </div>
                )}
                {directionsUrl && (
                  <a href={directionsUrl} target="_blank" rel="noopener noreferrer" data-testid="event-details-directions"
                    style={{ alignSelf: 'flex-start', minHeight: 44, display: 'inline-flex', alignItems: 'center', fontSize: 13, fontWeight: 600, color: ink, textDecoration: 'underline', textUnderlineOffset: 3 }}>{T('Chỉ đường', 'Directions')} ↗</a>
                )}
              </div>
            </>
          )}

          {policyNote && (
            <>
              <div style={sectionLabel}>{T('Hoàn tiền', 'Refunds')}</div>
              <p data-testid="event-details-policy" style={{ margin: 0, fontSize: 13.5, lineHeight: 1.55, color: ink }}>{policyNote}</p>
            </>
          )}
        </div>
        <div style={{ flex: 'none', padding: '10px 22px 22px', borderTop: `1px solid ${rule}` }}>
          <button type="button" className="bb-press" onClick={onOpenEvent} data-testid="event-details-open"
            style={{ width: '100%', minHeight: 52, border: 'none', borderRadius: 999, background: ink, color: paper, fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}>
            {over ? T('Xem trang sự kiện', 'View event page') : T('Mở trang sự kiện đầy đủ', 'Open full event page')} <Chevron stroke="currentColor" />
          </button>
        </div>
      </div>
    </div>
  );
}

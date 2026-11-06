import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import TicketQr from './TicketQr.jsx';
import { formatEntryCode } from '../../lib/ticketStatus.js';
import { ink, ink2, ink3, rule, display } from '../../theme.js';

// One stub per named attendee (migration 151), paged sideways with dots (note 78). Each stub has its own QR, 3-3 code,
// name and a Checked-in badge. When a ticket is scanned WHILE this screen is open, that stub tears off (it stays, torn and
// dimmed) and the pager moves on to the next ticket that is still to be scanned. Nothing replays on load: a stub that
// was already checked in simply renders torn. Reduced motion: no tilt or slide, an opacity change, and an instant move.
// Display only: the check-in RPC, the 6s door poll and the QR values are untouched.

const TEAR_MS = 450;
const ADVANCE_MS = 600;

function Zigzag() {
  const teeth = 28;
  const pts = Array.from({ length: teeth * 2 + 1 }, (_, i) => `${(i * 100) / (teeth * 2)},${i % 2 ? 0 : 6}`).join(' ');
  return (
    <svg aria-hidden width="100%" height="8" viewBox="0 0 100 8" preserveAspectRatio="none" style={{ display: 'block', marginBottom: 10 }}>
      <polyline points={pts} fill="none" stroke={rule} strokeWidth="1.5" vectorEffect="non-scaling-stroke" strokeLinejoin="round" />
    </svg>
  );
}

export default function TicketStubPager({ attendees, qrMode, qrLabel, reduceMotion, onActive, T }) {
  const live = qrMode === 'ok' || qrMode === 'in';
  const box = useRef(null);
  const [active, setActive] = useState(0);
  const [tearing, setTearing] = useState(null);
  const seen = useRef(null);
  const timers = useRef([]);
  const list = useRef(attendees);
  list.current = attendees;
  // Re-run only when somebody's checked-in state changes, not on every render of the parent.
  const sig = useMemo(() => attendees.map(a => `${a.id}:${a.checked_in_at ? 1 : 0}`).join(','), [attendees]);

  const goTo = useCallback((i, instant) => {
    const el = box.current;
    if (!el) return;
    const n = Math.max(0, Math.min(i, list.current.length - 1));
    el.scrollTo({ left: n * el.clientWidth, behavior: instant || reduceMotion ? 'auto' : 'smooth' });
  }, [reduceMotion]);

  useEffect(() => { onActive?.(active); }, [active, onActive]);
  useEffect(() => () => timers.current.forEach(clearTimeout), []);

  useEffect(() => {
    const now = new Map(list.current.map(a => [a.id, !!a.checked_in_at]));
    const before = seen.current;
    seen.current = now;
    if (!before || !live) return;
    // A tear is a null -> set change of a ticket we already knew as not scanned, seen while mounted.
    const idx = list.current.findIndex(a => a.checked_in_at && before.get(a.id) === false);
    if (idx < 0) return;
    goTo(idx, true);
    setTearing(list.current[idx].id);
    timers.current.push(setTimeout(() => setTearing(null), reduceMotion ? 300 : TEAR_MS));
    timers.current.push(setTimeout(() => {
      const arr = list.current;
      const next = [...arr.keys()].map(k => (idx + 1 + k) % arr.length).find(k => !arr[k].checked_in_at);
      if (next != null) goTo(next);
    }, reduceMotion ? 300 : ADVANCE_MS));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sig, live]);

  const onScroll = () => {
    const el = box.current;
    if (!el || !el.clientWidth) return;
    const i = Math.round(el.scrollLeft / el.clientWidth);
    if (i !== active) setActive(i);
  };
  const onKey = (e) => {
    if (e.key === 'ArrowRight') { e.preventDefault(); goTo(active + 1); }
    else if (e.key === 'ArrowLeft') { e.preventDefault(); goTo(active - 1); }
  };
  const many = attendees.length > 1;

  return (
    <div style={{ width: '100%' }} data-testid="confirmed-attendee-tickets">
      <div ref={box} onScroll={onScroll} onKeyDown={onKey} tabIndex={many ? 0 : -1} className="bb-snap" data-testid="confirmed-stub-pager"
        role="group" aria-roledescription="carousel" aria-label={T('Vé của từng người', 'Each person’s ticket')}
        style={{ display: 'flex', overflowX: many ? 'auto' : 'hidden', scrollSnapType: 'x mandatory', width: '100%', outlineOffset: 4 }}>
        {attendees.map((a, i) => {
          const checked = live && !!a.checked_in_at;
          const isTearing = tearing === a.id && !reduceMotion;
          const mode = live ? (checked ? 'in' : 'ok') : qrMode;
          return (
            <div key={a.id} role="group" aria-roledescription="slide" aria-label={T(`Vé ${i + 1} trên ${attendees.length}`, `Ticket ${i + 1} of ${attendees.length}`)}
              style={{ flex: '0 0 100%', scrollSnapAlign: 'center', display: 'flex', justifyContent: 'center' }}>
              <div data-testid={`confirmed-stub-${a.seat_no}`} data-torn={checked ? 'true' : 'false'} data-tearing={isTearing ? 'true' : 'false'}
                style={{
                  display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', transformOrigin: 'top left',
                  opacity: checked ? 0.6 : 1,
                  transform: checked && !reduceMotion ? 'translateY(6px) rotate(-1.5deg)' : 'none',
                  animation: isTearing ? `bbTear ${TEAR_MS}ms cubic-bezier(.4,0,.2,1) both` : 'none',
                  transition: reduceMotion ? 'opacity .3s' : 'none',
                }}>
                {checked && <Zigzag />}
                <TicketQr mode={mode} value={a.admission_token} size={220} pad={10} label={qrLabel} />
                <span data-testid={`confirmed-stub-name-${a.seat_no}`} style={{ ...display(17, { marginTop: 14, overflowWrap: 'anywhere' }) }}>{a.name}</span>
                <span style={{ marginTop: 10, fontSize: 11, fontWeight: 600, letterSpacing: '0.08em', textTransform: 'uppercase', color: ink3 }}>{T('Mã vào cửa', 'Entry code')}</span>
                <span style={{ marginTop: 4, fontSize: 29, fontWeight: 600, letterSpacing: '0.14em', fontFamily: 'ui-monospace, Menlo, monospace', color: ink, opacity: live ? 1 : 0.35, whiteSpace: 'nowrap' }}>
                  {live ? formatEntryCode(a.ticket_code) : '••• •••'}
                </span>
                {checked && <span data-testid={`confirmed-stub-badge-${a.seat_no}`} style={{ marginTop: 8, fontSize: 12.5, fontWeight: 600, color: ink }}>✓ {T('Đã vào cửa', 'Checked in')}</span>}
              </div>
            </div>
          );
        })}
      </div>
      {many && (
        <div style={{ marginTop: 14, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 2 }}>
          {attendees.map((a, i) => (
            <button key={a.id} type="button" onClick={() => goTo(i)} aria-label={T(`Vé ${i + 1}: ${a.name}`, `Ticket ${i + 1}: ${a.name}`)} aria-current={i === active ? 'true' : undefined} data-testid={`confirmed-stub-dot-${a.seat_no}`}
              style={{ width: 24, height: 24, padding: 0, border: 'none', background: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
              <span style={{ width: i === active ? 18 : 8, height: 8, borderRadius: 4, background: i === active ? ink : ink3, opacity: i === active ? 1 : 0.55, transition: reduceMotion ? 'none' : 'width .2s' }} />
            </button>
          ))}
          <span style={{ marginLeft: 8, fontSize: 12, color: ink2 }} aria-hidden>{active + 1}/{attendees.length}</span>
        </div>
      )}
    </div>
  );
}

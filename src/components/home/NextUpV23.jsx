// "Next up" on the v2.3 Home (note 81): the viewer's upcoming tickets as ticket cards (owner's mock-up, 2026-11-14).
// Photo top with the date badge and the countdown chip, the type · area kicker and the name; a perforated tear line
// with pressed notches; then Starts (with the end time) · Tickets (people across bookings) · Status, and the button
// that event needs now (Show ticket / Pay now / View status) beside Directions. Several events: a swipeable track,
// soonest first, the next card peeking, "1 of 3" and dots. Rules: src/lib/nextUp.js.
import { useRef, useState } from 'react';
import { display } from '../../theme.js';

const ico = { fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round', viewBox: '0 0 24 24', 'aria-hidden': true };
const IconClock = () => (<svg {...ico} width={15} height={15}><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 2" /></svg>);
const IconCheck = () => (<svg {...ico} width={15} height={15} strokeWidth={2.2}><path d="m6 12.5 4 4 8-9" /></svg>);
const IconQr = () => (<svg {...ico} width={17} height={17}><rect x="4" y="4" width="6" height="6" rx="1" /><rect x="14" y="4" width="6" height="6" rx="1" /><rect x="4" y="14" width="6" height="6" rx="1" /><path d="M14 14h2v2h-2zM18 18h2v2h-2zM14 18h2M18 14h2" /></svg>);
const IconPin = () => (<svg {...ico} width={17} height={17}><path d="M12 21s6.5-5.6 6.5-11a6.5 6.5 0 0 0-13 0C5.5 15.4 12 21 12 21Z" /><circle cx="12" cy="10" r="2.3" /></svg>);

const notch = (side) => ({
  position: 'absolute', top: -9, [side]: -1, width: 10, height: 18, boxSizing: 'border-box', borderRadius: side === 'left' ? '0 9px 9px 0' : '9px 0 0 9px',
  background: 'color-mix(in srgb, var(--bb-bg) 93%, #000)', boxShadow: 'inset 0 2px 3px rgba(0,0,0,.22)', zIndex: 2,
});
const cellLabel = { fontSize: 11, fontWeight: 700, letterSpacing: '0.12em', textTransform: 'uppercase', color: 'var(--bb-fg-3)' };

function Card({ it, T, onAction, single }) {
  const { g, ev, status, chip, people } = it;
  const tone = status.tone === 'moss' ? 'var(--bb-update)' : 'var(--bb-honey)';
  return (
    <article data-testid={`home-nextup-card-${g.eventId}`} data-state={g.state} data-zoom-src={g.eventId}
      style={{ flex: single ? '1 1 auto' : '0 0 calc(100% - 44px)', scrollSnapAlign: 'center', minWidth: 0, borderRadius: 26, overflow: 'hidden', background: 'var(--bb-surface-2)', color: 'var(--bb-fg)', boxShadow: '0 1px 0 rgba(var(--bb-fg-rgb),0.04)' }}>
      <div data-zoom-photo role="link" tabIndex={0} onClick={() => onAction('open', it)} onKeyDown={(e) => { if (e.key === 'Enter') onAction('open', it); }}
        style={{ position: 'relative', height: 206, cursor: 'pointer', background: ev.img ? `#241E17 center/cover no-repeat url("${ev.img}")` : '#241E17' }}>
        <div aria-hidden style={{ position: 'absolute', inset: 0, background: 'linear-gradient(180deg, rgba(6,5,4,.30) 0%, rgba(6,5,4,0) 34%, rgba(6,5,4,.25) 55%, rgba(6,5,4,.78) 100%)' }} />
        {ev.badge && (
          <div data-testid="home-nextup-date" style={{ position: 'absolute', top: 12, left: 12, minWidth: 52, padding: '7px 8px 6px', borderRadius: 14, background: 'rgba(247,244,236,.92)', color: '#1B1916', textAlign: 'center', lineHeight: 1 }}>
            <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.06em' }}>{ev.badge.weekday}</div>
            <div style={{ fontSize: 24, fontWeight: 700, margin: '3px 0 2px', letterSpacing: '-0.02em' }}>{ev.badge.day}</div>
            <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.06em' }}>{ev.badge.month}</div>
          </div>
        )}
        {chip && (
          <span data-testid="home-nextup-chip" style={{ position: 'absolute', top: 12, right: 12, height: 32, padding: '0 12px', borderRadius: 999, display: 'inline-flex', alignItems: 'center', gap: 6, background: 'rgba(12,10,8,.55)', color: '#fff', fontSize: 13, fontWeight: 600, backdropFilter: 'var(--bb-rt-blur, blur(12px))', WebkitBackdropFilter: 'var(--bb-rt-blur, blur(12px))' }}>
            <IconClock />{T(chip.vi, chip.en)}
          </span>
        )}
        <div style={{ position: 'absolute', left: 16, right: 16, bottom: 18, color: '#fff' }}>
          {ev.kicker && <div style={{ fontSize: 11.5, fontWeight: 600, letterSpacing: '0.12em', textTransform: 'uppercase', opacity: 0.88, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{ev.kicker}</div>}
          <div style={{ ...display(26, { color: '#fff', lineHeight: 1.15, marginTop: 4, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{ev.name}</div>
        </div>
      </div>
      <div aria-hidden style={{ position: 'relative', height: 0, borderTop: '1.5px dashed rgba(var(--bb-fg-rgb),0.18)', margin: '0 14px' }}>
        <span style={{ ...notch('left'), left: -15 }} />
        <span style={{ ...notch('right'), right: -15 }} />
      </div>
      <div style={{ padding: '14px 16px 16px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 0 }}>
          {[
            [T('Bắt đầu', 'Starts'), <span key="v" data-testid="home-nextup-starts">{ev.time}</span>, ev.timeNote],
            [T('Vé', 'Tickets'), <span key="v" data-testid="home-nextup-people">{T(people.main.vi, people.main.en)}</span>, people.note && T(people.note.vi, people.note.en)],
            [T('Trạng thái', 'Status'), <span key="v" data-testid="home-nextup-status" style={{ color: tone, display: 'inline-flex', alignItems: 'center', gap: 4 }}>
              {status.icon === 'check' ? <IconCheck /> : <IconClock />}{T(status.text.vi, status.text.en)}</span>, status.note && T(status.note.vi, status.note.en)],
          ].map(([label, value, note], i) => (
            <div key={i} style={{ minWidth: 0, padding: i ? '0 0 0 12px' : '0 10px 0 0', borderLeft: i ? '1px solid rgba(var(--bb-fg-rgb),0.12)' : 'none' }}>
              <div style={cellLabel}>{label}</div>
              <div style={{ fontSize: 15, fontWeight: 500, lineHeight: 1.3, marginTop: 4, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{value}</div>
              {note && <div style={{ fontSize: 12.5, color: 'var(--bb-fg-2)', marginTop: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{note}</div>}
            </div>
          ))}
        </div>
        <div style={{ display: 'flex', gap: 10, marginTop: 14 }}>
          <button type="button" data-testid="home-nextup-primary" data-action={status.action} onClick={() => onAction(status.action, it)} className="bbv23-press"
            style={{ flex: 1, minHeight: 46, borderRadius: 999, border: 'none', background: 'var(--bb-fg)', color: 'var(--bb-bg)', fontFamily: 'inherit', fontSize: 15, fontWeight: 700, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8, cursor: 'pointer' }}>
            {status.action === 'ticket' ? <IconQr /> : <IconClock />}{T(status.button.vi, status.button.en)}
          </button>
          {ev.mapsUrl && (
            <a href={ev.mapsUrl} target="_blank" rel="noopener noreferrer" data-testid="home-nextup-directions" className="bbv23-press"
              style={{ flex: 1, minHeight: 46, borderRadius: 999, background: 'var(--bb-surface-1)', color: 'var(--bb-fg)', fontSize: 15, fontWeight: 600, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8, textDecoration: 'none', boxShadow: 'inset 0 0 0 1px rgba(var(--bb-fg-rgb),0.06)' }}>
              <IconPin />{T('Chỉ đường', 'Directions')}
            </a>
          )}
        </div>
      </div>
    </article>
  );
}

/**
 * @param {object} p
 * @param {Array<{ g, ev: { name, img, kicker, badge, time, mapsUrl }, status, chip, people }>} p.items  soonest first
 * @param {(action: 'open'|'ticket'|'pay'|'status', item) => void} p.onAction
 * @param {() => void} p.onSchedule
 */
export default function NextUpV23({ items, onAction, onSchedule, T }) {
  const [index, setIndex] = useState(0);
  const trackRef = useRef(null);
  if (!items?.length) return null;
  const many = items.length > 1;
  const onScroll = () => {
    const el = trackRef.current;
    if (!el) return;
    const w = el.firstElementChild?.getBoundingClientRect().width || el.clientWidth;
    const i = Math.max(0, Math.min(items.length - 1, Math.round(el.scrollLeft / (w + 12))));
    if (i !== index) setIndex(i);
  };
  const goTo = (i) => {
    const el = trackRef.current;
    const card = el?.children[i];
    if (card) el.scrollTo({ left: card.offsetLeft - 20, behavior: 'smooth' });
  };
  return (
    <section data-testid="home-nextup" data-count={items.length} style={{ padding: '14px 0 6px', color: 'var(--bb-fg)' }}>
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12, padding: '0 20px 12px' }}>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
          <h2 style={{ ...display(22, { margin: 0, fontWeight: 400 }) }}>{T('Sắp tới', 'Next up')}</h2>
          {many && <span data-testid="home-nextup-count" aria-live="polite" style={{ fontSize: 13, fontWeight: 600, color: 'var(--bb-fg-3)' }}>{T(`${index + 1} / ${items.length}`, `${index + 1} of ${items.length}`)}</span>}
        </div>
        <button type="button" onClick={onSchedule} data-testid="home-nextup-schedule" style={{ minHeight: 44, margin: '-14px 0', padding: 0, border: 'none', background: 'none', color: 'var(--bb-fg-2)', fontFamily: 'inherit', fontSize: 14, fontWeight: 500, cursor: 'pointer' }}>
          {T('Lịch', 'Schedule')}
        </button>
      </div>
      <div ref={trackRef} onScroll={many ? onScroll : undefined} data-hscroll={many ? '' : undefined}
        style={{ display: 'flex', gap: 12, padding: '0 20px', overflowX: many ? 'auto' : 'visible', scrollSnapType: many ? 'x mandatory' : undefined, scrollPadding: '0 20px', scrollbarWidth: 'none' }}>
        {items.map(it => <Card key={it.g.eventId} it={it} T={T} onAction={onAction} single={!many} />)}
      </div>
      {many && (
        <div role="tablist" aria-label={T('Vé sắp tới', 'Upcoming tickets')} style={{ display: 'flex', justifyContent: 'center', gap: 2, marginTop: 6 }}>
          {items.map((it, i) => (
            <button key={it.g.eventId} type="button" role="tab" aria-selected={i === index} aria-label={T(`Vé ${i + 1}`, `Ticket ${i + 1}`)} onClick={() => goTo(i)}
              style={{ width: 24, height: 24, padding: 0, border: 'none', background: 'none', display: 'grid', placeItems: 'center', cursor: 'pointer' }}>
              <i style={{ width: i === index ? 16 : 6, height: 6, borderRadius: 3, background: 'var(--bb-fg)', opacity: i === index ? 0.85 : 0.22, transition: 'width .28s cubic-bezier(.2,1.04,.3,1), opacity .2s' }} />
            </button>
          ))}
        </div>
      )}
    </section>
  );
}

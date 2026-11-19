// v2.3 reserve bar (note 81, switch home_v23), the prototype's `.dbar`: a floating Liquid-Glass bar that slides up on a
// fresh open. COMPACT on arrival (one pill row: 1 · 2 · 3 · 4+ and a plain Reserve button) so the whole ticket stub is
// readable; past ~40 px of scrolling it morphs into the FULL card (the chips, the guest dots, the total with what it
// multiplies, Reserve, the trust line), and back near the top it compacts again. The height morphs (280 ms spring)
// and the contents fade in, so it reads as one bar changing shape. The chips share one sliding ink. 4+ turns its own
// slot into a − N + stepper up to 6 per person or the seats left (in the compact bar 1 · 2 · 3 fold away to make
// room). Rules: src/lib/reserveBarV23.js. Tap targets stay >= 44 px (the prototype's 34 px chips are 44 here).
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { qtyControl, seatDots, guestLine, moreRefusal, totalSub, MORE_AT, addControl, heldCopy, addGuestLine } from '../../lib/reserveBarV23.js';
import { useReducedMotion } from '../../lib/useReducedMotion.js';
import { SERIF } from './v23Style.js';

const ico = { fill: 'none', stroke: 'currentColor', strokeLinecap: 'round', strokeLinejoin: 'round', viewBox: '0 0 24 24', 'aria-hidden': true };
const IconMinus = () => (<svg {...ico} width={12} height={12} strokeWidth={2.6}><path d="M6 12h12" /></svg>);
const IconCheck = () => (<svg {...ico} width={18} height={18} strokeWidth={2.2}><path d="m6 12.5 4 4 8-9" /></svg>);
const IconPlus = () => (<svg {...ico} width={12} height={12} strokeWidth={2.6}><path d="M12 6v12M6 12h12" /></svg>);

/**
 * @param {object} p
 * @param {boolean} p.compact
 * @param {number} p.qty
 * @param {number|null} p.remaining  seats free (null = unknown)
 * @param {(n: number) => void} p.setQty
 * @param {(n: number) => string} p.totalFor  formatted total for n tickets
 * @param {string} p.unitText  one ticket's price, formatted
 * @param {boolean} p.free
 * @param {() => void} p.onReserve
 * @param {string|null} p.trustLine
 * @param {import('react').ReactNode} p.trustIcon
 * Phase e, once the viewer holds seats (`booked` > 0): the count can't go below what they hold; at what they hold the
 * button opens their booking ("Seats held" with a check, or "View your ticket" once `confirmed`); above it the bar
 * shows "+X · N more · M in all" and "Add N tickets" (`onAdd(extra)`: a second booking through Reserve).
 * @param {number} [p.booked]
 * @param {boolean} [p.confirmed]
 * @param {'hold'|'verify'|null} [p.phase]
 * @param {() => void} [p.onHeld]
 * @param {(extra: number) => void} [p.onAdd]
 */
export default function ReserveBarV23({ compact, qty, remaining, setQty, totalFor, unitText, free, onReserve, trustLine, trustIcon, T, booked = 0, confirmed = false, phase = null, onHeld, onAdd }) {
  const reduced = useReducedMotion();
  const held = booked > 0;
  const ac = held ? addControl(qty, remaining, booked) : null;
  const ctl = held ? ac : qtyControl(qty, remaining);
  const minQ = held ? ac.min : 1;
  const hc = held ? heldCopy({ booked, extra: ac.extra, confirmed, phase }) : null;
  const [refusal, setRefusal] = useState(null);
  const [shake, setShake] = useState(0);
  const line = held
    ? (addGuestLine(qty, booked, ac.max) || { vi: `${booked} vé của bạn · tối đa ${ac.max}`, en: `${booked} yours · up to ${ac.max}` })
    : guestLine(qty, remaining);
  const sub = held ? hc.sub : totalSub(qty, unitText, free);
  const barState = !held ? 'reserve' : ac.adding ? 'adding' : confirmed ? 'ticket' : 'held';
  const rowRef = useRef(null);
  const inkRef = useRef(null);
  const btnRefs = useRef({});
  const totalRef = useRef(null);
  const numRef = useRef(null);
  const prevQty = useRef(qty);
  const pad = compact ? 3 : 4;

  // The ink sits under the chosen chip (or hands over to the 4+ slot, which fills itself). Placed without a slide when
  // the bar changes shape, re-measured once the slot's flex transition has settled.
  const placeInk = (animate) => {
    const ink = inkRef.current;
    const b = btnRefs.current[ctl.stepper ? 'slot' : qty];
    if (!ink || !b) return;
    if (!animate) ink.style.transition = 'none';
    ink.style.left = `${b.offsetLeft}px`;
    ink.style.width = `${b.offsetWidth}px`;
    ink.style.opacity = ctl.stepper ? '0' : '1';
    if (!animate) requestAnimationFrame(() => { if (inkRef.current) inkRef.current.style.transition = ''; });
  };
  useLayoutEffect(() => { placeInk(!reduced); const t = setTimeout(() => placeInk(false), reduced ? 0 : 360); return () => clearTimeout(t); }); // every render: cheap, layout-true
  // A price that reacts: the total bobs when the count changes; the stepper's number rolls in.
  useEffect(() => {
    if (prevQty.current === qty) return;
    prevQty.current = qty;
    if (reduced) return;
    totalRef.current?.animate?.([{ transform: 'translateY(0)', opacity: 1 }, { transform: 'translateY(-5px)', opacity: 0.55 }, { transform: 'translateY(0)', opacity: 1 }], { duration: 260, easing: 'cubic-bezier(.22,.61,.36,1)' });
    numRef.current?.animate?.([{ transform: 'translateY(6px)', opacity: 0 }, { transform: 'none', opacity: 1 }], { duration: 220, easing: 'cubic-bezier(.2,1.2,.4,1)' });
  }, [qty, reduced]);
  useEffect(() => { if (!refusal) return undefined; const t = setTimeout(() => setRefusal(null), 2600); return () => clearTimeout(t); }, [refusal, shake]);

  const pick = (n) => { setRefusal(null); setQty(n); };
  const pickMore = () => {
    if (!ctl.moreEnabled) {
      setRefusal(held ? { vi: `Tối đa ${ac.max} vé cho bạn ở sự kiện này`, en: `Up to ${ac.max} tickets for you on this one` } : moreRefusal(remaining));
      setShake(x => x + 1); return;
    }
    pick(Math.max(MORE_AT, minQ));
  };
  const fold = compact && ctl.stepper; // compact + stepper: 1 · 2 · 3 fold away
  const chip = (n) => {
    const on = !ctl.stepper && qty === n;
    const enabled = n <= ctl.max && n >= minQ;
    return (
      <button key={n} ref={el => { btnRefs.current[n] = el; }} type="button" className="bbv23-fold bbv23-press" onClick={() => pick(n)} disabled={!enabled} aria-pressed={on} data-testid={`event-qty-${n}`}
        tabIndex={fold ? -1 : undefined} aria-hidden={fold || undefined}
        style={{ position: 'relative', zIndex: 1, flexGrow: compact ? 0 : 1, flexShrink: 1, flexBasis: fold ? 0 : compact ? 44 : 0, minWidth: fold ? 0 : 44, height: 44, padding: 0, overflow: 'hidden', border: 'none', borderRadius: 999, background: 'transparent',
          color: on ? 'var(--bb-bg)' : 'var(--bb-fg-2)', opacity: fold ? 0 : enabled ? 1 : 0.32, pointerEvents: fold ? 'none' : undefined, fontSize: compact ? 12.5 : 13, fontWeight: 600, cursor: enabled ? 'pointer' : 'default', whiteSpace: 'nowrap' }}>
        {compact ? `${n}` : T(`${n} vé`, n === 1 ? '1 ticket' : `${n} tickets`)}
      </button>
    );
  };
  const slot = (
    <div key="slot" ref={el => { btnRefs.current.slot = el; }} className="bbv23-slot"
      style={{ position: 'relative', zIndex: 1, display: 'flex', borderRadius: 999, flexGrow: compact ? 0 : ctl.stepper ? 2 : 1, flexShrink: 0, flexBasis: compact ? (ctl.stepper ? 132 : 44) : 0, minWidth: 44, background: ctl.stepper ? 'var(--bb-fg)' : 'transparent' }}>
      {ctl.stepper ? (
        <div role="group" aria-label={T('Số vé', 'Tickets')} data-testid="event-qty-stepper" className="bbv23-step"
          style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'space-between', height: 44, color: 'var(--bb-bg)' }}>
          {[['minus', -1, ctl.canMinus, T('Bớt một vé', 'One ticket fewer'), <IconMinus key="m" />], null, ['plus', 1, ctl.canPlus, T('Thêm một vé', 'One more ticket'), <IconPlus key="p" />]].map((b, i) => b ? (
            <button key={b[0]} type="button" onClick={() => setQty(qty + b[1])} disabled={!b[2]} aria-label={b[3]} data-testid={`event-qty-${b[0]}`}
              style={{ flex: 'none', width: 42, height: 44, padding: 0, border: 'none', background: 'none', color: 'inherit', display: 'grid', placeItems: 'center', cursor: b[2] ? 'pointer' : 'default', opacity: b[2] ? 1 : 0.3 }}>
              <span className="bbv23-press" style={{ width: 26, height: 26, borderRadius: '50%', display: 'grid', placeItems: 'center', background: 'color-mix(in srgb, var(--bb-bg) 18%, transparent)' }}>{b[4]}</span>
            </button>
          ) : (
            <span key="n" ref={numRef} data-testid="event-qty-value" aria-live="polite" aria-label={T(`${qty} vé`, `${qty} tickets`)} style={{ display: 'flex', alignItems: 'baseline', gap: 2, fontVariantNumeric: 'tabular-nums' }}>
              <b style={{ fontSize: 15, fontWeight: 800 }}>{qty}</b><small style={{ fontSize: 'var(--bb-text-meta)', fontWeight: 600, opacity: 0.75 }}>{T('vé', '')}</small>
            </span>
          ))}
        </div>
      ) : (
        <button key={`more-${shake}`} type="button" className="bbv23-press" onClick={pickMore} aria-pressed={false} aria-disabled={!ctl.moreEnabled || undefined} aria-label={T('4 đến 6 vé', '4 to 6 tickets')} data-testid="event-qty-more"
          style={{ flex: 1, minWidth: 44, height: 44, padding: 0, border: 'none', borderRadius: 999, background: 'transparent', color: 'var(--bb-fg-2)', opacity: ctl.moreEnabled ? 1 : 0.4, fontSize: compact ? 12.5 : 13, fontWeight: 600, cursor: 'pointer', whiteSpace: 'nowrap',
            animation: shake && !reduced ? 'bbV23Shake .26s' : undefined }}>
          {compact ? '4+' : T('4+ vé', '4+')}
        </button>
      )}
    </div>
  );
  const chips = (
    <div ref={rowRef} role="group" aria-label={T('Chọn số vé', 'Choose tickets')} data-testid="event-qty-presets"
      style={{ position: 'relative', display: 'flex', gap: fold ? 0 : compact ? 2 : 4, padding: pad, borderRadius: 999, background: 'var(--bb-surface-2)', flex: compact ? 'none' : undefined, minWidth: 0 }}>
      <span ref={inkRef} aria-hidden className="bbv23-ink" style={{ position: 'absolute', top: pad, bottom: pad, left: 0, width: 0, borderRadius: 999, background: 'var(--bb-fg)' }} />
      {[1, 2, 3].map(chip)}
      {slot}
    </div>
  );
  const onButton = !held ? onReserve : ac.adding ? () => onAdd?.(ac.extra) : onHeld;
  const reserve = (
    <button type="button" className="bbv23-press bbv23-reserve" onClick={onButton} data-testid="event-reserve-bar" data-state={barState}
      style={{ flex: 1, minWidth: 0, height: compact ? 46 : 54, borderRadius: 999, border: 'none', background: 'var(--bb-fg)', color: 'var(--bb-bg)', fontSize: compact ? 14 : 15, fontWeight: 700, cursor: 'pointer', whiteSpace: 'nowrap',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8, overflow: 'hidden', textOverflow: 'ellipsis',
        boxShadow: '0 14px 32px rgba(24,20,16,.24), inset 0 1px 0 rgba(255,255,255,.14)' }}>
      {barState === 'held' && <IconCheck />}
      {held ? T(hc.button.vi, hc.button.en) : T('Giữ chỗ', 'Reserve')}
    </button>
  );
  const totalText = !held ? totalFor(qty) : free ? totalFor(qty) : ac.adding ? `+${totalFor(ac.extra)}` : totalFor(booked);
  const trustText = held ? T(hc.trust.vi, hc.trust.en) : trustLine;
  const trustColor = barState === 'adding' ? 'var(--bb-honey)' : barState === 'ticket' ? 'var(--bb-update)' : 'var(--bb-fg-2)';

  return (
    <div data-testid="event-bar-v23" data-compact={compact ? 'true' : 'false'} style={{ position: 'relative' }}>
      {compact ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>{chips}{reserve}</div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column' }}>
          {chips}
          {ctl.stepper && (
            <div data-testid="event-guest-line" aria-live="polite" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, margin: '8px 0 0', fontSize: 12, color: 'var(--bb-fg-2)' }}>
              <span aria-hidden="true" style={{ display: 'inline-flex', gap: 3 }}>
                {seatDots(qty).map((d, i) => (
                  <i key={i} data-dot={d} style={{ width: 7, height: 7, borderRadius: '50%', boxSizing: 'border-box', border: `1.5px solid ${d === 'me' ? 'var(--bb-fg)' : d === 'guest' ? 'var(--bb-clay)' : 'var(--bb-fg-3)'}`, background: d === 'me' ? 'var(--bb-fg)' : d === 'guest' ? 'var(--bb-clay)' : 'transparent' }} />
                ))}
              </span>
              <span>{T(line.vi, line.en)}</span>
            </div>
          )}
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 10 }}>
            <div data-testid="event-bar-total" style={{ display: 'flex', flexDirection: 'column', minWidth: 112 }}>
              <b ref={totalRef} data-testid="event-bar-total-value" style={{ fontFamily: SERIF, fontSize: 26, fontWeight: 400, letterSpacing: '-0.025em', fontVariantNumeric: 'tabular-nums', lineHeight: 1.08, whiteSpace: 'nowrap' }}>{totalText}</b>
              <small data-testid="event-bar-total-sub" style={{ fontSize: 'var(--bb-text-meta)', color: barState === 'adding' ? 'var(--bb-honey)' : 'var(--bb-fg-2)', marginTop: 2, fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap' }}>{T(sub.vi, sub.en)}</small>
            </div>
            {reserve}
          </div>
          {trustText && (
            <div data-testid="event-trust-line" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5, marginTop: 8, fontSize: 12, lineHeight: 1.35, color: trustColor, textAlign: 'center', transition: 'color .28s' }}>
              <span style={{ color: held ? 'currentColor' : 'var(--bb-clay)', display: 'inline-flex', flex: 'none' }}>{trustIcon}</span>{trustText}
            </div>
          )}
        </div>
      )}
      {/* The prototype's toast: floats above the bar, so the bar never changes height for it. */}
      {refusal && (
        <div role="status" data-testid="event-qty-refusal" key={shake}
          style={{ position: 'absolute', left: '50%', bottom: 'calc(100% + 18px)', transform: 'translateX(-50%)', maxWidth: '92%', padding: '10px 16px', borderRadius: 999, background: 'var(--bb-fg)', color: 'var(--bb-bg)', fontSize: 12.5, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', boxShadow: '0 14px 30px rgba(0,0,0,.28)', animation: reduced ? undefined : 'bbV23Toast .28s cubic-bezier(.2,1.04,.3,1) both', pointerEvents: 'none' }}>
          {T(refusal.vi, refusal.en)}
        </div>
      )}
    </div>
  );
}

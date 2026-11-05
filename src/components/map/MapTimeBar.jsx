// Map E+ (note 79): the day button + two-knob hour range at the bottom of the map. It only reports choices; the Map
// recomputes what is in the window on the client, so dragging a knob never touches the network.
// The knobs are small at rest and grow only while touched (or focused). A press anywhere on the range picks the NEAREST
// knob, so both stay reachable even a step apart (two stacked native range inputs cannot do that: the top one's thumb
// covers the other). Each knob is a real slider for the keyboard and for screen readers.
import { useRef, useState } from 'react';
import GlassMenu, { GlassMenuItem } from '../GlassMenu.jsx';
import { RANGE_MIN, RANGE_MAX, RANGE_STEP, hourLabel } from '../../lib/mapTimeWindow.js';
import { MAP_DIM } from '../../lib/mapLayout.js';
import { ink, ink2, ink3, paper, photoPill } from '../../theme.js';

const TICKS = [10, 14, 18, 22, 26];
const SPAN = RANGE_MAX - RANGE_MIN;
const pct = (h) => ((h - RANGE_MIN) / SPAN) * 100;

export default function MapTimeBar({ win, options, dayLabel, onDay, onKnob, T, style }) {
  const [menu, setMenu] = useState(false);
  const [active, setActive] = useState(null); // 'from' | 'to' while that knob is dragged or has keyboard focus
  const [dragging, setDragging] = useState(false);
  const ruler = useRef(null);
  const dragKnob = useRef(null);
  const on = win.on;
  const currentKey = on ? win.key : 'all';

  const hourAt = (clientX) => {
    const r = ruler.current.getBoundingClientRect();
    return Math.round((RANGE_MIN + Math.max(0, Math.min(1, (clientX - r.left) / r.width)) * SPAN) / RANGE_STEP) * RANGE_STEP;
  };
  const onDown = (e) => {
    if (!on) return;
    const h = hourAt(e.clientX);
    const which = Math.abs(h - win.from) <= Math.abs(h - win.to) ? 'from' : 'to'; // the nearest knob
    dragKnob.current = which;
    setActive(which); setDragging(true);
    e.currentTarget.setPointerCapture(e.pointerId);
    onKnob(which, h);
  };
  const onMove = (e) => { if (dragKnob.current) onKnob(dragKnob.current, hourAt(e.clientX)); };
  const onUp = () => { dragKnob.current = null; setActive(null); setDragging(false); };
  const onKey = (which) => (e) => {
    const cur = which === 'from' ? win.from : win.to;
    const step = { ArrowRight: 1, ArrowUp: 1, ArrowLeft: -1, ArrowDown: -1, PageUp: 4, PageDown: -4 }[e.key];
    let next = null;
    if (step) next = cur + step * RANGE_STEP;
    else if (e.key === 'Home') next = RANGE_MIN;
    else if (e.key === 'End') next = RANGE_MAX;
    if (next == null) return;
    e.preventDefault();
    onKnob(which, next);
  };

  const knob = (which) => {
    const v = which === 'from' ? win.from : win.to;
    const act = active === which && (dragging || undefined);
    return (
      <div key={which} role="slider" tabIndex={on ? 0 : -1} aria-disabled={!on} data-testid={`map-time-knob-${which}`}
        aria-label={which === 'from' ? T('Từ giờ', 'From') : T('Đến giờ', 'To')} aria-orientation="horizontal"
        aria-valuemin={RANGE_MIN} aria-valuemax={RANGE_MAX} aria-valuenow={v} aria-valuetext={hourLabel(v)}
        className={`bb-tknob${act ? ' act' : ''}`} onKeyDown={onKey(which)}
        onFocus={() => setActive(which)} onBlur={() => { if (!dragKnob.current) setActive(null); }}
        style={{ left: `${pct(v)}%` }}>
        <span aria-hidden="true" className="bb-tknob-bubble" style={{ opacity: active === which ? 1 : 0 }}>{hourLabel(v)}</span>
      </div>
    );
  };

  return (
    <div data-testid="map-time-bar" style={{ position: 'absolute', left: 14, right: 14, zIndex: 3, ...style }}>
      {/* The glass is its own layer: photoPill carries a mask that would clip the day menu and the knob bubble. */}
      <div aria-hidden="true" style={{ ...photoPill({ position: 'absolute', borderRadius: 29 }), top: 0, left: 0, right: 0, height: 58, cursor: 'default' }} />
      <div style={{ position: 'relative', height: 58, display: 'flex', alignItems: 'center', gap: 6, padding: '0 18px 0 8px' }}>
        <GlassMenu open={menu} onOpenChange={setMenu} alignLeft above top={66} width={230} label={T('Chọn ngày', 'Pick a day')} menuTestId="map-time-menu"
          trigger={(
            <button type="button" onClick={() => setMenu(o => !o)} data-testid="map-time-day" aria-haspopup="menu" aria-expanded={menu}
              style={{ flex: 'none', height: 42, padding: '0 12px 0 15px', borderRadius: 21, border: 'none', background: ink, color: paper, fontFamily: 'inherit', fontSize: 13.5, fontWeight: 600, display: 'flex', alignItems: 'center', gap: 7, whiteSpace: 'nowrap', cursor: 'pointer' }}>
              {dayLabel}
              <svg aria-hidden="true" width={10} height={10} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={3} strokeLinecap="round" strokeLinejoin="round"><path d="m6 9 6 6 6-6" /></svg>
            </button>
          )}>
          {options.map(o => (
            <GlassMenuItem key={o.key} checked={o.key === currentKey} testId={`map-time-day-${o.key}`} onClick={() => onDay(o.key)}>
              <span style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                <span>{o.label}</span><small style={{ opacity: 0.65, fontWeight: 400 }}>{o.sub}</small>
              </span>
            </GlassMenuItem>
          ))}
        </GlassMenu>
        {/* The range: off (every event is in) for "All days". */}
        <div ref={ruler} data-testid="map-time-range" data-on={on ? 'true' : 'false'} onPointerDown={onDown} onPointerMove={onMove} onPointerUp={onUp} onPointerCancel={onUp}
          style={{ position: 'relative', flex: 1, height: 44, margin: '0 10px 0 8px', touchAction: 'none', cursor: on ? 'pointer' : 'default', opacity: on ? 1 : MAP_DIM.rangeOff, pointerEvents: on ? 'auto' : 'none', transition: 'opacity 0.2s ease' }}>
          <div aria-hidden="true" style={{ position: 'absolute', left: 0, right: 0, top: 14, height: 6, borderRadius: 3, background: 'rgba(var(--bb-fg-rgb),0.12)' }} />
          <div aria-hidden="true" style={{ position: 'absolute', top: 14, height: 6, borderRadius: 3, background: ink, left: `${pct(win.from)}%`, right: `${100 - pct(win.to)}%` }} />
          {TICKS.map(h => (
            <span key={h} aria-hidden="true" style={{ position: 'absolute', top: 30, left: `${pct(h)}%`, transform: 'translateX(-50%)', fontSize: 10, color: ink3, fontVariantNumeric: 'tabular-nums' }}>{hourLabel(h)}</span>
          ))}
          {knob('from')}
          {knob('to')}
        </div>
      </div>
      <span style={{ position: 'absolute', width: 1, height: 1, overflow: 'hidden', clip: 'rect(0 0 0 0)' }} aria-live="polite" data-testid="map-time-live">
        {on ? `${dayLabel}, ${hourLabel(win.from)} – ${hourLabel(win.to)}` : dayLabel}
      </span>
    </div>
  );
}

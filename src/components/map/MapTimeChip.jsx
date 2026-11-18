// Unified discovery (note 99, switch `unified_discovery`): the Map's time is ONE glass chip at the head of the chip row
// ("Hôm nay · 19–02"), replacing the 58 px MapTimeBar row. It opens a small popover with the same day choices and the
// same two-knob hour range (MapTimeRange) as MapTimeBar, so nothing the bar could do is lost: the window still dims
// rather than hides. The chip sits in a horizontal scroller, so the popover is rendered apart (MapExplore places it
// under the chip row) and the two are tied by `open` + refs. Closes on an outside tap, Esc or a day pick.
import { forwardRef, useEffect, useRef } from 'react';
import { MapTimeRange } from './MapTimeBar.jsx';
import { hourLabel } from '../../lib/mapTimeWindow.js';
import { ink, ink2, paper, photoPill, RADIUS } from '../../theme.js';

const pad = (n) => String(n % 24).padStart(2, '0');
/** "Hôm nay · 19–02" while a window is on, else the "All days" label. */
export function timeChipLabel(win, dayLabel) {
  return win?.on ? `${dayLabel} · ${pad(win.from)}–${pad(win.to)}` : dayLabel;
}

export const MapTimeChip = forwardRef(function MapTimeChip({ win, dayLabel, open, onToggle, T }, ref) {
  const on = !!win?.on;
  const label = timeChipLabel(win, dayLabel);
  return (
    <button ref={ref} type="button" onClick={onToggle} data-testid="map-time-chip" aria-haspopup="dialog" aria-expanded={open} aria-pressed={on}
      aria-label={T(`Thời gian: ${label}. Đổi`, `Time: ${label}. Change`)}
      style={{
        ...photoPill({ position: 'static', borderRadius: RADIUS.pill }),
        flex: 'none', display: 'inline-flex', alignItems: 'center', gap: 6, minHeight: 36, padding: '0 10px 0 11px', fontSize: 13, fontWeight: 600,
        whiteSpace: 'nowrap', fontFamily: 'inherit', cursor: 'pointer', color: ink,
        ...(on ? { background: ink, color: paper, border: `1px solid ${ink}`, backdropFilter: 'none', WebkitBackdropFilter: 'none', boxShadow: 'none' } : null),
      }}>
      <svg aria-hidden="true" width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.9} strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></svg>
      <span style={{ fontVariantNumeric: 'tabular-nums' }}>{label}</span>
      <svg aria-hidden="true" width={12} height={12} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.6} strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.6 }}><path d="m6 9 6 6 6-6" /></svg>
    </button>
  );
});

export function MapTimePopover({ open, onClose, chipRef, win, options, dayLabel, onDay, onKnob, T, style }) {
  const boxRef = useRef(null);
  useEffect(() => {
    if (!open) return undefined;
    const onDown = (e) => {
      if (boxRef.current?.contains(e.target) || chipRef?.current?.contains(e.target)) return;
      onClose(false);
    };
    const onKey = (e) => { if (e.key === 'Escape') { e.stopImmediatePropagation(); onClose(true); } };
    document.addEventListener('pointerdown', onDown, true);
    window.addEventListener('keydown', onKey, true);
    // Focus the checked day so the keyboard lands inside.
    requestAnimationFrame(() => {
      const box = boxRef.current;
      if (box && !box.contains(document.activeElement)) box.querySelector('[aria-checked="true"]')?.focus({ preventScroll: true });
    });
    return () => { document.removeEventListener('pointerdown', onDown, true); window.removeEventListener('keydown', onKey, true); };
  }, [open, onClose, chipRef]);
  if (!open) return null;
  const currentKey = win.on ? win.key : 'all';
  return (
    <div ref={boxRef} role="dialog" aria-label={T('Thời gian', 'Time')} data-testid="map-time-popover" className="bb-timepop"
      style={{ position: 'absolute', left: 12, width: 'min(320px, calc(100% - 24px))', zIndex: 6, pointerEvents: 'auto', ...style }}>
      {/* The glass is its own layer: photoPill carries a mask that would clip the knob bubble. */}
      <div aria-hidden="true" style={{ ...photoPill({ position: 'absolute', borderRadius: 22 }), inset: 0, cursor: 'default' }} />
      <div style={{ position: 'relative', padding: '8px 8px 6px' }}>
        <div role="radiogroup" aria-label={T('Chọn ngày', 'Pick a day')} style={{ display: 'flex', flexDirection: 'column' }}>
          {options.map(o => {
            const checked = o.key === currentKey;
            return (
              <button key={o.key} type="button" role="radio" aria-checked={checked} data-testid={`map-time-day-${o.key}`} onClick={() => onDay(o.key)}
                style={{ display: 'flex', alignItems: 'center', gap: 10, minHeight: 44, padding: '0 10px', border: 'none', borderRadius: 14, background: checked ? 'rgba(var(--bb-fg-rgb),0.08)' : 'transparent', color: ink, fontFamily: 'inherit', fontSize: 14.5, fontWeight: checked ? 700 : 500, textAlign: 'left', cursor: 'pointer' }}>
                <span aria-hidden="true" style={{ width: 16, flex: 'none', fontWeight: 700 }}>{checked ? '✓' : ''}</span>
                <span style={{ flex: 1 }}>{o.label}</span>
                <small style={{ color: ink2, fontWeight: 400, fontSize: 12.5 }}>{o.sub}</small>
              </button>
            );
          })}
        </div>
        <div style={{ borderTop: '1px solid rgba(var(--bb-fg-rgb),0.12)', margin: '6px 4px 0', padding: '10px 4px 0' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12.5, color: ink2, fontWeight: 600, padding: '0 6px' }}>
            <span>{T('Giờ', 'Hours')}</span>
            <span data-testid="map-time-hours" style={{ fontVariantNumeric: 'tabular-nums', color: win.on ? ink : ink2 }}>
              {win.on ? `${hourLabel(win.from)} – ${hourLabel(win.to)}` : T('Chọn một ngày trước', 'Pick a day first')}
            </span>
          </div>
          <div style={{ display: 'flex', paddingTop: 14 }}>
            <MapTimeRange win={win} onKnob={onKnob} T={T} margin="0 14px" />
          </div>
        </div>
      </div>
      <span style={{ position: 'absolute', width: 1, height: 1, overflow: 'hidden', clip: 'rect(0 0 0 0)' }} aria-live="polite" data-testid="map-time-live">
        {win.on ? `${dayLabel}, ${hourLabel(win.from)} – ${hourLabel(win.to)}` : dayLabel}
      </span>
    </div>
  );
}

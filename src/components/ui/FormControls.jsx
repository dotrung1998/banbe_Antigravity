// Low-friction form controls (note 48) — the web twins of iOS
// Views/FormControls.swift: a selectable chip, a −/+ count stepper, a
// named-step progress bar (with a head start) and a primary button that is a
// real <button disabled> and says WHY it is disabled.
import { paper, ink, display } from '../../theme.js';

const RULE = 'rgba(27,25,22,0.16)';

export function ChoiceChip({ label, selected, onClick, compact = false, testId }) {
  return (
    <button type="button" onClick={onClick} aria-pressed={selected} data-testid={testId}
      style={{
        fontSize: compact ? 11.5 : 13, fontWeight: selected ? 600 : 400, fontFamily: 'inherit',
        padding: compact ? '6px 10px' : '9px 14px', borderRadius: 999, cursor: 'pointer',
        background: selected ? ink : 'transparent', color: selected ? paper : ink,
        border: selected ? '1px solid transparent' : `1px solid ${RULE}`, whiteSpace: 'nowrap',
      }}>{label}</button>
  );
}

export function CountStepper({ value, min = 0, max = 99, step = 1, onChange, unit, testId }) {
  const canDec = value - step >= min;
  const canInc = value + step <= max;
  const btn = (sym, enabled, next, label) => (
    <button type="button" disabled={!enabled} aria-label={label} onClick={() => enabled && onChange(next)}
      style={{
        width: 36, height: 36, borderRadius: 12, fontSize: 18, fontFamily: 'inherit', background: 'transparent',
        border: `1px solid ${RULE}`, color: enabled ? ink : RULE, cursor: enabled ? 'pointer' : 'default',
      }}>{sym}</button>
  );
  return (
    <div role="group" aria-label={unit} data-testid={testId} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      {btn('−', canDec, Math.max(min, value - step), 'decrease')}
      <span aria-live="polite" style={{ ...display(18), minWidth: 28, textAlign: 'center', fontVariantNumeric: 'tabular-nums' }}>{value}</span>
      {btn('+', canInc, Math.min(max, value + step), 'increase')}
    </div>
  );
}

/** Fraction done; steps before `current` count as done unless `completed` is given. */
export function stepPercent(doneCount, total) {
  if (!total) return 0;
  return Math.round((Math.min(Math.max(doneCount, 0), total) / total) * 100);
}

export function encouragement(remaining, T) {
  if (remaining <= 0) return T('Xong rồi!', 'All done!');
  if (remaining === 1) return T('Còn 1 bước nữa thôi', 'Just 1 step to go');
  return T(`Tốt lắm, còn ${remaining} bước`, `Nice, ${remaining} steps to go`);
}

export function StepProgress({ steps, current, completed, message, showPercent = true, onSelect, testId }) {
  const isDone = (i) => (completed ? !!completed[i] : i < current);
  const doneCount = completed ? completed.filter(Boolean).length : current;
  const pct = stepPercent(doneCount, steps.length);
  return (
    <div data-testid={testId} role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct}
      aria-valuetext={`${pct}%`} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      {(showPercent || message) && (
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, fontWeight: 600, color: ink }}>
          <span>{message || ''}</span>
          {showPercent && <span style={{ opacity: 0.7, fontVariantNumeric: 'tabular-nums' }}>{pct}%</span>}
        </div>
      )}
      <div style={{ height: 5, borderRadius: 999, background: 'rgba(27,25,22,0.12)', overflow: 'hidden' }}>
        <div style={{ width: `${pct}%`, height: '100%', background: ink, borderRadius: 999, transition: 'width .25s ease-out' }} />
      </div>
      <div style={{ display: 'flex', gap: 4 }}>
        {steps.map((title, i) => {
          const done = isDone(i);
          const active = i === current && !done;
          const body = (
            <>
              <span aria-hidden style={{
                width: 20, height: 20, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center',
                background: done ? ink : active ? 'rgba(27,25,22,0.14)' : 'transparent', color: paper, fontSize: 11, fontWeight: 700,
                border: done ? 'none' : `1px solid ${RULE}`,
              }}>{done ? '✓' : active ? <span style={{ width: 7, height: 7, borderRadius: 999, background: ink }} /> : null}</span>
              <span style={{ fontSize: 10.5, fontWeight: active ? 600 : 400, opacity: active || done ? 1 : 0.55, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: '100%' }}>{title}</span>
            </>
          );
          const style = { flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, color: ink };
          return onSelect
            ? <button key={i} type="button" onClick={() => onSelect(i)} style={{ ...style, background: 'none', border: 'none', padding: 0, cursor: 'pointer', fontFamily: 'inherit' }}>{body}</button>
            : <div key={i} style={style}>{body}</div>;
        })}
      </div>
    </div>
  );
}

/** Booking journey: Event ✓ → Hold → Pay → Ticket. current: 1 hold, 2 pay, 3 ticket pending, 4 done. */
export function BookingJourneyProgress({ current, T }) {
  return (
    <StepProgress testId="booking-journey" current={current}
      steps={[T('Sự kiện', 'Event'), T('Giữ chỗ', 'Hold'), T('Thanh toán', 'Pay'), T('Vé', 'Ticket')]}
      message={encouragement(4 - current, T)} />
  );
}

/** Primary CTA: a real disabled button plus an optional reason caption. */
export function InkButton({ label, enabled = true, onClick, reason, style, testId }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      <button type="button" disabled={!enabled} onClick={onClick} data-testid={testId}
        aria-disabled={!enabled || undefined} aria-describedby={!enabled && reason ? `${testId}-reason` : undefined}
        style={{
          fontSize: 15, fontWeight: 600, fontFamily: 'inherit', textAlign: 'center', padding: 16, borderRadius: 999,
          border: 'none', background: enabled ? ink : 'rgba(27,25,22,0.16)', color: enabled ? paper : ink,
          cursor: enabled ? 'pointer' : 'default', transition: 'background .15s', ...style,
        }}>{label}</button>
      {!enabled && reason && (
        <div id={`${testId}-reason`} data-testid={`${testId}-reason`} style={{ fontSize: 12, textAlign: 'center', color: ink, opacity: 0.7 }}>{reason}</div>
      )}
    </div>
  );
}

/** Editable list of short options as removable chips + an "Add" field (replaces comma-separated text). */
export function OptionChipsEditor({ options, onChange, placeholder, T, testId }) {
  const add = (input) => {
    const v = input.value.trim();
    if (v && !options.includes(v)) onChange([...options, v]);
    input.value = '';
  };
  return (
    <div data-testid={testId} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      {options.length > 0 && (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
          {options.map(o => (
            <button key={o} type="button" onClick={() => onChange(options.filter(x => x !== o))} aria-label={`${o}, ${T('chạm để xoá', 'tap to remove')}`}
              style={{ fontSize: 12.5, fontFamily: 'inherit', padding: '7px 12px', borderRadius: 999, border: `1px solid ${RULE}`, background: 'transparent', color: ink, cursor: 'pointer' }}>
              {o} ✕
            </button>
          ))}
        </div>
      )}
      <form onSubmit={(e) => { e.preventDefault(); add(e.currentTarget.elements.opt); }} style={{ display: 'flex', gap: 8 }}>
        <input name="opt" placeholder={placeholder} data-testid={testId && `${testId}-field`}
          style={{ flex: 1, padding: '10px 12px', borderRadius: 8, border: `1px solid ${RULE}`, fontSize: 13.5, fontFamily: 'inherit' }} />
        <button type="submit" data-testid={testId && `${testId}-add`}
          style={{ fontSize: 13, fontWeight: 600, fontFamily: 'inherit', background: 'none', border: 'none', color: ink, cursor: 'pointer' }}>{T('Thêm', 'Add')}</button>
      </form>
    </div>
  );
}

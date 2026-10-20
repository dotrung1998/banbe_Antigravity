// Low-friction form controls (note 48) — the web twins of iOS
// Views/FormControls.swift: a selectable chip, a −/+ count stepper, a
// named-step progress bar (with a head start) and a primary button that is a
// real <button disabled> and says WHY it is disabled.
// Note 53: a three-level Button (primary / secondary / tertiary) so the main
// action never looks like the alternatives, and FieldNote for a field's
// error / warning line (the field itself gets aria-invalid / data-state, see
// the field-state rules in src/index.css).
import { paper, ink, display } from '../../theme.js';

const RULE = 'rgba(27,25,22,0.16)';

export function ChoiceChip({ label, selected, onClick, compact = false, testId }) {
  return (
    <button type="button" onClick={onClick} aria-pressed={selected} data-testid={testId} className="bb-press"
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

export function StepProgress({ steps, current, completed, message, showPercent = true, showBar = true, onSelect, testId }) {
  const isDone = (i) => (completed ? !!completed[i] : i < current);
  const doneCount = completed ? completed.filter(Boolean).length : current;
  const pct = stepPercent(doneCount, steps.length);
  const line = (on) => (on ? ink : 'rgba(var(--bb-fg-rgb),0.14)');
  return (
    <div data-testid={testId} role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct}
      aria-valuetext={`${pct}%`} style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      {(showPercent || message) && (
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12.5, fontWeight: 600, color: ink }}>
          <span>{message || ''}</span>
          {showPercent && <span style={{ opacity: 0.7, fontVariantNumeric: 'tabular-nums' }}>{pct}%</span>}
        </div>
      )}
      {showBar && (
        <div style={{ height: 5, borderRadius: 999, background: 'rgba(var(--bb-fg-rgb),0.12)', overflow: 'hidden' }}>
          <div style={{ width: `${pct}%`, height: '100%', background: ink, borderRadius: 999, transition: 'width .25s ease-out' }} />
        </div>
      )}
      <div style={{ display: 'flex' }}>
        {steps.map((title, i) => {
          const done = isDone(i);
          const active = i === current;
          const filled = done || active;
          // Numbered circle (✓ once done) on a connector that runs through the column, so circles and labels align.
          const body = (
            <>
              <span style={{ position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center', width: '100%', height: 36 }}>
                <span aria-hidden style={{ position: 'absolute', left: 0, width: '50%', height: 2, background: i === 0 ? 'transparent' : line(isDone(i - 1)) }} />
                <span aria-hidden style={{ position: 'absolute', right: 0, width: '50%', height: 2, background: i === steps.length - 1 ? 'transparent' : line(done) }} />
                <span style={{ position: 'relative', width: 28, height: 28, borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center',
                  background: filled ? ink : paper, color: filled ? paper : 'rgba(var(--bb-fg-rgb),0.6)', fontSize: 13, fontWeight: 700,
                  border: filled ? 'none' : '1.5px solid rgba(var(--bb-fg-rgb),0.25)', boxSizing: 'border-box',
                  boxShadow: active ? '0 0 0 4px rgba(var(--bb-fg-rgb),0.18)' : 'none' }}>
                  {done && !active ? '✓' : i + 1}
                  {done && active && (
                    <span aria-hidden style={{ position: 'absolute', top: -5, right: -5, width: 14, height: 14, borderRadius: 7, background: paper, color: ink,
                      fontSize: 9, display: 'flex', alignItems: 'center', justifyContent: 'center', border: `1.5px solid ${ink}`, boxSizing: 'border-box' }}>✓</span>
                  )}
                </span>
              </span>
              <span style={{ fontSize: 11, fontWeight: active ? 600 : 400, opacity: active || done ? 1 : 0.55, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: '100%' }}>{title}</span>
            </>
          );
          const style = { flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, color: ink };
          return onSelect
            ? <button key={i} type="button" onClick={() => onSelect(i)} aria-current={active ? 'step' : undefined}
                aria-label={done ? `${title} ✓` : title}
                style={{ ...style, background: 'none', border: 'none', padding: 0, cursor: 'pointer', fontFamily: 'inherit' }}>{body}</button>
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
      <button type="button" disabled={!enabled} onClick={onClick} data-testid={testId} className="bb-press"
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

/**
 * One button system (note 53). primary = solid ink, the one thing to do next; secondary = field fill with a
 * hairline, an alternative (optionally led by an emoji/icon); tertiary = text only, for skip/back/"later".
 * All three get the pressed state (.bb-press) and a 44px+ hit area.
 */
export function Button({ variant = 'primary', label, icon, onClick, disabled = false, testId, style, type = 'button', ariaLabel }) {
  const base = {
    display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8, minHeight: 52,
    fontFamily: 'inherit', fontSize: 15, fontWeight: 600, borderRadius: 999, cursor: disabled ? 'default' : 'pointer',
    padding: '0 22px', textAlign: 'center',
  };
  const look = variant === 'primary'
    ? { border: 'none', background: disabled ? 'rgba(var(--bb-fg-rgb),0.16)' : ink, color: disabled ? ink : paper }
    : variant === 'secondary'
      ? { border: '1px solid var(--bb-rule)', background: 'var(--bb-field)', color: ink, opacity: disabled ? 0.5 : 1 }
      : { border: 'none', background: 'none', color: ink, minHeight: 44, padding: '0 12px', fontWeight: 600, opacity: disabled ? 0.4 : 0.8 };
  return (
    <button type={type} onClick={disabled ? undefined : onClick} disabled={disabled} data-testid={testId} aria-label={ariaLabel}
      data-variant={variant} className="bb-press" style={{ ...base, ...look, ...style }}>
      {icon && <span aria-hidden="true" style={{ fontSize: 17, lineHeight: 1 }}>{icon}</span>}
      {label}
    </button>
  );
}

/**
 * The line under a field that has a problem. tone 'error' (alert) or 'warning' (honey), with an optional inline
 * action such as "Log in instead?". Give the field aria-invalid / data-state and aria-describedby={id}.
 */
export function FieldNote({ id, tone = 'error', children, actionLabel, onAction, testId }) {
  const color = tone === 'warning' ? 'var(--bb-honey)' : 'var(--bb-alert)';
  return (
    <p id={id} data-testid={testId} role={tone === 'error' ? 'alert' : 'status'}
      style={{ fontSize: 12.5, lineHeight: 1.45, color, margin: '6px 2px 0', fontWeight: 500 }}>
      {children}
      {actionLabel && onAction && (
        <>
          {' '}
          <button type="button" onClick={onAction} data-testid={testId ? `${testId}-action` : undefined}
            style={{ border: 'none', background: 'none', padding: 0, font: 'inherit', fontWeight: 700, color, textDecoration: 'underline', textDecorationStyle: 'dotted', textUnderlineOffset: 3, cursor: 'pointer' }}>
            {actionLabel}
          </button>
        </>
      )}
    </p>
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

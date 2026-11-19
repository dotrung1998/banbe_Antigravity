// End-of-list card (v2.3, note 81): a quiet block that closes the list — a small eyebrow, a serif line, a body line and
// actions (the first one primary), all on the leading edge like the rows above it. It used to be a dashed outline with
// three bobbing dots: the outline read as a placeholder and the dots as a second page indicator right above the real
// one. It fills the hole a short last page leaves (the Pager sizes the slot to the missing rows); with one row of room
// ('slim') it keeps the line and the main action side by side; with two ('mid') it drops the body so it never makes
// the page taller. It rises in when its page is shown (not with Reduce Motion).
// Also used for the empty states of the v2.3 lists (`EmptyCard`). Copy and actions: src/lib/listEnd.js.
import { slimmed } from '../../lib/listEnd.js';
import { SERIF } from '../event/v23Style.js';

const CSS = `
@keyframes bbEndIn { from { opacity: 0; transform: translateY(14px); } to { opacity: 1; transform: none; } }
.bb-end { animation: bbEndIn .62s cubic-bezier(.2,1.04,.3,1) .18s both; }
.bb-end-btn { transition: transform .11s cubic-bezier(.22,.61,.36,1); }
.bb-end-btn:active { transform: scale(.95); }
@media (prefers-reduced-motion: reduce) { .bb-end { animation: none; } }
`;

const card = { background: 'var(--bb-block)', color: 'var(--bb-fg)' };

function Btn({ a, tx, onAction }) {
  return (
    <button type="button" data-testid={a.testId || `list-end-${a.act}`} onClick={() => onAction(a.act)} className="bb-end-btn"
      style={{ minHeight: 44, padding: '0 16px', borderRadius: 999, border: a.primary ? '1px solid transparent' : '1px solid var(--bb-rule)', background: a.primary ? 'var(--bb-fg)' : 'transparent',
        color: a.primary ? 'var(--bb-bg)' : 'var(--bb-fg)', fontFamily: 'inherit', fontSize: 13.5, fontWeight: 600, cursor: 'pointer', whiteSpace: 'nowrap' }}>
      {tx(a.label)}
    </button>
  );
}

/**
 * @param {object} p
 * @param {{eyebrow,title,body,actions,kind}} p.card  { vi, en } pairs from listEnd.js
 * @param {'solo'|'slim'|'mid'|'fill'} p.variant
 * @param {(act: string) => void} p.onAction
 * @param {(vi:string, en:string) => string} p.T
 */
export default function EndCard({ card: data, variant, onAction, T }) {
  const c = variant === 'slim' ? slimmed(data) : data;
  const tx = (pair) => (pair ? T(pair.vi, pair.en) : '');
  const slim = variant === 'slim';
  const mid = variant === 'mid';
  const fill = variant !== 'solo';
  if (slim) {
    const pri = c.actions.find(a => a.primary) || c.actions[0];
    return (
      <div data-testid="list-end-card" data-kind={data.kind} className="bb-end"
        style={{ ...card, flex: 1, margin: '2px 20px 14px', padding: '12px 12px 12px 18px', borderRadius: 22, display: 'grid', gridTemplateColumns: 'minmax(0,1fr) auto', alignItems: 'center', gap: 12 }}>
        <style>{CSS}</style>
        <div style={{ fontFamily: SERIF, fontSize: 16.5, lineHeight: 1.25, letterSpacing: '-0.01em', minWidth: 0 }}>{tx(c.title)}</div>
        {pri && <Btn a={pri} tx={tx} onAction={onAction} />}
      </div>
    );
  }
  return (
    <div data-testid="list-end-card" data-kind={data.kind} className="bb-end"
      style={{ ...card, flex: fill ? 1 : 'none', margin: '6px 20px 14px', padding: mid ? '16px 20px' : '20px', borderRadius: 22, display: 'flex', flexDirection: 'column', alignItems: 'flex-start', justifyContent: 'flex-start', textAlign: 'left' }}>
      <style>{CSS}</style>
      {c.eyebrow && <span style={{ fontSize: 'var(--bb-text-kicker)', letterSpacing: '0.13em', textTransform: 'uppercase', color: 'var(--bb-fg-3)', fontWeight: 700 }}>{tx(c.eyebrow)}</span>}
      <div style={{ fontFamily: SERIF, fontSize: mid ? 19 : 22, fontWeight: 400, lineHeight: 1.18, letterSpacing: '-0.02em', margin: mid ? '6px 0 0' : '8px 0 6px' }}>{tx(c.title)}</div>
      {c.body && !mid && <p style={{ fontSize: 13, lineHeight: 1.55, color: 'var(--bb-fg-2)', margin: 0 }}>{tx(c.body)}</p>}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: mid ? 12 : 16 }}>
        {c.actions.map(a => <Btn key={a.act} a={a} tx={tx} onAction={onAction} />)}
      </div>
    </div>
  );
}

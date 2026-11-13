// End-of-list card (v2.3, note 81): fills the hole a short last page leaves, written for where you are. The Pager
// sizes its slot to the missing rows; this card fills that slot. 'slim' (one row of room) keeps one line and one
// action. Copy and actions come from src/lib/listEnd.js.
import { slimmed } from '../../lib/listEnd.js';

/**
 * @param {object} p
 * @param {{eyebrow,title,body,actions}} p.card  { vi, en } pairs from listEnd.js
 * @param {'solo'|'slim'|'mid'|'fill'} p.variant
 * @param {(act: string) => void} p.onAction
 * @param {(vi:string, en:string) => string} p.T
 */
export default function EndCard({ card, variant, onAction, T }) {
  const c = variant === 'slim' ? slimmed(card) : card;
  const tx = (pair) => (pair ? T(pair.vi, pair.en) : '');
  const slim = variant === 'slim';
  return (
    <div data-testid="list-end-card" data-kind={card.kind}
      style={{ flex: 1, margin: '2px 20px 14px', padding: slim ? '12px 14px' : '16px 16px 14px', borderRadius: 16, background: 'var(--bb-block)', display: 'flex', flexDirection: slim ? 'row' : 'column', alignItems: slim ? 'center' : 'stretch', justifyContent: slim ? 'space-between' : 'center', gap: slim ? 12 : 6 }}>
      <div style={{ minWidth: 0 }}>
        {!slim && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
            <span aria-hidden="true" style={{ display: 'flex', gap: 3 }}>{[0, 1, 2].map(i => <i key={i} style={{ width: 4, height: 4, borderRadius: 2, background: 'currentColor', opacity: 0.5 }} />)}</span>
            <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: '0.08em', textTransform: 'uppercase', opacity: 0.72 }}>{tx(c.eyebrow)}</span>
          </div>
        )}
        <div style={{ fontSize: slim ? 14 : 16.5, fontWeight: 600, lineHeight: 1.3 }}>{tx(c.title)}</div>
        {c.body && variant !== 'mid' && <p style={{ fontSize: 13.5, lineHeight: 1.45, opacity: 0.74, margin: '4px 0 0' }}>{tx(c.body)}</p>}
      </div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: slim ? 0 : 10, flex: 'none' }}>
        {c.actions.map(a => (
          <button key={a.act} type="button" data-testid={`list-end-${a.act}`} onClick={() => onAction(a.act)}
            style={{ minHeight: 44, padding: '0 16px', borderRadius: 999, border: a.primary ? 'none' : '1px solid var(--bb-rule)', background: a.primary ? 'var(--bb-fg)' : 'none', color: a.primary ? 'var(--bb-bg)' : 'inherit', fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer' }}>
            {tx(a.label)}
          </button>
        ))}
      </div>
    </div>
  );
}

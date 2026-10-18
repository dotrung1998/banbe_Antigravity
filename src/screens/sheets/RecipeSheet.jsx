// "Recipe for success" sheet + compact meter (note 50). Lists the 10 ingredients from src/lib/eventRecipe.js,
// each with what to do, why (naming its evidence: "Based on N similar events" or "General banbe tip") and a
// Fix button that jumps to the step. Informational only: it never blocks submitting. iOS: Views/RecipeSheet.swift.
import { useEffect } from 'react';
import { paper, ink, rule, display, RADIUS } from '../../theme.js';
import { recipeCopy, recipeScore } from '../../lib/eventRecipe.js';

const STATUS_MARK = { good: '✓', improve: '◐', missing: '○' };

export function RecipeMeter({ checks, onOpen, T }) {
  const { good, total } = recipeScore(checks);
  return (
    <button type="button" onClick={onOpen} data-testid="create-recipe-meter" data-good={good} data-total={total}
      aria-label={T(`Công thức thành công: ${good} trên ${total}. Xem gợi ý`, `Recipe for success: ${good} of ${total}. See tips`)}
      style={{ display: 'flex', alignItems: 'center', gap: 10, width: '100%', marginTop: 10, padding: '8px 12px', border: `1px solid ${rule}`, borderRadius: RADIUS.pill, background: 'transparent', color: ink, fontFamily: 'inherit', cursor: 'pointer' }}>
      <span style={{ fontSize: 12.5, fontWeight: 700, whiteSpace: 'nowrap' }}>{T('Công thức', 'Recipe')} {good}/{total}</span>
      <span aria-hidden="true" style={{ flex: 1, display: 'flex', gap: 3 }}>
        {checks.map(c => (
          <span key={c.id} style={{ flex: 1, height: 5, borderRadius: 3, background: c.status === 'good' ? 'rgba(var(--bb-fg-rgb),0.85)' : c.status === 'improve' ? 'var(--bb-honey)' : 'rgba(var(--bb-fg-rgb),0.15)' }} />
        ))}
      </span>
      <span style={{ fontSize: 12, fontWeight: 600, opacity: 0.7, whiteSpace: 'nowrap' }}>{T('Xem gợi ý', 'See tips')} ›</span>
    </button>
  );
}

/** Inline list used by the sheet and by the Review step. */
export function RecipeList({ checks, onFix, T, compact = false }) {
  const order = { missing: 0, improve: 1, good: 2 };
  const sorted = [...checks].sort((a, b) => order[a.status] - order[b.status]);
  return (
    <div data-testid="create-recipe-list" style={{ display: 'flex', flexDirection: 'column' }}>
      {sorted.map(c => {
        const { title, detail } = recipeCopy(c, T);
        return (
          <div key={c.id} data-testid={`recipe-${c.id}`} data-status={c.status}
            style={{ display: 'flex', gap: 12, alignItems: 'flex-start', padding: '12px 0', borderBottom: `1px solid ${rule}` }}>
            <span aria-label={c.status} style={{ width: 22, height: 22, flex: 'none', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12, fontWeight: 700,
              background: c.status === 'good' ? 'rgba(var(--bb-fg-rgb),0.85)' : 'transparent', color: c.status === 'good' ? 'var(--bb-bg)' : c.status === 'improve' ? 'var(--bb-honey)' : ink,
              border: c.status === 'good' ? 'none' : `1.5px solid ${c.status === 'improve' ? 'var(--bb-honey)' : 'rgba(var(--bb-fg-rgb),0.3)'}` }}>{STATUS_MARK[c.status]}</span>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 14, fontWeight: 600 }}>{title}</div>
              {(!compact || c.status !== 'good') && <div style={{ fontSize: 12.5, lineHeight: 1.45, opacity: 0.72, marginTop: 2 }}>{detail}</div>}
            </div>
            {c.status !== 'good' && onFix && (
              <button type="button" onClick={() => onFix(c)} data-testid={`recipe-fix-${c.id}`}
                style={{ flex: 'none', border: `1px solid ${rule}`, borderRadius: RADIUS.pill, background: 'none', color: ink, fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600, padding: '6px 12px', cursor: 'pointer' }}>
                {T('Sửa', 'Fix')}
              </button>
            )}
          </div>
        );
      })}
    </div>
  );
}

export default function RecipeSheet({ checks, hasData, n, onFix, onClose, T }) {
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  const { good, total } = recipeScore(checks);
  return (
    <div onClick={onClose} data-testid="create-recipe-backdrop"
      style={{ position: 'fixed', inset: 0, zIndex: 60, background: 'rgba(12,12,12,0.45)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'banbeFade 0.2s ease both' }}>
      <div role="dialog" aria-modal="true" aria-label={T('Công thức thành công', 'Recipe for success')} onClick={(e) => e.stopPropagation()} data-testid="create-recipe-sheet"
        style={{ background: paper, color: ink, borderRadius: '22px 22px 0 0', maxHeight: '86%', display: 'flex', flexDirection: 'column', animation: 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
        <div style={{ padding: '18px 22px 10px', borderBottom: `1px solid ${rule}` }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span style={{ ...display(19) }}>{T('Công thức thành công', 'Recipe for success')}</span>
            <button type="button" onClick={onClose} aria-label={T('Đóng', 'Close')} data-testid="create-recipe-close"
              style={{ width: 34, height: 34, borderRadius: '50%', border: 'none', background: 'rgba(var(--bb-fg-rgb),0.07)', color: ink, fontSize: 18, cursor: 'pointer' }}>×</button>
          </div>
          <div style={{ fontSize: 12.5, opacity: 0.7, marginTop: 4 }}>
            {T(`${good}/${total} thành phần đã ổn.`, `${good} of ${total} ingredients in place.`)}{' '}
            {hasData
              ? T(`Số liệu từ ${n} sự kiện tương tự trên banbe.`, `Numbers come from ${n} similar events on banbe.`)
              : T('Chưa đủ sự kiện tương tự để so sánh — đây là mẹo chung.', 'Not enough similar events to compare yet — these are general tips.')}
            {' '}{T('Không bắt buộc để gửi.', 'Never required to submit.')}
          </div>
        </div>
        <div style={{ overflowY: 'auto', padding: '0 22px 28px' }}>
          <RecipeList checks={checks} onFix={(c) => { onClose(); onFix(c); }} T={T} />
        </div>
      </div>
    </div>
  );
}

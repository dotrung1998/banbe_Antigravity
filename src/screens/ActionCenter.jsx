import { ink, alert, fieldGlass, display } from '../theme.js';

// TASK A (2026-10-01 UX foundation pass) — reusable presentational piece:
// takes the already-built, already-sorted `items` (see src/lib/
// actionCenter.js) and renders at most 3 cards + a "Xem tất cả" row when
// more exist (rule 3). Empty `items` renders nothing at all (rule 10 — the
// section itself must not exist, not just be visually empty). Card style
// reuses Home.jsx's existing PhaseBanner look exactly, just generalized to
// a shared component both Home and Account/Dashboard can mount.
export default function ActionCenter({ items, onSeeAll, T }) {
  if (!items.length) return null;
  const visible = items.slice(0, 3);
  const hasMore = items.length > 3;

  return (
    <div style={{ margin: '10px 20px 0', display: 'flex', flexDirection: 'column', gap: 8 }} data-testid="action-center">
      <span style={{ fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.7 }}>{T('Việc cần xử lý', 'Things to do')}</span>
      {visible.map(item => (
        <div
          key={item.id}
          onClick={item.onClick}
          data-testid={item.testId}
          style={{ ...fieldGlass({ padding: '12px 14px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, cursor: 'pointer' }) }}
        >
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: item.severity === 'overdue' ? alert : ink }}>{item.label}</span>
            <span style={{ fontSize: 12.5, lineHeight: 1.4, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
              {item.detail}
            </span>
          </div>
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.7, flex: 'none', marginLeft: 12 }}>{item.ctaLabel} ›</span>
        </div>
      ))}
      {hasMore && (
        <div onClick={onSeeAll} data-testid="action-center-see-all" style={{ textAlign: 'center', fontSize: 12, fontWeight: 600, color: ink, opacity: 0.75, padding: '4px 0', cursor: 'pointer' }}>
          {T('Xem tất cả', 'See all')}
        </div>
      )}
    </div>
  );
}

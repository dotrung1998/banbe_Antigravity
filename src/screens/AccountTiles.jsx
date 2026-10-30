import { ink, ink2, ink3, surface1, divider, alert, display } from '../theme.js';
import { formatBadgeCount } from '../lib/badges.js';
import { RowIcon } from './Account.jsx';

// Note 66 (Simple Shell, Phase 2): Account's building blocks after the tabs were removed.
// - AccountTileGrid / AccountTile: the four big 2x2 tiles at the top (>= 88px tall, whole tile is the target).
// - MoreList / MoreRow: the single grouped "More" card (52px rows, hairline dividers, chevrons).
// Both sit on `surface1` with no border, so dark mode reads as depth, not outlines.

function Badge({ count, testId }) {
  if (!count) return null;
  return (
    <span
      aria-hidden
      title={String(count)}
      data-testid={testId}
      style={{ minWidth: 20, height: 20, borderRadius: 10, padding: '0 6px', boxSizing: 'border-box', background: alert, color: 'var(--bb-on-alert)', fontSize: 11, fontWeight: 700, lineHeight: '20px', textAlign: 'center', flex: 'none' }}
    >
      {formatBadgeCount(count)}
    </span>
  );
}

/** One big tile: icon + title + one value line, badge in the corner. A real <button> for keyboard and screen readers. */
export function AccountTile({ tileKey, icon, title, value, badge = 0, onClick, T, dataAttrs }) {
  const parts = [title, value, badge > 0 ? T(`${badge} mục mới`, `${badge} new`) : null].filter(Boolean);
  return (
    <button
      type="button"
      onClick={onClick}
      data-testid={`account-tile-${tileKey}`}
      aria-label={parts.join(', ')}
      {...dataAttrs}
      style={{
        minHeight: 88, minWidth: 0, padding: 14, boxSizing: 'border-box', border: 'none', borderRadius: 14, background: surface1,
        display: 'flex', flexDirection: 'column', alignItems: 'flex-start', justifyContent: 'space-between', gap: 8,
        textAlign: 'left', cursor: 'pointer', color: ink, font: 'inherit', WebkitTapHighlightColor: 'transparent',
      }}
    >
      <span style={{ display: 'flex', width: '100%', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <RowIcon kind={icon} size={26} />
        <Badge count={badge} testId={`account-tile-${tileKey}-badge`} />
      </span>
      <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0, width: '100%' }}>
        <span style={{ fontSize: 15, fontWeight: 600, color: ink, lineHeight: 1.25 }}>{title}</span>
        {value && <span style={{ fontSize: 12, lineHeight: 1.35, color: ink2, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{value}</span>}
      </span>
    </button>
  );
}

export function AccountTileGrid({ tiles, T }) {
  return (
    <div data-testid="account-tiles" style={{ margin: '16px 20px 0', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
      {tiles.map(t => <AccountTile key={t.tileKey} {...t} T={T} />)}
    </div>
  );
}

/** Section label above a group ("More"). */
export function AccountSectionLabel({ label, testId }) {
  return (
    <div data-testid={testId} style={{ padding: '24px 24px 8px' }}>
      <span style={{ fontSize: 12, fontWeight: 600, letterSpacing: '0.04em', textTransform: 'uppercase', color: ink3 }}>{label}</span>
    </div>
  );
}

/** The grouped "More" card: rows separated by `divider` hairlines. */
export function MoreList({ children, testId }) {
  const rows = [].concat(children).flat().filter(Boolean);
  return (
    <div data-testid={testId} style={{ margin: '0 20px', borderRadius: 14, background: surface1, overflow: 'hidden' }}>
      {rows.map((row, i) => (
        <div key={i} style={{ borderTop: i > 0 ? `1px solid ${divider}` : 'none', position: 'relative' }}>{row}</div>
      ))}
    </div>
  );
}

/** A 52px row: icon + label (+ optional subtitle) + optional trailing text / badge + chevron (or a custom trailing node). */
export function MoreRow({ icon, label, sub, trailing, badge = 0, badgeLabel, onClick, testId, end, disabled = false, ariaLabel, role = 'button', ariaChecked }) {
  return (
    <div
      onClick={disabled ? undefined : onClick}
      onKeyDown={(e) => { if (!disabled && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); onClick?.(); } }}
      role={role} tabIndex={0} aria-disabled={disabled || undefined} aria-label={ariaLabel} aria-checked={ariaChecked}
      data-testid={testId}
      style={{ minHeight: 52, boxSizing: 'border-box', padding: '10px 16px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, cursor: disabled ? 'default' : 'pointer', opacity: disabled ? 0.55 : 1 }}
    >
      <span style={{ display: 'flex', alignItems: 'center', gap: 12, minWidth: 0 }}>
        <RowIcon kind={icon} />
        <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
          <span style={{ fontSize: 15, color: ink }}>{label}</span>
          {sub && <span style={{ fontSize: 12, lineHeight: 1.4, color: ink2 }}>{sub}</span>}
        </span>
      </span>
      <span style={{ display: 'flex', alignItems: 'center', gap: 10, flex: 'none' }}>
        {badge > 0 && <span role="status" aria-label={badgeLabel} data-testid={testId ? `${testId}-badge` : undefined} style={{ minWidth: 20, height: 20, borderRadius: 10, padding: '0 6px', boxSizing: 'border-box', background: alert, color: 'var(--bb-on-alert)', fontSize: 11, fontWeight: 700, lineHeight: '20px', textAlign: 'center' }}>{formatBadgeCount(badge)}</span>}
        {trailing != null && trailing !== '' && <span style={{ fontSize: 13, color: ink2 }}>{trailing}</span>}
        {end !== undefined ? end : <span aria-hidden style={{ fontSize: 17, color: ink3, lineHeight: 1 }}>›</span>}
      </span>
    </div>
  );
}

/** Compact rewards strip: one row, "🔥 streak · coins ›". */
export function RewardsStrip({ label, ariaLabel, onClick }) {
  return (
    <button
      type="button" onClick={onClick} data-testid="account-rewards" aria-label={ariaLabel || label}
      style={{ margin: '8px 20px 0', width: 'calc(100% - 40px)', minHeight: 48, padding: '0 16px', boxSizing: 'border-box', border: 'none', borderRadius: 14, background: surface1, color: ink, font: 'inherit', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, cursor: 'pointer', textAlign: 'left' }}
    >
      <span style={{ ...display(15, { fontVariantNumeric: 'tabular-nums' }) }}>{label}</span>
      <span aria-hidden style={{ fontSize: 17, color: ink3, lineHeight: 1 }}>›</span>
    </button>
  );
}

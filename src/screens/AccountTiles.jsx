import { ink, ink2, ink3, block, divider, alert, display } from '../theme.js';
import { formatBadgeCount } from '../lib/badges.js';
import { RowIcon } from './Account.jsx';

// Note 66 (Simple Shell, Phase 2): Account's building blocks after the tabs were removed.
// - AccountTileGrid / AccountTile: the four big 2x2 tiles at the top (>= 88px tall, whole tile is the target).
// - MoreList / MoreRow: the single grouped "More" card (52px rows, hairline dividers, chevrons).
// Both sit on `block` (note 66 follow-up: light #EEE8DA so they read on paper, dark unchanged) with no border.

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

/** One shortcut: icon + label, badge on the icon's corner (prototype `.shortcuts`). */
export function AccountTile({ tileKey, icon, title, value, badge = 0, onClick, T, dataAttrs }) {
  return (
    <button type="button" onClick={onClick} data-testid={`account-tile-${tileKey}`}
      aria-label={[title, badge > 0 ? T(`${badge} mục mới`, `${badge} new`) : null].filter(Boolean).join(', ')} {...dataAttrs}
      style={{ position: 'relative', padding: '16px 0 14px', border: 'none', background: 'none', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8,
        color: ink2, font: 'inherit', fontSize: 12, cursor: 'pointer', WebkitTapHighlightColor: 'transparent' }}>
      <span style={{ color: ink, display: 'flex' }}><RowIcon kind={icon} size={26} /></span>
      <span>{title}</span>
      {badge > 0 && <span style={{ position: 'absolute', top: 8, right: 14 }}><Badge count={badge} testId={`account-tile-${tileKey}-badge`} /></span>}
    </button>
  );
}

export function AccountTileGrid({ tiles, T }) {
  return (
    <div data-testid="account-tiles" style={{ margin: '18px 20px 0', display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', borderTop: `1px solid ${divider}`, borderBottom: `1px solid ${divider}` }}>
      {tiles.map(x => <AccountTile key={x.tileKey} {...x} T={T} />)}
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
    <div data-testid={testId} style={{ margin: '0 20px' }}>
      {rows.map((row, i) => (
        <div key={i} style={{ borderBottom: `1px solid ${divider}`, position: 'relative' }}>{row}</div>
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
      style={{ minHeight: 56, boxSizing: 'border-box', padding: '14px 0', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, cursor: disabled ? 'default' : 'pointer', opacity: disabled ? 0.55 : 1 }}
    >
      <span style={{ display: 'flex', alignItems: 'center', gap: 14, minWidth: 0 }}>
        <RowIcon kind={icon} size={24} />
        <span style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
          <span style={{ fontSize: 15, color: ink }}>{label}</span>
          {sub && <span style={{ fontSize: 12, lineHeight: 1.4, color: ink2 }}>{sub}</span>}
        </span>
      </span>
      <span style={{ display: 'flex', alignItems: 'center', gap: 10, flex: 'none' }}>
        {badge > 0 && <span role="status" aria-label={badgeLabel} data-testid={testId ? `${testId}-badge` : undefined} style={{ minWidth: 20, height: 20, borderRadius: 10, padding: '0 6px', boxSizing: 'border-box', background: alert, color: 'var(--bb-on-alert)', fontSize: 11, fontWeight: 700, lineHeight: '20px', textAlign: 'center' }}>{formatBadgeCount(badge)}</span>}
        {trailing != null && trailing !== '' && <span style={{ fontSize: 13, color: ink3 }}>{trailing}</span>}
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
      style={{ margin: '8px 20px 0', width: 'calc(100% - 40px)', minHeight: 48, padding: '0 16px', boxSizing: 'border-box', border: 'none', borderRadius: 14, background: block, color: ink, font: 'inherit', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, cursor: 'pointer', textAlign: 'left' }}
    >
      <span style={{ ...display(15, { fontVariantNumeric: 'tabular-nums' }) }}>{label}</span>
      <span aria-hidden style={{ fontSize: 17, color: ink3, lineHeight: 1 }}>›</span>
    </button>
  );
}

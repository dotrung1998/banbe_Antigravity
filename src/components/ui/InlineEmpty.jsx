// Calm Pass guided empty state for ONE section (not a whole screen; that is EmptyState.jsx). A dashed outline, so it
// can never be mistaken for real content, one bold line, one sentence and at most one action (44px, `block` capsule).
// Twin of iOS EmptyStateViews.swift `InlineEmptyState`.
import { ink, ink2, block, RADIUS } from '../../theme.js';

export const inlineEmptyAction = {
  display: 'inline-flex', alignItems: 'center', gap: 6, minHeight: 44, padding: '0 16px', borderRadius: 999, border: 'none',
  background: block, color: ink, fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer',
};

export default function InlineEmpty({ title, message, actionLabel, actionIcon, onAction, actionTestId, testId }) {
  return (
    <div data-testid={testId} style={{
      padding: 16, borderRadius: RADIUS.card, border: '1.2px dashed rgba(var(--bb-fg-rgb),0.3)', color: ink,
      display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 4,
    }}>
      <div style={{ fontSize: 14.5, fontWeight: 600, lineHeight: 1.35 }}>{title}</div>
      <p style={{ margin: 0, fontSize: 13, lineHeight: 1.45, color: ink2 }}>{message}</p>
      {actionLabel && onAction && (
        <button type="button" className="bb-press" onClick={onAction} data-testid={actionTestId} style={{ ...inlineEmptyAction, marginTop: 8 }}>
          {actionIcon && <span aria-hidden="true">{actionIcon}</span>}{actionLabel}
        </button>
      )}
    </div>
  );
}

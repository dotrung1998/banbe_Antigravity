import { ink } from '../theme.js';

// "✓ Following" marker for hosts the signed-in account follows. Plain inline text next to the
// host name (never positioned over an avatar), so it can't collide with story rings.
export default function FollowingBadge({ T, testId = 'following-badge', style }) {
  const label = T('Đang theo dõi', 'Following');
  return (
    <span
      data-testid={testId}
      aria-label={label}
      style={{ display: 'inline-flex', alignItems: 'center', gap: 3, fontSize: 11, fontWeight: 600, color: ink, opacity: 0.8, whiteSpace: 'nowrap', ...style }}
    >
      <span aria-hidden="true">✓</span>{label}
    </span>
  );
}

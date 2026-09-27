import { TAB_OUTLINE_SHAPES } from './BottomTabBar.jsx';
import { ink, rule } from '../theme.js';

// Read once at module load — same pattern StoryViewer.jsx already
// established for this exact media query (a live prefers-reduced-motion
// change mid-session is not something this component needs to react to).
const REDUCE_MOTION = typeof window !== 'undefined' && window.matchMedia
  ? window.matchMedia('(prefers-reduced-motion: reduce)').matches
  : false;

// Refresh-indicator fix pass (2026-09-27, follow-up A) — replaces the
// generic circular spinner with a thin stroke segment traveling around
// the OUTLINE of the tab actually being refreshed (never a filled icon),
// reusing BottomTabBar.jsx's own exported outline shapes so both places
// draw the exact same silhouette. Before release, the stroke simply grows
// with pull distance (a static reveal, no travel); once the real reload
// is running, a fixed-length segment travels the outline continuously
// until it resolves. Reduce Motion drops the travel animation entirely —
// a static outline plus this element's own `aria-live` region (both
// platforms' "Đang làm mới" requirement) is what's left to announce
// progress.
const SEGMENT_PCT = 26;

export default function RootRefreshIndicator({ screen, progress, refreshing, label }) {
  const shape = TAB_OUTLINE_SHAPES[screen] || TAB_OUTLINE_SHAPES.home;
  const shapeEl = (extraProps) => {
    if (shape.path) return <path d={shape.path} pathLength={100} fill="none" {...extraProps} />;
    if (shape.rect) return <rect {...shape.rect} pathLength={100} fill="none" {...extraProps} />;
    if (shape.circle) return <circle {...shape.circle} pathLength={100} fill="none" {...extraProps} />;
    return null;
  };
  const staticDashoffset = 100 - Math.min(1, progress) * 100;
  const showTravel = refreshing && !REDUCE_MOTION;

  return (
    <span role="status" aria-live="polite" style={{ display: 'inline-flex', position: 'relative' }}>
      <svg width={26} height={26} viewBox="0 0 24 24" aria-hidden="true" focusable="false">
        {shapeEl({ stroke: rule, strokeWidth: 2.2 })}
        {showTravel ? (
          shapeEl({
            stroke: ink, strokeWidth: 2.4, strokeLinecap: 'round',
            strokeDasharray: `${SEGMENT_PCT} ${100 - SEGMENT_PCT}`,
            style: { animation: 'gocRefreshTravel 0.9s linear infinite' },
          })
        ) : (
          shapeEl({
            stroke: ink, strokeWidth: 2.4, strokeLinecap: 'round',
            strokeDasharray: '100 100', strokeDashoffset: refreshing ? 0 : staticDashoffset,
          })
        )}
      </svg>
      <span style={{ position: 'absolute', width: 1, height: 1, overflow: 'hidden', clip: 'rect(0 0 0 0)' }}>
        {refreshing ? label : ''}
      </span>
    </span>
  );
}

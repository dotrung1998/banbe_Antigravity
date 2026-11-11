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

// One shared geometry for every dock screen (Home, Schedule, Activity, Account). The whole screen (incl. its sticky
// header) translates down by the pull distance, so the gap the pull opens is always at the very top of the scroller:
// the chip is centred in that gap, never over a header/tab/chip. While refreshing the content is held at
// PULL_GAP_PX = chip + padding; App.jsx reads this same constant so the content offset and the chip can't drift apart.
export const PULL_CHIP_PX = 40;
export const PULL_GAP_PX = PULL_CHIP_PX + 16;
export const PULL_TRIGGER_PX = 64;

export default function RootRefreshIndicator({ screen, pullDist, isPulling, refreshing, error, visible, label }) {
  const shape = TAB_OUTLINE_SHAPES[screen] || TAB_OUTLINE_SHAPES.home;
  const shapeEl = (extraProps) => {
    if (shape.path) return <path d={shape.path} pathLength={100} fill="none" {...extraProps} />;
    if (shape.rect) return <rect {...shape.rect} pathLength={100} fill="none" {...extraProps} />;
    if (shape.circle) return <circle {...shape.circle} pathLength={100} fill="none" {...extraProps} />;
    return null;
  };
  const progress = Math.min(1, pullDist / PULL_TRIGGER_PX);
  const ready = !refreshing && progress >= 1;
  const held = refreshing || !!error;
  const eff = held ? 1 : progress;
  const centre = held ? PULL_GAP_PX / 2 : Math.max(PULL_CHIP_PX / 2 - 6, pullDist / 2);
  const shown = visible && (held || pullDist > 0);
  const scale = REDUCE_MOTION ? 1 : shown ? 0.6 + 0.4 * eff : 0.6;
  const staticDashoffset = 100 - progress * 100;
  const showTravel = refreshing && !REDUCE_MOTION;
  const ease = 'cubic-bezier(.22,.61,.36,1)';
  const chip = {
    width: PULL_CHIP_PX, height: PULL_CHIP_PX, borderRadius: '50%', boxSizing: 'border-box',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    background: 'color-mix(in srgb, var(--bb-bg) 96%, transparent)', border: `1px solid ${rule}`,
    boxShadow: '0 4px 14px rgba(27,25,22,0.16), 0 1px 3px rgba(27,25,22,0.10)',
  };

  return (
    <div
      data-testid="pull-to-refresh-indicator"
      style={{
        position: 'absolute', top: 0, left: 0, right: 0, zIndex: 5, display: 'flex', justifyContent: 'center', pointerEvents: 'none',
        transform: REDUCE_MOTION ? `translateY(${PULL_GAP_PX / 2 - PULL_CHIP_PX / 2}px)` : `translateY(${centre - PULL_CHIP_PX / 2}px)`,
        transition: isPulling ? 'none' : `transform 0.28s ${ease}`, willChange: 'transform',
      }}
    >
      <div style={{ opacity: shown ? (REDUCE_MOTION ? 1 : Math.min(1, eff * 1.4)) : 0, transform: `scale(${scale})`, transition: isPulling ? 'none' : `opacity 0.2s ease, transform 0.28s ${ease}`, willChange: 'transform, opacity' }}>
        {error ? (
          <span role="status" style={{ ...chip, width: 'auto', borderRadius: 999, padding: '0 16px', fontSize: 12, fontWeight: 600, color: ink, whiteSpace: 'nowrap' }}>{error}</span>
        ) : (
          <span role="status" aria-live="polite" style={{ ...chip, position: 'relative', animation: ready && !REDUCE_MOTION ? 'banbeRefreshPop 0.26s ease-out' : undefined }}>
            <svg width={22} height={22} viewBox="0 0 24 24" aria-hidden="true" focusable="false">
              {shapeEl({ stroke: rule, strokeWidth: 2.2 })}
              {showTravel ? (
                shapeEl({
                  stroke: ink, strokeWidth: 2.4, strokeLinecap: 'round',
                  strokeDasharray: `${SEGMENT_PCT} ${100 - SEGMENT_PCT}`,
                  style: { animation: 'banbeRefreshTravel 0.9s linear infinite' },
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
        )}
      </div>
    </div>
  );
}

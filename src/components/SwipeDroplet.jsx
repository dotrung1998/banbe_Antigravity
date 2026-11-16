// Root-tab swipe feedback (note 90): a bead of water. The screens carry the drag; a drop gathers at the leading edge and
// stretches along the way of travel, so a page swipe reads as something wet passing under the finger. A committed swipe
// rolls the drop off the frame and leaves a short ripple; a drag that springs back lets it settle into the page again.
// Decorative only — no layout, no hit-testing, nothing announced — and nothing at all under Reduce Motion.
// Pure view: src/App.jsx owns the gesture and passes its live numbers in.
import { useEffect, useState } from 'react';

// Matches bbSwipeRipple in index.css; short enough to finish inside App.jsx's 250ms commit settle.
const RIPPLE_MS = 240;

/**
 * @param {object} p
 * @param {number} p.x  the gesture's own horizontal offset in px (negative = towards the next tab)
 * @param {number} p.width  the screen's width in px, so the drop's stretch is the same on every device
 * @param {boolean} p.active  a horizontal drag is under the finger right now (follows it with no transition)
 * @param {'next'|'prev'|null} p.commit  the swipe has committed and is settling; the drop rolls off
 */
export default function SwipeDroplet({ x = 0, width = 0, active = false, commit = null }) {
  const [ripple, setRipple] = useState(0);
  // Re-keyed on every commit, so a second swipe restarts the ripple instead of inheriting the first one's progress.
  useEffect(() => { if (commit) setRipple(n => n + 1); }, [commit]);

  const w = Math.max(1, width || 390);
  const p = Math.min(1, Math.abs(x) / (w * 0.6));
  const dir = x < 0 ? -1 : x > 0 ? 1 : (commit === 'prev' ? 1 : -1);
  const leaving = !!commit;
  const shown = active || leaving;
  // Follows the drag halfway, never past the middle third of the frame; a commit rolls it a little further that way.
  const offset = Math.max(-w * 0.3, Math.min(w * 0.3, x * 0.5)) + (leaving ? dir * 26 : 0);
  const beadW = 22 + 30 * p;
  const beadH = 26 - 6 * p;
  const follow = active ? 'none' : 'transform .26s cubic-bezier(.22,.61,.36,1), opacity .22s ease';

  return (
    <div aria-hidden data-testid="swipe-droplet"
      style={{ position: 'fixed', left: 0, right: 0, top: '50%', height: 0, zIndex: 22, pointerEvents: 'none' }}>
      {/* The wake: a faint thread of water trailing behind the bead, as long as the drag is. */}
      <span style={{
        position: 'absolute', top: 0, left: `calc(50% + ${offset}px)`,
        width: 20 + 110 * p, height: 10 + 10 * p, borderRadius: 999,
        transform: `translate(${dir > 0 ? '-100%' : '0'}, -50%)`,
        background: `linear-gradient(${dir > 0 ? '270deg' : '90deg'}, rgba(var(--bb-fg-rgb),0.16), rgba(var(--bb-fg-rgb),0))`,
        opacity: shown ? p * 0.5 : 0,
        transition: active ? 'none' : 'opacity .24s ease, transform .26s cubic-bezier(.22,.61,.36,1)',
      }} />
      {/* The bead: a glass drop, stretching along the swipe and thinning across it. */}
      <span style={{
        position: 'absolute', top: 0, left: `calc(50% + ${offset}px)`,
        width: beadW, height: beadH, borderRadius: '50%',
        transform: `translate(-50%, -50%) scaleX(${1 + p * 0.85}) scaleY(${1 - p * 0.12})`,
        background: 'radial-gradient(60% 60% at 34% 30%, rgba(255,255,255,0.95) 0%, rgba(255,255,255,0.5) 28%, rgba(var(--bb-fg-rgb),0.16) 66%, rgba(var(--bb-fg-rgb),0.05) 100%)',
        border: '1px solid rgba(255,255,255,0.55)',
        boxShadow: 'inset 0 -3px 6px rgba(var(--bb-fg-rgb),0.14), 0 6px 16px rgba(27,25,22,0.18)',
        opacity: shown ? (leaving ? 0 : Math.min(1, 0.3 + p)) : 0,
        transition: follow,
      }} />
      {/* The ripple a committed swipe leaves behind. */}
      {leaving && (
        <span key={ripple} style={{
          position: 'absolute', top: 0, left: `calc(50% + ${offset}px)`,
          width: 44, height: 44, marginLeft: -22, marginTop: -22, borderRadius: '50%',
          border: '1.5px solid rgba(var(--bb-fg-rgb),0.3)',
          animation: `bbSwipeRipple ${RIPPLE_MS}ms ease-out both`,
        }} />
      )}
    </div>
  );
}

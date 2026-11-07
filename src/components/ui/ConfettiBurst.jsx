// A short, one-shot confetti burst for a flow's peak moment (note 53, peak-end rule): the onboarding reveal and a
// submitted event. CSS only (keyframes `bbConfetti` in src/index.css); hidden entirely under reduced motion.
// Place it inside a position:relative parent; it bursts from `top` px down, horizontally centred.
import { useMemo } from 'react';

const COLORS = ['#E0A526', '#9C5B3B', '#485834', '#C8CBB2', '#E8715B', '#1B1916'];

export default function ConfettiBurst({ top = 24, count = 26 }) {
  const bits = useMemo(() => Array.from({ length: count }, (_, i) => {
    const angle = (i / count) * Math.PI * 2 + (i % 3) * 0.17;
    const dist = 90 + (i * 37) % 80;
    return {
      dx: Math.round(Math.cos(angle) * dist), dy: Math.round(Math.sin(angle) * dist * 0.7 - 40),
      rot: (i * 47) % 360, color: COLORS[i % COLORS.length], delay: (i % 5) * 18, w: i % 2 ? 6 : 8,
    };
  }), [count]);
  return (
    <div aria-hidden className="bb-confetti" style={{ position: 'absolute', left: '50%', top, width: 0, height: 0, pointerEvents: 'none', zIndex: 1 }}>
      {bits.map((b, i) => (
        <span key={i} style={{ position: 'absolute', width: b.w, height: b.w * 1.6, borderRadius: 2, background: b.color,
          '--dx': `${b.dx}px`, '--dy': `${b.dy}px`, '--rot': `${b.rot}deg`, animation: `bbConfetti 1.1s cubic-bezier(.2,.7,.3,1) ${b.delay}ms both` }} />
      ))}
    </div>
  );
}

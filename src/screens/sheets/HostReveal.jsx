import { useEffect, useRef } from 'react';
import {
  REVEAL_TIMELINE, REVEAL_TOTAL, buildParticles, particleState, sampleInRoundedRect, mulberry32, clamp01, flashLevel,
} from '../../lib/hostReveal.js';

// Full-bleed canvas overlay for the host-profile reveal: dots leave the setup sheet's elements,
// swirl into a rotating Earth-like sphere, then coalesce into the host card. Purely visual; the
// parent decides when it starts and unmounts it on `onDone`.

const DOT_COUNT = 1500;

function relRect(el, origin, k) {
  const r = el.getBoundingClientRect();
  return { left: (r.left - origin.left) * k, top: (r.top - origin.top) * k, width: r.width * k, height: r.height * k };
}

export default function HostReveal({ sourceRoot, targetSelector, onDone }) {
  const canvasRef = useRef(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return undefined;
    const ctx = canvas.getContext('2d');
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = canvas.clientWidth, h = canvas.clientHeight;
    canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const origin = canvas.getBoundingClientRect();
    const k = origin.width ? w / origin.width : 1;

    const sources = Array.from(sourceRoot?.querySelectorAll('[data-reveal-src]') || [])
      .map(el => ({ ...relRect(el, origin, k), radius: Number(el.getAttribute('data-radius')) || 14 }))
      .filter(r => r.width > 4 && r.height > 4);
    if (!sources.length) sources.push({ left: w * 0.1, top: h * 0.3, width: w * 0.8, height: h * 0.3, radius: 20 });

    const cx = w / 2, cy = h * 0.46;
    const radius = Math.max(70, Math.min(130, Math.min(w, h) * 0.2));
    const fallbackTarget = { left: w * 0.05, top: h * 0.14, width: w * 0.9, height: 110 };
    const readTarget = () => {
      const el = targetSelector ? document.querySelector(targetSelector) : null;
      return el ? relRect(el, origin, k) : fallbackTarget;
    };
    const view = { cx, cy, radius };
    let target = readTarget();
    const parts = buildParticles({ count: DOT_COUNT, sources, target, ...view, seed: 11 });
    let retargeted = false;
    const tCoal0 = REVEAL_TIMELINE.gather + REVEAL_TIMELINE.form + REVEAL_TIMELINE.spin;

    let raf = 0, start = 0, finished = false;
    const frame = (now) => {
      if (!start) start = now;
      const t = now - start;
      if (!retargeted && t >= tCoal0 - 50) {
        // The real card is mounted by now; aim at where it actually is.
        retargeted = true;
        target = readTarget();
        const rand = mulberry32(99);
        for (const p of parts) { const d = sampleInRoundedRect(target, 22, rand); p.dx = d.x; p.dy = d.y; }
      }
      ctx.clearRect(0, 0, w, h);
      // Soft halo behind the sphere while it exists.
      const halo = clamp01((t - REVEAL_TIMELINE.gather * 0.6) / 900) * (1 - clamp01((t - tCoal0) / REVEAL_TIMELINE.coalesce));
      if (halo > 0) {
        const g = ctx.createRadialGradient(cx, cy, radius * 0.2, cx, cy, radius * 1.9);
        g.addColorStop(0, `rgba(255,255,255,${0.16 * halo})`);
        g.addColorStop(1, 'rgba(255,255,255,0)');
        ctx.fillStyle = g;
        ctx.fillRect(0, 0, w, h);
      }
      ctx.fillStyle = '#FFFFFF';
      for (const p of parts) {
        const s = particleState(p, t, view);
        if (s.alpha <= 0.01) continue;
        ctx.globalAlpha = s.alpha;
        ctx.beginPath();
        ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.globalAlpha = 1;
      // The finished card lights up: a bright bloom hugging its outline that rises fast and decays.
      const flash = flashLevel(t);
      if (flash > 0) {
        const { left, top, width, height } = target;
        const r = Math.min(22, width / 2, height / 2);
        ctx.save();
        ctx.beginPath();
        ctx.moveTo(left + r, top);
        ctx.arcTo(left + width, top, left + width, top + height, r);
        ctx.arcTo(left + width, top + height, left, top + height, r);
        ctx.arcTo(left, top + height, left, top, r);
        ctx.arcTo(left, top, left + width, top, r);
        ctx.closePath();
        ctx.shadowColor = 'rgba(255,255,255,0.95)';
        ctx.shadowBlur = 70 * flash;
        ctx.fillStyle = `rgba(255,255,255,${0.42 * flash})`;
        ctx.fill();
        ctx.lineWidth = 1.5;
        ctx.strokeStyle = `rgba(255,255,255,${0.9 * flash})`;
        ctx.stroke();
        ctx.restore();
      }
      if (t < REVEAL_TOTAL) raf = requestAnimationFrame(frame);
      else if (!finished) { finished = true; onDone?.(); }
    };
    raf = requestAnimationFrame(frame);
    return () => cancelAnimationFrame(raf);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return <canvas ref={canvasRef} data-testid="host-reveal-canvas" aria-hidden="true" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', pointerEvents: 'none' }} />;
}

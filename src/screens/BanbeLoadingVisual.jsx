import { useEffect, useState } from 'react';

// Pulse/loading UX pass (2026-09-27) — the shared Banbe loading visual,
// used at every spot the ticket named: a fetching Pulse tab
// (sheets/PulseViewer.jsx), the branded splash screen (Splash.jsx), the
// Confirmed ticket's QR-generation gap (Confirmed.jsx's QrCode), and a
// pending seat reservation (Loading.jsx). iOS's equivalent is
// `BanbeLoadingVisual` in apps/ios/BanbeApp/Views/Components.swift,
// sharing the same bundled `banbe-loading.gif` file (public/, referenced
// in place by iOS's project.yml — one source of truth, never two
// independently-exported copies).
//
// Respects `prefers-reduced-motion`: falls back to the existing static
// banbe-mark artwork instead of the looping GIF — the ticket's own
// wording explicitly allows either "a static frame" or "brand fallback";
// a static frame would need extracting frame 0 from the GIF client-side
// (no reliable, dependency-free way to do that for an already-encoded
// GIF in a browser — canvas.drawImage on an <img> captures whatever frame
// happens to be showing at draw time, not frame 0), so the brand mark
// (already used as the equivalent "waiting" glyph in Loading.jsx before
// this pass) is the honest, already-established fallback instead.
export default function BanbeLoadingVisual({ size = 72 }) {
  const [reduceMotion, setReduceMotion] = useState(
    () => typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches,
  );
  useEffect(() => {
    const mq = window.matchMedia?.('(prefers-reduced-motion: reduce)');
    if (!mq) return undefined;
    const onChange = () => setReduceMotion(mq.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);

  if (reduceMotion) {
    return (
      <img
        src="/banbe-mark.png"
        alt=""
        crossOrigin="anonymous"
        data-testid="banbe-loading-visual-static"
        style={{ width: size * 0.7, height: 'auto', display: 'block' }}
      />
    );
  }
  return (
    <img
      src="/banbe-loading.gif"
      alt=""
      crossOrigin="anonymous"
      data-testid="banbe-loading-visual"
      style={{ width: size, height: size, objectFit: 'contain', display: 'block' }}
    />
  );
}

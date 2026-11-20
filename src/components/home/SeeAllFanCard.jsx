// "See all N" card at the end of the Home rail (v2.3, note 81): after at most four frames, this card plays the guest
// Welcome photo entrance (screens/Welcome.jsx): the side photos slide in from their own edge and swing into a fan, the
// middle one rises, then the tab's chip (For You, Weekend) arrives from below and glows gold once. It replays each time
// the card comes back into view. Reduced motion: the fan simply rests. A tap opens See all for THAT tab.
import { useEffect, useRef, useState } from 'react';
import { useReducedMotion } from '../../lib/useReducedMotion.js';
import HeroLineArt from './HeroLineArt.jsx';

const EASE = 'cubic-bezier(.22,1,.36,1)';
// Gold of the Welcome For You chip (screens/Welcome.jsx GOLD), kept as the same accent here.
const CSS = `
@keyframes bbV23ArtIn { 0% { transform: translateY(14px); opacity: 0; } 100% { transform: none; opacity: 1; } }
@keyframes bbV23FanL { 0% { transform: translate(-140px, 10px) rotate(-2deg); opacity: 0; } 55% { opacity: 1; } 100% { transform: translate(-58px, 8px) rotate(-8deg); opacity: 1; } }
@keyframes bbV23FanR { 0% { transform: translate(140px, 10px) rotate(2deg); opacity: 0; } 55% { opacity: 1; } 100% { transform: translate(58px, 8px) rotate(8deg); opacity: 1; } }
@keyframes bbV23FanM { 0% { transform: translate(0, 46px); opacity: 0; } 100% { transform: translate(0, -6px); opacity: 1; } }
@keyframes bbV23Chip { 0% { transform: translate(-50%, 40px); opacity: 0; } 60% { transform: translate(-50%, 62px); opacity: 1; box-shadow: 0 0 0 0 rgba(204,158,41,.0); }
  80% { box-shadow: 0 0 0 7px rgba(204,158,41,.35); } 100% { transform: translate(-50%, 62px); opacity: 1; box-shadow: 0 0 0 0 rgba(204,158,41,0); } }
`;

// Owner 2026-11-20: a fan of one or two photos looks broken, so with fewer than 3 photos the tab's line-art sketch
// (src/lib/heroLineArt.js, `art` = the tab id) stands in for the fan. `onEditPrefs` (For You, signed in) adds a small
// "Edit preferences" pill that opens the existing For You preferences editor. iOS twin: SeeAllFanCard in HomeV23Sections.swift.
export default function SeeAllFanCard({ photos, label, count, onOpen, T, art = 'all', onEditPrefs = null }) {
  const reduced = useReducedMotion();
  const ref = useRef(null);
  const [run, setRun] = useState(0);
  // Replays each time the card comes (back) into view inside the rail.
  useEffect(() => {
    const el = ref.current;
    if (!el || reduced || typeof IntersectionObserver === 'undefined') return undefined;
    let seen = false;
    const io = new IntersectionObserver(([e]) => {
      if (e.intersectionRatio >= 0.6 && !seen) { seen = true; setRun(r => r + 1); }
      else if (e.intersectionRatio < 0.2) seen = false;
    }, { threshold: [0, 0.2, 0.6, 1] });
    io.observe(el);
    return () => io.disconnect();
  }, [reduced]);
  const real = photos.filter(Boolean);
  const sketch = real.length < 3;
  const pics = sketch ? [] : real.slice(0, 3);
  const anim = (name, delay) => (reduced || !run ? undefined : `${name} 1.5s ${EASE} ${delay}ms both`);
  const rest = [
    'translate(-58px, 8px) rotate(-8deg)', 'translate(0, -6px)', 'translate(58px, 8px) rotate(8deg)',
  ];
  return (
    <div style={{ flex: '0 0 268px', height: 360, scrollSnapAlign: 'start', position: 'relative' }}>
    <button ref={ref} type="button" data-testid="home-hero-see-all" data-fan={reduced ? 'still' : 'animated'} data-art={sketch ? art : undefined} onClick={onOpen}
      aria-label={T(`Xem cả ${count} sự kiện trong ${label.vi}`, `See all ${count} events in ${label.en}`)}
      style={{ width: '100%', height: '100%', borderRadius: 16, border: '1px solid rgba(255,255,255,.18)', background: 'rgba(255,255,255,.07)', color: '#fff', fontFamily: 'inherit', position: 'relative', overflow: 'hidden', cursor: 'pointer', padding: 0 }}>
      <style>{CSS}</style>
      {sketch && (
        <HeroLineArt kind={art} testId="home-hero-see-all-art"
          style={{ position: 'absolute', left: 20, top: 44, color: 'rgba(255,255,255,.62)', animation: reduced || !run ? undefined : `bbV23ArtIn .9s ${EASE} both` }} />
      )}
      <span key={run} aria-hidden="true" style={{ position: 'absolute', left: '50%', top: 128, width: 0, height: 0 }}>
        {pics.map((src, i) => {
          const pos = pics.length === 1 ? 1 : pics.length === 2 ? [0, 2][i] : i;
          return (
            <span key={i} style={{ position: 'absolute', left: -48, top: -62, width: 96, height: 124, borderRadius: 14, boxShadow: '0 6px 22px rgba(0,0,0,.35)',
              background: src ? `#2a2620 center/cover no-repeat url("${src}")` : '#2a2620', zIndex: pos === 1 ? 2 : 1, transform: rest[pos],
              animation: anim(['bbV23FanL', 'bbV23FanM', 'bbV23FanR'][pos], pos === 1 ? 260 : 0) }} />
          );
        })}
        <span style={{ position: 'absolute', left: 0, top: 0, transform: 'translate(-50%, 62px)', zIndex: 3, display: 'inline-flex', alignItems: 'center', gap: 4, whiteSpace: 'nowrap',
          padding: '6px 12px', borderRadius: 999, background: 'var(--bb-bg)', color: 'var(--bb-fg)', border: '1px solid rgba(204,158,41,.7)', fontSize: 12, fontWeight: 600,
          animation: anim('bbV23Chip', 900) }}>
          <span style={{ color: '#CC9E29' }}>★</span>{T(label.vi, label.en)}
        </span>
      </span>
      <span style={{ position: 'absolute', left: 0, right: 0, bottom: 28, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
        <span style={{ fontSize: 22, fontWeight: 300 }}>{T(`Xem cả ${count}`, `See all ${count}`)}</span>
        <span style={{ fontSize: 13, opacity: 0.8 }}>{T('sự kiện trong mục này', 'events in this tab')} →</span>
      </span>
    </button>
    {onEditPrefs && (
      <button type="button" data-testid="home-hero-edit-prefs" onClick={onEditPrefs}
        style={{ position: 'absolute', top: 12, right: 12, zIndex: 4, minHeight: 36, padding: '0 12px', borderRadius: 999, border: '1px solid rgba(255,255,255,.28)',
          background: 'rgba(255,255,255,.12)', color: '#fff', fontFamily: 'inherit', fontSize: 12, fontWeight: 600, cursor: 'pointer', display: 'inline-flex', alignItems: 'center', gap: 6 }}>
        <svg aria-hidden="true" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" /></svg>
        {T('Sửa sở thích', 'Edit preferences')}
      </button>
    )}
    </div>
  );
}

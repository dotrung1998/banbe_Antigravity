// The v2.3 live line under the Home rail (note 81, switch home_v23). Full motion: a seamless ticker (two copies, so
// the next update is always coming in) with a Live / Paused button (WCAG 2.2.2 Pause, Stop, Hide); hovering or focusing
// the line pauses it too. Reduced motion: a sliding line cannot become "slower" and a frozen one shows a cut sentence,
// so it shows ONE whole update at a time with when the event is, and ‹ n/N › steps by a dissolve. Nothing changes on
// its own. A tap on the line opens "Live now" with every update. Updates come from src/lib/liveLine.js (real data only).
import { useEffect, useRef, useState } from 'react';
import { liveSeconds, stepIndex } from '../../lib/liveLine.js';
import { useReducedMotion } from '../../lib/useReducedMotion.js';

const CSS = `
@keyframes bbV23Marq { from { transform: translateX(0); } to { transform: translateX(-50%); } }
.bb-v23-live-run { display: inline-flex; flex: none; white-space: nowrap; will-change: transform; animation: bbV23Marq var(--bb-live-dur, 24s) linear infinite; }
.bb-v23-live.paused .bb-v23-live-run, .bb-v23-live-main:hover .bb-v23-live-run, .bb-v23-live-main:focus-visible .bb-v23-live-run { animation-play-state: paused; }
@media (prefers-reduced-motion: reduce) { .bb-v23-live-run { animation: none; } }
@keyframes bbV23Dissolve { from { opacity: 0; } to { opacity: 1; } }
@keyframes bbV23LiveDot { 0%, 100% { opacity: 1; } 50% { opacity: .35; } }
`;
const CHEV = (d) => <svg aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d={d} /></svg>;

/**
 * @param {object} p
 * @param {Array<{id, eventId, text:{vi,en}, when}>} p.updates
 * @param {number} p.index  the update shown in the Reduced form (owned by Home so the sheet can mark it)
 * @param {(i: number) => void} p.onIndex
 * @param {() => void} p.onOpen  opens Live now
 */
export default function LiveLine({ updates, index, onIndex, onOpen, T }) {
  const reduced = useReducedMotion();
  const [paused, setPaused] = useState(false);
  const oneRef = useRef(null);
  const prevIndex = useRef(index);
  useEffect(() => {
    if (prevIndex.current !== index && oneRef.current?.animate) oneRef.current.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 200, easing: 'ease-out' });
    prevIndex.current = index;
  }, [index]);
  if (!updates.length) return null;
  const texts = updates.map(u => T(u.text.vi, u.text.en));
  const cur = updates[Math.min(index, updates.length - 1)];
  const sideBtn = { minWidth: 44, height: 44, border: 'none', borderRadius: 999, background: 'none', color: 'inherit', display: 'grid', placeItems: 'center', cursor: 'pointer', fontFamily: 'inherit' };
  const dot = <i aria-hidden="true" style={{ width: 7, height: 7, borderRadius: '50%', background: 'var(--bb-alert)', flex: 'none', animation: reduced || paused ? 'none' : 'bbV23LiveDot 1.6s ease-in-out infinite' }} />;

  return (
    <section data-testid="home-live-line" data-mode={reduced ? 'reduced' : 'ticker'} className={`bb-v23-live${paused ? ' paused' : ''}`}
      aria-label={T('Đang diễn ra', 'Live activity')}
      style={{ margin: '16px 20px 0', minHeight: 48, borderRadius: 999, background: 'var(--bb-block)', display: 'flex', alignItems: 'center', gap: 2, padding: '0 4px 0 14px', overflow: 'hidden' }}>
      <style>{CSS}</style>
      {reduced ? (
        <>
          <button type="button" onClick={onOpen} data-testid="home-live-open" aria-label={T('Đang diễn ra, xem mọi cập nhật', 'Live activity, see all updates')}
            style={{ flex: 1, minWidth: 0, minHeight: 44, display: 'flex', alignItems: 'center', gap: 8, border: 'none', background: 'none', color: 'inherit', fontFamily: 'inherit', textAlign: 'left', cursor: 'pointer', padding: 0 }}>
            {dot}
            <span ref={oneRef} aria-live="polite" data-testid="home-live-one" style={{ minWidth: 0, display: 'flex', flexDirection: 'column' }}>
              <span style={{ fontSize: 13.5, fontWeight: 600, lineHeight: 1.25 }}>{T(cur.text.vi, cur.text.en)}</span>
              {cur.when && <small style={{ fontSize: 11.5, opacity: 0.72 }}>{cur.when}</small>}
            </span>
          </button>
          <div style={{ display: 'flex', alignItems: 'center', flex: 'none' }}>
            <button type="button" style={{ ...sideBtn, opacity: index === 0 ? 0.3 : 1 }} disabled={index === 0} onClick={() => onIndex(stepIndex(index, -1, updates.length))}
              aria-label={T('Cập nhật trước', 'Previous update')} data-testid="home-live-prev">{CHEV('m15 6-6 6 6 6')}</button>
            <b data-testid="home-live-index" style={{ fontSize: 12.5, fontVariantNumeric: 'tabular-nums', minWidth: 30, textAlign: 'center' }}>{index + 1}/{updates.length}</b>
            <button type="button" style={{ ...sideBtn, opacity: index >= updates.length - 1 ? 0.3 : 1 }} disabled={index >= updates.length - 1} onClick={() => onIndex(stepIndex(index, 1, updates.length))}
              aria-label={T('Cập nhật sau', 'Next update')} data-testid="home-live-next">{CHEV('m9 6 6 6-6 6')}</button>
          </div>
        </>
      ) : (
        <>
          <button type="button" onClick={onOpen} className="bb-v23-live-main" data-testid="home-live-open" aria-label={T('Đang diễn ra, xem mọi cập nhật', 'Live activity, see all updates')}
            style={{ flex: 1, minWidth: 0, minHeight: 44, display: 'flex', alignItems: 'center', border: 'none', background: 'none', color: 'inherit', fontFamily: 'inherit', cursor: 'pointer', padding: 0, overflow: 'hidden',
              WebkitMaskImage: 'linear-gradient(90deg, #000 0, #000 calc(100% - 24px), transparent 100%)', maskImage: 'linear-gradient(90deg, #000 0, #000 calc(100% - 24px), transparent 100%)' }}>
            <span aria-hidden="true" className="bb-v23-live-run" data-testid="home-live-run" style={{ '--bb-live-dur': `${liveSeconds(texts)}s` }}>
              {[0, 1].map(copy => (
                <span key={copy} style={{ display: 'inline-flex', alignItems: 'center', fontSize: 13.5, fontWeight: 500 }}>
                  {texts.map((t, i) => <span key={i} style={{ paddingRight: 28 }}>{t}<span style={{ paddingLeft: 28, opacity: 0.4 }}>·</span></span>)}
                </span>
              ))}
            </span>
          </button>
          <button type="button" onClick={() => setPaused(p => !p)} data-testid="home-live-pause" aria-pressed={paused}
            aria-label={paused ? T('Tiếp tục cập nhật trực tiếp', 'Resume live updates') : T('Tạm dừng cập nhật trực tiếp', 'Pause live updates')}
            style={{ ...sideBtn, flex: 'none', gap: 6, padding: '0 12px', display: 'flex', alignItems: 'center', fontSize: 12.5, fontWeight: 700, background: 'var(--bb-bg)', marginLeft: 6 }}>
            {dot}<span data-testid="home-live-state">{paused ? T('Đã dừng', 'Paused') : T('Trực tiếp', 'Live')}</span>
            {!paused && <span aria-hidden="true" style={{ fontSize: 10, letterSpacing: 1 }}>❙❙</span>}
          </button>
        </>
      )}
    </section>
  );
}

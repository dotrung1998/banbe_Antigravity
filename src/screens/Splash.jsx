import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink } from '../theme.js';

// Splash-only logo: the Adobe Animate/CreateJS "logomotion" export, vendored
// under public/logomotion (its own createjs.min.js copy included so it works
// offline, matching how the GIF it replaced here was bundled). It renders on
// a transparent canvas; pointerEvents: 'none' lets the tap-to-dismiss click
// on this screen's own wrapper div fall through the iframe instead of being
// swallowed by it. Every other screen that used the shared loading GIF
// (BanbeLoadingVisual) is untouched.
const LOGOMOTION_WIDTH = 280;
const LOGOMOTION_HEIGHT = Math.round((LOGOMOTION_WIDTH / 1288) * 800);

export default function Splash() {
  const { state: s, T, dismissSplash, notifyLogomotionComplete, resolvedTheme } = useBanBe();
  // Owner, 2026-10-24: a greeting under the motion. Signed in: "Welcome back, <given name>" (Vietnamese names put
  // the given name last, English first); signed out: a general welcome. iOS twin: SplashView.greeting.
  const parts = String(s.user?.name || '').trim().split(/\s+/).filter(Boolean);
  const given = parts.length ? (s.lang === 'en' ? parts[0] : parts[parts.length - 1]) : '';
  const greeting = !s.user ? T('Chào mừng bạn đến với banbe', 'Welcome to banbe')
    : given ? T(`Chào mừng trở lại, ${given}`, `Welcome back, ${given}`) : T('Chào mừng bạn trở lại', 'Welcome back');
  const iframeRef = useRef(null);
  const hostRef = useRef(null);
  // The logomotion lives in its own document, so it does not see this page's
  // `--bb-bg`. An iframe whose document declares no background is painted with
  // the UA's default white canvas, which in dark mode showed as a bright white
  // rectangle around the white tinted artwork. Read the splash's real resolved
  // background and hand it to the frame (the frame applies it before it paints).
  const [frameSrc, setFrameSrc] = useState(null);
  useLayoutEffect(() => {
    const bg = hostRef.current && getComputedStyle(hostRef.current).backgroundColor;
    if (!bg || bg === 'transparent' || bg === 'rgba(0, 0, 0, 0)') { setFrameSrc(null); return; }
    const tint = resolvedTheme === 'dark' ? '&tint=%23ffffff' : '';
    setFrameSrc(`/logomotion/logomotion2309.html?bg=${encodeURIComponent(bg)}${tint}`);
  }, [resolvedTheme]);

  // Completion-gating fix (2026-09-30) — `logomotion2309.html` posts a
  // distinct `{type:"logomotion-complete"}` message (separate from its
  // pre-existing `"logomotion-ready"`, which fires on asset load, not on
  // the animation having actually played through) the instant its
  // timeline reaches its last frame. Source-validated against this exact
  // iframe's own `contentWindow` (never a bare origin/type check alone) so
  // an unrelated same-origin postMessage elsewhere in the app can't
  // spoof this; cleaned up on unmount.
  useEffect(() => {
    function onMessage(event) {
      if (event.source !== iframeRef.current?.contentWindow) return;
      if (event.data?.type === 'logomotion-complete') notifyLogomotionComplete();
    }
    window.addEventListener('message', onMessage);
    return () => window.removeEventListener('message', onMessage);
  }, [notifyLogomotionComplete]);

  return (
    <div
      ref={hostRef}
      onClick={dismissSplash}
      style={{
        position: 'absolute', inset: 0, zIndex: 40, background: paper, display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center', cursor: 'pointer', animation: 'banbeFade 0.4s ease both',
      }}
      data-screen-label="Splash"
    >
      {frameSrc ? (
        <iframe
          ref={iframeRef}
          title="banbe"
          // Note 69: the artwork is black; in dark mode it is tinted white. `bg` is the splash's own resolved colour,
          // so the frame's canvas is not the UA's default white box (see the effect above).
          src={frameSrc}
          scrolling="no"
          data-testid="splash-logomotion"
          style={{
            width: LOGOMOTION_WIDTH, height: LOGOMOTION_HEIGHT, border: 'none', display: 'block',
            background: 'transparent', pointerEvents: 'none', animation: 'banbeIn 0.7s cubic-bezier(.22,.61,.36,1) both',
          }}
        />
      ) : (
        // One frame, before the resolved colour is read: hold the artwork's box so the greeting does not jump.
        <div aria-hidden="true" style={{ width: LOGOMOTION_WIDTH, height: LOGOMOTION_HEIGHT, flexShrink: 0 }} />
      )}
      <div data-testid="splash-greeting" className="bb-wel-rise" style={{ fontFamily: "var(--bb-face, 'Be Vietnam Pro'),sans-serif", fontSize: 22, fontWeight: 600, color: ink, marginTop: 18, padding: '0 32px', textAlign: 'center', animationDelay: '0.6s', animationDuration: '1s' }}>{greeting}</div>
      <span style={{ fontFamily: "var(--bb-face, 'Be Vietnam Pro'),sans-serif", fontSize: 14, fontWeight: 400, letterSpacing: '0.01em', color: ink, opacity: 0.75, marginTop: 8, animation: 'banbeFade 0.9s ease 0.9s both' }}>{T('bạn mới mỗi tuần', 'new friends every week')}</span>
    </div>
  );
}

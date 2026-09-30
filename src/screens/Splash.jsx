import { useEffect, useRef } from 'react';
import { useGoc } from '../state/GocContext.jsx';
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
  const { dismissSplash, notifyLogomotionComplete } = useGoc();
  const iframeRef = useRef(null);

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
      onClick={dismissSplash}
      style={{
        position: 'absolute', inset: 0, zIndex: 40, background: paper, display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center', cursor: 'pointer', animation: 'gocFade 0.4s ease both',
      }}
      data-screen-label="Splash"
    >
      <iframe
        ref={iframeRef}
        title="banbe"
        src="/logomotion/logomotion2309.html"
        scrolling="no"
        data-testid="splash-logomotion"
        style={{
          width: LOGOMOTION_WIDTH, height: LOGOMOTION_HEIGHT, border: 'none', display: 'block',
          background: 'transparent', pointerEvents: 'none', animation: 'gocIn 0.7s cubic-bezier(.22,.61,.36,1) both',
        }}
      />
      <span style={{ fontFamily: "'Be Vietnam Pro',sans-serif", fontSize: 14, fontWeight: 400, letterSpacing: '0.01em', color: ink, marginTop: 16, animation: 'gocFade 0.9s ease 0.5s both' }}>bạn mới mỗi tuần</span>
    </div>
  );
}

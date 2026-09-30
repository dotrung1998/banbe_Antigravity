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
  const { dismissSplash } = useGoc();

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

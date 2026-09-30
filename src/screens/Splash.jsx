import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, SPLASH_LOADING_GAP } from '../theme.js';
import BanbeLoadingVisual from './BanbeLoadingVisual.jsx';

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
      <img src="/banbe-wordmark.png" alt="banbe" crossOrigin="anonymous" style={{ width: 252, height: 'auto', display: 'block', animation: 'gocIn 0.7s cubic-bezier(.22,.61,.36,1) both' }} />
      <span style={{ fontFamily: "'Be Vietnam Pro',sans-serif", fontSize: 14, fontWeight: 400, letterSpacing: '0.01em', color: ink, marginTop: 16, animation: 'gocFade 0.9s ease 0.5s both' }}>bạn mới mỗi tuần</span>
      {/* A3 (Pulse/loading UX pass, 2026-09-27) — the shared Banbe loading
          GIF, replacing the plain orbit-arc spinner this used before
          (BanbeLoadingVisual itself honors prefers-reduced-motion). Served
          from /public, so it's cached by the browser like any other static
          asset — no separate offline-caching code needed on web (unlike
          iOS, which must explicitly bundle it — see project.yml). */}
      <div style={{ marginTop: SPLASH_LOADING_GAP, animation: 'gocFade 0.6s ease 1s both' }}>
        <BanbeLoadingVisual size={36} />
      </div>
    </div>
  );
}

import { paper, ink } from '../theme.js';

export default function Loading({ label }) {
  return (
    <div
      style={{
        position: 'absolute', inset: 0, zIndex: 50, background: paper, display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center', animation: 'gocFade 0.2s ease both',
      }}
      data-screen-label="Loading"
    >
      <div style={{ position: 'relative', width: 104, height: 104, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <svg viewBox="0 0 104 104" style={{ position: 'absolute', inset: 0, animation: 'gocOrbit 1.7s linear infinite' }}>
          <path d="M52 7 a45 45 0 0 1 45 45" fill="none" stroke={ink} strokeWidth="2" strokeLinecap="round" />
          <path d="M52 97 a45 45 0 0 1 -45 -45" fill="none" stroke={ink} strokeWidth="2" strokeLinecap="round" />
        </svg>
        <img src="/banbe-mark.png" alt="" crossOrigin="anonymous" style={{ width: 54, height: 'auto', display: 'block', animation: 'gocTumble 2.2s cubic-bezier(.45,.05,.35,1) infinite' }} />
      </div>
      <span style={{ fontSize: 12.5, color: ink, marginTop: 20 }}>{label}</span>
    </div>
  );
}

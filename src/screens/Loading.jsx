import { ink, paper } from '../theme.js';
import BanbeLoadingVisual from './BanbeLoadingVisual.jsx';

// A4 (Pulse/loading UX pass, 2026-09-27) — this screen is App.jsx's own
// `state.loading` overlay, shown while a seat-reservation request is
// pending (`Reserve.jsx`'s hold_seats() call) — exactly the "seat
// reservation pending" moment the ticket names. The plain mark+orbit-arc
// spinner this used before is replaced by the shared GIF
// (BanbeLoadingVisual honors prefers-reduced-motion on its own).
export default function Loading({ label }) {
  return (
    <div
      style={{
        position: 'absolute', inset: 0, zIndex: 50, background: paper, display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center', animation: 'gocFade 0.2s ease both',
      }}
      data-screen-label="Loading"
    >
      <BanbeLoadingVisual size={72} />
      <span style={{ fontSize: 12.5, color: ink, marginTop: 20 }}>{label}</span>
    </div>
  );
}

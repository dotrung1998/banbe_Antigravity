// Motivating empty states (note 48) — web twin of iOS EmptyStateViews.swift. A little scene of the app's
// own keychain charms (public/keychains) gently sways on a soft shadow, then a warm line and ONE next step.
import { paper, ink, display } from '../../theme.js';

const SCENES = {
  findPlans: ['trip-ticket', 'pals-bear', 'sky-star'],
  freeDay: ['cafe-cup', 'pals-cat', 'sky-moon'],
  explore: ['sky-cloud', 'trip-compass', 'trip-plane'],
};

export function CharmScene({ scene }) {
  const charms = SCENES[scene] || SCENES.findPlans;
  const charm = (name, width, delay) => (
    <img key={name} src={`/keychains/${name}.png`} alt="" draggable={false} className="bb-charm"
      style={{ width, height: 'auto', transformOrigin: 'top center', animation: `bbCharmSway ${1.6 + delay}s ease-in-out ${delay}s infinite alternate` }} />
  );
  return (
    <div aria-hidden style={{ position: 'relative', height: 170, display: 'flex', justifyContent: 'center' }}>
      <div style={{ position: 'absolute', top: 118, width: 200, height: 70, borderRadius: '50%',
        background: 'radial-gradient(closest-side, rgba(var(--bb-fg-rgb),0.07), rgba(var(--bb-fg-rgb),0))' }} />
      <div style={{ position: 'absolute', top: 0, width: 150, height: 4, borderRadius: 2, background: 'rgba(var(--bb-fg-rgb),0.18)' }} />
      <div style={{ position: 'relative', display: 'flex', alignItems: 'flex-start', gap: 6, marginTop: -6 }}>
        {charm(charms[0], 58, 0)}
        {charm(charms[1], 84, 0.35)}
        {charm(charms[2], 58, 0.7)}
      </div>
    </div>
  );
}

export default function EmptyState({ scene, title, message, actionLabel, actionIcon = '✦', onAction, actionTestId, secondaryLabel, onSecondary, secondaryTestId, testId }) {
  return (
    <div data-testid={testId} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', gap: 10, padding: '16px 24px', color: ink }}>
      <CharmScene scene={scene} />
      <h3 style={display(20, { margin: 0 })}>{title}</h3>
      <p style={{ fontSize: 14, lineHeight: 1.5, opacity: 0.75, margin: 0, maxWidth: 340 }}>{message}</p>
      <button type="button" onClick={onAction} data-testid={actionTestId}
        style={{ marginTop: 6, border: 'none', borderRadius: 999, padding: '0 22px', minHeight: 48, background: ink, color: paper, fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer', display: 'inline-flex', alignItems: 'center', gap: 8 }}>
        <span aria-hidden>{actionIcon}</span>{actionLabel}
      </button>
      {secondaryLabel && onSecondary && (
        <button type="button" onClick={onSecondary} data-testid={secondaryTestId}
          style={{ border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 14, fontWeight: 600, textDecoration: 'underline', minHeight: 44, cursor: 'pointer' }}>
          {secondaryLabel}
        </button>
      )}
    </div>
  );
}

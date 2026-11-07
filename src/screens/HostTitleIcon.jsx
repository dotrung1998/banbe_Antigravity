import { RowIcon, ROW_ACCENT_COLORS } from './Account.jsx';

// iOS screen-title badge: a 20pt glyph centred in a 34pt circle tinted with
// the group's accent at 0.33 alpha (e.g. VerificationsView / AdminEventsView).
export default function HostTitleIcon({ kind, group }) {
  const accent = ROW_ACCENT_COLORS[group];
  return (
    <span aria-hidden style={{ flex: 'none', width: 34, height: 34, borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', background: accent ? `${accent}55` : 'transparent' }}>
      <RowIcon kind={kind} size={24} />
    </span>
  );
}

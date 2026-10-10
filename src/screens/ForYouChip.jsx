// Gold-star "For You" chip with a one-shot attention effect when new matching
// events arrive (src/lib/forYouAlert.js). The sweep + halo run once (class is
// dropped by useForYouAlert after ~3s, keyframes are finite) and are disabled
// entirely under prefers-reduced-motion; the retained "New" pill is static.
// Pill: white on #7A5200 = ~6.9:1 (WCAG AA for small text).
const CSS = `
@keyframes bb-fy-halo { 0% { box-shadow: 0 0 0 0 rgba(224,165,38,0.6); } 100% { box-shadow: 0 0 0 12px rgba(224,165,38,0); } }
@keyframes bb-fy-sweep { 0% { transform: translateX(-120%); opacity: 1; } 85% { opacity: 1; } 100% { transform: translateX(220%); opacity: 0; } }
.bb-fy-animate { animation: bb-fy-halo 1.2s ease-out 2; }
.bb-fy-animate .bb-fy-sheen { animation: bb-fy-sweep 2.4s ease-in-out 1 forwards; }
.bb-fy-sheen { opacity: 0; }
@media (prefers-reduced-motion: reduce) { .bb-fy-animate, .bb-fy-animate .bb-fy-sheen { animation: none !important; } }
`;

export default function ForYouChip({ T, active, pending, animate, onClick, capsuleStyle }) {
  const label = T('Dành cho bạn', 'For You');
  const aria = pending && !active ? T('Dành cho bạn, có gợi ý mới', 'For You, new recommendations') : label;
  return (
    <span
      onClick={onClick}
      data-testid="home-filter-foryou"
      data-foryou-pending={pending ? 'true' : 'false'}
      className={animate ? 'bb-fy-animate' : undefined}
      role="button"
      aria-label={aria}
      aria-pressed={!!active}
      style={{ ...capsuleStyle, position: 'relative', gap: 6, flex: 'none', flexShrink: 0 }}
    >
      <style>{CSS}</style>
      <span aria-hidden="true" style={{ position: 'absolute', inset: 0, borderRadius: 999, overflow: 'hidden', pointerEvents: 'none' }}>
        <span className="bb-fy-sheen" style={{ position: 'absolute', top: 0, bottom: 0, width: '45%', background: 'linear-gradient(100deg, transparent, rgba(255,226,140,0.75), transparent)' }} />
      </span>
      <span aria-hidden="true" style={{ color: '#E0A526', fontSize: 15, lineHeight: 1 }}>★</span>
      {label}
      {pending && (
        <span data-testid="home-foryou-new" aria-hidden="true" style={{
          marginInlineStart: 2, padding: '1px 6px', borderRadius: 999, fontSize: 10.5, fontWeight: 700,
          lineHeight: '14px', color: '#fff', background: '#7A5200',
        }}>{T('Mới', 'New')}</span>
      )}
    </span>
  );
}

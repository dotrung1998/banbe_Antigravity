// Liquid-glass switch (first built for the migration-181 master switch, now shared with Admin > Feature switches).
// Frosted track that tints on, a glass knob with a springy slide. Purely presentational: the caller decides what a
// tap means (the phone-bypass switch opens a confirmation first; a feature switch flips directly).
export default function GlassSwitch({ on, busy, onPress, testId }) {
  const w = 64, h = 38, k = 30;
  return (
    <div role="switch" aria-checked={on} aria-busy={busy} tabIndex={0} data-testid={testId}
      onClick={() => !busy && onPress()}
      onKeyDown={e => { if ((e.key === ' ' || e.key === 'Enter') && !busy) { e.preventDefault(); onPress(); } }}
      style={{
        position: 'relative', width: w, height: h, borderRadius: h, flex: 'none', cursor: busy ? 'default' : 'pointer', opacity: busy ? 0.6 : 1,
        background: on
          ? 'linear-gradient(165deg, rgba(255,255,255,0.35), rgba(255,255,255,0) 60%), rgba(var(--bb-fg-rgb), 0.82)'
          : 'linear-gradient(165deg, rgba(255,255,255,0.5), rgba(255,255,255,0.05) 60%), rgba(var(--bb-fg-rgb), 0.10)',
        backdropFilter: 'blur(14px) saturate(1.6)', WebkitBackdropFilter: 'blur(14px) saturate(1.6)',
        border: '1px solid rgba(255,255,255,0.35)',
        boxShadow: 'inset 0 1px 2px rgba(255,255,255,0.5), inset 0 -6px 12px rgba(255,255,255,0.06), 0 6px 18px rgba(27,25,22,0.18)',
        transition: 'background 0.35s cubic-bezier(.22,.61,.36,1), opacity 0.2s',
        WebkitMaskImage: '-webkit-radial-gradient(white, black)', maskImage: 'radial-gradient(white, black)',
      }}>
      <div style={{
        position: 'absolute', top: (h - k) / 2 - 1, left: 3, width: k + (busy ? 4 : 0), height: k, borderRadius: k,
        transform: `translateX(${on ? w - k - 8 - (busy ? 4 : 0) : 0}px)`,
        background: 'linear-gradient(160deg, rgba(255,255,255,0.98), rgba(255,255,255,0.72))',
        boxShadow: 'inset 0 1px 1px #fff, 0 3px 10px rgba(27,25,22,0.3)',
        transition: 'transform 0.45s cubic-bezier(.34,1.45,.64,1), width 0.25s cubic-bezier(.22,.61,.36,1)',
      }} />
    </div>
  );
}

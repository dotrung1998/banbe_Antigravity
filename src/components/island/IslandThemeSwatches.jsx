import { ISLAND_THEMES, islandTheme } from '../../lib/islandPrefs.js';
import { ink, ink3, rule } from '../../theme.js';

// Shared style controls (note 101): the eight curated themes and a static mock of the island. Used by the person's
// settings screen and by the admin demo, so a new theme is added in one place (src/lib/islandPrefs.js) and appears
// in both. No dynaura call here: the mock is plain CSS, so it can show a style without firing a notification.

export function IslandThemeSwatches({ value, onChange, T, testId = 'island-theme' }) {
  return (
    <div role="radiogroup" aria-label={T('Kiểu đảo', 'Island style')} style={{ display: 'grid', gridTemplateColumns: 'repeat(4, minmax(0, 1fr))', gap: 8 }}>
      {ISLAND_THEMES.map(t => {
        const on = t.id === value;
        return (
          <button
            key={t.id} type="button" role="radio" aria-checked={on} data-testid={`${testId}-${t.id}`}
            onClick={() => onChange(t.id)}
            style={{
              display: 'flex', flexDirection: 'column', alignItems: 'stretch', gap: 5, minHeight: 62,
              padding: on ? 2 : 3, borderRadius: 16, cursor: 'pointer', fontFamily: 'inherit',
              border: on ? `2px solid ${ink}` : `1px solid ${rule}`, background: 'transparent',
            }}
          >
            <span aria-hidden style={{
              height: 32, borderRadius: 999, background: t.theme.background,
              border: `1px solid ${t.theme.ring}`, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 3,
              boxShadow: t.id === 'paper' ? '0 1px 4px rgba(27,25,22,0.14)' : '0 4px 12px rgba(0,0,0,0.16)',
            }}>
              <i style={{ width: 6, height: 6, borderRadius: '50%', background: t.theme.success }} />
              <i style={{ width: 6, height: 6, borderRadius: '50%', background: t.theme.warning }} />
              <i style={{ width: 6, height: 6, borderRadius: '50%', background: t.theme.info }} />
            </span>
            <span style={{ fontSize: 10.5, lineHeight: 1.2, color: ink, textAlign: 'center', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              {T(t.vi, t.en)}
            </span>
          </button>
        );
      })}
    </div>
  );
}

/** A static, non-interactive island in the chosen theme, on the theme's own stage colour. */
export function IslandPreview({ themeId, T, compact = false, detail = 'full' }) {
  const theme = islandTheme(themeId);
  const t = theme.theme;
  return (
    <div
      data-testid="island-preview" data-theme={themeId}
      style={{
        padding: compact ? '18px 14px' : '26px 16px 24px', borderRadius: 22,
        background: `radial-gradient(120% 160% at 50% 0%, ${theme.stage} 0%, #111 100%)`,
        display: 'flex', justifyContent: 'center',
      }}
    >
      <div style={{
        width: 'min(330px, 100%)', boxSizing: 'border-box', display: 'flex', alignItems: 'center', gap: 10,
        padding: compact ? '10px 12px' : '12px 14px', borderRadius: compact ? 999 : 22,
        background: t.background, color: t.foreground, border: `1px solid ${t.ring}`,
        boxShadow: `0 12px 28px -14px ${t.success}, 0 8px 20px rgba(0,0,0,0.35)`,
        backdropFilter: theme.glass ? 'blur(22px) saturate(1.5)' : undefined,
        WebkitBackdropFilter: theme.glass ? 'blur(22px) saturate(1.5)' : undefined,
      }}>
        <span aria-hidden style={{
          flex: 'none', width: 26, height: 26, borderRadius: '50%', display: 'grid', placeItems: 'center',
          background: `color-mix(in srgb, ${t.success} 18%, transparent)`, color: t.success, fontSize: 13, fontWeight: 700,
        }}>✓</span>
        <span style={{ flex: 1, minWidth: 0 }}>
          <span style={{ display: 'block', fontSize: 13.5, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
            {T('Đã giữ chỗ', 'Seat held')}
          </span>
          {detail !== 'title' && (
            <span style={{ display: 'block', fontSize: 11.5, lineHeight: 1.35, color: t.muted, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
              {T('3 vé · Bếp nhà Bông · T7 19:00', '3 tickets · Bếp nhà Bông · Sat 19:00')}
            </span>
          )}
        </span>
        <span style={{ flex: 'none', fontSize: 11, color: t.muted, fontVariantNumeric: 'tabular-nums' }}>19:00</span>
      </div>
    </div>
  );
}

/** Small caption line shared by the settings and the demo. */
export function IslandRealityNote({ T }) {
  return (
    <p style={{ fontSize: 12, lineHeight: 1.55, color: ink3, margin: 0 }}>
      {T(
        'iOS không cho trang web vẽ vào Đảo Động thật. banbe vẽ một viên đảo cùng vị trí và chuyển động: trong tab Safari nó ở đầu trang, còn khi thêm vào Màn hình chính nó nằm ngay dưới Đảo Động.',
        'iOS does not let a web page draw inside the physical Dynamic Island. banbe draws an island in the same place, with the same motion: at the top of the page in a Safari tab, and just below the Island in a Home Screen app.',
      )}
    </p>
  );
}

import { ink, rule, fieldGlass } from '../theme.js';

// Organizer Team pass (2026-09-27, Stage 3) — shared between the personal
// and organizer edit forms. One obvious "Thêm liên kết" control; only on
// tap does it reveal platform choice + URL field per link. Server-side
// validation (sanitize_social_links, migration 102) is the real boundary
// — this is just a reasonable client-side shape, never trusted alone.
export const LINK_PLATFORMS = [
  { key: 'website', label: 'Website' },
  { key: 'instagram', label: 'Instagram' },
  { key: 'facebook', label: 'Facebook' },
  { key: 'tiktok', label: 'TikTok' },
  { key: 'youtube', label: 'YouTube' },
  { key: 'twitter', label: 'Twitter/X' },
];

export function SocialLinksEditor({ T, links, open, onToggleOpen, onAdd, onSetField, onRemove, testPrefix }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      <div onClick={onToggleOpen} data-testid={`${testPrefix}-toggle`} style={{ fontSize: 11.5, fontWeight: 600, color: ink, cursor: 'pointer' }}>
        {T('Thêm liên kết', 'Add links')} {open ? '▾' : '▸'}
      </div>
      {open && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {links.map((link, i) => (
            <div key={i} style={{ display: 'flex', gap: 8, alignItems: 'center' }} data-testid={`${testPrefix}-row-${i}`}>
              <select
                value={link.platform}
                onChange={(e) => onSetField(i, 'platform', e.target.value)}
                data-testid={`${testPrefix}-platform-${i}`}
                style={{ ...fieldGlass({ padding: '10px 8px', fontSize: 12.5, flex: '0 0 110px' }) }}
              >
                {LINK_PLATFORMS.map(p => <option key={p.key} value={p.key}>{p.label}</option>)}
              </select>
              <input
                value={link.url}
                onChange={(e) => onSetField(i, 'url', e.target.value)}
                placeholder="https://…"
                data-testid={`${testPrefix}-url-${i}`}
                style={{ ...fieldGlass({ padding: '10px 12px', fontSize: 12.5, flex: 1 }) }}
              />
              <span onClick={() => onRemove(i)} data-testid={`${testPrefix}-remove-${i}`} style={{ fontSize: 12, color: ink, opacity: 0.6, cursor: 'pointer', flex: 'none' }}>✕</span>
            </div>
          ))}
          <div onClick={onAdd} data-testid={`${testPrefix}-add`} style={{ fontSize: 12, fontWeight: 600, color: ink, cursor: 'pointer', border: `1px dashed ${rule}`, borderRadius: 10, padding: '10px 0', textAlign: 'center' }}>
            + {T('Thêm một liên kết', 'Add another link')}
          </div>
        </div>
      )}
    </div>
  );
}

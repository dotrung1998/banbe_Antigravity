import { useState } from 'react';
import { ink, rule } from '../theme.js';

// Organizer Team pass (2026-09-27, Stage 3) — a concise preview of the
// separate long-form "Giới thiệu" with "Đọc thêm"/"Thu gọn" to expand —
// shared by the personal and organizer public profile screens. Renders
// nothing at all when there's no long intro to show (never a fabricated
// placeholder).
const PREVIEW_LENGTH = 160;

export function LongIntroPreview({ T, text }) {
  const [expanded, setExpanded] = useState(false);
  if (!text) return null;
  const isLong = text.length > PREVIEW_LENGTH;
  const shown = expanded || !isLong ? text : text.slice(0, PREVIEW_LENGTH).trimEnd() + '…';
  return (
    <div data-testid="long-intro-preview" style={{ textAlign: 'left', width: '100%' }}>
      <p style={{ fontSize: 12.5, lineHeight: 1.6, color: ink, whiteSpace: 'pre-wrap', margin: 0 }}>{shown}</p>
      {isLong && (
        <span
          onClick={() => setExpanded(x => !x)}
          data-testid="long-intro-toggle"
          style={{ fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.7, cursor: 'pointer' }}
        >
          {expanded ? T('Thu gọn', 'Show less') : T('Đọc thêm', 'Read more')}
        </span>
      )}
    </div>
  );
}

const PLATFORM_LABEL = {
  website: 'Website', instagram: 'Instagram', facebook: 'Facebook',
  tiktok: 'TikTok', youtube: 'YouTube', twitter: 'Twitter/X', x: 'X',
};

// Icons/buttons ONLY for saved public links — never a placeholder for a
// platform the profile didn't add.
export function SocialLinksRow({ links }) {
  if (!links || !links.length) return null;
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, justifyContent: 'center' }} data-testid="social-links-row">
      {links.map(l => (
        <a
          key={l.platform + l.url}
          href={l.url}
          target="_blank"
          rel="noopener noreferrer nofollow"
          data-testid={`social-link-${l.platform}`}
          style={{
            fontSize: 11, fontWeight: 600, color: ink, textDecoration: 'none',
            padding: '7px 12px', borderRadius: 999, border: `1px solid ${rule}`,
          }}
        >
          {PLATFORM_LABEL[l.platform] || l.platform}
        </a>
      ))}
    </div>
  );
}

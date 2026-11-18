// The account's face wherever the app offers a way into Account (Home's band, Browse's nav, quick settings).
// The real profile photo wins; initials are the fallback for a signed-in profile without one, and the
// person glyph is the guest state. Same clay disc and paper ring on all three.
import { useEffect, useState } from 'react';

const initials = (name) => String(name || '').trim().split(/\s+/).filter(Boolean).slice(0, 2)
  .map(w => w[0]).join('').toUpperCase();

export default function AccountAvatar({ name = '', avatarUrl = '', size = 40 }) {
  // A photo that fails (expired URL, offline) must not leave an empty clay disc: fall back to initials or the glyph.
  const [failed, setFailed] = useState(false);
  useEffect(() => { setFailed(false); }, [avatarUrl]);
  const fontSize = Math.max(13, Math.round(size * 0.34));
  const iconSize = Math.round(size * 0.42);
  return (
    <span className="bb-home-head__disc" style={{ fontSize }}>
      {avatarUrl && !failed ? <img src={avatarUrl} alt="" decoding="async" onError={() => setFailed(true)} />
        : String(name || '').trim() ? <span aria-hidden="true">{initials(name)}</span>
          : (
            <svg aria-hidden="true" width={iconSize} height={iconSize} viewBox="0 0 24 24" fill="none" stroke="currentColor"
              strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="8" r="4" />
              <path d="M4 21a8 8 0 0 1 16 0" />
            </svg>
          )}
    </span>
  );
}

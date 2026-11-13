// Host deck (v2.3, note 81): under a Browse by type / See all title, four overlapping host faces, then +N, with
// "AEIE Studios, Bàn Dài and 16 more hosts". It turns over one face every few seconds while the screen is open (never
// with Reduced motion, never while the page is hidden). A tap opens the searchable host list. Faces are the hosts' real
// photos (organizers.avatar_path); no photo = a monogram on a theme tint. Rules: src/lib/browse.js.
import { useEffect, useState } from 'react';
import { deckLine, deckFaces, rotateHosts, tintIndex } from '../../lib/browse.js';
import { useReducedMotion } from '../../lib/useReducedMotion.js';

// Monogram tints: theme accent tokens, with the letter in the page colour (dark letter on the light dark-mode
// accents, light letter on the deep light-mode accents), so the contrast holds in both themes.
export const FACE_TINTS = ['var(--bb-clay)', 'var(--bb-update)', 'var(--bb-honey)', 'var(--bb-plum)'];
const CYCLE_MS = 3200;

export function Face({ host, size = 34, ring = 'var(--bb-bg)', style }) {
  const initial = (host.name || '·').trim().charAt(0).toUpperCase();
  return (
    <span aria-hidden="true" style={{ width: size, height: size, borderRadius: '50%', flex: 'none', boxShadow: `0 0 0 2px ${ring}`, display: 'grid', placeItems: 'center',
      color: 'var(--bb-bg)', fontSize: size * 0.42, fontWeight: 700, overflow: 'hidden',
      background: host.avatarUrl ? `center/cover no-repeat url("${host.avatarUrl}")` : FACE_TINTS[tintIndex(host.name, FACE_TINTS.length)], ...style }}>
      {host.avatarUrl ? null : initial}
    </span>
  );
}

/** @param {{ hosts: Array<{id,name,avatarUrl,events}>, onOpen: () => void, T: Function }} p */
export default function HostDeck({ hosts, onOpen, T }) {
  const reduced = useReducedMotion();
  const [order, setOrder] = useState(hosts);
  const sig = hosts.map(h => h.id).join('|');
  // Same hosts (typing a search, say): keep the deck as it is instead of replaying it.
  useEffect(() => { setOrder(hosts); }, [sig]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (reduced || hosts.length <= 1) return undefined;
    const t = setInterval(() => { if (!document.hidden) setOrder(o => rotateHosts(o)); }, CYCLE_MS);
    return () => clearInterval(t);
  }, [reduced, hosts.length]);
  if (!hosts.length) return null;
  const { faces, more } = deckFaces(order);
  const line = deckLine(hosts);
  return (
    <button type="button" onClick={onOpen} data-testid="browse-host-deck" data-hosts={hosts.length}
      aria-label={T(`Xem cả ${hosts.length} host`, `See all ${hosts.length} ${hosts.length === 1 ? 'host' : 'hosts'}`)}
      style={{ display: 'flex', alignItems: 'center', gap: 12, minHeight: 48, padding: '4px 0', border: 'none', background: 'none', color: 'inherit', fontFamily: 'inherit', cursor: 'pointer', textAlign: 'left', maxWidth: '100%' }}>
      <span style={{ display: 'flex', alignItems: 'center', paddingLeft: 2, flex: 'none' }}>
        {faces.map((h, i) => (
          <Face key={h.id} host={h} style={{ marginLeft: i ? -10 : 0, zIndex: faces.length - i, transition: reduced ? 'none' : 'transform .36s cubic-bezier(.2,1.3,.4,1)' }} />
        ))}
        {more > 0 && (
          <span data-testid="browse-host-more" aria-hidden="true" style={{ marginLeft: -10, height: 34, minWidth: 34, padding: '0 8px', borderRadius: 999, boxShadow: '0 0 0 2px var(--bb-bg)', background: 'var(--bb-block)', color: 'var(--bb-fg)', fontSize: 12.5, fontWeight: 700, display: 'grid', placeItems: 'center' }}>+{more}</span>
        )}
      </span>
      <span style={{ minWidth: 0, display: 'flex', flexDirection: 'column' }}>
        <b style={{ fontSize: 14, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{T(line.names.vi, line.names.en)}</b>
        {line.more.en && <small style={{ fontSize: 12.5, opacity: 0.72 }}>{T(line.more.vi, line.more.en)}</small>}
      </span>
    </button>
  );
}

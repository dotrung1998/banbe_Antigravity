// All the hosts of a Browse by type / See all list (v2.3, note 81): searchable by name (accent-insensitive), each with
// how many of these events they host. A tap opens the REAL host profile (/org/<id>, OrganizerProfile.jsx); its Back
// returns to the Browse list. Portals into the phone frame like the other sheets.
import { useEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { filterHosts } from '../../lib/browse.js';
import { Face } from '../../components/browse/HostDeck.jsx';

export default function HostListSheet({ hosts, title, onPick, onClose, T }) {
  const [q, setQ] = useState('');
  const inputRef = useRef(null);
  const rows = useMemo(() => filterHosts(hosts, q), [hosts, q]);
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  const target = typeof document !== 'undefined' ? (document.querySelector('.bb-screen') || document.body) : null;
  if (!target) return null;
  return createPortal(
    <div onClick={onClose} data-testid="host-list-backdrop"
      style={{ position: 'fixed', inset: 0, zIndex: 2100, background: 'rgba(12,12,12,0.45)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'banbeFade 0.2s ease both' }}>
      <div role="dialog" aria-modal="true" aria-labelledby="host-list-title" onClick={(e) => e.stopPropagation()} data-testid="host-list-sheet"
        style={{ background: 'var(--bb-bg)', color: 'var(--bb-fg)', borderRadius: '22px 22px 0 0', maxHeight: '86%', display: 'flex', flexDirection: 'column', animation: 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '14px 16px 6px 20px' }}>
          <div style={{ minWidth: 0 }}>
            <div id="host-list-title" style={{ fontSize: 18, fontWeight: 600 }}>{T(`${hosts.length} host`, `${hosts.length} ${hosts.length === 1 ? 'host' : 'hosts'}`)}</div>
            {title && <div style={{ fontSize: 13, opacity: 0.72 }}>{title}</div>}
          </div>
          <button type="button" onClick={onClose} aria-label={T('Đóng', 'Close')} data-testid="host-list-close"
            style={{ width: 44, height: 44, borderRadius: '50%', border: 'none', background: 'rgba(var(--bb-fg-rgb),0.07)', color: 'inherit', fontSize: 20, cursor: 'pointer', flex: 'none' }}>×</button>
        </div>
        <div style={{ padding: '6px 20px 10px' }}>
          <input ref={inputRef} type="search" value={q} onChange={(e) => setQ(e.target.value)} enterKeyHint="search" autoComplete="off"
            placeholder={T('Tìm host theo tên', 'Search hosts by name')} aria-label={T('Tìm host theo tên', 'Search hosts by name')} data-testid="host-list-search"
            style={{ width: '100%', boxSizing: 'border-box', minHeight: 44, padding: '0 14px', borderRadius: 999, border: '1px solid var(--bb-rule)', background: 'var(--bb-field, var(--bb-block))', color: 'inherit', fontFamily: 'inherit', fontSize: 15 }} />
        </div>
        <ul role="list" style={{ listStyle: 'none', margin: 0, padding: '0 8px 24px', overflowY: 'auto' }}>
          {rows.map(h => (
            <li key={h.id}>
              <button type="button" onClick={() => onPick(h.id)} data-testid={`host-list-row-${h.id}`}
                style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', minHeight: 56, padding: '6px 12px', border: 'none', borderRadius: 14, background: 'none', color: 'inherit', fontFamily: 'inherit', textAlign: 'left', cursor: 'pointer' }}>
                <Face host={h} size={40} ring="transparent" />
                <span style={{ flex: 1, minWidth: 0 }}>
                  <b style={{ display: 'block', fontSize: 15, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{h.name}</b>
                  <small style={{ fontSize: 12.5, opacity: 0.72 }}>{T(`${h.events.length} sự kiện ở đây`, `${h.events.length} ${h.events.length === 1 ? 'event' : 'events'} here`)}</small>
                </span>
                <span aria-hidden="true" style={{ opacity: 0.5 }}>›</span>
              </button>
            </li>
          ))}
          {!rows.length && (
            <li data-testid="host-list-empty" style={{ padding: '18px 12px', fontSize: 14, opacity: 0.72 }}>{T(`Không có host nào tên “${q.trim()}”.`, `No host called “${q.trim()}”.`)}</li>
          )}
        </ul>
      </div>
    </div>,
    target,
  );
}

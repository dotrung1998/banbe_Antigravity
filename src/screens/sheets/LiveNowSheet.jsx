// "Live now" (v2.3, note 81): every update of the Home live line, in the line's order (the summary, then today's Pulse
// ranking), the one shown on Home marked in the Reduced form, each event with Open. Part of browser history like the
// Pulse viewer: opening it pushes an entry, the browser's Back closes it. Portals into the phone frame.
import { useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';

export default function LiveNowSheet({ updates, shownIndex = null, onOpenEvent, onClose, T }) {
  const pushed = useRef(false);
  useEffect(() => {
    // Back closes the sheet (and only the sheet): one history entry while it is open, same URL.
    window.history.pushState({ ...(window.history.state || {}), liveNow: true }, '', window.location.href);
    pushed.current = true;
    const onPop = () => { pushed.current = false; onClose(); };
    const onKey = (e) => { if (e.key === 'Escape') close(); };
    window.addEventListener('popstate', onPop);
    window.addEventListener('keydown', onKey);
    return () => { window.removeEventListener('popstate', onPop); window.removeEventListener('keydown', onKey); };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  // Closing by tap also removes the entry it pushed, so Back afterwards goes where it should. Opening an event instead
  // REPLACES that entry (an async history.back() could land after the navigation and undo it).
  const close = (after) => {
    if (pushed.current) {
      pushed.current = false;
      if (after) { const { liveNow, ...rest } = window.history.state || {}; void liveNow; window.history.replaceState(rest, '', window.location.href); }
      else window.history.back();
    }
    onClose();
    if (after) after();
  };
  const target = typeof document !== 'undefined' ? (document.querySelector('.bb-screen') || document.body) : null;
  if (!target) return null;
  return createPortal(
    <div onClick={() => close()} data-testid="live-now-backdrop"
      style={{ position: 'fixed', inset: 0, zIndex: 2100, background: 'rgba(12,12,12,0.45)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'banbeFade 0.2s ease both' }}>
      <div role="dialog" aria-modal="true" aria-labelledby="live-now-title" onClick={(e) => e.stopPropagation()} data-testid="live-now-sheet"
        style={{ background: 'var(--bb-bg)', color: 'var(--bb-fg)', borderRadius: '22px 22px 0 0', maxHeight: '82%', display: 'flex', flexDirection: 'column', animation: 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, padding: '14px 16px 8px 20px' }}>
          <div>
            <div id="live-now-title" style={{ fontSize: 18, fontWeight: 600 }}>{T('Đang diễn ra', 'Live now')}</div>
            <div style={{ fontSize: 13, opacity: 0.72 }}>{T(`${updates.length} cập nhật hôm nay`, `${updates.length} ${updates.length === 1 ? 'update' : 'updates'} today`)}</div>
          </div>
          <button type="button" onClick={() => close()} aria-label={T('Đóng', 'Close')} data-testid="live-now-close"
            style={{ width: 44, height: 44, borderRadius: '50%', border: 'none', background: 'rgba(var(--bb-fg-rgb),0.07)', color: 'inherit', fontSize: 20, cursor: 'pointer' }}>×</button>
        </div>
        <ul role="list" style={{ listStyle: 'none', margin: 0, padding: '0 8px 24px', overflowY: 'auto' }}>
          {updates.map((u, i) => {
            const here = shownIndex === i;
            const body = (
              <>
                <i aria-hidden="true" style={{ width: 8, height: 8, borderRadius: '50%', flex: 'none', marginTop: 6, background: i === 0 ? 'var(--bb-alert)' : 'rgba(var(--bb-fg-rgb),0.3)' }} />
                <span style={{ flex: 1, minWidth: 0 }}>
                  <b style={{ display: 'block', fontSize: 15, fontWeight: 600, lineHeight: 1.3 }}>{T(u.text.vi, u.text.en)}</b>
                  <small style={{ fontSize: 12.5, opacity: 0.72 }}>
                    {[u.when, here ? T('đang hiện trên Trang chủ', 'showing on Home') : null].filter(Boolean).join(' · ')}
                  </small>
                </span>
                {u.eventId && <span style={{ flex: 'none', fontSize: 13.5, fontWeight: 600, alignSelf: 'center' }}>{T('Mở', 'Open')} ›</span>}
              </>
            );
            const rowStyle = { display: 'flex', alignItems: 'flex-start', gap: 12, width: '100%', minHeight: 56, padding: '10px 12px', border: 'none', borderRadius: 14, background: here ? 'var(--bb-block)' : 'none', color: 'inherit', fontFamily: 'inherit', textAlign: 'left' };
            return (
              <li key={u.id} data-testid={`live-now-row-${i}`} data-here={here ? 'true' : 'false'}>
                {u.eventId
                  ? <button type="button" onClick={() => close(() => onOpenEvent(u.eventId, i))} data-testid={`live-now-open-${i}`} style={{ ...rowStyle, cursor: 'pointer' }}>{body}</button>
                  : <div style={rowStyle}>{body}</div>}
              </li>
            );
          })}
        </ul>
      </div>
    </div>,
    target,
  );
}

import { useEffect, useRef, useState } from 'react';
import { paper, ink, rule, display, fieldSolid, alert, clay } from '../../theme.js';
import { MAX_DRAFTS } from '../../lib/eventDrafts.js';

const fmtSaved = (ms, EN) => new Date(ms).toLocaleString(EN ? 'en-US' : 'vi-VN', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });

/**
 * "Draft saved": what next, in the same card style as "Event submitted!" (CreateEvent's SubmitSuccessChooser; iOS
 * DraftSavedCard). Native <dialog>; Escape / backdrop just closes it.
 */
export function DraftSavedCard({ T, count, onExit, onNew, onViewDrafts, onDismiss }) {
  const ref = useRef(null);
  useEffect(() => { ref.current?.showModal(); }, []);
  const btnBase = {
    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, width: '100%', minHeight: 50,
    fontSize: 15, fontWeight: 600, fontFamily: 'inherit', borderRadius: 18, cursor: 'pointer',
  };
  const secondary = { ...btnBase, background: fieldSolid, border: `1px solid ${rule}`, color: ink };
  const steps = [
    ['📱', T('Lưu trên trình duyệt này, trong tài khoản của bạn', 'Kept in this browser, for your account')],
    ['✏️', T('Tiếp tục chỉnh sửa bất cứ lúc nào', 'Pick it up and edit it any time')],
    ['🗂️', T(`Tối đa ${MAX_DRAFTS} bản nháp (${count}/${MAX_DRAFTS})`, `Up to ${MAX_DRAFTS} drafts (${count}/${MAX_DRAFTS} used)`)],
  ];
  return (
    <dialog
      ref={ref}
      className="bb-bounce-in"
      data-testid="create-draft-saved"
      onCancel={(e) => { e.preventDefault(); onDismiss(); }}
      onClick={(e) => { if (e.target === ref.current) onDismiss(); }}
      style={{ border: `1px solid ${rule}`, borderRadius: 28, padding: 0, maxWidth: 520, width: 'calc(100% - 40px)', background: paper, color: ink, boxShadow: '0 10px 40px rgba(0,0,0,0.18)' }}
    >
      <div style={{ padding: 22 }}>
        <p style={{ ...display(22, { margin: '0 0 16px' }) }}>💾 {T('Đã lưu bản nháp', 'Draft saved')}</p>
        <ul style={{ listStyle: 'none', margin: '0 0 16px', padding: 0, display: 'flex', flexDirection: 'column', gap: 10 }}>
          {steps.map(([icon, text]) => (
            <li key={text} style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: 14.5, lineHeight: 1.35 }}>
              <span aria-hidden style={{ flex: 'none', width: 28, height: 28, borderRadius: '50%', background: fieldSolid, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13 }}>{icon}</span>
              {text}
            </li>
          ))}
        </ul>
        <p style={{ fontSize: 13.5, fontWeight: 600, opacity: 0.75, margin: '0 0 12px' }}>{T('Bạn muốn làm gì tiếp theo?', 'What would you like to do next?')}</p>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <button onClick={onViewDrafts} data-testid="create-draft-saved-view" className="bb-press" style={{ ...btnBase, background: ink, color: paper, border: 'none' }}>
            <span aria-hidden>🗂️</span>{T('Xem bản nháp', 'View drafts')}
          </button>
          <button onClick={onNew} data-testid="create-draft-saved-new" className="bb-press" style={secondary}>
            <span aria-hidden>📝</span>{T('Bắt đầu bản nháp mới', 'Start a new draft')}
          </button>
          <button onClick={onExit} data-testid="create-draft-saved-exit" className="bb-press" style={secondary}>
            <span aria-hidden>↩︎</span>{T('Thoát', 'Exit')}
          </button>
        </div>
      </div>
    </dialog>
  );
}

/** One draft card: tap to continue; ⋯ or a swipe left reveals Edit / Delete. */
function DraftRow({ T, EN, draft, thumb, onOpen, onAskDelete }) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [dx, setDx] = useState(0);         // swipe offset (negative = revealed)
  const drag = useRef(null);
  const REVEAL = 150;
  const name = (draft.fields?.createName || '').trim();

  const onDown = (e) => { drag.current = { x: e.clientX, y: e.clientY, base: dx, moved: false }; };
  const onMove = (e) => {
    const g = drag.current;
    if (!g) return;
    const ddx = e.clientX - g.x;
    if (!g.moved && Math.abs(ddx) < 8) return;
    if (!g.moved && Math.abs(e.clientY - g.y) > Math.abs(ddx)) { drag.current = null; return; }  // vertical scroll
    g.moved = true;
    setDx(Math.max(-REVEAL, Math.min(0, g.base + ddx)));
  };
  const onUp = () => {
    const g = drag.current;
    drag.current = null;
    if (!g?.moved) return;
    setDx(cur => (cur < -REVEAL / 2 ? -REVEAL : 0));
  };
  const actionBtn = (bg) => ({ width: REVEAL / 2, border: 'none', color: '#fff', background: bg, fontFamily: 'inherit', fontSize: 13, fontWeight: 700, cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 4 });

  return (
    <div style={{ position: 'relative', borderRadius: 18, overflow: 'hidden' }} data-testid={`create-draft-${draft.id}`}>
      {/* Revealed by a swipe left. */}
      <div style={{ position: 'absolute', inset: 0, display: 'flex', justifyContent: 'flex-end' }}>
        <button style={actionBtn(clay)} onClick={() => { setDx(0); onOpen(draft); }} data-testid="create-draft-swipe-edit"><span aria-hidden>✏️</span>{T('Sửa', 'Edit')}</button>
        <button style={actionBtn(alert)} onClick={() => { setDx(0); onAskDelete(draft); }} data-testid="create-draft-swipe-delete"><span aria-hidden>🗑️</span>{T('Xoá', 'Delete')}</button>
      </div>
      <div
        onPointerDown={onDown} onPointerMove={onMove} onPointerUp={onUp} onPointerCancel={onUp}
        style={{ position: 'relative', display: 'flex', alignItems: 'center', gap: 12, padding: 12, background: fieldSolid, borderRadius: 18, transform: `translateX(${dx}px)`, transition: drag.current ? 'none' : 'transform .22s ease', touchAction: 'pan-y' }}
      >
        <div
          role="button" tabIndex={0}
          onClick={() => { if (dx) { setDx(0); return; } onOpen(draft); }}
          onKeyDown={(e) => { if (e.key === 'Enter') onOpen(draft); }}
          data-testid={`create-draft-open-${draft.id}`}
          style={{ display: 'flex', alignItems: 'center', gap: 12, flex: 1, minWidth: 0, cursor: 'pointer' }}
        >
          <div style={{ width: 56, height: 56, flex: 'none', borderRadius: 12, background: paper, overflow: 'hidden', display: 'flex', alignItems: 'center', justifyContent: 'center', opacity: thumb ? 1 : 0.5 }}>
            {thumb ? <img src={thumb} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : <span aria-hidden>🖼️</span>}
          </div>
          <div style={{ minWidth: 0, flex: 1 }}>
            <div style={{ fontSize: 15, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{name || T('Chưa đặt tên', 'Untitled event')}</div>
            <div style={{ fontSize: 12, opacity: 0.65 }}>{T('Lưu ', 'Saved ')}{fmtSaved(draft.savedAt, EN)}</div>
            <div style={{ fontSize: 12, opacity: 0.65 }}>{T(`${draft.photos?.length || 0} ảnh · bước ${(draft.step || 0) + 1}/5`, `${draft.photos?.length || 0} photos · step ${(draft.step || 0) + 1}/5`)}</div>
          </div>
        </div>
        <div style={{ position: 'relative', flex: 'none' }}>
          <button
            onClick={() => setMenuOpen(o => !o)} aria-label={T('Thao tác bản nháp', 'Draft actions')} aria-expanded={menuOpen}
            data-testid={`create-draft-menu-${draft.id}`}
            style={{ width: 36, height: 36, borderRadius: '50%', background: paper, border: `1px solid ${rule}`, color: ink, fontSize: 16, fontWeight: 700, cursor: 'pointer', fontFamily: 'inherit' }}
          >⋯</button>
          {menuOpen && (
            <div role="menu" style={{ position: 'absolute', right: 0, top: 42, zIndex: 3, minWidth: 150, background: paper, border: `1px solid ${rule}`, borderRadius: 14, boxShadow: '0 8px 24px rgba(0,0,0,0.16)', overflow: 'hidden' }}>
              <button role="menuitem" onClick={() => { setMenuOpen(false); onOpen(draft); }} data-testid="create-draft-menu-edit"
                style={{ display: 'block', width: '100%', textAlign: 'left', padding: '12px 14px', border: 'none', background: 'transparent', color: ink, fontFamily: 'inherit', fontSize: 14, cursor: 'pointer' }}>✏️ {T('Sửa', 'Edit')}</button>
              <button role="menuitem" onClick={() => { setMenuOpen(false); onAskDelete(draft); }} data-testid="create-draft-menu-delete"
                style={{ display: 'block', width: '100%', textAlign: 'left', padding: '12px 14px', border: 'none', borderTop: `1px solid ${rule}`, background: 'transparent', color: alert, fontFamily: 'inherit', fontSize: 14, cursor: 'pointer' }}>🗑️ {T('Xoá', 'Delete')}</button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/**
 * The host's drafts, laid out like the Share card sheet (ProfileShareSheet: paper sheet sliding up, grab bar, title
 * centred with the glass ✕ on the right). Tap a draft to continue it; ⋯ or swipe left for Edit / Delete.
 */
export function EventDraftsSheet({ T, EN, drafts, onOpen, onDelete, onClose }) {
  const [closing, setClosing] = useState(false);
  const [pendingDelete, setPendingDelete] = useState(null);
  const [thumbs, setThumbs] = useState({});

  useEffect(() => {
    const urls = {};
    for (const d of drafts) {
      const p = d.photos?.[Math.min(d.coverIndex || 0, (d.photos?.length || 1) - 1)];
      if (p?.blob) urls[d.id] = URL.createObjectURL(p.blob);
    }
    setThumbs(urls);
    return () => Object.values(urls).forEach(u => URL.revokeObjectURL(u));
  }, [drafts]);

  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') requestClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  function requestClose() {
    if (closing) return;
    setClosing(true);
    setTimeout(() => { setClosing(false); onClose(); }, 220);
  }

  return (
    <div onClick={requestClose} data-testid="create-drafts-sheet"
      style={{ position: 'fixed', inset: 0, zIndex: 70, background: 'rgba(27,25,22,0.5)', display: 'flex', alignItems: 'flex-end', animation: closing ? 'banbeFade 0.22s ease reverse both' : 'banbeFade 0.22s ease both' }}>
      <div onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true" aria-label={T('Bản nháp', 'Drafts')}
        style={{ background: paper, color: ink, width: '100%', maxHeight: '94%', overflowY: 'auto', borderRadius: '18px 18px 0 0', padding: '10px 20px 28px', boxSizing: 'border-box',
          animation: closing ? 'banbeSheetOut 0.22s cubic-bezier(.22,.61,.36,1) both' : 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
        <div style={{ width: 36, height: 4, background: rule, borderRadius: 2, margin: '6px auto 12px' }} />
        <div style={{ position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: 36 }}>
          <span onClick={requestClose} role="button" aria-label={T('Đóng', 'Close')} data-testid="create-drafts-close"
            style={{ position: 'absolute', right: 0, top: '50%', transform: 'translateY(-50%)', width: 36, height: 36, borderRadius: '50%', background: 'rgba(120,120,128,0.16)', backdropFilter: 'blur(14px) saturate(1.6)', WebkitBackdropFilter: 'blur(14px) saturate(1.6)', boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,0.35), 0 1px 4px rgba(0,0,0,0.12)', color: ink, fontSize: 15, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>✕</span>
          <span style={{ ...display(17) }}>{T(`Bản nháp (${drafts.length}/${MAX_DRAFTS})`, `Drafts (${drafts.length}/${MAX_DRAFTS})`)}</span>
        </div>
        <p style={{ fontSize: 11, opacity: 0.65, lineHeight: 1.5, margin: '14px 0' }}>
          {T(`Bản nháp lưu trên trình duyệt này, tối đa ${MAX_DRAFTS}. Chạm để tiếp tục, hoặc vuốt trái / chạm ⋯ để sửa hay xoá.`,
            `Drafts are kept in this browser, up to ${MAX_DRAFTS}. Tap one to continue, or swipe left / tap ⋯ to edit or delete.`)}
        </p>
        {drafts.length === 0 && <p style={{ fontSize: 13, opacity: 0.7 }}>{T('Chưa có bản nháp nào.', 'No drafts yet.')}</p>}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {drafts.map(d => (
            <DraftRow key={d.id} T={T} EN={EN} draft={d} thumb={thumbs[d.id]} onOpen={onOpen} onAskDelete={setPendingDelete} />
          ))}
        </div>
        {pendingDelete && (
          <div role="alertdialog" data-testid="create-draft-delete-confirm"
            style={{ marginTop: 16, padding: 14, borderRadius: 16, border: `1px solid ${rule}`, background: fieldSolid }}>
            <div style={{ fontSize: 14, fontWeight: 600 }}>{T('Xoá bản nháp này?', 'Delete this draft?')}</div>
            <div style={{ fontSize: 12.5, opacity: 0.7, margin: '4px 0 12px' }}>{T('Thông tin và ảnh trong bản nháp sẽ mất.', 'Its details and photos will be gone.')}</div>
            <div style={{ display: 'flex', gap: 10 }}>
              <button onClick={() => setPendingDelete(null)} className="bb-press"
                style={{ flex: 1, minHeight: 44, borderRadius: 14, border: `1px solid ${rule}`, background: paper, color: ink, fontFamily: 'inherit', fontWeight: 600, cursor: 'pointer' }}>{T('Huỷ', 'Cancel')}</button>
              <button onClick={() => { onDelete(pendingDelete); setPendingDelete(null); }} data-testid="create-draft-delete-yes" className="bb-press"
                style={{ flex: 1, minHeight: 44, borderRadius: 14, border: 'none', background: alert, color: '#fff', fontFamily: 'inherit', fontWeight: 700, cursor: 'pointer' }}>{T('Xoá', 'Delete')}</button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

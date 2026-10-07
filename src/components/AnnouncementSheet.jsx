import { useMemo, useState } from 'react';
import { paper, ink, rule, display, fieldGlass, alert } from '../theme.js';
import {
  ANNOUNCEMENT_CATEGORIES, ANNOUNCEMENT_TEMPLATES, ANNOUNCEMENT_MAX, ANNOUNCEMENT_ERRORS, filterAnnouncementTemplates,
} from '../lib/eventAnnouncements.js';

// Host "send announcement" sheet (migration 166). Mirrors iOS EventAnnouncementSheet.
// Layout, top to bottom: message box (what will be sent) → 3 one-tap quick picks →
// search + category chips → template list → sticky Send (two-step confirm).
const QUICK_IDS = ['starting-soon', 'delay-15', 'doors-open'];

export default function AnnouncementSheet({ eventKey, eventName, lang, T, send, onClose }) {
  const [text, setText] = useState('');
  const [templateId, setTemplateId] = useState(null);
  const [category, setCategory] = useState('all');
  const [query, setQuery] = useState('');
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [sent, setSent] = useState(null);

  const pick = (t) => { setText(t[lang]); setTemplateId(t.id); setConfirming(false); setError(''); };
  const list = useMemo(() => filterAnnouncementTemplates(query, category), [query, category]);
  const quick = QUICK_IDS.map(id => ANNOUNCEMENT_TEMPLATES.find(t => t.id === id));
  const trimmed = text.trim();
  const tooLong = trimmed.length > ANNOUNCEMENT_MAX;
  const canSend = trimmed.length > 0 && !tooLong && !busy;
  const tplCategory = templateId ? ANNOUNCEMENT_TEMPLATES.find(t => t.id === templateId)?.category : null;

  const doSend = async () => {
    setBusy(true); setError('');
    const res = await send(eventKey, tplCategory || 'custom', trimmed, templateId);
    setBusy(false);
    if (res?.success) { setSent(res.sent ?? 0); return; }
    const m = ANNOUNCEMENT_ERRORS[res?.error];
    setError(m ? T(m[0], m[1]) : T('Không gửi được. Thử lại nhé.', "Couldn't send. Please try again."));
    setConfirming(false);
  };

  const chip = (active) => ({
    flex: 'none', fontSize: 12, fontWeight: 600, padding: '7px 13px', borderRadius: 999, cursor: 'pointer', whiteSpace: 'nowrap',
    border: `1px solid ${active ? alert : rule}`, background: active ? alert : 'transparent', color: active ? 'var(--bb-on-alert, #fff)' : ink,
  });

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 60, background: 'rgba(27,25,22,0.45)', display: 'flex', alignItems: 'flex-end', justifyContent: 'center' }}
         onClick={busy ? undefined : onClose} data-testid="announcement-sheet">
      <div onClick={e => e.stopPropagation()} style={{ background: paper, color: ink, width: '100%', maxWidth: 480, height: '92%', display: 'flex', flexDirection: 'column', borderRadius: '22px 22px 0 0' }}>
        <div style={{ padding: '20px 22px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
          <div style={{ minWidth: 0 }}>
            <h2 style={{ ...display(21, { margin: 0 }) }}>📣 {T('Thông báo cho khách', 'Announce to guests')}</h2>
            <div style={{ fontSize: 11.5, opacity: 0.65, marginTop: 3, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{eventName}</div>
          </div>
          <span onClick={onClose} data-testid="announcement-close" style={{ fontSize: 12.5, cursor: 'pointer', flex: 'none' }}>{sent != null ? T('Xong', 'Done') : T('Đóng', 'Close')}</span>
        </div>

        {sent != null ? (
          <div style={{ padding: '40px 22px', textAlign: 'center' }} data-testid="announcement-sent">
            <div style={{ fontSize: 34, color: alert }}>✓</div>
            <p style={{ fontSize: 15, fontWeight: 600, margin: '10px 0 4px' }}>{sent === 0 ? T('Chưa có khách nào khác để gửi', 'No other ticket holders to notify') : T(`Đã gửi cho ${sent} khách`, `Sent to ${sent} guest${sent === 1 ? '' : 's'}`)}</p>
            <p style={{ fontSize: 12.5, opacity: 0.7, margin: 0 }}>{sent === 0 ? T('Thông báo chỉ gửi cho người giữ vé khác bạn (bạn không tự nhận thông báo của mình).', "Announcements go to ticket holders other than you; you don't receive your own.") : T('Khách nhận thông báo và tin nhắn nổi bật màu đỏ trong chat.', 'Guests get a notification and a red-highlighted chat message.')}</p>
          </div>
        ) : (
          <>
            <div style={{ flex: 1, overflowY: 'auto', padding: '14px 22px 8px' }}>
              <textarea
                value={text} onChange={e => { setText(e.target.value); setConfirming(false); }} rows={3} maxLength={ANNOUNCEMENT_MAX + 50}
                placeholder={T('Chọn mẫu bên dưới hoặc tự viết tin nhắn…', 'Pick a template below or write your own…')}
                data-testid="announcement-text"
                style={{ ...fieldGlass({ padding: '12px 14px', width: '100%', boxSizing: 'border-box', fontSize: 14, lineHeight: 1.45, resize: 'none', fontFamily: 'inherit', color: ink, border: `1px solid ${alert}` }) }}
              />
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, opacity: 0.65, margin: '4px 2px 0' }}>
                <span>{templateId ? T('Từ mẫu — bạn có thể sửa', 'From a template — you can edit it') : T('Tin nhắn tuỳ chỉnh', 'Custom message')}</span>
                <span style={{ color: tooLong ? alert : ink }}>{trimmed.length}/{ANNOUNCEMENT_MAX}</span>
              </div>

              <div style={{ fontSize: 11.5, fontWeight: 600, margin: '14px 0 8px' }}>{T('Gửi nhanh', 'Quick send')}</div>
              <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                {quick.map(t => (
                  <span key={t.id} onClick={() => pick(t)} data-testid={`announcement-quick-${t.id}`} style={chip(templateId === t.id)}>{t[lang].replace(/[!.]$/, '').split(',')[0]}</span>
                ))}
              </div>

              <div style={{ ...fieldGlass({ display: 'flex', alignItems: 'center', gap: 8, padding: '9px 12px', marginTop: 16 }) }}>
                <span aria-hidden="true" style={{ opacity: 0.55 }}>⌕</span>
                <input value={query} onChange={e => setQuery(e.target.value)} placeholder={T('Tìm mẫu thông báo…', 'Search templates…')} data-testid="announcement-search"
                       style={{ flex: 1, border: 'none', background: 'transparent', outline: 'none', fontSize: 14, color: ink, fontFamily: 'inherit' }} />
                {query && <span onClick={() => setQuery('')} style={{ cursor: 'pointer', opacity: 0.55 }}>✕</span>}
              </div>
              <div data-hscroll="true" style={{ display: 'flex', gap: 8, overflowX: 'auto', padding: '10px 0 4px', scrollbarWidth: 'none' }}>
                <span onClick={() => setCategory('all')} style={chip(category === 'all')} data-testid="announcement-cat-all">{T('Tất cả', 'All')}</span>
                {ANNOUNCEMENT_CATEGORIES.map(c => (
                  <span key={c.id} onClick={() => setCategory(c.id)} style={chip(category === c.id)} data-testid={`announcement-cat-${c.id}`}>{c[lang]}</span>
                ))}
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 6 }} data-testid="announcement-list">
                {list.length === 0 && <p style={{ fontSize: 12.5, opacity: 0.7, margin: '10px 2px' }}>{T('Không có mẫu phù hợp. Bạn có thể tự viết ở khung trên.', 'No matching template. Write your own in the box above.')}</p>}
                {list.map(t => (
                  <div key={t.id} onClick={() => pick(t)} data-testid={`announcement-template-${t.id}`}
                       style={{ ...fieldGlass({ padding: '12px 14px', cursor: 'pointer', fontSize: 13.5, lineHeight: 1.4 }), outline: templateId === t.id ? `1.5px solid ${alert}` : 'none' }}>
                    {t[lang]}
                  </div>
                ))}
              </div>
            </div>

            <div style={{ padding: '12px 22px 22px', borderTop: `1px solid ${rule}` }}>
              {error && <p style={{ fontSize: 12, color: alert, margin: '0 0 8px' }} data-testid="announcement-error">{error}</p>}
              {confirming ? (
                <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
                  <span style={{ flex: 1, fontSize: 12.5, fontWeight: 600 }}>{T('Gửi cho tất cả người giữ vé?', 'Send to all ticket holders?')}</span>
                  <span onClick={() => !busy && setConfirming(false)} style={{ fontSize: 13, cursor: 'pointer' }}>{T('Huỷ', 'Cancel')}</span>
                  <span onClick={doSend} data-testid="announcement-confirm" style={{ fontSize: 13.5, fontWeight: 700, color: 'var(--bb-on-alert, #fff)', background: alert, borderRadius: 14, padding: '11px 20px', cursor: 'pointer', opacity: busy ? 0.6 : 1 }}>{busy ? T('Đang gửi…', 'Sending…') : T('Gửi ngay', 'Send now')}</span>
                </div>
              ) : (
                <div onClick={() => canSend && setConfirming(true)} data-testid="announcement-send"
                     style={{ textAlign: 'center', fontSize: 14.5, fontWeight: 700, color: 'var(--bb-on-alert, #fff)', background: alert, borderRadius: 16, padding: '14px', cursor: canSend ? 'pointer' : 'not-allowed', opacity: canSend ? 1 : 0.4 }}>
                  {T('Gửi thông báo', 'Send announcement')}
                </div>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}

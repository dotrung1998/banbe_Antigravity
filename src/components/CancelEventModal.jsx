import { useEffect, useMemo, useState } from 'react';
import { supabase } from '../lib/supabase.js';
import { paper, ink, rule, display, fieldGlass, alert } from '../theme.js';
import { CANCELLATION_TEMPLATES, buildCancellationDraft, buildMailtoUrl } from '../lib/eventCancellationTemplates.js';

// Host flow, two phases. Mirrors apps/ios/BanbeApp/Views/CancelEventSheet.swift.
//
//   plan  pick an apology template, preview it, confirm → cancel_event RPC
//         (cancels every ticket, opens the refund claims).
//   send  one personalised draft per ticket holder, each opened in the HOST'S OWN
//         mail app (mailto:) so they press Send from their own mailbox. banbe
//         sends nothing; each guest sees only their own address.
//
// A cancelled event opens straight into `send`, so the host can leave and come
// back to finish. Which guests they've already drafted is remembered on this device.

const draftedKey = (eventKey) => `banbe.cancelDrafts.${eventKey}`;
const readDrafted = (eventKey) => {
  try { return new Set(JSON.parse(localStorage.getItem(draftedKey(eventKey)) || '[]')); } catch { return new Set(); }
};

export default function CancelEventModal({
  eventKey, eventName, eventDate, eventPlace, organizerName, lang, T, cancelEvent,
  alreadyCancelled = false, onClose, onFinished,
}) {
  const [phase, setPhase] = useState(alreadyCancelled ? 'send' : 'plan');
  const [holders, setHolders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadFailed, setLoadFailed] = useState(false);
  const [templateKey, setTemplateKey] = useState(CANCELLATION_TEMPLATES[0].key);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [drafted, setDrafted] = useState(() => readDrafted(eventKey));

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data, error: err } = await supabase.rpc('get_event_ticket_holders', { p_event: eventKey });
      if (!alive) return;
      if (err || !data?.success) setLoadFailed(true);
      else setHolders(data.holders || []);
      setLoading(false);
    })();
    return () => { alive = false; };
  }, [eventKey]);

  const template = CANCELLATION_TEMPLATES.find(t => t.key === templateKey);
  const base = { eventName, eventDate, eventPlace, organizerName };
  const sample = useMemo(
    () => buildCancellationDraft(template, lang, { ...base, guestName: holders[0]?.name ?? '' }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [template, lang, holders, eventName, eventDate, eventPlace, organizerName],
  );

  const markDrafted = (email) => {
    setDrafted(prev => {
      const next = new Set(prev).add(email);
      try { localStorage.setItem(draftedKey(eventKey), JSON.stringify([...next])); } catch { /* optional */ }
      return next;
    });
  };

  const individualUrl = (h) => {
    const d = buildCancellationDraft(template, lang, { ...base, guestName: h.name });
    return buildMailtoUrl({ to: [h.email] }, d.subject, d.body);
  };
  const groupUrl = () => {
    const d = buildCancellationDraft(template, lang, { ...base, guestNames: holders.map(h => h.name) });
    return buildMailtoUrl({ bcc: holders.map(h => h.email) }, d.subject, d.body);
  };

  const doCancel = async () => {
    setBusy(true);
    setError('');
    const result = await cancelEvent(eventKey, sample.reason);
    setBusy(false);
    setConfirming(false);
    if (!result?.success) {
      setError(result?.error === 'NOT_AUTHORIZED'
        ? T('Bạn không có quyền huỷ sự kiện này.', "You're not allowed to cancel this event.")
        : T('Không huỷ được sự kiện. Vui lòng thử lại.', "Couldn't cancel the event. Please try again."));
      return;
    }
    setPhase('send');
  };

  const templatePicker = (
    <>
      <div style={{ fontSize: 11.5, fontWeight: 600, margin: '16px 0 8px' }}>{T('Chọn mẫu thư xin lỗi', 'Choose an apology template')}</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {CANCELLATION_TEMPLATES.map(t => (
          <div key={t.key} onClick={() => setTemplateKey(t.key)} data-testid={`cancel-template-${t.key}`}
               style={{ ...fieldGlass({ padding: '13px 14px', cursor: 'pointer', fontSize: 14, display: 'flex', alignItems: 'center', gap: 10 }), outline: t.key === templateKey ? `1.5px solid ${ink}` : 'none' }}>
            <span>{t.key === templateKey ? '●' : '○'}</span>{t.title[lang]}
          </div>
        ))}
      </div>
    </>
  );

  const preview = (
    <>
      <div style={{ fontSize: 11.5, fontWeight: 600, margin: '16px 0 8px' }}>
        {T('Xem trước', 'Preview')}{holders[0]?.name ? ` · ${T('ví dụ cho', 'as sent to')} ${holders[0].name}` : ''}
      </div>
      <div style={{ ...fieldGlass({ padding: 14 }) }} data-testid="cancel-preview">
        <div style={{ fontSize: 13, fontWeight: 600 }}>{sample.subject}</div>
        <div style={{ borderTop: `1px solid ${rule}`, margin: '8px 0' }} />
        <div style={{ fontSize: 12.5, lineHeight: 1.55, whiteSpace: 'pre-wrap' }}>{sample.body}</div>
      </div>
    </>
  );

  const shell = (children) => (
    <div style={{ position: 'fixed', inset: 0, zIndex: 60, background: 'rgba(27,25,22,0.45)', display: 'flex', alignItems: 'flex-end', justifyContent: 'center' }}
         onClick={busy ? undefined : onClose} data-testid="cancel-event-modal">
      <div onClick={e => e.stopPropagation()} style={{ background: paper, color: ink, width: '100%', maxWidth: 480, maxHeight: '92%', overflowY: 'auto', borderRadius: '22px 22px 0 0', padding: '22px 22px 28px' }}>
        {children}
      </div>
    </div>
  );

  if (phase === 'send') {
    return shell(
      <>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h2 style={{ ...display(22, { margin: 0 }) }}>{T('Gửi thư cho khách', 'Email your guests')}</h2>
          <span onClick={onFinished} style={{ fontSize: 12.5, cursor: 'pointer' }} data-testid="cancel-send-done">{T('Xong', 'Done')}</span>
        </div>
        <p style={{ fontSize: 12.5, opacity: 0.75, margin: '10px 0 0' }}>
          {T('Mỗi thư mở trong ứng dụng email của bạn, gửi riêng cho từng khách. Bạn tự bấm Gửi từ hộp thư của mình.',
             "Each email opens in your own mail app, addressed to one guest. You press Send from your own mailbox.")}
        </p>
        {loading && <p style={{ fontSize: 12.5, margin: '18px 0' }}>{T('Đang tải…', 'Loading…')}</p>}
        {loadFailed && <p style={{ fontSize: 12.5, color: alert, margin: '18px 0' }}>{T('Không tải được danh sách người giữ vé. Hãy thử lại.', "Couldn't load the ticket holders. Please try again.")}</p>}
        {!loading && !loadFailed && (
          <>
            {templatePicker}
            {preview}
            <div style={{ fontSize: 11.5, fontWeight: 600, margin: '18px 0 8px' }}>
              {holders.length
                ? T(`Đã mở thư cho ${holders.filter(h => drafted.has(h.email)).length}/${holders.length} khách`, `${holders.filter(h => drafted.has(h.email)).length} of ${holders.length} guests drafted`)
                : T('Không có người giữ vé nào để gửi thư.', 'No ticket holders to email.')}
            </div>
            <div style={{ ...fieldGlass({ display: 'flex', flexDirection: 'column' }) }}>
              {holders.map((h, i) => (
                <div key={h.email} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, padding: '12px 14px', borderBottom: i < holders.length - 1 ? `1px solid ${rule}` : 'none' }}>
                  <div style={{ minWidth: 0 }}>
                    <div style={{ fontSize: 14, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{h.name || T('Khách', 'Guest')}</div>
                    <div style={{ fontSize: 11.5, opacity: 0.7, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{h.email}</div>
                  </div>
                  <a href={individualUrl(h)} onClick={() => markDrafted(h.email)} data-testid="cancel-draft-one"
                     style={{ flex: 'none', fontSize: 12.5, fontWeight: 600, color: ink, textDecoration: 'none', border: `1px solid ${rule}`, borderRadius: 999, padding: '7px 14px' }}>
                    {drafted.has(h.email) ? T('Đã mở ✓', 'Drafted ✓') : T('Soạn thư', 'Draft email')}
                  </a>
                </div>
              ))}
            </div>
            {holders.length > 1 && (
              <p style={{ fontSize: 11.5, margin: '14px 0 0' }}>
                <a href={groupUrl()} onClick={() => holders.forEach(h => markDrafted(h.email))} style={{ color: ink }} data-testid="cancel-draft-group">
                  {T('Hoặc soạn một thư chung cho tất cả (BCC)', 'Or draft one email to everyone (BCC)')}
                </a>
              </p>
            )}
          </>
        )}
      </>,
    );
  }

  return shell(
    <>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h2 style={{ ...display(22, { margin: 0 }) }}>{T(`Huỷ sự kiện "${eventName}"`, `Cancel "${eventName}"`)}</h2>
        <span onClick={busy ? undefined : onClose} style={{ fontSize: 12.5, cursor: 'pointer' }}>{T('Đóng', 'Close')}</span>
      </div>
      <p style={{ fontSize: 12.5, opacity: 0.75, margin: '10px 0 0' }}>
        {T('Tất cả vé sẽ bị huỷ và các khoản đã thanh toán được chuyển vào mục hoàn tiền. Việc này không thể hoàn tác.',
           "Every ticket will be cancelled and paid tickets move to refunds. This can't be undone.")}
      </p>
      {loading && <p style={{ fontSize: 12.5, margin: '18px 0' }}>{T('Đang tải…', 'Loading…')}</p>}
      {loadFailed && <p style={{ fontSize: 12.5, color: alert, margin: '18px 0' }}>{T('Không tải được danh sách người giữ vé. Hãy thử lại.', "Couldn't load the ticket holders. Please try again.")}</p>}
      {!loading && !loadFailed && (
        <>
          <p style={{ fontSize: 12.5, margin: '16px 0 0' }}>
            {holders.length
              ? T(`Sau khi huỷ, bạn sẽ soạn thư xin lỗi riêng cho ${holders.length} người giữ vé, gửi từ email của bạn.`,
                  `After cancelling you'll draft a separate apology to each of ${holders.length} ticket holder(s), sent from your own email.`)
              : T('Chưa có người giữ vé nào để gửi thư.', 'No ticket holders to email.')}
          </p>
          {templatePicker}
          {preview}
        </>
      )}
      {error && <p style={{ fontSize: 12, color: alert, margin: '12px 0 0' }}>{error}</p>}
      {!confirming ? (
        <button disabled={loading || loadFailed || busy} onClick={() => setConfirming(true)} data-testid="cancel-event-confirm"
                style={{ width: '100%', marginTop: 18, padding: '15px 0', border: 'none', borderRadius: 18, background: alert, color: '#fff', fontSize: 15, fontWeight: 600, cursor: 'pointer', opacity: loading || loadFailed ? 0.5 : 1 }}>
          {T('Huỷ sự kiện', 'Cancel event')}
        </button>
      ) : (
        <div style={{ marginTop: 18, ...fieldGlass({ padding: 14 }) }}>
          <div style={{ fontSize: 13, fontWeight: 600 }}>{T('Huỷ sự kiện này?', 'Cancel this event?')}</div>
          <div style={{ fontSize: 12, opacity: 0.8, margin: '4px 0 12px' }}>
            {holders.length
              ? T(`${holders.length} người giữ vé sẽ bị huỷ vé.`, `${holders.length} ticket holder(s) will lose their tickets.`)
              : T('Sự kiện sẽ bị huỷ.', 'The event will be cancelled.')}
          </div>
          <div style={{ display: 'flex', gap: 10 }}>
            <button disabled={busy} onClick={doCancel} data-testid="cancel-event-yes"
                    style={{ flex: 1, padding: '12px 0', border: 'none', borderRadius: 14, background: alert, color: '#fff', fontSize: 13.5, fontWeight: 600, cursor: 'pointer' }}>
              {busy ? '…' : T('Có, huỷ sự kiện', 'Yes, cancel the event')}
            </button>
            <button disabled={busy} onClick={() => setConfirming(false)}
                    style={{ flex: 1, padding: '12px 0', border: `1px solid ${rule}`, borderRadius: 14, background: 'transparent', color: ink, fontSize: 13.5, cursor: 'pointer' }}>
              {T('Giữ sự kiện', 'Keep the event')}
            </button>
          </div>
        </div>
      )}
    </>,
  );
}

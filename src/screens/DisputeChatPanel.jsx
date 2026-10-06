import { useEffect, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { ink, rule, fieldGlass, cardGlass, alert } from '../theme.js';
import { supabase } from '../lib/supabase.js';
import { buildRefundDisputeExport, saveBlob } from '../lib/disputeExport.js';

const ATTACH_MIME = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];
const ATTACH_MAX = 20 * 1024 * 1024; // bucket file_size_limit (migration 131)
const AUTO_BODY = /^Sent a (photo|file)$/;

function imageSize(file) {
  return new Promise((resolve) => {
    if (!file.type.startsWith('image/')) return resolve({});
    const url = URL.createObjectURL(file);
    const im = new Image();
    im.onload = () => { URL.revokeObjectURL(url); resolve({ w: im.naturalWidth, h: im.naturalHeight }); };
    im.onerror = () => { URL.revokeObjectURL(url); resolve({}); };
    im.src = url;
  });
}

// "closes in ~Nh" for the payment not-found window (dispute_threads.expires_at).
export function windowLabel(expiresAt, T) {
  if (!expiresAt) return null;
  const ms = new Date(expiresAt).getTime() - Date.now();
  if (!(ms > 0)) return T('Sắp đóng', 'Closing soon');
  const h = Math.ceil(ms / 3600000);
  return h >= 24 ? T(`Đóng sau ~${Math.ceil(h / 24)} ngày`, `Closes in ~${Math.ceil(h / 24)}d`) : T(`Đóng sau ~${h} giờ`, `Closes in ~${h}h`);
}

// A static (non-ticking, computed at render time), read-only countdown —
// never a delete button, unlike the ordinary chat (Chat.jsx) or the
// notification inbox (Notifications.jsx): dispute_messages must survive
// until purge_resolved_dispute_threads() actually removes it, per
// 05-notify-retention.md's 72h retention requirement. Returns null for an
// open thread (resolvedAt/purgeAfter both null) or one whose purge_after
// has already passed (about to be swept, or the cron just hasn't run yet
// — either way, nothing useful to say).
function retentionLabel(thread, T) {
  if (!thread?.resolvedAt || !thread.purgeAfter) return null;
  const msLeft = new Date(thread.purgeAfter).getTime() - Date.now();
  if (msLeft <= 0) return null;
  const hoursLeft = msLeft / 3600000;
  if (hoursLeft >= 1) {
    const n = Math.round(hoursLeft);
    return T(`Sẽ tự xoá trong ~${n} giờ`, `Auto-deletes in ~${n}h`);
  }
  const n = Math.max(1, Math.round(msLeft / 60000));
  return T(`Sẽ tự xoá trong ~${n} phút`, `Auto-deletes in ~${n}m`);
}

// The temporary chat for a dispute — shared between the guest's side
// (PaymentDetails.jsx, while payment_state = 'disputed') and the
// organizer's side (Verifications.jsx, in the "escalated to banbe" list).
// Deliberately its own small table (dispute_messages), not the ordinary
// booking thread: this conversation is purged once resolve_dispute() closes
// it out (see purge_resolved_dispute_threads, 72h grace window), where the
// ordinary thread is permanent.
//
// Two kinds, one panel (migration 129): a PAYMENT dispute (the host
// escalated to banbe, keyed by booking) and a REFUND dispute (the goer
// reported not receiving the money, keyed by refund claim — settled between
// the two of them, no banbe ruling). Same table, same purge machinery, so
// only the selector, the RPCs and the explanatory copy differ. Exactly one of
// bookingId / refundClaimId is passed.
export default function DisputeChatPanel({ bookingId, refundClaimId }) {
  const { state, T, loadDisputeChat, loadRefundDisputeChat, disputeChatDraftType, sendDisputeMessage, sendRefundDisputeMessage, clearChatHighlight, loadDisputeChats } = useBanBe();
  const s = state;
  const listRef = useRef(null);
  const messageRefs = useRef({}); // message id -> DOM node, for scrollIntoView
  const [highlightedId, setHighlightedId] = useState(null);
  const isRefund = !!refundClaimId;
  const lang = s.lang;

  // Dispute header facts the shared chat state doesn't carry: for a REFUND the
  // verified get_refund_dispute_thread (viewer role, closed state, thread id);
  // for a PAYMENT the thread id + expires_at (migration 149 2-day window).
  const [meta, setMeta] = useState(null);
  const [urls, setUrls] = useState({}); // attachment path -> { url, at }
  const [busy, setBusy] = useState('');  // '' | 'attach' | 'export' | 'close' | 'delete'
  const [flash, setFlash] = useState(null); // { kind: 'ok' | 'err', text }
  const [confirm, setConfirm] = useState(null); // null | 'close' | 'delete'
  const [deleted, setDeleted] = useState(false);
  const fileRef = useRef(null);

  const loadMeta = async () => {
    if (isRefund) {
      const { data } = await supabase.rpc('get_refund_dispute_thread', { p_claim_id: refundClaimId });
      if (data?.reason === 'deleted_by_you') setDeleted(true);
      setMeta(data || null);
    } else {
      const { data } = await supabase.from('dispute_threads').select('id, expires_at, resolved_at').eq('booking_id', bookingId).maybeSingle();
      setMeta(data ? { found: true, dispute_thread_id: data.id, expires_at: data.expires_at, resolved_at: data.resolved_at } : null);
    }
  };
  useEffect(() => {
    setMeta(null); setDeleted(false); setConfirm(null); setFlash(null);
    loadMeta();
    const id = setInterval(loadMeta, 5000);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refundClaimId, bookingId]);

  // No realtime subscription exists anywhere in this app (no
  // supabase.channel()/postgres_changes usage, and dispute_messages was
  // never added to the supabase_realtime publication) — without this poll,
  // the party who didn't just send a message never sees a new one until
  // they leave and reopen this panel. 4s, matching PaymentDetails.jsx's own
  // 6s poll for the same "nothing pushes to this client" reason.
  const reload = isRefund ? loadRefundDisputeChat : loadDisputeChat;
  const chatKey = isRefund ? refundClaimId : bookingId;
  useEffect(() => {
    reload(chatKey);
    const id = setInterval(() => reload(chatKey), 4000);
    return () => clearInterval(id);
  }, [chatKey, reload]);

  // Same staleness guard the payment-only version had, expressed once: state
  // records WHICH dispute it currently holds, and the panel only renders that
  // one. A 4s poll for a different thread landing late therefore can't paint
  // the wrong conversation here.
  const isActiveChat = isRefund ? s.disputeChatRefundClaimId === refundClaimId : s.disputeChatBookingId === bookingId;
  const messages = isActiveChat ? s.disputeChatMessages : [];
  const thread = isActiveChat ? s.disputeChatThread : null;
  const retention = retentionLabel(thread, T);
  // Once a dispute is concluded the chat is a read-only record until the
  // purge sweep removes it (send_refund_dispute_message/send_dispute_message
  // both refuse once resolved) — so the composer is hidden rather than left
  // there to fail on submit.
  const readOnly = !!thread?.resolvedAt;
  const send = isRefund ? sendRefundDisputeMessage : sendDisputeMessage;

  // Sign attachment paths (private bucket). An already-signed path is kept
  // until ~8 min old so the 4s poll doesn't churn <img src>.
  useEffect(() => {
    const now = Date.now();
    const wanted = [...new Set(messages.map(m => m.attachment_path).filter(Boolean))]
      .filter(p => !urls[p] || now - urls[p].at > 480000);
    if (!wanted.length) return;
    supabase.storage.from('dispute-attachments').createSignedUrls(wanted, 600).then(({ data }) => {
      if (!data) return;
      setUrls(prev => {
        const next = { ...prev };
        for (const r of data) if (r.path && r.signedUrl && !r.error) next[r.path] = { url: r.signedUrl, at: Date.now() };
        return next;
      });
    });
  }, [messages]); // eslint-disable-line react-hooks/exhaustive-deps

  const claimClosed = !!(meta?.dispute_closed_at || meta?.resolved_at);
  const threadId = meta?.dispute_thread_id;
  const isGuest = meta?.viewer_role === 'guest';

  const onPickFile = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file || !threadId) return;
    if (!ATTACH_MIME.includes(file.type)) return setFlash({ kind: 'err', text: T('Chỉ gửi được ảnh JPG/PNG/WebP hoặc PDF.', 'Only JPG/PNG/WebP photos or PDFs can be sent.') });
    if (file.size > ATTACH_MAX) return setFlash({ kind: 'err', text: T('Tệp quá lớn (tối đa 20 MB).', 'File too large (20 MB max).') });
    setBusy('attach'); setFlash(null);
    const ext = file.type === 'application/pdf' ? 'pdf' : file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg';
    const path = `${threadId}/${crypto.randomUUID()}.${ext}`;
    const up = await supabase.storage.from('dispute-attachments').upload(path, file, { contentType: file.type, upsert: false });
    if (up.error) { setBusy(''); return setFlash({ kind: 'err', text: T('Không tải tệp lên được.', "Couldn't upload the file.") }); }
    const { w, h } = await imageSize(file);
    const { data, error } = await supabase.rpc('send_refund_dispute_attachment', {
      p_refund_claim_id: refundClaimId, p_body: '', p_attachment_path: path, p_attachment_type: file.type,
      p_attachment_width: w ?? null, p_attachment_height: h ?? null,
    });
    if (error || data?.success === false) {
      await supabase.storage.from('dispute-attachments').remove([path]); // don't orphan the file
      setFlash({ kind: 'err', text: data?.error === 'DISPUTE_RESOLVED' ? T('Tranh chấp đã kết thúc.', 'This dispute has ended.') : T('Chưa gửi được tệp.', "Couldn't send the file.") });
    } else {
      await reload(chatKey);
    }
    setBusy('');
  };

  const doExport = async () => {
    setBusy('export'); setFlash(null);
    try {
      const { blob, fileName, attachmentCount } = await buildRefundDisputeExport(refundClaimId, lang);
      saveBlob(blob, fileName);
      setFlash({ kind: 'ok', text: T(`Đã tải bản ghi (${attachmentCount} tệp đính kèm).`, `Transcript downloaded (${attachmentCount} attachment${attachmentCount === 1 ? '' : 's'}).`) });
      setBusy('');
      return true;
    } catch (err) {
      console.warn('dispute export failed:', err);
      setFlash({ kind: 'err', text: T('Không xuất được bản ghi đầy đủ — chưa có gì bị xoá. Thử lại nhé.', "Couldn't build the full transcript — nothing was deleted. Please try again.") });
      setBusy('');
      return false;
    }
  };

  const doClose = async () => {
    setBusy('close'); setFlash(null);
    const { data, error } = await supabase.rpc('close_refund_dispute', { p_claim_id: refundClaimId, p_note: '' });
    setBusy('');
    if (error || data?.success === false) return setFlash({ kind: 'err', text: T('Chưa đóng được tranh chấp.', "Couldn't close the dispute.") });
    setConfirm(null);
    await Promise.all([loadMeta(), reload(chatKey), loadDisputeChats?.()]);
  };

  const doDelete = async () => {
    setBusy('delete'); setFlash(null);
    const { data, error } = await supabase.rpc('delete_my_refund_dispute_copy', { p_claim_id: refundClaimId });
    setBusy('');
    if (error || data?.success === false) return setFlash({ kind: 'err', text: T('Chưa xoá được bản của bạn.', "Couldn't delete your copy.") });
    setConfirm(null); setDeleted(true);
    await loadDisputeChats?.();
  };

  // Reached by tapping a 'dispute_message' toast/notification
  // (openNotification, BanBeContext.jsx) — scrolls to and briefly highlights
  // the specific message named by `chatHighlight.messageId`, or just the
  // bottom of the thread if that's null (an older notification row from
  // before migration 050 added message_id). Only runs once per highlight —
  // clearChatHighlight() consumes it so the 4s poll's re-renders don't
  // keep re-triggering the scroll/flash.
  useEffect(() => {
    const highlight = s.chatHighlight;
    if (!highlight) return;
    if (isRefund ? highlight.refundClaimId !== refundClaimId : highlight.bookingId !== bookingId) return;
    const { messageId } = highlight;
    if (messageId) {
      const node = messageRefs.current[messageId];
      if (!node) return; // messages haven't loaded yet — wait for the next render
      node.scrollIntoView({ behavior: 'smooth', block: 'center' });
      setHighlightedId(messageId);
      setTimeout(() => setHighlightedId(id => (id === messageId ? null : id)), 1600);
    } else if (messages.length > 0 && listRef.current) {
      listRef.current.scrollTop = listRef.current.scrollHeight;
    } else if (messages.length === 0) {
      return; // nothing to scroll to yet — wait for the next render
    }
    clearChatHighlight();
  }, [s.chatHighlight, bookingId, refundClaimId, isRefund, messages, clearChatHighlight]);

  if (deleted) {
    return (
      <div style={{ ...fieldGlass({ marginTop: 10, padding: '12px 14px' }) }} data-testid="dispute-chat-deleted">
        <span style={{ fontSize: 12, color: ink, opacity: 0.7 }}>
          {T('Bạn đã xoá bản sao tranh chấp này. Phía bên kia vẫn giữ bản ghi chung cho đến khi hết hạn.', 'You deleted your copy of this dispute. The other side keeps the shared record until it expires.')}
        </span>
      </div>
    );
  }
  const windowText = !isRefund && !claimClosed ? windowLabel(meta?.expires_at, T) : null;

  return (
    <div style={{ ...fieldGlass({ marginTop: 10, padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 10 }) }} data-testid="dispute-chat-panel">
      <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>
        {T('Trao đổi trực tiếp về tranh chấp này', 'Direct chat about this dispute')}
      </span>
      {isRefund && meta?.found && (
        claimClosed ? (
          <span style={{ fontSize: 11.5, fontWeight: 700, color: ink, opacity: 0.7 }} data-testid="dispute-chat-completed">
            {T('Tranh chấp đã hoàn tất', 'Dispute completed')}
            {meta.dispute_closed_by_role ? ` ▪︎ ${meta.dispute_closed_by_role === meta.viewer_role ? T('bạn đã đóng', 'closed by you') : T('bên kia đã đóng', 'closed by the other side')}` : ''}
          </span>
        ) : (
          <span style={{ fontSize: 11.5, fontWeight: 700, color: alert }} data-testid="dispute-chat-in-progress">
            {T('Đang tranh chấp', 'Dispute in progress')}
          </span>
        )
      )}
      {windowText && (
        <span style={{ fontSize: 11, fontWeight: 700, color: alert }} data-testid="dispute-chat-window">{windowText}</span>
      )}
      <p style={{ fontSize: 11, lineHeight: 1.45, color: ink, opacity: 0.7, margin: 0 }}>
        {/* The two kinds have genuinely different endings — a payment
            dispute is closed by banbe and emailed a transcript, a refund
            dispute is just settled between the two parties — so the promise
            made to the reader has to differ too. */}
        {isRefund
          ? T('Cuộc trò chuyện này là tạm thời: khi tranh chấp kết thúc, nó sẽ tự xoá sau 7 ngày.',
               'This conversation is temporary: once the dispute is settled it deletes itself after 7 days.')
          : T('Cuộc trò chuyện này là tạm thời: sẽ bị xoá sau khi banbe đưa ra quyết định, và bản ghi được gửi qua email cho cả hai bên.',
               'This conversation is temporary: it is deleted once banbe rules on the dispute, and a copy is emailed to both of you.')}
      </p>
      {readOnly && (
        <span style={{ fontSize: 10.5, fontWeight: 600, color: ink, opacity: 0.55 }} data-testid="dispute-chat-closed">
          {T('Tranh chấp đã kết thúc — chỉ còn để đọc.', 'This dispute has ended — read only.')}
        </span>
      )}
      {retention && (
        <span style={{ fontSize: 10.5, fontWeight: 600, color: ink, opacity: 0.55 }} data-testid="dispute-chat-retention">
          {retention}
        </span>
      )}

      <div ref={listRef} style={{ display: 'flex', flexDirection: 'column', gap: 6, maxHeight: 220, overflowY: 'auto' }}>
        {s.disputeChatLoading && messages.length === 0 && (
          <span style={{ fontSize: 11.5, color: ink, opacity: 0.6 }}>{T('Đang tải…', 'Loading…')}</span>
        )}
        {!s.disputeChatLoading && messages.length === 0 && !s.disputeChatError && (
          <span style={{ fontSize: 11.5, color: ink, opacity: 0.6 }} data-testid="dispute-chat-empty">
            {T('Chưa có tin nhắn nào.', 'No messages yet.')}
          </span>
        )}
        {messages.map(m => (
          <div
            key={m.id}
            ref={(node) => { if (node) messageRefs.current[m.id] = node; else delete messageRefs.current[m.id]; }}
            style={{
              ...cardGlass({ padding: '8px 10px' }),
              transition: 'background-color 0.3s ease, box-shadow 0.3s ease',
              boxShadow: highlightedId === m.id ? `0 0 0 1.5px ${alert}` : undefined,
            }}
            data-testid="dispute-chat-message"
            data-highlighted={highlightedId === m.id || undefined}
          >
            <div style={{ fontSize: 10, color: ink, opacity: 0.55 }}>
              {m.sender_role === 'organizer' ? T('Người tổ chức', 'Organizer')
                : m.sender_role === 'guest' ? T('Khách', 'Guest')
                : m.sender_role === 'admin' ? T('banbe', 'banbe') : T('Hệ thống', 'System')}
              {' ▪︎ '}{new Date(m.created_at).toLocaleString()}
            </div>
            {m.attachment_path && (
              (() => {
                const u = urls[m.attachment_path]?.url;
                const isImg = m.attachment_type?.startsWith('image/');
                const r = m.attachment_width && m.attachment_height ? m.attachment_width / m.attachment_height : 1;
                const bw = Math.round(Math.min(200, 200 * Math.min(r, 1.2)));
                return isImg ? (
                  u ? (
                    <img
                      src={u} alt="" data-testid="dispute-chat-attachment"
                      onClick={() => window.open(u, '_blank', 'noopener')}
                      style={{ display: 'block', marginTop: 4, width: bw, aspectRatio: String(r), maxHeight: 240, objectFit: 'cover', borderRadius: 10, border: `1px solid ${rule}`, cursor: 'pointer' }}
                    />
                  ) : (
                    <div data-testid="dispute-chat-attachment-pending" style={{ marginTop: 4, fontSize: 11.5, color: ink, opacity: 0.6 }}>{T('Đang tải tệp…', 'Loading attachment…')}</div>
                  )
                ) : (
                  <a href={u || undefined} target="_blank" rel="noreferrer" data-testid="dispute-chat-attachment" style={{ display: 'inline-block', marginTop: 4, fontSize: 12.5, color: ink }}>
                    📎 {T('Tệp PDF', 'PDF file')}
                  </a>
                );
              })()
            )}
            {!(m.attachment_path && AUTO_BODY.test(m.body || '')) && (
              <div style={{ fontSize: 13, color: ink, marginTop: 2 }}>{m.body}</div>
            )}
          </div>
        ))}
      </div>

      {!readOnly && (
        <div style={{ display: 'flex', gap: 8 }}>
          {isRefund && (
            <>
              <input ref={fileRef} type="file" accept={ATTACH_MIME.join(',')} style={{ display: 'none' }} onChange={onPickFile} data-testid="dispute-chat-file-input" />
              <div
                onClick={() => busy === '' && threadId && fileRef.current?.click()}
                data-testid="dispute-chat-attach"
                title={T('Đính kèm ảnh hoặc PDF', 'Attach a photo or PDF')}
                style={{ flex: 'none', width: 40, display: 'flex', alignItems: 'center', justifyContent: 'center', borderRadius: 12, ...fieldGlass({}), fontSize: 17, color: ink, cursor: threadId ? 'pointer' : 'default', opacity: busy === 'attach' || !threadId ? 0.5 : 1 }}
              >
                {busy === 'attach' ? '…' : '📎'}
              </div>
            </>
          )}
          <input
            value={s.disputeChatDraft} onChange={disputeChatDraftType}
            placeholder={T('Nhắn gì đó…', 'Say something…')}
            data-testid="dispute-chat-input"
            onKeyDown={(e) => { if (e.key === 'Enter' && s.disputeChatDraft.trim()) send(chatKey); }}
            style={{ ...fieldGlass({ padding: '10px 12px', border: 'none', flex: 1 }), fontSize: 13, color: ink, outline: 'none', fontFamily: 'inherit' }}
          />
          <div
            onClick={() => s.disputeChatDraft.trim() && send(chatKey)}
            data-testid="dispute-chat-send"
            style={{
              flex: 'none', display: 'flex', alignItems: 'center', padding: '0 16px', borderRadius: 12,
              fontSize: 13, fontWeight: 600, cursor: s.disputeChatDraft.trim() ? 'pointer' : 'default',
              background: s.disputeChatDraft.trim() ? ink : 'rgba(27,25,22,0.16)', color: 'var(--bb-bg)',
              border: `1px solid ${rule}`,
            }}
          >
            {T('Gửi', 'Send')}
          </div>
        </div>
      )}
      {flash && (
        <p style={{ fontSize: 11.5, color: flash.kind === 'err' ? alert : ink, margin: 0 }} data-testid={flash.kind === 'err' ? 'dispute-chat-flash-error' : 'dispute-chat-flash'}>{flash.text}</p>
      )}
      {isRefund && meta?.found && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }} data-testid="dispute-chat-actions">
          {confirm === null && (
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              <div onClick={() => busy === '' && doExport()} data-testid="dispute-chat-export" style={{ ...fieldGlass({ padding: '8px 12px', borderRadius: 999 }), fontSize: 12, fontWeight: 600, color: ink, cursor: 'pointer', opacity: busy === 'export' ? 0.5 : 1 }}>
                {busy === 'export' ? T('Đang tạo bản ghi…', 'Building transcript…') : T('Tải bản ghi (ZIP)', 'Download transcript (ZIP)')}
              </div>
              {!claimClosed && (
                <div onClick={() => setConfirm('close')} data-testid="dispute-chat-close" style={{ ...fieldGlass({ padding: '8px 12px', borderRadius: 999 }), fontSize: 12, fontWeight: 600, color: ink, cursor: 'pointer' }}>
                  {T('Đóng tranh chấp', 'Close dispute')}
                </div>
              )}
              {isGuest && (
                <div onClick={() => setConfirm('delete')} data-testid="dispute-chat-delete-copy" style={{ ...fieldGlass({ padding: '8px 12px', borderRadius: 999 }), fontSize: 12, fontWeight: 600, color: alert, cursor: 'pointer' }}>
                  {T('Đóng và xoá bản của tôi', 'Close and delete my copy')}
                </div>
              )}
            </div>
          )}
          {confirm && (
            <div style={{ ...cardGlass({ padding: '10px 12px' }), display: 'flex', flexDirection: 'column', gap: 8 }} data-testid="dispute-chat-confirm">
              <span style={{ fontSize: 12, color: ink, lineHeight: 1.45 }}>
                {confirm === 'close'
                  ? T('Đóng tranh chấp không chuyển tiền và không đổi trạng thái khoản hoàn. Đoạn chat chỉ còn để đọc và tự xoá sau 7 ngày. Bạn nên tải bản ghi trước.',
                       'Closing does not move any money or change the refund status. The chat becomes read-only and deletes itself after 7 days. Download the transcript first.')
                  : T('Bản của bạn (tin nhắn và tệp) sẽ bị ẩn khỏi bạn vĩnh viễn; tranh chấp được đóng nếu còn mở. Người tổ chức vẫn giữ bản ghi chung. Hãy tải bản ghi trước khi xoá.',
                       'Your copy (messages and files) will be hidden from you permanently; the dispute is closed if still open. The organizer keeps the shared record. Download the transcript before deleting.')}
              </span>
              <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                <div onClick={() => busy === '' && doExport()} data-testid="dispute-chat-confirm-export" style={{ ...fieldGlass({ padding: '8px 12px', borderRadius: 999 }), fontSize: 12, fontWeight: 600, color: ink, cursor: 'pointer' }}>
                  {busy === 'export' ? T('Đang tạo…', 'Building…') : T('Tải bản ghi', 'Download transcript')}
                </div>
                <div onClick={() => busy === '' && (confirm === 'close' ? doClose() : doDelete())} data-testid="dispute-chat-confirm-go" style={{ padding: '8px 12px', borderRadius: 999, background: alert, color: 'var(--bb-on-alert)', fontSize: 12, fontWeight: 600, cursor: 'pointer', opacity: busy === 'close' || busy === 'delete' ? 0.5 : 1 }}>
                  {confirm === 'close' ? T('Đóng tranh chấp', 'Close dispute') : T('Xoá bản của tôi', 'Delete my copy')}
                </div>
                <div onClick={() => setConfirm(null)} data-testid="dispute-chat-confirm-cancel" style={{ padding: '8px 12px', fontSize: 12, color: ink, cursor: 'pointer' }}>
                  {T('Huỷ', 'Cancel')}
                </div>
              </div>
            </div>
          )}
        </div>
      )}
      {s.disputeChatError && (
        <p style={{ fontSize: 11.5, color: alert, margin: 0 }} data-testid="dispute-chat-error">
          {s.disputeChatError}
        </p>
      )}
    </div>
  );
}

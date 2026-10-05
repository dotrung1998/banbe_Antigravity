// ---- account gate (web parity) ---- host promotional messages (migration 123)
// Web port of iOS SecurityView's promo-consent switch and HostPromoSheet.
// Consent is its own server-stored choice (default OFF), never tied to
// sign-in. A host is only ever handed ONE consenting recipient at a time and
// the server rechecks permission/consent/audience before revealing a phone.
// The web can't open a Messages composer, so the host gets an `sms:` link and
// sends (or cancels) the text themselves; banbe never sends.

import { useEffect, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { supabase } from '../lib/supabase.js';
import { getHostPromoConsent, setHostPromoConsent } from '../lib/accountGate.js';
import { paper, ink, display, fieldGlass, inkButton, alert } from '../theme.js';

const small = { fontSize: 11.5, lineHeight: 1.55, color: ink, opacity: 0.7 };

export function PromoConsentSection() {
  const { T } = useGoc();
  const [on, setOn] = useState(null); // null = loading/unknown
  const [busy, setBusy] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    let live = true;
    getHostPromoConsent().then(v => { if (live) setOn(v); });
    return () => { live = false; };
  }, []);

  const save = async (enabled) => {
    setBusy(true); setError('');
    const v = await setHostPromoConsent(enabled);
    setBusy(false); setConfirming(false);
    if (v == null) setError(T('Chưa lưu được lựa chọn. Thử lại sau.', "Couldn't save your choice. Please try again."));
    else setOn(v);
  };
  const enabled = on === true;
  const disabled = busy || on == null;

  return (
    <div data-testid="promo-consent" style={{ marginTop: 28 }}>
      <div style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Tin nhắn quảng bá từ host', 'Host promotional messages')}</div>
      <div
        onClick={disabled ? undefined : () => (enabled ? save(false) : setConfirming(true))}
        role="switch" aria-checked={enabled} data-testid="promo-consent-toggle"
        style={{ ...fieldGlass({ marginTop: 10, padding: '15px 18px', border: 'none' }), display: 'flex', alignItems: 'center', gap: 12, cursor: disabled ? 'default' : 'pointer', opacity: disabled ? 0.6 : 1 }}
      >
        <div style={{ flex: 1 }}>
          <div style={display(16, { lineHeight: 1.3 })}>{T('Cho phép host nhắn tin quảng bá', 'Allow hosts to text me promotions')}</div>
          <div style={{ ...small, marginTop: 3 }}>
            {T('Mặc định tắt. Chỉ các host mà bạn đã đặt chỗ, theo dõi hoặc lưu sự kiện mới được soạn tin quảng bá ngắn cho bạn qua SMS, và chỉ khi bạn bật mục này.',
              "Off by default. Only hosts you've booked with, follow or saved an event from can compose a short promo text to you, and only while this is on.")}
          </div>
        </div>
        <span style={{ flex: 'none', width: 44, height: 26, borderRadius: 13, background: enabled ? ink : 'rgba(27,25,22,0.18)', position: 'relative', transition: 'background .15s' }}>
          <span style={{ position: 'absolute', top: 3, left: enabled ? 21 : 3, width: 20, height: 20, borderRadius: 10, background: paper, transition: 'left .15s' }} />
        </span>
      </div>
      <p style={{ ...small, margin: '10px 0 0' }}>
        {T('Host tự soạn và tự bấm gửi từng tin trong ứng dụng nhắn tin của chính host; banbe không gửi hàng loạt hay tự động, và không đảm bảo tin được nhận. Tắt mục này sẽ chặn các tin quảng bá do banbe hỗ trợ trong tương lai, nhưng không ảnh hưởng tới tin nhắn mà host gửi độc lập sau khi đã có số của bạn.',
          "Hosts write and send each text themselves from the host's own messaging app. Banbe never sends in bulk or automatically and can't guarantee delivery. Turning this off blocks future banbe-assisted promos, but doesn't affect messages a host sends independently after already having your number.")}
      </p>
      {error && <p style={{ fontSize: 12, color: alert, margin: '8px 0 0' }}>{error}</p>}
      {confirming && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 1500, background: 'rgba(0,0,0,0.4)', display: 'flex', alignItems: 'flex-end', justifyContent: 'center' }} onClick={() => setConfirming(false)}>
          <div onClick={(e) => e.stopPropagation()} data-testid="promo-consent-confirm" style={{ background: paper, width: '100%', maxWidth: 480, borderRadius: '22px 22px 0 0', padding: '24px 26px 34px', boxSizing: 'border-box' }}>
            <h3 style={display(20, { margin: 0 })}>{T('Cho phép tin nhắn quảng bá từ host?', 'Allow promotional texts from hosts?')}</h3>
            <p style={{ fontSize: 13, lineHeight: 1.55, color: ink, margin: '10px 0 0' }}>
              {T('Host mà bạn đã tương tác có thể soạn tin quảng bá sự kiện trong ứng dụng nhắn tin của host, gửi tới số điện thoại đã xác minh của bạn. Host tự bấm gửi; banbe không gửi hộ. Bạn có thể tắt bất cứ lúc nào.',
                "Hosts you've interacted with may compose an event promo text in the host's own messaging app, addressed to your verified phone number. The host sends it themselves; banbe doesn't send for them. You can turn this off any time.")}
            </p>
            <div onClick={busy ? undefined : () => save(true)} data-testid="promo-consent-agree" style={{ ...inkButton({ marginTop: 18, borderRadius: 18, padding: 14, fontSize: 14 }), cursor: 'pointer' }}>{T('Đồng ý', 'I agree')}</div>
            <div onClick={() => setConfirming(false)} style={{ textAlign: 'center', fontSize: 13, marginTop: 14, cursor: 'pointer', color: ink }}>{T('Huỷ', 'Cancel')}</div>
          </div>
        </div>
      )}
    </div>
  );
}

const promoErrorText = (code, T) => {
  switch (code) {
    case 'NOT_AUTHORIZED': return T('Bạn không có quyền gửi tin quảng bá cho sự kiện này.', "You aren't allowed to send promos for this event.");
    case 'RATE_LIMITED': return T('Bạn đã đạt giới hạn tin quảng bá hôm nay. Thử lại sau.', "You've reached today's promo limit. Try again later.");
    case 'NOT_ELIGIBLE': case 'ALREADY_PROMPTED': return T('Người này không đủ điều kiện nhận tin.', "This person isn't eligible.");
    case 'GATE_REQUIRED': return T('Hãy hoàn tất xác nhận tài khoản trước.', 'Finish confirming your account first.');
    default: return T('Chưa thực hiện được. Thử lại sau.', "That didn't work. Please try again later.");
  }
};

// Short text in the RECIPIENT's language, with the host's page link.
function promoBody(c) {
  const link = `https://banbe.app/org/${c.organizer_id}`;
  const host = c.organizer_name || 'banbe';
  return c.locale === 'en'
    ? `Hi ${c.display_name}! ${host} has an event: “${c.event_name}”. Details: ${link}`
    : `Chào ${c.display_name}! ${host} có sự kiện “${c.event_name}”. Xem chi tiết: ${link}`;
}

export function HostPromoSheet({ eventKey, onClose }) {
  const { T } = useGoc();
  // phase: loading | recipient | none | failed | composing | finished
  const [phase, setPhase] = useState('loading');
  const [recipient, setRecipient] = useState(null);
  const [compose, setCompose] = useState(null);
  const [text, setText] = useState('');
  const [retry, setRetry] = useState(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');

  const loadNext = async () => {
    setNotice(''); setPhase('loading'); setRetry(null);
    const { data, error } = await supabase.rpc('next_promo_recipient', { p_event_id: eventKey });
    if (error || !data) { setText(promoErrorText('other', T)); setPhase('failed'); return; }
    if (data.success !== true) { setText(promoErrorText(data.error, T)); setPhase('failed'); return; }
    setRecipient(data.recipient || null);
    setPhase(data.recipient ? 'recipient' : 'none');
  };
  useEffect(() => { loadNext(); /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [eventKey]);

  const prepare = async (r) => {
    setNotice(''); setBusy(true);
    const { data, error } = await supabase.rpc('begin_promo_compose', { p_event_id: eventKey, p_recipient_id: r.id });
    setBusy(false);
    if (error || !data || data.success !== true || !data.log_id || !data.phone) {
      const code = data?.error;
      if (code === 'NOT_ELIGIBLE' || code === 'ALREADY_PROMPTED') {
        setNotice(T('Người này không còn đủ điều kiện nhận tin. Chuyển sang người tiếp theo.', 'This person is no longer eligible. Moving on.'));
        await loadNext();
      } else setNotice(promoErrorText(code, T));
      return;
    }
    setCompose({ ...data, recipient_id: r.id });
    setPhase('composing');
    // Hand the draft to the host's own messaging app; the host sends or cancels.
    window.location.href = `sms:${data.phone}?&body=${encodeURIComponent(promoBody(data))}`;
  };

  const finish = async (outcome) => {
    if (compose) await supabase.rpc('finish_promo_compose', { p_log_id: compose.log_id, p_result: outcome }).catch(() => {});
    setRetry(outcome === 'sent' ? null : { id: compose.recipient_id, display_name: compose.display_name });
    setText(outcome === 'sent'
      ? T('Bạn đã xác nhận đã gửi tin. banbe không xác nhận được người nhận đã nhận.', "You said you sent the text. banbe can't confirm the recipient received it.")
      : outcome === 'cancelled' ? T('Bạn đã huỷ — không có tin nào được gửi.', 'You cancelled — nothing was sent.')
        : T('Không gửi được tin này.', "This text couldn't be sent."));
    setCompose(null); setPhase('finished');
  };

  const btn = (label, onClick, enabled = true, testid) => (
    <div onClick={enabled ? onClick : undefined} data-testid={testid} style={{ ...inkButton({ borderRadius: 18, padding: 13, fontSize: 14 }), opacity: enabled ? 1 : 0.45, cursor: enabled ? 'pointer' : 'default' }}>{label}</div>
  );

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 1500, background: 'rgba(0,0,0,0.4)', display: 'flex', alignItems: 'flex-end', justifyContent: 'center' }} onClick={onClose}>
      <div onClick={(e) => e.stopPropagation()} data-testid="host-promo-sheet" style={{ background: paper, width: '100%', maxWidth: 480, maxHeight: '88%', overflowY: 'auto', borderRadius: '22px 22px 0 0', padding: '24px 26px 34px', boxSizing: 'border-box', color: ink, display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <h3 style={display(22, { margin: 0 })}>{T('Nhắn tin quảng bá', 'Text a promo')}</h3>
          <span onClick={onClose} style={{ fontSize: 13, cursor: 'pointer' }}>{T('Đóng', 'Close')}</span>
        </div>
        <p style={{ ...small, margin: 0, fontSize: 12 }}>
          {T('Chỉ những người đã bật “Tin nhắn quảng bá từ host” và từng đặt chỗ, theo dõi hoặc lưu sự kiện của bạn. Tin mở trong ứng dụng nhắn tin của bạn — bạn tự bấm gửi hoặc huỷ. banbe không gửi hộ và không xác nhận tin đã được nhận.',
            'Only people who turned on “Host promotional messages” and have booked, followed or saved one of your events. The text opens in your messaging app — you send or cancel it yourself. banbe doesn\'t send for you and can\'t confirm delivery.')}
        </p>
        {phase === 'loading' && <p style={{ fontSize: 13, textAlign: 'center' }}>{T('Đang tải…', 'Loading…')}</p>}
        {phase === 'recipient' && recipient && (
          <div style={fieldGlass({ padding: 16, border: 'none', display: 'flex', flexDirection: 'column', gap: 12 })}>
            <div style={display(20)}>{recipient.display_name}</div>
            <div style={{ ...small, fontSize: 12 }}>{T('Đã đồng ý nhận tin quảng bá.', 'Has opted in to promotional texts.')}</div>
            {btn(busy ? T('Đang chuẩn bị…', 'Preparing…') : T('Mở ứng dụng nhắn tin', 'Open messaging app'), () => prepare(recipient), !busy, 'promo-open')}
          </div>
        )}
        {phase === 'none' && <p style={{ fontSize: 13, margin: 0 }}>{T('Hiện chưa có ai khác đủ điều kiện nhận tin quảng bá cho sự kiện này.', 'No one else is eligible for a promo about this event right now.')}</p>}
        {phase === 'failed' && <p style={{ fontSize: 13, color: alert, margin: 0 }}>{text}</p>}
        {phase === 'composing' && compose && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <p style={{ fontSize: 13, lineHeight: 1.5, margin: 0 }}>{T(`Tin cho ${compose.display_name} đã mở trong ứng dụng nhắn tin. Sau khi bạn gửi hoặc huỷ, hãy cho banbe biết:`, `The text for ${compose.display_name} was opened in your messaging app. After you send or cancel it, tell banbe:`)}</p>
            <a href={`sms:${compose.phone}?&body=${encodeURIComponent(promoBody(compose))}`} style={{ fontSize: 12.5, color: ink, textDecoration: 'underline' }}>{T('Mở lại tin nhắn', 'Reopen the text')}</a>
            {btn(T('Tôi đã gửi', 'I sent it'), () => finish('sent'), true, 'promo-sent')}
            <div onClick={() => finish('cancelled')} style={{ textAlign: 'center', fontSize: 13, cursor: 'pointer' }}>{T('Tôi đã huỷ', 'I cancelled')}</div>
          </div>
        )}
        {phase === 'finished' && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <p style={{ fontSize: 13, margin: 0 }}>{text}</p>
            {retry && btn(T(`Thử lại với ${retry.display_name}`, `Try again with ${retry.display_name}`), () => prepare(retry), !busy, 'promo-retry')}
            {btn(T('Người tiếp theo', 'Next recipient'), loadNext, true, 'promo-next')}
          </div>
        )}
        {notice && <p style={{ fontSize: 12.5, color: alert, margin: 0 }}>{notice}</p>}
      </div>
    </div>
  );
}

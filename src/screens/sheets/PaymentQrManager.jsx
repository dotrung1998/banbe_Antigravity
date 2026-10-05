import { useEffect, useRef, useState, useCallback } from 'react';
import { useGoc } from '../../state/GocContext.jsx';
import { supabase } from '../../lib/supabase.js';
import { ink, display, fieldGlass, cardGlass, inkButton, alert } from '../../theme.js';
import {
  prepareQrUpload, decodeFromImage, classifyQr, qrKindLabel, isMobileBrowser,
} from '../../lib/paymentQr.js';

// Downloads a QR image from a private bucket under the viewer's own RLS.
function useQrImage(path) {
  const [url, setUrl] = useState(null);
  const [blobImg, setBlobImg] = useState(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let alive = true; let obj = null;
    setUrl(null); setFailed(false); setBlobImg(null);
    if (!path) return undefined;
    supabase.storage.from('pay-qr').download(path).then(({ data, error }) => {
      if (!alive) return;
      if (error || !data) { setFailed(true); return; }
      obj = URL.createObjectURL(data);
      setUrl(obj); setBlobImg(data);
    }).catch(() => alive && setFailed(true));
    return () => { alive = false; if (obj) URL.revokeObjectURL(obj); };
  }, [path]);
  return { url, blob: blobImg, failed };
}

function QrImage({ url, failed, size = 210 }) {
  return (
    <div style={{ width: size, height: size, background: '#FFFFFF', padding: 6, borderRadius: 12, boxSizing: 'border-box', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      {url ? <img src={url} alt="QR" data-testid="payment-uploaded-qr" style={{ maxWidth: '100%', maxHeight: '100%', display: 'block' }} />
        : <span style={{ fontSize: 11, color: '#666' }}>{failed ? 'QR' : '…'}</span>}
    </div>
  );
}

// Resolves the payload: stored text first, else decode the downloaded image.
function usePayload(stored, blob) {
  const [decoded, setDecoded] = useState('');
  useEffect(() => {
    let alive = true;
    if (stored || !blob) { setDecoded(''); return undefined; }
    const u = URL.createObjectURL(blob);
    const img = new Image();
    img.onload = () => { if (alive) setDecoded(decodeFromImage(img) || ''); URL.revokeObjectURL(u); };
    img.onerror = () => URL.revokeObjectURL(u);
    img.src = u;
    return () => { alive = false; };
  }, [stored, blob]);
  return stored || decoded;
}

function copy(text) {
  try { return navigator.clipboard.writeText(text); } catch { return Promise.resolve(); }
}

// What the payer can do with the decoded payload. Mobile: one clearly labelled
// button (web equivalent of iOS long-press). Desktop: account info to copy.
function PayActions({ payload, T }) {
  const [note, setNote] = useState('');
  if (!payload) return null;
  const c = classifyQr(payload);
  const mobile = isMobileBrowser();
  const flash = (m) => { setNote(m); setTimeout(() => setNote(''), 4000); };
  const btn = (label, onClick, testid) => (
    <div onClick={onClick} data-testid={testid}
         style={{ ...inkButton({ borderRadius: 14, padding: '11px 16px', fontSize: 13, width: '100%', boxSizing: 'border-box', textAlign: 'center' }) }}>{label}</div>
  );
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8, width: '100%', alignItems: 'center' }}>
      <span style={{ fontSize: 11, color: ink, opacity: 0.65 }}>{qrKindLabel(c, T)}</span>
      {c.kind === 'vietqr' && (
        <div style={{ fontSize: 12.5, color: ink, textAlign: 'center', wordBreak: 'break-all' }}>
          {T('Số tài khoản', 'Account')}: <b>{c.info.account}</b>
        </div>
      )}
      {c.kind === 'vietqr' && btn(T('Chép số tài khoản', 'Copy account number'),
        () => copy(c.info.account).then(() => flash(T('Đã chép số tài khoản.', 'Account number copied.'))), 'payqr-copy')}
      {mobile && c.kind === 'vietqr' && btn(T('Mở app thanh toán', 'Open payment app'),
        () => { copy(c.info.account); flash(T('Đang mở app thanh toán · đã chép số tài khoản', 'Opening your payment app · account number copied')); window.location.href = c.link; }, 'payqr-open')}
      {mobile && c.kind === 'url' && btn(T('Mở app thanh toán', 'Open payment app'),
        () => { flash(T('Đang mở app thanh toán…', 'Opening your payment app…')); window.location.href = c.link; }, 'payqr-open')}
      {c.kind === 'url' && !mobile && btn(T('Chép liên kết thanh toán', 'Copy payment link'),
        () => copy(c.link).then(() => flash(T('Đã chép liên kết.', 'Link copied.'))), 'payqr-copy')}
      {c.kind === 'text' && btn(T('Chép nội dung mã', 'Copy QR content'),
        () => copy(c.text).then(() => flash(T('Đã chép nội dung mã.', 'QR content copied.'))), 'payqr-copy')}
      {note && <span style={{ fontSize: 11.5, color: ink, textAlign: 'center' }}>{note}</span>}
    </div>
  );
}

// ---- Guest: the host's uploaded QR on the payment screen ----
// Privacy: the pay-qr storage policy (migration 122) only lets the host's
// owners and people holding a pending/confirmed/attended booking read it, so
// a failed download simply renders nothing.
export function GuestPaymentQr({ orgId, path }) {
  const { T } = useGoc();
  const { url, blob, failed } = useQrImage(path);
  const [stored, setStored] = useState('');
  useEffect(() => {
    let alive = true;
    if (!orgId || !path) return undefined;
    supabase.from('organizers').select('pay_qr_payload').eq('id', orgId).maybeSingle()
      .then(({ data }) => { if (alive) setStored(data?.pay_qr_payload || ''); }, () => {});
    return () => { alive = false; };
  }, [orgId, path]);
  const payload = usePayload(stored, blob);
  if (!path || failed) return null;
  return (
    <div style={{ margin: '20px 22px 0' }} data-testid="payment-uploaded-qr-card">
      <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Mã QR của người tổ chức', "Organizer's payment QR")}</span>
      <div style={{ ...cardGlass({ marginTop: 10, padding: 18, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }) }}>
        <QrImage url={url} failed={failed} />
        <span style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, opacity: 0.7, textAlign: 'center' }}>
          {T('Quét bằng app ngân hàng hoặc ví, rồi nhập đúng số tiền và nội dung chuyển khoản bên dưới.',
             'Scan with your banking or wallet app, then enter the exact amount and the reference shown here.')}
        </span>
        <PayActions payload={payload} T={T} />
      </div>
    </div>
  );
}

// ---- Host: upload / replace / remove on the Getting Paid screen ----
export function HostPaymentQr() {
  const { state: s, T } = useGoc();
  const orgId = s.myOrganizerIds?.[0];
  const [qr, setQr] = useState({ path: '', payload: '' });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const fileRef = useRef(null);

  useEffect(() => {
    let alive = true;
    if (!orgId) return undefined;
    supabase.from('organizers').select('pay_qr_path, pay_qr_payload').eq('id', orgId).maybeSingle()
      .then(({ data }) => {
        if (alive && data) setQr({ path: data.pay_qr_path || '', payload: data.pay_qr_payload || '' });
      }, () => {});
    return () => { alive = false; };
  }, [orgId]);

  const { url, blob, failed } = useQrImage(qr.path);
  const payload = usePayload(qr.payload, blob);
  const saveFail = T('Chưa lưu được mã QR. Thử lại nhé.', "Couldn't save the QR code. Please try again.");

  const onPick = useCallback(async (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file || !orgId) return;
    setBusy(true); setError('');
    try {
      let prepared;
      try { prepared = await prepareQrUpload(file); }
      catch (err) {
        setError(err.message === 'noQR'
          ? T('Không tìm thấy mã QR trong ảnh này. Hãy chọn ảnh chụp rõ mã QR.', 'No QR code found in that image. Pick a clear picture of the QR.')
          : T('Không đọc được ảnh.', "Couldn't read that image."));
        return;
      }
      const previous = qr.path;
      const path = `${orgId}/qr-${Math.floor(Date.now() / 1000)}.jpg`;
      const up = await supabase.storage.from('pay-qr').upload(path, prepared.blob, { contentType: 'image/jpeg', upsert: true });
      if (up.error) throw up.error;
      const { data, error: rpcErr } = await supabase.rpc('set_organizer_pay_qr', { p_organizer: orgId, p_path: path, p_payload: prepared.payload });
      if (rpcErr || data?.success === false) throw rpcErr || new Error(data?.error);
      setQr({ path, payload: prepared.payload });
      if (previous && previous !== path) supabase.storage.from('pay-qr').remove([previous]).catch(() => {});
    } catch (err) {
      console.error('uploadPayoutQR failed', err);
      setError(saveFail);
    } finally { setBusy(false); }
  }, [orgId, qr.path, T, saveFail]);

  const onRemove = useCallback(async () => {
    if (!orgId || !qr.path) return;
    setBusy(true); setError('');
    try {
      const { data, error: rpcErr } = await supabase.rpc('set_organizer_pay_qr', { p_organizer: orgId, p_path: '', p_payload: '' });
      if (rpcErr || data?.success === false) throw rpcErr || new Error(data?.error);
      const previous = qr.path;
      setQr({ path: '', payload: '' });
      supabase.storage.from('pay-qr').remove([previous]).catch(() => {});
    } catch (err) {
      console.error('removePayoutQR failed', err);
      setError(saveFail);
    } finally { setBusy(false); }
  }, [orgId, qr.path, saveFail]);

  if (!orgId) return null;
  const hasQr = !!qr.path;
  const pill = (extra) => ({ ...fieldGlass({ padding: '9px 14px', border: 'none', borderRadius: 999, cursor: busy ? 'default' : 'pointer', opacity: busy ? 0.5 : 1 }), fontSize: 13, fontWeight: 600, color: ink, ...extra });

  return (
    <div style={{ margin: '20px 22px 0' }} data-testid="payout-qr-section">
      <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Mã QR nhận tiền', 'Payment QR code')}</span>
      <p style={{ fontSize: 12, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
        {T('Tải ảnh mã QR của ngân hàng hoặc ví bạn dùng (VietQR, MoMo, Zelle, Venmo, Cash App…). Khách sẽ thấy mã này khi thanh toán.',
           'Upload the QR from the bank or wallet you get paid on (VietQR, MoMo, Zelle, Venmo, Cash App…). Guests see it when they pay.')}
      </p>
      {hasQr && (
        <div style={{ ...cardGlass({ marginTop: 12, padding: 16, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }) }}>
          <QrImage url={url} failed={failed} size={180} />
          {payload && <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>{qrKindLabel(classifyQr(payload), T)}</span>}
        </div>
      )}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 12, flexWrap: 'wrap' }}>
        <input ref={fileRef} type="file" accept="image/png,image/jpeg,image/*" onChange={onPick} style={{ display: 'none' }} data-testid="payout-qr-file" />
        <div onClick={() => !busy && fileRef.current?.click()} style={pill()} data-testid="payout-qr-upload">
          {busy ? T('Đang xử lý…', 'Working…') : hasQr ? T('Thay mã QR', 'Replace QR code') : T('Tải mã QR lên', 'Upload a QR code')}
        </div>
        {hasQr && (
          <span onClick={() => !busy && onRemove()} style={{ fontSize: 12.5, color: alert, cursor: busy ? 'default' : 'pointer' }} data-testid="payout-qr-remove">
            {T('Xoá', 'Remove')}
          </span>
        )}
      </div>
      {error && <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '10px 0 0' }}>{error}</p>}
    </div>
  );
}

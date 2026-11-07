import { useEffect, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { ink, FACE, alert } from '../theme.js';

// "Request a correction" under the profile birthday on Reserve (migration 175).
// The birthday itself is never editable here: this only files a request that a
// platform admin reviews and applies.
const ERRORS = {
  INVALID_DOB: ['Ngày sinh không hợp lệ.', 'That date of birth isn’t valid.'],
  INVALID_REASON: ['Hãy nêu lý do (ít nhất 5 ký tự).', 'Please give a reason (at least 5 characters).'],
  SAME_DOB: ['Ngày này giống ngày hiện tại.', 'That is the same as the current date.'],
  ALREADY_PENDING: ['Bạn đã có một yêu cầu đang chờ.', 'You already have a request waiting.'],
  NO_DOB_ON_FILE: ['Hồ sơ chưa có ngày sinh.', 'There is no birthday on your profile.'],
};
const fmt = (iso, lang) => new Date(`${iso}T00:00:00`).toLocaleDateString(lang === 'en' ? 'en-GB' : 'vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric' });

export default function DobCorrectionRequest() {
  const { state: s, T } = useBanBe();
  const [req, setReq] = useState(null);
  const [open, setOpen] = useState(false);
  const [dob, setDob] = useState('');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const todayIso = new Date().toISOString().slice(0, 10);

  const load = async () => {
    const { data } = await supabase.rpc('get_my_dob_correction');
    setReq(data && data.status ? data : null);
  };
  useEffect(() => { load(); }, []);

  const submit = async () => {
    if (busy) return;
    setBusy(true); setErr('');
    const { data, error } = await supabase.rpc('request_dob_correction', { p_dob: dob, p_reason: reason });
    setBusy(false);
    if (error || !data?.success) {
      const e = ERRORS[data?.error];
      setErr(e ? T(e[0], e[1]) : T('Không gửi được. Thử lại.', 'Couldn’t send that. Try again.'));
      return;
    }
    setOpen(false); setDob(''); setReason('');
    load();
  };

  const input = { fontFamily: FACE, fontSize: 13, color: ink, background: 'rgba(255,255,255,0.55)', border: '1px solid rgba(27,25,22,0.12)', borderRadius: 10, padding: '7px 10px', boxSizing: 'border-box' };

  if (req?.status === 'pending') {
    return (
      <span style={{ fontSize: 11.5, color: ink, opacity: 0.75 }} data-testid="dob-correction-pending">
        {T(`Yêu cầu sửa thành ${fmt(req.requested_dob, s.lang)} đang chờ quản trị viên xem xét.`, `Your request to change it to ${fmt(req.requested_dob, s.lang)} is waiting for an admin.`)}
      </span>
    );
  }
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      {req?.status === 'rejected' && (
        <span style={{ fontSize: 11.5, color: ink, opacity: 0.75 }} data-testid="dob-correction-rejected">
          {T('Yêu cầu sửa trước đó đã bị từ chối', 'Your last correction request was declined')}{req.decision_note ? `: ${req.decision_note}` : '.'}
        </span>
      )}
      {!open ? (
        <span role="button" onClick={() => setOpen(true)} style={{ fontSize: 11.5, fontWeight: 600, color: ink, textDecoration: 'underline', cursor: 'pointer' }} data-testid="dob-correction-open">
          {T('Sai ngày sinh? Yêu cầu sửa', 'Wrong? Request a correction')}
        </span>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }} data-testid="dob-correction-form">
          <label style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, fontSize: 12.5, color: ink }}>
            {T('Ngày sinh đúng', 'Correct date of birth')}
            <input type="date" value={dob} max={todayIso} onChange={(e) => setDob(e.target.value)} style={input} data-testid="dob-correction-dob" />
          </label>
          <textarea value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} rows={2}
            placeholder={T('Lý do (ví dụ: nhập nhầm khi đăng ký)', 'Reason (for example: mistyped at sign-up)')}
            style={{ ...input, resize: 'vertical', width: '100%' }} data-testid="dob-correction-reason" />
          <span style={{ fontSize: 11, color: ink, opacity: 0.65 }}>
            {T('Quản trị viên sẽ xem xét. Ngày sinh chỉ đổi khi yêu cầu được duyệt.', 'An admin reviews it. Your birthday only changes if the request is approved.')}
          </span>
          {err && <span style={{ fontSize: 12, color: alert }} data-testid="dob-correction-error">{err}</span>}
          <div style={{ display: 'flex', gap: 14, fontSize: 12.5, fontWeight: 600, color: ink }}>
            <span role="button" onClick={submit} style={{ cursor: dob && reason.trim().length >= 5 ? 'pointer' : 'default', opacity: dob && reason.trim().length >= 5 && !busy ? 1 : 0.4 }} data-testid="dob-correction-submit">
              {busy ? T('Đang gửi…', 'Sending…') : T('Gửi yêu cầu', 'Send request')}
            </span>
            <span role="button" onClick={() => { setOpen(false); setErr(''); }} style={{ cursor: 'pointer' }}>{T('Hủy', 'Cancel')}</span>
          </div>
        </div>
      )}
    </div>
  );
}

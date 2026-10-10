import { useEffect, useState, useCallback } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { paper, ink, display, fieldGlass, inkButton, alert } from '../theme.js';

// Admin > Birthday corrections (migration 175). Lists correction requests with the
// current and requested date; Approve rewrites the stored birthday, Decline keeps it.
// Authority is enforced by the RPCs (admin only, not your own request).
const ERRORS = {
  NOT_AUTHORIZED: ['Bạn không có quyền.', 'You are not allowed to do this.'],
  NOT_PENDING: ['Yêu cầu này đã được xử lý.', 'That request was already handled.'],
  INVALID_TARGET: ['Bạn không thể xử lý yêu cầu của chính mình.', 'You can’t decide your own request.'],
  NOT_FOUND: ['Không tìm thấy yêu cầu.', 'Request not found.'],
};

export default function AdminDobCorrections() {
  const { state: s, T, set } = useBanBe();
  const [rows, setRows] = useState([]);
  const [notes, setNotes] = useState({});
  const [busyId, setBusyId] = useState(null);
  const [msg, setMsg] = useState({ text: '', bad: false });
  const [loading, setLoading] = useState(true);

  const fmt = (iso) => (iso ? new Date(`${iso}T00:00:00`).toLocaleDateString(s.lang === 'en' ? 'en-GB' : 'vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric' }) : '—');
  const load = useCallback(async () => {
    const { data, error } = await supabase.rpc('admin_list_dob_corrections');
    setLoading(false);
    if (error || !data?.success) { setMsg({ text: T('Không tải được danh sách.', 'Couldn’t load the list.'), bad: true }); return; }
    setRows(data.requests || []);
  }, [T]);
  useEffect(() => { if (s.accountType === 'admin') load(); }, [s.accountType, load]);

  if (s.accountType !== 'admin') return null;

  const decide = async (id, approve) => {
    setBusyId(id); setMsg({ text: '', bad: false });
    const { data, error } = await supabase.rpc('admin_decide_dob_correction', { p_id: id, p_approve: approve, p_note: notes[id] || null });
    setBusyId(null);
    if (error || !data?.success) {
      const e = ERRORS[data?.error];
      setMsg({ text: e ? T(e[0], e[1]) : T('Không thực hiện được. Thử lại.', 'Couldn’t do that. Try again.'), bad: true });
      return;
    }
    setMsg({ text: approve ? T('Đã duyệt và cập nhật ngày sinh.', 'Approved. The birthday was updated.') : T('Đã từ chối.', 'Declined.'), bad: false });
    load();
  };

  const pending = rows.filter(r => r.status === 'pending');
  const done = rows.filter(r => r.status !== 'pending');
  const card = (r, withActions) => (
    <div key={r.id} style={{ ...fieldGlass({ marginTop: 10, padding: 16 }) }} data-testid={`dob-request-${r.id}`}>
      <div style={{ fontSize: 14, fontWeight: 600 }}>{r.display_name || r.email}</div>
      <div style={{ fontSize: 12, opacity: 0.75, marginTop: 2 }}>{r.email}</div>
      <div style={{ fontSize: 12.5, lineHeight: 1.6, marginTop: 8 }}>
        {T('Hiện tại', 'Current')}: <b>{fmt(r.current_dob)}</b><br />
        {T('Yêu cầu đổi thành', 'Requested')}: <b>{fmt(r.requested_dob)}</b><br />
        {T('Lý do', 'Reason')}: {r.reason}
      </div>
      {withActions ? (
        <>
          <input value={notes[r.id] || ''} onChange={e => setNotes({ ...notes, [r.id]: e.target.value })} maxLength={500}
            placeholder={T('Ghi chú cho người dùng (không bắt buộc)', 'Note to the user (optional)')}
            style={{ ...fieldGlass({ marginTop: 10, padding: 12, border: 'none', width: '100%', boxSizing: 'border-box' }), fontSize: 13, color: ink, outline: 'none' }} />
          <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
            <div onClick={() => busyId == null && decide(r.id, true)} style={{ ...inkButton({ flex: 1, padding: 12, fontSize: 13 }), opacity: busyId == null ? 1 : 0.45, cursor: 'pointer' }} data-testid={`dob-approve-${r.id}`}>{T('Duyệt', 'Approve')}</div>
            <div onClick={() => busyId == null && decide(r.id, false)} style={{ ...fieldGlass({ flex: 1, padding: 12, fontSize: 13, textAlign: 'center', cursor: 'pointer' }), opacity: busyId == null ? 1 : 0.45 }} data-testid={`dob-decline-${r.id}`}>{T('Từ chối', 'Decline')}</div>
          </div>
        </>
      ) : (
        <div style={{ fontSize: 12, marginTop: 8, opacity: 0.75 }}>{r.status === 'approved' ? T('Đã duyệt', 'Approved') : T('Đã từ chối', 'Declined')}{r.decision_note ? `: ${r.decision_note}` : ''}</div>
      )}
    </div>
  );

  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Admin birthday corrections">
      <div onClick={() => set({ screen: 'accountGroup', accountGroupKey: 'adminReview' })} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="admin-dob-back">
        ‹ {T('Duyệt & Kiểm Duyệt', 'Review & Moderation')}
      </div>
      <div style={{ padding: '14px 30px 42px' }}>
        <h1 style={{ ...display(24, { margin: 0 }) }}>{T('Sửa ngày sinh', 'Birthday corrections')}</h1>
        <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
          {T('Người dùng gửi yêu cầu khi ngày sinh trong hồ sơ bị sai. Duyệt sẽ ghi đè ngày sinh đã lưu.', 'People file a request when the birthday on their profile is wrong. Approving overwrites the stored birthday.')}
        </p>
        {msg.text && <p style={{ fontSize: 12.5, color: msg.bad ? alert : ink, margin: '12px 0 0' }} data-testid="admin-dob-msg">{msg.text}</p>}
        {loading && <p style={{ fontSize: 13, opacity: 0.65, marginTop: 18 }}>{T('Đang tải…', 'Loading…')}</p>}
        {!loading && pending.length === 0 && <p style={{ fontSize: 13, opacity: 0.65, marginTop: 18 }} data-testid="admin-dob-empty">{T('Không có yêu cầu nào đang chờ.', 'No requests waiting.')}</p>}
        {pending.map(r => card(r, true))}
        {done.length > 0 && <span style={{ display: 'block', fontSize: 11.5, fontWeight: 600, marginTop: 24 }}>{T('Đã xử lý', 'Handled')}</span>}
        {done.map(r => card(r, false))}
      </div>
    </div>
  );
}

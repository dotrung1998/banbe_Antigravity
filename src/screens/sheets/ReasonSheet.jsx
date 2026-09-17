import { useGoc, UNDO_CHECKIN_REASONS, CANCEL_BOOKING_REASONS, REJECT_GUEST_REASONS } from '../../state/GocContext.jsx';
import { paper, ink, rule, alert } from '../../theme.js';

// Shown whenever an organizer reverses a check-in, cancels an already-paid
// booking, or rejects a still-pending one — all three require picking one of
// a fixed list of reasons (no free text) before anything actually changes,
// so the guest's notification always says something concrete. A fourth kind,
// 'confirmCheckin' (14-organizer-checkin.md, Bug 3), has no reason list at
// all — a plain yes/no before actually marking a guest arrived.
export default function ReasonSheet() {
  const { state, T, closeReasonPrompt, submitReasonPrompt, confirmCheckin } = useGoc();
  const s = state;
  const prompt = s.reasonPrompt;
  if (!prompt) return null;

  const isConfirmCheckin = prompt.kind === 'confirmCheckin';
  if (isConfirmCheckin) {
    return (
      <div onClick={s.reasonPromptBusy ? undefined : closeReasonPrompt} style={{ position: 'absolute', inset: 0, zIndex: 23, background: 'rgba(12,12,12,0.55)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'gocFade 0.2s ease both' }}>
        <div onClick={(e) => e.stopPropagation()} style={{ background: paper, padding: '26px 24px 36px', display: 'flex', flexDirection: 'column', animation: 'gocSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Xác nhận điểm danh', 'Confirm check-in')}</span>
          <p style={{ fontSize: 13, lineHeight: 1.5, color: ink, margin: '8px 0 0' }}>
            {prompt.guestName
              ? T('Bạn có chắc muốn xác nhận ' + prompt.guestName + ' đã tới?', 'Are you sure ' + prompt.guestName + ' has arrived?')
              : T('Bạn có chắc muốn xác nhận khách này đã tới?', 'Are you sure this guest has arrived?')}
          </p>
          <div style={{ display: 'flex', gap: 8, marginTop: 16 }}>
            <div onClick={confirmCheckin} data-testid="confirm-checkin"
                 style={{ flex: 1, textAlign: 'center', fontSize: 13, fontWeight: 600, padding: '11px 12px', borderRadius: 12, cursor: 'pointer', background: ink, color: paper }}>
              {T('Xác nhận', 'Confirm')}
            </div>
            <div onClick={closeReasonPrompt} data-testid="cancel-checkin"
                 style={{ flex: 1, textAlign: 'center', fontSize: 13, fontWeight: 600, padding: '11px 12px', borderRadius: 12, cursor: 'pointer', border: `1px solid ${rule}`, color: ink }}>
              {T('Để sau', 'Not now')}
            </div>
          </div>
        </div>
      </div>
    );
  }

  const reasons = prompt.kind === 'undoCheckin' ? UNDO_CHECKIN_REASONS
    : prompt.kind === 'rejectGuest' ? REJECT_GUEST_REASONS
    : CANCEL_BOOKING_REASONS;
  const title = prompt.kind === 'undoCheckin' ? T('Huỷ điểm danh', 'Undo check-in')
    : prompt.kind === 'rejectGuest' ? T('Từ chối yêu cầu đặt chỗ', 'Reject this request')
    : T('Huỷ vé', 'Cancel booking');
  const subtitle = prompt.guestName
    ? (prompt.kind === 'undoCheckin'
      ? T('Vì sao bạn muốn chuyển ' + prompt.guestName + ' về "Chưa đến"?', 'Why move ' + prompt.guestName + ' back to "Not yet"?')
      : prompt.kind === 'rejectGuest'
      ? T('Vì sao bạn không nhận yêu cầu của ' + prompt.guestName + '?', "Why reject " + prompt.guestName + "'s request?")
      : T('Vì sao bạn muốn huỷ vé của ' + prompt.guestName + '?', "Why cancel " + prompt.guestName + "'s booking?"))
    : '';

  return (
    <div onClick={s.reasonPromptBusy ? undefined : closeReasonPrompt} style={{ position: 'absolute', inset: 0, zIndex: 23, background: 'rgba(12,12,12,0.55)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'gocFade 0.2s ease both' }}>
      <div onClick={(e) => e.stopPropagation()} style={{ background: paper, padding: '26px 24px 36px', display: 'flex', flexDirection: 'column', animation: 'gocSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{title}</span>
        {subtitle && <p style={{ fontSize: 13, lineHeight: 1.5, color: ink, margin: '8px 0 0' }}>{subtitle}</p>}
        <p style={{ fontSize: 12, lineHeight: 1.5, color: ink, opacity: 0.7, margin: '6px 0 0' }}>
          {prompt.kind === 'rejectGuest'
            ? T('Chỗ sẽ được mở lại ngay và khách sẽ được báo trong ứng dụng.', 'The seat is returned to the pool immediately and the guest is notified in the app.')
            : T('Khách sẽ được báo qua email và trong ứng dụng.', 'The guest will be notified by email and in the app.')}
        </p>
        <div style={{ display: 'flex', flexDirection: 'column', marginTop: 14 }}>
          {reasons.map(r => (
            <div
              key={r.key}
              onClick={s.reasonPromptBusy ? undefined : () => submitReasonPrompt(T(r.vi, r.en))}
              style={{ padding: '13px 2px', borderBottom: `1px solid ${rule}`, cursor: s.reasonPromptBusy ? 'default' : 'pointer', fontSize: 14.5, color: ink, opacity: s.reasonPromptBusy ? 0.5 : 1 }}
            >
              {T(r.vi, r.en)}
            </div>
          ))}
        </div>
        {s.reasonPromptError && <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '12px 0 0' }}>{s.reasonPromptError}</p>}
        <div onClick={s.reasonPromptBusy ? undefined : closeReasonPrompt} style={{ marginTop: 14, color: ink, fontSize: 13.5, textAlign: 'center', padding: 8, cursor: 'pointer' }}>
          {s.reasonPromptBusy ? T('Đang xử lý…', 'Working…') : T('Để sau', 'Not now')}
        </div>
      </div>
    </div>
  );
}

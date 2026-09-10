import { useGoc, UNDO_CHECKIN_REASONS, CANCEL_BOOKING_REASONS } from '../../state/GocContext.jsx';
import { paper, ink, rule } from '../../theme.js';

// Shown whenever an organizer reverses a check-in or cancels an already-paid
// booking — both require picking one of a fixed list of reasons (no free
// text) before anything actually changes, so the guest's notification
// always says something concrete.
export default function ReasonSheet() {
  const { state, T, closeReasonPrompt, submitReasonPrompt } = useGoc();
  const s = state;
  const prompt = s.reasonPrompt;
  if (!prompt) return null;

  const isUndo = prompt.kind === 'undoCheckin';
  const reasons = isUndo ? UNDO_CHECKIN_REASONS : CANCEL_BOOKING_REASONS;
  const title = isUndo ? T('Huỷ điểm danh', 'Undo check-in') : T('Huỷ vé', 'Cancel booking');
  const subtitle = prompt.guestName
    ? (isUndo
      ? T('Vì sao bạn muốn chuyển ' + prompt.guestName + ' về "Chưa đến"?', 'Why move ' + prompt.guestName + ' back to "Not yet"?')
      : T('Vì sao bạn muốn huỷ vé của ' + prompt.guestName + '?', "Why cancel " + prompt.guestName + "'s booking?"))
    : '';

  return (
    <div onClick={s.reasonPromptBusy ? undefined : closeReasonPrompt} style={{ position: 'absolute', inset: 0, zIndex: 23, background: 'rgba(12,12,12,0.55)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'gocFade 0.2s ease both' }}>
      <div onClick={(e) => e.stopPropagation()} style={{ background: paper, padding: '26px 24px 36px', display: 'flex', flexDirection: 'column', animation: 'gocSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{title}</span>
        {subtitle && <p style={{ fontSize: 13, lineHeight: 1.5, color: ink, margin: '8px 0 0' }}>{subtitle}</p>}
        <p style={{ fontSize: 12, lineHeight: 1.5, color: ink, opacity: 0.7, margin: '6px 0 0' }}>
          {T('Khách sẽ được báo qua email và trong ứng dụng.', 'The guest will be notified by email and in the app.')}
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
        {s.reasonPromptError && <p style={{ fontSize: 12, lineHeight: 1.5, color: '#9A3E2D', margin: '12px 0 0' }}>{s.reasonPromptError}</p>}
        <div onClick={s.reasonPromptBusy ? undefined : closeReasonPrompt} style={{ marginTop: 14, color: ink, fontSize: 13.5, textAlign: 'center', padding: 8, cursor: 'pointer' }}>
          {s.reasonPromptBusy ? T('Đang xử lý…', 'Working…') : T('Để sau', 'Not now')}
        </div>
      </div>
    </div>
  );
}

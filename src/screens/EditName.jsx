import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, display, fieldGlass, inkButton } from '../theme.js';

export default function EditName() {
  const { state, T, set, editNameType, saveDisplayName } = useGoc();
  const s = state;

  return (
    <div style={{ animation: 'gocFade 0.32s ease both', minHeight: '100%', background: paper }} data-screen-label="Edit name">
      <div onClick={() => set({ screen: 'profile' })} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Tài khoản', 'Account')}</div>
      <div style={{ padding: '16px 30px 42px' }}>
        <h1 style={{ ...display(27, { margin: 0, lineHeight: 1.2 }) }}>{T('Tên hiển thị', 'Display name')}</h1>
        <p style={{ fontSize: 13.5, lineHeight: 1.55, color: ink, margin: '10px 0 0' }}>
          {T('Đây là tên mà người tổ chức và khách khác thấy. Nếu bạn từng giữ chỗ ở đâu, đổi tên sẽ báo cho người tổ chức đó qua thông báo và email.', 'This is the name organizers and other guests see. If you have any bookings, changing it notifies those organizers by in-app notification and email.')}
        </p>

        <input
          value={s.editNameValue}
          onChange={editNameType}
          placeholder={T('Tên của bạn', 'Your name')}
          maxLength={60}
          style={{ ...fieldGlass({ marginTop: 22, padding: 14, border: 'none' }), fontSize: 15, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none' }}
        />
        {s.editNameError && <p style={{ fontSize: 12, lineHeight: 1.5, color: '#9A3E2D', margin: '10px 0 0' }}>{s.editNameError}</p>}
        <div
          onClick={s.editNameSaving ? undefined : saveDisplayName}
          style={{ ...inkButton({ marginTop: 18, borderRadius: 18, padding: 15 }), opacity: s.editNameSaving ? 0.6 : 1, cursor: s.editNameSaving ? 'default' : 'pointer' }}
        >
          {s.editNameSaving ? T('Đang lưu…', 'Saving…') : T('Lưu tên', 'Save name')}
        </div>
      </div>
    </div>
  );
}

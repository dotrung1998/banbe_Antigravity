import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, display, fieldGlass } from '../theme.js';

export default function Login() {
  const {
    state, T, set,
    loginEmailType, loginEmailSubmit, loginEmailKey, loginPhoneType, loginCodeType, verifyLoginCode, loginZalo, loginPhone, loginFacebook, loginInstagram, emailValid,
  } = useGoc();
  const s = state;
  const valid = emailValid(s.loginEmail);
  const changeAuthMode = (authMode) => set({ authMode, reserveError: '', loginSent: false, loginSentVia: null });

  const loginBtnStyle = {
    marginTop: 12, fontSize: 15, fontWeight: 600, textAlign: 'center', padding: 15, cursor: valid ? 'pointer' : 'default',
    background: valid ? ink : 'rgba(27,25,22,0.16)',
    color: valid ? paper : ink,
    transition: 'background .15s',
  };

  const zaloBtn = {
    marginTop: 26,
    background: 'linear-gradient(165deg, rgba(255,255,255,0.25) 0%, rgba(255,255,255,0.07) 30%, rgba(255,255,255,0) 55%), rgba(0,72,196,0.66)',
    color: '#FFFFFF', backdropFilter: 'blur(22px) saturate(1.7)', WebkitBackdropFilter: 'blur(22px) saturate(1.7)',
    border: '1px solid rgba(255,255,255,0.35)',
    boxShadow: 'inset 0 1px 1px rgba(255,255,255,0.5), inset 0 -12px 22px rgba(255,255,255,0.1), 0 14px 34px rgba(0,104,255,0.35)',
    borderRadius: 18, textShadow: '0 1px 2px rgba(0,60,150,0.35)', fontSize: 15, fontWeight: 600,
    textAlign: 'center', padding: 15, cursor: 'pointer',
  };

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', height: '100%', display: 'flex', flexDirection: 'column', background: paper }} data-screen-label="Login">
      <div onClick={() => set({ screen: s.authBackScreen })} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Quay lại', 'Back')}</div>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: '0 26px' }}>
        <div style={{ display: 'flex', gap: 16, borderBottom: '1px solid rgba(27,25,22,0.16)', paddingBottom: 8 }}>
          {['login', 'signup'].map(mode => <span key={mode} onClick={() => changeAuthMode(mode)} style={{ fontSize: 11.5, color: ink, fontWeight: s.authMode === mode ? 600 : 400, borderBottom: s.authMode === mode ? `2px solid ${ink}` : '2px solid transparent', paddingBottom: 6, cursor: 'pointer' }}>{mode === 'login' ? T('Đăng nhập', 'Log in') : T('Đăng ký', 'Sign up')}</span>)}
        </div>
        <h2 style={{ ...display(25, { lineHeight: 1.3, margin: '10px 0 0' }) }}>{s.authMode === 'signup' ? T('Tạo tài khoản banbe', 'Create your banbe account') : T('Chào mừng trở lại', 'Welcome back')}</h2>
        <p style={{ fontSize: 13.5, lineHeight: 1.55, color: ink, margin: '12px 0 0' }}>{T('Một tài khoản cho tất cả. Muốn tổ chức sự kiện, bạn chỉ cần bật chế độ tổ chức trong Tài khoản.', 'One account for everything. To host events, just switch on organizer mode from your Account.')}</p>
        <div onClick={loginZalo} style={zaloBtn}>{T('Tiếp tục với Zalo', 'Continue with Zalo')}</div>
        <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
          <div onClick={loginPhone} style={{ ...fieldGlass({ padding: '13px 4px', border: 'none' }), ...socialBtn }}>{T('Gửi OTP', 'Send OTP')}</div>
          <div onClick={loginFacebook} style={{ ...fieldGlass({ padding: '13px 4px', border: 'none' }), ...socialBtn }}>Facebook</div>
          <div onClick={loginInstagram} style={{ ...fieldGlass({ padding: '13px 4px', border: 'none' }), ...socialBtn }}>Instagram</div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 16 }}>
          <span style={{ flex: 1, height: 1, background: 'rgba(27,25,22,0.16)' }} />
          <span style={{ fontSize: 11, color: ink }}>{T('hoặc dùng email', 'or use email')}</span>
          <span style={{ flex: 1, height: 1, background: 'rgba(27,25,22,0.16)' }} />
        </div>
        <input value={s.loginEmail} onChange={loginEmailType} onKeyDown={loginEmailKey} placeholder="ban@email.com" style={{ ...fieldGlass({ marginTop: 14, padding: 14, border: 'none' }), fontSize: 14, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none' }} />
        <input value={s.loginPhoneNumber} onChange={loginPhoneType} placeholder="+84 901 234 567" inputMode="tel" style={{ ...fieldGlass({ marginTop: 10, padding: 14, border: 'none' }), fontSize: 14, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none' }} />
        {s.loginSentVia === 'phone' && <div style={{ display: 'flex', gap: 8, marginTop: 10 }}><input value={s.loginCode} onChange={loginCodeType} placeholder={T('Mã OTP', 'OTP code')} inputMode="numeric" style={{ ...fieldGlass({ flex: 1, padding: 14, border: 'none' }), fontSize: 14, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none' }} /><div onClick={verifyLoginCode} style={{ ...fieldGlass({ padding: '14px 12px', border: 'none' }), fontSize: 12, fontWeight: 600, color: ink, cursor: 'pointer' }}>{T('Xác nhận', 'Verify')}</div></div>}
        <div onClick={loginEmailSubmit} style={loginBtnStyle}>{s.authMode === 'signup' ? T('Gửi link đăng ký', 'Send sign-up link') : T('Gửi link đăng nhập', 'Send sign-in link')}</div>
        {s.loginSentVia === 'email' && <p style={{ fontSize: 12, lineHeight: 1.5, color: ink, margin: '12px 0 0', textAlign: 'center' }}>{s.authMode === 'signup' ? T('Đã gửi link đăng ký. Mở email trên thiết bị này để tiếp tục.', 'Sign-up link sent. Open the email on this device to continue.') : T('Đã gửi link đăng nhập. Mở email trên thiết bị này để tiếp tục.', 'Sign-in link sent. Open the email on this device to continue.')}</p>}
        {s.loginSentVia === 'phone' && <p style={{ fontSize: 12, lineHeight: 1.5, color: ink, margin: '12px 0 0', textAlign: 'center' }}>{T('Đã gửi mã OTP. Hãy nhập mã để tiếp tục.', 'OTP sent. Enter the code to continue.')}</p>}
        {s.reserveError && <p style={{ fontSize: 12, lineHeight: 1.5, color: '#9A3E2D', margin: '12px 0 0', textAlign: 'center' }}>{s.reserveError}</p>}
        <p style={{ fontSize: 11, lineHeight: 1.5, color: ink, margin: '16px 0 0', textAlign: 'center' }}>{T('Đã giữ chỗ sự kiện nào thì bạn đã đăng nhập sẵn.', "If you've already reserved a spot, you're already logged in.")}</p>
      </div>
    </div>
  );
}

const socialBtn = { flex: 1, color: ink, fontSize: 13, fontWeight: 500, textAlign: 'center', cursor: 'pointer' };

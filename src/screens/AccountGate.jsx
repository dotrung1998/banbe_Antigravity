// ---- account gate (web parity) ----
// Blocking overlay mirroring iOS Views/AccountGateViews.swift `AccountGateOverlay`.
// Mounted by App.jsx above every screen while the signed-in session has not
// cleared the SERVER-owned gate (migration 123): verified phone -> date-of-birth
// enrollment (new registrations), or "Confirm date of birth" (every new session
// of an account that has one). The database enforces the same rule via RLS;
// this is only its UI. Because it is an overlay and not a route, navigating
// cannot bypass it; once it clears, the user is exactly where they were headed.

import { useEffect, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, display, fieldGlass, inkButton, alert } from '../theme.js';
import { PHONE_COUNTRIES, DEFAULT_PHONE_COUNTRY, flagOf, toE164 } from '../lib/phone.js';
import { digitsOnly, validateDob, dobProblemText } from '../lib/dob.js';
import {
  useAccountGate, refreshGate, sendPhoneCode, resendPhoneCode, verifyPhoneCode, phoneFailureText,
  submitEnrollmentDob, confirmDob,
} from '../lib/accountGate.js';

const FONT = "'Be Vietnam Pro', sans-serif";
const inputStyle = (extra) => ({
  ...fieldGlass({ padding: 14, border: 'none', boxSizing: 'border-box' }),
  fontSize: 15, fontFamily: FONT, color: ink, outline: 'none', ...extra,
});

function Scaffold({ title, subtitle, children }) {
  const { T, logout } = useBanBe();
  return (
    <div style={{ minHeight: '100%', padding: '62px 24px 40px', boxSizing: 'border-box', color: ink }}>
      <img src="/banbe-wordmark.png" alt="banbe" crossOrigin="anonymous" style={{ width: 96, height: 'auto', display: 'block', marginTop: 36 }} />
      <h1 style={display(26, { margin: '28px 0 0', lineHeight: 1.25 })} data-testid="gate-title">{title}</h1>
      <p style={{ fontSize: 14, lineHeight: 1.55, color: ink, opacity: 0.8, margin: '10px 0 0' }}>{subtitle}</p>
      <div style={{ marginTop: 22, display: 'flex', flexDirection: 'column', gap: 14 }}>{children}</div>
      <div onClick={logout} data-testid="gate-signout" style={{ fontSize: 13, textAlign: 'center', marginTop: 28, cursor: 'pointer' }}>
        {T('Đăng xuất', 'Sign out')}
      </div>
    </div>
  );
}

function InkBtn({ label, enabled = true, onClick, testid }) {
  return (
    <div
      onClick={enabled ? onClick : undefined} data-testid={testid} role="button" aria-disabled={!enabled}
      style={{ ...inkButton({ borderRadius: 18, padding: 15, fontSize: 15 }), opacity: enabled ? 1 : 0.45, cursor: enabled ? 'pointer' : 'default' }}
    >{label}</div>
  );
}

const ErrorLine = ({ text, testid }) => text
  ? <p data-testid={testid} style={{ fontSize: 12.5, lineHeight: 1.5, color: alert, margin: 0 }}>{text}</p>
  : null;

// Day / Month / Year as three digit-only fields; focus moves on as each fills.
function DobFields({ value, onChange, prefix }) {
  const { T } = useBanBe();
  const refs = [useRef(null), useRef(null), useRef(null)];
  const field = (key, label, ph, max, idx) => (
    <label style={{ display: 'flex', flexDirection: 'column', gap: 6, flex: key === 'year' ? 1.4 : 1, minWidth: 0 }}>
      <span style={{ fontSize: 11.5, fontWeight: 600 }}>{label}</span>
      <input
        ref={refs[idx]} value={value[key]} placeholder={ph} inputMode="numeric" autoComplete="off" data-testid={`${prefix}-${key}`}
        onChange={(e) => {
          const d = digitsOnly(e.target.value, max);
          onChange({ ...value, [key]: d });
          if (d.length === max && refs[idx + 1]) refs[idx + 1].current?.focus();
        }}
        style={inputStyle({ textAlign: 'center', width: '100%', fontSize: 17, fontWeight: 500 })}
      />
    </label>
  );
  return (
    <div style={{ display: 'flex', gap: 10 }}>
      {field('day', T('Ngày', 'Day'), 'DD', 2, 0)}
      {field('month', T('Tháng', 'Month'), 'MM', 2, 1)}
      {field('year', T('Năm', 'Year'), 'YYYY', 4, 2)}
    </div>
  );
}

function PhoneEnrollment() {
  const { T } = useBanBe();
  const [country, setCountry] = useState(DEFAULT_PHONE_COUNTRY);
  const [number, setNumber] = useState('');
  const [e164, setE164] = useState('');
  const [codeSent, setCodeSent] = useState(false);
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [cooldown, setCooldown] = useState(0);

  useEffect(() => {
    if (cooldown <= 0) return undefined;
    const id = setTimeout(() => setCooldown(c => c - 1), 1000);
    return () => clearTimeout(id);
  }, [cooldown]);

  const send = async () => {
    setMessage('');
    const parsed = toE164(country, number);
    if (!parsed) { setMessage(T('Số điện thoại chưa hợp lệ. Kiểm tra mã quốc gia và số.', "That phone number isn't valid. Check the country code and number.")); return; }
    setBusy(true);
    const failure = await sendPhoneCode(parsed);
    setBusy(false);
    if (failure) { setMessage(phoneFailureText(failure, T)); return; }
    setE164(parsed); setCodeSent(true); setCooldown(60);
  };
  const resend = async () => {
    setMessage(''); setBusy(true);
    const failure = await resendPhoneCode(e164);
    setBusy(false);
    if (failure) setMessage(phoneFailureText(failure, T)); else setCooldown(60);
  };
  const verify = async () => {
    setMessage(''); setBusy(true);
    const failure = await verifyPhoneCode(e164, code);
    setBusy(false);
    if (failure) { setCode(''); setMessage(phoneFailureText(failure, T)); }
  };

  return (
    <Scaffold
      title={codeSent ? T('Nhập mã xác minh', 'Enter the verification code') : T('Xác minh số điện thoại', 'Verify your phone number')}
      subtitle={codeSent
        ? T('Nhập mã 6 số vừa được gửi qua SMS.', 'Enter the 6-digit code we just texted you.')
        : T('Thêm số điện thoại có mã quốc gia để hoàn tất đăng ký. Chúng tôi sẽ gửi một mã SMS.', "Add a phone number with its country code to finish registering. We'll text you a code.")}
    >
      {!codeSent ? (
        <>
          <div style={{ display: 'flex', gap: 10 }}>
            <select
              value={country.iso} data-testid="gate-phone-country"
              onChange={(e) => setCountry(PHONE_COUNTRIES.find(c => c.iso === e.target.value) || DEFAULT_PHONE_COUNTRY)}
              style={inputStyle({ flex: 'none', maxWidth: 120, padding: '14px 8px', cursor: 'pointer' })}
            >
              {PHONE_COUNTRIES.map(c => <option key={c.iso} value={c.iso}>{flagOf(c.iso)} +{c.dial} {T(c.vi, c.en)}</option>)}
            </select>
            <input
              value={number} onChange={(e) => setNumber(e.target.value)} inputMode="tel" autoComplete="tel" data-testid="gate-phone-number"
              onKeyDown={(e) => { if (e.key === 'Enter' && !busy) send(); }}
              placeholder={T('Số điện thoại', 'Phone number')} style={inputStyle({ flex: 1, minWidth: 0 })}
            />
          </div>
          <InkBtn label={busy ? T('Đang gửi…', 'Sending…') : T('Gửi mã', 'Send code')} enabled={!busy && number.trim().length > 0} onClick={send} testid="gate-phone-send" />
        </>
      ) : (
        <>
          <p style={{ fontSize: 12.5, lineHeight: 1.5, opacity: 0.75, margin: 0 }}>
            {T(`Mã 6 số đã được gửi tới ${e164}. Mã chỉ xác minh bạn nhận được tin nhắn trên số này.`, `A 6-digit code was sent to ${e164}. It only confirms you can receive texts on this number.`)}
          </p>
          <input
            value={code} onChange={(e) => setCode(digitsOnly(e.target.value, 6))} inputMode="numeric" autoComplete="one-time-code" placeholder="123456" data-testid="gate-phone-code"
            onKeyDown={(e) => { if (e.key === 'Enter' && !busy && code.length === 6) verify(); }}
            style={inputStyle({ textAlign: 'center', fontSize: 24, fontWeight: 600, letterSpacing: '0.2em' })}
          />
          <InkBtn label={busy ? T('Đang kiểm tra…', 'Checking…') : T('Xác minh', 'Verify')} enabled={!busy && code.length === 6} onClick={verify} testid="gate-phone-verify" />
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13 }}>
            <span onClick={cooldown > 0 || busy ? undefined : resend} style={{ cursor: cooldown > 0 || busy ? 'default' : 'pointer', opacity: cooldown > 0 || busy ? 0.5 : 1 }}>
              {cooldown > 0 ? T(`Gửi lại sau ${cooldown}s`, `Resend in ${cooldown}s`) : T('Gửi lại mã', 'Resend code')}
            </span>
            <span onClick={() => { setCodeSent(false); setCode(''); setMessage(''); }} style={{ cursor: 'pointer' }}>{T('Đổi số', 'Change number')}</span>
          </div>
        </>
      )}
      <ErrorLine text={message} testid="gate-phone-error" />
    </Scaffold>
  );
}

function DobEnrollment() {
  const { T } = useBanBe();
  const [input, setInput] = useState({ day: '', month: '', year: '' });
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const submit = async () => {
    setMessage('');
    const v = validateDob(input);
    if (!v.iso) { setMessage(dobProblemText(v.problem, T)); return; }
    setBusy(true);
    const ok = await submitEnrollmentDob(v.iso);
    setBusy(false);
    if (!ok) setMessage(T('Chưa lưu được. Thử lại sau.', "Couldn't save. Please try again."));
  };
  return (
    <Scaffold title={T('Ngày sinh', 'Date of birth')} subtitle={T('Nhập ngày sinh của bạn để hoàn tất đăng ký.', 'Enter your date of birth to complete registration.')}>
      <DobFields value={input} onChange={setInput} prefix="gate-enroll" />
      <p style={{ fontSize: 12, opacity: 0.7, margin: 0 }}>{T('Bạn không thể tự đổi ngày sinh sau khi lưu.', "You can't change your date of birth yourself after saving.")}</p>
      <ErrorLine text={message} testid="gate-enroll-error" />
      <InkBtn label={busy ? T('Đang lưu…', 'Saving…') : T('Hoàn tất đăng ký', 'Complete registration')} enabled={!busy} onClick={submit} testid="gate-enroll-submit" />
    </Scaffold>
  );
}

function ConfirmDob({ lockedUntil }) {
  const { T } = useBanBe();
  const [input, setInput] = useState({ day: '', month: '', year: '' });
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const initialLock = lockedUntil ? Math.max(0, Math.ceil((new Date(lockedUntil).getTime() - Date.now()) / 1000)) : 0;
  const [lockedFor, setLockedFor] = useState(initialLock);

  useEffect(() => {
    if (lockedFor <= 0) return undefined;
    const id = setTimeout(() => setLockedFor(n => n - 1), 1000);
    return () => clearTimeout(id);
  }, [lockedFor]);

  const lockText = lockedFor > 0
    ? T(`Quá nhiều lần thử. Thử lại sau khoảng ${Math.ceil(lockedFor / 60)} phút.`, `Too many attempts. Try again in about ${Math.ceil(lockedFor / 60)} min.`)
    : '';

  const submit = async () => {
    setMessage('');
    const v = validateDob(input);
    if (!v.iso) { setMessage(dobProblemText(v.problem, T)); return; }
    setBusy(true);
    const r = await confirmDob(v.iso);
    setBusy(false);
    if (r.result === 'success') return;
    setInput({ day: '', month: '', year: '' }); // always blank for the next try
    if (r.result === 'incorrect') {
      setMessage(r.attemptsLeft != null
        ? T(`Ngày sinh chưa đúng. Còn ${r.attemptsLeft} lần thử.`, `That isn't right. ${r.attemptsLeft} tries left.`)
        : T('Ngày sinh chưa đúng.', "That isn't right."));
    } else if (r.result === 'locked') setLockedFor(Math.max(r.retryAfter || 900, 1));
    else setMessage(T('Chưa kiểm tra được. Thử lại sau.', "Couldn't check. Please try again."));
  };

  return (
    <Scaffold title={T('Xác nhận ngày sinh', 'Confirm date of birth')} subtitle={T('Nhập ngày sinh đã đăng ký để tiếp tục đăng nhập.', 'Enter your registered date of birth to continue signing in.')}>
      <DobFields value={input} onChange={setInput} prefix="gate-confirm" />
      <ErrorLine text={lockText || message} testid="gate-confirm-error" />
      <InkBtn label={busy ? T('Đang kiểm tra…', 'Checking…') : T('Tiếp tục', 'Continue')} enabled={!busy && lockedFor === 0} onClick={submit} testid="gate-confirm-submit" />
      <div style={{ marginTop: 6 }}>
        <div style={{ fontSize: 12, fontWeight: 600 }}>{T('Quên ngày sinh đã đăng ký?', 'Forgot your registered date of birth?')}</div>
        <p style={{ fontSize: 12, lineHeight: 1.5, opacity: 0.75, margin: '6px 0 0' }}>
          {T('Ngày sinh không thể tự đặt lại trong ứng dụng. Hãy đăng xuất và liên hệ hỗ trợ banbe để được trợ giúp.', "It can't be reset in the app. Sign out and contact banbe support for help.")}
        </p>
      </div>
    </Scaffold>
  );
}

export default function AccountGate() {
  const { state, T } = useBanBe();
  const { gate, status, blocking } = useAccountGate();
  // Like iOS: the splash plays first, then the gate takes over.
  if (!blocking || state.screen === 'splash') return null;

  let body;
  if (gate === 'blocked' && status) {
    if (status.phone_required) body = <PhoneEnrollment />;
    else if (status.dob_enrollment_required) body = <DobEnrollment />;
    else body = <ConfirmDob lockedUntil={status.locked_until} />;
  } else if (gate === 'unavailable') {
    body = (
      <Scaffold
        title={T('Dịch vụ tạm thời không khả dụng', 'Service temporarily unavailable')}
        subtitle={T('banbe chưa kết nối được tới máy chủ. Kiểm tra kết nối hoặc thử lại sau ít phút. Bạn chưa vào được ứng dụng cho tới khi bước này hoàn tất.', "banbe can't reach its servers right now. Check your connection or try again in a little while. You can't use the app until this finishes.")}
      >
        <InkBtn label={T('Thử lại', 'Try again')} onClick={refreshGate} testid="gate-retry" />
      </Scaffold>
    );
  } else {
    body = (
      <div style={{ height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, color: ink }}>
        {T('Đang tải, vui lòng đợi một chút…', 'Loading, just a moment…')}
      </div>
    );
  }
  return (
    <div data-testid="account-gate" data-gate={gate} style={{ position: 'fixed', inset: 0, zIndex: 2000, background: paper, overflowY: 'auto', animation: 'banbeFade 0.25s ease both' }}>
      {/* Home's Pulse teaser bubble is portaled to <body> (outside this overlay's
          stacking context) and would float over the gate; hide it while gated. */}
      <style>{'[data-testid="home-pulse-teaser-bubble"]{display:none !important}'}</style>
      <div style={{ maxWidth: 480, margin: '0 auto', minHeight: '100%' }}>{body}</div>
    </div>
  );
}

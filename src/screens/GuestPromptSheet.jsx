// Contextual sign-in prompt for a guest — web twin of iOS GuestPromptSheet (note 48). Shown when a signed-out visitor
// tries something personal (save, follow, reserve, message, like). "Continue" creates an account, "Log in" signs in,
// "Not now" keeps browsing. Never "Sign up", never a dead end; sign-in resumes the action (lib/guestAccess.js).
import { useEffect } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, display, inkButton } from '../theme.js';
import { promptCopy, promptBenefits } from '../lib/guestAccess.js';

const ICON = { save: '♥', follow: '＋', reserve: '🎟', message: '💬', like: '👍' };

export default function GuestPromptSheet() {
  const { state: s, T, continueFromGuestPrompt, dismissGuestPrompt } = useBanBe();
  const prompt = s.guestPrompt;
  useEffect(() => {
    if (!prompt) return undefined;
    const onKey = (e) => { if (e.key === 'Escape') dismissGuestPrompt(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [prompt, dismissGuestPrompt]);
  if (!prompt) return null;
  const copy = promptCopy(prompt.context, T);
  return (
    <div role="dialog" aria-modal="true" aria-labelledby="guest-prompt-title" data-testid="guest-prompt" onClick={dismissGuestPrompt}
      style={{ position: 'fixed', inset: 0, zIndex: 2300, background: 'rgba(0,0,0,0.36)', display: 'flex', alignItems: 'flex-end', justifyContent: 'center' }}>
      <div onClick={(e) => e.stopPropagation()} style={{ width: '100%', maxWidth: 480, background: paper, color: ink, borderRadius: '26px 26px 0 0', padding: '24px 22px 30px', boxSizing: 'border-box' }}>
        <div aria-hidden style={{ width: 68, height: 68, borderRadius: 22, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 28, background: 'linear-gradient(135deg, rgba(var(--bb-fg-rgb),0.10), rgba(var(--bb-fg-rgb),0.03))' }}>
          {ICON[prompt.context] || '★'}
        </div>
        <h2 id="guest-prompt-title" style={display(26, { margin: '18px 0 0' })}>{copy.title}</h2>
        <p style={{ fontSize: 14, lineHeight: 1.55, opacity: 0.75, margin: '6px 0 0' }}>{copy.body}</p>
        <div style={{ background: 'var(--bb-field)', borderRadius: 18, padding: 16, marginTop: 18, display: 'flex', flexDirection: 'column', gap: 12 }}>
          {promptBenefits(prompt.context, T).map(r => (
            <div key={r.id} style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14 }}>
              <span aria-hidden style={{ width: 32, height: 32, borderRadius: 16, background: 'rgba(var(--bb-fg-rgb),0.07)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 14 }}>{r.icon}</span>
              <span>{r.text}</span>
            </div>
          ))}
        </div>
        <button type="button" onClick={() => continueFromGuestPrompt('signup')} data-testid="guest-prompt-continue"
          style={{ ...inkButton({ width: '100%', padding: 15, marginTop: 20, fontFamily: 'inherit' }) }}>{T('Tiếp tục', 'Continue')}</button>
        <button type="button" onClick={() => continueFromGuestPrompt('login')} data-testid="guest-prompt-login"
          style={{ display: 'block', width: '100%', marginTop: 10, padding: 13, borderRadius: 18, border: '1px solid rgba(var(--bb-fg-rgb),0.2)', background: 'transparent', color: ink, fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer' }}>
          {T('Đăng nhập', 'Log in')}
        </button>
        <button type="button" onClick={dismissGuestPrompt} data-testid="guest-prompt-dismiss"
          style={{ display: 'block', width: '100%', marginTop: 6, padding: 12, border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 14, cursor: 'pointer', opacity: 0.75 }}>
          {T('Để sau', 'Not now')}
        </button>
      </div>
    </div>
  );
}

/** Slim banner at the top of Home for a guest — iOS GuestBrowseBanner. */
export function GuestBrowseBanner() {
  const { state: s, T, openAuth } = useBanBe();
  if (s.user) return null;
  return (
    <div data-testid="guest-banner" style={{ margin: '12px 20px 0', padding: '12px 14px', borderRadius: 18, background: 'var(--bb-field)', color: ink, display: 'flex', alignItems: 'center', gap: 12 }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14, fontWeight: 600 }}>{T('Bạn đang xem với tư cách khách', "You're browsing as a guest")}</div>
        <div style={{ fontSize: 12.5, opacity: 0.75, marginTop: 2 }}>{T('Tạo tài khoản để lưu, giữ chỗ và nhắn tin cho host.', 'Create an account to save, hold seats and message hosts.')}</div>
      </div>
      <button type="button" onClick={() => openAuth('login', s.screen)} data-testid="guest-banner-login"
        style={{ border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 13.5, fontWeight: 700, cursor: 'pointer', minHeight: 44, whiteSpace: 'nowrap' }}>
        {T('Đăng nhập', 'Log in')}
      </button>
    </div>
  );
}

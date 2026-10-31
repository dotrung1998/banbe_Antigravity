// Simple Shell follow-up (note 66): the "Start hosting" invitation, shared by Account (inline card, the old
// account-host-first-event card) and the StartHostingSheet (Home's locked Hosting segment, "+" > Host an event).
// Twin of iOS Views/StartHostingCard.swift. One primary action; an account that can already host (`canHost`) but has
// organizer mode off sees "Turn on hosting" instead of the first-event copy.
import { useEffect, useRef } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { ink, ink2, paper, display, inkButton, block } from '../theme.js';
import { useReducedMotion } from '../lib/useReducedMotion.js';

export function startHostingCopy(canHost, T) {
  return canHost
    ? {
      title: T('Chế độ tổ chức đang tắt', 'Hosting is off'),
      body: T('Bật lại để tạo sự kiện, đăng story và quản lý khách.', 'Turn it back on to create events, post stories and manage guests.'),
      cta: T('Bật chế độ tổ chức', 'Turn on hosting'),
    }
    : {
      title: T('Tổ chức sự kiện đầu tiên', 'Host your first event'),
      body: T('Miễn phí khi banbe còn mới: không phí đăng, không phí giao dịch.', 'Free while banbe is new: no listing or transaction fees.'),
      cta: T('Bắt đầu tổ chức ▪︎ miễn phí', 'Start hosting ▪︎ free'),
    };
}

/** The card body. `testId` / `ctaTestId` keep the caller's existing ids (Account: account-host-first-event). */
export default function StartHostingCard({ canHost = false, onStart, busy = false, testId, ctaTestId, titleId, style }) {
  const { T } = useBanBe();
  const copy = startHostingCopy(canHost, T);
  return (
    <div data-testid={testId} style={{ padding: 16, borderRadius: 14, background: block, color: ink, display: 'flex', flexDirection: 'column', gap: 8, ...style }}>
      <span id={titleId} style={{ ...display(17, { lineHeight: 1.3 }) }}>{copy.title}</span>
      <p style={{ fontSize: 12.5, lineHeight: 1.5, color: ink2, margin: 0 }}>{copy.body}</p>
      <button type="button" onClick={onStart} disabled={busy} aria-busy={busy || undefined} data-testid={ctaTestId} className="bb-press"
        style={{ ...inkButton({ marginTop: 4, borderRadius: 18, padding: 12, fontSize: 14, minHeight: 44, width: '100%', fontFamily: 'inherit', cursor: busy ? 'default' : 'pointer', opacity: busy ? 0.7 : 1 }) }}>
        {copy.cta}
      </button>
    </div>
  );
}

/** The invitation as a bottom sheet (GuestPromptSheet style). Mounted once in App.jsx. */
export function StartHostingSheet() {
  const { state: s, T, canHost, startHosting, closeStartHosting } = useBanBe();
  const open = !!(s.startHostingOpen && s.user);
  const reduce = useReducedMotion();
  const sheetRef = useRef(null);
  const returnFocus = useRef(null);
  useEffect(() => {
    if (!open) return undefined;
    returnFocus.current = document.activeElement;
    const t = setTimeout(() => sheetRef.current?.querySelector('button')?.focus({ preventScroll: true }), 0);
    const onKey = (e) => {
      if (e.key === 'Escape') { e.preventDefault(); closeStartHosting(); return; }
      if (e.key !== 'Tab' || !sheetRef.current) return;
      const f = [...sheetRef.current.querySelectorAll('button:not([disabled])')];
      if (!f.length) return;
      const first = f[0], last = f[f.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    };
    window.addEventListener('keydown', onKey);
    return () => {
      clearTimeout(t); window.removeEventListener('keydown', onKey);
      try { returnFocus.current?.focus?.({ preventScroll: true }); } catch { /* element gone */ }
    };
  }, [open, closeStartHosting]);
  if (!open) return null;
  // `canHost` includes organizerMode, which is off here, so it means "has hosted / admin".
  return (
    <div role="presentation" data-testid="start-hosting-backdrop" onClick={closeStartHosting}
      style={{ position: 'fixed', inset: 0, zIndex: 2300, background: 'rgba(0,0,0,0.36)', display: 'flex', alignItems: 'flex-end', justifyContent: 'center', animation: 'banbeFade 0.2s ease both' }}>
      <div ref={sheetRef} role="dialog" aria-modal="true" aria-labelledby="start-hosting-title" data-testid="start-hosting-sheet" onClick={(e) => e.stopPropagation()}
        style={{
          width: '100%', maxWidth: 480, background: paper, color: ink, borderRadius: '26px 26px 0 0', boxSizing: 'border-box',
          padding: '20px 20px calc(24px + env(safe-area-inset-bottom, 0px))',
          animation: reduce ? 'banbeFade 0.2s ease both' : 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both',
        }}>
        <StartHostingCard canHost={canHost} busy={s.organizerModeBusy} titleId="start-hosting-title"
          onStart={() => startHosting({ land: 'home', confirmed: true })} ctaTestId="start-hosting-confirm" />
        {s.organizerModeError && <p role="alert" style={{ fontSize: 12, lineHeight: 1.5, color: 'var(--bb-alert)', margin: '10px 4px 0' }}>{s.organizerModeError}</p>}
        <button type="button" onClick={closeStartHosting} data-testid="start-hosting-dismiss"
          style={{ display: 'block', width: '100%', minHeight: 44, marginTop: 8, padding: 12, border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 14, cursor: 'pointer', opacity: 0.75 }}>
          {T('Để sau', 'Not now')}
        </button>
      </div>
    </div>
  );
}

// Post-signup onboarding overlay (web port of iOS EventOnboardingOverlay, note 34):
// settings review first, then five optional preference questions. Mounted by
// App.jsx below the account gate; shown only for a signed-in user past
// splash/login/policy whose server markers say a step is still owed.
//
// No-repeat: finishing/skipping calls complete_* (a server marker). If that
// fails the user stays on the step with Retry and "Skip for now", which closes
// the step for this session only (the marker stays unset, so it may reappear).
// Nothing here is mandatory: every control can be skipped and "Continue" works
// with nothing granted. Haptics and Face ID do not exist on web and are omitted.

import { useEffect, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { useAccountGate, getHostPromoConsent, setHostPromoConsent } from '../lib/accountGate.js';
import { paper, ink, display, fieldGlass, inkButton, alert } from '../theme.js';
import { StepProgress, encouragement } from '../components/ui/FormControls.jsx';
import { normalizeForSave, budgetRegionDefault } from '../lib/eventPrefs.js';
import { EventPreferencesForm, EventPrefsPrivacyNote } from './EventPreferences.jsx';

const NOT_ONBOARDING_SCREENS = new Set(['splash', 'langPick', 'themePick', 'login', 'resetPassword', 'policy']);

/** True while the onboarding overlay is (or should be) on screen; App.jsx hides the dock with it. */
export function useEventOnboardingActive() {
  const { state: s } = useBanBe();
  const { gate } = useAccountGate();
  return !!s.user && s.sessionChecked && !s.authSyncing && !s.policyGateActive && gate === 'ready'
    && !NOT_ONBOARDING_SCREENS.has(s.screen) && (s.needsSettingsOnboarding || s.needsPreferencesOnboarding);
}

// Goal gradient (note 48): creating the account is step 1 and already done,
// so the first onboarding screen opens at 33%, never 0%.
function StepIndicator({ step, total = 2 }) {
  const { T } = useBanBe();
  const steps = [T('Tài khoản', 'Account'), T('Cài đặt', 'Settings'), T('Sở thích', 'Interests')].slice(0, total + 1);
  return (
    <div data-testid="onboarding-step-indicator" aria-label={T(`Bước ${step} trên ${total}`, `Step ${step} of ${total}`)} style={{ marginBottom: 22 }}>
      <StepProgress steps={steps} current={step} message={encouragement(steps.length - step, T)} />
    </div>
  );
}

function SwitchRow({ title, detail, on, onClick, testId, disabled }) {
  return (
    <div
      onClick={disabled ? undefined : onClick} role="switch" aria-checked={on} aria-disabled={!!disabled} data-testid={testId}
      style={{ ...fieldGlass({ padding: '15px 18px', border: 'none' }), display: 'flex', alignItems: 'center', gap: 12, cursor: disabled ? 'default' : 'pointer', opacity: disabled ? 0.55 : 1 }}
    >
      <div style={{ flex: 1 }}>
        <div style={display(16, { lineHeight: 1.3 })}>{title}</div>
        <div style={{ fontSize: 11.5, lineHeight: 1.55, color: ink, opacity: 0.8, marginTop: 3 }}>{detail}</div>
      </div>
      <span style={{ flex: 'none', width: 44, height: 26, borderRadius: 13, background: on ? ink : 'rgba(27,25,22,0.18)', position: 'relative', transition: 'background .15s' }}>
        <span style={{ position: 'absolute', top: 3, left: on ? 21 : 3, width: 20, height: 20, borderRadius: 10, background: paper, transition: 'left .15s' }} />
      </span>
    </div>
  );
}

function InkBtn({ label, enabled = true, onClick, testId }) {
  return (
    <div onClick={enabled ? onClick : undefined} role="button" aria-disabled={!enabled} data-testid={testId}
      style={{ ...inkButton({ borderRadius: 18, padding: 15, fontSize: 15 }), opacity: enabled ? 1 : 0.45, cursor: enabled ? 'pointer' : 'default' }}>{label}</div>
  );
}

const LinkBtn = ({ label, onClick, testId, disabled }) => (
  <div onClick={disabled ? undefined : onClick} role="button" data-testid={testId}
    style={{ fontSize: 13, fontWeight: 600, textDecoration: 'underline', textAlign: 'center', marginTop: 14, cursor: disabled ? 'default' : 'pointer', color: ink, opacity: disabled ? 0.5 : 1 }}>{label}</div>
);

function SettingsStep() {
  const { state: s, T, set, toggleAutoEmailDocuments, completeSettingsOnboarding } = useBanBe();
  const isNew = s.eventOnboardingIsNewAccount;
  // New account: ordinary non-sensitive settings default ON. An existing prompted
  // account shows and keeps what it already has; only changed toggles are written.
  // Consent is never pre-ticked (note 48): promo starts OFF for new accounts.
  // Location is no longer asked here (iOS parity, note 43): Map/area picker
  // request it when they actually need it.
  const [emailDocs, setEmailDocs] = useState(() => (isNew ? true : s.autoEmailDocuments));
  const [promo, setPromo] = useState(false);
  const [promoCurrent, setPromoCurrent] = useState(null); // null = unknown (read failed / loading)
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let live = true;
    getHostPromoConsent().then(v => {
      if (!live) return;
      setPromoCurrent(v);
      setPromo(isNew ? false : (v ?? false));
    });
    return () => { live = false; };
  }, [isNew]);

  const finish = async () => {
    if (busy) return;
    setBusy(true); setFailed(false);
    try {
      // Write a setting only when the final toggle differs from its current value.
      if (emailDocs !== s.autoEmailDocuments) toggleAutoEmailDocuments();
      if (promoCurrent !== null && promo !== promoCurrent) {
        const v = await setHostPromoConsent(promo);
        if (v != null) setPromoCurrent(v);
      }
      const ok = await completeSettingsOnboarding();
      setFailed(!ok);
    } finally { setBusy(false); }
  };

  return (
    <div data-testid="onboarding-settings-step">
      <StepIndicator step={1} />
      <h1 style={display(27, { margin: 0, lineHeight: 1.2 })}>{T('Xem nhanh cài đặt', 'Quick settings review')}</h1>
      <p style={{ fontSize: 13.5, lineHeight: 1.55, color: ink, margin: '10px 0 0' }}>
        {T('Tất cả đều không bắt buộc, bạn có thể đổi lại bất cứ lúc nào trong Tài khoản.', 'Everything here is optional, you can change it any time in Account.')}
      </p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 22 }}>
        <SwitchRow testId="onboarding-settings-emailDocs" on={emailDocs} onClick={() => setEmailDocs(v => !v)}
          title={T('Gửi hoá đơn qua email', 'Email me payment documents')}
          detail={T('Tự gửi hoá đơn/biên nhận tới email của bạn. Đổi lại tại Tài khoản > Cài đặt > Tùy chỉnh ứng dụng.', 'Automatically email invoices and receipts to you. Change it in Account > Settings > App Preferences.')} />
        <SwitchRow testId="onboarding-settings-promo" on={promo} disabled={promoCurrent === null} onClick={() => setPromo(v => !v)}
          title={T('Tin nhắn quảng bá từ host', 'Host promotional texts')}
          detail={T('Tắt trừ khi bạn bật. Nếu bật, host bạn đã tương tác có thể soạn tin quảng bá SMS và tự gửi; banbe không gửi hộ. Đổi lại bất cứ lúc nào tại Tài khoản > Cài đặt > Bảo mật.',
            "Off unless you switch it on. If on, hosts you've interacted with may compose a promo text that they send themselves; banbe doesn't send for them. Change it any time in Account > Settings > Security.")} />
      </div>
      {failed && (
        <p data-testid="onboarding-settings-error" style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '16px 0 0' }}>
          {T('Chưa hoàn tất được bước này. Thử lại, hoặc bỏ qua lúc này (bước này có thể hiện lại lần mở sau).',
            'Couldn\'t finish this step. Retry, or skip for now (it may reappear next time you open the app).')}
        </p>
      )}
      <div style={{ marginTop: 22 }}>
        <InkBtn testId="onboarding-settings-continue" enabled={!busy} onClick={finish}
          label={busy ? T('Đang lưu…', 'Saving…') : failed ? T('Thử lại', 'Retry') : T('Tiếp tục', 'Continue')} />
      </div>
      {failed && <LinkBtn testId="onboarding-settings-skip" label={T('Bỏ qua lúc này', 'Skip for now')} onClick={() => set({ needsSettingsOnboarding: false })} />}
    </div>
  );
}

function QuestionsStep() {
  const { state: s, T, set, completePreferencesOnboarding } = useBanBe();
  const [draft, setDraft] = useState({});
  const [region, setRegion] = useState(() => budgetRegionDefault());
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  const complete = async (skipAll) => {
    if (busy) return;
    setBusy(true);
    const answered = normalizeForSave(draft);
    const hasAnswers = Object.keys(answered).length > 1; // beyond { version }
    const ok = await completePreferencesOnboarding(skipAll || !hasAnswers ? null : draft);
    setBusy(false);
    setFailed(!ok);
  };

  return (
    <div data-testid="onboarding-prefs-step">
      <StepIndicator step={s.needsSettingsOnboarding ? 1 : 2} />
      <h1 style={display(27, { margin: 0, lineHeight: 1.2 })}>{T('Vài câu hỏi nhanh', 'A few quick questions')}</h1>
      <p style={{ fontSize: 13.5, lineHeight: 1.55, color: ink, margin: '10px 0 0' }}>
        {T('Giúp chúng tôi gợi ý sự kiện hợp với bạn. Bỏ qua câu nào cũng được.', "Helps us suggest events you'll like. Skip any question you like.")}
      </p>
      <div style={{ marginTop: 24 }}>
        <EventPreferencesForm prefs={draft} onChange={setDraft} region={region} onRegionChange={setRegion} />
      </div>
      <div style={{ marginTop: 22 }}><EventPrefsPrivacyNote /></div>
      {failed && (
        <p data-testid="onboarding-prefs-error" style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '14px 0 0' }}>
          {T('Chưa lưu được. Thử lại, hoặc bỏ qua lúc này (bước này có thể hiện lại lần mở sau).',
            "Couldn't save. Retry, or skip for now (this step may reappear next time you open the app).")}
        </p>
      )}
      <div style={{ marginTop: 20 }}>
        <InkBtn testId="onboarding-prefs-finish" enabled={!busy} onClick={() => complete(false)}
          label={busy ? T('Đang lưu…', 'Saving…') : failed ? T('Thử lại', 'Retry') : T('Hoàn tất', 'Finish')} />
      </div>
      <LinkBtn testId="onboarding-prefs-skip" disabled={busy}
        label={failed ? T('Bỏ qua lúc này', 'Skip for now') : T('Bỏ qua tất cả', 'Skip all')}
        onClick={() => (failed ? set({ needsPreferencesOnboarding: false }) : complete(true))} />
    </div>
  );
}

export default function EventOnboarding() {
  const { state: s } = useBanBe();
  const active = useEventOnboardingActive();
  if (!active) return null;
  // While the (existing) area sheet is open from the settings step, step aside
  // without unmounting so the user's choices survive.
  return (
    <div data-testid="event-onboarding-overlay" style={{ position: 'fixed', inset: 0, zIndex: 1900, background: paper, overflowY: 'auto', display: s.areaAsking ? 'none' : 'block', animation: 'banbeFade 0.25s ease both' }}>
      <div style={{ maxWidth: 480, margin: '0 auto', padding: '60px 30px 42px', boxSizing: 'border-box', color: ink }}>
        {s.needsSettingsOnboarding ? <SettingsStep /> : <QuestionsStep />}
      </div>
    </div>
  );
}

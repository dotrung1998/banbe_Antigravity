// Post-signup personalization flow — web port of the iOS flow (note 43; pure rules in lib/onboardingFlow.js):
// welcome → five questions, one per screen ("n of 5", Back, Skip, Continue) → save → a real For You reveal →
// the settings review (only if owed) → Home, with For You switched on only when there are real matches.
// Mounted by App.jsx below the account gate; shown only for a signed-in user past splash/login/policy whose
// server markers say a step is still owed (and kept up through the reveal by `onboardingFlowActive`).
//
// Server contract unchanged: complete_preferences_onboarding(p) (null = skipped everything, marker only) and
// complete_settings_onboarding. A failed save leaves the user on an honest screen with Retry / Edit answers /
// Skip for now (this session only — the marker stays unset). An unfinished questionnaire is kept in this
// browser for this account (lib/onboardingFlow.js draftStore) and resumed only while the server still owes it.
// Haptics and Face ID do not exist on web and are omitted.

import { useEffect, useMemo, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { useAccountGate, getHostPromoConsent, setHostPromoConsent } from '../lib/accountGate.js';
import { paper, ink, display, fieldGlass, inkButton, alert } from '../theme.js';
import { StepProgress, encouragement } from '../components/ui/FormControls.jsx';
import { NO_PREFERENCE, BUDGET_TIERS, BUDGET_REGIONS, budgetTierLabel, budgetRegionDefault, normalizeForSave, prefLabel } from '../lib/eventPrefs.js';
import { QUESTIONS, questionOptions, reduce, draftStore, impactLines, revealMatches, payload as flowPayload } from '../lib/onboardingFlow.js';
import { LOCATION_ALL } from '../lib/locationTree.js';
import { track, matchBucket } from '../lib/analytics.js';
import { EventPrefsPrivacyNote } from './EventPreferences.jsx';

const NOT_ONBOARDING_SCREENS = new Set(['splash', 'langPick', 'themePick', 'login', 'resetPassword', 'policy']);
const muted = (a) => `rgba(var(--bb-fg-rgb), ${a})`;

/** True while the onboarding overlay is (or should be) on screen; App.jsx hides the dock with it. */
export function useEventOnboardingActive() {
  const { state: s } = useBanBe();
  const { gate } = useAccountGate();
  return !!s.user && s.sessionChecked && !s.authSyncing && !s.policyGateActive && gate === 'ready'
    && !NOT_ONBOARDING_SCREENS.has(s.screen)
    && (s.needsSettingsOnboarding || s.needsPreferencesOnboarding || s.onboardingFlowActive);
}

// Goal gradient (note 48): creating the account is step 1 and already done, so nothing opens at 0%.
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
    <button type="button" onClick={enabled ? onClick : undefined} disabled={!enabled} data-testid={testId}
      style={{ ...inkButton({ borderRadius: 18, padding: 15, fontSize: 15, width: '100%', fontFamily: 'inherit' }), opacity: enabled ? 1 : 0.45, cursor: enabled ? 'pointer' : 'default' }}>{label}</button>
  );
}

const LinkBtn = ({ label, onClick, testId, disabled }) => (
  <button type="button" onClick={disabled ? undefined : onClick} disabled={disabled} data-testid={testId}
    style={{ display: 'block', width: '100%', background: 'none', border: 'none', fontFamily: 'inherit', fontSize: 13, fontWeight: 600, textDecoration: 'underline', textAlign: 'center', marginTop: 14, minHeight: 36, cursor: disabled ? 'default' : 'pointer', color: ink, opacity: disabled ? 0.5 : 1 }}>{label}</button>
);

function SettingsStep({ onDone, stepIndex, stepTotal }) {
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
      if (ok) onDone();
    } finally { setBusy(false); }
  };

  return (
    <div data-testid="onboarding-settings-step">
      <StepIndicator step={stepIndex} total={stepTotal} />
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
      {failed && <LinkBtn testId="onboarding-settings-skip" label={T('Bỏ qua lúc này', 'Skip for now')} onClick={() => { set({ needsSettingsOnboarding: false }); onDone(); }} />}
    </div>
  );
}


// ---- welcome ----

function WelcomeStep({ send }) {
  const { T } = useBanBe();
  const point = (icon, text) => (
    <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start', fontSize: 14, lineHeight: 1.5 }}>
      <span aria-hidden style={{ width: 22, textAlign: 'center', opacity: 0.7 }}>{icon}</span><span>{text}</span>
    </div>
  );
  return (
    <div data-testid="onboarding-welcome">
      <div aria-hidden style={{ fontSize: 40, color: '#CC9E29' }}>★</div>
      <h1 style={display(30, { margin: '18px 0 0', lineHeight: 1.15 })}>{T('Tìm những buổi bạn thật sự muốn đi', "Find events you'll actually want to go to")}</h1>
      <p style={{ fontSize: 15, lineHeight: 1.6, margin: '12px 0 0' }}>
        {T('Trả lời 5 câu ngắn, banbe sẽ gắn sao ★ Dành cho bạn lên những sự kiện hợp với bạn.', 'Answer 5 quick questions and banbe stars ★ For You on the events that fit.')}
      </p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12, margin: '26px 0 30px' }}>
        {point('◷', T('Khoảng 1 phút. Câu nào cũng bỏ qua được.', 'About a minute. Every question is optional.'))}
        {point('🔒', T('Chỉ bạn thấy câu trả lời, host không bao giờ thấy.', 'Only you see your answers. Hosts never do.'))}
        {point('⚙', T('Đổi lại bất cứ lúc nào trong Tài khoản.', 'Change them any time in Account.'))}
      </div>
      <InkBtn testId="onboarding-start" label={T('Bắt đầu', 'Get started')} onClick={() => send('start')} />
      <LinkBtn testId="onboarding-skip-all" label={T('Bỏ qua, xem tất cả sự kiện', 'Skip, show me everything')} onClick={() => send('skipAll')} />
    </div>
  );
}

// ---- one question per screen ----

const QUESTION_COPY = {
  goals: [['Bạn muốn gì từ một buổi đi chơi?', 'What do you want from a night out?'], ['Chọn bao nhiêu cũng được. Dùng để xếp gợi ý lên trước.', 'Pick any. We rank matching events higher.'], ['Mục tiêu', 'Goals']],
  interests: [['Loại sự kiện nào hợp với bạn?', 'Which kinds of events are you into?'], ['Chọn bao nhiêu cũng được. Gợi ý chỉ gồm những loại bạn chọn.', 'Pick any. Your picks only include these kinds.'], ['Sở thích', 'Interests']],
  availability: [['Bạn thường rảnh khi nào?', 'When are you usually free?'], ['Chọn bao nhiêu cũng được. Giờ khác vẫn hiện, chỉ xếp sau.', 'Pick any. Other times still show, just lower.'], ['Thời gian', 'Time']],
  budget: [['Mỗi buổi bạn muốn chi khoảng bao nhiêu?', 'How much do you like to spend per event?'], ['Chọn một mức.', 'Pick one.'], ['Ngân sách', 'Budget']],
  languages: [['Bạn thoải mái với ngôn ngữ nào?', 'Which languages are you comfortable with?'], ["Không bắt buộc. Sự kiện chưa ghi ngôn ngữ nên câu này chưa dùng để lọc.", "Optional. Events don't list a language yet, so this won't filter anything for now."], ['Ngôn ngữ', 'Language']],
};

function ChoiceRow({ title, selected, onClick, testId, multi = true }) {
  return (
    <button type="button" onClick={onClick} aria-pressed={selected} data-testid={testId}
      style={{
        display: 'flex', alignItems: 'center', gap: 12, width: '100%', textAlign: 'left', fontFamily: 'inherit', fontSize: 15,
        padding: '14px 16px', borderRadius: 16, cursor: 'pointer', color: ink, minHeight: 50,
        background: selected ? muted(0.08) : 'var(--bb-field)', border: `1.5px solid ${selected ? ink : 'transparent'}`,
      }}>
      <span style={{ flex: 1, fontWeight: selected ? 600 : 400 }}>{title}</span>
      <span aria-hidden style={{
        width: 22, height: 22, borderRadius: multi ? 6 : 11, flex: '0 0 auto', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        border: `1.5px solid ${selected ? ink : muted(0.35)}`, background: selected ? ink : 'transparent', color: paper, fontSize: 13,
      }}>{selected ? '✓' : ''}</span>
    </button>
  );
}

function QuestionStep({ flow, send }) {
  const { state: s, T } = useBanBe();
  const vi = s.lang !== 'en';
  const q = QUESTIONS[flow.index];
  const [[titleVi, titleEn], [subVi, subEn]] = QUESTION_COPY[q];
  const last = flow.index + 1 === QUESTIONS.length;
  const steps = [T('Tài khoản', 'Account'), ...QUESTIONS.map(x => T(...QUESTION_COPY[x][2]))];
  const picked = flow.draft[q];
  return (
    <div data-testid={`onboarding-question-${q}`}>
      <div style={{ display: 'flex', alignItems: 'center', marginBottom: 14 }}>
        <button type="button" onClick={() => send('back')} aria-label={T('Quay lại', 'Back')} data-testid="onboarding-back"
          style={{ background: 'none', border: 'none', color: ink, fontSize: 24, width: 44, height: 44, marginLeft: -12, cursor: 'pointer' }}>‹</button>
        <span style={{ flex: 1, textAlign: 'center', fontSize: 13, fontWeight: 600, color: muted(0.7) }} data-testid="onboarding-counter">
          {T(`Câu ${flow.index + 1}/${QUESTIONS.length}`, `${flow.index + 1} of ${QUESTIONS.length}`)}
        </span>
        <button type="button" onClick={() => send('skipQuestion')} data-testid="onboarding-skip"
          style={{ background: 'none', border: 'none', color: ink, fontFamily: 'inherit', fontSize: 14, fontWeight: 600, minHeight: 44, cursor: 'pointer' }}>{T('Bỏ qua', 'Skip')}</button>
      </div>
      {/* Head start (note 48): the account counts as done, so question 1 opens at 17%, not 0%. */}
      <StepProgress steps={steps} current={flow.index + 1} message={encouragement(steps.length - flow.index - 1, T)} testId="onboarding-progress" />
      <h1 style={display(26, { margin: '24px 0 0', lineHeight: 1.2 })}>{T(titleVi, titleEn)}</h1>
      <p style={{ fontSize: 13.5, lineHeight: 1.55, color: muted(0.75), margin: '8px 0 0' }}>{T(subVi, subEn)}</p>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 22 }}>
        {q === 'budget' ? (
          <>
            <div role="group" aria-label={T('Loại tiền', 'Currency')} style={{ display: 'inline-flex', alignSelf: 'flex-start', gap: 4, padding: 4, borderRadius: 999, background: 'var(--bb-field)', marginBottom: 4 }}>
              {BUDGET_REGIONS.map(r => (
                <button key={r} type="button" aria-pressed={flow.region === r} data-testid={`onboarding-region-${r}`} onClick={() => send({ type: 'setRegion', region: r })}
                  style={{ border: 'none', fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600, padding: '7px 14px', borderRadius: 999, cursor: 'pointer', background: flow.region === r ? ink : 'transparent', color: flow.region === r ? paper : ink }}>
                  {r === 'US' ? 'USD' : 'VND'}
                </button>
              ))}
            </div>
            {BUDGET_TIERS.map(t => (
              <ChoiceRow key={t} multi={false} testId={`onboarding-option-${t}`} title={budgetTierLabel(flow.region, t, vi)}
                selected={flow.draft.budget?.tier === t} onClick={() => send({ type: 'pickBudget', tier: t })} />
            ))}
            <ChoiceRow multi={false} testId={`onboarding-option-${NO_PREFERENCE}`} title={T('Không ưu tiên', 'No preference')}
              selected={flow.draft.budget?.tier === NO_PREFERENCE} onClick={() => send({ type: 'pickBudget', tier: NO_PREFERENCE })} />
          </>
        ) : (
          <>
            {questionOptions(q).map(o => (
              <ChoiceRow key={o.id} testId={`onboarding-option-${o.id}`} title={prefLabel(o.id, questionOptions(q), vi)}
                selected={!!picked?.includes(o.id)} onClick={() => send({ type: 'toggle', question: q, id: o.id })} />
            ))}
            <ChoiceRow testId={`onboarding-option-${NO_PREFERENCE}`} title={T('Không ưu tiên', 'No preference')}
              selected={!!picked?.includes(NO_PREFERENCE)} onClick={() => send({ type: 'toggle', question: q, id: NO_PREFERENCE })} />
          </>
        )}
      </div>
      {last && <div style={{ marginTop: 18 }}><EventPrefsPrivacyNote /></div>}
      <div style={{ marginTop: 24 }}>
        <InkBtn testId="onboarding-next" label={last ? T('Xem gợi ý của tôi', 'See my picks') : T('Tiếp tục', 'Continue')} onClick={() => send('next')} />
      </div>
    </div>
  );
}

// ---- saving / failed ----

function SavingStep() {
  const { T } = useBanBe();
  return (
    <div role="status" data-testid="onboarding-saving" style={{ padding: '120px 0', textAlign: 'center', fontSize: 14 }}>
      {T('Đang lưu lựa chọn của bạn…', 'Saving your picks…')}
    </div>
  );
}

function SaveFailedStep({ send }) {
  const { T } = useBanBe();
  return (
    <div data-testid="onboarding-save-failed">
      <h1 style={display(26, { margin: '40px 0 0' })}>{T('Chưa lưu được', "Couldn't save yet")}</h1>
      <p style={{ fontSize: 14, lineHeight: 1.55, margin: '10px 0 24px' }}>
        {T('Câu trả lời vẫn còn trên máy này. Thử lại, hoặc bỏ qua lúc này (bước này có thể hiện lại lần mở sau).',
          'Your answers are still on this device. Retry, or skip for now (this step may come back next time).')}
      </p>
      <InkBtn testId="onboarding-retry" label={T('Thử lại', 'Retry')} onClick={() => send('retrySave')} />
      <LinkBtn testId="onboarding-edit-answers" label={T('Sửa câu trả lời', 'Edit answers')} onClick={() => send('back')} />
      <LinkBtn testId="onboarding-skip-for-now" label={T('Bỏ qua lúc này', 'Skip for now')} onClick={() => send('skipForNow')} />
    </div>
  );
}

// ---- personalized reveal (real matches, real ranking) ----

function revealWhen(startsAt, lang) {
  if (!startsAt) return '';
  return new Date(startsAt).toLocaleString(lang === 'en' ? 'en-GB' : 'vi-VN', { timeZone: 'Asia/Ho_Chi_Minh', weekday: 'short', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
}

function RevealStep({ flow, reveal, onContinue, onOpenEvent }) {
  const { state: s, T, curArea, loadDiscoveryEvents, pickArea } = useBanBe();
  const vi = s.lang !== 'en';
  const prefs = s.eventPrefs || normalizeForSave(flow.draft);
  const lines = impactLines(prefs, vi);
  const { matches, everywhereCount } = reveal;
  const areaLimited = curArea.key !== LOCATION_ALL;
  const failed = s.discoveryEventsLoadFailed && !(s.discoveryEvents || []).length;
  const loading = !!s.discoveryEventsLoading;
  const trackedRef = useRef(false);

  useEffect(() => {
    if (!(s.discoveryEvents || []).length && !s.discoveryEventsLoading) loadDiscoveryEvents();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  useEffect(() => {
    if (trackedRef.current || loading || failed) return;
    trackedRef.current = true;
    track('personalized_results_viewed', { matchBucket: matchBucket(matches.length) });
  }, [loading, failed, matches.length]);

  const byKey = new Map((s.discoveryEvents || []).map(e => [e.key, e]));
  const cta = flow.needsSettings ? T('Tiếp tục', 'Continue') : matches.length ? T('Xem gợi ý cho tôi', 'Show my picks') : T('Xem tất cả sự kiện', 'See all events');
  const areaSuffix = (viTxt) => (areaLimited ? (viTxt ? ` ở ${curArea.label}` : ` in ${curArea.label}`) : '');

  return (
    <div data-testid="onboarding-reveal">
      <h1 style={display(30, { margin: 0, lineHeight: 1.15 })}>{T('Đây là những gì hợp với bạn', "Here's what fits you")}</h1>
      <div data-testid="onboarding-reveal-impacts" style={{ background: 'var(--bb-field)', borderRadius: 20, padding: 16, marginTop: 18 }}>
        <div style={{ fontSize: 14, fontWeight: 600 }}>{T('Câu trả lời của bạn thay đổi gì', 'What your answers change')}</div>
        {lines.length === 0 && (
          <p style={{ fontSize: 13.5, margin: '8px 0 0' }}>{T('Chưa lọc gì cả: bạn chọn "Không ưu tiên" nên mọi sự kiện đều hiện như bình thường.', 'Nothing is filtered: you chose "No preference", so every event shows as usual.')}</p>
        )}
        {lines.map((l, i) => (
          <div key={i} style={{ display: 'flex', gap: 10, marginTop: 10, fontSize: 13.5, lineHeight: 1.45 }}>
            <span aria-hidden style={{ width: 18, opacity: 0.7 }}>{l.kind === 'filter' ? '⏷' : l.kind === 'ranking' ? '↑' : '🔖'}</span>
            <span>{l.text}</span>
          </div>
        ))}
      </div>

      <div style={{ marginTop: 22 }}>
        {loading ? (
          <p role="status" data-testid="onboarding-reveal-loading" style={{ fontSize: 14, textAlign: 'center', padding: '40px 0' }}>{T('Đang tìm sự kiện hợp với bạn…', 'Finding events that fit…')}</p>
        ) : failed ? (
          <div data-testid="onboarding-reveal-failed">
            <p style={{ fontSize: 14, margin: 0 }}>{T('Chưa tải được sự kiện. Lựa chọn của bạn đã được lưu.', "Couldn't load events right now. Your answers are saved.")}</p>
            <LinkBtn testId="onboarding-reveal-retry" label={T('Thử lại', 'Try again')} onClick={loadDiscoveryEvents} />
          </div>
        ) : matches.length === 0 ? (
          <div>
            <div data-testid="onboarding-reveal-empty" style={{ fontSize: 16, fontWeight: 600 }}>
              {T(`Hiện chưa có sự kiện sắp tới nào khớp${areaSuffix(true)}.`, `No upcoming events match yet${areaSuffix(false)}.`)}
            </div>
            <p style={{ fontSize: 13.5, color: muted(0.75), margin: '8px 0 0' }}>
              {T('Khi có sự kiện hợp, chip ★ Dành cho bạn sẽ hiện trên trang chủ. Bạn có thể nới lựa chọn trong Tài khoản > Sở thích sự kiện.',
                'When one does, the ★ For You chip shows up on Home. You can loosen your answers in Account > Event preferences.')}
            </p>
            {areaLimited && everywhereCount > 0 && (
              <LinkBtn testId="onboarding-reveal-all-areas" label={T(`Xem ở mọi khu vực (${everywhereCount})`, `Look in all areas (${everywhereCount})`)} onClick={() => pickArea(LOCATION_ALL)} />
            )}
          </div>
        ) : (
          <div>
            <div data-testid="onboarding-reveal-count" style={{ fontSize: 16, fontWeight: 600 }}>
              {T(`${matches.length} sự kiện sắp tới hợp với bạn${areaSuffix(true)}`, `${matches.length} upcoming event${matches.length === 1 ? '' : 's'} fit you${areaSuffix(false)}`)}
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 12 }}>
              {matches.slice(0, 3).map(m => {
                const e = byKey.get(m.key);
                if (!e) return null;
                return (
                  <button key={m.key} type="button" onClick={() => onOpenEvent(e.key)} data-testid="onboarding-reveal-event"
                    style={{ display: 'flex', gap: 12, alignItems: 'center', width: '100%', textAlign: 'left', fontFamily: 'inherit', color: ink, padding: 10, borderRadius: 16, border: 'none', background: 'var(--bb-field)', cursor: 'pointer' }}>
                    <span aria-hidden style={{ width: 72, height: 72, borderRadius: 12, flex: '0 0 auto', background: e.photoUrl ? `center/cover no-repeat url("${e.photoUrl}")` : muted(0.08) }} />
                    <span style={{ flex: 1, minWidth: 0 }}>
                      <span style={{ display: 'block', fontSize: 14, fontWeight: 600 }}>{e.name}</span>
                      <span style={{ display: 'block', fontSize: 12.5, opacity: 0.75, marginTop: 3 }}>{revealWhen(e.startsAt, s.lang)}</span>
                      <span style={{ display: 'block', fontSize: 12.5, opacity: 0.75 }}>{e.priceVnd ? `${String(e.priceVnd).replace(/\B(?=(\d{3})+(?!\d))/g, '.')}₫` : T('Miễn phí', 'Free')}</span>
                    </span>
                    <span aria-hidden style={{ color: '#CC9E29' }}>★</span>
                  </button>
                );
              })}
            </div>
          </div>
        )}
      </div>
      <div style={{ marginTop: 26 }}>
        <InkBtn testId="onboarding-reveal-continue" enabled={!loading} label={cta} onClick={onContinue} />
      </div>
    </div>
  );
}

// ---- the flow ----

function OnboardingFlowRunner() {
  const { state: s, set, curArea, completePreferencesOnboarding, finishOnboardingFlow } = useBanBe();
  const uid = s.user?.id;
  const [flow, setFlow] = useState(() => draftStore.resume(uid, {
    needsPreferences: s.needsPreferencesOnboarding, needsSettings: s.needsSettingsOnboarding, region: budgetRegionDefault(),
  }));
  const flowRef = useRef(flow);
  flowRef.current = flow;
  const pendingEventRef = useRef(null);
  const finishedRef = useRef(false);

  // Keep the overlay up through the reveal even after the server markers clear — but never re-arm it once the
  // flow has finished (finishOnboardingFlow clears the flag while this runner is still mounted).
  useEffect(() => {
    if (!s.onboardingFlowActive && flow.stage !== 'finished' && !finishedRef.current) set({ onboardingFlowActive: true });
  }, [s.onboardingFlowActive, flow.stage, set]);
  useEffect(() => { draftStore.save(flow, uid); }, [flow, uid]);

  const send = (action) => {
    const { state, effects } = reduce(flowRef.current, action);
    flowRef.current = state;
    setFlow(state);
    for (const e of effects) {
      if (e.type === 'track') track(e.name, e.props);
      if (e.type === 'save') {
        completePreferencesOnboarding(e.payload).then(ok => send(ok ? 'saveSucceeded' : 'saveFailed'));
      }
    }
  };

  const prefs = s.eventPrefs || normalizeForSave(flow.draft);
  const reveal = useMemo(
    () => revealMatches(s.discoveryEvents, prefs, curArea.key === LOCATION_ALL ? null : curArea.match),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [s.discoveryEvents, s.eventPrefs, s.eventPrefsVersion, flow.draft, curArea],
  );

  // Hand-off once the flow is done: the overlay closes, For You turns on only with real matches.
  useEffect(() => {
    if (flow.stage !== 'finished' || finishedRef.current) return;
    finishedRef.current = true;
    draftStore.clear(uid);
    const answered = flowPayload(flow) != null;
    finishOnboardingFlow({ showForYou: answered, hasMatches: reveal.matches.length > 0, openEventKey: pendingEventRef.current, answeredPreferences: answered });
  }, [flow, uid, reveal.matches.length, finishOnboardingFlow]);

  const settingsTotal = flow.needsPreferences || s.needsPreferencesOnboarding ? 2 : 1;
  switch (flow.stage) {
    case 'welcome': return <WelcomeStep send={send} />;
    case 'question': return <QuestionStep flow={flow} send={send} />;
    case 'saving': return <SavingStep />;
    case 'saveFailed': return <SaveFailedStep send={send} />;
    case 'reveal':
      return (
        <RevealStep flow={flow} reveal={reveal}
          onContinue={() => send('revealContinue')}
          onOpenEvent={(key) => { pendingEventRef.current = key; send('revealContinue'); }} />
      );
    case 'settings': return <SettingsStep onDone={() => send('settingsDone')} stepIndex={settingsTotal} stepTotal={settingsTotal} />;
    default: return null;
  }
}

export default function EventOnboarding() {
  const { state: s } = useBanBe();
  const active = useEventOnboardingActive();
  if (!active) return null;
  // While the (existing) area sheet is open from the reveal, step aside without unmounting so the flow survives.
  return (
    <div data-testid="event-onboarding-overlay" style={{ position: 'fixed', inset: 0, zIndex: 1900, background: paper, overflowY: 'auto', display: s.areaAsking ? 'none' : 'block', animation: 'banbeFade 0.25s ease both' }}>
      <div style={{ maxWidth: 480, margin: '0 auto', padding: '48px 24px 42px', boxSizing: 'border-box', color: ink }}>
        <OnboardingFlowRunner key={s.user?.id || 'none'} />
      </div>
    </div>
  );
}

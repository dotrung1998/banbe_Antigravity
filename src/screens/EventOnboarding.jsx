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
import { paper, ink, display, fieldGlass, alert } from '../theme.js';
import { StepProgress, encouragement, Button } from '../components/ui/FormControls.jsx';
import { NO_PREFERENCE, BUDGET_TIERS, BUDGET_REGIONS, budgetTierLabel, budgetRegionDefault, normalizeForSave, prefLabel, optionEmoji } from '../lib/eventPrefs.js';
import { QUESTIONS, questionOptions, reduce, draftStore, impactLines, revealMatches, selectionFeedback, payload as flowPayload } from '../lib/onboardingFlow.js';
import { LOCATION_ALL } from '../lib/locationTree.js';
import { track, matchBucket } from '../lib/analytics.js';
import { EventPrefsPrivacyNote } from './EventPreferences.jsx';
import ConfettiBurst from '../components/ui/ConfettiBurst.jsx';

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

// Note 53: one button system. The next step is always the solid primary; an alternative is a secondary (field
// fill + hairline); "skip / later" is text only. Selected answers are tinted, never solid ink, so they can't be
// mistaken for the Continue button.
function InkBtn({ label, enabled = true, onClick, testId }) {
  return <Button variant="primary" testId={testId} label={label} disabled={!enabled} onClick={onClick} style={{ width: '100%' }} />;
}

const SecondaryBtn = ({ label, icon, onClick, testId, disabled }) => (
  <Button variant="secondary" testId={testId} label={label} icon={icon} disabled={disabled} onClick={onClick} style={{ width: '100%', marginTop: 10 }} />
);

const LinkBtn = ({ label, onClick, testId, disabled }) => (
  <Button variant="tertiary" testId={testId} label={label} disabled={disabled} onClick={onClick} style={{ width: '100%', marginTop: 8, fontSize: 14 }} />
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
          detail={T('Tắt trừ khi bạn bật. Nếu bật, host bạn đã tương tác có thể soạn tin quảng bá SMS và tự gửi. banbe không gửi hộ. Đổi lại bất cứ lúc nào tại Tài khoản > Cài đặt > Bảo mật.',
            "Off unless you switch it on. If on, hosts you've interacted with may compose a promo text that they send themselves. banbe doesn't send for them. Change it any time in Account > Settings > Security.")} />
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
  // Entrance (owner, 2026-10-21): the content rises in from below, then the three tiles land one after
  // another, left to right. `.bb-rise` turns all of it off under prefers-reduced-motion.
  const rise = (delayMs) => ({ animation: `bbRiseIn .4s cubic-bezier(.2,.8,.2,1) ${delayMs}ms backwards` });
  // Three glanceable tiles instead of three sentences (note 53). Flex stretches them to one shared height;
  // the title keeps two lines' room so every tile's text starts and sits at the same place.
  const tile = (i, emoji, title, sub) => (
    <div className="bb-rise" style={{ flex: 1, minWidth: 0, background: 'var(--bb-field)', borderRadius: 16, padding: '14px 10px', textAlign: 'center', ...rise(120 + i * 70) }}>
      <div aria-hidden style={{ fontSize: 26, lineHeight: '32px', height: 32 }}>{emoji}</div>
      <div style={{ fontSize: 13, fontWeight: 700, lineHeight: 1.3, marginTop: 6 }}>{title}</div>
      <div style={{ fontSize: 11.5, lineHeight: 1.35, color: muted(0.7), marginTop: 2 }}>{sub}</div>
    </div>
  );
  return (
    <div data-testid="onboarding-welcome">
      <div className="bb-rise" style={rise(0)}>
        <div aria-hidden style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: 84, height: 84, borderRadius: 26, background: 'var(--bb-honey-bg)', fontSize: 42 }}>🌟</div>
        <h1 style={display(30, { margin: '20px 0 0', lineHeight: 1.15 })}>{T('Tìm những buổi bạn thật sự muốn đi', "Find events you'll actually want to go to")}</h1>
        <p style={{ fontSize: 15, lineHeight: 1.55, margin: '10px 0 0', color: muted(0.8) }}>
          {T('5 câu ngắn, rồi banbe gắn ★ Dành cho bạn lên sự kiện hợp với bạn.', '5 quick taps, then banbe stars ★ For You on the events that fit.')}
        </p>
      </div>
      <div style={{ display: 'flex', alignItems: 'stretch', gap: 8, margin: '24px 0 28px' }}>
        {tile(0, '⏱️', T('~1 phút', '~1 minute'), T('Câu nào cũng bỏ qua được', 'Skip any question'))}
        {tile(1, '🔒', T('Chỉ bạn thấy', 'Only you see it'), T('Host không bao giờ thấy', 'Hosts never do'))}
        {tile(2, '⚙️', T('Đổi lúc nào', 'Change anytime'), T('Trong Tài khoản', 'In Account'))}
      </div>
      <div className="bb-rise" style={rise(300)}>
        <InkBtn testId="onboarding-start" label={T('Bắt đầu', 'Get started')} onClick={() => send('start')} />
        <LinkBtn testId="onboarding-skip-all" label={T('Bỏ qua, xem tất cả sự kiện', 'Skip, show me everything')} onClick={() => send('skipAll')} />
      </div>
    </div>
  );
}

// ---- one question per screen ----

// [title, subtitle (one line), step name, hero emoji]. The first question greets by name (note 53: personal,
// conversational, one short line under the title instead of a paragraph).
const QUESTION_COPY = {
  goals: [['Bạn muốn gì từ một buổi đi chơi?', 'What do you want from a night out?'], ['Chọn bao nhiêu cũng được.', 'Pick as many as you like.'], ['Mục tiêu', 'Goals'], '👋'],
  interests: [['Loại sự kiện nào hợp với bạn?', 'Which kinds of events are you into?'], ['Chỉ những loại bạn chọn được gắn ★.', 'Only the kinds you pick get the ★.'], ['Sở thích', 'Interests'], '🎟️'],
  availability: [['Bạn thường rảnh khi nào?', 'When are you usually free?'], ['Giờ khác vẫn hiện, chỉ xếp sau.', 'Other times still show, just lower.'], ['Thời gian', 'Time'], '🗓️'],
  budget: [['Mỗi buổi bạn muốn chi khoảng bao nhiêu?', 'How much do you like to spend per event?'], ['Chọn một mức.', 'Pick one.'], ['Ngân sách', 'Budget'], '💸'],
  languages: [['Bạn thoải mái với ngôn ngữ nào?', 'Which languages are you comfortable with?'], ['Không bắt buộc, chưa dùng để lọc.', "Optional, doesn't filter yet."], ['Ngôn ngữ', 'Language'], '💬'],
};
// Short labels sit in a 2-column grid of emoji tiles; long ones (budget amounts, languages) stay as rows.
const TILE_QUESTIONS = new Set(['goals', 'interests', 'availability']);

/** An answer. Selected = tinted fill + ink outline + check badge + a bigger emoji; never solid ink (that's the CTA). */
function ChoiceRow({ title, emoji, selected, onClick, testId, multi = true, tile = false }) {
  const check = (
    <span aria-hidden style={{
      width: 22, height: 22, borderRadius: multi ? 7 : 11, flex: '0 0 auto', display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      border: `1.5px solid ${selected ? ink : muted(0.3)}`, background: selected ? ink : 'transparent', color: paper, fontSize: 13,
      transition: 'background .15s, border-color .15s',
    }}>{selected ? '✓' : ''}</span>
  );
  const face = (
    <span aria-hidden style={{ fontSize: tile ? 32 : 22, lineHeight: 1, display: 'inline-block',
      transform: selected ? 'scale(1.15)' : 'none', transition: 'transform .25s cubic-bezier(.34,1.56,.64,1)' }}>{emoji}</span>
  );
  const base = {
    position: 'relative', width: '100%', fontFamily: 'inherit', fontSize: 15, cursor: 'pointer', color: ink, borderRadius: 18,
    background: selected ? muted(0.06) : 'var(--bb-field)', border: `1.5px solid ${selected ? ink : 'transparent'}`,
    transition: 'background .15s, border-color .15s',
  };
  if (tile) {
    return (
      <button type="button" onClick={onClick} aria-pressed={selected} data-testid={testId} className="bb-press"
        style={{ ...base, minHeight: 108, padding: '16px 12px 14px', display: 'flex', flexDirection: 'column', alignItems: 'flex-start', justifyContent: 'space-between', gap: 10, textAlign: 'left' }}>
        <span style={{ position: 'absolute', top: 10, right: 10 }}>{check}</span>
        {face}
        <span style={{ fontWeight: selected ? 700 : 500, lineHeight: 1.25 }}>{title}</span>
      </button>
    );
  }
  return (
    <button type="button" onClick={onClick} aria-pressed={selected} data-testid={testId} className="bb-press"
      style={{ ...base, display: 'flex', alignItems: 'center', gap: 14, textAlign: 'left', padding: '13px 16px', minHeight: 56 }}>
      {face}
      <span style={{ flex: 1, fontWeight: selected ? 700 : 500 }}>{title}</span>
      {check}
    </button>
  );
}

function QuestionStep({ flow, send }) {
  const { state: s, T } = useBanBe();
  const vi = s.lang !== 'en';
  const q = QUESTIONS[flow.index];
  const [[titleVi, titleEn], [subVi, subEn], , hero] = QUESTION_COPY[q];
  const last = flow.index + 1 === QUESTIONS.length;
  const picked = flow.draft[q];
  const tiles = TILE_QUESTIONS.has(q);
  // Slide in from the side we're moving towards (iOS parity: questions slide).
  const prevIndex = useRef(flow.index);
  const forward = flow.index >= prevIndex.current;
  useEffect(() => { prevIndex.current = flow.index; }, [flow.index]);
  // Given name: last word of a Vietnamese name ("Nguyễn Văn An" -> An), first word in English.
  const nameParts = flow.index === 0 ? String(s.user?.name || '').trim().split(/\s+/).filter(Boolean) : [];
  const firstName = nameParts.length ? (vi ? nameParts[nameParts.length - 1] : nameParts[0]) : '';
  const title = firstName
    ? T(`Chào ${firstName}! ${titleVi}`, `Hi ${firstName}! ${titleEn}`)
    : T(titleVi, titleEn);
  // Head start (note 48): the account counts as done, so question 1 opens at 1/6 of the bar, not empty.
  const pct = Math.round(((flow.index + 1) / (QUESTIONS.length + 1)) * 100);
  const feedback = selectionFeedback(q, picked, vi);
  return (
    <div data-testid={`onboarding-question-${q}`}>
      {/* One compact progress line (note 53): back, the bar with "2/5", skip. Was three indicators. */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 6 }}>
        <button type="button" onClick={() => send('back')} aria-label={T('Quay lại', 'Back')} data-testid="onboarding-back" className="bb-press"
          style={{ background: 'none', border: 'none', color: ink, fontSize: 24, width: 44, height: 44, marginLeft: -12, cursor: 'pointer', flex: 'none' }}>‹</button>
        <div data-testid="onboarding-progress" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct}
          aria-valuetext={T(`Câu ${flow.index + 1} trên ${QUESTIONS.length}`, `Question ${flow.index + 1} of ${QUESTIONS.length}`)}
          style={{ flex: 1, height: 6, borderRadius: 999, background: muted(0.12), overflow: 'hidden' }}>
          <div style={{ width: `${pct}%`, height: '100%', borderRadius: 999, background: ink, transition: 'width .35s cubic-bezier(.22,.61,.36,1)' }} />
        </div>
        <span style={{ fontSize: 12.5, fontWeight: 700, color: muted(0.7), fontVariantNumeric: 'tabular-nums', flex: 'none' }} data-testid="onboarding-counter">
          {flow.index + 1}/{QUESTIONS.length}
        </span>
        <Button variant="tertiary" testId="onboarding-skip" label={T('Bỏ qua', 'Skip')} onClick={() => send('skipQuestion')} style={{ marginRight: -12, flex: 'none' }} />
      </div>

      <div key={q} className="bb-slide" style={{ animation: `${forward ? 'bbSlideFromRight' : 'bbSlideFromLeft'} .3s cubic-bezier(.22,.61,.36,1) both` }}>
      <div aria-hidden style={{ fontSize: 52, lineHeight: 1, marginTop: 18 }}>{hero}</div>
      <h1 style={display(26, { margin: '14px 0 0', lineHeight: 1.2 })}>{title}</h1>
      <p style={{ fontSize: 14, lineHeight: 1.5, color: muted(0.7), margin: '6px 0 0' }}>{T(subVi, subEn)}</p>

      <div style={tiles ? { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, marginTop: 22 } : { display: 'flex', flexDirection: 'column', gap: 10, marginTop: 22 }}>
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
              <ChoiceRow key={t} multi={false} testId={`onboarding-option-${t}`} title={budgetTierLabel(flow.region, t, vi)} emoji={optionEmoji(t)}
                selected={flow.draft.budget?.tier === t} onClick={() => send({ type: 'pickBudget', tier: t })} />
            ))}
            <ChoiceRow multi={false} testId={`onboarding-option-${NO_PREFERENCE}`} title={T('Không ưu tiên', 'No preference')} emoji={optionEmoji(NO_PREFERENCE)}
              selected={flow.draft.budget?.tier === NO_PREFERENCE} onClick={() => send({ type: 'pickBudget', tier: NO_PREFERENCE })} />
          </>
        ) : (
          <>
            {questionOptions(q).map(o => (
              <ChoiceRow key={o.id} tile={tiles} testId={`onboarding-option-${o.id}`} title={prefLabel(o.id, questionOptions(q), vi)} emoji={optionEmoji(o.id)}
                selected={!!picked?.includes(o.id)} onClick={() => send({ type: 'toggle', question: q, id: o.id })} />
            ))}
            <div style={tiles ? { gridColumn: '1 / -1' } : undefined}>
              <ChoiceRow testId={`onboarding-option-${NO_PREFERENCE}`} title={T('Không ưu tiên', 'No preference')} emoji={optionEmoji(NO_PREFERENCE)}
                selected={!!picked?.includes(NO_PREFERENCE)} onClick={() => send({ type: 'toggle', question: q, id: NO_PREFERENCE })} />
            </div>
          </>
        )}
      </div>
      {/* Live feedback (note 53): each tap answers with what it will do. Reserved height, so nothing jumps. */}
      <p data-testid="onboarding-feedback" aria-live="polite" style={{ minHeight: 20, fontSize: 13, fontWeight: 600, lineHeight: 1.5, color: muted(0.75), margin: '14px 2px 0' }}>
        {feedback || ''}
      </p>
      {last && <div style={{ marginTop: 10 }}><EventPrefsPrivacyNote /></div>}
      </div>
      <div style={{ marginTop: 18 }}>
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
      <SecondaryBtn testId="onboarding-edit-answers" icon="✏️" label={T('Sửa câu trả lời', 'Edit answers')} onClick={() => send('back')} />
      <LinkBtn testId="onboarding-skip-for-now" label={T('Bỏ qua lúc này', 'Skip for now')} onClick={() => send('skipForNow')} />
    </div>
  );
}

// ---- personalized reveal (real matches, real ranking) ----

function revealWhen(startsAt, lang) {
  if (!startsAt) return '';
  return new Date(startsAt).toLocaleString(lang === 'en' ? 'en-GB' : 'vi-VN', { timeZone: 'Asia/Ho_Chi_Minh', weekday: 'short', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
}

// The reveal is the peak of onboarding (note 53, peak-end rule): a short confetti burst when it lands, and the
// natural next ask (♡ Save) right on the cards.
function RevealStep({ flow, reveal, onContinue, onOpenEvent }) {
  const { state: s, T, curArea, loadDiscoveryEvents, pickArea, isSaved, toggleFav } = useBanBe();
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
    <div data-testid="onboarding-reveal" style={{ position: 'relative' }}>
      {!loading && !failed && matches.length > 0 && <ConfettiBurst />}
      <div aria-hidden style={{ fontSize: 44, lineHeight: 1 }}>{!loading && !failed && matches.length > 0 ? '🎉' : '✨'}</div>
      <h1 style={display(30, { margin: '12px 0 0', lineHeight: 1.15 })}>{T('Đây là những gì hợp với bạn', "Here's what fits you")}</h1>
      <div data-testid="onboarding-reveal-impacts" style={{ background: 'var(--bb-field)', borderRadius: 20, padding: 16, marginTop: 18 }}>
        <div style={{ fontSize: 14, fontWeight: 600 }}>{T('Câu trả lời của bạn thay đổi gì', 'What your answers change')}</div>
        {lines.length === 0 && (
          <p style={{ fontSize: 13.5, margin: '8px 0 0' }}>{T('Chưa lọc gì cả: bạn chọn "Không ưu tiên" nên mọi sự kiện đều hiện như bình thường.', 'Nothing is filtered: you chose "No preference", so every event shows as usual.')}</p>
        )}
        {lines.map((l, i) => (
          <div key={i} style={{ display: 'flex', gap: 10, marginTop: 10, fontSize: 13.5, lineHeight: 1.45 }}>
            <span aria-hidden style={{ width: 20, textAlign: 'center' }}>{l.kind === 'filter' ? '🎯' : l.kind === 'ranking' ? '⬆️' : '🔖'}</span>
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
                const saved = isSaved(e.key);
                return (
                  <div key={m.key} style={{ display: 'flex', alignItems: 'center', gap: 4, borderRadius: 16, background: 'var(--bb-field)', paddingRight: 4 }}>
                    <button type="button" onClick={() => onOpenEvent(e.key)} data-testid="onboarding-reveal-event" className="bb-press"
                      style={{ flex: 1, minWidth: 0, display: 'flex', gap: 12, alignItems: 'center', textAlign: 'left', fontFamily: 'inherit', color: ink, padding: 10, borderRadius: 16, border: 'none', background: 'none', cursor: 'pointer' }}>
                      <span aria-hidden style={{ width: 72, height: 72, borderRadius: 12, flex: '0 0 auto', background: e.photoUrl ? `center/cover no-repeat url("${e.photoUrl}")` : muted(0.08) }} />
                      <span style={{ flex: 1, minWidth: 0 }}>
                        <span style={{ display: 'block', fontSize: 14, fontWeight: 600 }}><span aria-hidden style={{ color: '#CC9E29' }}>★ </span>{e.name}</span>
                        <span style={{ display: 'block', fontSize: 12.5, opacity: 0.75, marginTop: 3 }}>{revealWhen(e.startsAt, s.lang)}</span>
                        <span style={{ display: 'block', fontSize: 12.5, opacity: 0.75 }}>{e.priceVnd ? `${String(e.priceVnd).replace(/\B(?=(\d{3})+(?!\d))/g, '.')}₫` : T('Miễn phí', 'Free')}</span>
                      </span>
                    </button>
                    {/* The ask inside the peak: keep the ones you like, one tap. */}
                    <button type="button" onClick={() => toggleFav(e.key)} aria-pressed={saved} data-testid="onboarding-reveal-save" className="bb-press"
                      aria-label={saved ? T(`Bỏ lưu ${e.name}`, `Unsave ${e.name}`) : T(`Lưu ${e.name}`, `Save ${e.name}`)}
                      style={{ flex: 'none', width: 44, height: 44, borderRadius: 999, border: 'none', background: saved ? 'var(--bb-clay-bg)' : 'transparent', color: saved ? 'var(--bb-clay)' : ink, fontSize: 20, cursor: 'pointer' }}>
                      {saved ? '♥' : '♡'}
                    </button>
                  </div>
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

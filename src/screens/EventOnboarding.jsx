// Post-signup personalization, onboarding v5 (note 80; prototype docs/prototypes/banbe-onboarding-v5-standalone.html).
// Web twin of iOS Views/OnboardingFlowViews.swift; pure rules in lib/onboardingFlow.js:
// welcome → What sounds fun? → When are you usually free? → A comfortable ticket price? → save → your For You (never
// empty) → one choice per screen (only when the settings step is owed) → recap with the tour offer → Home, or the
// chaptered tour. Mounted by App.jsx below the account gate; shown only for a signed-in user past
// splash/login/policy whose server markers say a step is still owed (and kept up by `onboardingFlowActive`).
//
// Server contract unchanged: complete_preferences_onboarding(p) (null = skipped everything, marker only) and
// complete_settings_onboarding after the last choice. Each choice writes a real setting only on Continue:
// the weekly digest (set_my_digest_opt_in, while `weekly_digest` is on) and Hosting mode (set_organizer_mode). Web has
// no push permission, so there is no notifications screen here. An unfinished questionnaire is kept in this browser
// for this account (draftStore) and resumed only while the server still owes it.

import { useEffect, useMemo, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { useAccountGate } from '../lib/accountGate.js';
import { supabase } from '../lib/supabase.js';
import { flagOn } from '../lib/featureFlags.js';
import { paper, ink, display } from '../theme.js';
import { Button } from '../components/ui/FormControls.jsx';
import NativeSheet from '../components/NativeSheet.jsx';
import { NO_PREFERENCE, BUDGET_TIERS, BUDGET_REGIONS, INTERESTS, AVAILABILITY, budgetTierLabel, budgetRegionDefault, normalizeForSave, prefLabel, optionEmoji } from '../lib/eventPrefs.js';
import {
  QUESTIONS, reduce, initialState, draftStore, markGuestOnboardingSeen, payload as flowPayload, currentConsent, consentAsksSystem,
  onboardingCandidates, typeCounts, tileTypes, matchCount, optionCount, revealPlan, MIN_FOR_YOU,
} from '../lib/onboardingFlow.js';
import { tourPlan } from '../data/onboardingTour.js';
import { EVENTS } from '../data/events.js';
import { LOCATION_ALL } from '../lib/locationTree.js';
import { track, matchBucket } from '../lib/analytics.js';
import { formatMoney, rowCurrency, rowTimeZone } from '../lib/eventMarket.js';
import ConfettiBurst from '../components/ui/ConfettiBurst.jsx';

const NOT_ONBOARDING_SCREENS = new Set(['splash', 'langPick', 'themePick', 'login', 'resetPassword', 'policy']);
const muted = (a) => `rgba(var(--bb-fg-rgb), ${a})`;
const NIGHT = '#16140f';

/** True while the onboarding overlay is (or should be) on screen; App.jsx hides the dock with it. */
export function useEventOnboardingActive() {
  const { state: s } = useBanBe();
  const { gate } = useAccountGate();
  // Guest preview (note 80): a local-only demo of the same flow, shown before login. Never touches the server.
  if (s.onboardingPreview === 'flow') return true;
  return !!s.user && s.sessionChecked && !s.authSyncing && !s.policyGateActive && gate === 'ready'
    && !NOT_ONBOARDING_SCREENS.has(s.screen)
    && (s.needsSettingsOnboarding || s.needsPreferencesOnboarding || s.onboardingFlowActive);
}

// Note 53: one button system. The next step is always the solid primary; an alternative is a secondary (field
// fill + hairline); "skip / later" is text only.
function InkBtn({ label, enabled = true, onClick, testId }) {
  return <Button variant="primary" testId={testId} label={label} disabled={!enabled} onClick={onClick} style={{ width: '100%' }} />;
}
const SecondaryBtn = ({ label, icon, onClick, testId, disabled, style }) => (
  <Button variant="secondary" testId={testId} label={label} icon={icon} disabled={disabled} onClick={onClick} style={{ width: '100%', marginTop: 10, ...style }} />
);
const LinkBtn = ({ label, onClick, testId, disabled }) => (
  <Button variant="tertiary" testId={testId} label={label} disabled={disabled} onClick={onClick} style={{ width: '100%', marginTop: 4, fontSize: 14 }} />
);

const evN = (n, vi) => (vi ? `${n} sự kiện` : `${n} ${n === 1 ? 'event' : 'events'}`);
const typeLabel = (id, vi) => prefLabel(id, INTERESTS, vi);
/** "A, B and C" / "A, B or C" with the type labels. */
function joinTypes(ids, vi, or = false) {
  const n = ids.map(k => typeLabel(k, vi));
  if (n.length < 2) return n.join('');
  return `${n.slice(0, -1).join(', ')} ${or ? (vi ? 'hoặc' : 'or') : (vi ? 'và' : 'and')} ${n[n.length - 1]}`;
}

function Eyebrow({ children, style }) {
  return <div style={{ fontSize: 'var(--bb-text-kicker)', fontWeight: 600, letterSpacing: '.12em', textTransform: 'uppercase', color: muted(0.62), ...style }}>{children}</div>;
}

/** Back (labelled with where it goes), "1 of 3", and one bar per screen. */
function StepHeader({ label, step, total, backLabel, onBack }) {
  return (
    <div style={{ marginBottom: 18 }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', minHeight: 44 }}>
        {onBack ? (
          <button type="button" onClick={onBack} data-testid="onboarding-back" className="bb-press"
            style={{ background: 'none', border: 'none', color: ink, fontFamily: 'inherit', fontSize: 14, fontWeight: 500, minHeight: 44, marginLeft: -6, padding: '0 6px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 4 }}>
            <span aria-hidden style={{ fontSize: 22, lineHeight: 1 }}>‹</span>{backLabel}
          </button>
        ) : <span />}
        <span data-testid="onboarding-progress" style={{ fontSize: 13, color: muted(0.65), fontVariantNumeric: 'tabular-nums' }}>{label}</span>
      </div>
      <div aria-hidden style={{ display: 'flex', gap: 6, marginTop: 4 }}>
        {Array.from({ length: total }, (_, i) => (
          <i key={i} style={{ flex: 1, height: 3, borderRadius: 2, background: i <= step ? ink : muted(0.14), transition: 'background .3s' }} />
        ))}
      </div>
    </div>
  );
}

// ---- welcome ----

function WelcomeStep({ send }) {
  const { T } = useBanBe();
  const photos = EVENTS.slice(0, 3).map(e => e.img).filter(Boolean);
  const rise = (delayMs) => ({ animation: `bbRiseIn .4s cubic-bezier(.2,.8,.2,1) ${delayMs}ms backwards` });
  const fan = [
    { left: 22, top: 16, width: 148, height: 196, rotate: -5 },
    { right: 24, top: 0, width: 150, height: 186, rotate: 5 },
    { left: '50%', top: 132, width: 176, height: 170, rotate: -1, centered: true },
  ];
  return (
    <div data-testid="onboarding-welcome" style={{ position: 'fixed', inset: 0, background: NIGHT, color: '#fff', overflowY: 'auto', zIndex: 1 }}>
      {photos[0] && (
        <div aria-hidden style={{ position: 'fixed', inset: -30, background: `center/cover no-repeat url("${photos[0]}")`, filter: 'blur(18px) brightness(.42) saturate(.9)', transform: 'scale(1.1)' }} />
      )}
      <div style={{ position: 'relative', maxWidth: 480, margin: '0 auto', padding: '40px 24px 32px', boxSizing: 'border-box', minHeight: '100%', display: 'flex', flexDirection: 'column' }}>
        <div aria-hidden style={{ position: 'relative', height: 318, margin: '6px 0 0' }}>
          {photos.map((p, i) => {
            const f = fan[i];
            return (
              <span key={p} className="bb-rise" style={{
                position: 'absolute', top: f.top, left: f.left, right: f.right, width: f.width, height: f.height, borderRadius: 14,
                background: `center/cover no-repeat url("${p}")`, boxShadow: '0 14px 30px rgba(0,0,0,.35)',
                transform: `${f.centered ? 'translateX(-50%) ' : ''}rotate(${f.rotate}deg)`, ...rise(i * 80),
              }} />
            );
          })}
        </div>
        <div className="bb-rise" style={rise(100)}>
          <h1 style={display(34, { margin: '10px 0 0', lineHeight: 1.12, color: '#fff', fontWeight: 300 })}>
            {T('Những buổi nhỏ, đáng để ra ngoài.', 'Small events worth going out for.')}
          </h1>
          <p style={{ fontSize: 15, lineHeight: 1.5, margin: '10px 0 0', color: 'rgba(255,255,255,.82)' }}>
            {T('Supper club, buổi nghe nhạc, triển lãm. Do host thật tổ chức, mỗi lần vài chỗ.', 'Supper clubs, listening sessions, openings. Run by real hosts, a few seats at a time.')}
          </p>
        </div>
        <div className="bb-rise" style={{ marginTop: 'auto', paddingTop: 28, display: 'grid', gap: 8, ...rise(250) }}>
          <button type="button" data-testid="onboarding-start" onClick={() => send('start')} className="bb-press"
            style={{ height: 50, borderRadius: 999, border: 'none', background: '#fff', color: '#111', fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer' }}>
            {T('Bắt đầu', 'Get started')}
          </button>
          <button type="button" data-testid="onboarding-skip-all" onClick={() => send('skipAll')} className="bb-press"
            style={{ height: 50, borderRadius: 999, border: '1px solid rgba(255,255,255,.85)', background: 'transparent', color: '#fff', fontFamily: 'inherit', fontSize: 15, fontWeight: 500, cursor: 'pointer' }}>
            {T('Bỏ qua, xem tất cả sự kiện', 'Skip, show me everything')}
          </button>
          <p style={{ fontSize: 12.5, textAlign: 'center', color: 'rgba(255,255,255,.65)', margin: '4px 0 0' }}>{T('3 câu hỏi, khoảng một phút', '3 questions, about a minute')}</p>
        </div>
      </div>
    </div>
  );
}

// ---- one question per screen ----

// [title, subtitle (one line), step name, hero emoji]. HowBanbeWorks' quiz card reuses the interests entry.
export const QUESTION_COPY = {
  interests: [['Bạn thấy gì vui?', 'What sounds fun?'], ['Chọn bao nhiêu cũng được. Đây sẽ là gợi ý Dành cho bạn trên Trang chính.', 'Pick any. This becomes your For You on Home.'], ['Sở thích', 'Interests'], '🎟️'],
  availability: [['Bạn thường rảnh khi nào?', 'When are you usually free?'], ['Chọn bao nhiêu cũng được. Giờ khác vẫn hiện, chỉ xếp sau.', 'Pick any. Other times still show, just lower down.'], ['Thời gian', 'Time'], '🗓️'],
  budget: [['Giá vé bao nhiêu thì thoải mái?', 'A comfortable ticket price?'], ['Chọn một mức. Sự kiện đắt hơn sẽ không được gợi ý.', 'Pick one. Pricier events are left out of For You.'], ['Ngân sách', 'Budget'], '💸'],
};

const AVAILABILITY_DETAIL = {
  weekdays: ['Thứ Hai đến thứ Sáu', 'Monday to Friday'],
  weekends: ['Thứ Bảy và Chủ nhật', 'Saturday and Sunday'],
  daytime: ['Bắt đầu trước 17:00', 'Starts before 17:00'],
  evening: ['Bắt đầu từ 17:00', 'Starts at 17:00 or later'],
};

export function ChoiceRow({ title, emoji, selected, onClick, testId, multi = true, tile = false }) {
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

const selectedLook = (on) => ({
  color: ink, fontFamily: 'inherit', cursor: 'pointer', borderRadius: 16,
  background: on ? muted(0.07) : 'var(--bb-field)', border: `${on ? 1.5 : 1}px solid ${on ? ink : 'var(--bb-rule)'}`,
  transition: 'background .15s, border-color .15s',
});

function Tile({ emoji, title, detail, selected, onClick, testId, haspopup }) {
  return (
    <button type="button" onClick={onClick} aria-pressed={haspopup ? undefined : selected} aria-haspopup={haspopup || undefined} data-testid={testId} className="bb-press"
      style={{ ...selectedLook(selected), position: 'relative', minHeight: 96, padding: '12px 4px', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 3, textAlign: 'center' }}>
      {selected && <span aria-hidden style={{ position: 'absolute', top: 6, right: 8, fontSize: 12 }}>✓</span>}
      <span aria-hidden style={{ fontSize: 26, lineHeight: 1.1 }}>{emoji}</span>
      <span style={{ fontSize: 13, fontWeight: selected ? 700 : 500, lineHeight: 1.25 }}>{title}</span>
      {detail != null && <small style={{ fontSize: 'var(--bb-text-meta)', color: muted(0.65) }}>{detail}</small>}
    </button>
  );
}

function CountRow({ title, detail, count, selected, onClick, testId, single }) {
  return (
    <button type="button" onClick={onClick} aria-pressed={selected} data-testid={testId} className="bb-press"
      style={{ ...selectedLook(selected), width: '100%', display: 'flex', alignItems: 'center', gap: 12, textAlign: 'left', padding: '12px 16px', minHeight: 60 }}>
      <span style={{ flex: 1 }}>
        <span style={{ display: 'block', fontSize: 15, fontWeight: selected ? 700 : 500 }}>{title}</span>
        {detail && <small style={{ display: 'block', fontSize: 12.5, opacity: 0.7, marginTop: 2 }}>{detail}</small>}
      </span>
      {count != null && <span data-testid={`${testId}-count`} style={{ fontSize: 12.5, opacity: 0.7, fontVariantNumeric: 'tabular-nums' }}>{count}</span>}
      <span aria-hidden style={{ width: 22, height: 22, borderRadius: single ? 11 : 7, flex: 'none', display: 'grid', placeItems: 'center', fontSize: 13,
        border: `1.5px solid ${selected ? ink : muted(0.3)}`, background: selected ? ink : 'transparent', color: paper }}>{selected ? '✓' : ''}</span>
    </button>
  );
}

/** "More types": every type, searchable. Types with events on now first (most first), then the rest A to Z. */
function TypesPanel({ flow, send, counts, countsReady, onClose }) {
  const { state: s, T } = useBanBe();
  const vi = s.lang !== 'en';
  const [query, setQuery] = useState('');
  const inputRef = useRef(null);
  useEffect(() => { inputRef.current?.focus(); }, []);
  const q = query.trim().toLowerCase();
  const all = INTERESTS.filter(o => !q || o.vi.toLowerCase().includes(q) || o.en.toLowerCase().includes(q));
  const label = (o) => (vi ? o.vi : o.en);
  const live = all.filter(o => (counts[o.id] || 0) > 0).sort((a, b) => (counts[b.id] - counts[a.id]) || label(a).localeCompare(label(b)));
  const rest = all.filter(o => !(counts[o.id] > 0)).sort((a, b) => label(a).localeCompare(label(b)));
  const picked = flow.draft.interests || [];
  const group = (text) => <div style={{ fontSize: 'var(--bb-text-kicker)', fontWeight: 600, letterSpacing: '.12em', textTransform: 'uppercase', color: muted(0.6), margin: '16px 0 4px' }}>{text}</div>;
  const row = (o) => {
    const on = picked.includes(o.id);
    const n = counts[o.id] || 0;
    return (
      <button key={o.id} type="button" aria-pressed={on} data-testid={`onboarding-types-${o.id}`} onClick={() => send({ type: 'toggle', question: 'interests', id: o.id })}
        style={{ width: '100%', display: 'flex', alignItems: 'center', gap: 12, minHeight: 52, padding: 0, border: 'none', borderBottom: '1px solid var(--bb-rule)', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 15, cursor: 'pointer', textAlign: 'left' }}>
        <span aria-hidden style={{ width: 32, fontSize: 20 }}>{optionEmoji(o.id)}</span>
        <span style={{ flex: 1, fontWeight: on ? 600 : 400 }}>{label(o)}</span>
        {countsReady && n > 0 && <small style={{ fontSize: 12.5, opacity: 0.65 }}>{evN(n, vi)}</small>}
        <span aria-hidden style={{ width: 22, height: 22, borderRadius: 11, display: 'grid', placeItems: 'center', fontSize: 12, border: `1.5px solid ${on ? ink : muted(0.3)}`, background: on ? ink : 'transparent', color: paper }}>{on ? '✓' : ''}</span>
      </button>
    );
  };
  return (
    <NativeSheet open onClose={onClose} labelledBy="onboarding-types-title" testId="onboarding-types"
      zIndex={5} scrim="rgba(0,0,0,.4)">
      <div
        style={{ height: 'calc(100% - 60px)', width: '100%', maxWidth: 480, background: paper, color: ink, borderRadius: '26px 26px 0 0', display: 'flex', flexDirection: 'column', boxShadow: '0 -10px 40px rgba(0,0,0,.2)' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '14px 20px 0' }}>
          <h2 id="onboarding-types-title" style={{ fontSize: 19, fontWeight: 600, margin: 0 }}>{T('Mọi loại sự kiện', 'All types')}</h2>
          <button type="button" data-testid="onboarding-types-done" onClick={onClose}
            style={{ minHeight: 44, border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer' }}>{T('Xong', 'Done')}</button>
        </div>
        <div style={{ margin: '10px 20px', display: 'flex', alignItems: 'center', gap: 8, padding: '0 14px', minHeight: 44, borderRadius: 999, background: 'var(--bb-field)' }}>
          <span aria-hidden style={{ opacity: 0.6 }}>⌕</span>
          <input ref={inputRef} value={query} onChange={e => setQuery(e.target.value)} data-testid="onboarding-types-search" autoComplete="off"
            aria-label={T('Tìm loại sự kiện', 'Search event types')}
            placeholder={T(`Tìm ${INTERESTS.length} loại`, `Search ${INTERESTS.length} types`)}
            style={{ flex: 1, border: 'none', outline: 'none', background: 'transparent', color: ink, fontFamily: 'inherit', fontSize: 15, minHeight: 40 }} />
        </div>
        <div style={{ flex: 1, overflowY: 'auto', padding: '0 20px 24px' }}>
          {!live.length && !rest.length && (
            <div style={{ padding: '24px 0' }}>
              <div style={{ fontSize: 16, fontWeight: 600 }}>{T(`Không có loại nào tên “${query}”`, `No type called “${query}”`)}</div>
              <div style={{ fontSize: 14, opacity: 0.7, marginTop: 4 }}>{T('Thử một từ ngắn hơn.', 'Try a shorter word.')}</div>
            </div>
          )}
          {live.length > 0 && <>{group(T('Đang có sự kiện', 'On now'))}{live.map(row)}</>}
          {rest.length > 0 && <>{group(T('Các loại khác, A to Z', 'More types, A to Z'))}{rest.map(row)}</>}
        </div>
      </div>
    </NativeSheet>
  );
}

function QuestionStep({ flow, send, cands, countsReady }) {
  const { state: s, T } = useBanBe();
  const vi = s.lang !== 'en';
  const q = QUESTIONS[flow.index];
  const [[titleVi, titleEn], [subVi, subEn]] = QUESTION_COPY[q];
  const last = flow.index + 1 === QUESTIONS.length;
  const draft = flow.draft;
  const picked = q === 'budget' ? !!draft.budget : (draft[q] || []).length > 0;
  const [typesOpen, setTypesOpen] = useState(false);
  const prevIndex = useRef(flow.index);
  const forward = flow.index >= prevIndex.current;
  useEffect(() => { prevIndex.current = flow.index; }, [flow.index]);

  const counts = useMemo(() => typeCounts(cands), [cands]);
  const feedback = (() => {
    if (!picked) return q === 'interests' ? T('Bỏ qua thì Dành cho bạn bắt đầu với những gì sắp diễn ra.', "Skip it and For You starts with what's on soon.") : '';
    if (q === 'budget') {
      const tier = draft.budget?.tier;
      return tier === 'flexible' ? T('Đã ghi nhận. Không giới hạn giá.', 'Got it. No price limit.')
        : tier === 'free' ? T('Đã ghi nhận. Chỉ sự kiện miễn phí.', 'Got it. Free events only.')
          : T('Đã ghi nhận. Sự kiện đắt hơn sẽ bị bỏ ra.', 'Got it. Pricier events are left out.');
    }
    if (!countsReady) return '';
    if (q === 'interests' && !(draft.interests || []).some(k => counts[k] > 0)) {
      return T('Hiện chưa có buổi nào. Dành cho bạn sẽ bắt đầu với những gì sắp diễn ra, và các loại này hiện lên khi host đăng.',
        "None on right now. For You starts with what's on soon, and these types show up as hosts post them.");
    }
    const n = matchCount(cands, draft);
    if (n === 0) return T('Chưa có gì khớp hết. Dành cho bạn sẽ thêm gợi ý gần đúng.', 'Nothing fits all of that yet. For You will add close picks.');
    if (n < MIN_FOR_YOU) return T(`${n} sự kiện khớp. Dành cho bạn sẽ thêm gợi ý gần đúng.`, `${n} ${n === 1 ? 'event fits' : 'events fit'} so far. For You will add close picks.`);
    return T(`${n} sự kiện khớp đến giờ.`, `${n} events match so far.`);
  })();

  let options;
  if (q === 'interests') {
    const tiles = tileTypes(counts, k => typeLabel(k, vi));
    const sel = draft.interests || [];
    const extra = sel.filter(k => k !== NO_PREFERENCE && !tiles.includes(k));
    options = (
      <>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
          {tiles.map(k => (
            <Tile key={k} testId={`onboarding-option-${k}`} emoji={optionEmoji(k)} title={typeLabel(k, vi)} detail={countsReady ? evN(counts[k] || 0, vi) : null}
              selected={sel.includes(k)} onClick={() => send({ type: 'toggle', question: 'interests', id: k })} />
          ))}
          <Tile testId="onboarding-more-types" emoji="🔍" title={T('Loại khác', 'More types')} haspopup="dialog" selected={extra.length > 0}
            detail={extra.length ? T(`Đã chọn ${extra.length}`, `${extra.length} picked`) : T(`Tìm ${INTERESTS.length} loại`, `${INTERESTS.length} to search`)}
            onClick={() => setTypesOpen(true)} />
        </div>
        {extra.length > 0 && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 12 }}>
            {extra.map(k => (
              <button key={k} type="button" data-testid={`onboarding-chip-${k}`} onClick={() => send({ type: 'toggle', question: 'interests', id: k })}
                aria-label={T(`Bỏ ${typeLabel(k, vi)}`, `Remove ${typeLabel(k, vi)}`)}
                style={{ minHeight: 36, padding: '0 14px', borderRadius: 999, border: 'none', background: ink, color: paper, fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer' }}>
                {typeLabel(k, vi)} ×
              </button>
            ))}
          </div>
        )}
      </>
    );
  } else if (q === 'availability') {
    options = (
      <div style={{ display: 'grid', gap: 8 }}>
        {AVAILABILITY.map(o => (
          <CountRow key={o.id} testId={`onboarding-option-${o.id}`} title={vi ? o.vi : o.en} detail={T(...AVAILABILITY_DETAIL[o.id])}
            count={countsReady ? evN(optionCount(cands, draft, 'availability', o.id, flow.region), vi) : null}
            selected={!!draft.availability?.includes(o.id)} onClick={() => send({ type: 'toggle', question: 'availability', id: o.id })} />
        ))}
      </div>
    );
  } else {
    options = (
      <div style={{ display: 'grid', gap: 8 }}>
        <div role="group" aria-label={T('Loại tiền', 'Currency')} style={{ display: 'flex', gap: 4, padding: 3, borderRadius: 999, background: 'var(--bb-field)', marginBottom: 4 }}>
          {BUDGET_REGIONS.map(r => (
            <button key={r} type="button" aria-pressed={flow.region === r} data-testid={`onboarding-region-${r}`} onClick={() => send({ type: 'setRegion', region: r })}
              style={{ flex: 1, minHeight: 36, borderRadius: 999, border: 'none', fontFamily: 'inherit', fontSize: 13, fontWeight: 600, cursor: 'pointer', background: flow.region === r ? ink : 'transparent', color: flow.region === r ? paper : ink }}>
              {r === 'US' ? 'USD' : 'VND'}
            </button>
          ))}
        </div>
        {BUDGET_TIERS.map(t => (
          <CountRow key={t} single testId={`onboarding-option-${t}`}
            title={t === 'flexible' ? T('Giá nào cũng được', "Price doesn't matter") : budgetTierLabel(flow.region, t, vi)}
            count={countsReady ? evN(optionCount(cands, draft, 'budget', t, flow.region), vi) : null}
            selected={draft.budget?.tier === t} onClick={() => send({ type: 'pickBudget', tier: t })} />
        ))}
      </div>
    );
  }

  return (
    <div data-testid={`onboarding-question-${q}`}>
      <StepHeader label={T(`Câu ${flow.index + 1}/${QUESTIONS.length}`, `${flow.index + 1} of ${QUESTIONS.length}`)} step={flow.index} total={QUESTIONS.length}
        backLabel={flow.index === 0 ? T('Chào mừng', 'Welcome') : T('Quay lại', 'Back')} onBack={() => send('back')} />
      <div key={q} className="bb-slide" style={{ animation: `${forward ? 'bbSlideFromRight' : 'bbSlideFromLeft'} .3s cubic-bezier(.22,.61,.36,1) both` }}>
        <Eyebrow>{T('Dành cho bạn', 'For You')}</Eyebrow>
        <h1 style={display(30, { margin: '8px 0 0', lineHeight: 1.12, fontWeight: 300 })}>{T(titleVi, titleEn)}</h1>
        <p style={{ fontSize: 15, lineHeight: 1.5, color: muted(0.72), margin: '8px 0 22px' }}>{T(subVi, subEn)}</p>
        {options}
        <p data-testid="onboarding-feedback" aria-live="polite" style={{ minHeight: 20, fontSize: 13.5, fontWeight: 600, lineHeight: 1.5, color: 'var(--bb-moss, inherit)', margin: '14px 2px 0' }}>
          {feedback}
        </p>
      </div>
      <div style={{ marginTop: 18 }}>
        <InkBtn testId="onboarding-next" enabled={picked} label={last ? T('Xem gợi ý của tôi', 'Show my picks') : T('Tiếp tục', 'Continue')} onClick={() => send('next')} />
        <LinkBtn testId="onboarding-skip" label={T('Bỏ qua câu này', 'Skip this question')} onClick={() => send('skipQuestion')} />
      </div>
      {typesOpen && q === 'interests' && (
        <TypesPanel flow={flow} send={send} counts={counts} countsReady={countsReady} onClose={() => setTypesOpen(false)} />
      )}
    </div>
  );
}

// ---- saving / failed ----

function SavingStep({ label }) {
  const { T } = useBanBe();
  return (
    <div role="status" data-testid="onboarding-saving" style={{ padding: '120px 0', textAlign: 'center', fontSize: 14 }}>
      {label || T('Đang lưu lựa chọn của bạn…', 'Saving your picks…')}
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

/** The settings marker didn't save. The choices themselves are already written; only "done" is missing. */
function SettingsFailedStep({ send }) {
  const { T, set } = useBanBe();
  return (
    <div data-testid="onboarding-settings-failed">
      <h1 style={display(26, { margin: '40px 0 0' })}>{T('Chưa hoàn tất được', "Couldn't finish setup yet")}</h1>
      <p style={{ fontSize: 14, lineHeight: 1.55, margin: '10px 0 24px' }}>
        {T('Lựa chọn của bạn đã được lưu. Thử lại, hoặc bỏ qua lúc này (bước này có thể hiện lại lần mở sau).',
          'Your choices are saved. Retry, or skip for now (this step may come back next time you open the app).')}
      </p>
      <InkBtn testId="onboarding-settings-retry" label={T('Thử lại', 'Retry')} onClick={() => send('retrySettings')} />
      {/* Session-only, as before: the server marker stays unset. */}
      <LinkBtn testId="onboarding-settings-skip" label={T('Bỏ qua lúc này', 'Skip for now')} onClick={() => { set({ needsSettingsOnboarding: false }); send('skipSettingsForNow'); }} />
    </div>
  );
}

// ---- your For You (the reveal) ----

// In the event's own zone (migration 195): a US event's 19:00 reads 19:00 here too.
function revealWhen(startsAt, lang, timeZone) {
  if (!startsAt) return '';
  return new Date(startsAt).toLocaleString(lang === 'en' ? 'en-GB' : 'vi-VN', { timeZone, weekday: 'short', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
}

/** The payoff before anything is asked. Never empty while any upcoming event exists; each case says which it is. */
function RevealStep({ flow, send, cands }) {
  const { state: s, T, curArea, loadDiscoveryEvents, pickArea, isSaved, toggleFav } = useBanBe();
  const vi = s.lang !== 'en';
  const prefs = s.eventPrefs || normalizeForSave(flow.draft);
  const plan = useMemo(() => revealPlan(cands, prefs), [cands, prefs]);
  const loading = !!s.discoveryEventsLoading && !(s.discoveryEvents || []).length;
  const failed = !!s.discoveryEventsLoadFailed && !(s.discoveryEvents || []).length;
  const areaLimited = curArea.key !== LOCATION_ALL;
  const trackedRef = useRef(false);

  useEffect(() => {
    if (!(s.discoveryEvents || []).length && !s.discoveryEventsLoading) loadDiscoveryEvents();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  useEffect(() => {
    if (trackedRef.current || loading || failed) return;
    trackedRef.current = true;
    track('personalized_results_viewed', { match_bucket: matchBucket(plan.exact) });
  }, [loading, failed, plan.exact]);

  const names = (ids, or) => joinTypes(ids, vi, or);
  const title = loading ? T('Đang tìm sự kiện cho bạn…', 'Finding your events…')
    : plan.mode === 'popular' ? T('Đây là những gì sắp diễn ra', "Here's what's on soon")
      : plan.mode === 'soon' ? T(`Chưa có buổi ${names(plan.waiting)} nào`, `Nothing on for ${names(plan.waiting)} right now`)
        : plan.mode === 'topped' ? (plan.exact === 0 ? T('Chưa có gì khớp mọi câu trả lời', 'Nothing fits every answer yet')
          : T(`${plan.exact} sự kiện khớp, và vài buổi tương tự`, `${plan.exact} close ${plan.exact === 1 ? 'match' : 'matches'}, and more like ${plan.exact === 1 ? 'it' : 'them'}`))
          : T(`${plan.exact} sự kiện chọn cho bạn`, `${plan.exact} events picked for you`);
  const later = plan.waiting.length && plan.mode !== 'soon'
    ? T(` Hiện chưa có buổi ${names(plan.waiting, true)}; chúng sẽ hiện khi host đăng.`, ` Nothing is on for ${names(plan.waiting, true)} yet; those show up as hosts post them.`) : '';
  const sub = plan.mode === 'popular'
    ? T('Bạn bỏ qua phần sở thích, nên danh sách bắt đầu với các sự kiện sớm nhất. Trả lời lúc nào cũng được trong Tài khoản › Sở thích sự kiện.',
      'You skipped what you like, so this starts with the soonest events. Answer any time in Account › Event preferences.')
    : plan.mode === 'soon'
      ? T(`Trong lúc chờ, đây là những sự kiện sớm nhất. Khi host đăng một buổi ${names(plan.waiting, true)}, nó sẽ được gợi ý trước.`,
        `Meanwhile, here are the soonest events. When a host posts ${names(plan.waiting, true)}, it's suggested first.`)
      : plan.mode === 'topped'
        ? T(`${plan.exact ? 'Chỉ vài sự kiện khớp mọi câu trả lời lúc này, nên' : 'Câu trả lời của bạn hơi hẹp lúc này, nên'} danh sách thêm các buổi ${names(plan.live)} khác, rồi đến những gì sắp diễn ra. Buổi khớp nhất luôn đứng đầu.`,
          `${plan.exact ? 'Only a few events fit all your answers right now, so' : 'Your answers are narrow right now, so'} this also shows other ${names(plan.live)} events, then what's on soon. Exact matches stay first.`) + later
        : T(`Chọn từ những gì bạn thích: ${names(plan.live)}. Bật ★ Dành cho bạn trên Trang chính để chỉ xem chúng.`,
          `Picked from what you like: ${names(plan.live)}. Turn on ★ For You on Home to see only these.`) + later;
  const redo = plan.mode === 'popular' ? T('Trả lời các câu hỏi', 'Answer the questions')
    : plan.mode === 'picked' ? T('Đổi câu trả lời', 'Change my answers') : T('Chọn loại khác', 'Pick other types');
  const byKey = new Map((s.discoveryEvents || []).map(e => [e.key, e]));

  return (
    <div data-testid="onboarding-reveal" data-mode={plan.mode} style={{ position: 'relative' }}>
      {!loading && !failed && plan.mode === 'picked' && <ConfettiBurst />}
      <Eyebrow>{T('Dành cho bạn', 'Your For You')}</Eyebrow>
      <h1 data-testid="onboarding-reveal-title" style={display(30, { margin: '8px 0 0', lineHeight: 1.12, fontWeight: 300 })}>{title}</h1>
      {!loading && !failed && <p data-testid="onboarding-reveal-sub" style={{ fontSize: 15, lineHeight: 1.5, color: muted(0.75), margin: '8px 0 0' }}>{sub}</p>}
      <div style={{ marginTop: 22 }}>
        {loading ? (
          <p role="status" data-testid="onboarding-reveal-loading" style={{ fontSize: 14, textAlign: 'center', padding: '40px 0' }}>{T('Đang tìm sự kiện hợp với bạn…', 'Finding events that fit…')}</p>
        ) : failed ? (
          <div data-testid="onboarding-reveal-failed">
            <p style={{ fontSize: 14, margin: 0 }}>{T('Chưa tải được sự kiện. Lựa chọn của bạn đã được lưu.', "Couldn't load events right now. Your answers are saved.")}</p>
            <LinkBtn testId="onboarding-reveal-retry" label={T('Thử lại', 'Try again')} onClick={loadDiscoveryEvents} />
          </div>
        ) : !plan.keys.length ? (
          <div>
            <div data-testid="onboarding-reveal-empty" style={{ fontSize: 16, fontWeight: 600 }}>
              {T(`Hiện chưa có sự kiện sắp tới nào${areaLimited ? ` ở ${curArea.label}` : ''}.`, `No upcoming events yet${areaLimited ? ` in ${curArea.label}` : ''}.`)}
            </div>
            {areaLimited && <LinkBtn testId="onboarding-reveal-all-areas" label={T('Xem ở mọi khu vực', 'Look in all areas')} onClick={() => pickArea(LOCATION_ALL)} />}
          </div>
        ) : (
          <div data-testid="onboarding-reveal-rail" style={{ display: 'flex', gap: 12, overflowX: 'auto', margin: '0 -24px', padding: '0 24px 4px', scrollbarWidth: 'none' }}>
            {plan.keys.map(k => {
              const e = byKey.get(k);
              if (!e) return null;
              const saved = isSaved(e.key);
              return (
                <div key={k} data-testid="onboarding-reveal-event" style={{ flex: '0 0 180px' }}>
                  <div style={{ position: 'relative', height: 210, borderRadius: 14, background: e.photoUrl ? `center/cover no-repeat url("${e.photoUrl}")` : muted(0.08) }}>
                    {/* The ask inside the peak: keep the ones you like, one tap. */}
                    <button type="button" onClick={() => toggleFav(e.key)} aria-pressed={saved} data-testid="onboarding-reveal-save" className="bb-press"
                      aria-label={saved ? T(`Bỏ lưu ${e.name}`, `Unsave ${e.name}`) : T(`Lưu ${e.name}`, `Save ${e.name}`)}
                      style={{ position: 'absolute', top: 4, right: 4, width: 44, height: 44, borderRadius: 999, border: 'none', background: 'rgba(247,244,236,.92)', color: saved ? 'var(--bb-clay)' : '#1B1916', fontSize: 19, cursor: 'pointer' }}>
                      {saved ? '♥' : '♡'}
                    </button>
                  </div>
                  <div style={{ fontSize: 14, fontWeight: 600, marginTop: 8, lineHeight: 1.3 }}>{e.name}</div>
                  <div style={{ fontSize: 12, opacity: 0.7, marginTop: 2 }}>
                    {revealWhen(e.startsAt, s.lang, rowTimeZone(e))} · {e.priceVnd ? formatMoney(e.priceVnd, rowCurrency(e)) : T('Miễn phí', 'Free')}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
      <div style={{ marginTop: 26 }}>
        <InkBtn testId="onboarding-reveal-continue" enabled={!loading} label={T('Tiếp tục', 'Continue')} onClick={() => send('revealContinue')} />
        <LinkBtn testId="onboarding-reveal-redo" label={redo} onClick={() => send('redoAnswers')} />
      </div>
    </div>
  );
}

// ---- one choice per screen ----

const CONSENT_COPY = {
  push: {
    icon: '🔔', eb: ['Thông báo', 'Notifications'], t: ['Biết khi nào cần đi', "Know when it's time to go"],
    lead: ['banbe có thể báo khi có gì mới với vé, thanh toán và tin nhắn của bạn.', 'banbe can tell you when something happens with your tickets, payments and messages.'],
    ticks: [['Chỉ về vé, thanh toán và tin nhắn của bạn', 'Only about your own tickets, payments and messages'], ['Thông báo quảng bá vẫn tắt trừ khi bạn bật', 'Promotional pushes stay off unless you turn them on']],
    fine: ['Tiếp theo, trình duyệt sẽ hỏi. Bạn quyết định ở đó.', 'Next, your browser asks. You decide there.'],
  },
  digest: {
    icon: '✉️', eb: ['Bản tin', 'Weekly digest'], t: ['Sự kiện cuối tuần, mỗi tuần một lần', "This weekend's events, once a week"],
    lead: ['Một bản tin ngắn tối thứ Năm với các sự kiện cuối tuần.', "A short digest on Thursday evening with the weekend's events."],
    ticks: [['Mỗi tuần một lần, tối thứ Năm', 'Once a week, Thursday evening'], ['Là tin quảng bá, nên tắt trừ khi bạn đồng ý', "It's promotional, so it stays off unless you say yes"], ['Đổi trong Tài khoản › Cài đặt › Thông báo', 'Change it in Account › Settings › Notifications']],
    fine: ['Tiếp tục để bật. Để sau thì vẫn tắt.', 'Continue turns this on. Not now keeps it off.'],
  },
  hosting: {
    icon: '🏪', eb: ['Tổ chức', 'Hosting'], t: ['Muốn tự tổ chức sự kiện?', 'Want to host your own events?'],
    lead: ['Chế độ tổ chức thêm công cụ để tạo sự kiện, check-in khách và nhận tiền.', 'Hosting mode adds the tools to create events, check guests in and get paid.'],
    ticks: [['Tạo sự kiện trong khoảng 5 phút', 'Create an event in about 5 minutes'], ['Phần đi chơi vẫn y như cũ', 'Going out stays exactly the same']],
    fine: ['Tiếp tục để bật chế độ tổ chức. Để sau thì ứng dụng gọn hơn.', 'Continue turns on Hosting mode. Not now keeps the app simpler.'],
  },
};

function ConsentStep({ flow, busy, onAnswer }) {
  const { state: s, T } = useBanBe();
  const kind = currentConsent(flow);
  const c = CONSENT_COPY[kind];
  const simple = flagOn(s.featureFlags, 'simple_shell');
  const ticks = kind === 'hosting'
    ? [...c.ticks, simple ? ['Tắt lúc nào cũng được, ngay trên Trang chính', 'Switch it off any time, right on Home'] : ['Tắt lúc nào cũng được, trong Tài khoản', 'Switch it off any time, in Account']]
    : c.ticks;
  return (
    <div data-testid={`onboarding-consent-${kind}`}>
      <StepHeader label={T(`Lựa chọn ${flow.index + 1}/${flow.consents.length}`, `Choice ${flow.index + 1} of ${flow.consents.length}`)} step={flow.index} total={flow.consents.length} />
      <div key={kind} className="bb-slide" style={{ animation: 'bbSlideFromRight .3s cubic-bezier(.22,.61,.36,1) both' }}>
        <div aria-hidden style={{ fontSize: 30, marginTop: 18 }}>{c.icon}</div>
        <Eyebrow style={{ marginTop: 16 }}>{T(...c.eb)}</Eyebrow>
        <h1 style={display(30, { margin: '8px 0 0', lineHeight: 1.12, fontWeight: 300 })}>{T(...c.t)}</h1>
        <p style={{ fontSize: 15, lineHeight: 1.5, color: muted(0.75), margin: '8px 0 0' }}>{T(...c.lead)}</p>
        <ul style={{ listStyle: 'none', padding: 0, margin: '22px 0 0' }}>
          {ticks.map(t => (
            <li key={t[1]} style={{ display: 'flex', gap: 12, padding: '12px 0', borderTop: '1px solid var(--bb-rule)', fontSize: 14, lineHeight: 1.45 }}>
              <span aria-hidden style={{ fontWeight: 700 }}>✓</span><span>{T(...t)}</span>
            </li>
          ))}
        </ul>
      </div>
      <div style={{ marginTop: 22 }}>
        <InkBtn testId="onboarding-consent-continue" enabled={!busy} label={busy ? T('Đang lưu…', 'Saving…') : T('Tiếp tục', 'Continue')} onClick={() => onAnswer(true)} />
        {/* Same size as Continue: saying no is as easy as saying yes. */}
        {!consentAsksSystem(kind) && (
          <SecondaryBtn testId="onboarding-consent-not-now" disabled={busy} label={T('Để sau', 'Not now')} onClick={() => onAnswer(false)} />
        )}
        <p style={{ fontSize: 12.5, textAlign: 'center', color: muted(0.65), margin: '10px 0 0' }}>{T(...c.fine)}</p>
      </div>
    </div>
  );
}

// ---- recap and the tour offer ----

function RecapStep({ flow, send, preview }) {
  const { state: s, T } = useBanBe();
  const simple = flagOn(s.featureFlags, 'simple_shell');
  const chapters = tourPlan({ organizerMode: !!s.organizerMode, simpleShell: simple }).map(c => c.chapter);
  const p = flowPayload(flow) || (s.eventPrefs && Object.keys(normalizeForSave(s.eventPrefs)).length > 1 ? s.eventPrefs : null);
  const nTypes = (p?.interests || []).filter(x => x !== NO_PREFERENCE).length;
  const forYou = !p ? null : nTypes ? T(`${nTypes} loại`, `${nTypes} ${nTypes === 1 ? 'type' : 'types'}`) : T('Đã lưu', 'Saved');
  const row = (id, icon, title, where, value, on) => (
    <div data-testid={`onboarding-recap-${id}`} style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 0', borderBottom: '1px solid var(--bb-rule)' }}>
      <span aria-hidden style={{ width: 24, textAlign: 'center' }}>{icon}</span>
      <span style={{ flex: 1 }}>
        <span style={{ display: 'block', fontSize: 15 }}>{title}</span>
        <small style={{ display: 'block', fontSize: 12, color: muted(0.62) }}>{where}</small>
      </span>
      <span data-testid={`onboarding-recap-${id}-value`} style={{ fontSize: 14, fontWeight: on ? 600 : 400, color: on ? ink : muted(0.62) }}>{value}</span>
    </div>
  );
  return (
    <div data-testid="onboarding-recap">
      <Eyebrow style={{ marginTop: 6 }}>{T('Xong', 'Done')}</Eyebrow>
      <h1 style={display(30, { margin: '8px 0 0', fontWeight: 300 })}>{T('Bạn đã sẵn sàng', "You're all set")}</h1>
      <p style={{ fontSize: 15, color: muted(0.75), margin: '8px 0 0' }}>{T('Đây là những gì bạn chọn. Đổi lúc nào cũng được.', "Here's what you chose. All of it can change later.")}</p>
      <div style={{ marginTop: 20 }}>
        {row('foryou', '✨', T('Dành cho bạn', 'For You'), T('Tài khoản › Sở thích sự kiện', 'Account › Event preferences'), forYou || T('Chưa đặt', 'Not set yet'), !!forYou)}
        {flow.consents.includes('digest') && row('digest', '✉️', T('Bản tin cuối tuần', 'Weekly digest'), T('Tài khoản › Cài đặt › Thông báo', 'Account › Settings › Notifications'),
          flow.choices.digest ? T('Bật', 'On') : T('Tắt', 'Off'), !!flow.choices.digest)}
        {row('hosting', '🏪', T('Chế độ tổ chức', 'Hosting mode'), simple ? T('Trang chính, nút Tổ chức', 'Home, the Hosting switch') : T('Tài khoản, dưới tên bạn', 'Account, under your name'),
          s.organizerMode ? T('Bật', 'On') : T('Tắt', 'Off'), !!s.organizerMode)}
      </div>
      <div style={{ marginTop: 22, padding: 18, borderRadius: 16, background: 'var(--bb-field)' }}>
        <div style={{ fontSize: 16, fontWeight: 500 }}>{T('Xem hướng dẫn, khoảng 2 phút', 'Take the tour, about 2 minutes')}</div>
        <div style={{ fontSize: 13.5, lineHeight: 1.5, color: muted(0.75), marginTop: 4 }}>
          {T(`${chapters.length} chương ngắn trên chính các màn hình thật. Chỉ đi tới, và bạn có thể dừng sau mỗi chương.`,
            `${chapters.length} short chapters on the real screens. It only goes forward, and you can stop after any chapter.`)}
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 12 }}>
          {chapters.map(c => <span key={c.id} style={{ fontSize: 12, fontWeight: 600, padding: '5px 10px', borderRadius: 999, background: paper }}>{T(...c.name)}</span>)}
        </div>
      </div>
      <div style={{ marginTop: 22 }}>
        <InkBtn testId="onboarding-recap-tour" label={T('Bắt đầu hướng dẫn', 'Start the tour')} onClick={() => send('startTour')} />
        <LinkBtn testId="onboarding-recap-home" label={preview ? T('Bỏ qua, xem sự kiện', 'Skip, browse events') : T('Bỏ qua, về Trang chính', 'Skip, go to Home')} onClick={() => send('skipTour')} />
        {preview && <p data-testid="onboarding-preview-note" style={{ fontSize: 12.5, textAlign: 'center', color: muted(0.65), margin: '8px 0 0' }}>{T('Bạn chưa đăng nhập: chưa có gì được lưu. Tạo tài khoản để giữ lựa chọn.', 'You are not logged in, so nothing was saved. Create an account to keep these.')}</p>}
      </div>
    </div>
  );
}

// ---- the flow ----

/** The choice screens this run can honestly show, decided once when the flow opens. */
function consentsFor(s) {
  if (!s.needsSettingsOnboarding) return [];
  const out = [];
  if (flagOn(s.featureFlags, 'weekly_digest')) out.push('digest');
  if (!s.organizerMode) out.push('hosting');
  return out;
}

function OnboardingFlowRunner({ preview = false }) {
  const { state: s, set, browseAsGuest, curArea, loadDiscoveryEvents, completePreferencesOnboarding, saveEventPreferences, completeSettingsOnboarding, applyOrganizerMode, finishOnboardingFlow } = useBanBe();
  const uid = s.user?.id;
  const [flow, setFlow] = useState(() => (preview
    ? initialState({ needsPreferences: true, needsSettings: true, region: budgetRegionDefault(), consents: ['digest', 'hosting'] })
    : draftStore.resume(uid, {
      needsPreferences: s.needsPreferencesOnboarding, needsSettings: s.needsSettingsOnboarding, region: budgetRegionDefault(), consents: consentsFor(s),
    })));
  const [consentBusy, setConsentBusy] = useState(false);
  const flowRef = useRef(flow);
  flowRef.current = flow;
  const finishedRef = useRef(false);
  const live = useRef({});
  live.current = { needsPreferences: s.needsPreferencesOnboarding };

  // Keep the overlay up through the recap even after the server markers clear, but never re-arm it once the flow
  // has finished (finishOnboardingFlow clears the flag while this runner is still mounted).
  useEffect(() => {
    if (preview) return;
    if (!s.onboardingFlowActive && flow.stage !== 'finished' && !finishedRef.current) set({ onboardingFlowActive: true });
  }, [s.onboardingFlowActive, flow.stage, set]);

  useEffect(() => { if (!preview) draftStore.save(flow, uid); }, [flow, uid, preview]);

  const send = (action) => {
    const { state, effects } = reduce(flowRef.current, action);
    flowRef.current = state;
    setFlow(state);
    for (const e of effects) {
      if (e.type === 'track') track(e.name, e.props);
      // Preview: every write is answered locally, no RPC is ever called.
      if (preview && (e.type === 'save' || e.type === 'completeSettings')) {
        send(e.type === 'save' ? 'saveSucceeded' : 'settingsSucceeded');
        continue;
      }
      if (e.type === 'save') {
        // "Change my answers" after the first save: the marker is already set, so a plain save (skipping every
        // question there keeps the answers already saved).
        const save = live.current.needsPreferences ? completePreferencesOnboarding(e.payload)
          : e.payload ? saveEventPreferences(e.payload) : Promise.resolve(true);
        save.then(ok => send(ok ? 'saveSucceeded' : 'saveFailed'));
      }
      if (e.type === 'completeSettings') completeSettingsOnboarding().then(ok => send(ok ? 'settingsSucceeded' : 'settingsFailed'));
    }
  };

  // A flow that opens on work (only the settings marker is owed and there's nothing to ask) starts it here.
  useEffect(() => {
    if (!preview && flow.stage === 'settingsSaving') completeSettingsOnboarding().then(ok => send(ok ? 'settingsSucceeded' : 'settingsFailed'));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /** A choice screen's button. Continue writes the setting; Not now writes nothing (every choice is already off). */
  const answer = async (yes) => {
    const kind = currentConsent(flowRef.current);
    if (!kind || consentBusy) return;
    if (!yes) { send({ type: 'consentAnswered', kind, on: false }); return; }
    if (preview) { send({ type: 'consentAnswered', kind, on: true }); return; }
    setConsentBusy(true);
    let on = false;
    try {
      if (kind === 'digest') {
        const { data, error } = await supabase.rpc('set_my_digest_opt_in', { p_enabled: true }).then(r => r, () => ({ data: null, error: true }));
        on = !error && data?.success === true;
      } else if (kind === 'hosting') {
        on = !!(await applyOrganizerMode(true));
      }
    } finally { setConsentBusy(false); }
    send({ type: 'consentAnswered', kind, on });
  };

  const areaMatch = curArea.key === LOCATION_ALL ? null : curArea.match;
  const cands = useMemo(() => onboardingCandidates(s.discoveryEvents, areaMatch), [s.discoveryEvents, areaMatch]);
  const countsReady = (s.discoveryEvents || []).length > 0;

  useEffect(() => {
    if (flow.stage === 'question' && !(s.discoveryEvents || []).length && !s.discoveryEventsLoading && !s.discoveryEventsLoadFailed) loadDiscoveryEvents();
  }, [flow.stage]); // eslint-disable-line react-hooks/exhaustive-deps

  // Hand-off once the flow is done: the overlay closes, For You turns on only with real matches.
  const exactMatches = useMemo(() => {
    const prefs = s.eventPrefs || normalizeForSave(flow.draft);
    return revealPlan(cands, prefs).exact;
  }, [cands, s.eventPrefs, flow.draft]);
  useEffect(() => {
    if (flow.stage !== 'finished' || finishedRef.current) return;
    finishedRef.current = true;
    if (preview) {
      // Preview ends at sign-up (or in the tour over guest Home). Nothing was written, so no marker.
      // Guest first run: nothing was written, so no server marker. Remember on this device that it was shown.
      markGuestOnboardingSeen();
      if (flow.tourRequested) { browseAsGuest(); set({ onboardingPreview: 'tour', screen: 'home', tourRecapStartToken: Date.now() }); }
      else { set({ onboardingPreview: false }); browseAsGuest(); }
      return;
    }
    draftStore.clear(uid);
    const answered = flowPayload(flow) != null;
    finishOnboardingFlow({ showForYou: answered, hasMatches: exactMatches > 0, openEventKey: null, answeredPreferences: answered, startTour: flow.tourRequested });
  }, [flow, uid, exactMatches, finishOnboardingFlow]);

  switch (flow.stage) {
    case 'welcome': return <WelcomeStep send={send} />;
    case 'question': return <QuestionStep flow={flow} send={send} cands={cands} countsReady={countsReady} />;
    case 'saving': return <SavingStep />;
    case 'saveFailed': return <SaveFailedStep send={send} />;
    case 'reveal': return <RevealStep flow={flow} send={send} cands={cands} />;
    case 'consent': return <ConsentStep flow={flow} busy={consentBusy} onAnswer={answer} />;
    case 'settingsSaving': return <SavingStep label={s.lang === 'en' ? 'Saving your choices…' : 'Đang lưu lựa chọn của bạn…'} />;
    case 'settingsFailed': return <SettingsFailedStep send={send} />;
    case 'recap': return <RecapStep flow={flow} send={send} preview={preview} />;
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
      <div style={{ maxWidth: 480, margin: '0 auto', padding: '40px 24px 42px', boxSizing: 'border-box', color: ink }}>
        <OnboardingFlowRunner key={s.onboardingPreview === 'flow' ? 'preview' : (s.user?.id || 'none')} preview={s.onboardingPreview === 'flow'} />
      </div>
    </div>
  );
}

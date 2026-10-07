// Account > Event preferences, plus the shared chips form the onboarding
// questions step also renders (web port of iOS EventPreferencesViews.swift,
// note 34). One form component for both entry points so they cannot drift.
// Answers are private to the account and never shown to hosts.

import { useEffect, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, rule, display, fieldSolid, inkButton, alert } from '../theme.js';
import {
  INTERESTS, GOALS, AVAILABILITY, LANGUAGES, BUDGET_TIERS, NO_PREFERENCE, BUDGET_REGIONS,
  toggleMulti, pickBudgetTier, budgetTierLabel, budgetRegionDefault, budgetRegionForCurrency,
  budgetRegionCurrency, normalizeForSave, prefsEqual,
} from '../lib/eventPrefs.js';

const small = { fontSize: 11.5, lineHeight: 1.55, color: ink, opacity: 0.7 };

function Chip({ text, selected, onClick, testId, compact }) {
  return (
    <button
      type="button" onClick={onClick} data-testid={testId} aria-pressed={selected}
      style={{
        fontFamily: 'inherit', cursor: 'pointer', textAlign: 'left',
        fontSize: compact ? 11.5 : 13, fontWeight: selected ? 600 : 400,
        padding: compact ? '6px 10px' : '9px 14px', borderRadius: 999,
        color: selected ? paper : ink, background: selected ? ink : fieldSolid,
        border: selected ? `1px solid ${ink}` : `1px solid ${rule}`,
      }}
    >{text}</button>
  );
}

/** The five questions as localized chips. `prefs` is the draft object; `onChange(next)` receives a new object. */
export function EventPreferencesForm({ prefs, onChange, region, onRegionChange }) {
  const { T, EN } = useBanBe();
  const vi = !EN;

  const setField = (field, value) => {
    const next = { ...prefs };
    if (value === undefined) delete next[field]; else next[field] = value;
    onChange(next);
  };

  const question = (title, field, options) => (
    <div key={field} data-testid={`prefs-q-${field}`}>
      <div style={{ fontSize: 13.5, fontWeight: 600, color: ink }}>{title}</div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 10 }}>
        {options.map(o => (
          <Chip key={o.id} text={vi ? o.vi : o.en} selected={(prefs[field] || []).includes(o.id)}
            testId={`prefs-${field}-${o.id}`} onClick={() => setField(field, toggleMulti(prefs[field], o.id))} />
        ))}
        <Chip text={T('Không ưu tiên', 'No preference')} selected={(prefs[field] || [])[0] === NO_PREFERENCE}
          testId={`prefs-${field}-no_preference`} onClick={() => setField(field, toggleMulti(prefs[field], NO_PREFERENCE))} />
      </div>
    </div>
  );

  const pickRegion = (r) => {
    onRegionChange(r);
    if (prefs.budget?.currency) setField('budget', { ...prefs.budget, currency: budgetRegionCurrency(r) });
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 26 }} data-testid="event-preferences-form">
      {question(T('Bạn quan tâm loại sự kiện nào?', 'Which events interest you?'), 'interests', INTERESTS)}
      {question(T('Bạn muốn gì từ sự kiện?', 'What do you want from events?'), 'goals', GOALS)}
      {question(T('Bạn thường rảnh khi nào?', 'When are you usually free?'), 'availability', AVAILABILITY)}
      <div data-testid="prefs-q-budget">
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
          <div style={{ fontSize: 13.5, fontWeight: 600, color: ink }}>{T('Ngân sách mỗi sự kiện', 'Budget per event')}</div>
          <div style={{ display: 'flex', gap: 6 }}>
            {BUDGET_REGIONS.map(r => (
              <Chip key={r} compact text={r === 'VN' ? 'VND' : 'USD'} selected={region === r}
                testId={`prefs-budget-region-${r}`} onClick={() => pickRegion(r)} />
            ))}
          </div>
        </div>
        <div style={{ ...small, marginTop: 8 }}>
          {region === 'VN'
            ? T('Khoảng giá tính theo đồng (VND).', 'Ranges are in Vietnamese dong (VND).')
            : T('Khoảng giá tính theo đô la Mỹ (USD).', 'Ranges are in US dollars (USD).')}
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 10 }}>
          {[...BUDGET_TIERS, NO_PREFERENCE].map(t => (
            <Chip key={t} text={budgetTierLabel(region, t, vi)} selected={prefs.budget?.tier === t}
              testId={`prefs-budget-${t}`} onClick={() => setField('budget', pickBudgetTier(prefs.budget, t, region))} />
          ))}
        </div>
      </div>
      {question(T('Ngôn ngữ sự kiện bạn thích', 'Event languages you prefer'), 'languages', LANGUAGES)}
    </div>
  );
}

/** Privacy footer shared by both entry points. */
export function EventPrefsPrivacyNote() {
  const { T } = useBanBe();
  return (
    <p data-testid="prefs-privacy-note" style={{ ...small, margin: 0 }}>
      {T('Câu trả lời chỉ thuộc về tài khoản của bạn và không bao giờ hiển thị cho host. Đây là sở thích bạn tự khai, không phải thông tin đã được xác minh.',
        'Your answers are private to your account and never shown to hosts. They are self-declared preferences, not verified credentials.')}
    </p>
  );
}

export default function EventPreferences() {
  const { state: s, T, set, saveEventPreferences, loadEventPreferences } = useBanBe();
  const [draft, setDraft] = useState(() => s.eventPrefs || {});
  const [baseline, setBaseline] = useState(() => s.eventPrefs || {});
  const [region, setRegion] = useState(() => (s.eventPrefs?.budget?.currency ? budgetRegionForCurrency(s.eventPrefs.budget.currency) : budgetRegionDefault()));
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [failed, setFailed] = useState(false);
  const seededLoaded = useRef(s.eventPrefsLoaded);

  // A cold deep link can arrive before the preferences have loaded: fetch, then
  // seed once (never over edits the user already made).
  useEffect(() => {
    if (!s.eventPrefsLoaded && s.user?.id) loadEventPreferences();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  useEffect(() => {
    if (!s.eventPrefsLoaded || seededLoaded.current) return;
    seededLoaded.current = true;
    const p = s.eventPrefs || {};
    setDraft(d => (prefsEqual(d, baseline) ? p : d));
    setBaseline(p);
    if (p.budget?.currency) setRegion(budgetRegionForCurrency(p.budget.currency));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [s.eventPrefsLoaded]);

  const fromReservation = !!s.eventPrefsReturnScreen;
  const changed = !prefsEqual(draft, baseline);

  const goBack = () => {
    if (s.eventPrefsReturnScreen) set({ screen: s.eventPrefsReturnScreen, eventPrefsReturnScreen: null });
    else set({ screen: 'accountGroup', accountGroupKey: 'preferences' });
  };
  const edit = (next) => { setDraft(next); setSaved(false); setFailed(false); };

  const save = async () => {
    if (saving) return;
    setSaving(true); setSaved(false); setFailed(false);
    // Nothing changed (only reachable from the reservation prompt): just go back.
    if (!changed) { setSaving(false); if (fromReservation) goBack(); return; }
    const ok = await saveEventPreferences(draft);
    setSaving(false);
    if (ok) {
      setBaseline(normalizeForSave(draft)); setSaved(true);
      if (fromReservation) goBack();
    } else setFailed(true);
  };

  const enabled = !saving && (changed || fromReservation);
  const label = saving ? T('Đang lưu…', 'Saving…') : fromReservation ? T('Lưu và quay lại', 'Save and go back') : T('Lưu', 'Save');

  return (
    <div style={{ animation: 'banbeFade 0.32s ease both', minHeight: '100%', background: paper }} data-screen-label="EventPreferences" data-testid="event-preferences-screen">
      <div onClick={goBack} data-testid="prefs-back" style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>
        ‹ {s.eventPrefsReturnScreen ? T('Quay lại', 'Back') : T('Cài Đặt', 'Settings')}
      </div>
      <div style={{ padding: '16px 30px 42px' }}>
        <h1 style={display(27, { margin: 0, lineHeight: 1.2 })}>{T('Sở thích sự kiện', 'Event preferences')}</h1>
        <p style={{ fontSize: 13.5, lineHeight: 1.55, color: ink, margin: '10px 0 0' }}>
          {T('Dùng để gợi ý sự kiện phù hợp cho bạn. Câu nào cũng có thể bỏ qua.', 'Used to suggest events that suit you. Every question is optional.')}
        </p>
        <div style={{ marginTop: 24 }}>
          <EventPreferencesForm prefs={draft} onChange={edit} region={region} onRegionChange={setRegion} />
        </div>
        <div style={{ marginTop: 22 }}><EventPrefsPrivacyNote /></div>
        {failed && <p data-testid="prefs-save-error" style={{ fontSize: 12, color: alert, margin: '14px 0 0' }}>{T('Chưa lưu được. Vui lòng thử lại.', "Couldn't save. Please try again.")}</p>}
        {saved && !failed && <p data-testid="prefs-save-ok" style={{ fontSize: 12, color: ink, margin: '14px 0 0' }}>{T('Đã lưu sở thích.', 'Preferences saved.')}</p>}
        <div
          onClick={enabled ? save : undefined} role="button" aria-disabled={!enabled} data-testid="prefs-save"
          style={{ ...inkButton({ marginTop: 16, borderRadius: 18, padding: 15, fontSize: 15 }), opacity: enabled ? 1 : 0.45, cursor: enabled ? 'pointer' : 'default' }}
        >{label}</div>
      </div>
    </div>
  );
}

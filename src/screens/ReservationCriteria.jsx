// Host "Reservation criteria" picker + guest "unmet criteria" card + shared
// guest hook (web port of iOS ReservationCriteriaViews.swift, note 34).
// Criteria are eligibility rules on SELF-DECLARED interests/goals only.
// A guest's answers are never shown to hosts.

import { useEffect } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, rule, fieldSolid, inkButton, alert } from '../theme.js';
import {
  INTERESTS, GOALS, everyone, normalizeCriteria, criteriaIsEveryone, criteriaSummary, eligibilityGuidance, evaluateCriteria,
} from '../lib/eventPrefs.js';

const small = { fontSize: 11.5, lineHeight: 1.55, color: ink, opacity: 0.7 };

function Chip({ text, selected, onClick, testId }) {
  return (
    <button
      type="button" onClick={onClick} data-testid={testId} aria-pressed={selected}
      style={{
        fontFamily: 'inherit', cursor: 'pointer', fontSize: 12.5, fontWeight: selected ? 600 : 400,
        padding: '8px 13px', borderRadius: 999,
        color: selected ? paper : ink, background: selected ? ink : fieldSolid,
        border: selected ? `1px solid ${ink}` : `1px solid ${rule}`,
      }}
    >{text}</button>
  );
}

function Group({ kind, title, options, group, onChange, vi, T }) {
  const values = group?.values || [];
  const rule_ = group?.rule === 'all' ? 'all' : 'any';
  const toggle = (id) => {
    const next = values.includes(id) ? values.filter(v => v !== id) : [...values, id];
    onChange(next.length ? { rule: rule_, values: next } : null);
  };
  const setRule = (r) => onChange({ rule: r, values });
  return (
    <div style={{ marginTop: 14 }} data-testid={`criteria-group-${kind}`}>
      <div style={{ fontSize: 12.5, fontWeight: 600, color: ink }}>{title}</div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, marginTop: 8 }}>
        {options.map(o => (
          <Chip key={o.id} text={vi ? o.vi : o.en} selected={values.includes(o.id)} onClick={() => toggle(o.id)} testId={`criteria-${kind}-${o.id}`} />
        ))}
      </div>
      {values.length === 0 ? (
        <p style={{ ...small, margin: '8px 0 0' }}>{T('Không chọn gì nghĩa là không giới hạn theo nhóm này.', 'Selecting nothing means no restriction on this group.')}</p>
      ) : (
        <>
          <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
            <Chip text={T('Một trong số này', 'Any of these')} selected={rule_ === 'any'} onClick={() => setRule('any')} testId={`criteria-${kind}-rule-any`} />
            <Chip text={T('Tất cả những mục này', 'All of these')} selected={rule_ === 'all'} onClick={() => setRule('all')} testId={`criteria-${kind}-rule-all`} />
          </div>
          <p style={{ ...small, margin: '6px 0 0' }}>
            {rule_ === 'any'
              ? T('Khách cần đã khai báo ít nhất một mục bạn chọn.', 'Guests need to have declared at least one of your picks.')
              : T('Khách cần đã khai báo tất cả các mục bạn chọn.', 'Guests need to have declared every one of your picks.')}
          </p>
        </>
      )}
    </div>
  );
}

/** Host form section. `criteria` is the form value; `onChange(next)` receives a new criteria object. */
export function ReservationCriteriaPicker({ criteria, onChange, loadState }) {
  const { T, EN } = useBanBe();
  const vi = !EN;
  const declared = !criteriaIsEveryone(criteria) || criteria?.mode === 'declared';
  const c = criteria || everyone();
  const setGroup = (kind, g) => {
    const next = { version: 1, mode: 'declared', interests: c.interests || null, goals: c.goals || null };
    next[kind] = g;
    onChange(next);
  };
  const empty = declared && !normalizeCriteria(c).interests && !normalizeCriteria(c).goals;
  return (
    <div style={{ marginTop: 0 }} data-testid="create-criteria">
      <label style={{ fontSize: 11.5, color: ink }}>{T('Điều kiện đặt chỗ', 'Reservation criteria')}</label>
      <div style={{ display: 'flex', gap: 8, marginTop: 6 }}>
        {[
          { key: 'everyone', vi: 'Mọi người', en: 'Everyone' },
          { key: 'declared', vi: 'Người đã khai báo...', en: 'Only people who declare...' },
        ].map(opt => {
          const on = (opt.key === 'declared') === declared;
          return (
            <button
              key={opt.key} type="button" data-testid={`create-criteria-${opt.key}`} aria-pressed={on}
              disabled={loadState === 'loading'}
              onClick={() => onChange(opt.key === 'declared' ? { version: 1, mode: 'declared', interests: c.interests || null, goals: c.goals || null } : everyone())}
              style={{
                flex: 1, padding: '10px 12px', borderRadius: 10, fontSize: 13, cursor: 'pointer', fontFamily: 'inherit',
                border: `1px solid ${on ? ink : rule}`, background: on ? ink : 'transparent', color: on ? paper : ink,
              }}
            >{T(opt.vi, opt.en)}</button>
          );
        })}
      </div>
      {loadState === 'loading' && <p style={{ ...small, margin: '6px 0 0' }}>{T('Đang tải điều kiện hiện tại…', 'Loading current criteria…')}</p>}
      {loadState === 'failed' && <p style={{ fontSize: 11.5, color: alert, margin: '6px 0 0' }} data-testid="create-criteria-load-failed">{T('Không tải được điều kiện hiện tại. Hãy mở lại sự kiện để sửa.', 'Could not load the current criteria. Reopen the event to edit it.')}</p>}
      {declared && (
        <>
          <Group kind="interests" title={T('Sở thích', 'Interests')} options={INTERESTS} group={c.interests} onChange={(g) => setGroup('interests', g)} vi={vi} T={T} />
          <Group kind="goals" title={T('Mục tiêu', 'Goals')} options={GOALS} group={c.goals} onChange={(g) => setGroup('goals', g)} vi={vi} T={T} />
          {empty && <p style={{ ...small, margin: '12px 0 0' }} data-testid="create-criteria-empty-hint">{T('Chưa chọn mục nào, sự kiện vẫn mở cho mọi người.', 'Nothing selected yet, so the event stays open to everyone.')}</p>}
        </>
      )}
      <p style={{ ...small, margin: '10px 0 0' }}>
        {T('Dựa trên thông tin khách tự khai báo, không được xác minh, khách có thể thay đổi. Không dùng cho ngân sách, lịch, ngôn ngữ hay độ tuổi.', 'Based on what guests declare about themselves: unverified and editable by them. Not used for budget, schedule, language or age.')}
      </p>
      <p style={{ fontSize: 12, fontWeight: 600, color: ink, margin: '6px 0 0' }} data-testid="create-criteria-summary">
        {T('Ai có thể đặt: ', 'Who can reserve: ')}{criteriaSummary(normalizeCriteria(c), vi)}
      </p>
    </div>
  );
}

/**
 * Guest-side state for one event. `eligibility` is null until known; `blocked` is
 * true only when the server said ineligible. Re-checks whenever `eventPrefsVersion`
 * changes (the screen's own mount re-checks on return).
 * `alwaysCheck`: pre-check even when the cached criteria say Everyone (reserve screen).
 */
export function useReservationCriteria(eventKey, { alwaysCheck = false, isReal = true } = {}) {
  const { state: s, loadEventCriteria, checkReservationEligibility } = useBanBe();
  const criteria = s.eventCriteriaByKey[eventKey];
  const restricted = criteria ? !criteriaIsEveryone(criteria) : false;
  useEffect(() => {
    if (!eventKey || !isReal) return;
    loadEventCriteria(eventKey);
  }, [eventKey, isReal, loadEventCriteria, s.eventPrefsVersion]);
  useEffect(() => {
    if (!eventKey || !isReal || !s.user) return;
    if (alwaysCheck || restricted) checkReservationEligibility(eventKey);
  }, [eventKey, isReal, s.user, alwaysCheck, restricted, s.eventPrefsVersion, checkReservationEligibility]);
  // Server answer wins; until it arrives (or if the RPC call fails) fall back to the same rule locally
  // so a restricted event never looks open to someone who doesn't qualify.
  const elig = s.eligibilityByKey[eventKey]
    || (restricted && s.user && s.eventPrefsLoaded ? evaluateCriteria(criteria, s.eventPrefs) : null);
  return { criteria, restricted, eligibility: elig, blocked: !!elig && elig.eligible === false };
}

/** "Who can reserve: ..." line for restricted events only. */
export function WhoCanReserve({ criteria, style }) {
  const { T, EN } = useBanBe();
  if (!criteria || criteriaIsEveryone(criteria)) return null;
  return (
    <div style={{ fontSize: 12.5, color: ink, ...style }} data-testid="event-who-can-reserve">
      {T('Ai có thể đặt: ', 'Who can reserve: ')}{criteriaSummary(criteria, !EN)}
    </div>
  );
}

/** Card shown when the guest does not meet the host's criteria. `returnTo` is 'event' or 'reserve'. */
export function CriteriaUnmetCard({ eligibility, returnTo, style }) {
  const { T, EN, openEventPreferences } = useBanBe();
  const lines = eligibilityGuidance(eligibility, !EN);
  return (
    <div
      data-testid={`criteria-unmet-${returnTo}`}
      style={{ background: fieldSolid, border: `1px solid ${rule}`, borderRadius: 14, padding: 14, ...style }}
    >
      <div style={{ fontSize: 13, fontWeight: 600, color: ink }}>
        {T('Sự kiện này dành cho những người đã khai báo...', 'This event is for people who declared...')}
      </div>
      {lines.map((l, i) => (
        <div key={i} style={{ fontSize: 12.5, color: ink, marginTop: 6 }} data-testid="criteria-unmet-line">{l}</div>
      ))}
      <p style={{ ...small, margin: '8px 0 0' }}>
        {T('Cập nhật sở thích của bạn trong Tài khoản để đủ điều kiện. Thông tin này chỉ mình bạn thấy.', 'Update your preferences in Account to qualify. Your answers stay private to you.')}
      </p>
      <div
        role="button" onClick={() => openEventPreferences(returnTo)} data-testid={`criteria-update-prefs-${returnTo}`}
        style={{ ...inkButton({ marginTop: 12, padding: '12px 0', fontSize: 14 }) }}
      >
        {T('Cập nhật sở thích', 'Update my preferences')}
      </div>
    </div>
  );
}

import { useEffect, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { EVENTS, findEvent, bg } from '../data/events.js';
import { liveEventOverrides, formatVnEventDate } from '../lib/countdown.js';
import { reminderPhase, REMINDER_CSS, reminderRank } from '../lib/eventReminder.js';
import { paper, ink, rule, alert, display } from '../theme.js';
import { fieldGlass, cardGlass, inkButton } from './hostStyle.js';
import { buildActionCenterItems, sortActionCenterItems } from '../lib/actionCenter.js';
import ActionCenter from './ActionCenter.jsx';
import { supabase } from '../lib/supabase.js';
import { organizerAvatarPublicUrl } from '../lib/mediaUrls.js';

// THIRD STALE-AVATAR SITE (2026-09-28) — this header's round avatar next to
// the org name / "Bởi <org> Team" line used to always be `bg(ev.img, ...)`,
// i.e. the STATIC demo-catalogue event photo — never the organizer's own
// real `avatar_path` at all, on either the stale OR the fresh case. Same
// canonical source/helper Account.jsx and OrganizerProfile.jsx already use
// (`s.myOrganizerAvatarPath`, kept fresh in place by saveOrganizerProfile's
// success branch), so a real host photo change now shows here too, without
// re-deriving a second copy of the URL logic.
function organizerAvatarUrl(path, r2Ref, variant = 'thumb') {
  return organizerAvatarPublicUrl(path, r2Ref, variant);
}

import { useSubmittedEvents, useFormatWhen } from '../lib/submittedEvents.jsx';
import PendingEventSheet from './sheets/PendingEventSheet.jsx';

// Section header that expands/collapses its content; shows the item count.
function CollapseHeader({ title, count, open, onToggle, testId }) {
  return (
    <div onClick={onToggle} role="button" aria-expanded={open} data-testid={testId}
         style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer', padding: '4px 0' }}>
      <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>
        {title}{count > 0 && <span style={{ fontWeight: 400, opacity: 0.65 }}> ▪︎ {count}</span>}
      </span>
      <span aria-hidden="true" style={{ fontSize: 12, color: ink, display: 'inline-block', transform: open ? 'rotate(90deg)' : 'none', transition: 'transform 0.2s' }}>›</span>
    </div>
  );
}

export default function Dashboard() {
  const {
    state, T, trStatus, stripKm, curEvent, backFromDashboard, goCreate, openAttendance, goEvent, requestVerify, loadHomeLiveEvents,
    loadVerifications, loadRefundQueue, loadOrganizerHoldingSummary, openVerifications, uploadEventPhoto,
    loadRealEventsById, goEditEvent, openOrganizerProfile,
    loadOrgTeamRoster, orgTeamInviteHandleType, orgTeamInviteRoleType, inviteOrganizerMember, removeOrganizerMember,
    assignEventCredit, withdrawEventSubmission, loadResubmissionStatus,
    loadMyOrgStats,
  } = useBanBe();
  const s = state;
  const [creditEventKey, setCreditEventKey] = useState('');
  const [creditUserId, setCreditUserId] = useState('');
  // Withdrawal (migration 107) — a plain inline reason prompt, one at a
  // time (never more than one pending event's own withdraw form open),
  // matching this screen's existing "Sửa & gửi lại" inline-action style
  // rather than introducing a separate modal component.
  // Back label names the screen Back actually returns to (same pattern as Attendance/Verifications).
  const backLabel = ({ profile: T('Tài khoản', 'Account'), home: T('Nhà', 'Home'), notifications: T('Thông báo', 'Notifications') })[s.dashboardBack] || T('Quay lại', 'Back');
  const [teamOpen, setTeamOpen] = useState(false);
  // Collapsed by default to save space.
  const [pastOpen, setPastOpen] = useState(false);
  const [submittedOpen, setSubmittedOpen] = useState(false);
  const [withdrawTargetKey, setWithdrawTargetKey] = useState(null);
  const [withdrawReasonDraft, setWithdrawReasonDraft] = useState('');
  // Event review queue — a real, host-created event isn't in the static
  // demo catalogue, so it's resolved through the same canonical
  // realEventsById cache Home/EventList already use (see loadRealEventsById's
  // own comment), keyed off the account's real ownership list
  // (myOrgEventKeys, loaded at sign-in from events -> organizer -> owner_id).
  const myRealOrgKeys = s.myOrgEventKeys.filter(k => !EVENTS.some(e => e.key === k));
  useEffect(() => {
    if (myRealOrgKeys.length) loadRealEventsById(myRealOrgKeys);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [myRealOrgKeys.join(','), loadRealEventsById]);
  // Organizer Team pass (2026-09-27, Stage 1) — the FULL roster (every
  // status), owner-only (this screen only ever renders for the account's
  // own organizer).
  useEffect(() => { if (s.myOrganizerId) loadOrgTeamRoster(s.myOrganizerId); }, [s.myOrganizerId, loadOrgTeamRoster]);
  const ROLE_STATUS_LABEL = { invited: T('Đang chờ', 'Pending'), accepted: T('Đã tham gia', 'Joined'), declined: T('Đã từ chối', 'Declined'), removed: T('Đã xoá', 'Removed') };
  const myRealEvents = myRealOrgKeys.map(k => s.realEventsById[k]).filter(Boolean);
  const teamCount = s.orgTeamRoster.filter(m => m.status !== 'removed').length;
  // Review tracking reads live rows (polled), not the one-shot realEventsById
  // cache, so an admin approving / sending an event back shows up on its own.
  const submitted = useSubmittedEvents(true);
  const fmtWhen = useFormatWhen();
  const [viewingPending, setViewingPending] = useState(null);
  const pendingReal = submitted.pending.map(r => ({ key: r.id, name: r.name, submittedAt: r.submitted_at, remindCount: r.admin_remind_count }));
  const needsFixReal = submitted.needsFix.map(r => ({ key: r.id, name: r.name, rejectionReason: r.rejection_reason, reviewedAt: r.reviewed_at, submittedAt: r.submitted_at }));
  // Remaining-resubmission-attempts surfacing (migration 107) — fetched
  // once per event that actually has something to resubmit, so the "N
  // attempts left" hint is visible BEFORE a host hits the limit, not just
  // as an error after a blocked 3rd attempt.
  useEffect(() => {
    needsFixReal.forEach(e => { if (!(e.key in s.resubmissionStatusByEvent)) loadResubmissionStatus(e.key); });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [needsFixReal.map(e => e.key).join(','), loadResubmissionStatus]);
  // STAGE C (2026-09-25) — the real "add a photo to one of my own events"
  // flow; see uploadEventPhoto's own doc comment (BanBeContext.jsx).
  const photoInputRef = useRef(null);
  const [photoUploadTarget, setPhotoUploadTarget] = useState(null);
  const pickEventPhoto = (eventId) => { setPhotoUploadTarget(eventId); photoInputRef.current?.click(); };
  const onEventPhotoChosen = (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (file && photoUploadTarget) uploadEventPhoto(photoUploadTarget, file);
  };

  // TASK A (2026-10-01 UX foundation pass) — Dashboard is host-only (this
  // whole screen only ever renders for an organizer), so only host sources
  // are loaded/shown here — same canonical loaders Home/Account use.
  useEffect(() => {
    if (!s.user?.id) return;
    loadVerifications();
    loadRefundQueue();
    loadOrganizerHoldingSummary();
  }, [s.user?.id, loadVerifications, loadRefundQueue, loadOrganizerHoldingSummary]);
  const actionItems = sortActionCenterItems(buildActionCenterItems({
    role: 'host', T, now: s.now || Date.now(),
    verifications: s.verifications || [], refundQueue: s.refundQueue || [], orgHolding: s.organizerHoldingSummary,
    onOpenVerifications: () => openVerifications('dashboard'),
    onOpenRefundCenter: () => openVerifications('dashboard'),
    onOpenDashboard: () => {},
  }));

  // TASK 3 (organizer Check-in ended-event filtering) — same batched live
  // fetch Home.jsx already calls on mount (loadHomeLiveEvents), reused here
  // rather than inventing a separate "ended" calculation: without this,
  // `s.homeLiveEvents` could still be empty/stale if the organizer landed
  // here without ever visiting Home first, and a real, DB-backed event
  // that's actually ended would keep offering "Điểm danh"/Check-in below.
  useEffect(() => { loadHomeLiveEvents(); }, [loadHomeLiveEvents]);

  // The header shows the org branding for one of the account's own events
  // when it actually owns any (see myOrgEventKeys) — otherwise it falls back
  // to whichever demo event is "current", same as before real assignment
  // existed.
  const ev = s.myOrgEventKeys.length ? findEvent(s.myOrgEventKeys[0]) : curEvent;

  const verifyState = ev.orgTrusted ? 'verified' : (s.orgVerifyRequested ? 'pending' : 'none');
  const badgeMap = {
    verified: { label: T('Đã xác minh', 'Verified'), border: `1px solid ${ink}` },
    pending: { label: T('Đang xác minh', 'Verifying'), border: `1px solid ${ink}` },
    none: { label: T('Chưa xác minh', 'Not verified'), border: '1px solid rgba(27,25,22,0.16)' },
  };
  const b = badgeMap[verifyState];

  // Live track record of this account's own organizer (loadMyOrgStats ->
  // get_public_profile's published-events count), never the demo catalogue's
  // baked-in orgSince/orgCount. Empty until loaded / when there are none.
  useEffect(() => { if (s.myOrganizerId) loadMyOrgStats(); }, [s.myOrganizerId, loadMyOrgStats]);
  const dashStatsLine = s.myOrgPublishedEventCount > 0
    ? (s.myOrgHostingSinceYear
      ? T(`Tổ chức từ ${s.myOrgHostingSinceYear} ▪︎ ${s.myOrgPublishedEventCount} sự kiện`, `Hosting since ${s.myOrgHostingSinceYear} ▪︎ ${s.myOrgPublishedEventCount} events`)
      : T(`${s.myOrgPublishedEventCount} sự kiện`, `${s.myOrgPublishedEventCount} events`))
    : '';

  // Once the signed-in account actually owns events in the database (see
  // BanBeContext's myOrgEventKeys), the dashboard lists those — the real
  // assignment — instead of every demo event that happens to share the
  // currently-viewed org's name. Accounts with no real assignment yet (a
  // fresh dev database, or before the demo catalogue has been seeded) still
  // see the old name-matched demo behavior, so the prototype keeps working.
  // TASK 3 — was the raw static catalogue with no live status merged in;
  // each event now gets the same `liveEventOverrides` merge Home.jsx
  // already applies (src/lib/countdown.js), so a real event that has
  // actually ended (live `status`, not just the static catalogue's
  // frozen `endedHoursAgo`) actually drops into `past` and loses its
  // Check-in button below instead of staying "upcoming" forever.
  //
  // Part B audit (2026-09-28) — this used to filter on `myOrgEventKeys`
  // alone, which is the account-wide UNION of every organizer row this
  // account owns (deliberately so — it's also the real ownership gate
  // openNotification()/openVerificationDetail() use for dual-role
  // accounts, see its own comment in BanBeContext.jsx). This header,
  // though, brands ONE organizer (`s.myOrganizerId`, the deterministic
  // "primary" org above) — so an account seeded with several organizer
  // rows (migration 020's per-event random assignment; a real user only
  // ever has one) showed every one of ITS organizers' events here under
  // just the primary org's name/avatar, even though each event's own
  // EventDetail "Ghé <organizer>" correctly names its real, distinct
  // owner (no bad FK — every event's organizer_id was always right).
  // Narrowed to events whose real organizer_id (myOrgEventOrganizerId)
  // actually matches the organizer branded above.
  const myOrgEventKeysForEv = s.myOrgEventKeys.filter(k => s.myOrgEventOrganizerId[k] === s.myOrganizerId);
  const myEvents = (myOrgEventKeysForEv.length
    ? EVENTS.filter(e => myOrgEventKeysForEv.includes(e.key))
    : EVENTS.filter(e => e.orgName === ev.orgName)
  ).map(e => {
    const overrides = liveEventOverrides(s.homeLiveEvents[e.key], e);
    return overrides ? { ...e, ...overrides } : e;
  });
  // Real (host-created) events are not in the static catalogue, so they were missing from this list
  // (and had no Check-in button). Shape them like a catalogue row; iOS already does the same.
  const realRows = myOrgEventKeysForEv.filter(k => !EVENTS.some(e => e.key === k)).map(k => s.realEventsById[k])
    .filter(r => r && (r.status === 'live' || r.status === 'ended'))
    .map(r => {
      const startsAt = r.startsAt ? new Date(r.startsAt) : null;
      const { weekdayShort, dayMonth, time } = startsAt ? formatVnEventDate(startsAt) : {};
      return {
        key: r.key, name: r.name, img: r.photoUrl || '', startDate: startsAt, cancelled: false,
        meta: [r.catLabel, r.area, startsAt ? `${weekdayShort}, ${dayMonth} ▪︎ ${time}` : ''].filter(Boolean).join(' ▪︎ '),
        endedHoursAgo: r.status === 'ended' && startsAt ? Math.max(0, Math.round((Date.now() - startsAt.getTime()) / 3600000)) : null,
        until: startsAt ? Math.round((startsAt.getTime() - Date.now()) / 86400000) : 999,
        agoLabel: (h) => T(`${h} giờ trước`, `${h}h ago`), isReal: true,
      };
    });
  const allEvents = [...myEvents, ...realRows];
  // Reminder events (starting within 24h / happening now) lead the list, "live" first — same as Home.
  const withReminder = (e) => ({ ...e, reminder: reminderPhase(e.startDate) });
  const upcoming = allEvents.filter(e => !e.cancelled && e.endedHoursAgo == null).map(withReminder)
    .sort((a, c) => reminderRank(a.reminder) - reminderRank(c.reminder) || (a.until ?? 999) - (c.until ?? 999));
  const past = allEvents.filter(e => !e.cancelled && e.endedHoursAgo != null)
    .sort((a, c) => a.endedHoursAgo - c.endedHoursAgo);

  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', height: '100%', display: 'flex', flexDirection: 'column', background: paper }} data-screen-label="Organizer dashboard">
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>
      <div style={{ padding: '66px 22px 0', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div onClick={backFromDashboard} style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
          <span style={{ fontSize: 14, color: ink, lineHeight: 1 }}>‹</span>
          <span data-testid="dashboard-back-label" style={{ fontSize: 12, color: ink }}>{backLabel}</span>
        </div>
      </div>
      <div style={{ padding: '16px 22px 0', display: 'flex', gap: 14, alignItems: 'center' }}>
        {/* Real organizer avatar when this account actually has one
            (canonical `s.myOrganizerAvatarPath`, same source as the
            Account card / Profile tổ chức / public organizer profile) —
            `ev.img`'s demo-catalogue photo is only ever the fallback for a
            never-hosted dev/seed account, same fallback rule the org
            name/stats lines above already follow. */}
        {s.myOrganizerId && organizerAvatarUrl(s.myOrganizerAvatarPath, s.myOrganizerAvatarR2Ref) ? (
          <img
            src={organizerAvatarUrl(s.myOrganizerAvatarPath, s.myOrganizerAvatarR2Ref)}
            alt=""
            data-testid="dashboard-organizer-avatar"
            style={{ flex: 'none', width: 56, height: 56, borderRadius: '50%', objectFit: 'cover' }}
          />
        ) : (
          <div data-testid="dashboard-organizer-avatar-fallback" style={bg(ev.img, { flex: 'none', width: 56, height: 56, borderRadius: '50%' })} />
        )}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 5, minWidth: 0 }}>
          {/* Personal-vs-organizer hierarchy pass (2026-09-27) — the real
              organizers.name (s.orgRegName, kept in sync by
              loadMyOrgStats/saveOrganizerProfile) once this account
              actually has one; the demo-catalogue ev.orgName is only ever
              a fallback for a never-hosted dev/seed account. */}
          <h1 style={{ ...display(24, { margin: 0, lineHeight: 1.2 }) }}>{s.orgRegName || ev.orgName}</h1>
          {/* Real owner, never guessed/invented — this page only ever
              renders for the signed-in account's OWN organizer, so the
              viewer IS the owner. Never persisted as part of the name
              itself ("Team" is display-only text here). */}
          {s.myOrganizerId && (
            <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }} data-testid="dashboard-owner-line">
              {T(`Bởi ${s.user?.name || ''} Team`, `By ${s.user?.name || ''} Team`)}
            </span>
          )}
          <span style={{ display: 'inline-block', fontSize: 10, fontWeight: 600, padding: '5px 11px', borderRadius: 999, background: 'transparent', color: ink, border: b.border, width: 'fit-content' }}>{b.label}</span>
        </div>
      </div>
      <div style={{ padding: '14px 22px 0', fontSize: 12.5, color: ink }}>{dashStatsLine}</div>

      {/* Personal-vs-organizer hierarchy pass (2026-09-27) — replaces the
          former "Chỉnh sửa"/"Xem như khách" pair with ONE clear action:
          opens the organizer's own separate public page
          (OrganizerProfile.jsx — real avatar/stats/upcoming events/
          photos, its own shareable /org/<id> link and, for the owner
          only, its own "Chỉnh sửa hồ sơ tổ chức" entry), never the
          personal profile editor. Event management controls stay here. */}
      {s.myOrganizerId && (
        <div
          onClick={() => openOrganizerProfile(s.myOrganizerId, 'dashboard')}
          data-testid="dashboard-organizer-public-profile"
          style={{ margin: '16px 22px 0', textAlign: 'center', fontSize: 12.5, fontWeight: 600, color: ink, padding: '12px 0', borderRadius: 12, cursor: 'pointer', border: '1px solid rgba(27,25,22,0.16)' }}
        >
          {T('Hồ sơ công khai của tổ chức', "Organizer's public profile")}
        </div>
      )}

      {verifyState === 'none' && (
        <div style={{ ...cardGlass({ margin: '16px 22px 0', padding: '14px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12 }) }}>
          <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, margin: 0 }}>{T('Xác minh hồ sơ để khách tin tưởng hơn.', 'Get verified so guests trust you faster.')}</p>
          <span onClick={requestVerify} style={{ flex: 'none', fontSize: 12.5, fontWeight: 600, padding: '9px 16px', borderRadius: 999, background: ink, color: paper, cursor: 'pointer' }}>{T('Yêu cầu xác minh', 'Request')}</span>
        </div>
      )}

      <ActionCenter items={actionItems} onSeeAll={() => openVerifications('dashboard')} T={T} inset={22} />

      {/* Event review queue — a real submission's own status/reason, never
          the static catalogue. Pending: still awaiting an admin decision,
          no action to take yet. Needs fixing: rejected (status flipped back
          to 'draft' by admin_review_event, migration 085) — "Sửa & gửi lại"
          opens CreateEvent pre-filled (goEditEvent), which resubmits the
          SAME event row (resubmit_event_for_review), never a duplicate. */}
      {(pendingReal.length > 0 || needsFixReal.length > 0) && (
        <div style={{ margin: '24px 22px 0' }}>
          <CollapseHeader title={T('Sự kiện đã gửi', 'Submitted events')} count={pendingReal.length + needsFixReal.length} open={submittedOpen} onToggle={() => setSubmittedOpen(o => !o)} testId="dashboard-submitted-toggle" />
          {submittedOpen && <div style={{ ...fieldGlass({ marginTop: 10, display: 'flex', flexDirection: 'column' }) }}>
            {needsFixReal.map((e, i) => (
              <div key={e.key} data-testid={`dashboard-needs-fix-${e.key}`} style={{ display: 'flex', flexDirection: 'column', gap: 6, padding: '13px 16px', borderBottom: (i < needsFixReal.length - 1 || pendingReal.length) ? `1px solid ${rule}` : 'none' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10, alignItems: 'baseline' }}>
                  <span style={{ ...display(15) }}>{e.name}</span>
                  <span style={{ fontSize: 10.5, fontWeight: 600, color: alert }}>{T('Cần chỉnh sửa', 'Needs fixing')}</span>
                </div>
                <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, opacity: 0.8, margin: 0 }}>{e.rejectionReason}</p>
                {(e.submittedAt || e.reviewedAt) && (
                  <span data-testid={`dashboard-needs-fix-times-${e.key}`} style={{ fontSize: 10.5, color: ink, opacity: 0.6 }}>
                    {[e.submittedAt && T(`Gửi lúc ${fmtWhen(e.submittedAt)}`, `Submitted ${fmtWhen(e.submittedAt)}`), e.reviewedAt && T(`Admin phản hồi lúc ${fmtWhen(e.reviewedAt)}`, `Sent back ${fmtWhen(e.reviewedAt)}`)].filter(Boolean).join(' ▪︎ ')}
                  </span>
                )}
                {/* Remaining-resubmission-attempts surfacing (migration 107,
                    task 1's own "surface remaining attempts + next eligible
                    timestamp" requirement) — a banbe PRODUCT POLICY limit
                    (2 successful resubmissions per rolling 24h), never
                    phrased as a legal/Ticketbox requirement. */}
                {s.resubmissionStatusByEvent[e.key] && (
                  <span style={{ fontSize: 10.5, color: ink, opacity: 0.6 }} data-testid={`dashboard-resubmit-remaining-${e.key}`}>
                    {s.resubmissionStatusByEvent[e.key].remaining > 0
                      ? T(`Còn ${s.resubmissionStatusByEvent[e.key].remaining} lần gửi lại trong 24 giờ.`, `${s.resubmissionStatusByEvent[e.key].remaining} resubmission(s) left in the next 24h.`)
                      : T(`Đã hết lượt gửi lại. Thử lại sau ${new Date(s.resubmissionStatusByEvent[e.key].nextEligibleAt).toLocaleString()}.`, `Resubmission limit reached. Try again after ${new Date(s.resubmissionStatusByEvent[e.key].nextEligibleAt).toLocaleString()}.`)}
                  </span>
                )}
                <span
                  onClick={s.resubmissionStatusByEvent[e.key]?.remaining === 0 ? undefined : () => goEditEvent(e.key)}
                  data-testid={`dashboard-resubmit-${e.key}`}
                  style={{ fontSize: 11, fontWeight: 600, color: ink, border: '1px solid rgba(27,25,22,0.16)', borderRadius: 12, padding: '6px 10px', alignSelf: 'flex-start', cursor: 'pointer', opacity: s.resubmissionStatusByEvent[e.key]?.remaining === 0 ? 0.4 : 1 }}
                >
                  {T('Sửa & gửi lại', 'Fix & resubmit')}
                </span>
              </div>
            ))}
            {pendingReal.map((e, i) => (
              <div key={e.key} data-testid={`dashboard-pending-${e.key}`} style={{ display: 'flex', flexDirection: 'column', gap: 6, padding: '13px 16px', borderBottom: i < pendingReal.length - 1 ? `1px solid ${rule}` : 'none' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10, alignItems: 'center' }}>
                  <span style={{ ...display(15) }}>{e.name}</span>
                  <span style={{ fontSize: 10.5, fontWeight: 600, color: ink, opacity: 0.65 }}>{T('Đang chờ Banbe duyệt', 'Waiting for Banbe to review')}</span>
                </div>
                {e.submittedAt && (
                  <span data-testid={`dashboard-pending-submitted-${e.key}`} style={{ fontSize: 10.5, color: ink, opacity: 0.6 }}>{T(`Gửi lúc ${fmtWhen(e.submittedAt)}`, `Submitted ${fmtWhen(e.submittedAt)}`)}</span>
                )}
                {/* Owner-only withdrawal (migration 107,
                    withdraw_event_submission) — requires a non-empty reason
                    + this explicit confirm step; never deletes the event
                    row, only moves it back to editable ('draft') so
                    goEditEvent's existing edit-and-resubmit path can reuse
                    the SAME event id afterwards. */}
                {withdrawTargetKey === e.key ? (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                    <input
                      value={withdrawReasonDraft}
                      onChange={ev => setWithdrawReasonDraft(ev.target.value)}
                      placeholder={T('Lý do rút lại sự kiện…', 'Reason for withdrawing…')}
                      data-testid={`dashboard-withdraw-reason-${e.key}`}
                      style={{ fontSize: 12, padding: '8px 10px', borderRadius: 10, border: `1px solid ${rule}` }}
                    />
                    {s.withdrawEventError && <span style={{ fontSize: 10.5, color: alert }}>{s.withdrawEventError}</span>}
                    <div style={{ display: 'flex', gap: 8 }}>
                      <span
                        onClick={async () => {
                          const ok = await withdrawEventSubmission(e.key, withdrawReasonDraft);
                          if (ok) { setWithdrawTargetKey(null); setWithdrawReasonDraft(''); submitted.refresh(); }
                        }}
                        data-testid={`dashboard-withdraw-confirm-${e.key}`}
                        style={{ fontSize: 11, fontWeight: 600, color: paper, background: alert, borderRadius: 12, padding: '6px 10px', cursor: 'pointer', opacity: s.withdrawEventBusy ? 0.6 : 1 }}
                      >
                        {T('Xác nhận rút lại', 'Confirm withdrawal')}
                      </span>
                      <span
                        onClick={() => { setWithdrawTargetKey(null); setWithdrawReasonDraft(''); }}
                        data-testid={`dashboard-withdraw-cancel-${e.key}`}
                        style={{ fontSize: 11, fontWeight: 600, color: ink, opacity: 0.6, cursor: 'pointer', padding: '6px 4px' }}
                      >
                        {T('Huỷ', 'Cancel')}
                      </span>
                    </div>
                  </div>
                ) : (
                  <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
                    <span
                      onClick={() => setViewingPending(e)}
                      data-testid={`dashboard-view-pending-${e.key}`}
                      style={{ fontSize: 12, fontWeight: 600, color: ink, border: '1px solid rgba(var(--bb-fg-rgb), 0.5)', borderRadius: 999, padding: '7px 16px', cursor: 'pointer' }}
                    >
                      {T('Xem', 'View')}
                    </span>
                    <span
                      onClick={() => { setWithdrawTargetKey(e.key); setWithdrawReasonDraft(''); }}
                      data-testid={`dashboard-withdraw-${e.key}`}
                      style={{ fontSize: 12, fontWeight: 600, color: alert, textDecoration: 'underline', cursor: 'pointer' }}
                    >
                      {T('Rút lại sự kiện', 'Withdraw event')}
                    </span>
                  </div>
                )}
              </div>
            ))}
          </div>}
        </div>
      )}

      {viewingPending && <PendingEventSheet eventId={viewingPending.key} name={viewingPending.name} onClose={() => setViewingPending(null)} onChanged={submitted.refresh} />}

      <div style={{ margin: '24px 22px 0' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Sự kiện sắp tới', 'Upcoming events')}</span>
          <span style={{ fontSize: 10.5, color: ink }}>{upcoming.length}{T(' sự kiện', upcoming.length === 1 ? ' event' : ' events')}</span>
        </div>
        <div style={{ ...fieldGlass({ marginTop: 10, display: 'flex', flexDirection: 'column' }) }}>
          {upcoming.map((e, i, arr) => (
            <div key={e.key} style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '13px 16px', borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none' }}>
              <div className={e.reminder ? 'bb-rem-card' : undefined} data-testid={e.reminder ? 'dashboard-event-reminder' : undefined} data-reminder={e.reminder || undefined}
                   style={{ position: 'relative', flex: 'none', width: 52, height: 52, '--bb-rem-r': '14px' }}>
                {e.reminder && <style>{REMINDER_CSS}</style>}
                <div onClick={() => goEvent(e.key)} style={bg(e.img, { width: 52, height: 52, cursor: 'pointer' })} />
              </div>
              <div onClick={() => goEvent(e.key)} style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0, flex: 1, cursor: 'pointer' }}>
                {e.reminder && (
                  <span style={{ fontSize: 10, fontWeight: 700, letterSpacing: '0.04em', textTransform: 'uppercase', color: '#7A5200' }}>
                    <span aria-hidden="true" style={{ color: '#E0A526' }}>★ </span>{e.reminder === 'live' ? T('Đang diễn ra', 'Happening now') : T('Sắp diễn ra', 'Starting soon')}
                  </span>
                )}
                <span style={{ ...display(15, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{e.name}</span>
                <span style={{ fontSize: 11.5, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{trStatus(stripKm(e.meta, e))}</span>
              </div>
              {/* STAGE C (2026-09-25) — real "add photo" affordance, the
                  actual thing that lets Pulse's photo tab and Task 3's
                  like/heart system have real eligible data going forward.
                  A plain hidden file input (one shared input, `pickEventPhoto`
                  sets which event id it's for) rather than a whole new
                  upload sheet — same minimal shape `uploadAvatar`'s own
                  call site uses. */}
              <span
                onClick={() => pickEventPhoto(e.key)}
                data-testid={`dashboard-add-photo-${e.key}`}
                style={{ fontSize: 11, fontWeight: 600, color: ink, border: '1px solid rgba(27,25,22,0.16)', borderRadius: 12, padding: '6px 10px', flex: 'none', cursor: s.eventPhotoUploadBusy[e.key] ? 'default' : 'pointer', opacity: s.eventPhotoUploadBusy[e.key] ? 0.5 : 1 }}
              >
                {s.eventPhotoUploaded[e.key] ? T('Đã thêm ✓', 'Added ✓') : s.eventPhotoUploadBusy[e.key] ? T('Đang tải…', 'Uploading…') : T('+ Ảnh', '+ Photo')}
              </span>
              <span onClick={() => openAttendance(e.key)} data-testid={`dashboard-checkin-${e.key}`}
                    style={e.reminder
                      ? { fontSize: 11, fontWeight: 700, color: paper, background: ink, borderRadius: 12, padding: '7px 12px', flex: 'none', cursor: 'pointer' }
                      : { fontSize: 11, fontWeight: 600, color: ink, border: '1px solid rgba(27,25,22,0.16)', borderRadius: 12, padding: '6px 10px', flex: 'none', cursor: 'pointer' }}>{T('Điểm danh', 'Check-in')}</span>
            </div>
          ))}
          {upcoming.length === 0 && (
            <p style={{ fontSize: 12.5, color: ink, padding: '14px 16px', margin: 0 }}>{T('Bạn chưa có sự kiện nào sắp tới. Tạo bên dưới.', 'No upcoming events yet. Create one below.')}</p>
          )}
        </div>
      </div>

      <div style={{ margin: '22px 22px 24px' }}>
        <CollapseHeader title={T('Sự kiện đã qua', 'Past events')} count={past.length} open={pastOpen} onToggle={() => setPastOpen(o => !o)} testId="dashboard-past-toggle" />
        {pastOpen && <div style={{ ...fieldGlass({ marginTop: 10, display: 'flex', flexDirection: 'column' }) }}>
          {past.map((e, i, arr) => (
            <div key={e.key} style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '13px 16px', borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none' }}>
              <div onClick={() => goEvent(e.key)} style={bg(e.img, { flex: 'none', width: 52, height: 52, filter: 'grayscale(0.5)', cursor: 'pointer' })} />
              <div onClick={() => goEvent(e.key)} style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0, flex: 1, cursor: 'pointer' }}>
                <span style={{ ...display(15, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{e.name}</span>
                <span style={{ fontSize: 11.5, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{trStatus(stripKm(e.meta, e))} ▪︎ {e.agoLabel(e.endedHoursAgo)}</span>
              </div>
              {/* STAGE C — Task 1's own "ended must stay in the library"
                  rule implies a host should be able to add a recap photo
                  to an event after it's over, not just while it's live. */}
              <span
                onClick={() => pickEventPhoto(e.key)}
                data-testid={`dashboard-add-photo-${e.key}`}
                style={{ fontSize: 11, fontWeight: 600, color: ink, border: '1px solid rgba(27,25,22,0.16)', borderRadius: 12, padding: '6px 10px', flex: 'none', cursor: s.eventPhotoUploadBusy[e.key] ? 'default' : 'pointer', opacity: s.eventPhotoUploadBusy[e.key] ? 0.5 : 1 }}
              >
                {s.eventPhotoUploaded[e.key] ? T('Đã thêm ✓', 'Added ✓') : s.eventPhotoUploadBusy[e.key] ? T('Đang tải…', 'Uploading…') : T('+ Ảnh', '+ Photo')}
              </span>
            </div>
          ))}
          {past.length === 0 && (
            <p style={{ fontSize: 12.5, color: ink, padding: '14px 16px', margin: 0 }}>{T('Chưa có sự kiện nào đã qua.', 'No past events yet.')}</p>
          )}
        </div>}
      </div>

      {/* Organizer Team pass (2026-09-27, Stage 1) — owner-only roster
          management. Public role is display-only (never authorization —
          this account's own owner_id/user_id on `organizers` is still the
          only thing any event/payment/refund/bank action ever checks).
          The owner can invite/remove but never flip a member's own
          public_visible switch (that row simply isn't writable from
          here). */}
      {s.myOrganizerId && (
        <div style={{ margin: '0 22px 24px' }} data-testid="dashboard-team-section">
          {/* Collapsed by default to save space; the toggle shows the member count. */}
          <div
            onClick={() => setTeamOpen(o => !o)} role="button" aria-expanded={teamOpen} data-testid="dashboard-team-toggle"
            style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer', padding: '4px 0' }}
          >
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>
              {T('Đội ngũ', 'Team')}
              {teamCount > 0 && <span style={{ fontWeight: 400, opacity: 0.65 }}> ▪︎ {teamCount}</span>}
            </span>
            <span aria-hidden="true" style={{ fontSize: 12, color: ink, display: 'inline-block', transform: teamOpen ? 'rotate(90deg)' : 'none', transition: 'transform 0.2s' }}>›</span>
          </div>
          {teamOpen && (<>
          <div style={{ ...fieldGlass({ marginTop: 8, padding: 14, display: 'flex', flexDirection: 'column', gap: 8 }) }}>
            <input
              value={s.orgTeamInviteHandle} onChange={orgTeamInviteHandleType}
              placeholder={T('Tên người dùng (@handle)', 'Handle (@handle)')}
              data-testid="dashboard-team-invite-handle"
              style={{ border: 'none', outline: 'none', background: 'transparent', fontSize: 13, color: ink }}
            />
            <input
              value={s.orgTeamInviteRole} onChange={orgTeamInviteRoleType}
              placeholder={T('Vai trò công khai (VD: Điều phối)', 'Public role (e.g. Coordinator)')}
              data-testid="dashboard-team-invite-role"
              style={{ border: 'none', outline: 'none', background: 'transparent', fontSize: 13, color: ink }}
            />
            {s.orgTeamInviteError && <span style={{ fontSize: 11.5, color: alert }}>{s.orgTeamInviteError}</span>}
            <div
              onClick={s.orgTeamInviteBusy ? undefined : () => inviteOrganizerMember(s.myOrganizerId)}
              data-testid="dashboard-team-invite-submit"
              style={{ ...inkButton({ opacity: s.orgTeamInviteBusy ? 0.6 : 1 }) }}
            >
              {s.orgTeamInviteBusy ? T('Đang gửi…', 'Sending…') : T('Mời thành viên', 'Invite member')}
            </div>
          </div>
          {s.orgTeamRoster.filter(m => m.status !== 'removed').map(m => (
            <div key={m.id} style={{ ...fieldGlass({ marginTop: 8, padding: '12px 14px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }) }} data-testid={`dashboard-team-member-${m.id}`}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                <span style={{ fontSize: 13, color: ink }}>{m.profiles?.display_name || m.profiles?.handle}</span>
                <span style={{ fontSize: 11, color: ink, opacity: 0.65 }}>
                  {m.public_role} ▪︎ {ROLE_STATUS_LABEL[m.status]}{m.status === 'accepted' && !m.public_visible ? ` ▪︎ ${T('đã ẩn công khai', 'hidden from public')}` : ''}
                </span>
              </div>
              <div onClick={() => removeOrganizerMember(m.id, s.myOrganizerId)} data-testid={`dashboard-team-remove-${m.id}`} style={{ fontSize: 12, color: alert, cursor: 'pointer' }}>
                {T('Xoá', 'Remove')}
              </div>
            </div>
          ))}
          {/* Organizer Team pass (2026-09-27, Stage 2) — credits a real,
              ACCEPTED team member for a real event this account owns.
              Never the owner's own name; never a stranger who hasn't
              accepted the Team invite (assign_event_credit itself
              re-checks both server-side regardless). */}
          {myRealEvents.length > 0 && s.orgTeamRoster.some(m => m.status === 'accepted') && (
            <div style={{ ...fieldGlass({ marginTop: 8, padding: 14, display: 'flex', flexDirection: 'column', gap: 8 }) }}>
              <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Ghi nhận đóng góp sự kiện', 'Credit an event contribution')}</span>
              <select value={creditEventKey} onChange={e => setCreditEventKey(e.target.value)} data-testid="dashboard-credit-event-select" style={{ fontSize: 12.5, padding: 8 }}>
                <option value="">{T('Chọn sự kiện…', 'Choose an event…')}</option>
                {myRealEvents.map(e => <option key={e.key} value={e.key}>{e.name}</option>)}
              </select>
              <select value={creditUserId} onChange={e => setCreditUserId(e.target.value)} data-testid="dashboard-credit-member-select" style={{ fontSize: 12.5, padding: 8 }}>
                <option value="">{T('Chọn thành viên…', 'Choose a member…')}</option>
                {s.orgTeamRoster.filter(m => m.status === 'accepted').map(m => (
                  <option key={m.user_id} value={m.user_id}>{m.profiles?.display_name || m.profiles?.handle}</option>
                ))}
              </select>
              <div
                onClick={creditEventKey && creditUserId ? async () => { await assignEventCredit(creditEventKey, creditUserId); setCreditEventKey(''); setCreditUserId(''); } : undefined}
                data-testid="dashboard-credit-submit"
                style={{ ...inkButton({ opacity: creditEventKey && creditUserId ? 1 : 0.5 }) }}
              >
                {T('Ghi nhận', 'Credit')}
              </div>
            </div>
          )}
          </>)}
        </div>
      )}


      <div aria-hidden="true" style={{ height: 76 }} />
      <input ref={photoInputRef} type="file" accept="image/jpeg,image/png,image/webp" style={{ display: 'none' }} onChange={onEventPhotoChosen} />
      {s.eventPhotoUploadError && (
        <p style={{ fontSize: 12, color: alert, margin: '0 22px 16px' }}>{s.eventPhotoUploadError}</p>
      )}

      </div>
      {/* RESTYLE (2026-09-28) — this used to be a full-width, square-cornered
          bar pinned flush to the viewport bottom (`inkButton({ borderRadius: 0 })`,
          no horizontal inset). Reuses the exact same `inkButton()` style token
          "Mời thành viên" already uses above (same padding/fontSize, so same
          corner radius/typography by construction — not a new, eyeballed
          style), inset from the edges, with real bottom safe-area spacing
          (`env(safe-area-inset-bottom)`, same pattern ChatPhotoViewer.jsx's
          bottom bar already uses) instead of a fixed 30px guess. Tap action
          and the screen-level host-only gate (HOST_ONLY_SCREENS in
          BanBeContext.jsx — this whole screen only ever renders for an
          organizer) are unchanged. */}
      <div style={{ flex: 'none', padding: '10px 22px calc(env(safe-area-inset-bottom, 0px) + 14px)' }}>
        <div onClick={goCreate} data-testid="dashboard-create-event" style={{ ...inkButton() }}>
          {T('+ Tạo sự kiện mới', '+ Create new event')}
        </div>
      </div>
    </div>
  );
}

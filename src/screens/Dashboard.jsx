import { useEffect, useRef, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { EVENTS, findEvent, bg } from '../data/events.js';
import { liveEventOverrides } from '../lib/countdown.js';
import { paper, ink, rule, alert, display, fieldGlass, cardGlass, inkButton } from '../theme.js';
import { buildActionCenterItems, sortActionCenterItems } from '../lib/actionCenter.js';
import ActionCenter from './ActionCenter.jsx';

export default function Dashboard() {
  const {
    state, T, trStatus, stripKm, curEvent, backFromDashboard, switchToGoer, goCreate, openAttendance, goEvent, requestVerify, loadHomeLiveEvents,
    loadVerifications, loadRefundQueue, loadOrganizerHoldingSummary, openVerifications, uploadEventPhoto,
    loadRealEventsById, goEditEvent,
  } = useGoc();
  const s = state;
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
  const myRealEvents = myRealOrgKeys.map(k => s.realEventsById[k]).filter(Boolean);
  const pendingReal = myRealEvents.filter(e => e.status === 'review');
  const needsFixReal = myRealEvents.filter(e => e.status === 'draft' && e.rejectionReason);
  // STAGE C (2026-09-25) — the real "add a photo to one of my own events"
  // flow; see uploadEventPhoto's own doc comment (GocContext.jsx).
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

  const dashStatsLine = T('Tổ chức từ ' + ev.orgSince + ' ▪︎ ' + ev.orgCount + ' sự kiện', 'Hosting since ' + ev.orgSince + ' ▪︎ ' + ev.orgCount + ' events');

  // Once the signed-in account actually owns events in the database (see
  // GocContext's myOrgEventKeys), the dashboard lists those — the real
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
  const myEvents = (s.myOrgEventKeys.length
    ? EVENTS.filter(e => s.myOrgEventKeys.includes(e.key))
    : EVENTS.filter(e => e.orgName === ev.orgName)
  ).map(e => {
    const overrides = liveEventOverrides(s.homeLiveEvents[e.key], e);
    return overrides ? { ...e, ...overrides } : e;
  });
  const upcoming = myEvents.filter(e => !e.cancelled && e.endedHoursAgo == null)
    .sort((a, c) => (a.until ?? 999) - (c.until ?? 999));
  const past = myEvents.filter(e => !e.cancelled && e.endedHoursAgo != null)
    .sort((a, c) => a.endedHoursAgo - c.endedHoursAgo);

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', height: '100%', display: 'flex', flexDirection: 'column', background: paper }} data-screen-label="Organizer dashboard">
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>
      <div style={{ padding: '66px 22px 0', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div onClick={backFromDashboard} style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
          <span style={{ fontSize: 14, color: ink, lineHeight: 1 }}>‹</span>
          <img src="/banbe-mark.png" alt="banbe" crossOrigin="anonymous" style={{ height: 34, width: 'auto' }} />
        </div>
        <span onClick={switchToGoer} style={{ fontSize: 11.5, color: ink, cursor: 'pointer', border: '1px solid rgba(27,25,22,0.16)', padding: '7px 12px', borderRadius: 999 }}>{T('Xem như khách', 'View as goer')}</span>
      </div>
      <div style={{ padding: '16px 22px 0', display: 'flex', gap: 14, alignItems: 'center' }}>
        <div style={bg(ev.img, { flex: 'none', width: 56, height: 56, borderRadius: '50%' })} />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 5, minWidth: 0 }}>
          <h1 style={{ ...display(24, { margin: 0, lineHeight: 1.2 }) }}>{ev.orgName}</h1>
          <span style={{ display: 'inline-block', fontSize: 10, fontWeight: 600, padding: '5px 11px', borderRadius: 999, background: 'transparent', color: ink, border: b.border, width: 'fit-content' }}>{b.label}</span>
        </div>
      </div>
      <div style={{ padding: '14px 22px 0', fontSize: 12.5, color: ink }}>{dashStatsLine}</div>

      {verifyState === 'none' && (
        <div style={{ ...cardGlass({ margin: '16px 22px 0', padding: '14px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12 }) }}>
          <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, margin: 0 }}>{T('Xác minh hồ sơ để khách tin tưởng hơn.', 'Get verified so guests trust you faster.')}</p>
          <span onClick={requestVerify} style={{ flex: 'none', fontSize: 12.5, fontWeight: 600, padding: '9px 16px', borderRadius: 999, background: ink, color: paper, cursor: 'pointer' }}>{T('Yêu cầu xác minh', 'Request')}</span>
        </div>
      )}

      <ActionCenter items={actionItems} onSeeAll={() => openVerifications('dashboard')} T={T} />

      {/* Event review queue — a real submission's own status/reason, never
          the static catalogue. Pending: still awaiting an admin decision,
          no action to take yet. Needs fixing: rejected (status flipped back
          to 'draft' by admin_review_event, migration 085) — "Sửa & gửi lại"
          opens CreateEvent pre-filled (goEditEvent), which resubmits the
          SAME event row (resubmit_event_for_review), never a duplicate. */}
      {(pendingReal.length > 0 || needsFixReal.length > 0) && (
        <div style={{ margin: '24px 22px 0' }}>
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Sự kiện đã gửi', 'Submitted events')}</span>
          <div style={{ ...fieldGlass({ marginTop: 10, display: 'flex', flexDirection: 'column' }) }}>
            {needsFixReal.map((e, i) => (
              <div key={e.key} data-testid={`dashboard-needs-fix-${e.key}`} style={{ display: 'flex', flexDirection: 'column', gap: 6, padding: '13px 16px', borderBottom: (i < needsFixReal.length - 1 || pendingReal.length) ? `1px solid ${rule}` : 'none' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10, alignItems: 'baseline' }}>
                  <span style={{ ...display(15) }}>{e.name}</span>
                  <span style={{ fontSize: 10.5, fontWeight: 600, color: alert }}>{T('Cần chỉnh sửa', 'Needs fixing')}</span>
                </div>
                <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, opacity: 0.8, margin: 0 }}>{e.rejectionReason}</p>
                <span onClick={() => goEditEvent(e.key)} data-testid={`dashboard-resubmit-${e.key}`} style={{ fontSize: 11, fontWeight: 600, color: ink, border: '1px solid rgba(27,25,22,0.16)', borderRadius: 12, padding: '6px 10px', alignSelf: 'flex-start', cursor: 'pointer' }}>
                  {T('Sửa & gửi lại', 'Fix & resubmit')}
                </span>
              </div>
            ))}
            {pendingReal.map((e, i) => (
              <div key={e.key} data-testid={`dashboard-pending-${e.key}`} style={{ display: 'flex', justifyContent: 'space-between', gap: 10, alignItems: 'center', padding: '13px 16px', borderBottom: i < pendingReal.length - 1 ? `1px solid ${rule}` : 'none' }}>
                <span style={{ ...display(15) }}>{e.name}</span>
                <span style={{ fontSize: 10.5, fontWeight: 600, color: ink, opacity: 0.65 }}>{T('Đang chờ Banbe duyệt', 'Waiting for Banbe to review')}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      <div style={{ margin: '24px 22px 0' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Sự kiện sắp tới', 'Upcoming events')}</span>
          <span style={{ fontSize: 10.5, color: ink }}>{upcoming.length}{T(' sự kiện', upcoming.length === 1 ? ' event' : ' events')}</span>
        </div>
        <div style={{ ...fieldGlass({ marginTop: 10, display: 'flex', flexDirection: 'column' }) }}>
          {upcoming.map((e, i, arr) => (
            <div key={e.key} style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '13px 16px', borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none' }}>
              <div onClick={() => goEvent(e.key)} style={bg(e.img, { flex: 'none', width: 52, height: 52, cursor: 'pointer' })} />
              <div onClick={() => goEvent(e.key)} style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0, flex: 1, cursor: 'pointer' }}>
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
              <span onClick={() => openAttendance(e.key)} style={{ fontSize: 11, fontWeight: 600, color: ink, border: '1px solid rgba(27,25,22,0.16)', borderRadius: 12, padding: '6px 10px', flex: 'none', cursor: 'pointer' }}>{T('Điểm danh', 'Check-in')}</span>
            </div>
          ))}
          {upcoming.length === 0 && (
            <p style={{ fontSize: 12.5, color: ink, padding: '14px 16px', margin: 0 }}>{T('Bạn chưa có sự kiện nào sắp tới. Tạo bên dưới.', 'No upcoming events yet. Create one below.')}</p>
          )}
        </div>
      </div>

      <div style={{ margin: '22px 22px 100px' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Sự kiện đã qua', 'Past events')}</span>
        <div style={{ ...fieldGlass({ marginTop: 10, display: 'flex', flexDirection: 'column' }) }}>
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
        </div>
      </div>

      <input ref={photoInputRef} type="file" accept="image/jpeg,image/png,image/webp" style={{ display: 'none' }} onChange={onEventPhotoChosen} />
      {s.eventPhotoUploadError && (
        <p style={{ fontSize: 12, color: alert, margin: '0 22px 16px' }}>{s.eventPhotoUploadError}</p>
      )}

      </div>
      <div onClick={goCreate} style={{ ...inkButton({ flex: 'none', borderRadius: 0, padding: '18px 0 30px' }) }}>{T('+ Tạo sự kiện mới', '+ Create new event')}</div>
    </div>
  );
}

import { useGoc } from '../state/GocContext.jsx';
import { EVENTS, findEvent, bg } from '../data/events.js';
import { paper, ink, rule, display, fieldGlass, cardGlass, inkButton } from '../theme.js';

export default function Dashboard() {
  const { state, T, trStatus, stripKm, curEvent, goHome, switchToGoer, goCreate, openAttendance, goEvent, requestVerify } = useGoc();
  const s = state;

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
  const myEvents = s.myOrgEventKeys.length
    ? EVENTS.filter(e => s.myOrgEventKeys.includes(e.key))
    : EVENTS.filter(e => e.orgName === ev.orgName);
  const upcoming = myEvents.filter(e => !e.cancelled && e.endedHoursAgo == null)
    .sort((a, c) => (a.until ?? 999) - (c.until ?? 999));
  const past = myEvents.filter(e => !e.cancelled && e.endedHoursAgo != null)
    .sort((a, c) => a.endedHoursAgo - c.endedHoursAgo);

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', height: '100%', display: 'flex', flexDirection: 'column', background: paper }} data-screen-label="Organizer dashboard">
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>
      <div style={{ padding: '66px 22px 0', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div onClick={goHome} style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
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
                <span style={{ fontSize: 11.5, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{trStatus(stripKm(e.meta))}</span>
              </div>
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
            <div key={e.key} onClick={() => goEvent(e.key)} style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '13px 16px', borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none', cursor: 'pointer' }}>
              <div style={bg(e.img, { flex: 'none', width: 52, height: 52, filter: 'grayscale(0.5)' })} />
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0, flex: 1 }}>
                <span style={{ ...display(15, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{e.name}</span>
                <span style={{ fontSize: 11.5, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{trStatus(stripKm(e.meta))} ▪︎ {e.agoLabel(e.endedHoursAgo)}</span>
              </div>
            </div>
          ))}
          {past.length === 0 && (
            <p style={{ fontSize: 12.5, color: ink, padding: '14px 16px', margin: 0 }}>{T('Chưa có sự kiện nào đã qua.', 'No past events yet.')}</p>
          )}
        </div>
      </div>

      </div>
      <div onClick={goCreate} style={{ ...inkButton({ flex: 'none', borderRadius: 0, padding: '18px 0 30px' }) }}>{T('+ Tạo sự kiện mới', '+ Create new event')}</div>
    </div>
  );
}

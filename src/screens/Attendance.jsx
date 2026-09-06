import { useGoc } from '../state/GocContext.jsx';
import { findEvent, GUESTS } from '../data/events.js';
import { paper, ink, rule, display, fieldGlass } from '../theme.js';

export default function Attendance() {
  const { state, T, trStatus, goDashboard, toggleCheckin } = useGoc();
  const s = state;

  const attKey = s.attendanceEventKey;
  const attEv = attKey ? findEvent(attKey) : null;

  if (!attEv) {
    return (
      <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Attendance">
        <div onClick={goDashboard} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Trang của bạn', 'Your dashboard')}</div>
      </div>
    );
  }

  const bookedCount = Math.max(4, Math.min(9, 20 - (attEv.seats.match(/\d+/) ? parseInt(attEv.seats.match(/\d+/)[0], 10) : 6)));
  const guests = GUESTS(attKey, bookedCount);
  const checkedMap = s.checkins[attKey] || {};
  const checkedCount = guests.filter(g => checkedMap[g.id]).length;

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Attendance">
      <div onClick={goDashboard} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Trang của bạn', 'Your dashboard')}</div>
      <div style={{ padding: '14px 22px 0' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Điểm danh khách', 'Guest check-in')}</span>
        <h1 style={{ ...display(24, { margin: '8px 0 0' }) }}>{attEv.name}</h1>
        <div style={{ fontSize: 12.5, color: ink, marginTop: 4 }}>{trStatus(attEv.when)}</div>
      </div>
      <div style={{ margin: '18px 22px 0', background: ink, padding: '16px 18px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ fontSize: 12.5, color: paper }}>{T('Đã đến', 'Checked in')}</span>
        <span style={{ fontFamily: "'Be Vietnam Pro', sans-serif", fontWeight: 600, letterSpacing: '-0.02em', fontSize: 24, color: paper }}>{checkedCount} / {guests.length}</span>
      </div>
      <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, margin: '10px 22px 0' }}>{T('Chạm vào tên khách khi họ tới nơi.', "Tap a guest's name when they arrive.")}</p>
      <div style={{ ...fieldGlass({ margin: '14px 22px 40px', display: 'flex', flexDirection: 'column' }) }}>
        {guests.map(g => {
          const checked = !!checkedMap[g.id];
          const meta = (g.qty > 1 ? (g.qty + T(' vé', ' tickets')) : T('1 vé', '1 ticket')) + (g.held ? T(' ▪︎ đang giữ chỗ', ' ▪︎ on hold') : '');
          return (
            <div key={g.id} onClick={() => toggleCheckin(attKey, g.id, checked)} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '13px 16px', borderBottom: `1px solid ${rule}`, cursor: 'pointer', background: checked ? 'rgba(27,25,22,0.16)' : 'transparent' }}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                <span style={{ ...display(15) }}>{g.name}</span>
                <span style={{ fontSize: 11.5, color: ink }}>{meta}</span>
              </div>
              <span style={{ fontSize: 11.5, fontWeight: 600, flex: 'none', padding: '5px 10px', color: checked ? paper : ink, background: checked ? ink : 'rgba(27,25,22,0.16)' }}>
                {checked ? T('Đã đến ✓', 'Here ✓') : T('Chưa đến', 'Not yet')}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

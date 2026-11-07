import { useEffect } from 'react';
import { useEventProject } from '../state/useEventProject.js';
import { paper, ink, ink2, ink3, block, clay, clayBg, display } from '../theme.js';
import { pillButton } from '../components/project/ProjectUI.jsx';

// Account > Projects I'm in (note 76): every event project where I am a Host or a member, soonest first.
export default function MyProjects() {
  const p = useEventProject();
  const { s, T, set } = p;
  useEffect(() => { p.loadMyProjects(); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const date = (x) => {
    if (!x.event_date) return null;
    const [y, m, d] = x.event_date.split('-').map(Number);
    return new Intl.DateTimeFormat(T('vi-VN', 'en-US'), { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' }).format(new Date(Date.UTC(y, m - 1, d)));
  };
  return (
    <div data-screen-label="MyProjects" data-testid="project-mine" style={{ minHeight: '100%', background: paper, color: ink, padding: '66px 20px 40px', boxSizing: 'border-box' }}>
      <button type="button" onClick={() => set({ screen: 'profile' })} style={{ background: 'none', border: 0, color: ink, fontSize: 12, cursor: 'pointer', minHeight: 44, padding: 0 }}>‹ {T('Tài khoản', 'Account')}</button>
      <h1 style={display(24, { margin: '6px 0 0' })}>{T('Dự án của tôi', "Projects I'm in")}</h1>
      {!s.myProjectsLoaded ? <p style={{ color: ink3 }}>{T('Đang tải…', 'Loading…')}</p>
        : s.myProjects.length === 0 ? <p style={{ color: ink2, fontSize: 14 }}>{T('Bạn chưa ở trong dự án nào. Khi được mời, dự án sẽ hiện ở đây.', "You're not in any project yet. When someone invites you, it shows up here.")}</p>
          : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 18 }}>
              {s.myProjects.map(x => (
                <button key={x.event_id} type="button" onClick={() => p.open(x.event_id, 'myProjects')} data-testid={`project-mine-${x.event_id}`}
                  style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 16, minHeight: 64, borderRadius: 16, border: 0, background: block, color: ink, textAlign: 'left', cursor: 'pointer' }}>
                  <span style={{ flex: 1 }}><strong style={{ display: 'block' }}>{x.name}</strong>
                    <span style={{ fontSize: 13, color: ink2 }}>{[p.roleName(x.role), date(x), x.read_only ? T('Chỉ xem', 'Read only') : null].filter(Boolean).join(' · ')}</span></span>
                  {x.my_open_tasks > 0 && <span style={{ fontSize: 12, fontWeight: 700, padding: '4px 9px', borderRadius: 999, color: clay, background: clayBg }}>{T(`${x.my_open_tasks} việc`, x.my_open_tasks === 1 ? '1 task' : `${x.my_open_tasks} tasks`)}</span>}
                  <span aria-hidden style={{ color: ink3 }}>›</span>
                </button>
              ))}
            </div>
          )}
      <button type="button" onClick={() => p.openJoin('', 'myProjects')} data-testid="project-mine-join" style={pillButton(false, { marginTop: 18 })}>＋ {T('Có mã mời? Vào đội', 'Have an invite code? Join a team')}</button>
    </div>
  );
}

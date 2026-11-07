import { useEffect } from 'react';
import { useEventProject, PENDING_PROJECT_INVITE_KEY } from '../state/useEventProject.js';
import { paper, ink, ink2, ink3, block, blockInset, fieldSolid, alert } from '../theme.js';
import { Card, Note, pillButton } from '../components/project/ProjectUI.jsx';

// "Join a team" (note 76): what an invite link (/join/<token or code>) or a typed BB-XXXX code points at, then Join. The
// server decides the event, role and lane; the link never does. Signed out, the code is kept in this browser and the
// screen asks to log in first (iOS twin: ProjectJoinView.swift).
export default function ProjectJoin() {
  const p = useEventProject();
  const { s, T, set } = p;
  const signedIn = !!s.user?.id;
  useEffect(() => {
    if (!s.projectJoinCode) {
      try { const v = localStorage.getItem(PENDING_PROJECT_INVITE_KEY); if (v) set({ projectJoinCode: v }); } catch { /* storage blocked */ }
    } else if (!signedIn) {
      try { localStorage.setItem(PENDING_PROJECT_INVITE_KEY, s.projectJoinCode); } catch { /* storage blocked */ }
    }
    if (signedIn && s.projectJoinCode && !s.projectJoinPeek && !s.projectJoinError) p.peek(s.projectJoinCode);
  }, [signedIn, s.projectJoinCode]); // eslint-disable-line react-hooks/exhaustive-deps

  const check = () => {
    if (!signedIn) {
      try { localStorage.setItem(PENDING_PROJECT_INVITE_KEY, s.projectJoinCode.trim()); } catch { /* ignore */ }
      set({ screen: 'login', authReturnScreen: 'projectJoin', authBackScreen: s.projectJoinBack || 'home' });
      return;
    }
    p.peek(s.projectJoinCode);
  };
  const peek = s.projectJoinPeek;
  const stateText = {
    revoked: p.errorText('INVITE_REVOKED'), expired: p.errorText('INVITE_EXPIRED'), used: p.errorText('INVITE_USED'),
    event_closed: T('Sự kiện đã huỷ, bị gỡ hoặc dự án đã đóng.', 'The event was cancelled or removed, or the project has closed.'),
    is_host: p.errorText('IS_HOST'), already_member: p.errorText('ALREADY_MEMBER'),
  };
  const day = peek?.event_date ? (() => { const [y, m, d] = peek.event_date.split('-').map(Number); return new Intl.DateTimeFormat(T('vi-VN', 'en-US'), { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' }).format(new Date(Date.UTC(y, m - 1, d))); })() : null;
  return (
    <div data-screen-label="ProjectJoin" data-testid="project-join" style={{ minHeight: '100%', background: paper, color: ink, padding: '58px 18px 40px', boxSizing: 'border-box' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <button type="button" onClick={() => set({ screen: s.projectJoinBack || 'home' })} aria-label={T('Quay lại', 'Back')} data-testid="project-join-back"
          style={{ width: 44, height: 44, borderRadius: '50%', border: 0, background: block, color: ink, fontSize: 20, cursor: 'pointer' }}>‹</button>
        <h1 style={{ flex: 1, margin: 0, fontSize: 17, textAlign: 'center' }}>{T('Vào đội sự kiện', 'Join a team')}</h1>
        <span style={{ width: 44 }} />
      </div>
      <label style={{ display: 'block', marginTop: 20, fontSize: 12, fontWeight: 700, letterSpacing: 0.6, color: ink3 }}>{T('MÃ MỜI HOẶC LIÊN KẾT', 'INVITE CODE OR LINK')}</label>
      <div style={{ display: 'flex', gap: 8, marginTop: 6 }}>
        <input value={s.projectJoinCode} onChange={e => set({ projectJoinCode: e.target.value, projectJoinPeek: null, projectJoinError: '' })} placeholder="BB-XXXX"
          aria-label={T('Mã mời', 'Invite code')} data-testid="project-join-code" autoCapitalize="characters" autoCorrect="off" onKeyDown={e => { if (e.key === 'Enter') check(); }}
          style={{ flex: 1, minWidth: 0, font: 'inherit', fontFamily: 'ui-monospace, Menlo, monospace', fontWeight: 700, fontSize: 18, padding: '12px 14px', borderRadius: 14, border: 0, background: fieldSolid, color: ink }} />
        <button type="button" onClick={check} disabled={!s.projectJoinCode.trim() || s.projectJoinLoading} data-testid="project-join-check"
          style={{ minHeight: 50, padding: '0 16px', borderRadius: 999, border: 0, background: blockInset, color: ink, fontWeight: 600, cursor: 'pointer' }}>{T('Kiểm tra', 'Check')}</button>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 16, marginTop: 18 }}>
        {s.projectJoinError && <p role="alert" data-testid="project-join-error" style={{ margin: 0, color: alert, fontSize: 14 }}>{s.projectJoinError}</p>}
        {!signedIn && (
          <Card data-testid="project-join-sign-in">
            <p style={{ margin: '0 0 12px' }}>{T('Đăng nhập để xem và nhận lời mời. Mã của bạn được giữ lại.', 'Log in to see and accept this invite. Your code is kept for you.')}</p>
            <button type="button" onClick={check} style={pillButton(true)}>{T('Đăng nhập để vào đội', 'Log in to join')}</button>
          </Card>
        )}
        {signedIn && peek && (
          <Card data-testid="project-join-card">
            <h2 style={{ margin: 0, fontSize: 22 }}>{peek.event_name}</h2>
            <Note tone="ink2">{[peek.organizer_name, day].filter(Boolean).join(' · ')}</Note>
            <div style={{ margin: '12px 0' }}><strong>{T('Vai trò: ', 'Role: ')}{p.roleName(peek.role)}{peek.lane_name ? ` · ${peek.lane_name}` : ''}</strong>
              <div style={{ fontSize: 13, color: ink2 }}>{p.roleNote(peek.role || 'helper')}</div></div>
            {peek.state === 'ok' ? (<>
              {p.inviteExpiry(peek.expires_at) && <Note>{T(`Lời mời ${p.inviteExpiry(peek.expires_at)}.`, `Invite: ${p.inviteExpiry(peek.expires_at)}.`)}</Note>}
              <button type="button" onClick={p.join} disabled={s.projectJoinLoading} data-testid="project-join-confirm" style={pillButton(true, { marginTop: 10 })}>{T('Vào đội', 'Join the team')}</button>
            </>) : (<>
              <p data-testid="project-join-state" style={{ margin: 0, color: ['is_host', 'already_member'].includes(peek.state) ? ink : alert }}>{stateText[peek.state] || p.errorText(null)}</p>
              {['is_host', 'already_member'].includes(peek.state) && peek.event_id &&
                <button type="button" onClick={() => p.open(peek.event_id, s.projectJoinBack || 'home')} style={pillButton(true, { marginTop: 10 })}>{T('Mở dự án', 'Open project')}</button>}
            </>)}
          </Card>
        )}
        <Note>{T('Bạn chỉ thấy dự án của sự kiện này: việc, chủ đề và lịch chạy của đội. Vai trò do người mời đặt sẵn.', "You'll only see this event's team project: its tasks, topics and run-of-show. Your role is set by whoever invited you.")}</Note>
      </div>
    </div>
  );
}

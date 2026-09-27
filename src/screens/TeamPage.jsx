import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, display, cardGlass } from '../theme.js';

function memberAvatarUrl(url) {
  return url || '';
}

// Organizer Team pass (2026-09-27, Stage 2) — a Banbe-styled, readable
// Team page: large rounded member cards, grouped by their REAL public
// role (a display-only label — never implies a management hierarchy the
// data doesn't support; groups are just "people who share this same
// title," in the order those titles first appear). Real organizer/member
// identity only (get_organizer_team, 098/101) — accepted AND
// public_visible members alone; a member who has opted out simply never
// appears here, with no trace (no hidden count, no placeholder row).
export default function TeamPage() {
  const { state, T, backFromOrganizerTeam, openPublicProfile } = useGoc();
  const s = state;
  const team = s.organizerTeam;

  if (s.organizerTeamLoading) {
    return <div style={{ minHeight: '100%', background: paper }} data-screen-label="Organizer team" />;
  }
  if (s.organizerTeamError || !team) {
    return (
      <div style={{ minHeight: '100%', background: paper }} data-screen-label="Organizer team">
        <div style={{ padding: '66px 20px 0' }}>
          <span onClick={backFromOrganizerTeam} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>{T('‹ Quay lại', '‹ Back')}</span>
        </div>
        <p style={{ textAlign: 'center', fontSize: 13, color: ink, marginTop: 60 }}>{s.organizerTeamError}</p>
      </div>
    );
  }

  const members = team.members || [];
  const groups = [];
  const groupIndexByRole = new Map();
  for (const m of members) {
    if (!groupIndexByRole.has(m.public_role)) {
      groupIndexByRole.set(m.public_role, groups.length);
      groups.push({ role: m.public_role, members: [] });
    }
    groups[groupIndexByRole.get(m.public_role)].members.push(m);
  }

  return (
    <div style={{ minHeight: '100%', background: paper, animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both' }} data-screen-label="Organizer team">
      <div style={{ padding: '66px 20px 0' }}>
        <span onClick={backFromOrganizerTeam} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>{T('‹ Quay lại', '‹ Back')}</span>
      </div>
      <div style={{ padding: '14px 20px 0' }}>
        <span style={{ ...display(24) }}>{T(`Đội ngũ ${team.organizer_name || ''}`, `The ${team.organizer_name || ''} Team`)}</span>
      </div>

      {members.length === 0 ? (
        <p style={{ textAlign: 'center', fontSize: 13, color: ink, opacity: 0.6, marginTop: 60, padding: '0 30px' }}>
          {T('Đội ngũ này chưa công khai thành viên nào.', 'This Team has no publicly shown members yet.')}
        </p>
      ) : (
        <div style={{ padding: '18px 20px 40px' }}>
          {groups.map(group => (
            <div key={group.role} style={{ marginBottom: 22 }}>
              <span style={{ fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.7 }}>{group.role}</span>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 8 }}>
                {group.members.map(m => (
                  <div
                    key={m.handle}
                    onClick={() => openPublicProfile(m.handle, 'organizerTeam')}
                    data-testid={`team-member-card-${m.handle}`}
                    style={{ ...cardGlass({ padding: 16, display: 'flex', alignItems: 'center', gap: 14, cursor: 'pointer', borderRadius: 20 }) }}
                  >
                    {memberAvatarUrl(m.avatar_url) ? (
                      <img src={m.avatar_url} alt="" style={{ width: 56, height: 56, borderRadius: 16, objectFit: 'cover' }} />
                    ) : (
                      <div style={{ width: 56, height: 56, borderRadius: 16, background: ink, color: paper, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20, fontWeight: 700 }}>
                        {(m.display_name || m.handle || '?').trim()[0]?.toUpperCase() || '?'}
                      </div>
                    )}
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                      <span style={{ fontSize: 14, fontWeight: 600, color: ink }}>{m.display_name || m.handle}</span>
                      <span style={{ fontSize: 11.5, color: ink, opacity: 0.65 }}>@{m.handle}</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

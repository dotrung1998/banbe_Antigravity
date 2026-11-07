// Team tab of the web Event Project Hub (note 76): members with their private working role, lane and money/check-in
// access, the invite button (Host and Managers), live invites, "Who can do what", and the privacy note. Same rules as
// iOS ProjectTeamTab / ProjectTeamSheets. With switch project_qr_invite the invite sheet also shows a QR and a
// "Single use only" toggle (phase 4b).
import { useEffect, useRef, useState } from 'react';
import QRCode from 'qrcode';
import { MATRIX_COLUMNS, MATRIX_ROWS } from '../../lib/projectRoleMatrix.js';
import { PROJECT_ROLES, INVITABLE_ROLES } from '../../lib/projectPermissions.js';
import { flagOn } from '../../lib/featureFlags.js';
import { ink, ink2, ink3, divider, fieldSolid, block, honeyBg, paper, clay, clayBg } from '../../theme.js';
import { Card, CountHeader, SectionHeader, Chip, ChipRow, Avatar, Tag, Sheet, FieldLabel, ReasonField, reasonOk, Note, pillButton, dangerButton, linkButton } from './ProjectUI.jsx';

export default function ProjectTeam({ p, ui }) {
  const { snap, T } = p;
  const canInvite = p.can('invite.create', { role: 'helper' });
  const qr = flagOn(p.s.featureFlags || {}, 'project_qr_invite');
  useEffect(() => { p.loadInvites(); }, [p.s.projectEventId]); // eslint-disable-line react-hooks/exhaustive-deps
  const rows = [...(snap.hosts || []).map(h => ({ ...h, role: 'host', key: `h-${h.user_id}` })), ...(snap.members || []).map(m => ({ ...m, key: m.member_id }))];
  const invites = p.s.projectInvites || [];
  return (
    <div data-testid="project-team">
      <Card padding={4}>
        {rows.map((m, i) => {
          const open = (snap.tasks || []).filter(t => String(t.assignee_id || '').toLowerCase() === String(m.user_id).toLowerCase() && t.status !== 'done').length;
          const me = String(m.user_id).toLowerCase() === p.userId;
          const inner = (
            <span style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', padding: '10px 0', minHeight: 44 }}>
              <Avatar name={p.personName(m.user_id)} />
              <span style={{ flex: 1, minWidth: 0 }}>
                <span style={{ display: 'flex', gap: 6, alignItems: 'center' }}><strong>{p.personName(m.user_id)}</strong>{me && <Tag tone="ink">{T('bạn', 'you')}</Tag>}</span>
                <span style={{ display: 'block', fontSize: 13, color: ink2 }}>{[p.roleName(m.role), m.lane_id ? p.laneName(m.lane_id) : null].filter(Boolean).join(' · ')}</span>
                {m.role !== 'host' && (m.cap_money || m.cap_checkin) && (
                  <span style={{ display: 'flex', gap: 6, marginTop: 4 }}>{m.cap_money && <Tag tone="ink">💳 {T('Tiền', 'Money')}</Tag>}{m.cap_checkin && <Tag tone="ink">▦ Check-in</Tag>}</span>
                )}
              </span>
              <span style={{ textAlign: 'right' }}><strong>{open}</strong><span style={{ display: 'block', fontSize: 12, color: ink2 }}>{T('việc mở', 'open')}</span></span>
            </span>
          );
          return (
            <div key={m.key}>
              {m.member_id ? (
                <button type="button" onClick={() => ui.openSheet({ kind: 'member', id: m.member_id })} data-testid={`project-member-${m.member_id}`}
                  style={{ display: 'block', width: '100%', background: 'none', border: 0, color: ink, textAlign: 'left', cursor: 'pointer', padding: 0 }}>{inner}</button>
              ) : <div data-testid="project-member-host">{inner}</div>}
              {i < rows.length - 1 && <div style={{ height: 1, background: divider }} />}
            </div>
          );
        })}
      </Card>
      {canInvite ? (<>
        <button type="button" data-testid="project-team-invite" onClick={() => ui.openSheet({ kind: 'invite' })} style={pillButton(false, { marginTop: 12 })}>
          {qr ? `▦ ${T('Mời bằng mã QR', 'Invite by QR')}` : `🔗 ${T('Mời thành viên', 'Invite someone')}`}
        </button>
        {invites.length > 0 && (<>
          <CountHeader title={T('Lời mời còn hiệu lực', 'Live invites')} count={invites.length} />
          <Card padding={4} data-testid="project-team-invites">
            {invites.map((inv, i) => (
              <div key={inv.invite_id}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 0' }}>
                  <span style={{ flex: 1 }}><strong style={{ fontFamily: 'ui-monospace, Menlo, monospace' }}>{inv.short_code}</strong>
                    <span style={{ display: 'block', fontSize: 13, color: ink2 }}>{[p.roleName(inv.role), inv.lane_id ? p.laneName(inv.lane_id) : null, p.inviteExpiry(inv.expires_at)].filter(Boolean).join(' · ')}</span></span>
                  <button type="button" onClick={() => p.revokeInvite(inv.invite_id)} data-testid={`project-invite-revoke-${inv.invite_id}`} aria-label={T(`Huỷ lời mời ${inv.short_code}`, `Cancel invite ${inv.short_code}`)}
                    style={{ ...linkButton, color: 'var(--bb-alert)', minWidth: 44 }}>{T('Huỷ', 'Cancel')}</button>
                </div>
                {i < invites.length - 1 && <div style={{ height: 1, background: divider }} />}
              </div>
            ))}
          </Card>
        </>)}
      </>) : <div style={{ marginTop: 12 }}><Note tone="ink2">{T('Chỉ Chủ sự kiện và Quản lý mời được người.', 'Only the Host and Managers can invite people.')}</Note></div>}
      <SectionHeader title={T('Ai làm được gì', 'Who can do what')} />
      <Matrix p={p} ui={ui} />
      <div data-testid="project-team-privacy" style={{ marginTop: 12, padding: 16, borderRadius: 20, background: fieldSolid, fontSize: 14, color: ink2 }}>
        ⓘ {T('Vai trò làm việc là riêng tư trong dự án. Nó khác với vai trò công khai ở trang Team của chủ sự kiện và không thay đổi trang đó.',
          'Working roles are private to the project. They are separate from the public role on the host’s Team page and don’t change it.')}
      </div>
    </div>
  );
}

const SYMBOL = { yes: '✓', no: '–', lane: '•', grant: '+', propose: '✎' };

function Matrix({ p, ui }) {
  const { T, snap } = p;
  // The viewer's own role column is bold and tinted; the header row sticks under the hub's sticky top while reading down.
  const mine = snap?.is_host ? 0 : MATRIX_COLUMNS.indexOf(snap?.me?.role ?? '');
  const head = { position: 'sticky', top: ui?.stickyTop || 0, zIndex: 2, background: block, paddingBlock: 6 };
  const words = { yes: T('có', 'yes'), no: T('không', 'no'), lane: T('chỉ hạng mục của mình', 'own lane only'), grant: T('nếu Chủ sự kiện cấp', 'if the Host grants it'), propose: T('đề xuất', 'proposes') };
  const short = [T('Chủ', 'Host'), T('QL', 'Mgr'), T('TC', 'Fin'), T('THM', 'Lead'), T('HT', 'Help')];
  return (
    <div data-testid="project-team-matrix" style={{ background: block, borderRadius: 20, padding: 12 }}>
      <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
        <thead data-testid="project-team-matrix-head"><tr><th scope="col" style={{ ...head, textAlign: 'left' }}><span style={{ position: 'absolute', left: -9999 }}>{T('Việc', 'Action')}</span></th>
          {short.map((n, i) => <th key={n} scope="col" title={p.roleName(MATRIX_COLUMNS[i])} style={{ ...head, width: 38, fontSize: 11, color: i === mine ? paper : ink3 }}>
            <abbr title={p.roleName(MATRIX_COLUMNS[i])} aria-current={i === mine ? 'true' : undefined}
              style={{ textDecoration: 'none', display: 'inline-block', minWidth: 32, padding: '3px 0', borderRadius: 999, fontWeight: i === mine ? 900 : 700, background: i === mine ? ink : 'transparent' }}>{n}</abbr></th>)}</tr></thead>
        <tbody>
          {MATRIX_ROWS.map(r => (
            <tr key={r.id} style={{ borderTop: `1px solid ${divider}` }}>
              <th scope="row" style={{ textAlign: 'left', fontWeight: 400, padding: '7px 4px 7px 0' }}>{T(r.vi, r.en)}</th>
              {r.cells.map((c, i) => <td key={i} aria-label={`${p.roleName(MATRIX_COLUMNS[i])}: ${words[c]}`}
                style={{ textAlign: 'center', fontWeight: i === mine ? 900 : 700, fontSize: i === mine ? 15 : undefined, color: c === 'no' ? ink3 : i === mine ? clay : ink,
                  background: i === mine ? `color-mix(in srgb, ${clayBg} 55%, transparent)` : undefined }}>{SYMBOL[c]}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
      <Note>{T('• chỉ trong hạng mục của mình · + Chủ sự kiện cấp được · ✎ đề xuất, Chủ sự kiện duyệt', '• only in their own lane · + the Host can grant it · ✎ proposes, the Host approves')}</Note>
      <Note>{T('Quyền tiền và check-in cho thành viên đội chỉ có hiệu lực khi banbe bật tính năng này.', 'Money and check-in access for team members only takes effect once banbe turns it on.')}</Note>
    </div>
  );
}

export function MemberSheet({ memberId, close, p }) {
  const { T, snap } = p;
  const m = (snap.members || []).find(x => x.member_id === memberId);
  const host = p.can('member.manage');
  const [role, setRole] = useState(m?.role || 'helper');
  const [laneId, setLaneId] = useState(m?.lane_id || null);
  const [money, setMoney] = useState(!!m?.cap_money);
  const [checkin, setCheckin] = useState(!!m?.cap_checkin);
  const [removing, setRemoving] = useState(false);
  const [reason, setReason] = useState('');
  if (!m) return <Sheet title={T('Thành viên', 'Member')} onClose={close}><Note>{T('Người này không còn trong dự án.', 'This person is no longer in the project.')}</Note></Sheet>;
  const finance = role === 'finance';
  const lanes = [...(snap.lanes || [])].sort((a, b) => a.position - b.position);
  const dirty = role !== m.role || (role === 'lane_lead' && laneId !== m.lane_id) || (!finance && (money !== !!m.cap_money || checkin !== !!m.cap_checkin));
  if (removing) {
    return (
      <Sheet title={T('Xoá khỏi dự án', 'Remove from project')} onClose={close} testId="project-member-sheet">
        <h3 style={{ margin: 0 }}>{T(`Xoá ${p.personName(m.user_id)} khỏi dự án?`, `Remove ${p.personName(m.user_id)} from the project?`)}</h3>
        <Note tone="ink2">{T('Việc đang giao cho họ thành chưa giao. Họ cần lời mời mới để vào lại.', "Their open tasks become unassigned. They'd need a new invite to come back.")}</Note>
        {(snap.project?.channels || []).length > 0 && <div data-testid="project-member-channel-nudge" style={{ padding: 14, borderRadius: 16, background: honeyBg, fontSize: 14 }}>🔗 {T('Ai có liên kết kênh của đội vẫn vào được kênh đó. Hãy cân nhắc đổi liên kết.', 'Anyone with a team channel link can still join it. Consider making new links.')}</div>}
        <ReasonField reason={reason} setReason={setReason} T={T} picks={[T('Không tham gia nữa', 'No longer helping'), T('Thêm nhầm người', 'Added by mistake')]} />
        <button type="button" disabled={!reasonOk(reason)} data-testid="project-member-confirm-remove" style={dangerButton({ opacity: reasonOk(reason) ? 1 : 0.4 })}
          onClick={async () => { if (await p.removeMember(memberId, reason.trim())) close(); }}>{T('Xoá khỏi dự án', 'Remove from project')}</button>
        <button type="button" onClick={() => setRemoving(false)} style={linkButton}>{T('Không xoá', 'Keep them')}</button>
      </Sheet>
    );
  }
  const Toggle = ({ on, set, label, note, testId }) => (
    <label style={{ display: 'flex', gap: 12, alignItems: 'flex-start', minHeight: 44, cursor: host && !finance ? 'pointer' : 'default' }}>
      <input type="checkbox" role="switch" checked={finance || on} disabled={!host || finance} onChange={e => set(e.target.checked)} data-testid={testId} style={{ width: 22, height: 22, marginTop: 2 }} />
      <span><strong style={{ display: 'block' }}>{label}</strong><span style={{ fontSize: 13, color: ink2 }}>{note}</span></span>
    </label>
  );
  return (
    <Sheet title={p.personName(m.user_id)} onClose={close} testId="project-member-sheet">
      <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
        <Avatar name={p.personName(m.user_id)} size={52} />
        <span><strong>{p.roleName(role)}</strong><span style={{ display: 'block', fontSize: 14, color: ink2 }}>{p.roleNote(role)}</span></span>
      </div>
      {host && (<>
        <FieldLabel>{T('Vai trò', 'Role')}</FieldLabel>
        <ChipRow>{PROJECT_ROLES.map(r => <Chip key={r} title={p.roleName(r)} selected={role === r} testId={`project-member-role-${r}`} onClick={() => { setRole(r); if (r === 'lane_lead' && !laneId) setLaneId(lanes[0]?.id || null); }} />)}</ChipRow>
        {role === 'lane_lead' && (<>
          <FieldLabel>{T('Hạng mục phụ trách', 'Lane owned')}</FieldLabel>
          <ChipRow>{lanes.map(l => <Chip key={l.id} title={l.name} selected={laneId === l.id} onClick={() => setLaneId(l.id)} testId={`project-member-lane-${l.id}`} />)}</ChipRow>
        </>)}
      </>)}
      <FieldLabel>{T('Quyền nhạy cảm', 'Sensitive access')}</FieldLabel>
      <Toggle on={money} set={setMoney} label={T('Tiền & hoàn tiền', 'Money & refunds')} note={T('Xem số tiền, xác nhận thanh toán, xử lý hoàn tiền.', 'See amounts, confirm payments, handle refunds.')} testId="project-member-cap-money" />
      <Toggle on={checkin} set={setCheckin} label="Check-in" note={T('Quét vé và đánh dấu khách vào cửa. Không thấy số tiền.', 'Scan tickets and tick guests in. Sees no amounts.')} testId="project-member-cap-checkin" />
      <Note>{finance ? T('Tài chính & cổng luôn có hai quyền này.', 'Finance & door always has both.')
        : host ? T('Chỉ có hiệu lực khi banbe bật quyền tiền và check-in cho đội.', 'Takes effect once banbe turns on team money and check-in.')
          : T('Chỉ Chủ sự kiện đổi được quyền.', 'Only the Host can change access.')}</Note>
      {host && (<>
        <button type="button" disabled={!dirty || (role === 'lane_lead' && !laneId)} data-testid="project-member-save" style={pillButton(true, { opacity: dirty ? 1 : 0.4 })}
          onClick={async () => { if (await p.setMember(memberId, { role, laneId, capMoney: finance || money, capCheckin: finance || checkin })) close(); }}>{T('Lưu thay đổi', 'Save changes')}</button>
        <button type="button" data-testid="project-member-remove" onClick={() => setRemoving(true)} style={dangerButton()}>{T('Xoá khỏi dự án', 'Remove from project')}</button>
      </>)}
    </Sheet>
  );
}

export function InviteSheet({ close, p }) {
  const { T, snap } = p;
  const host = snap.is_host === true;
  const qr = flagOn(p.s.featureFlags || {}, 'project_qr_invite');
  const roles = host ? INVITABLE_ROLES.host : INVITABLE_ROLES.manager;
  const lanes = [...(snap.lanes || [])].sort((a, b) => a.position - b.position);
  const [role, setRole] = useState('helper');
  const [laneId, setLaneId] = useState(null);
  const [single, setSingle] = useState(true);
  const [invite, setInvite] = useState(null);
  const [copied, setCopied] = useState(false);
  const [img, setImg] = useState(null);
  const minting = useRef(0);
  const ready = role !== 'lane_lead' || !!laneId;
  const link = invite ? `https://www.banbe.app/join/${invite.token}` : '';

  // QR mode: mint at once and again 400 ms after the last change; the replaced invite is cancelled.
  useEffect(() => {
    if (!qr || !ready) return undefined;
    const run = ++minting.current;
    const t = setTimeout(async () => {
      const prev = invite;
      const made = await p.createInvite(role, laneId, single ? 1 : p.LIMITS.inviteMaxUses);
      if (!made) return;
      if (run !== minting.current) { p.revokeInvite(made.invite_id); return; }
      setInvite(made); setCopied(false);
      if (prev) p.revokeInvite(prev.invite_id);
    }, invite ? 400 : 0);
    return () => clearTimeout(t);
  }, [qr, role, laneId, single]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!qr || !link) { setImg(null); return; }
    QRCode.toDataURL(link, { margin: 1, width: 420, color: { dark: '#000000', light: '#FFFFFF' } }).then(setImg).catch(() => setImg(null));
  }, [qr, link]);

  const copy = async () => { try { await navigator.clipboard.writeText(link); setCopied(true); } catch { /* the code stays on screen */ } };
  const share = async () => {
    const text = p.inviteShareText(invite);
    if (navigator.share) { try { await navigator.share({ text }); } catch { /* cancelled */ } } else { try { await navigator.clipboard.writeText(text); setCopied(true); } catch { /* ignore */ } }
  };

  return (
    <Sheet title={T('Mời thành viên', 'Invite someone')} onClose={close} testId="project-invite-sheet">
      <Note tone="ink2">{T('Người được mời nhận vai bạn đặt sẵn. Họ chỉ thấy dự án này, không thấy các sự kiện khác của bạn.', 'Invitees get the role you preset. They see this project only, not your other events.')}</Note>
      <FieldLabel>{T('Vai trò', 'Role')}</FieldLabel>
      <ChipRow>{roles.map(r => <Chip key={r} title={p.roleName(r)} selected={role === r} testId={`project-invite-role-${r}`} onClick={() => { setRole(r); if (!qr) setInvite(null); if (r === 'lane_lead' && !laneId) setLaneId(lanes[0]?.id || null); }} />)}</ChipRow>
      <Note tone="ink2">{p.roleNote(role)}</Note>
      {role === 'lane_lead' && (<>
        <FieldLabel>{T('Hạng mục', 'Lane')}</FieldLabel>
        <ChipRow>{lanes.map(l => <Chip key={l.id} title={l.name} selected={laneId === l.id} onClick={() => { setLaneId(l.id); if (!qr) setInvite(null); }} testId={`project-invite-lane-${l.id}`} />)}</ChipRow>
      </>)}
      {!host && <Note testId="project-invite-manager-note">{T('Quản lý chỉ mời được Trưởng hạng mục và Hỗ trợ. Quản lý và Tài chính & cổng do Chủ sự kiện mời.', 'Managers can invite Lane leads and Helpers only. Manager and Finance & door invites come from the Host.')}</Note>}
      {qr ? (<>
        <div style={{ background: '#fff', color: '#000', borderRadius: 22, padding: 18, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
          {img ? <img src={img} alt={T('Mã QR mời vào đội', 'Team invite QR code')} data-testid="project-invite-qr" width={210} height={210} /> : <div style={{ width: 210, height: 210 }} />}
          {invite && <strong data-testid="project-invite-code" style={{ fontFamily: 'ui-monospace, Menlo, monospace', fontSize: 22, letterSpacing: 2 }}>{invite.short_code}</strong>}
          <span data-testid="project-invite-uses" style={{ fontSize: 13, opacity: 0.65 }}>
            {T(`Hết hạn sau ${p.LIMITS.inviteHours} giờ · `, `Expires in ${p.LIMITS.inviteHours} hours · `)}{single ? T('dùng một lần', 'single use') : T(`tối đa ${p.LIMITS.inviteMaxUses} người`, `up to ${p.LIMITS.inviteMaxUses} people`)}
          </span>
        </div>
        <label style={{ display: 'flex', gap: 12, alignItems: 'flex-start', minHeight: 44, cursor: 'pointer' }}>
          <input type="checkbox" role="switch" checked={single} onChange={e => setSingle(e.target.checked)} data-testid="project-invite-single" style={{ width: 22, height: 22, marginTop: 2 }} />
          <span><strong style={{ display: 'block' }}>{T('Chỉ dùng một lần', 'Single use only')}</strong>
            <span style={{ fontSize: 13, color: ink2 }}>{T(`Tắt để tối đa ${p.LIMITS.inviteMaxUses} người quét cùng một mã, ví dụ khi dán ở buổi họp đội.`, `Turn off to let up to ${p.LIMITS.inviteMaxUses} people scan the same code, for example at a team meeting.`)}</span></span>
        </label>
      </>) : invite ? (
        <div style={{ background: fieldSolid, borderRadius: 20, padding: 18, textAlign: 'center' }}>
          <div style={{ fontSize: 13, color: ink2 }}>{T(`Mã mời (hết hạn sau ${p.LIMITS.inviteHours} giờ, dùng một lần)`, `Invite code (expires in ${p.LIMITS.inviteHours} hours, single use)`)}</div>
          <div data-testid="project-invite-code" style={{ fontFamily: 'ui-monospace, Menlo, monospace', fontSize: 30, fontWeight: 800, letterSpacing: 3 }}>{invite.short_code}</div>
        </div>
      ) : (
        <button type="button" disabled={!ready || p.s.projectBusy} data-testid="project-invite-create" style={pillButton(true, { opacity: ready ? 1 : 0.4 })}
          onClick={async () => { const inv = await p.createInvite(role, laneId, 1); if (inv) { setInvite(inv); setCopied(false); } }}>{T('Tạo mã mời', 'Create invite code')}</button>
      )}
      {invite && (
        <div style={{ display: 'flex', gap: 10 }}>
          <button type="button" onClick={copy} data-testid="project-invite-copy" style={pillButton(true)}>{copied ? `✓ ${T('Đã sao chép', 'Copied')}` : `🔗 ${T('Sao chép liên kết', 'Copy link')}`}</button>
          <button type="button" onClick={share} data-testid="project-invite-share" style={pillButton(false)}>{T('Chia sẻ', 'Share')}</button>
        </div>
      )}
      <Note>{qr ? T('Mã QR chỉ chứa mã mời. Vai trò do banbe giữ, nên sửa liên kết không đổi được vai trò. Đổi lựa chọn sẽ tạo mã mới và huỷ mã cũ.', "The QR holds only the invite code. banbe keeps the role, so editing the link can't change it. Changing a choice makes a new code and cancels the old one.")
        : T('Đổi vai trò sẽ tạo mã mới. Mã cũ vẫn dùng được cho tới khi hết hạn hoặc bạn huỷ ở thẻ Đội.', 'Changing the role makes a new code. The old one still works until it expires or you cancel it on the Team tab.')}</Note>
    </Sheet>
  );
}

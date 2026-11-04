// Money & door tab of the web Event Project Hub (note 76). The Host sees the numbers and goes to the EXISTING screens
// (Verifications, its refund section, Attendance); payout and cancelling stay with the Host. Everyone else sees the v6
// lock card; a member the Host granted money or check-in is told it isn't on yet (phases 9a–9c). Same as iOS ProjectMoneyTab.
import { useEffect, useState } from 'react';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { formatMoney } from '../../lib/eventMarket.js';
import { ink, ink2, ink3, clay, divider, alert } from '../../theme.js';
import { Card, SectionHeader, Avatar, Tag, Note } from './ProjectUI.jsx';

export default function ProjectMoney({ p }) {
  const { openVerifications, openVerificationsRefunds, openAttendance } = useBanBe();
  const { snap, T } = p;
  useEffect(() => { p.loadMoney(); p.loadDoor(); }, [p.s.projectEventId, p.moneyAccess, p.doorAccess]); // eslint-disable-line react-hooks/exhaustive-deps
  if (!p.moneyAccess) return p.doorAccess ? <Door p={p} /> : <Lock p={p} />;
  const m = p.s.projectMoney;
  const holders = (snap.members || []).filter(x => x.cap_money || x.cap_checkin);
  const stat = (value, label, hot, testId) => (
    <div data-testid={testId} style={{ flex: '1 1 140px', padding: 14, borderRadius: 18, background: hot ? 'color-mix(in srgb, var(--bb-alert) 10%, transparent)' : 'var(--bb-block)' }}>
      <div style={{ fontSize: 22, fontWeight: 700, color: hot ? alert : ink, fontVariantNumeric: 'tabular-nums' }}>{value}</div>
      <div style={{ fontSize: 13, fontWeight: 600, color: ink2 }}>{label}</div>
    </div>
  );
  const row = (icon, title, detail, hot, testId, run) => (
    <button type="button" onClick={run} data-testid={testId}
      style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', minHeight: 56, padding: '10px 0', background: 'none', border: 0, color: ink, textAlign: 'left', cursor: 'pointer', flexWrap: 'wrap' }}>
      <span aria-hidden style={{ color: clay, fontSize: 20, width: 28 }}>{icon}</span>
      <span style={{ flex: '1 1 160px' }}><strong style={{ display: 'block' }}>{title}</strong><span style={{ fontSize: 13, color: hot ? alert : ink2 }}>{detail}</span></span>
      <span aria-hidden style={{ color: ink3 }}>›</span>
    </button>
  );
  return (
    <div data-testid="project-money-tab">
      <div data-testid="project-money-stats" style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
        {stat(m ? formatMoney(m.confirmedAmount, 'VND') : '—', T('Đã xác nhận', 'Confirmed'), false, 'project-money-confirmed')}
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, flex: '1 1 100%' }}>
          {stat(m ? m.awaiting : '—', T('Chờ xác nhận', 'Awaiting'), (m?.awaiting || 0) > 0, 'project-money-awaiting')}
          {stat(m ? m.refunds : '—', T('Xin hoàn', 'Refund asks'), (m?.refunds || 0) > 0, 'project-money-refund-count')}
        </div>
      </div>
      <SectionHeader title={T('Việc cần làm', 'Act on it')} />
      <Card padding={4}>
        {row('✔', T('Kiểm tra thanh toán', 'Check payments'),
          (m?.awaiting || 0) > 0 ? T(`${m.awaiting} khách chờ bạn xác nhận`, m.awaiting === 1 ? '1 guest waiting for you' : `${m.awaiting} guests waiting for you`) : T('Không ai đang chờ', 'Nobody is waiting'),
          (m?.awaiting || 0) > 0, 'project-money-verify', () => openVerifications('eventProject'))}
        <div style={{ height: 1, background: divider }} />
        {row('↺', T('Hoàn tiền', 'Refunds'),
          (m?.refunds || 0) > 0 ? T(`${m.refunds} yêu cầu đang mở`, m.refunds === 1 ? '1 open request' : `${m.refunds} open requests`) + (m.refundsOverdue ? T(` · ${m.refundsOverdue} quá hạn`, ` · ${m.refundsOverdue} overdue`) : '') : T('Không có yêu cầu hoàn tiền', 'No refund requests'),
          (m?.refunds || 0) > 0, 'project-money-refunds', () => openVerificationsRefunds('eventProject'))}
        <div style={{ height: 1, background: divider }} />
        {row('▦', T('Check-in ở cửa', 'Door check-in'), m ? T(`${m.checkedIn}/${m.seats} chỗ đã vào`, `${m.checkedIn}/${m.seats} seats in`) : '', false, 'project-money-door',
          () => openAttendance(snap.event?.id || p.s.projectEventId, 'eventProject'))}
      </Card>
      <SectionHeader title={T('Quyền của đội', 'Team access')} />
      <Card data-testid="project-money-team">
        {holders.length === 0 ? <Note tone="ink2">{T('Chưa ai trong đội có quyền tiền hoặc check-in. Cấp ở thẻ Đội.', 'Nobody on the team has money or check-in access. Grant it on the Team tab.')}</Note>
          : holders.map(x => (
            <div key={x.member_id} style={{ display: 'flex', alignItems: 'center', gap: 10, minHeight: 44 }}>
              <Avatar name={p.personName(x.user_id)} size={32} /><strong style={{ flex: 1 }}>{p.personName(x.user_id)}</strong>
              {x.cap_money && <Tag tone="ink">💳 {T('Tiền', 'Money')}</Tag>}{x.cap_checkin && <Tag tone="ink">▦ Check-in</Tag>}
            </div>
          ))}
        <div style={{ marginTop: 8 }}><Note>{T('Hiện chỉ bạn làm được các việc này. Quyền của đội có hiệu lực khi banbe bật tính năng giao quyền tiền và check-in.', 'For now only you can do these. Team access takes effect once banbe turns on team money and check-in.')}</Note></div>
      </Card>
      <div style={{ marginTop: 14 }}><Note tone="ink2" testId="project-money-host-only">🔒 {T('Tài khoản nhận tiền và huỷ sự kiện luôn do bạn làm, không giao cho đội.', "The payout account and cancelling the event stay with you. They're never handed to the team.")}</Note></div>
    </div>
  );
}

function Lock({ p }) {
  const { snap, T } = p;
  const me = snap.me;
  const granted = !!(me && (me.cap_money || me.cap_checkin));
  const list = [me?.cap_money ? T('tiền', 'money') : null, me?.cap_checkin ? 'check-in' : null].filter(Boolean).join(T(' và ', ' and '));
  const holders = [...(snap.hosts || []).map(h => h.user_id), ...(snap.members || []).filter(x => x.cap_money || x.cap_checkin).map(x => x.user_id)];
  return (
    <Card style={{ textAlign: 'center', padding: '28px 16px' }} data-testid={granted ? 'project-money-lock-granted' : 'project-money-lock'}>
      <div aria-hidden style={{ fontSize: 28, color: clay }}>🔒</div>
      <h3 style={{ margin: '10px 0 6px' }}>{granted ? T('Quyền của bạn chưa bật', "Your access isn't on yet") : T('Bạn chưa có quyền ở mục này', "You don't have access here")}</h3>
      <p style={{ margin: 0, color: ink2, fontSize: 14 }}>{granted ? T(`Chủ sự kiện đã cấp cho bạn quyền ${list}. Quyền này có hiệu lực khi banbe bật tính năng giao quyền cho đội.`, `The Host gave you ${list} access. It starts working once banbe turns on team access.`)
        : T('Tiền, hoàn tiền và check-in chỉ dành cho người được Chủ sự kiện cấp quyền.', 'Money, refunds and check-in are for people the Host has given access.')}</p>
      <p style={{ margin: '10px 0 0', color: ink3, fontSize: 13 }} aria-label={T('Người có quyền: ', 'People with access: ') + holders.map(u => p.personName(u)).join(', ')}>{holders.map(u => p.personName(u)).join(', ')}</p>
    </Card>
  );
}

/** Phase 9a (migration 212, switch project_delegate_checkin): the door for a team member with check-in access. Names and
 * check-in state only; checking a party in admits everyone in it not yet in; every check-in is recorded for the Host. */
function Door({ p }) {
  const { T } = p;
  const [q, setQ] = useState('');
  const guests = p.s.projectDoor || [];
  const query = q.trim().toLowerCase();
  const shown = query ? guests.filter(g => g.names.join(' ').toLowerCase().includes(query)) : guests;
  const inside = guests.reduce((a, g) => a + Math.min(g.inside, g.party), 0), total = guests.reduce((a, g) => a + g.party, 0);
  return (
    <div data-testid="project-door">
      <h2 style={{ margin: 0, fontSize: 20 }}>{T('Check-in ở cửa', 'Door check-in')}</h2>
      <div data-testid="project-door-count" style={{ fontWeight: 600, color: ink2, margin: '4px 0' }}>{T(`${inside}/${total} người đã vào`, `${inside} of ${total} people in`)}</div>
      <Note>{T('Chỉ có tên khách. Tiền và hoàn tiền vẫn do Chủ sự kiện làm. Mỗi lần check-in đều được ghi lại cho Chủ sự kiện.', 'Names only. Money and refunds stay with the Host. Every check-in is recorded for the Host.')}</Note>
      <input value={q} onChange={e => setQ(e.target.value)} placeholder={T('Tìm tên khách', 'Search guests')} aria-label={T('Tìm tên khách', 'Search guests')} data-testid="project-door-search"
        style={{ width: '100%', boxSizing: 'border-box', margin: '12px 0', font: 'inherit', fontSize: 16, padding: '12px 14px', borderRadius: 14, border: 0, background: 'var(--bb-field)', color: ink }} />
      {p.s.projectDoor == null ? <Note>{T('Đang tải…', 'Loading…')}</Note> : shown.length === 0
        ? <Note tone="ink2">{guests.length ? T('Không có tên nào khớp.', 'No names match.') : T('Chưa có khách đã xác nhận.', 'No confirmed guests yet.')}</Note> : (
          <Card padding={4} data-testid="project-door-list">
            {shown.map((g, i) => {
              const all = g.inside >= g.party;
              return (
                <div key={g.bookingId}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 0' }}>
                    <span style={{ flex: 1 }}><strong style={{ display: 'block' }}>{g.names.join(', ')}</strong>
                      <span style={{ fontSize: 13, color: ink2 }}>{T(`${g.party} người · ${Math.min(g.inside, g.party)} đã vào`, `${g.party === 1 ? '1 person' : `${g.party} people`} · ${Math.min(g.inside, g.party)} in`)}</span></span>
                    {all ? <span data-testid={`project-door-in-${g.bookingId}`} style={{ color: ink2, fontWeight: 600, minHeight: 44, display: 'grid', placeItems: 'center' }}>✓ {T('Đã vào', 'In')}</span>
                      : <button type="button" disabled={p.s.projectBusy} onClick={() => p.checkInGuest(g.bookingId)} data-testid={`project-door-checkin-${g.bookingId}`}
                        aria-label={T(`Check-in cho ${g.names.join(', ')}`, `Check in ${g.names.join(', ')}`)}
                        style={{ minHeight: 44, padding: '0 14px', borderRadius: 999, border: 0, background: ink, color: 'var(--bb-bg)', fontWeight: 700, cursor: 'pointer' }}>{T('Check-in', 'Check in')}</button>}
                  </div>
                  {i < shown.length - 1 && <div style={{ height: 1, background: divider }} />}
                </div>
              );
            })}
          </Card>
        )}
    </div>
  );
}

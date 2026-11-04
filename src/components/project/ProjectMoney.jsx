// Money & door tab of the web Event Project Hub (note 76). The Host sees the numbers and goes to the EXISTING screens
// (Verifications, its refund section, Attendance); payout and cancelling stay with the Host. Everyone else sees the v6
// lock card; a member the Host granted money or check-in is told it isn't on yet (phases 9a–9c). Same as iOS ProjectMoneyTab.
import { useEffect, useRef, useState } from 'react';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { formatMoney } from '../../lib/eventMarket.js';
import { ink, ink2, ink3, clay, divider, alert } from '../../theme.js';
import { Card, SectionHeader, Avatar, Tag, Note, Sheet, TextField, ReasonField, reasonOk, Chip, ChipRow, FieldLabel, pillButton, dangerButton } from './ProjectUI.jsx';
import { refundRowState, teamRefundRequests, refundDelegates, teamGrantsOver } from '../../lib/projectPresentation.js';

export default function ProjectMoney({ p }) {
  const { openVerifications, openVerificationsRefunds, openAttendance } = useBanBe();
  const { snap, T } = p;
  useEffect(() => { p.loadMoney(); p.loadPayments(); p.loadRefunds(); p.loadDoor(); }, [p.s.projectEventId, p.moneyAccess, p.doorAccess, p.paymentsAccess, p.refundsAccess]); // eslint-disable-line react-hooks/exhaustive-deps
  if (!p.moneyAccess) {
    if (!p.paymentsAccess && !p.doorAccess && !p.refundsAccess) return <Lock p={p} />;
    return <div style={{ display: 'flex', flexDirection: 'column', gap: 28 }}>{p.paymentsAccess && <Payments p={p} />}{p.refundsAccess && <Refunds p={p} />}{p.doorAccess && <Door p={p} />}</div>;
  }
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
      <HostRefunds p={p} />
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

/** Phase 9b (migration 214, switch project_delegate_payments): payments waiting for a check, for a team member with money
 * access. Amounts and references, the proof of the one booking being checked (view only, each open recorded), and
 * "Money received". "Can't find it" and rejecting stay with the Host; invoices and receipts never appear here. */
function Payments({ p }) {
  const { T } = p;
  const [proof, setProof] = useState(null);
  const v = p.s.projectPayments;
  const rows = v?.awaiting || [];
  return (
    <div data-testid="project-payments">
      <h2 style={{ margin: 0, fontSize: 20 }}>{T('Thanh toán cần kiểm tra', 'Payments to check')}</h2>
      {v && <div data-testid="project-payments-confirmed" style={{ fontWeight: 600, color: ink2, margin: '4px 0' }}>
        {T('Đã xác nhận: ', 'Confirmed: ')}{formatMoney(v.confirmed_amount || 0, 'VND')}{T(` · ${v.confirmed_seats || 0} chỗ`, ` · ${v.confirmed_seats || 0} seats`)}</div>}
      <Note>{T('Kiểm tra tài khoản nhận tiền trước khi bấm. “Không thấy tiền” và từ chối vẫn do Chủ sự kiện làm. Mỗi lần xác nhận và mở ảnh đều được ghi lại.', "Check the receiving account before you tap. “Can't find it” and rejecting stay with the Host. Every confirmation and every proof you open is recorded.")}</Note>
      <div style={{ marginTop: 12 }}>
        {!v ? <Note>{T('Đang tải…', 'Loading…')}</Note> : rows.length === 0 ? <Note tone="ink2" testId="project-payments-empty">{T('Không có khoản nào đang chờ.', 'Nothing is waiting for a check.')}</Note> : (
          <Card padding={4} data-testid="project-payments-list">
            {rows.map((r, i) => (
              <div key={r.booking_id}>
                <div style={{ padding: '10px 0', display: 'flex', flexDirection: 'column', gap: 8 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}><strong>{r.name}</strong><strong style={{ fontVariantNumeric: 'tabular-nums' }}>{formatMoney(r.amount, 'VND')}</strong></div>
                  <span style={{ fontSize: 13, color: ink2 }}>{[T(`${r.qty} chỗ`, r.qty === 1 ? '1 seat' : `${r.qty} seats`), r.payment_ref ? T(`Mã ${r.payment_ref}`, `Ref ${r.payment_ref}`) : null].filter(Boolean).join(' · ')}</span>
                  <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                    {r.has_proof && <button type="button" data-testid={`project-payments-proof-${r.booking_id}`}
                      onClick={async () => setProof({ name: r.name, url: await p.openProof(r.booking_id) })}
                      style={{ minHeight: 44, padding: '0 12px', borderRadius: 999, border: 0, background: 'var(--bb-block-inset)', color: ink, fontWeight: 600, cursor: 'pointer' }}>{T('Xem ảnh chuyển khoản', 'View transfer proof')}</button>}
                    <button type="button" disabled={p.s.projectBusy} onClick={() => p.confirmPayment(r.booking_id)} data-testid={`project-payments-confirm-${r.booking_id}`}
                      aria-label={T(`Đã nhận tiền của ${r.name}`, `Money received from ${r.name}`)}
                      style={{ marginLeft: 'auto', minHeight: 44, padding: '0 14px', borderRadius: 999, border: 0, background: ink, color: 'var(--bb-bg)', fontWeight: 700, cursor: 'pointer' }}>{T('Đã nhận tiền', 'Money received')}</button>
                  </div>
                </div>
                {i < rows.length - 1 && <div style={{ height: 1, background: divider }} />}
              </div>
            ))}
          </Card>
        )}
      </div>
      {proof && (
        <div onClick={() => setProof(null)} style={{ position: 'absolute', inset: 0, zIndex: 30, background: 'rgba(12,12,12,0.6)', display: 'flex', alignItems: 'flex-end' }}>
          <div role="dialog" aria-modal="true" aria-label={T('Ảnh chuyển khoản', 'Transfer proof')} data-testid="project-proof" onClick={e => e.stopPropagation()}
            style={{ background: 'var(--bb-bg)', color: ink, width: '100%', borderRadius: '22px 22px 0 0', padding: 20, boxSizing: 'border-box' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}><strong>{proof.name}</strong>
              <button type="button" onClick={() => setProof(null)} aria-label="Close" data-testid="project-proof-close" style={{ width: 44, height: 44, borderRadius: '50%', border: 0, background: 'var(--bb-block-inset)', color: ink, cursor: 'pointer' }}>✕</button></div>
            <div style={{ marginTop: 12, minHeight: 240, borderRadius: 16, background: 'var(--bb-block-inset)', display: 'grid', placeItems: 'center', overflow: 'hidden' }}>
              {proof.url ? <img src={proof.url} alt={T('Ảnh chuyển khoản', 'Transfer proof')} draggable={false} onContextMenu={e => e.preventDefault()} style={{ maxWidth: '100%', userSelect: 'none' }} />
                : <span style={{ color: ink2 }}>{T('Chưa có ảnh để hiển thị.', 'No image to show.')}</span>}
            </div>
            <div style={{ marginTop: 10 }}><Note>{T(`Chỉ xem. Lần mở này đã được ghi lại cho Chủ sự kiện, và liên kết đóng sau ${p.LIMITS.proofUrlSeconds} giây.`, `View only. This open was recorded for the Host, and the link closes after ${p.LIMITS.proofUrlSeconds} seconds.`)}</Note></div>
          </div>
        </div>
      )}
    </div>
  );
}

const smallButton = (primary = false, extra) => ({ minHeight: 44, padding: '0 14px', borderRadius: 999, border: 0, cursor: 'pointer', fontWeight: primary ? 700 : 600,
  background: primary ? ink : 'var(--bb-block-inset)', color: primary ? 'var(--bb-bg)' : ink, ...extra });

/** Phase 9c (migration 215, switch project_delegate_refunds): refunds the Host owes, for a team member with money access.
 * Name, amount, due day and the guest's refund account (needed to send the money). Under 'host' approval the transfer is
 * recorded for the Host, who tells the guest by approving; under 'finance_alone' "Mark refund sent" tells the guest at once.
 * Refund proofs, payment proofs and invoices never appear here: a receipt I attach shows only as "Receipt attached". */
function Refunds({ p }) {
  const { T } = p;
  const [open, setOpen] = useState(null);
  const v = p.s.projectRefunds;
  const rows = v?.claims || [];
  const mode = v?.mode || p.refundMode;
  const claim = open ? rows.find(c => c.claim_id === open) : null;
  return (
    <div data-testid="project-refunds">
      <h2 style={{ margin: 0, fontSize: 20 }}>{T('Hoàn tiền cần gửi', 'Refunds to send')}</h2>
      <div style={{ margin: '4px 0' }}><Note>{mode === 'finance_alone'
        ? T('Chủ sự kiện cho phép bạn tự báo đã hoàn tiền. Mỗi lần đều được ghi lại cho Chủ sự kiện.', 'The Host lets you mark refunds sent yourself. Every one is recorded for the Host.')
        : T('Bạn chuyển tiền rồi ghi nhận lại. Chủ sự kiện duyệt trước khi khách được báo.', 'You send the money, then record it. The Host approves before the guest is told.')}</Note></div>
      <div style={{ marginTop: 12 }}>
        {!v ? <Note>{T('Đang tải…', 'Loading…')}</Note> : rows.length === 0 ? <Note tone="ink2" testId="project-refunds-empty">{T('Không có khoản hoàn tiền nào cần gửi.', 'No refunds to send.')}</Note> : (
          <Card padding={4} data-testid="project-refunds-list">
            {rows.map((c, i) => {
              const st = refundRowState(c, mode);
              const detail = st.state === 'waiting'
                ? (st.mine ? T('Bạn đã ghi nhận · đang chờ Chủ sự kiện', 'You recorded this · waiting for the Host') : T('Đang chờ Chủ sự kiện', 'Waiting for Host'))
                : p.refundDueText(c.refund_due_at);
              const body = (
                <>
                  <span style={{ display: 'flex', justifyContent: 'space-between', gap: 8, alignItems: 'baseline' }}>
                    <strong>{c.name}</strong><strong style={{ fontVariantNumeric: 'tabular-nums' }}>{formatMoney(c.amount, 'VND')}</strong>
                  </span>
                  <span style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
                    <span data-testid={`project-refunds-state-${c.claim_id}`} style={{ fontSize: 13, color: ink2 }}>{detail}</span>
                    {c.dispute_open && <Tag tone="alert" testId={`project-refunds-disputed-${c.claim_id}`}>{T('Đang tranh chấp', 'Disputed')}</Tag>}
                  </span>
                  {st.declined && <span data-testid={`project-refunds-declined-${c.claim_id}`} style={{ fontSize: 13, color: alert }}>{T(`Chủ sự kiện từ chối: ${st.declined}`, `Host declined: ${st.declined}`)}</span>}
                </>
              );
              return (
                <div key={c.claim_id}>
                  {st.state === 'waiting'
                    ? <div data-testid={`project-refunds-row-${c.claim_id}`} style={{ padding: '10px 0', display: 'flex', flexDirection: 'column', gap: 6 }}>{body}</div>
                    : <button type="button" onClick={() => setOpen(c.claim_id)} data-testid={`project-refunds-row-${c.claim_id}`}
                      style={{ width: '100%', padding: '10px 0', display: 'flex', flexDirection: 'column', gap: 6, background: 'none', border: 0, color: ink, textAlign: 'left', cursor: 'pointer', font: 'inherit' }}>{body}</button>}
                  {i < rows.length - 1 && <div style={{ height: 1, background: divider }} />}
                </div>
              );
            })}
          </Card>
        )}
      </div>
      {claim && <RefundSheet p={p} claim={claim} mode={mode} close={() => setOpen(null)} />}
    </div>
  );
}

function CopyRow({ label, value, testId, T }) {
  const [done, setDone] = useState(false);
  const copy = async () => {
    try { await navigator.clipboard.writeText(value); } catch { /* clipboard blocked: the value is on screen to copy by hand */ }
    setDone(true); setTimeout(() => setDone(false), 1500);
  };
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10, minHeight: 48 }}>
      <span style={{ flex: 1, minWidth: 0 }}>
        <span style={{ display: 'block', fontSize: 12, fontWeight: 700, letterSpacing: 0.6, color: ink3 }}>{label.toUpperCase()}</span>
        <span data-testid={`${testId}-value`} style={{ display: 'block', fontWeight: 600, overflowWrap: 'anywhere', userSelect: 'all' }}>{value}</span>
      </span>
      <button type="button" onClick={copy} data-testid={testId} aria-label={T(`Sao chép ${label}`, `Copy ${label}`)} style={smallButton(false)}>{done ? T('Đã chép', 'Copied') : T('Sao chép', 'Copy')}</button>
    </div>
  );
}

function RefundSheet({ p, claim, mode, close }) {
  const { T } = p;
  const [note, setNote] = useState('');
  const [file, setFile] = useState(null);
  const fileRef = useRef(null);
  const st = refundRowState(claim, mode);
  const a = claim.account;
  const markSent = st.cta === 'markSent';
  const off = st.state !== 'ready' || p.s.projectBusy;
  return (
    <Sheet title={T('Gửi hoàn tiền', 'Send a refund')} onClose={close} testId="project-refund-sheet">
      <div>
        <div style={{ fontSize: 13, color: ink2 }}>{claim.name}{claim.refund_due_at ? ` · ${p.refundDueText(claim.refund_due_at)}` : ''}</div>
        <div data-testid="project-refund-amount" style={{ fontSize: 28, fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{formatMoney(claim.amount, 'VND')}</div>
        {claim.dispute_open && <div style={{ marginTop: 6 }}><Tag tone="alert">{T('Đang tranh chấp', 'Disputed')}</Tag></div>}
      </div>
      {st.declined && <Note tone="alert" testId="project-refund-declined">{T(`Chủ sự kiện từ chối: ${st.declined}`, `Host declined: ${st.declined}`)}</Note>}
      <div>
        <FieldLabel>{T('Tài khoản nhận hoàn tiền', 'Refund account')}</FieldLabel>
        {a ? (
          <Card padding={6} style={{ marginTop: 8 }}>
            <CopyRow T={T} label={T('Ngân hàng', 'Bank')} value={a.bank_name} testId="project-refund-copy-bank" />
            <div style={{ height: 1, background: divider }} />
            <CopyRow T={T} label={T('Số tài khoản', 'Account number')} value={a.account_number} testId="project-refund-copy-number" />
            <div style={{ height: 1, background: divider }} />
            <CopyRow T={T} label={T('Chủ tài khoản', 'Account holder')} value={a.account_holder_name} testId="project-refund-copy-holder" />
          </Card>
        ) : <div style={{ marginTop: 8 }}><Note tone="ink2" testId="project-refund-no-account">{T('Khách chưa thêm tài khoản nhận hoàn tiền.', "The guest hasn't added a refund account yet.")}</Note></div>}
      </div>
      {a && <>
        <TextField label={T('Ghi chú (không bắt buộc)', 'Note (optional)')} value={note} onChange={setNote} limit={280} multiline placeholder={T('Ví dụ: đã chuyển lúc 14:05', 'For example: sent at 14:05')} testId="project-refund-note" />
        <div>
          <input ref={fileRef} type="file" accept="image/*,application/pdf" hidden data-testid="project-refund-file" onChange={e => setFile(e.target.files?.[0] || null)} />
          {file ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span data-testid="project-refund-receipt" style={{ flex: 1, fontWeight: 600 }}>✓ {T('Đã đính kèm biên lai', 'Receipt attached')}</span>
              <button type="button" onClick={() => { setFile(null); if (fileRef.current) fileRef.current.value = ''; }} style={smallButton(false)}>{T('Bỏ', 'Remove')}</button>
            </div>
          ) : <button type="button" onClick={() => fileRef.current?.click()} data-testid="project-refund-attach" style={smallButton(false)}>{T('Đính kèm biên lai', 'Attach receipt')}</button>}
        </div>
      </>}
      <button type="button" disabled={off} data-testid="project-refund-submit" style={pillButton(true, { opacity: off ? 0.4 : 1 })}
        onClick={async () => { if (await p.sendRefund(claim.claim_id, note, file)) close(); }}>
        {markSent ? T('Đánh dấu đã hoàn tiền', 'Mark refund sent') : T('Ghi nhận để chủ sự kiện duyệt', 'Record transfer for Host approval')}
      </button>
      <Note testId="project-refund-footer">{st.state === 'noAccount'
        ? T('Bạn gửi được khi khách đã thêm tài khoản.', 'You can send it once the guest adds an account.')
        : markSent ? T('Khách được báo ngay.', 'The guest is told right away.') : T('Khách chỉ được báo sau khi Chủ sự kiện duyệt.', 'The guest is told only after the Host approves.')}</Note>
    </Sheet>
  );
}

/** Phase 9c, the Host's side: the team's refund records to approve or decline, who may refund without the Host (only while
 * project_delegate_refunds is on), and one disputed refund handed to a money member once team access is over. */
function HostRefunds({ p }) {
  const { T, snap } = p;
  const [approve, setApprove] = useState(null);
  const [decline, setDecline] = useState(null);
  const [grant, setGrant] = useState(null);
  const [toAlone, setToAlone] = useState(false);
  const [granted, setGranted] = useState('');
  const claims = p.s.projectRefunds?.claims || [];
  const team = teamRefundRequests(claims);
  const mode = p.refundMode;
  const over = teamGrantsOver(snap, p.now(), p.LIMITS.grantDays);
  const disputed = p.refundsFlag && over ? claims.filter(c => c.dispute_open) : [];
  const find = (id) => claims.find(c => c.claim_id === id);
  if (!team.length && !p.refundsFlag) return null;
  return (
    <div data-testid="project-host-refunds">
      {team.length > 0 && <>
        <SectionHeader title={T('Hoàn tiền từ đội', 'Refunds from the team')} />
        <Card padding={4} data-testid="project-team-refunds">
          {team.map((c, i) => (
            <div key={c.claim_id}>
              <div data-testid={`project-team-refund-${c.claim_id}`} style={{ padding: '10px 0', display: 'flex', flexDirection: 'column', gap: 6 }}>
                <span style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}><strong>{c.name}</strong><strong style={{ fontVariantNumeric: 'tabular-nums' }}>{formatMoney(c.amount, 'VND')}</strong></span>
                <span style={{ fontSize: 13, color: ink2 }}>{T(`${c.request.by} đã ghi nhận chuyển khoản`, `${c.request.by} recorded the transfer`)}{c.request.has_proof ? T(' · Có biên lai', ' · Receipt attached') : ''}</span>
                {c.request.note && <span style={{ fontSize: 14 }}>“{c.request.note}”</span>}
                <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end', flexWrap: 'wrap' }}>
                  <button type="button" disabled={p.s.projectBusy} onClick={() => setDecline(c.claim_id)} data-testid={`project-team-refund-decline-${c.claim_id}`} style={smallButton(false)}>{T('Từ chối', 'Decline')}</button>
                  <button type="button" disabled={p.s.projectBusy} onClick={() => setApprove(c.claim_id)} data-testid={`project-team-refund-approve-${c.claim_id}`}
                    aria-label={T(`Duyệt hoàn tiền cho ${c.name}`, `Approve the refund to ${c.name}`)} style={smallButton(true)}>{T('Duyệt', 'Approve')}</button>
                </div>
              </div>
              {i < team.length - 1 && <div style={{ height: 1, background: divider }} />}
            </div>
          ))}
        </Card>
      </>}
      {p.refundsFlag && <>
        <SectionHeader title={T('Duyệt hoàn tiền', 'Refund approval')} />
        <Card data-testid="project-refund-approval">
          <ChipRow>
            <Chip title={T('Chủ sự kiện duyệt', 'Host approves')} selected={mode === 'host'} disabled={p.s.projectBusy} testId="project-refund-approval-host"
              onClick={() => { if (mode !== 'host') p.setRefundApproval('host'); }} />
            <Chip title={T('Tài chính tự hoàn tiền', 'Finance can refund alone')} selected={mode === 'finance_alone'} disabled={p.s.projectBusy} testId="project-refund-approval-alone"
              onClick={() => { if (mode !== 'finance_alone') setToAlone(true); }} />
          </ChipRow>
          <div style={{ marginTop: 8 }}><Note>{mode === 'finance_alone'
            ? T('Đội báo khách đã hoàn tiền mà không cần bạn duyệt. Mỗi lần đều được ghi lại.', 'The team tells guests a refund was sent without your approval. Every one is recorded.')
            : T('Đội ghi nhận chuyển khoản, bạn duyệt rồi khách mới được báo.', 'The team records each transfer and the guest is told once you approve.')}</Note></div>
        </Card>
      </>}
      {disputed.length > 0 && <>
        <SectionHeader title={T('Tranh chấp hoàn tiền', 'Disputed refunds')} />
        <Card padding={4} data-testid="project-dispute-grants">
          {disputed.map((c, i) => (
            <div key={c.claim_id}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 0', flexWrap: 'wrap' }}>
                <span style={{ flex: '1 1 160px' }}><strong style={{ display: 'block' }}>{c.name}</strong><span style={{ fontSize: 13, color: ink2 }}>{formatMoney(c.amount, 'VND')}</span></span>
                <button type="button" onClick={() => setGrant(c.claim_id)} data-testid={`project-dispute-grant-${c.claim_id}`} style={smallButton(false)}>{T('Giao cho đội xử lý', 'Let the team handle this refund')}</button>
              </div>
              {i < disputed.length - 1 && <div style={{ height: 1, background: divider }} />}
            </div>
          ))}
        </Card>
        {granted && <div style={{ marginTop: 8 }}><Note tone="ink2" testId="project-dispute-granted">✓ {granted}</Note></div>}
      </>}
      {approve && find(approve) && (
        <Sheet title={T('Duyệt hoàn tiền', 'Approve refund')} onClose={() => setApprove(null)} testId="project-team-refund-approve-sheet">
          <p style={{ margin: 0 }}>{T('Khách sẽ được báo là đã hoàn tiền.', 'The guest will be told the refund was sent.')}</p>
          <button type="button" disabled={p.s.projectBusy} data-testid="project-team-refund-approve-confirm" style={pillButton(true)}
            onClick={async () => { const id = approve; setApprove(null); await p.approveRefund(id); }}>{T(`Duyệt ${formatMoney(find(approve).amount, 'VND')}`, `Approve ${formatMoney(find(approve).amount, 'VND')}`)}</button>
        </Sheet>
      )}
      {decline && find(decline) && <DeclineRefundSheet p={p} claim={find(decline)} close={() => setDecline(null)} />}
      {toAlone && (
        <Sheet title={T('Tài chính tự hoàn tiền', 'Finance can refund alone')} onClose={() => setToAlone(false)} testId="project-refund-approval-sheet">
          <p style={{ margin: 0 }}>{T('Tài chính & cổng và thành viên có quyền tiền sẽ báo khách đã hoàn tiền mà không cần bạn.', 'Finance & door and members with money access will be able to tell guests a refund was sent without you.')}</p>
          <button type="button" disabled={p.s.projectBusy} data-testid="project-refund-approval-confirm" style={pillButton(true)}
            onClick={async () => { setToAlone(false); await p.setRefundApproval('finance_alone'); }}>{T('Cho phép', 'Allow')}</button>
        </Sheet>
      )}
      {grant && find(grant) && <DisputeGrantSheet p={p} claim={find(grant)} close={() => setGrant(null)} done={setGranted} />}
    </div>
  );
}

function DeclineRefundSheet({ p, claim, close }) {
  const { T } = p;
  const [reason, setReason] = useState('');
  const ok = reasonOk(reason);
  return (
    <Sheet title={T('Từ chối bản ghi hoàn tiền', 'Decline refund record')} onClose={close} testId="project-team-refund-decline-sheet">
      <h3 style={{ margin: 0 }}>{claim.name} · {formatMoney(claim.amount, 'VND')}</h3>
      <ReasonField reason={reason} setReason={setReason} T={T} picks={[T('Không thấy tiền đi', "I can't see the transfer"), T('Sai số tiền', 'Wrong amount'), T('Sai tài khoản', 'Wrong account')]} />
      <button type="button" disabled={!ok || p.s.projectBusy} data-testid="project-team-refund-decline-confirm" style={dangerButton({ opacity: ok ? 1 : 0.4 })}
        onClick={async () => { if (await p.declineRefund(claim.claim_id, reason.trim())) close(); }}>{T('Từ chối', 'Decline')}</button>
      <Note>{T('Người ghi nhận sẽ thấy lý do và có thể ghi nhận lại. Khách không được báo gì.', 'The person who recorded it sees the reason and can record it again. The guest is told nothing.')}</Note>
    </Sheet>
  );
}

function DisputeGrantSheet({ p, claim, close, done }) {
  const { T, snap } = p;
  const people = refundDelegates(snap);
  const [who, setWho] = useState(people.length === 1 ? people[0].user_id : null);
  const [days, setDays] = useState(7);
  const choices = [7, 14, 30].filter(d => d <= p.LIMITS.disputeGrantMaxDays);
  return (
    <Sheet title={T('Giao cho đội xử lý', 'Let the team handle this refund')} onClose={close} testId="project-dispute-grant-sheet">
      <h3 style={{ margin: 0 }}>{claim.name} · {formatMoney(claim.amount, 'VND')}</h3>
      <Note>{T('Chỉ khoản hoàn tiền này, chỉ khi tranh chấp còn mở. Trò chuyện tranh chấp vẫn do bạn.', 'This refund only, and only while the dispute is open. The dispute chat stays with you.')}</Note>
      <FieldLabel>{T('Người xử lý', 'Who')}</FieldLabel>
      {people.length === 0 ? <Note tone="ink2" testId="project-dispute-grant-nobody">{T('Chưa ai trong đội có quyền tiền. Cấp ở thẻ Đội.', 'Nobody on the team has money access. Grant it on the Team tab.')}</Note>
        : <ChipRow>{people.map(m => <Chip key={m.user_id} title={p.personName(m.user_id)} selected={who === m.user_id} onClick={() => setWho(m.user_id)} testId={`project-dispute-grant-who-${m.user_id}`} />)}</ChipRow>}
      <FieldLabel>{T('Trong bao lâu', 'For how long')}</FieldLabel>
      <ChipRow>{choices.map(d => <Chip key={d} title={T(`${d} ngày`, `${d} days`)} selected={days === d} onClick={() => setDays(d)} testId={`project-dispute-grant-days-${d}`} />)}</ChipRow>
      <button type="button" disabled={!who || p.s.projectBusy} data-testid="project-dispute-grant-confirm" style={pillButton(true, { opacity: who ? 1 : 0.4 })}
        onClick={async () => {
          if (!(await p.extendDisputeGrant(claim.claim_id, who, days))) return;
          done(T(`${p.personName(who)} xử lý được khoản hoàn tiền của ${claim.name} trong ${days} ngày.`, `${p.personName(who)} can handle the refund to ${claim.name} for ${days} days.`));
          close();
        }}>{T('Giao quyền', 'Give access')}</button>
    </Sheet>
  );
}

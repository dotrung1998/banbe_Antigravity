import { useEffect } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { EVENTS } from '../data/events.js';
import { paper, ink, rule, display, fieldGlass, inkButton } from '../theme.js';
import { RowIcon, ROW_ACCENT_COLORS } from './Account.jsx';

// Account IA pass (2026-09-27) — the ONE shared child screen every
// Account group entry card opens (`openAccountGroup(key)`), keyed by
// `s.accountGroupKey`. Never a separate screen per group: the six groups
// (team/activity/payments/preferences on Cá nhân, hostOps on Tổ chức,
// adminReview on Admin) are really one layout — a title, a back-to-
// Account link, and a handful of EXISTING rows relocated here verbatim
// (same data-testid, same onClick target) — so building six near-
// identical files/screens would just be repetition, not a real
// architectural need. `accountTab` itself is never touched by this
// screen, so "‹ Tài khoản" always lands back on whichever tab was showing.
const GROUP_META = {
  team: { vi: 'Hồ sơ & Team', en: 'Profile & Team' },
  activity: { vi: 'Vé & hoạt động', en: 'Tickets & activity' },
  payments: { vi: 'Thanh toán & giấy tờ', en: 'Payments & documents' },
  preferences: { vi: 'Tùy chỉnh', en: 'Preferences' },
  hostOps: { vi: 'Vận hành & thanh toán tổ chức', en: 'Event operations & payments' },
  adminReview: { vi: 'Duyệt & kiểm duyệt', en: 'Review & moderation' },
};

function Row({ icon, label, trailing, onClick, testId, border = true }) {
  return (
    <div onClick={onClick} data-testid={testId} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', borderBottom: border ? `1px solid ${rule}` : 'none', cursor: 'pointer' }}>
      <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}><RowIcon kind={icon} />{label}</span>
      <span style={{ fontSize: 13, color: ink }}>{trailing}</span>
    </div>
  );
}

export default function AccountGroup() {
  const {
    state: s, T, set,
    goCompletedList, respondToEventCredit, goEvent,
    respondToOrganizerInvite, setOrganizerMemberVisibility,
    openPreferences, openSecurity, openDocuments, openRefundAccounts, openMyRefunds,
    openVerifications, openPayout, openDisputes, openAdminEvents,
  } = useGoc();
  const key = s.accountGroupKey;

  // Safety net (mirrors Account.jsx's own accountTab role-sync effect) — a
  // role change while this screen happens to be open (organizer mode
  // toggled off elsewhere, an admin demoted) sends it back to Account
  // rather than showing a group its own role no longer has.
  useEffect(() => {
    if (key === 'hostOps' && !s.organizerMode) set({ screen: 'profile' });
    else if (key === 'adminReview' && s.accountType !== 'admin') set({ screen: 'profile' });
  }, [key, s.organizerMode, s.accountType, set]);

  if (!key || !GROUP_META[key]) return null;
  const title = T(GROUP_META[key].vi, GROUP_META[key].en);
  const completedCount = [...new Set([...(s.favorites || []), ...s.attending])]
    .map(k => EVENTS.find(e => e.key === k))
    .filter(e => e && e.endedHoursAgo != null).length;

  return (
    <div style={{ animation: 'gocFade 0.32s ease both', minHeight: '100%', background: paper }} data-screen-label="AccountGroup">
      <div onClick={() => set({ screen: 'profile' })} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="account-group-back">
        ‹ {T('Tài khoản', 'Account')}
      </div>
      <div style={{ padding: '16px 20px 40px' }}>
        <h1 style={{ ...display(27, { margin: 0, lineHeight: 1.2, display: 'flex', alignItems: 'center', gap: 10 }) }}>
          <RowIcon kind={{ team: 'users', activity: 'calendarCheck', payments: 'banknote', preferences: 'sliders', hostOps: 'checklist', adminReview: 'alertShield' }[key]} size={26} accent={ROW_ACCENT_COLORS[key]} />
          {title}
        </h1>

        {key === 'team' && (
          <>
            {s.myOrganizerInvites.length > 0 && (
              <div style={{ marginTop: 24 }} data-testid="account-team-invites">
                <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Lời mời Team', 'Team invites')}</span>
                {s.myOrganizerInvites.map(inv => (
                  <div key={inv.id} style={{ ...fieldGlass({ marginTop: 8, padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 8 }) }} data-testid={`team-invite-${inv.id}`}>
                    <span style={{ fontSize: 13, color: ink }}>
                      {T(`${inv.organizers?.name || 'Một tổ chức'} mời bạn làm ${inv.public_role}`, `${inv.organizers?.name || 'An organizer'} invited you as ${inv.public_role}`)}
                    </span>
                    <div style={{ display: 'flex', gap: 8 }}>
                      <div onClick={() => respondToOrganizerInvite(inv.id, true)} data-testid={`team-invite-accept-${inv.id}`} style={{ ...inkButton({ flex: 1, padding: 10, fontSize: 12.5 }) }}>{T('Chấp nhận', 'Accept')}</div>
                      <div onClick={() => respondToOrganizerInvite(inv.id, false)} data-testid={`team-invite-decline-${inv.id}`} style={{ ...fieldGlass({ flex: 1, padding: 10, fontSize: 12.5, textAlign: 'center', cursor: 'pointer' }) }}>{T('Từ chối', 'Decline')}</div>
                    </div>
                  </div>
                ))}
              </div>
            )}
            {s.myTeamMemberships.length > 0 && (
              <div style={{ marginTop: 24 }} data-testid="account-team-memberships">
                <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Đội ngũ của tôi', 'My teams')}</span>
                {s.myTeamMemberships.map(m => (
                  <div key={m.id} style={{ ...fieldGlass({ marginTop: 8, padding: '14px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }) }} data-testid={`team-membership-${m.id}`}>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
                      <span style={{ fontSize: 13, color: ink }}>{m.organizers?.name || T('Một tổ chức', 'An organizer')}</span>
                      <span style={{ fontSize: 11, color: ink, opacity: 0.65 }}>{m.public_role}</span>
                    </div>
                    <div
                      onClick={() => setOrganizerMemberVisibility(m.id, !m.public_visible)}
                      data-testid={`team-membership-visibility-${m.id}`}
                      style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}
                    >
                      <span style={{ fontSize: 11, color: ink }}>{T('Hiển thị tôi trong Team', 'Show me in the Team')}</span>
                      <span aria-hidden style={{ flex: 'none', width: 40, height: 24, borderRadius: 12, padding: 3, background: m.public_visible ? ink : 'rgba(27,25,22,0.18)', transition: 'background .15s' }}>
                        <span style={{ display: 'block', width: 18, height: 18, borderRadius: '50%', background: paper, transform: m.public_visible ? 'translateX(16px)' : 'translateX(0)', transition: 'transform .15s' }} />
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            )}
            {s.myOrganizerInvites.length === 0 && s.myTeamMemberships.length === 0 && (
              <p style={{ fontSize: 13, color: ink, opacity: 0.65, marginTop: 24 }}>{T('Chưa có lời mời hay Team nào.', 'No invites or teams yet.')}</p>
            )}
          </>
        )}

        {key === 'activity' && (
          <>
            <div style={{ ...fieldGlass({ marginTop: 24, display: 'flex', flexDirection: 'column' }) }}>
              <Row icon="calendarCheck" label={T('Sự kiện đã hoàn thành', 'Completed events')} trailing={`${completedCount} ›`} testId="account-completed-events" onClick={goCompletedList} border={false} />
            </div>
            {s.myEventCredits.length > 0 && (
              <div style={{ marginTop: 24 }} data-testid="account-event-credits">
                <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Đóng góp sự kiện — lời mời đang chờ', 'Event contributions — pending invites')}</span>
                {s.myEventCredits.map(c => (
                  <div key={c.id} style={{ ...fieldGlass({ marginTop: 8, padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 8 }) }} data-testid={`event-credit-${c.id}`}>
                    <span style={{ fontSize: 13, color: ink }}>
                      {T(`${c.organizers?.name || 'Một tổ chức'} ghi nhận bạn đã tổ chức "${c.events?.name || ''}"`, `${c.organizers?.name || 'An organizer'} credited you for organizing "${c.events?.name || ''}"`)}
                    </span>
                    <div style={{ display: 'flex', gap: 8 }}>
                      <div onClick={() => respondToEventCredit(c.id, true)} data-testid={`event-credit-accept-${c.id}`} style={{ ...inkButton({ flex: 1, padding: 10, fontSize: 12.5 }) }}>{T('Chấp nhận', 'Accept')}</div>
                      <div onClick={() => respondToEventCredit(c.id, false)} data-testid={`event-credit-decline-${c.id}`} style={{ ...fieldGlass({ flex: 1, padding: 10, fontSize: 12.5, textAlign: 'center', cursor: 'pointer' }) }}>{T('Từ chối', 'Decline')}</div>
                    </div>
                  </div>
                ))}
              </div>
            )}
            {s.myConfirmedEventCredits.length > 0 && (
              <div style={{ marginTop: 24 }} data-testid="account-event-credits-confirmed">
                <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Đóng góp sự kiện — đã xác nhận', 'Event contributions — confirmed')}</span>
                {s.myConfirmedEventCredits.map(c => (
                  <div
                    key={c.id}
                    onClick={() => goEvent(c.event_id)}
                    style={{ ...fieldGlass({ marginTop: 8, padding: '14px 16px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }) }}
                    data-testid={`event-credit-confirmed-${c.id}`}
                  >
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                      <span style={{ fontSize: 13, fontWeight: 600, color: ink }}>{c.events?.name || T('Một sự kiện', 'An event')}</span>
                      <span style={{ fontSize: 11, color: ink, opacity: 0.65 }}>{c.organizers?.name || T('Một tổ chức', 'An organizer')}</span>
                    </div>
                    <span aria-hidden style={{ fontSize: 18, color: ink, opacity: 0.5 }}>›</span>
                  </div>
                ))}
              </div>
            )}
          </>
        )}

        {key === 'payments' && (
          <div style={{ ...fieldGlass({ marginTop: 24, display: 'flex', flexDirection: 'column' }) }}>
            <Row icon="document" label={T('Hoá đơn', 'Invoices')} trailing="›" testId="account-invoices" onClick={() => openDocuments('invoice', 'guest')} />
            <Row icon="receipt" label={T('Biên nhận', 'Receipts')} trailing="›" testId="account-receipts" onClick={() => openDocuments('receipt', 'guest')} />
            <Row icon="banknote" label={T('Tài khoản thanh toán & nhận hoàn tiền', 'Payment & refund accounts')} trailing="›" testId="account-refund-accounts" onClick={() => openRefundAccounts('profile')} />
            <Row icon="checklist" label={T('Hoàn tiền', 'Refunds')} trailing="›" testId="account-refunds" onClick={() => openMyRefunds('profile')} border={false} />
          </div>
        )}

        {key === 'preferences' && (
          <div style={{ ...fieldGlass({ marginTop: 24, display: 'flex', flexDirection: 'column' }) }}>
            <Row
              icon="sliders" label={T('Tùy chỉnh ứng dụng', 'App preferences')}
              trailing={`${s.lang === 'en' ? 'English' : 'Tiếng Việt'} ▪︎ ${s.theme === 'dark' ? T('Tối', 'Dark') : T('Sáng', 'Light')}`}
              testId="account-preferences"
              onClick={openPreferences}
            />
            <Row icon="shield" label={T('Bảo mật', 'Security')} trailing="›" testId="account-security" onClick={openSecurity} border={false} />
          </div>
        )}

        {key === 'hostOps' && (
          <div style={{ ...fieldGlass({ marginTop: 24, display: 'flex', flexDirection: 'column' }) }}>
            <Row icon="checklist" label={T('Chờ xác nhận thanh toán', 'Awaiting verification')} trailing="›" testId="host-verifications" onClick={openVerifications} />
            <Row icon="banknote" label={T('Nhận thanh toán', 'Getting paid')} trailing="›" testId="host-payout" onClick={openPayout} />
            <Row icon="document" label={T('Hoá đơn đã phát hành', 'Invoices issued')} trailing="›" testId="host-invoices" onClick={() => openDocuments('invoice', 'host')} />
            <Row icon="receipt" label={T('Biên nhận đã phát hành', 'Receipts issued')} trailing="›" testId="host-receipts" onClick={() => openDocuments('receipt', 'host')} border={false} />
          </div>
        )}

        {key === 'adminReview' && (
          <div style={{ ...fieldGlass({ marginTop: 24, display: 'flex', flexDirection: 'column' }) }}>
            <Row icon="alertShield" label={T('Tranh chấp thanh toán', 'Payment disputes')} trailing="›" testId="admin-disputes" onClick={openDisputes} />
            <Row icon="alertShield" label={T('Sự kiện chờ duyệt', 'Pending events')} trailing="›" testId="admin-events" onClick={openAdminEvents} border={false} />
          </div>
        )}
      </div>
    </div>
  );
}

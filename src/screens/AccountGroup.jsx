import { useEffect } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { EVENTS } from '../data/events.js';
import { paper, ink, rule, display, fieldGlass, inkButton, alert } from '../theme.js';
import { RowIcon, ROW_ACCENT_COLORS } from './Account.jsx';
import { computeHostActionCount, computeRefundActionCount, formatBadgeCount } from '../lib/badges.js';
import { isBookingTicket } from '../lib/bookingTicket.js';

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
// Account IA reorg (2026-09-30) — "activity"'s visible label changed to
// "Tickets & Bookings" (its content is now this account's REAL bookings,
// see the `key === 'activity'` block below) and "preferences" relabeled
// to "Settings" for accuracy. Both `groupKey`s themselves are UNCHANGED
// (still "activity"/"preferences" — the route/testid/deep-link target),
// per this pass's own instruction to rename labels only, never keys.
const GROUP_META = {
  team: { vi: 'Hồ Sơ & Team', en: 'Profile & Team' },
  activity: { vi: 'Vé & Đặt Chỗ', en: 'Tickets & Bookings' },
  payments: { vi: 'Thanh Toán & Giấy Tờ', en: 'Payments & Documents' },
  preferences: { vi: 'Cài Đặt', en: 'Settings' },
  hostOps: { vi: 'Vận Hành & Thanh Toán Tổ Chức', en: 'Event Operations & Payments' },
  adminReview: { vi: 'Duyệt & Kiểm Duyệt', en: 'Review & Moderation' },
};

// TASK 5 real-device follow-up — `badge` (0/undefined = hidden) so a child
// row (e.g. "Pending events") can show the SAME real count its own
// group-entry card already does — same capsule style `GroupCard`
// (Account.jsx) uses, capped at "99+" with the full count kept in
// aria-label/title.
function Row({ icon, label, trailing, onClick, testId, border = true, badge }) {
  return (
    <div onClick={onClick} data-testid={testId} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '15px 16px', borderBottom: border ? `1px solid ${rule}` : 'none', cursor: 'pointer' }}>
      <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}><RowIcon kind={icon} />{label}</span>
      <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        {!!badge && (
          <span data-testid={`${testId}-badge`} role="status" aria-label={`${badge} new item(s)`} title={String(badge)} style={{ fontSize: 11, fontWeight: 700, color: paper, background: alert, borderRadius: 999, padding: '2px 7px', minWidth: 18, textAlign: 'center' }}>
            {formatBadgeCount(badge)}
          </span>
        )}
        <span style={{ fontSize: 13, color: ink }}>{trailing}</span>
      </span>
    </div>
  );
}

export default function AccountGroup() {
  const {
    state: s, T, set,
    goCompletedList, respondToEventCredit, goEvent,
    respondToOrganizerInvite, setOrganizerMemberVisibility,
    openPreferences, openSecurity, openDocuments, openRefundAccounts, openMyRefunds,
    openVerifications, openVerificationsRefunds, openPayout, openDisputes, openAdminEvents,
    loadPaymentBookings, openBookingConfirmed, openDeleteAccount,
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

  // Account IA reorg (2026-09-30) — "My Tickets" (the `activity` group's
  // new real content) reuses the SAME `paymentBookings` array Account.jsx
  // already loads for its own Action Center — Account.jsx has already
  // loaded it by the time this screen is reachable, but a direct deep link
  // straight into `accountGroupKey: 'activity'` (bypassing Account.jsx's
  // own mount effect) is a real path, so this screen loads it itself too;
  // `loadPaymentBookings` is idempotent (a plain re-fetch), never a second
  // divergent source.
  useEffect(() => {
    if (key === 'activity' && s.user?.id) loadPaymentBookings();
  }, [key, s.user?.id, loadPaymentBookings]);

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
                <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Lời mời Team', 'Team Invites')}</span>
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
                <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Đội ngũ của tôi', 'My Teams')}</span>
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
            {/* Account IA reorg (2026-09-30) — event-credit invites
                (organizer-collaboration credits, not attendee tickets)
                RELOCATED here from the old "activity" group — a deliberate
                reclassification, not a silent drop: both this and Team
                invites/memberships above are organizer-collaboration
                concerns, a better semantic fit than sitting alongside real
                attendee bookings in "Tickets & Bookings". Content/testids
                unchanged from their previous location. */}
            {s.myEventCredits.length > 0 && (
              <div style={{ marginTop: 24 }} data-testid="account-event-credits">
                <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Đóng góp sự kiện: lời mời đang chờ', 'Event contributions: pending invites')}</span>
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
                <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Đóng góp sự kiện: đã xác nhận', 'Event contributions: confirmed')}</span>
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

        {key === 'activity' && (
          <>
            {/* Account IA reorg (2026-09-30) — Task 2b: "My Tickets" is now
                REAL DB-backed data, reusing `s.paymentBookings`
                (`loadPaymentBookings()`, GocContext.jsx) — the exact same
                `bookings` query Account.jsx's own Action Center already
                loads (`user_id`-scoped, joined to `events`/`organizers` for
                real name/date), not the static demo catalogue and not a
                second divergent query. Active bookings (pending/confirmed/
                attended) tap into `openBookingConfirmed`, the same booking-
                id-scoped helper Confirmed.jsx's own notification-reopen
                path already uses — it self-gates the real QR (via
                `isBookingTicket`) vs. the "awaiting payment" state, exactly
                like Event Detail's reserve bar's `openHeld` already does
                for whichever booking happens to be in `state.booking`, just
                generalized to any booking id. Cancelled/expired/no_show
                bookings (real `bookings.status` values confirmed in the
                migrations — see 069/070/072/011) get their own clearly
                labeled, non-interactive section — no fabricated "refunded"
                bucket, since `bookings.status` has no such value. */}
            {s.paymentsLoading && !s.paymentBookings.length && (
              <p style={{ fontSize: 13, color: ink, opacity: 0.65, marginTop: 24 }} data-testid="my-tickets-loading">{T('Đang tải vé của bạn…', 'Loading your tickets…')}</p>
            )}
            {!s.paymentsLoading && s.paymentBookings.length === 0 && (
              <p style={{ fontSize: 13, color: ink, opacity: 0.65, marginTop: 24 }} data-testid="my-tickets-empty">{T('Bạn chưa có vé nào.', "You don't have any tickets yet.")}</p>
            )}
            {(() => {
              const active = s.paymentBookings.filter(b => ['pending', 'confirmed', 'attended'].includes(b.status));
              const inactive = s.paymentBookings.filter(b => ['cancelled', 'expired', 'no_show'].includes(b.status));
              const statusLabel = (b) => {
                if (isBookingTicket(b)) return T('Vé đã sẵn sàng', 'Ticket ready');
                if (b.status === 'attended') return T('Đã tham dự', 'Attended');
                if (b.payment_state === 'pending_verification') return T('Chờ xác nhận thanh toán', 'Awaiting Verification');
                if (b.status === 'pending') return T('Đang giữ chỗ', 'Holding');
                return T('Đang xử lý', 'In progress');
              };
              const terminalLabel = (b) => ({
                cancelled: T('Đã hủy', 'Cancelled'),
                expired: T('Đã hết hạn', 'Expired'),
                no_show: T('Không tham dự', 'No-show'),
              }[b.status] || b.status);
              return (
                <>
                  {active.length > 0 && (
                    <div style={{ marginTop: 24 }} data-testid="my-tickets-active">
                      <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Vé của tôi', 'My Tickets')}</span>
                      {active.map(b => (
                        <div
                          key={b.id}
                          onClick={() => openBookingConfirmed(b.id, b.event_id, 'accountGroup')}
                          style={{ ...fieldGlass({ marginTop: 8, padding: '14px 16px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', cursor: 'pointer' }) }}
                          data-testid={`my-ticket-${b.id}`}
                        >
                          <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                            <span style={{ fontSize: 13, fontWeight: 600, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{b.events?.name || T('Một sự kiện', 'An event')}</span>
                            <span style={{ fontSize: 11, color: ink, opacity: 0.65 }}>{b.events?.event_date ? `${b.events.event_date}${b.events.event_time ? ' ▪︎ ' + b.events.event_time : ''}` : ''}</span>
                            <span style={{ fontSize: 11, color: ink, opacity: 0.85 }}>{statusLabel(b)}</span>
                          </div>
                          <span aria-hidden style={{ fontSize: 18, color: ink, opacity: 0.5, flex: 'none' }}>›</span>
                        </div>
                      ))}
                    </div>
                  )}
                  {inactive.length > 0 && (
                    <div style={{ marginTop: 24 }} data-testid="my-tickets-inactive">
                      <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Đã hủy / hết hạn', 'Cancelled / expired')}</span>
                      {inactive.map(b => (
                        <div
                          key={b.id}
                          style={{ ...fieldGlass({ marginTop: 8, padding: '14px 16px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', opacity: 0.65 }) }}
                          data-testid={`my-ticket-inactive-${b.id}`}
                        >
                          <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                            <span style={{ fontSize: 13, fontWeight: 600, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{b.events?.name || T('Một sự kiện', 'An event')}</span>
                            <span style={{ fontSize: 11, color: ink }}>{terminalLabel(b)}</span>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </>
              );
            })()}
            {/* "Sự kiện đã hoàn thành" relabeled "Quá Khứ"/"Past Events" for
                clarity — same destination (`goCompletedList` ->
                `EventListView`/`EventList.jsx` mode 'completed'), unchanged. */}
            <div style={{ ...fieldGlass({ marginTop: 24, display: 'flex', flexDirection: 'column' }) }}>
              <Row icon="calendarCheck" label={T('Sự Kiện Quá Khứ', 'Past Events')} trailing={`${completedCount} ›`} testId="account-completed-events" onClick={goCompletedList} border={false} />
            </div>
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
              icon="sliders" label={T('Tùy chỉnh ứng dụng', 'App Preferences')}
              trailing={`${s.lang === 'en' ? 'English' : 'Tiếng Việt'} ▪︎ ${s.theme === 'dark' ? T('Tối', 'Dark') : T('Sáng', 'Light')}`}
              testId="account-preferences"
              onClick={openPreferences}
            />
            <Row icon="shield" label={T('Bảo mật', 'Security')} trailing="›" testId="account-security" onClick={openSecurity} border={false} />
          </div>
        )}

        {/* Account deletion (Task 2, Account/Settings pass) — a visually
            separated "Account Management" subsection inside this same
            `preferences` group screen, per this ticket's own placement
            instruction (distinct from the ordinary rows above and from
            Sign Out on the parent Account screen). Reuses the existing
            `alert` color token — no new color introduced. */}
        {key === 'preferences' && (
          <div style={{ marginTop: 24 }} data-testid="account-management-section">
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Quản Lý Tài Khoản', 'Account Management')}</span>
            <div
              onClick={openDeleteAccount}
              data-testid="account-delete-row"
              style={{
                marginTop: 8, padding: '15px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                cursor: 'pointer', borderRadius: 14, border: `1px solid ${alert}55`, background: `${alert}14`,
              }}
            >
              <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: alert, fontWeight: 600 }}>
                <RowIcon kind="alertShield" />{T('Xóa Tài Khoản', 'Delete Account')}
              </span>
              <span style={{ fontSize: 15, color: alert, lineHeight: 1 }}>›</span>
            </div>
          </div>
        )}

        {key === 'hostOps' && (
          <div style={{ ...fieldGlass({ marginTop: 24, display: 'flex', flexDirection: 'column' }) }}>
            {/* FIX PASS (2026-09-30) — badge parity with this group's own
                entry card (Account.jsx's "Vận hành & thanh toán tổ chức"),
                same rule 25bd5f5 already established for "Pending events"
                below: both verifications AND refundQueue land on THIS exact
                screen (openVerifications), so this row's badge is the same
                sum, not a second independently-derived count. */}
            <Row icon="checklist" label={T('Chờ xác nhận thanh toán', 'Awaiting Verification')} trailing="›" testId="host-verifications" onClick={openVerifications} badge={computeHostActionCount(s)} />
            {/* Refund-discoverability fix — refunds previously only lived
                inside the row above, with no mention of the word "refund"
                anywhere in this group's own labels. Same screen/data
                (openVerificationsRefunds just adds a one-shot scroll flag
                to the SAME openVerifications() call), own badge
                (computeRefundActionCount — the same refundQueue.length term
                the row above's own sum already includes, never a second,
                differently-defined count). */}
            <Row icon="banknote" label={T('Hoàn tiền', 'Refunds')} trailing="›" testId="host-refunds" onClick={openVerificationsRefunds} badge={computeRefundActionCount(s)} />
            <Row icon="banknote" label={T('Nhận thanh toán', 'Getting Paid')} trailing="›" testId="host-payout" onClick={openPayout} />
            <Row icon="document" label={T('Hoá đơn đã phát hành', 'Invoices Issued')} trailing="›" testId="host-invoices" onClick={() => openDocuments('invoice', 'host')} />
            <Row icon="receipt" label={T('Biên nhận đã phát hành', 'Receipts Issued')} trailing="›" testId="host-receipts" onClick={() => openDocuments('receipt', 'host')} border={false} />
          </div>
        )}

        {key === 'adminReview' && (
          <div style={{ ...fieldGlass({ marginTop: 24, display: 'flex', flexDirection: 'column' }) }}>
            <Row icon="alertShield" label={T('Tranh chấp thanh toán', 'Payment Disputes')} trailing="›" testId="admin-disputes" onClick={openDisputes} />
            <Row icon="alertShield" label={T('Sự Kiện Chờ Duyệt', 'Pending Events')} trailing="›" testId="admin-events" onClick={openAdminEvents} border={false} badge={s.pendingEventsCount} />
          </div>
        )}
      </div>
    </div>
  );
}

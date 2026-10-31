import { glassCapsuleInactive } from '../lib/glassOpacity.js';
import { useEffect, useRef, useState } from 'react';
import DockHeaderTitle, { DOCK_HEADER } from '../components/ui/DockHeaderTitle.jsx';
import { useBanBe } from '../state/BanBeContext.jsx';
import { EVENTS } from '../data/events.js';
import { supabase } from '../lib/supabase.js';
import { organizerAvatarPublicUrl } from '../lib/mediaUrls.js';
import { paper, ink, ink2, ink3, block, rule, display, fieldGlass, fieldSolid, cardGlass, inkButton, alert } from '../theme.js';
import { AttachMenuIcon } from './Chat.jsx';
import { buildActionCenterItems, sortActionCenterItems } from '../lib/actionCenter.js';
import { PROFILE_PALETTE_COLORS } from '../lib/profileTheme.js';
import ActionCenter from './ActionCenter.jsx';
import AccountSearchResults from './AccountSearch.jsx';
import { takeSearchState, resetSearchState } from '../lib/accountSearch.js';
import { useSubmittedEvents } from '../lib/submittedEvents.jsx';
import ProfileShareSheet, { profileShareLinks } from './sheets/ProfileShareSheet.jsx';
import { KeychainFrame, useMyKeychain } from '../components/KeychainCharm.jsx';
import { pickSoonest, liveEventOverrides } from '../lib/countdown.js';
import { reminderPhase, REMINDER_CSS } from '../lib/eventReminder.js';
import { computeAdminModerationCount, computeHostActionCount, computeMyTicketsActionCount, computeMyRefundActionCount } from '../lib/badges.js';
import { capsuleStreak } from '../lib/rewards.js';
import { AccountTileGrid, AccountSectionLabel, MoreList, MoreRow, RewardsStrip } from './AccountTiles.jsx';
import StartHostingCard from '../components/StartHostingCard.jsx';

function organizerAvatarUrl(path, r2Ref, variant = 'thumb') {
  return organizerAvatarPublicUrl(path, r2Ref, variant);
}

// Note 66: the grouped-row helpers (GroupedContainer/GroupedRow/ReportsRow/GroupCard/SectionHeader) left with
// the tabs; Account's rows and tiles now live in AccountTiles.jsx.

// Color-as-wayfinding pass (2026-09-27) — a restrained accent, reusing the
// SAME existing profile-palette tokens (src/lib/profileTheme.js — already
// how the personal/organizer card washes tell those two apart) rather than
// a new/arbitrary color set. Icon glyphs themselves stay `ink` (unchanged,
// always-readable stroke) — the color lives ONLY in a soft circular
// backdrop behind the glyph, exactly the existing card-wash convention
// (a translucent tint OVER the card's own paper/field background), so
// light/dark contrast is inherited for free instead of re-derived, and
// color is never the only signal (shape + label are unchanged). Kept in
// one small map here (not per-call-site) so Account/Notifications can
// never drift on what a given meaning's color is — Notifications.jsx's
// own KindIcon imports this exact map.
export const ROW_ACCENT_COLORS = {
  team: PROFILE_PALETTE_COLORS.moss,
  activity: PROFILE_PALETTE_COLORS.rose,
  payments: PROFILE_PALETTE_COLORS.sand,
  preferences: PROFILE_PALETTE_COLORS.ink,
  hostOps: PROFILE_PALETTE_COLORS.moss,
  adminReview: PROFILE_PALETTE_COLORS.rose,
  // iOS parity: standalone screens reached from an Account row, and adminTeam
  // on sand (ink at 0.33 alpha read as a plain gray circle).
  reports: PROFILE_PALETTE_COLORS.moss,
  adminTeam: PROFILE_PALETTE_COLORS.sand,
};

export function RowIcon({ kind, size = 22, accent }) {
  const glyphSize = Math.round(size * 0.82);
  const common = { width: glyphSize, height: glyphSize, viewBox: '0 0 24 24', fill: 'none', stroke: ink, strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' };
  const byKind = {
    pencil: <path d="M15.2 4.3l4.5 4.5L8.4 20.1H4v-4.4z" />,
    bell: <><path d="M12 3.5c-2.8 0-5 2.2-5 5v4.6l-1.6 2.7c-.3.5.1 1.2.7 1.2h11.8c.6 0 1-.7.7-1.2L17 13.1V8.5c0-2.8-2.2-5-5-5z" /><path d="M9.6 18.6a2.4 2.4 0 0 0 4.8 0" /></>,
    calendarCheck: <><rect x="3.5" y="5" width="17" height="15.5" rx="2.3" /><path d="M3.5 9.7h17" /><path d="M8 3v4M16 3v4" /><path d="M8.7 14.7l2 2 4.3-4.3" /></>,
    sliders: <><path d="M4 6.5h6M14 6.5h6M4 12h9M17 12h3M4 17.5h11M19 17.5h1" /><circle cx="12" cy="6.5" r="2.1" /><circle cx="15" cy="12" r="2.1" /><circle cx="17" cy="17.5" r="2.1" /></>,
    receipt: <><path d="M6.5 3h11v18l-2.3-1.5L13 21l-2.2-1.5L8.5 21l-2-1.5V3z" /><path d="M9.2 8.2h5.6M9.2 12h5.6M9.2 15.8h3.6" /></>,
    document: <><path d="M7.3 3h6.4l4 4v14H7.3z" /><path d="M13.7 3v4h4" /><path d="M9.6 12.3h5M9.6 15.7h5" /></>,
    shield: <path d="M12 3.2l6.8 2.8v5.7c0 4.7-3 7.4-6.8 8.7-3.8-1.3-6.8-4-6.8-8.7V6z" />,
    banknote: <><rect x="3" y="7.3" width="18" height="9.4" rx="1.6" /><circle cx="12" cy="12" r="2.3" /><path d="M6 9.8h0M18 14.2h0" /></>,
    checklist: <><path d="M4.2 6.3h1.8M4.2 12h1.8M4.2 17.7h1.8" /><path d="M9 6.3h10.8M9 12h10.8M9 17.7h6.6" /></>,
    users: <><circle cx="9" cy="8" r="3" /><path d="M3.6 19c0-3.2 2.4-5.4 5.4-5.4S14.4 15.8 14.4 19" /><circle cx="17.3" cy="9.6" r="2.2" /><path d="M15.7 13.6c2.2.4 3.9 2.2 3.9 5" /></>,
    switch: <><rect x="3" y="9" width="18" height="6" rx="3" /><circle cx="8" cy="12" r="2.1" /></>,
    logout: <><path d="M9.2 4.3H5v15.4h4.2" /><path d="M12.3 12h8.7M21 12l-3.3-3.3M21 12l-3.3 3.3" /></>,
    login: <><path d="M9.2 4.3H5v15.4h4.2" /><path d="M12.3 12h8.7M17.7 8.7l3.3 3.3-3.3 3.3" /></>,
    heart: <path d="M12 20.2s-7.4-4.4-7.4-10a4.3 4.3 0 0 1 7.4-2.9 4.3 4.3 0 0 1 7.4 2.9c0 5.6-7.4 10-7.4 10z" />,
    calendar: <><rect x="3.5" y="5" width="17" height="15.5" rx="2.3" /><path d="M3.5 9.7h17M8 3v4M16 3v4M8 13.5h.01M12 13.5h.01M16 13.5h.01M8 17h.01M12 17h.01" /></>,
    person: <><circle cx="12" cy="12" r="8.6" /><circle cx="12" cy="10" r="2.9" /><path d="M6.6 18.3c1.2-2.1 3.1-3.2 5.4-3.2s4.2 1.1 5.4 3.2" /></>,
    bookmark: <path d="M7 3.5h10v17l-5-3.6-5 3.6z" />,
    checkCircle: <><circle cx="12" cy="12" r="8.6" /><path d="M8.3 12.3l2.5 2.5 4.9-5" /></>,
    lightbulb: <><path d="M9 18.5h6M10 21h4" /><path d="M12 3a6 6 0 0 0-3.6 10.8c.7.6 1.1 1.4 1.1 2.2v.5h5v-.5c0-.8.4-1.6 1.1-2.2A6 6 0 0 0 12 3z" /></>,
    hexCoin: <><circle cx="12" cy="12" r="8.6" /><path d="M12 7.2l4.2 2.4v4.8L12 16.8l-4.2-2.4V9.6z" /></>,
    store: <><path d="M4 9.5l1.5-5h13L20 9.5" /><path d="M4 9.5c0 1.4 1.1 2.5 2.7 2.5s2.6-1.1 2.6-2.5c0 1.4 1.1 2.5 2.7 2.5s2.7-1.1 2.7-2.5c0 1.4 1 2.5 2.6 2.5S20 10.9 20 9.5" /><path d="M5.5 12v8h13v-8M10 20v-4.5h4V20" /></>,
    coin: <><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5v9M9.6 9.6c.5-.8 1.4-1.2 2.4-1.2 1.4 0 2.4.7 2.4 1.8 0 2.4-4.8 1.2-4.8 3.6 0 1.1 1 1.8 2.4 1.8 1 0 1.9-.4 2.4-1.2" /></>,
    // Note 66: Account tiles.
    ticket: <><path d="M3.5 8.2V6.5h17v1.7a2.3 2.3 0 0 0 0 4.6v4.7h-17v-4.7a2.3 2.3 0 0 0 0-4.6z" /><path d="M14.5 6.5v11" strokeDasharray="1.6 2" /></>,
    wallet: <><path d="M4 7.5h14.5a1.5 1.5 0 0 1 1.5 1.5v9.5a1.5 1.5 0 0 1-1.5 1.5H5.5A1.5 1.5 0 0 1 4 18.5z" /><path d="M4 7.5l11-3v3" /><path d="M16 13.5h.01" /></>,
    help: <><circle cx="12" cy="12" r="8.6" /><path d="M9.6 9.6a2.5 2.5 0 0 1 4.8.9c0 1.7-2.4 2.1-2.4 3.6" /><path d="M12 16.9v.01" /></>,
    chart: <><path d="M4 20h16" /><path d="M7 16.5v-5M12 16.5V7M17 16.5v-8" /></>,
    alertShield: <><path d="M12 3.2l6.8 2.8v5.7c0 4.7-3 7.4-6.8 8.7-3.8-1.3-6.8-4-6.8-8.7V6z" /><path d="M12 8.5v4.3M12 15.4v0" /></>,
  };
  return (
    <span
      aria-hidden
      style={{
        width: size, height: size, flex: 'none', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center',
        // iOS parity (2026-10-18): every section uses the same plain line icon, no coloured backdrop.
        background: 'transparent',
      }}
    >
      <svg {...common} style={{ opacity: 0.72 }}>{byKind[kind]}</svg>
    </span>
  );
}

export default function Account() {
  const {
    state, T, set, goEditName, goSavedList, openVerifications, goLogin, logout, canHost, toggleOrganizerMode, referralLink, shareReferral,
    startHosting,
    openMyRefunds,
    loadHomeStories, openStoryViewer, openStoryLibraryPicker, openStoryCameraPicker,
    loadPaymentBookings, loadMyRefunds, loadVerifications, loadRefundQueue, loadOrganizerHoldingSummary, loadPendingEventsCount,
    openPaymentDetails, goDashboard, loadHomeLiveEvents, loadRealEventsById,
    loadMyOrgStats, openPublicProfile, openReports, openAccountGroup, goSurveysHosting,
    loadMyOrganizerMemberships,
    loadMyEventCredits, loadMyConfirmedEventCredits,
    loadMyAdminInvite, loadAdminTeam, openHostSetup, openOrganizerProfile, goNotifications, rewardsEnabled, rewardsV2Enabled, loadRewardsSummary,
  } = useBanBe();
  const s = state;
  const myKeychain = useMyKeychain();
  const [shareCardFor, setShareCardFor] = useState(null); // 'member' | 'host' | null
  // Account search — restored only when we're coming back from a search result
  // (see lib/accountSearch.js); a normal visit starts with it closed.
  const [searchInit] = useState(() => takeSearchState());
  const [searchOpen, setSearchOpen] = useState(searchInit.open);
  const [searchQuery, setSearchQuery] = useState(searchInit.query);
  const searchInputRef = useRef(null);
  useEffect(() => { if (searchOpen && !searchInit.open) searchInputRef.current?.focus(); }, [searchOpen, searchInit.open]);
  const toggleSearch = () => {
    if (searchOpen) { setSearchQuery(''); resetSearchState(); }
    setSearchOpen(v => !v);
  };
  // Note 66 (Simple Shell, Phase 2): Account has no Personal / Host / Admin tabs any more. Its content follows the
  // mode: organizer mode on = host content, off = goer content. Admin lives behind one "Admin tools" row (the
  // 'admin' AccountGroup). `s.accountTab` is kept in state for compatibility but is no longer read here.
  const isOrganizer = s.organizerMode;
  const isAdmin = s.accountType === 'admin';
  // Host-side review tracking (iOS parity): submitted ('review') + needs-fix events.
  const submitted = useSubmittedEvents(!!s.user?.id && isOrganizer);
  // "Post a story" (host mode only) — the two-option menu (Photo library / Camera). The file inputs and upload
  // live in StoryCreateOverlay.jsx (mounted once in App.jsx); this only flips the shared open* flags.
  const [hostStoryMenuOpen, setHostStoryMenuOpen] = useState(false);

  // Task 3.3 (07-notifications.md) — active stories (mine + followed hosts') so the avatar ring reflects real data.
  useEffect(() => { if (s.user) loadHomeStories(); }, [s.user, loadHomeStories]);
  // Organizer Team pass — this account's own pending invites/accepted memberships (team invite banner, Team tile).
  useEffect(() => { if (s.user?.id) loadMyOrganizerMemberships(); }, [s.user?.id, loadMyOrganizerMemberships]);
  // Admin Team pass — this account's own pending admin invite (Action Center), reachable regardless of role.
  useEffect(() => { if (s.user?.id) loadMyAdminInvite(); }, [s.user?.id, loadMyAdminInvite]);
  useEffect(() => { if (s.canManageAdmins) loadAdminTeam(); }, [s.canManageAdmins, loadAdminTeam]);
  // Pending event-credit invites ("did I really help organize this event") — the Team tile badge.
  useEffect(() => { if (s.user?.id) loadMyEventCredits(); }, [s.user?.id, loadMyEventCredits]);
  useEffect(() => { if (s.user?.id) loadMyConfirmedEventCredits(); }, [s.user?.id, loadMyConfirmedEventCredits]);
  // Rewards strip: the same summary the Home shortcut reads; no request at all while the switch is off.
  useEffect(() => { if (s.user?.id && rewardsEnabled) loadRewardsSummary(); }, [s.user?.id, rewardsEnabled, loadRewardsSummary]);
  // TASK A (2026-10-01 UX foundation pass) — the same canonical sources Home loads, so the Action Center and the
  // tile badges reflect live server state here too.
  useEffect(() => {
    if (!s.user?.id) return;
    loadPaymentBookings();
    loadMyRefunds();
    if (canHost) {
      loadVerifications();
      loadRefundQueue();
      loadOrganizerHoldingSummary();
    }
    if (isAdmin) loadPendingEventsCount();
  }, [s.user?.id, canHost, isAdmin, loadPaymentBookings, loadMyRefunds, loadVerifications, loadRefundQueue, loadOrganizerHoldingSummary, loadPendingEventsCount]);
  useEffect(() => { if (canHost && s.myOrganizerId) loadMyOrgStats(); }, [canHost, s.myOrganizerId, loadMyOrgStats]);
  const myHolding = pickSoonest(s.paymentBookings, 'holding', 'hold_expires_at');
  const myPendingVerification = (s.paymentBookings || [])
    .filter(b => b.payment_state === 'pending_verification')
    .sort((a, b) => new Date(a.proof_uploaded_at || 0) - new Date(b.proof_uploaded_at || 0))[0] || null;
  const goerActionItems = sortActionCenterItems(buildActionCenterItems({
    role: 'goer', T, now: s.now || Date.now(),
    myHolding, myPendingVerification, myRefunds: s.myRefunds || [],
    myAdminInvite: s.myAdminInvite,
    onOpenPayment: (bookingId) => openPaymentDetails(bookingId, 'profile'),
    onOpenMyRefunds: () => openMyRefunds('profile'),
    onOpenAdminInvite: () => openAccountGroup('adminTeam'),
  }));
  const hostActionItems = canHost ? sortActionCenterItems(buildActionCenterItems({
    role: 'host', T, now: s.now || Date.now(),
    verifications: s.verifications || [], refundQueue: s.refundQueue || [], orgHolding: s.organizerHoldingSummary,
    onOpenVerifications: () => openVerifications('profile'),
    onOpenRefundCenter: () => openVerifications('profile'),
    onOpenDashboard: () => goDashboard('profile'),
  })) : [];
  // Goer mode: as before on Personal (host duties stay visible while organizer mode is off, so owed money is never
  // hidden). Host mode: host duties first-class, plus this account's own goer deadlines (a held seat about to
  // expire) — with the tabs gone there is no other Account surface that would show those.
  const actionItems = sortActionCenterItems([...goerActionItems, ...hostActionItems]);
  const myStoryGroup = s.myOrganizerIds.length ? s.homeStories.find(g => s.myOrganizerIds.includes(g.organizerId)) : null;
  const hasActiveStory = !!myStoryGroup;
  const storyUnviewed = hasActiveStory && !myStoryGroup.allViewed;

  // Once an event is over it belongs in "Completed", not "Going".
  const goingCount = s.attending
    .map(k => EVENTS.find(e => e.key === k))
    .filter(e => e && e.endedHoursAgo == null).length;
  const savedCount = (s.favorites || []).length;

  const profileName = s.user ? (s.user.name || (s.user.email ? s.user.email.split('@')[0] : T('Bạn', 'You'))) : T('Khách', 'Guest');
  // Host card highlight: this host has an open event starting within 24h or in progress.
  const hostOwnKeys = s.myOrgEventKeys.filter(k => s.myOrgEventOrganizerId[k] === s.myOrganizerId);
  const hostRealKeys = hostOwnKeys.filter(k => !EVENTS.some(e => e.key === k));
  useEffect(() => {
    if (!canHost || !s.myOrganizerId) return;
    loadHomeLiveEvents();
    if (hostRealKeys.length) loadRealEventsById(hostRealKeys);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canHost, s.myOrganizerId, hostRealKeys.join(','), loadHomeLiveEvents, loadRealEventsById]);
  const hostPhases = hostOwnKeys.map(k => {
    const cat = EVENTS.find(e => e.key === k);
    if (cat) {
      const o = liveEventOverrides(s.homeLiveEvents[k], cat);
      const merged = o ? { ...cat, ...o } : cat;
      return merged.cancelled || merged.endedHoursAgo != null ? null : reminderPhase(merged.startDate);
    }
    const r = s.realEventsById[k];
    return r ? reminderPhase(r.startsAt, { status: r.status }) : null;
  }).filter(Boolean);
  const hostReminder = hostPhases.includes('live') ? 'live' : hostPhases[0] || null;
  const profileSub = isAdmin ? T('Quản trị viên', 'Admin') : isOrganizer ? T('Người tham gia ▪︎ Người tổ chức', 'Goer ▪︎ Host') : T('Người tham gia', 'Goer');
  const openMyPublicProfile = () => { if (s.user?.handle) openPublicProfile(s.user.handle, 'profile'); };

  // ---- Tiles (note 66) --------------------------------------------------------------------------------------
  const goerTiles = [
    { tileKey: 'tickets', icon: 'ticket', title: T('Vé & đặt chỗ', 'Tickets'),
      value: goingCount > 0 ? T(`${goingCount} sắp tới`, `${goingCount} upcoming`) : T('Chưa có vé sắp tới', 'Nothing upcoming'),
      badge: computeMyTicketsActionCount(s), onClick: () => openAccountGroup('activity'),
      // Test-only observability carried over from the old account-going-card: the unfiltered s.attending.length.
      dataAttrs: { 'data-attending-raw-count': s.attending.length } },
    { tileKey: 'wallet', icon: 'wallet', title: T('Ví & chứng từ', 'Wallet'),
      value: T('Hoá đơn, biên nhận, hoàn tiền', 'Invoices, receipts, refunds'),
      badge: computeMyRefundActionCount(s), onClick: () => openAccountGroup('payments') },
    { tileKey: 'saved', icon: 'bookmark', title: T('Đã lưu', 'Saved'),
      value: T(`${savedCount} sự kiện`, `${savedCount} ${savedCount === 1 ? 'event' : 'events'}`), onClick: goSavedList },
    { tileKey: 'help', icon: 'help', title: T('Trợ giúp', 'Help'),
      value: T('Hướng dẫn, điều khoản, Q&A', 'Guides, terms, Q&A'), onClick: () => openAccountGroup('helpLegal') },
  ];
  const eventsValue = (() => {
    const bits = [];
    if (submitted.pending.length) bits.push(T(`${submitted.pending.length} chờ duyệt`, `${submitted.pending.length} in review`));
    if (submitted.needsFix.length) bits.push(T(`${submitted.needsFix.length} cần sửa`, `${submitted.needsFix.length} to fix`));
    if (bits.length) return bits.join(' · ');
    if (s.myOrgPublishedEventCount !== null && s.myOrgPublishedEventCount !== undefined) {
      return T(`${s.myOrgPublishedEventCount} đã đăng`, `${s.myOrgPublishedEventCount} published`);
    }
    return null;
  })();
  const hostTiles = [
    // Was the "Submitted Events" row; the Dashboard holds the same review queue (pending + needs fixing + View).
    { tileKey: 'events', icon: 'calendarCheck', title: T('Sự kiện', 'Events'), value: eventsValue,
      badge: submitted.total, onClick: () => goDashboard('profile') },
    { tileKey: 'getpaid', icon: 'banknote', title: T('Nhận tiền', 'Get paid'),
      value: T('Xác nhận, hoàn tiền, chứng từ', 'Verify, refunds, documents'),
      badge: computeHostActionCount(s), onClick: () => openAccountGroup('hostOps') },
    { tileKey: 'team', icon: 'users', title: T('Đội ngũ', 'Team'),
      value: T('Lời mời, thành viên', 'Invites, members'),
      badge: s.myOrganizerInvites.length + s.myEventCredits.length, onClick: () => openAccountGroup('team') },
    // No organizer yet: the tile opens the same "Set up profile" flow as org-profile-ensure.
    { tileKey: 'reports', icon: 'chart', title: T('Báo cáo', 'Reports'),
      value: s.myOrganizerId ? T('Số liệu tổ chức', 'Host metrics') : null,
      onClick: () => (s.myOrganizerId ? openReports('host', s.myOrganizerId, 'profile') : openHostSetup()) },
  ];

  const rewardsSummaryLive = rewardsEnabled && s.rewardsSummaryStatus === 'loaded' && !!s.rewardsSummary;
  const rewardsStreak = capsuleStreak(s.rewardsSummary, rewardsV2Enabled);
  const rewardsLabel = rewardsSummaryLive
    ? (rewardsStreak.unit === 'week'
      ? T(`🔥 ${rewardsStreak.value} tuần · ${s.rewardsSummary.balance} xu`, `🔥 ${rewardsStreak.value}-week streak · ${s.rewardsSummary.balance} coins`)
      : T(`🔥 ${rewardsStreak.value} ngày · ${s.rewardsSummary.balance} xu`, `🔥 ${rewardsStreak.value}-day streak · ${s.rewardsSummary.balance} coins`))
    : T('Phần thưởng & huy hiệu', 'Rewards & badges');

  const organizerToggleRow = (
    <MoreRow
      key="organizer-mode"
      icon="switch"
      label={T('Chế độ tổ chức', 'Hosting mode')}
      sub={T('Bật để tạo và quản lý sự kiện. Tắt lúc nào cũng được.', 'Turn on to create and manage events. Turn it off any time.')}
      testId="organizer-mode-toggle"
      role="switch" ariaChecked={isOrganizer}
      disabled={s.organizerModeBusy}
      onClick={toggleOrganizerMode}
      end={(
        <span aria-hidden style={{ flex: 'none', width: 44, height: 26, borderRadius: 13, padding: 3, boxSizing: 'border-box', background: isOrganizer ? ink : 'rgba(var(--bb-fg-rgb),0.18)', transition: 'background .15s' }}>
          <span style={{ display: 'block', width: 20, height: 20, borderRadius: '50%', background: paper, transform: isOrganizer ? 'translateX(18px)' : 'translateX(0)', transition: 'transform .15s' }} />
        </span>
      )}
    />
  );
  const notificationsRow = (
    <MoreRow key="notifications" icon="bell" label={T('Thông báo', 'Notifications')} testId="account-notifications" onClick={goNotifications}
      badge={s.unreadNotifications || 0} badgeLabel={T(`${s.unreadNotifications || 0} chưa đọc`, `${s.unreadNotifications || 0} unread`)} />
  );
  const settingsRow = (
    <MoreRow key="settings" icon="sliders" label={T('Cài đặt', 'Settings')} testId="account-group-preferences" onClick={() => openAccountGroup('preferences')} />
  );
  const adminRow = isAdmin ? (
    <MoreRow key="admin" icon="shield" label={T('Công cụ quản trị', 'Admin tools')} testId="account-admin-tools"
      badge={computeAdminModerationCount(s)} badgeLabel={T(`${computeAdminModerationCount(s)} mục mới`, `${computeAdminModerationCount(s)} new item(s)`)}
      onClick={() => openAccountGroup('admin')} />
  ) : null;

  const goerMoreRows = [
    notificationsRow,
    <MoreRow key="following" icon="heart" label={T('Đang theo dõi', 'Following')} testId="account-following"
      trailing={s.followedStatus === 'loaded' ? String(s.followedOrgIds.length) : null} onClick={() => set({ screen: 'following' })} />,
    referralLink ? (
      <MoreRow key="invite" icon="users" label={T('Mời bạn bè', 'Invite friends')} testId="account-invite-friends" onClick={shareReferral}
        sub={s.referralShared ? T('Đã sao chép link mời ▪︎ gửi cho bạn bè thôi!', 'Invite link copied ▪︎ send it to a friend!') : null} />
    ) : null,
    s.user?.handle ? (
      <MoreRow key="share" icon="person" label={T('Chia sẻ thẻ hồ sơ', 'Share your card')} testId="account-share-card-personal" onClick={() => setShareCardFor('member')} />
    ) : null,
    s.user ? (
      <MoreRow key="reports" icon="chart" label={T('Báo cáo', 'Reports')} testId="account-reports-personal" onClick={() => openReports('personal', null, 'profile')} />
    ) : null,
    settingsRow,
    s.user ? organizerToggleRow : null,
    adminRow,
  ];
  const hostMoreRows = [
    notificationsRow,
    <MoreRow key="story" icon="pencil" label={T('Đăng story', 'Post a story')} testId="account-host-post-story"
      sub={T('Thêm chữ và liên kết, sửa hoặc xóa sau khi đăng', 'Add text and a link, edit or delete after posting')}
      onClick={() => setHostStoryMenuOpen(v => !v)} />,
    s.myOrganizerId ? (
      <MoreRow key="share-host" icon="store" label={T('Chia sẻ thẻ tổ chức', 'Share host card')} testId="account-share-card-host" onClick={() => setShareCardFor('host')} />
    ) : null,
    <MoreRow key="surveys" icon="lightbulb" label={T('Khảo sát & ý tưởng sự kiện', 'Surveys & event ideas')} testId="account-group-surveys" onClick={goSurveysHosting} />,
    s.myOrganizerId ? (
      <MoreRow key="org-profile" icon="store" label={T('Hồ sơ tổ chức', 'Organizer profile')} testId="account-organizer-profile" onClick={() => openOrganizerProfile(s.myOrganizerId, 'profile')} />
    ) : null,
    settingsRow,
    organizerToggleRow,
    adminRow,
  ];

  return (
    <div style={{ position: 'relative', animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Account" data-account-mode={isOrganizer ? 'host' : 'goer'}>
      {/* Sticky header: title + search toggle/input (unchanged by note 66, minus the tabs that used to sit under it). */}
      <div style={{ position: 'sticky', top: 0, zIndex: 5, background: paper, paddingBottom: 8 }} data-testid="account-fixed-header">
        <div style={{ padding: `${DOCK_HEADER.top}px ${DOCK_HEADER.side}px 0`, height: DOCK_HEADER.rowHeight, boxSizing: 'content-box', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          {searchOpen ? (
            <input
              ref={searchInputRef}
              value={searchQuery}
              onChange={ev => setSearchQuery(ev.target.value)}
              placeholder={T('Tìm trong tài khoản…', 'Search Account…')}
              autoCapitalize="none" autoCorrect="off" spellCheck={false} enterKeyHint="search"
              data-testid="account-search-input"
              style={{ ...fieldGlass({ flex: 1, minWidth: 0, padding: '10px 14px', borderRadius: 999, fontSize: 13.5, color: ink, border: 'none', outline: 'none' }) }}
            />
          ) : (
            <DockHeaderTitle title={T('Tài khoản', 'Account')} testId="account-title" />
          )}
          <span style={{ display: 'flex', alignItems: 'center', gap: 14, flex: 'none', marginLeft: searchOpen ? 12 : 0 }}>
            <span onClick={toggleSearch} data-testid="account-search-toggle" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2, cursor: 'pointer', color: ink }}>
              <span style={{ width: 34, height: 34, borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', background: fieldSolid }}>
                <svg width={14} height={14} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round">
                  {searchOpen ? <path d="M5 5l14 14M19 5L5 19" /> : <><circle cx="11" cy="11" r="7" /><path d="M21 21l-4.35-4.35" /></>}
                </svg>
              </span>
              <span style={{ fontSize: 9.5, opacity: 0.7 }}>{searchOpen ? T('Đóng', 'Close') : T('Tìm', 'Search')}</span>
            </span>
          </span>
        </div>
      </div>

      {searchOpen && <div style={{ height: 8 }} />}
      {searchOpen && <AccountSearchResults query={searchQuery} />}

      <div data-testid="account-content" style={{ display: searchOpen ? 'none' : 'block' }}>
        {/* 2. Identity card. Goer: the personal profile card (it IS the profile; › opens the public page).
            Host: the organizer card instead, with a small link back to the personal public profile. */}
        {!isOrganizer && (
          <KeychainFrame config={myKeychain} margin="8px 20px 0" cardHeight={92} testId="account-keychain-frame">
          {({ reserveLeft, reserveRight }) => (
          <div
            style={{
              ...cardGlass({ margin: 0, padding: `18px ${16 + reserveRight}px 18px ${16 + reserveLeft}px`, display: 'flex', gap: 14, alignItems: 'center' }),
              // Note 66 follow-up: the theme wash sits on the `block` fill, so the card reads on paper in light mode.
              background: `linear-gradient(165deg, ${PROFILE_PALETTE_COLORS[s.user?.profileTheme] || PROFILE_PALETTE_COLORS.default}55, transparent 70%), ${block}`,
            }}
            data-testid="account-profile-card"
          >
            {/* Story ring: bright while an active story is unviewed, subdued once viewed, none without a story. */}
            <div
              onClick={hasActiveStory ? () => openStoryViewer(myStoryGroup.organizerId) : undefined}
              data-testid="account-story-ring"
              data-story-state={hasActiveStory ? (storyUnviewed ? 'unviewed' : 'viewed') : 'none'}
              style={{
                flex: 'none', width: 64, height: 64, borderRadius: 15, display: 'flex', alignItems: 'center', justifyContent: 'center',
                border: hasActiveStory ? `2.5px solid ${storyUnviewed ? alert : 'transparent'}` : '2.5px solid transparent',
                boxShadow: hasActiveStory && !storyUnviewed ? `inset 0 0 0 2.5px ${rule}` : 'none',
                cursor: hasActiveStory ? 'pointer' : 'default',
              }}
            >
              {s.user?.avatarUrl ? (
                <img src={s.user.avatarUrl} alt="" style={{ width: 56, height: 56, borderRadius: 12, objectFit: 'cover' }} />
              ) : (
                <div style={{ ...fieldGlass({ width: 56, height: 56, borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center' }), ...display(22) }}>
                  {(profileName || 'B').trim()[0]?.toUpperCase() || 'B'}
                </div>
              )}
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0, flex: 1 }}>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, minWidth: 0 }}>
                <span style={{ ...display(22, { lineHeight: 1.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{profileName}</span>
                {s.user && (
                  <span onClick={goEditName} data-testid="account-rename" style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 11.5, color: ink2, cursor: 'pointer', flex: 'none' }}>
                    <RowIcon kind="pencil" size={13} />{T('Đổi tên', 'Rename')}
                  </span>
                )}
              </div>
              {s.user?.handle && <span style={{ fontSize: 11.5, color: ink2 }}>@{s.user.handle}</span>}
              <span style={{ fontSize: 11, letterSpacing: '0.06em', color: ink2 }}>{profileSub}</span>
            </div>
            {s.user && (
              <span
                onClick={openMyPublicProfile}
                role="button"
                aria-label={T('Mở hồ sơ công khai', 'Open your public profile')}
                data-testid="account-edit-profile"
                style={{ flex: 'none', fontSize: 20, color: ink, opacity: 0.55, cursor: 'pointer', alignSelf: 'center', padding: '12px 4px' }}>
                ›
              </span>
            )}
          </div>
          )}
          </KeychainFrame>
        )}

        {isOrganizer && (
          <>
            {/* ensure_my_organizer (migration 163): organizer mode on but no owned organizer yet. */}
            {canHost && !s.myOrganizerId && !s.hostSetupOpen && (
              <div data-testid="org-profile-ensure" style={{ ...cardGlass({ margin: '8px 20px 0', padding: '20px 18px', display: 'flex', flexDirection: 'column', gap: 10 }) }}>
                <span style={{ ...display(18, { lineHeight: 1.3 }) }}>{T('Hoàn tất hồ sơ tổ chức', 'Finish your host profile')}</span>
                <p style={{ fontSize: 12.5, lineHeight: 1.5, color: ink2, margin: 0 }}>
                  {T('Chọn ảnh bìa, đặt tên và viết vài dòng giới thiệu để khách biết bạn là ai.', 'Pick a cover, name it and add a short intro so guests know who you are.')}
                </p>
                <div role="button" data-testid="org-profile-ensure-setup" onClick={openHostSetup} style={{ ...inkButton({ marginTop: 4, borderRadius: 18, padding: 14, fontSize: 14 }) }}>{T('Thiết lập hồ sơ', 'Set up profile')}</div>
              </div>
            )}
            {canHost && s.myOrganizerId && (
              <div
                onClick={() => goDashboard('profile')}
                className={hostReminder ? 'bb-rem-card' : undefined}
                data-reminder={hostReminder || undefined}
                style={{
                  ...cardGlass({ margin: '8px 20px 0', padding: '18px 16px', display: 'flex', flexDirection: 'column', gap: 8, cursor: 'pointer' }),
                  position: 'relative', '--bb-rem-r': '12px',
                  // Moss wash, never the personal `profileTheme`, so it always reads as the organization identity.
                  background: `linear-gradient(165deg, ${PROFILE_PALETTE_COLORS.moss}66, transparent 70%), ${block}`,
                }}
                data-testid="org-profile-card"
              >
                {hostReminder && <style>{REMINDER_CSS}</style>}
                <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
                  <div style={{ flex: 'none', width: 56, height: 56, borderRadius: 14, overflow: 'hidden' }}>
                    {organizerAvatarUrl(s.myOrganizerAvatarPath, s.myOrganizerAvatarR2Ref) ? (
                      <img src={organizerAvatarUrl(s.myOrganizerAvatarPath, s.myOrganizerAvatarR2Ref)} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                    ) : (
                      <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', background: ink, color: paper, ...display(20) }}>
                        {(s.orgRegName || 'B').trim()[0]?.toUpperCase() || 'B'}
                      </div>
                    )}
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0, flex: 1 }}>
                    <span style={{ ...display(18, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{s.orgRegName || T('Chưa đặt tên', 'Unnamed host')}</span>
                    {s.myOrgPublishedEventCount !== null && (
                      <span style={{ fontSize: 11, color: ink2 }}>
                        {s.myOrgHostingSinceYear
                          ? T(`Tổ chức từ ${s.myOrgHostingSinceYear} ▪︎ ${s.myOrgPublishedEventCount} sự kiện`, `Hosting since ${s.myOrgHostingSinceYear} ▪︎ ${s.myOrgPublishedEventCount} events`)
                          : T('Chưa có sự kiện công khai nào', 'No published events yet')}
                      </span>
                    )}
                  </div>
                  {hostReminder && (
                    <span data-testid="org-profile-checkin-hint" style={{ flex: 'none', fontSize: 12, fontWeight: 700, color: '#7A5200' }}>{T('Điểm danh', 'Check-in')}</span>
                  )}
                  <span aria-hidden data-testid="org-profile-view-public" style={{ flex: 'none', fontSize: 20, color: ink, opacity: hostReminder ? 1 : 0.55 }}>›</span>
                </div>
                {s.orgRegDesc && (
                  <p style={{ fontSize: 12.5, lineHeight: 1.5, color: ink2, margin: 0 }}>{s.orgRegDesc}</p>
                )}
              </div>
            )}
            {s.user?.handle && (
              <div style={{ padding: '8px 24px 0', display: 'flex', justifyContent: 'flex-end' }}>
                <span
                  onClick={openMyPublicProfile}
                  role="button"
                  data-testid="account-switch-identity"
                  style={{ fontSize: 12.5, color: ink2, cursor: 'pointer', padding: '12px 0', display: 'inline-flex', alignItems: 'center', gap: 4 }}
                >
                  {T('Hồ sơ cá nhân', 'Personal profile')} <span aria-hidden>›</span>
                </span>
              </div>
            )}
          </>
        )}

        {/* 3. Four big tiles, mode-scoped. */}
        <AccountTileGrid tiles={isOrganizer ? hostTiles : goerTiles} T={T} />

        {/* 4. Rewards strip (behind the `rewards` switch, both modes). */}
        {rewardsEnabled && s.user && (
          <RewardsStrip
            label={rewardsLabel}
            ariaLabel={rewardsSummaryLive ? `${rewardsLabel}. ${T('Mở phần thưởng và huy hiệu', 'Open rewards and badges')}` : rewardsLabel}
            onClick={() => set({ screen: 'rewards', rewardsBack: 'profile' })}
          />
        )}

        {/* 5. Action Center (renders nothing when there is nothing to do). */}
        <ActionCenter items={actionItems} onSeeAll={() => openVerifications('profile')} T={T} />

        {/* 6. Team invite banner — goer mode only (in host mode the Team tile carries the same badge). */}
        {!isOrganizer && s.myOrganizerInvites.length > 0 && (
          <div
            onClick={() => openAccountGroup('team')}
            role="button"
            data-testid="account-team-invite-banner"
            style={{ margin: '8px 20px 0', minHeight: 52, boxSizing: 'border-box', padding: '10px 16px', borderRadius: 14, background: block, display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }}
          >
            <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 15, color: ink }}>
              <RowIcon kind="users" accent={ROW_ACCENT_COLORS.team} />{T('Bạn có lời mời Team', 'You have a team invite')}
            </span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span
                role="status"
                aria-label={T(`${s.myOrganizerInvites.length} lời mời`, `${s.myOrganizerInvites.length} invite(s)`)}
                style={{ fontSize: 11, fontWeight: 700, color: paper, background: alert, borderRadius: 999, padding: '2px 7px', minWidth: 18, textAlign: 'center' }}
                data-testid="account-team-invite-banner-badge"
              >
                {s.myOrganizerInvites.length}
              </span>
              <span aria-hidden style={{ fontSize: 17, color: ink3, lineHeight: 1 }}>›</span>
            </span>
          </div>
        )}

        {/* 7. More: one grouped list. */}
        <AccountSectionLabel label={T('Thêm', 'More')} testId="account-section-more" />
        <MoreList testId="account-more-group">{isOrganizer ? hostMoreRows : goerMoreRows}</MoreList>
        {s.organizerModeError && <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '10px 24px 0' }}>{s.organizerModeError}</p>}

        {/* Host-mode "Post a story" menu (same two pickers as before). */}
        {isOrganizer && hostStoryMenuOpen && (
          <div onClick={() => setHostStoryMenuOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 35 }}>
            <div
              onClick={(e) => e.stopPropagation()}
              data-testid="account-host-post-story-menu"
              style={{ ...cardGlass({ position: 'absolute', right: 20, top: '40%', minWidth: 200 }), padding: 6, display: 'flex', flexDirection: 'column' }}
            >
              <div
                onClick={() => { setHostStoryMenuOpen(false); openStoryLibraryPicker(); }}
                data-testid="account-host-post-story-library"
                style={{ padding: '12px 14px', minHeight: 44, boxSizing: 'border-box', fontSize: 13.5, color: ink, cursor: 'pointer', borderRadius: 8, display: 'flex', alignItems: 'center', gap: 10 }}
              >
                <AttachMenuIcon name="library" />{T('Thư Viện Ảnh', 'Photo Library')}
              </div>
              <div
                onClick={() => { setHostStoryMenuOpen(false); openStoryCameraPicker(); }}
                data-testid="account-host-post-story-camera"
                style={{ padding: '12px 14px', minHeight: 44, boxSizing: 'border-box', fontSize: 13.5, color: ink, cursor: 'pointer', borderRadius: 8, display: 'flex', alignItems: 'center', gap: 10 }}
              >
                <AttachMenuIcon name="camera" />{T('Camera', 'Camera')}
              </div>
            </div>
          </div>
        )}

        {/* 8. "Host your first event" — only for an account that has never hosted (goer mode by definition). */}
        {!isOrganizer && !canHost && s.user && (
          // The shared Start hosting invitation (StartHostingCard, also the sheet behind Home's locked Hosting segment).
          // This card IS the invitation, so it turns organizer mode on right away and lands on Home > Hosting.
          <StartHostingCard canHost={false} busy={s.organizerModeBusy} style={{ margin: '16px 20px 0' }}
            onStart={() => startHosting({ land: 'home', confirmed: true })}
            testId="account-host-first-event" ctaTestId="account-host-first-event-start" />
        )}

        {/* 9. Sign out / Sign in, both modes. */}
        {s.user ? (
          <div onClick={logout} role="button" data-testid="account-sign-out" style={{ padding: '24px 24px 40px', minHeight: 44, display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink, cursor: 'pointer' }}><RowIcon kind="logout" size={18} />{T('Đăng xuất', 'Sign out')}</div>
        ) : (
          <div onClick={goLogin} role="button" data-testid="account-sign-in" style={{ padding: '24px 24px 40px', minHeight: 44, display: 'flex', alignItems: 'center', gap: 12, fontSize: 13, lineHeight: 1.5, color: ink, cursor: 'pointer' }}><RowIcon kind="login" size={18} />{T('Đăng nhập để lưu sự kiện và nhắn tin', 'Sign in to save events and message hosts')}</div>
        )}
      </div>

      <ProfileShareSheet
        open={shareCardFor !== null}
        onClose={() => setShareCardFor(null)}
        kindLabel={shareCardFor === 'host' ? T('Tổ chức', 'Host') : T('Thành viên', 'Member')}
        name={shareCardFor === 'host' ? (s.orgRegName || T('Chưa đặt tên', 'Unnamed host')) : profileName}
        subtitle={shareCardFor === 'host'
          ? (s.myOrgPublishedEventCount !== null && s.myOrgPublishedEventCount !== undefined ? T(`${s.myOrgPublishedEventCount} sự kiện`, `${s.myOrgPublishedEventCount} events`) : '')
          : (s.user?.handle ? `@${s.user.handle}` : '')}
        detail={shareCardFor === 'host' ? (s.orgRegDesc || '') : ''}
        avatarUrl={shareCardFor === 'host' ? organizerAvatarUrl(s.myOrganizerAvatarPath, s.myOrganizerAvatarR2Ref, 'card') : (s.user?.avatarUrl || '')}
        roundAvatar={shareCardFor !== 'host'}
        link={shareCardFor === 'host' ? profileShareLinks().host(s.myOrganizerId) : profileShareLinks().member(s.user?.handle)}
        idPrefix={shareCardFor === 'host' ? 'account-host-share' : 'account-personal-share'}
        kind={shareCardFor === 'host' ? 'host' : 'member'}
        publishId={shareCardFor === 'host' ? (s.myOrganizerId || '') : (s.user?.handle || '')}
        isOwner
      />
    </div>
  );
}

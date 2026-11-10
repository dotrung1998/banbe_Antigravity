import { glassCapsuleInactive } from '../lib/glassOpacity.js';
import { useEffect, useRef, useState } from 'react';
import DockHeaderTitle, { DOCK_HEADER } from '../components/ui/DockHeaderTitle.jsx';
import { useBanBe } from '../state/BanBeContext.jsx';
import { EVENTS } from '../data/events.js';
import { supabase } from '../lib/supabase.js';
import { organizerAvatarPublicUrl } from '../lib/mediaUrls.js';
import { paper, ink, ink2, ink3, block, rule, display, fieldGlass, fieldSolid, cardGlass, inkButton, alert, surface2 } from '../theme.js';
import { accountTabs, resolveAccountTab } from '../lib/accountTabs.js';
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
import { useEventProject } from '../state/useEventProject.js';
import { computeAdminModerationCount, computeHostActionCount, computeMyTicketsActionCount, computeMyRefundActionCount } from '../lib/badges.js';
import { capsuleStreak } from '../lib/rewards.js';
import { AccountTileGrid, MoreList, MoreRow, RewardsStrip } from './AccountTiles.jsx';
import StartHostingCard from '../components/StartHostingCard.jsx';
import { resolveTheme } from '../lib/themeChoice.js';

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
    sun: <><circle cx="12" cy="12" r="4" /><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6L7 7M17 17l1.4 1.4M5.6 18.4L7 17M17 7l1.4-1.4" /></>,
    globe: <><circle cx="12" cy="12" r="8.6" /><path d="M3.4 12h17.2M12 3.4c2.5 2.5 2.5 14.7 0 17.2M12 3.4c-2.5 2.5-2.5 14.7 0 17.2" /></>,
    card: <><rect x="3.5" y="5.5" width="17" height="13" rx="2" /><path d="M3.5 10h17M7 15h4" /></>,
    doc: <><path d="M6 3.5h8l4 4v13H6z" /><path d="M14 3.5v4h4M9 12h6M9 16h6" /></>,
    refund: <><path d="M4 12a8 8 0 1 0 2.5-5.8" /><path d="M4 4.5v4h4" /></>,
    bank: <><path d="M3.5 9.5L12 4l8.5 5.5z" /><path d="M6 11.5v6M10 11.5v6M14 11.5v6M18 11.5v6M4 20h16" /></>,
    plus: <path d="M12 5v14M5 12h14" />,
    star: <path d="M12 3.8l2.5 5.2 5.7.8-4.1 4 1 5.7-5.1-2.7-5.1 2.7 1-5.7-4.1-4 5.7-.8z" />,
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

/** Note 69: a labelled group of rows; the heading is a real heading, sized to be seen. */
function RowGroup({ title, testId, top = 30, children }) {
  return (
    <section data-testid={testId} style={{ marginTop: top }}>
      <h2 style={{ margin: '0 20px 4px', fontSize: 11, fontWeight: 400, letterSpacing: '.12em', textTransform: 'uppercase', color: ink3 }}>{title}</h2>
      <MoreList testId={`${testId}-list`}>{children}</MoreList>
    </section>
  );
}

export default function Account() {
  const project = useEventProject();
  const {
    state, T, set, goEditName, openRefundAccounts, openSecurity, openEventPreferences, openPolicy, pickTheme, toggleLang, openAdminEvents, goSavedList, openVerifications, goLogin, logout, canHost, toggleOrganizerMode, referralLink, shareReferral,
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
  // Note 76: the Projects row needs the list (switch event_project_hub).
  useEffect(() => { if (s.user?.id && s.featureFlags?.event_project_hub === true) project.loadMyProjects(); }, [s.user?.id, s.featureFlags?.event_project_hub]); // eslint-disable-line react-hooks/exhaustive-deps
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
  // Note 69: Personal / Host / Admin tabs again, but which ones exist follows Hosting mode (lib/accountTabs.js; iOS
  // twin AccountTabs.swift). `s.accountTab` is the selection; a tab that no longer exists falls back to the first.
  const isOrganizer = s.organizerMode;
  const isAdmin = s.accountType === 'admin';
  const tabs = s.user ? accountTabs({ isAdmin, hostMode: !!isOrganizer && canHost }) : [];
  const tab = resolveAccountTab(s.accountTab, tabs);
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
    rewardsEnabled
      ? { tileKey: 'rewards', icon: 'star', title: T('Phần thưởng', 'Rewards'), onClick: () => set({ screen: 'rewards', rewardsBack: 'profile' }) }
      : { tileKey: 'help', icon: 'help', title: T('Trợ giúp', 'Help'), onClick: () => openAccountGroup('helpLegal') },
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
    <MoreRow key="notifications" icon="bell" label={T('Tùy chọn thông báo', 'Notification preferences')} testId="account-notifications" onClick={() => set({ screen: 'notifPrefs', notifPrefsBack: 'profile' })} />
  );
  // Note 76: "Projects I'm in", or "Join an event team with a code" while I'm in none (switch event_project_hub).
  const projectsOn = !!s.user?.id && s.featureFlags?.event_project_hub === true;
  const projectsRow = projectsOn && s.myProjectsLoaded ? (s.myProjects.length > 0
    ? <MoreRow key="projects" icon="users" label={T("Dự án của tôi", "Projects I'm in")} testId="account-projects" trailing={String(s.myProjects.length)} onClick={() => set({ screen: 'myProjects' })} />
    : <MoreRow key="projects" icon="users" label={T('Vào đội sự kiện bằng mã mời', 'Join an event team with a code')} testId="account-projects-join" onClick={() => project.openJoin('', 'profile')} />) : null;
  const settingsRow = (
    <MoreRow key="settings" icon="sliders" label={T('Cài đặt', 'Settings')} testId="account-group-preferences" onClick={() => openAccountGroup('preferences')} />
  );
  const adminModeration = computeAdminModerationCount(s);
  const adminInvitesPending = (s.adminInvites || []).filter(i => i.status === 'pending').length;

  // Note 69: labelled groups instead of one "More" list.
  const activityRows = [
    <MoreRow key="following" icon="heart" label={T('Đang theo dõi', 'Following')} testId="account-following"
      trailing={s.followedStatus === 'loaded' ? String(s.followedOrgIds.length) : null} onClick={() => set({ screen: 'following' })} />,
    s.user ? (projectsRow || <MoreRow key="projects" icon="users" label={T('Đội sự kiện', 'Event teams')} testId="account-projects" onClick={() => project.openJoin('', 'profile')} />) : null,
    s.user ? (
      <MoreRow key="reports" icon="chart" label={T('Năm của bạn trên banbe', 'Your year in banbe')} testId="account-reports-personal" onClick={() => openReports('personal', null, 'profile')} />
    ) : null,
  ];
  const shareRows = [
    referralLink ? (
      <MoreRow key="invite" icon="users" label={T('Mời bạn bè', 'Invite friends')} testId="account-invite-friends" onClick={shareReferral}
        sub={s.referralShared ? T('Đã sao chép link mời ▪︎ gửi cho bạn bè thôi!', 'Invite link copied ▪︎ send it to a friend!') : null} />
    ) : null,
    s.user?.handle ? (
      <MoreRow key="share" icon="person" label={T('Chia sẻ thẻ hồ sơ', 'Share your card')} testId="account-share-card-personal" onClick={() => setShareCardFor('member')} />
    ) : null,
  ].filter(Boolean);
  // What is on screen (a System choice resolves to the device's), so the segment never shows Light on a dark page.
  const shownDark = resolveTheme(s.theme, s.systemDark) === 'dark';
  const seg = (testId, opts) => (
    <span style={{ display: 'flex', background: block, borderRadius: 999, padding: 2 }} onClick={e => e.stopPropagation()}>
      {opts.map(([k, label, on, fn]) => (
        <button key={k} type="button" data-testid={`${testId}-${k}`} onClick={fn} style={{ height: 30, padding: '0 11px', border: 'none', borderRadius: 999, fontFamily: 'inherit', fontSize: 12, cursor: 'pointer',
          background: on ? ink : 'transparent', color: on ? paper : ink2, fontWeight: on ? 600 : 400 }}>{label}</button>
      ))}
    </span>
  );
  const appRows = [
    s.user ? <MoreRow key="profile" icon="person" label={T('Hồ sơ & đăng nhập', 'Profile & sign-in')} sub={T('Tên, số điện thoại, mật khẩu', 'Name, phone, password')} testId="account-group-preferences" onClick={goEditName} /> : null,
    s.user ? notificationsRow : null,
    s.user ? <MoreRow key="foryou" icon="star" label={T('Gợi ý Dành cho bạn', 'For You preferences')} sub={T('Sở thích và mục tiêu', 'Interests and goals')} testId="account-event-preferences" onClick={() => openEventPreferences(null)} /> : null,
    <MoreRow key="appearance" icon="sun" label={T('Giao diện', 'Appearance')} testId="account-appearance" end={seg('account-theme', [['light', T('Sáng', 'Light'), !shownDark, () => pickTheme('light')], ['dark', T('Tối', 'Dark'), shownDark, () => pickTheme('dark')]])} />,
    <MoreRow key="language" icon="globe" label={T('Ngôn ngữ', 'Language')} testId="account-language" end={seg('account-lang', [['vi', 'VI', s.lang !== 'en', () => s.lang === 'en' && toggleLang()], ['en', 'EN', s.lang === 'en', () => s.lang !== 'en' && toggleLang()]])} />,
    s.user ? <MoreRow key="refund-accounts" icon="bank" label={T('Tài khoản thanh toán & nhận hoàn tiền', 'Payment & refund accounts')} testId="account-refund-accounts" onClick={() => openRefundAccounts('profile')} /> : null,
    s.user ? <MoreRow key="security" icon="shield" label={T('Quyền riêng tư & bảo mật', 'Privacy & security')} sub={T('Face ID, người bị chặn, xoá tài khoản', 'Face ID, blocked people, delete account')} testId="account-security" onClick={openSecurity} /> : null,
  ];
  const supportRows = [
    <MoreRow key="help" icon="help" label={T('Hướng dẫn', 'Help & guides')} testId="account-help" onClick={() => openAccountGroup('helpLegal')} />,
    <MoreRow key="qa" icon="help" label={T('Hỏi & Đáp', 'Questions & answers')} testId="account-faq" onClick={() => set({ screen: 'faq' })} />,
    <MoreRow key="terms" icon="doc" label={T('Điều khoản & chính sách', 'Terms & policies')} testId="account-terms" onClick={openPolicy} />,
  ];
  const hostToolRows = [
    <MoreRow key="surveys" icon="lightbulb" label={T('Khảo sát & ý tưởng sự kiện', 'Surveys & event ideas')} testId="account-group-surveys" onClick={goSurveysHosting} />,
    <MoreRow key="story" icon="pencil" label={T('Đăng story', 'Post a story')} testId="account-host-post-story"
      sub={T('Thêm chữ và liên kết, sửa hoặc xóa sau khi đăng', 'Add text and a link, edit or delete after posting')}
      onClick={() => setHostStoryMenuOpen(v => !v)} />,
    s.myOrganizerId ? (
      <MoreRow key="org-profile" icon="store" label={T('Hồ sơ tổ chức', 'Organizer profile')} testId="account-organizer-profile" onClick={() => openOrganizerProfile(s.myOrganizerId, 'profile')} />
    ) : null,
    s.myOrganizerId ? (
      <MoreRow key="share-host" icon="card" label={T('Chia sẻ thẻ tổ chức', 'Share host card')} testId="account-share-card-host" onClick={() => setShareCardFor('host')} />
    ) : null,
  ];
  const moneyRows = [
    ['refund', T('Hoàn tiền', 'Refunds'), 'refunds'],
    ['doc', T('Hoá đơn & biên nhận đã phát hành', 'Invoices & receipts issued'), 'documents'],
    ['bank', T('Tài khoản nhận tiền', 'Payout account'), 'payout'],
  ].map(([icon, label, k]) => <MoreRow key={k} icon={icon} label={label} testId={`account-money-${k}`} onClick={() => openAccountGroup('hostOps')} />);
  // The former 'admin' AccountGroup rows, inline. Back from each lands on this tab.
  const adminRows = [
    <MoreRow key="review" icon="shield" label={T('Duyệt & kiểm duyệt', 'Review & moderation')} testId="account-group-adminReview"
      badge={adminModeration} badgeLabel={T(`${adminModeration} mục mới`, `${adminModeration} new item(s)`)}
      onClick={() => set({ screen: 'accountGroup', accountGroupKey: 'adminReview', accountGroupBack: null })} />,
    <MoreRow key="team" icon="users" label={T('Đội ngũ quản trị', 'Admin team')} testId="account-group-adminTeam"
      badge={adminInvitesPending} badgeLabel={T(`${adminInvitesPending} lời mời`, `${adminInvitesPending} invite(s)`)}
      onClick={() => set({ screen: 'accountGroup', accountGroupKey: 'adminTeam', accountGroupBack: null })} />,
    <MoreRow key="events" icon="calendarCheck" label={T('Quản lý sự kiện', 'Manage events')} testId="admin-manage-events" onClick={() => set({ screen: 'adminManageEvents' })} />,
    <MoreRow key="metrics" icon="chart" label={T('Số liệu & báo cáo', 'Metrics & reports')} testId="account-reports-admin" onClick={() => openReports('admin', null, 'profile')} />,
    <MoreRow key="features" icon="sliders" label={T('Công tắc tính năng', 'Feature switches')} testId="admin-features" onClick={() => set({ screen: 'adminFeatures' })} />,
    <MoreRow key="testacc" icon="person" label={T('Tài khoản thử nghiệm', 'Test accounts')} testId="admin-test-accounts" onClick={() => set({ screen: 'adminTestAccounts' })} />,
    <MoreRow key="guide" icon="help" label={T('Hướng dẫn quản trị', 'Admin guide')} testId="account-admin-guide" onClick={() => set({ screen: 'guide', guideKey: 'admin' })} />,
  ];
  const tabMeta = {
    host: { label: T('Tổ chức', 'Host'), badge: hostActionItems.length },
    personal: { label: T('Cá nhân', 'Personal'), badge: 0 },
    admin: { label: T('Quản trị', 'Admin'), badge: adminModeration + adminInvitesPending },
  };
  const pickTab = (key) => { if (key !== tab) set({ accountTab: key }); };
  const onTabKeyDown = (e) => {
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
    e.preventDefault();
    const i = tabs.indexOf(tab);
    const next = tabs[Math.max(0, Math.min(tabs.length - 1, i + (e.key === 'ArrowRight' ? 1 : -1)))];
    pickTab(next);
    document.querySelector(`[data-testid="account-tab-${next}"]`)?.focus();
  };
  const personalItems = tabs.includes('host') ? goerActionItems : actionItems;

  return (
    <div style={{ position: 'relative', animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Account" data-account-mode={isOrganizer ? 'host' : 'goer'} data-account-tab={tab}>
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
            <h1 data-testid="account-title" style={{ margin: 0, fontSize: 30, fontWeight: 300, letterSpacing: '-.01em', color: ink }}>{T('Tài khoản', 'Account')}</h1>
          )}
          <span style={{ display: 'flex', alignItems: 'center', gap: 14, flex: 'none', marginLeft: searchOpen ? 12 : 0 }}>
            {s.user && (
              <button type="button" onClick={() => setShareCardFor('member')} data-testid="account-share-profile" aria-label={T('Chia sẻ hồ sơ', 'Share profile')}
                style={{ width: 44, height: 44, border: 'none', background: 'none', color: ink, display: 'grid', placeItems: 'center', cursor: 'pointer', padding: 0 }}>
                <svg width={22} height={22} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round"><path d="M12 15V4M8 8l4-4 4 4M5 12v7h14v-7" /></svg>
              </button>
            )}
          </span>
        </div>
      </div>

      {searchOpen && <div style={{ height: 8 }} />}
      {searchOpen && <AccountSearchResults query={searchQuery} />}

      <div data-testid="account-content" style={{ display: searchOpen ? 'none' : 'block' }}>
        {/* 2. Identity card. Goer: the personal profile card (it IS the profile; › opens the public page).
            Host: the organizer card instead, with a small link back to the personal public profile. */}
        <KeychainFrame config={myKeychain} margin="0" cardHeight={64} testId="account-keychain-frame">
          {({ reserveRight }) => {
            const hostTab = tab === 'host' && !!s.myOrganizerId;
            const orgImg = hostTab ? organizerAvatarUrl(s.myOrganizerAvatarPath, s.myOrganizerAvatarR2Ref) : '';
            const img = hostTab ? orgImg : s.user?.avatarUrl;
            const title = hostTab ? (s.orgRegName || T('Chưa đặt tên', 'Unnamed host')) : profileName;
            const initials = title.split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0]).join('').toUpperCase();
            const since = s.user?.createdAt ? ` ${T('từ', 'since')} ${new Date(s.user.createdAt).getFullYear()}` : '';
            const sub = hostTab
              ? (s.myOrgHostingSinceYear ? T(`Tổ chức từ ${s.myOrgHostingSinceYear}`, `Hosting since ${s.myOrgHostingSinceYear}`) : T('Người tổ chức', 'Host'))
              : [s.user?.handle && `@${s.user.handle}`, `${tab === 'admin' ? T('Quản trị viên', 'Admin') : isOrganizer ? T('Người tổ chức', 'Host') : T('Thành viên', 'Member')}${tab === 'admin' ? '' : since}`].filter(Boolean).join(' · ');
            const linkLabel = hostTab ? T('Hồ sơ tổ chức', 'Host profile') : T('Xem hồ sơ', 'View profile');
            const open = hostTab ? () => openOrganizerProfile(s.myOrganizerId, 'profile') : s.user?.handle ? openMyPublicProfile : undefined;
            return (
              <button type="button" data-testid="account-profile-card" onClick={open}
                style={{ display: 'flex', alignItems: 'center', gap: 16, width: '100%', padding: `8px ${20 + reserveRight}px 0 20px`, boxSizing: 'border-box', border: 'none', background: 'none', textAlign: 'left', color: ink, font: 'inherit', cursor: open ? 'pointer' : 'default' }}>
                <span style={{ flex: 'none', width: 64, height: 64, borderRadius: hostTab ? 16 : '50%', background: 'var(--bb-clay, #9C5B3B)', color: '#fff', display: 'grid', placeItems: 'center', fontSize: 22, fontWeight: 500, overflow: 'hidden' }}>
                  {img ? <img src={img} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : initials}
                </span>
                <span style={{ minWidth: 0 }}>
                  <span data-testid="account-profile-name" style={{ display: 'block', fontSize: 22, fontWeight: 300 }}>{title}</span>
                  <span style={{ display: 'block', fontSize: 13, color: ink3, marginTop: 2 }}>{sub}</span>
                  {open && <span style={{ display: 'inline-flex', alignItems: 'center', gap: 2, marginTop: 6, fontSize: 13, borderBottom: '1px solid var(--bb-rule)' }}>{linkLabel} ›</span>}
                </span>
              </button>
            );
          }}
        </KeychainFrame>
        {s.user && (
          <div style={{ margin: '18px 20px 0' }}>
            <button type="button" role="switch" aria-checked={!!isOrganizer} disabled={s.organizerModeBusy} onClick={toggleOrganizerMode} data-testid="organizer-mode-toggle"
              style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', textAlign: 'left', padding: '12px 14px', border: 'none', borderRadius: 16, color: ink, font: 'inherit', cursor: 'pointer',
                background: isOrganizer ? `color-mix(in srgb, var(--bb-moss, #5E7A5A) 14%, ${block})` : block }}>
              <span style={{ flex: 'none', width: 36, height: 36, borderRadius: '50%', background: paper, display: 'grid', placeItems: 'center' }}><RowIcon kind="store" size={19} /></span>
              <span style={{ flex: 1, fontSize: 15, fontWeight: 600 }}>{T('Chế độ tổ chức', 'Hosting mode')}
                <small style={{ display: 'block', fontSize: 12.5, fontWeight: 400, color: ink2, marginTop: 1 }}>{T('Bật để tạo và quản lý sự kiện', 'Turn on to create and manage events')}</small></span>
              <span aria-hidden style={{ flex: 'none', width: 46, height: 28, borderRadius: 14, position: 'relative', background: isOrganizer ? 'var(--bb-moss, #5E7A5A)' : 'rgba(var(--bb-fg-rgb),0.18)', transition: 'background .2s' }}>
                <span style={{ position: 'absolute', top: 3, left: 3, width: 22, height: 22, borderRadius: '50%', background: '#fff', transform: isOrganizer ? 'translateX(18px)' : 'none', transition: 'transform .2s', boxShadow: '0 1px 2px rgba(0,0,0,.2)' }} />
              </span>
            </button>
          </div>
        )}
        {tabs.length > 0 && (
          <div role="tablist" aria-label={T('Tài khoản', 'Account')} data-testid="account-tabs" onKeyDown={onTabKeyDown}
            style={{ display: 'flex', gap: 2, padding: 2, margin: '12px 20px 0', borderRadius: 999, background: surface2 }}>
            {tabs.map(key => {
              const on = key === tab;
              const m = tabMeta[key];
              return (
                <button key={key} type="button" role="tab" aria-selected={on} tabIndex={on ? 0 : -1}
                  onClick={() => pickTab(key)} data-testid={`account-tab-${key}`} className="bb-press"
                  aria-label={m.badge > 0 ? T(`${m.label}, ${m.badge} mục mới`, `${m.label}, ${m.badge} new item(s)`) : m.label}
                  style={{
                    flex: 1, minWidth: 0, minHeight: 44, border: 'none', borderRadius: 999, cursor: 'pointer', fontFamily: 'inherit',
                    fontSize: 14.5, fontWeight: 600, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6,
                    background: on ? ink : 'transparent', color: on ? paper : ink2, transition: 'background-color .18s ease, color .18s ease',
                  }}>
                  {m.label}
                  {m.badge > 0 && (
                    <span aria-hidden style={{ fontSize: 11, fontWeight: 700, minWidth: 18, padding: '1px 6px', boxSizing: 'border-box', borderRadius: 999, background: on ? paper : alert, color: on ? ink : paper }}>{m.badge}</span>
                  )}
                </button>
              );
            })}
          </div>
        )}

        {tab === 'host' && (
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
          </>
        )}

        {/* 3. Rewards strip (behind the `rewards` switch), right under the profile card on Personal (note 69). */}

        {/* 4. Four big tiles, per tab. */}
        {tab !== 'admin' && <AccountTileGrid tiles={tab === 'host' ? hostTiles : goerTiles} T={T} />}

        {/* 5. Action Center (renders nothing when there is nothing to do). Host duties on Host; on Personal while there
            is no Host tab, so owed money is never out of sight. */}
        {tab !== 'admin' && (
          <ActionCenter items={tab === 'host' ? hostActionItems : personalItems} onSeeAll={() => openVerifications('profile')} T={T} />
        )}

        {/* 6. Team invite banner, Personal only (the Host tab's Team tile carries the same badge). */}
        {tab === 'personal' && s.myOrganizerInvites.length > 0 && (
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

        {/* 7. Labelled groups (note 69; replaced the single "More" list). */}
        {tab === 'personal' && (
          <>
            <RowGroup title={T('Hoạt động của bạn', 'Your activity')} testId="account-group-activity">{activityRows}</RowGroup>
            {shareRows.length > 0 && <RowGroup title={T('Chia sẻ', 'Share')} testId="account-group-share">{shareRows}</RowGroup>}
            <RowGroup title={T('Cài đặt', 'Settings')} testId="account-group-app">{appRows}</RowGroup>
            <RowGroup title={T('Hỗ trợ', 'Support')} testId="account-group-support">{supportRows}</RowGroup>
          </>
        )}
        {tab === 'host' && (
          <>
            <RowGroup title={T('Công cụ tổ chức', 'Hosting tools')} testId="account-group-host-tools">{hostToolRows}</RowGroup>
            <RowGroup title={T('Tiền', 'Money')} testId="account-group-money">{moneyRows}</RowGroup>
          </>
        )}
        {tab === 'admin' && <RowGroup title={T('Quản trị', 'Administration')} testId="account-group-admin-tools" top={16}>{adminRows}</RowGroup>}
        {tab === 'personal' && s.organizerModeError && <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '10px 24px 0' }}>{s.organizerModeError}</p>}

        {/* Host-mode "Post a story" menu (same two pickers as before). */}
        {tab === 'host' && hostStoryMenuOpen && (
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
        {tab === 'personal' && !canHost && s.user && (
          // The shared Start hosting invitation (StartHostingCard, also the sheet behind Home's locked Hosting segment).
          // This card IS the invitation, so it turns organizer mode on right away and lands on Home > Hosting.
          <StartHostingCard canHost={false} busy={s.organizerModeBusy} style={{ margin: '16px 20px 0' }}
            onStart={() => startHosting({ land: 'home', confirmed: true })}
            testId="account-host-first-event" ctaTestId="account-host-first-event-start" />
        )}

        {/* 9. Sign out / Sign in, once, on Personal. Host and Admin end on a group: give them the same room above the dock. */}
        {!s.user && tab !== 'personal' ? <div aria-hidden style={{ height: 40 }} /> : s.user ? (
          <div onClick={logout} role="button" data-testid="account-sign-out" style={{ margin: '30px 20px 40px', height: 48, border: '1.5px solid var(--bb-alert)', borderRadius: 999, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, fontSize: 15, fontWeight: 600, color: 'var(--bb-alert)', cursor: 'pointer' }}><RowIcon kind="logout" size={18} />{T('Đăng xuất', 'Sign out')}</div>
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

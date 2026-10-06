import { useEffect, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { EVENTS } from '../data/events.js';
import { supabase } from '../lib/supabase.js';
import { organizerAvatarPublicUrl } from '../lib/mediaUrls.js';
import { paper, ink, rule, display, fieldGlass, fieldSolid, cardGlass, inkButton, alert } from '../theme.js';
import { AttachMenuIcon } from './Chat.jsx';
import { buildActionCenterItems, sortActionCenterItems } from '../lib/actionCenter.js';
import { PROFILE_PALETTE_COLORS } from '../lib/profileTheme.js';
import ActionCenter from './ActionCenter.jsx';
import AccountSearchResults from './AccountSearch.jsx';
import { takeSearchState, resetSearchState } from '../lib/accountSearch.js';
import { useSubmittedEvents, SubmittedEventsRow } from '../lib/submittedEvents.jsx';
import ProfileShareSheet, { ShareCardRow, profileShareLinks } from './sheets/ProfileShareSheet.jsx';
import { pickSoonest } from '../lib/countdown.js';
import { computeAdminModerationCount, computeHostActionCount, computeMyTicketsActionCount, computeMyRefundActionCount, computePersonalActionCount, formatBadgeCount } from '../lib/badges.js';

function organizerAvatarUrl(path, r2Ref, variant = 'thumb') {
  return organizerAvatarPublicUrl(path, r2Ref, variant);
}

// TASK 3C (2026-09-22 twenty-first follow-up) — no existing icon
// component/library covers this screen's semantics (only Chat.jsx's own
// attach-menu `AttachMenuIcon`, a different icon set for a different
// purpose), so per this ticket's own instruction this is a minimal local
// inline-SVG set: one stroke weight (1.8), one viewBox (24x24 at 18px),
// `ink` only — no new colors, no third-party icon set.
// Account extension (2026-09-27, Stage 3) — the one recognizable "Số liệu
// & báo cáo" entry point every visible tab gets, near its own top (not
// buried among the rest of that tab's rows). `scope` here is always the
// SAME string get_account_kpis (migration 097) expects — never re-derived
// inside Reports.jsx itself, so what the user tapped is exactly what gets
// fetched.
export function ReportsRow({ label, onClick, testId }) {
  return (
    <div
      onClick={onClick}
      data-testid={testId}
      style={{ ...fieldGlass({ margin: '18px 20px 0', padding: '15px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }) }}
    >
      <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}><RowIcon kind="checklist" />{label}</span>
      <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
    </div>
  );
}

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
    alertShield: <><path d="M12 3.2l6.8 2.8v5.7c0 4.7-3 7.4-6.8 8.7-3.8-1.3-6.8-4-6.8-8.7V6z" /><path d="M12 8.5v4.3M12 15.4v0" /></>,
  };
  return (
    <span
      aria-hidden
      style={{
        width: size, height: size, flex: 'none', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: accent ? `${accent}55` : 'transparent',
      }}
    >
      <svg {...common} style={{ opacity: 0.72 }}>{byKind[kind]}</svg>
    </span>
  );
}

// Account IA pass (2026-09-27) — a grouped entry card: icon + title +
// optional badge (an urgent pending-action COUNT, never buried inside the
// child screen only — see this ticket's own "preserve urgent pending-
// action visibility... at the group entry" instruction) + chevron, opening
// the shared AccountGroup child screen. `groupKey` doubles as the
// `ROW_ACCENT_COLORS` lookup AND the `data-testid`/route id both platforms
// share, so iOS/web can't drift on what a given group actually is.
function GroupCard({ groupKey, iconKind, label, badge, onClick, marginTop = 8 }) {
  const { T } = useBanBe();
  return (
    <div
      onClick={onClick}
      data-testid={`account-group-${groupKey}`}
      style={{ ...fieldGlass({ margin: `${marginTop}px 20px 0`, padding: '15px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }) }}
    >
      <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}>
        <RowIcon kind={iconKind} accent={ROW_ACCENT_COLORS[groupKey]} />
        {label}
      </span>
      <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        {/* TASK 5 (Account badges pass) — "99+" display, same cap
            convention BottomTabBar.jsx's own Notifications badge already
            uses, with the real count kept in aria-label/title (never lost,
            just not rendered) for accessibility/debugging. */}
        {!!badge && (
          <span
            role="status"
            aria-label={`${badge} ${T('mục mới', 'new item(s)')}`}
            title={String(badge)}
            style={{ fontSize: 11, fontWeight: 700, color: paper, background: alert, borderRadius: 999, padding: '2px 7px', minWidth: 18, textAlign: 'center' }}
            data-testid={`account-group-${groupKey}-badge`}
          >
            {badge > 99 ? '99+' : badge}
          </span>
        )}
        <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
      </span>
    </div>
  );
}

// Account IA reorder pass (2026-09-30 second) — a reusable section header,
// visually identical to the pre-existing "Tổ Chức" header style (11.5px,
// weight 600, `ink`) so every cluster in Personal/Host/Admin reads as one
// consistent convention instead of a one-off. Purely presentational — never
// changes a groupKey/testid/route, only adds a label above a cluster.
export function SectionHeader({ label, testId, marginTop = 22 }) {
  return (
    <div style={{ padding: `${marginTop}px 20px 0` }} data-testid={testId}>
      <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{label}</span>
    </div>
  );
}

export default function Account() {
  const {
    state, T, goHome, goEditName, goGoingList, goSavedList, openVerifications, goLogin, logout, canHost, toggleOrganizerMode, referralLink, shareReferral,
    openMyRefunds, openEditProfile,
    loadHomeStories, openStoryViewer, openStoryLibraryPicker, openStoryCameraPicker,
    loadPaymentBookings, loadMyRefunds, loadVerifications, loadRefundQueue, loadOrganizerHoldingSummary, loadPendingEventsCount,
    openPaymentDetails, goDashboard,
    loadMyOrgStats, setAccountTab, openPublicProfile, openReports, openAccountGroup, goSurveysHosting,
    loadMyOrganizerMemberships,
    loadMyEventCredits, loadMyConfirmedEventCredits, openPolicy,
    loadMyAdminInvite, respondToAdminInvite, loadAdminTeam,
  } = useBanBe();
  const s = state;
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
  // Host-side review tracking (iOS parity): submitted ('review') + needs-fix events.
  const submitted = useSubmittedEvents(!!s.user?.id && s.organizerMode);
  // Stage D (2026-09-26) — Cá nhân/Tổ chức top-level tabs. Both panes stay
  // mounted (display:none on the inactive one, not unmounted), each in its
  // OWN independently-scrolling container — switching tabs never resets
  // either one's scroll position, and never touches organizerMode/canHost
  // (that stays a wholly separate, explicit toggle inside the Tổ chức
  // pane itself, same as before).
  // iPhone fix pass (2026-09-26) — lifted into global state (s.accountTab)
  // so it survives this component remounting on any navigation away and
  // back (Preferences, the public-profile link below, etc.) — see the
  // state's own comment (BanBeContext.jsx) for the full root cause.
  const accountTab = s.accountTab;
  // Account extension (2026-09-27, Stage 1/2) — a role change (organizer
  // mode toggled off elsewhere, an admin demoted, an account switch) can
  // land this component with `accountTab` pointing at a tab that's no
  // longer in the list above; the toggle's own redirect (BanBeContext.jsx,
  // applyOrganizerMode) covers the direct toggle path, this is the general
  // safety net for every other path (mount, account switch, server resync).
  useEffect(() => {
    if (accountTab === 'host' && !s.organizerMode) setAccountTab('personal');
    else if (accountTab === 'admin' && s.accountType !== 'admin') setAccountTab('personal');
  }, [accountTab, s.organizerMode, s.accountType, setAccountTab]);
  // Task 1 (2026-09-21 real-device follow-up) — "Post Story" is now a real
  // two-option menu (Photo library / Camera), matching Chat.jsx's own
  // attach-menu convention (same icon set, same popup shape) instead of a
  // single link that only ever opened the library picker.
  // TASK 1 (dock "+" menu pass) — the actual file inputs/upload/preview
  // this opens now live in StoryCreateOverlay.jsx (mounted once, globally,
  // in App.jsx) — not here — so the dock "+" menu's own "Đăng story" row
  // can drive the exact same pipeline. This component only flips the
  // shared open* flags below.
  const [storyMenuOpen, setStoryMenuOpen] = useState(false);
  const [hostStoryMenuOpen, setHostStoryMenuOpen] = useState(false);

  // Stage 1 (2026-09-27 nav/discovery pass) — this card's own inline
  // avatar/name/intro editor is gone: the whole card is now a single tap
  // target that opens the REAL public organizer profile
  // (openPublicProfile), which already has its own "Chỉnh sửa" entry
  // (PublicProfile.jsx's org edit card) — editing one place, not two.

  // Task 3.3 (07-notifications.md) — loads active stories (mine + followed
  // hosts') so the ring below reflects real data even when Account is
  // opened directly, without having visited Home first this session.
  useEffect(() => { if (s.user) loadHomeStories(); }, [s.user, loadHomeStories]);
  // Organizer Team pass (2026-09-27, Stage 1) — this account's own pending
  // invites/accepted memberships, shown in the Cá nhân tab below.
  useEffect(() => { if (s.user?.id) loadMyOrganizerMemberships(); }, [s.user?.id, loadMyOrganizerMemberships]);
  // Admin Team pass (2026-10-02) — this account's own pending admin invite,
  // if any — reachable regardless of current role (the invitee isn't an
  // admin yet), same "Cá nhân" tab placement as the Team-invite banner.
  useEffect(() => { if (s.user?.id) loadMyAdminInvite(); }, [s.user?.id, loadMyAdminInvite]);
  // A manage-admins-capable admin's own badge/roster source — loaded here
  // (not only on opening the group) for the same reason pendingEventsCount
  // is loaded on mount below: an accurate badge, never a guessed/stale one.
  useEffect(() => { if (s.canManageAdmins) loadAdminTeam(); }, [s.canManageAdmins, loadAdminTeam]);
  // Organizer Team pass (2026-09-27, Stage 2) — this account's own pending
  // event-credit invites ("did I really help organize this event").
  useEffect(() => { if (s.user?.id) loadMyEventCredits(); }, [s.user?.id, loadMyEventCredits]);
  useEffect(() => { if (s.user?.id) loadMyConfirmedEventCredits(); }, [s.user?.id, loadMyConfirmedEventCredits]);
  // TASK A (2026-10-01 UX foundation pass) — Account is one of this
  // component's three placements; loads the same canonical sources Home
  // does so the Action Center reflects live server state here too, not a
  // stale snapshot from whenever Home last loaded them.
  useEffect(() => {
    if (!s.user?.id) return;
    loadPaymentBookings();
    loadMyRefunds();
    if (canHost) {
      loadVerifications();
      loadRefundQueue();
      loadOrganizerHoldingSummary();
    }
    // TASK 5 (Account badges pass) — same "load it here so the group-entry
    // badge is real, not stale" reasoning as verifications/refundQueue
    // above, gated on the actual admin role (RLS-backed), not a UI toggle.
    if (s.accountType === 'admin') loadPendingEventsCount();
  }, [s.user?.id, canHost, s.accountType, loadPaymentBookings, loadMyRefunds, loadVerifications, loadRefundQueue, loadOrganizerHoldingSummary, loadPendingEventsCount]);
  // Stage 1 — re-run whenever this account's organizer id becomes known
  // (session restore, or right after creating a first event — see
  // createSubmit's own comment) so the host card's real published-event
  // stats reflect the latest admin approval/cancellation, not a stale
  // snapshot from whenever it was last loaded.
  useEffect(() => { if (canHost && s.myOrganizerId) loadMyOrgStats(); }, [canHost, s.myOrganizerId, loadMyOrgStats]);
  const myHolding = pickSoonest(s.paymentBookings, 'holding', 'hold_expires_at');
  const myPendingVerification = (s.paymentBookings || [])
    .filter(b => b.payment_state === 'pending_verification')
    .sort((a, b) => new Date(a.proof_uploaded_at || 0) - new Date(b.proof_uploaded_at || 0))[0] || null;
  // Goer-side items belong to Personal; host-side items (payments to verify,
  // refunds you owe, guests holding seats) belong to the Host tab, the same
  // split the tab badges use. While the Host tab is hidden (organizerMode
  // off) they stay on Personal so owed money is never silently hidden.
  const goerActionItems = sortActionCenterItems(buildActionCenterItems({
    role: 'goer', T, now: s.now || Date.now(),
    myHolding, myPendingVerification, myRefunds: s.myRefunds || [],
    onOpenPayment: (bookingId) => openPaymentDetails(bookingId, 'profile'),
    onOpenMyRefunds: () => openMyRefunds('profile'),
  }));
  const hostActionItems = canHost ? sortActionCenterItems(buildActionCenterItems({
    role: 'host', T, now: s.now || Date.now(),
    verifications: s.verifications || [], refundQueue: s.refundQueue || [], orgHolding: s.organizerHoldingSummary,
    onOpenVerifications: () => openVerifications('profile'),
    onOpenRefundCenter: () => openVerifications('profile'),
    onOpenDashboard: goDashboard,
  })) : [];
  const actionItems = s.organizerMode ? goerActionItems : sortActionCenterItems([...goerActionItems, ...hostActionItems]);
  const myStoryGroup = s.myOrganizerIds.length ? s.homeStories.find(g => s.myOrganizerIds.includes(g.organizerId)) : null;
  const hasActiveStory = !!myStoryGroup;
  const storyUnviewed = hasActiveStory && !myStoryGroup.allViewed;

  // Once an event is over it belongs in "Completed", not "Going" — otherwise
  // it just sits there forever looking like something still upcoming.
  const goingCount = s.attending
    .map(k => EVENTS.find(e => e.key === k))
    .filter(e => e && e.endedHoursAgo == null).length;

  const profileName = s.user ? (s.user.name || (s.user.email ? s.user.email.split('@')[0] : T('Bạn', 'You'))) : T('Khách', 'Guest');
  // TASK B (2026-10-03 fix pass) — `isOrganizer` is the CURRENT UI
  // preference (organizerMode), never eligibility (canHost). Using
  // `canHost` here was the actual root cause of "organizer mode appears on
  // by default and cannot be turned off": `canHost` stays true forever
  // for any account that has ever really hosted (via `hasHosted`), so the
  // switch/host section never visually reflected a toggle-off at all —
  // see applyOrganizerMode's/toggleOrganizerMode's own doc comments for
  // the matching state-side half of this same bug. `canHost` is still
  // used on its own below (and by the Action Center above) wherever the
  // question is genuinely "is this account eligible," not "is host UI on
  // right now."
  const isOrganizer = s.organizerMode;
  const profileSub = s.accountType === 'admin' ? T('Quản trị viên', 'Admin') : isOrganizer ? T('Người tham gia ▪︎ Người tổ chức', 'Goer ▪︎ Host') : T('Người tham gia', 'Goer');

  return (
    <div style={{ position: 'relative', animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Account">
      {/* Fixed-header pass (2026-10-02) — title row + tabs used to just
          scroll away with the rest of the page (this screen has no sticky
          header at all before this pass, unlike iOS's own `accountHeader`/
          `accountTabsBar` siblings above `ScreenScaffold`). `position:
          sticky` on the single shared scroll container this screen already
          renders inside (App.jsx's Shell, see its own `overflowY: 'auto'`
          div) keeps both stationary while only the content below scrolls —
          no second scroll/tab system, same `accountTab` state and
          `setAccountTab` routing as before. */}
      <div style={{ position: 'sticky', top: 0, zIndex: 5, background: paper }} data-testid="account-fixed-header">
        <div style={{ padding: '66px 20px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
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
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
              <img src="/banbe-wordmark.png" alt="banbe" crossOrigin="anonymous" style={{ width: 96, height: 'auto', display: 'block' }} />
              <span style={{ ...display(27), lineHeight: 1.1 }}>{T('Tài khoản', 'Account')}</span>
            </div>
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

        {/* Stage D — Cá nhân/Tổ chức top-level tabs. Purely a display switch
            below (both panes' own scroll containers keep their scrollTop
            whichever is hidden) — never calls toggleOrganizerMode or any
            hosting-mode side effect by itself. */}
        <div style={{ display: searchOpen ? 'none' : 'flex', gap: 6, padding: '18px 20px 14px' }} data-testid="account-tabs">
        {[
          // Same source as the "Tickets & Bookings" group card badge below.
          { key: 'personal', label: T('Cá Nhân', 'Personal'), badge: computePersonalActionCount(s) },
          // Account extension (2026-09-27, Stage 1) — "organizer mode OFF
          // means host UI is OFF": Tổ chức only shows while `organizerMode`
          // (the CURRENT toggle) is actually on, never `canHost`
          // (eligibility) — a never-hosted account reaches hosting via the
          // toggle row moved into Cá nhân below, not this tab.
          // FIX PASS (2026-09-30) — badge propagated from the SAME source
          // as this tab's own group card ("Vận hành & thanh toán tổ chức"
          // below): verifications + refundQueue, never a second count.
          ...(isOrganizer ? [{ key: 'host', label: T('Tổ Chức', 'Host'), badge: computeHostActionCount(s) + submitted.total }] : []),
          // Stage 2 — Admin depends only on a server-confirmed role
          // (`accountType`, set exclusively by syncUser()'s own read of
          // `profiles.role`/`set_organizer_mode`'s return value — never
          // client-writable to "admin" by this toggle), never organizerMode.
          // Badge propagated from the SAME source as the "Duyệt & kiểm
          // duyệt" group card / "Sự kiện chờ duyệt" row below —
          // pendingEventsCount, never a second, independently-derived count.
          ...(s.accountType === 'admin' ? [{ key: 'admin', label: T('Quản Trị', 'Admin'), badge: computeAdminModerationCount(s) }] : []),
        ].map(tab => (
          <span
            key={tab.key}
            onClick={() => setAccountTab(tab.key)}
            data-testid={`account-tab-${tab.key}`}
            style={{
              fontSize: 13, fontWeight: 600, padding: '9px 16px', borderRadius: 999, cursor: 'pointer',
              ...(accountTab === tab.key
                ? { background: 'rgba(var(--bb-fg-rgb), 0.92)', color: paper, border: '1px solid transparent', boxShadow: '0 2px 6px rgba(27,25,22,0.18)' }
                : { background: 'linear-gradient(180deg, rgba(255,255,255,0.35), rgba(255,255,255,0.05)), rgba(var(--bb-fg-rgb), 0.06)', color: ink, border: '1px solid rgba(var(--bb-fg-rgb), 0.14)', backdropFilter: 'blur(14px) saturate(1.1)', WebkitBackdropFilter: 'blur(14px) saturate(1.1)', boxShadow: '0 2px 8px rgba(27,25,22,0.08), inset 0 1px 0 rgba(255,255,255,0.5)' }),
              display: 'flex', alignItems: 'center', gap: 6,
            }}
          >
            {tab.label}
            {!!tab.badge && (
              <span
                data-testid={`account-tab-${tab.key}-badge`}
                role="status"
                aria-label={T(`${tab.badge} mục mới`, `${tab.badge} new item(s)`)}
                title={String(tab.badge)}
                style={{
                  fontSize: 10, fontWeight: 700, minWidth: 16, height: 16, padding: '0 4px', lineHeight: '16px',
                  textAlign: 'center', borderRadius: 999,
                  background: accountTab === tab.key ? paper : alert,
                  color: accountTab === tab.key ? ink : '#fff',
                }}
              >
                {formatBadgeCount(tab.badge)}
              </span>
            )}
          </span>
        ))}
        </div>
      </div>

      {/* iPhone fix pass (2026-09-26) — this personal identity card (and
          its story ring/"Đổi tên") used to sit ABOVE both tab panes, so it
          rendered on the Tổ chức tab too, right on top of that tab's own
          organizer profile card below — two profile cards for one screen.
          Moved inside the SAME Cá nhân pane wrapper as the rest of this
          tab's content (opened here, closed at its usual spot further
          down) — the Tổ chức tab gets its own separate, organizer-only
          card instead. */}
      {searchOpen && <div style={{ height: 8 }} />}
      {searchOpen && <AccountSearchResults query={searchQuery} />}

      <div data-testid="account-tab-panel-personal" style={{ display: !searchOpen && accountTab === 'personal' ? 'block' : 'none' }}>
      {/* Account IA pass (2026-09-27) — the identity card is now the FIRST
          thing under the tab pills (was: reports row, then Team invites/
          memberships/event-credit sections, THEN this card) — Going/Saved
          immediately follow it, per this ticket's own ordering ask.
          Team invites/memberships and event credits (pending + confirmed)
          moved into the "team"/"activity" AccountGroup child screens below
          — never duplicated here, only their own pending COUNTS surface at
          the group-entry level now (GroupCard's `badge`).
          TASK D (2026-10-01 UX foundation pass) — the header is now a
          tappable rounded profile card (editorial style: soft gradient
          wash from the account's own chosen palette, real avatar or a
          palette-tinted monogram, handle line). The story ring/post-story
          menu keep their own existing nested tap targets unchanged — a
          separate small "Chỉnh sửa" affordance (not the whole card) opens
          EditProfile, so it can't conflict with those. */}
      <div
        style={{
          ...cardGlass({ margin: '22px 20px 0', padding: '18px 16px', display: 'flex', gap: 14, alignItems: 'center' }),
          background: `linear-gradient(165deg, ${PROFILE_PALETTE_COLORS[s.user?.profileTheme] || PROFILE_PALETTE_COLORS.default}55, transparent 70%)`,
        }}
        data-testid="account-profile-card"
      >
        {/* Task 3.3 (07-notifications.md) — story ring: a bright outline
            while this host has an active, not-fully-viewed story; a
            subdued one once every active story has been viewed; no ring
            at all when there's no active story. Tapping the avatar opens
            the viewer only when there's something to view. */}
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
              <span onClick={goEditName} style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 11.5, color: ink, opacity: 0.65, cursor: 'pointer', flex: 'none' }}>
                <RowIcon kind="pencil" size={13} />{T('Đổi tên', 'Rename')}
              </span>
            )}
          </div>
          {s.user?.handle && <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>@{s.user.handle}</span>}
          <span style={{ fontSize: 11, letterSpacing: '0.06em', color: ink }}>{profileSub}</span>
          {/* Task 3.2 — story creation entry point, hosts only. */}
          {isOrganizer && (
            <div style={{ position: 'relative' }}>
              <span onClick={() => setStoryMenuOpen(v => !v)} data-testid="account-post-story" style={{ fontSize: 11.5, color: ink, opacity: 0.65, cursor: 'pointer' }}>
                {T('▪︎ Đăng story', '▪︎ Post story')}
              </span>
              {storyMenuOpen && (
                <div onClick={() => setStoryMenuOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 35 }}>
                  <div
                    onClick={(e) => e.stopPropagation()}
                    style={{ ...cardGlass({ position: 'absolute', top: 20, left: 0, minWidth: 200 }), padding: 6, display: 'flex', flexDirection: 'column' }}
                  >
                    <div
                      onClick={() => { setStoryMenuOpen(false); openStoryLibraryPicker(); }}
                      data-testid="account-post-story-library"
                      style={{ padding: '12px 14px', fontSize: 13.5, color: ink, cursor: 'pointer', borderRadius: 8, display: 'flex', alignItems: 'center', gap: 10 }}
                    >
                      <AttachMenuIcon name="library" />
                      {T('Thư Viện Ảnh', 'Photo Library')}
                    </div>
                    <div
                      onClick={() => { setStoryMenuOpen(false); openStoryCameraPicker(); }}
                      data-testid="account-post-story-camera"
                      style={{ padding: '12px 14px', fontSize: 13.5, color: ink, cursor: 'pointer', borderRadius: 8, display: 'flex', alignItems: 'center', gap: 10 }}
                    >
                      <AttachMenuIcon name="camera" />
                      {T('Camera', 'Camera')}
                    </div>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
        {/* iPhone fix pass (2026-09-26) — this used to open EditProfile
            directly; it now opens the same public profile page anyone else
            sees when visiting this account's own /u/<handle> (isOwnProfile
            there is what actually surfaces its own "Chỉnh sửa hồ sơ" row)
            — editing is one tap further in, not the arrow's own
            destination. */}
        {s.user && (
          <span
            onClick={() => s.user?.handle && openPublicProfile(s.user.handle, 'profile')}
            data-testid="account-edit-profile"
            style={{ flex: 'none', fontSize: 20, color: ink, opacity: 0.55, cursor: 'pointer', alignSelf: 'center' }}>
            ›
          </span>
        )}
      </div>

      {s.user?.handle && (
        <ShareCardRow onClick={() => setShareCardFor('member')} testId="account-share-card-personal" />
      )}

      {/* Account IA reorder pass (2026-09-30 second) — target order per
          17-ux-foundation-release.md's dated section: this cluster answers
          "what needs my attention / where are my tickets and payments"
          first (a product hypothesis on common task frequency — ticket/
          booking access, then payments, then settings, then hosting, then
          admin — NOT measured banbe usage data, none exists to cite). */}
      <SectionHeader label={T('Hoạt Động Của Bạn', 'Your Activity')} testId="account-section-activity" />

      <ActionCenter items={actionItems} onSeeAll={() => openVerifications('profile')} T={T} />

      {/* Account IA reorg (2026-09-30) — relabeled "Vé & Hoạt Động"/"Tickets
          & Activity" -> "Vé & Đặt Chỗ"/"Tickets & Bookings"; `groupKey`
          stays "activity" (route/testid unchanged, only the visible label
          and its content changed — see AccountGroup.jsx). Badge is now the
          real count of this account's own holding/awaiting-payment/
          pending-verification bookings (computeMyTicketsActionCount,
          reading the SAME `paymentBookings` array already loaded above for
          the Action Center — no new query). */}
      <GroupCard
        groupKey="activity" iconKind="calendarCheck"
        label={T('Vé & Đặt Chỗ', 'Tickets & Bookings')}
        badge={computeMyTicketsActionCount(s)}
        onClick={() => openAccountGroup('activity')}
        marginTop={14}
      />

      <div style={{ display: 'flex', gap: 10, padding: '14px 20px 0' }}>
        {/* data-attending-raw-count is the unfiltered s.attending.length — not
            shown to users (goingCount below is what actually renders, and is
            deliberately narrowed to the static demo catalogue + not-yet-ended
            events). Exists purely so a test can observe the real client-side
            "going" state for a booking outside that catalogue, which no
            visible UI element can ever reflect otherwise. */}
        <div onClick={goGoingList} data-testid="account-going-card" data-attending-raw-count={s.attending.length} style={{ ...cardGlass({ flex: 1, padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 3, cursor: 'pointer' }) }}>
          <RowIcon kind="calendarCheck" size={18} />
          <span style={{ ...display(24) }}>{goingCount}</span>
          <span style={{ fontSize: 11, color: ink }}>{T('Đang tham gia', 'Going')}</span>
        </div>
        {/* Account IA reorder pass — relabeled "Đã lưu"/"Saved" (generic) ->
            "Sự Kiện Đã Lưu"/"Saved Events" per this pass's own instruction;
            destination (goSavedList) and testid unchanged. */}
        <div onClick={goSavedList} data-testid="account-saved-card" style={{ ...cardGlass({ flex: 1, padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 3, cursor: 'pointer' }) }}>
          <RowIcon kind="document" size={18} />
          <span style={{ ...display(24) }}>{(s.favorites || []).length}</span>
          <span style={{ fontSize: 11, color: ink }}>{T('Sự Kiện Đã Lưu', 'Saved Events')}</span>
        </div>
      </div>

      <GroupCard
        groupKey="payments" iconKind="banknote"
        label={T('Thanh Toán & Giấy Tờ', 'Payments & Documents')}
        badge={computeMyRefundActionCount(s)}
        onClick={() => openAccountGroup('payments')}
        marginTop={14}
      />

      <ReportsRow label={T('Số Liệu & Báo Cáo', 'Metrics & Reports')} testId="account-reports-personal" onClick={() => openReports('personal', null, 'profile')} />

      {referralLink && (
        <div style={{ ...cardGlass({ margin: '20px 20px 0', padding: '16px 18px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 14, cursor: 'pointer' }) }} onClick={shareReferral}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, minWidth: 0 }}>
          <RowIcon kind="users" />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
            <span style={{ ...display(16) }}>{T('Mời bạn bè', 'Invite friends')}</span>
            <span style={{ fontSize: 11.5, lineHeight: 1.45, color: ink, opacity: 0.7 }}>
              {s.referralShared
                ? T('Đã sao chép link mời ▪︎ gửi cho bạn bè thôi!', 'Invite link copied ▪︎ send it to a friend!')
                : T('Rủ bạn bè cùng tham gia banbe qua link riêng của bạn.', 'Bring friends onto banbe with your own link.')}
            </span>
          </div>
          </div>
          <span style={{ flex: 'none', fontSize: 12, fontWeight: 600, color: paper, background: ink, borderRadius: 999, padding: '9px 16px' }}>{T('Chia sẻ', 'Share')}</span>
        </div>
      )}

      {/* Account IA reorder pass (2026-09-30 second) — second cluster:
          account-level settings, reached after the actionable/ticket stuff
          above. `team` GroupCard used to always render here — REMOVED
          wholesale (not simply moved into Hosting): a user can receive a
          co-organizer invite before ever turning Hosting Mode on, and
          hiding the ONLY entry point to that invite behind the Hosting
          toggle would strand them with an invisible, un-actionable invite.
          Instead: (a) the Host tab now has its own entry point into the
          SAME `groupKey: 'team'` screen (see account-tab-panel-host below —
          mirrors the existing "two doors, one destination" pattern already
          used for the Payment Disputes row), and (b) a lightweight
          conditional row right below surfaces the SAME destination here
          ONLY when there's a real pending invite AND Hosting is currently
          off (so it's never invisible, but a participant who's never
          touched hosting doesn't see an empty organizer-team card by
          default). Gating is mutually exclusive with the Host-tab card
          (that card only renders while organizerMode is on — see
          `useEffect` above that forces accountTab off 'host' whenever
          organizerMode is false), so the two entry points are never both
          visible at once and neither ever double-counts. */}
      <SectionHeader label={T('Tài Khoản & Cài Đặt', 'Account & Settings')} testId="account-section-settings" />

      <div
        onClick={() => s.user?.handle && openPublicProfile(s.user.handle, 'profile')}
        data-testid="account-personal-profile"
        style={{ ...fieldGlass({ margin: '14px 20px 0', padding: '15px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }) }}
      >
        <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}>
          <RowIcon kind="pencil" />{T('Hồ Sơ Cá Nhân', 'Personal Profile')}
        </span>
        <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
      </div>

      {/* Account IA reorg (2026-09-30) — relabeled "Tùy Chỉnh"/"Preferences"
          -> "Cài Đặt"/"Settings" (reads more accurately for its actual
          contents, app preferences + security). `groupKey`/testid/route
          unchanged (still "preferences" — see AccountGroup.jsx's own
          GROUP_META, only its display string changed). */}
      <GroupCard
        groupKey="preferences" iconKind="sliders"
        label={T('Cài Đặt', 'Settings')}
        onClick={() => openAccountGroup('preferences')}
      />
      {/* Account IA reorg (2026-09-30) — "Help & Legal". No dedicated
          in-app Help/Support screen exists anywhere in this codebase
          (searched for one) — only the real, already-wired Policy screen
          (`openPolicy`/`Policy.jsx`, the same bilingual policy text used at
          signup consent and reachable read-only here, `backFromPolicy`
          returning to whichever screen opened it). This row is therefore
          the Legal half only; the "Help" half has no real destination to
          point to yet (a genuine gap, not fabricated here — flagged in
          09-auth-onboarding.md's dated fix-pass section). */}
      <div
        onClick={openPolicy}
        data-testid="account-help-legal"
        style={{ ...fieldGlass({ margin: '8px 20px 0', padding: '15px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }) }}
      >
        <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}>
          <RowIcon kind="shield" />{T('Trợ Giúp & Pháp Lý', 'Help & Legal')}
        </span>
        <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
      </div>

      {/* Account IA reorder pass — the lightweight conditional invite row
          described above. Same badge SOURCE as the Host-tab `team` card
          (myOrganizerInvites.length [+ myEventCredits.length]) — never a
          second independently-derived count, and never rendered at the
          same time as that card (mutually exclusive on `isOrganizer`). */}
      {!isOrganizer && s.myOrganizerInvites.length > 0 && (
        <div
          onClick={() => openAccountGroup('team')}
          data-testid="account-team-invite-banner"
          style={{ ...fieldGlass({ margin: '8px 20px 0', padding: '15px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }) }}
        >
          <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}>
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
            <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
          </span>
        </div>
      )}

      {/* Admin Team pass (2026-10-02) — same banner shape as the Team
          invite above, reachable regardless of current role (the invitee
          isn't an admin yet). */}
      {s.myAdminInvite && (
        <div
          onClick={() => openAccountGroup('adminTeam')}
          data-testid="account-admin-invite-banner"
          style={{ ...fieldGlass({ margin: '8px 20px 0', padding: '15px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }) }}
        >
          <span style={{ display: 'flex', alignItems: 'center', gap: 12, fontSize: 14, color: ink }}>
            <RowIcon kind="alertShield" accent={ROW_ACCENT_COLORS.adminReview} />{T('Bạn có lời mời quản trị', 'You have an admin invite')}
          </span>
          <span style={{ fontSize: 15, color: ink, lineHeight: 1 }}>›</span>
        </div>
      )}

      {/* Account extension (2026-09-27, Stage 1) — "Organizer mode OFF
          means host UI is OFF": the whole Tổ chức tab disappears while
          this is off, so the ON/OFF control itself (and any actionable
          host duty) can't live there any more — moved here, into Cá nhân,
          which is always reachable. The Tổ chức tab (when it does show)
          now holds only the organizer identity card + its management
          entry point (org-profile-card, above/unchanged). */}
      <div style={{ padding: '22px 20px 0' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Tổ Chức', 'Hosting')}</span>
        {/* TASK 2 (2026-10-05 fix pass) — `organizerModeBusy` (real guard
            in toggleOrganizerMode/applyOrganizerMode, see BanBeContext.jsx)
            mirrored here as `.opacity`/no-op click so a second tap while
            one request is already in flight visibly does nothing instead
            of silently queuing a race. */}
        <div
          onClick={s.organizerModeBusy ? undefined : toggleOrganizerMode}
          data-testid="organizer-mode-toggle"
          aria-disabled={s.organizerModeBusy}
          style={{ ...fieldGlass({ marginTop: 10, padding: '15px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: s.organizerModeBusy ? 'default' : 'pointer', opacity: s.organizerModeBusy ? 0.55 : 1 }) }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, minWidth: 0, paddingRight: 12 }}>
            <RowIcon kind="switch" />
            <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
              <span style={{ fontSize: 14, color: ink }}>{T('Chế độ tổ chức', 'Organizer mode')}</span>
              <span style={{ fontSize: 11.5, lineHeight: 1.45, color: ink, opacity: 0.7 }}>{T('Bật để tạo và quản lý sự kiện. Tắt lúc nào cũng được.', 'Turn on to create and manage events. Turn it off any time.')}</span>
            </div>
          </div>
          <span aria-hidden style={{ flex: 'none', width: 44, height: 26, borderRadius: 13, padding: 3, background: isOrganizer ? ink : 'rgba(27,25,22,0.18)', transition: 'background .15s' }}>
            <span style={{ display: 'block', width: 20, height: 20, borderRadius: '50%', background: paper, transform: isOrganizer ? 'translateX(18px)' : 'translateX(0)', transition: 'transform .15s' }} />
          </span>
        </div>
        {s.organizerModeError && <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '10px 0 0' }}>{s.organizerModeError}</p>}
        {/* Account regression fix pass (2026-09-27), Item 1 — the actual
            host-management rows (verifications/payout/invoices/receipts)
            used to live here too, so Cá nhân showed the full old
            "Tổ chức" management menu underneath a toggle that was
            supposed to be the ONLY thing here. They moved to the Tổ chức
            tab (below, in account-tab-panel-host) — reachable ONLY while
            organizerMode is actually on, matching that tab's own
            visibility. Any genuinely URGENT outstanding duty (a pending
            verification, an overdue refund) still surfaces here via the
            ActionCenter above, which is gated on `canHost` (eligibility),
            not `organizerMode` — a neutral actionable notice, never the
            full menu. */}
        {/* No separate "Xem trang tổ chức của bạn" card here — org-profile-card
            (Tổ chức tab, once organizerMode is on) is the single entry into
            that management page now. This onboarding pitch is for an
            account that has never hosted (`canHost` false always implies
            `organizerMode` false too, so it can only ever show in the true
            "never hosted" case). */}
        {!canHost && (
          <div style={{ ...cardGlass({ marginTop: 10, padding: '18px 16px', display: 'flex', flexDirection: 'column', gap: 10 }) }}>
            <span style={{ ...display(19, { lineHeight: 1.3 }) }}>{T('Tổ chức sự kiện đầu tiên', 'Host your first event')}</span>
            <p style={{ fontSize: 12.5, lineHeight: 1.5, color: ink, margin: 0 }}>
              {T('Miễn phí hoàn toàn khi banbe còn mới: không phí đăng, không phí giao dịch. Tạo sự kiện đầu tiên để mở trang tổ chức.', 'Completely free while banbe is new: no listing or transaction fees. Create your first event to unlock your host page.')}
            </p>
            <div onClick={toggleOrganizerMode} style={{ ...inkButton({ marginTop: 4, borderRadius: 18, padding: 14, fontSize: 14 }) }}>{T('Bắt đầu tổ chức ▪︎ miễn phí', 'Start hosting ▪︎ free')}</div>
          </div>
        )}
      </div>

      {s.user ? (
        <div onClick={logout} style={{ padding: '24px 20px 40px', display: 'flex', alignItems: 'center', gap: 12, fontSize: 13, color: ink, cursor: 'pointer' }}><RowIcon kind="logout" size={18} />{T('Đăng xuất', 'Sign out')}</div>
      ) : (
        <div onClick={goLogin} style={{ padding: '24px 20px 40px', display: 'flex', alignItems: 'center', gap: 12, fontSize: 12.5, lineHeight: 1.5, color: ink, cursor: 'pointer' }}><RowIcon kind="login" size={18} />{T('Đăng nhập để lưu sự kiện và nhắn tin', 'Sign in to save events and message hosts')}</div>
      )}
      </div>

      <div data-testid="account-tab-panel-host" style={{ display: !searchOpen && accountTab === 'host' ? 'block' : 'none' }}>
      {/* Account IA pass (2026-09-27) — identity card FIRST under the tab
          pills (was: reports row, then this card) — matches Cá nhân's own
          reordering. */}
      {/* Host tab's OWN rounded profile card (Stage D) — organizer avatar/
          name/introduction, stored on `organizers` (migration 090), never
          profiles.display_name. Only shown once this account has ever
          hosted; a never-hosted account instead sees the same "Host your
          first event" pitch further down (unchanged from before). */}
      {canHost && s.myOrganizerId && (
        <div
          onClick={() => goDashboard('profile')}
          style={{
            ...cardGlass({ margin: '22px 20px 0', padding: '18px 16px', display: 'flex', flexDirection: 'column', gap: 8, cursor: 'pointer' }),
            // Account regression fix pass (2026-09-27), Item 4 — same
            // visual quality as the personal card's own gradient wash
            // (account-profile-card, above), but a deliberately DIFFERENT
            // palette (moss, never the account's own chosen `profileTheme`)
            // so this always reads as a distinct organization identity,
            // never a second copy of the personal card.
            background: `linear-gradient(165deg, ${PROFILE_PALETTE_COLORS.moss}66, transparent 70%)`,
          }}
          data-testid="org-profile-card"
        >
          <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
            {/* Real avatar only — a rounded-SQUARE frame (never the
                personal card's circular one), so the two are never
                visually confusable at a glance even before reading any
                text. A missing avatar falls back to a real monogram
                (organizer name's own first letter), never a broken
                image/placeholder icon. */}
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
              {/* Stage 1 — same published-events-only rule as
                  get_public_profile's event_count/hosting_since_year
                  (migration 091, loadMyOrgStats above), so this card and
                  the public page never disagree. null = not loaded yet
                  (shows nothing rather than a flash of "0 sự kiện") — never
                  a fabricated count either way. */}
              {s.myOrgPublishedEventCount !== null && (
                <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>
                  {s.myOrgHostingSinceYear
                    ? T(`Tổ chức từ ${s.myOrgHostingSinceYear} ▪︎ ${s.myOrgPublishedEventCount} sự kiện`, `Hosting since ${s.myOrgHostingSinceYear} ▪︎ ${s.myOrgPublishedEventCount} events`)
                    : T('Chưa có sự kiện công khai nào', 'No published events yet')}
                </span>
              )}
            </div>
            {/* Profile-nav fix pass (2026-09-27) — the whole card is now
                the single tap target, opening the real organizer
                management page (Dashboard.jsx, real upcoming/past events +
                check-in), NOT the public profile — visiting the public
                page is Dashboard's own "Hồ sơ công khai của tổ chức"
                button. This chevron is purely visual, matching the
                personal profile card's own right-side "›" — an
                accessible, large tap target (the whole card, not just
                this glyph). */}
            <span
              aria-hidden
              data-testid="org-profile-view-public"
              style={{ flex: 'none', fontSize: 20, color: ink, opacity: 0.55 }}
            >›</span>
          </div>
          {s.orgRegDesc && (
            <p style={{ fontSize: 12.5, lineHeight: 1.5, color: ink, opacity: 0.85, margin: 0 }}>{s.orgRegDesc}</p>
          )}
        </div>
      )}

      {/* Account regression fix pass (2026-09-27), Item 1 — host-management
          rows, only ever reachable while organizerMode is on (this whole
          tab's own visibility rule). Account IA pass (2026-09-27) — now
          ONE grouped entry card (was an inline 4-row list) — same exact
          child actions/testids, moved into the shared AccountGroup screen.
          Badge = real outstanding host duties (verifications + refund
          queue), never invented. */}
      {/* Host tab "Post a story" row — story posting is a host action (matches
          iOS's postStoryCTA); same two pickers as the personal card's menu. */}
      {isOrganizer && (
        <div style={{ position: 'relative', margin: '14px 20px 0' }}>
          <div
            onClick={() => setHostStoryMenuOpen(v => !v)}
            data-testid="account-host-post-story"
            style={{ ...cardGlass({ padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer' }) }}
          >
            <span aria-hidden style={{ flex: 'none', width: 24, height: 24, borderRadius: '50%', background: ink, color: paper, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18, lineHeight: 1 }}>+</span>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 2, flex: 1, minWidth: 0 }}>
              <span style={{ fontSize: 15, fontWeight: 600, color: ink }}>{T('Đăng story', 'Post a story')}</span>
              <span style={{ fontSize: 11.5, color: ink, opacity: 0.65 }}>{T('Thêm chữ và liên kết, sửa hoặc xóa sau khi đăng', 'Add text and a link; edit or delete after posting')}</span>
            </div>
            <span aria-hidden style={{ fontSize: 12, color: ink, opacity: 0.5 }}>⌃⌄</span>
          </div>
          {hostStoryMenuOpen && (
            <div onClick={() => setHostStoryMenuOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 35 }}>
              <div
                onClick={(e) => e.stopPropagation()}
                style={{ ...cardGlass({ position: 'absolute', right: 20, top: '50%', minWidth: 200 }), padding: 6, display: 'flex', flexDirection: 'column' }}
              >
                <div
                  onClick={() => { setHostStoryMenuOpen(false); openStoryLibraryPicker(); }}
                  style={{ padding: '12px 14px', fontSize: 13.5, color: ink, cursor: 'pointer', borderRadius: 8, display: 'flex', alignItems: 'center', gap: 10 }}
                >
                  <AttachMenuIcon name="library" />{T('Thư Viện Ảnh', 'Photo Library')}
                </div>
                <div
                  onClick={() => { setHostStoryMenuOpen(false); openStoryCameraPicker(); }}
                  style={{ padding: '12px 14px', fontSize: 13.5, color: ink, cursor: 'pointer', borderRadius: 8, display: 'flex', alignItems: 'center', gap: 10 }}
                >
                  <AttachMenuIcon name="camera" />{T('Camera', 'Camera')}
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {canHost && s.myOrganizerId && (
        <ShareCardRow host onClick={() => setShareCardFor('host')} testId="account-share-card-host" />
      )}

      <ActionCenter items={hostActionItems} onSeeAll={() => openVerifications('profile')} T={T} />

      {canHost && (
        <GroupCard
          groupKey="hostOps" iconKind="checklist"
          label={T('Vận Hành & Thanh Toán Tổ Chức', 'Event Operations & Payments')}
          // Stale-badge fix pass — was a raw `refundQueue.length`, bypassing
          // `computeHostActionCount` entirely (the one place this app
          // already decides what's actually host-actionable) — the exact
          // same staleness bug as every other raw-count call site this pass
          // fixes, just one `badges.js` never caught before.
          badge={computeHostActionCount(s)}
          onClick={() => openAccountGroup('hostOps')}
          marginTop={22}
        />
      )}

      {/* Account IA reorder pass (2026-09-30 second) — the Host tab's own
          entry point into the SAME `groupKey: 'team'` screen the personal
          tab's conditional invite row also opens (see that row's own
          comment for the full "two doors, one destination" reasoning —
          mirrors the Payment Disputes row's existing pattern). Gated
          `canHost`, matching `hostOps` above (the rest of this tab's own
          convention) — a genuine co-organizer invite/team membership is
          eligibility-scoped content, not preference-scoped. */}
      {canHost && <SubmittedEventsRow submitted={submitted} />}

      {canHost && (
        <GroupCard
          groupKey="team" iconKind="users"
          label={T('Hồ Sơ & Team Tổ Chức', 'Organizer Profile & Team')}
          badge={s.myOrganizerInvites.length + s.myEventCredits.length}
          onClick={() => openAccountGroup('team')}
          marginTop={8}
        />
      )}

      {/* Interest surveys (Slice B) — a standalone screen (SurveysHosting),
          not a case inside the shared AccountGroup switch, since it has
          its own tabs (Active/Closed/Suggested Drafts) and a create form,
          not a simple flat list. Badge is honestly 0 for now — the
          unseen/actionable candidate count this badge is meant to carry
          (Slice C, candidate generation) is not implemented yet; see
          .claude/notes/21-invite-only-events-and-surveys.md. */}
      {canHost && (
        <GroupCard
          groupKey="surveys" iconKind="checklist"
          label={T('Khảo Sát & Ý Tưởng Sự Kiện', 'Surveys & Event Ideas')}
          badge={0}
          onClick={goSurveysHosting}
          marginTop={8}
        />
      )}

      {/* Account IA reorder pass — actionable content first: Reports moved
          AFTER the group cards above (was: identity card, Reports, then
          the group card) per this ticket's explicit instruction. Same
          destination/testid, only position changed. */}
      {s.myOrganizerId && (
        <ReportsRow label={T('Số Liệu & Báo Cáo', 'Metrics & Reports')} testId="account-reports-host" onClick={() => openReports('host', s.myOrganizerId, 'profile')} />
      )}

      <div style={{ height: 24 }} />
      </div>

      {/* Stage 2 — Admin is its own top-level tab now, independent of
          organizerMode: these two rows used to sit inside the Tổ chức
          pane, so an admin who never turned organizer mode on (or turned
          it off) lost them entirely once that tab started hiding itself
          for Stage 1. Same actions, same RPC/RLS-enforced screens
          (openDisputes/openAdminEvents) — moved, not cloned. Still JS-
          gated on `s.accountType === 'admin'` (not just the CSS
          display:none the personal/host panes use), so these two rows
          never even reach the DOM for a non-admin — a real, if secondary,
          reason on top of RLS/RPC enforcement, and what an existing test
          (payment-state-machine.spec.js) already asserts by element count. */}
      {s.accountType === 'admin' && (
        <div data-testid="account-tab-panel-admin" style={{ display: !searchOpen && accountTab === 'admin' ? 'block' : 'none' }}>
          {/* Account IA reorder pass (2026-09-30 second) — this tab had no
              header at all ("nothing to group"); now there is: the header
              plus a real order swap justify it. Actionable review/disputes
              FIRST, administrative reports AFTER — the explicit instruction
              for this tab, a real reorder from the previous code, not just
              a label change. */}
          <SectionHeader label={T('Quản Trị', 'Administration')} testId="account-section-admin" marginTop={22} />
          {/* Account IA pass (2026-09-27) — same "Payment disputes"/
              "Pending events" actions, now one grouped entry card. No
              identity card exists for Admin (there never was one) — this
              tab has nothing else to reorder ahead of. */}
          <GroupCard
            groupKey="adminReview" iconKind="alertShield"
            label={T('Duyệt & Kiểm Duyệt', 'Review & Moderation')}
            badge={s.pendingEventsCount}
            onClick={() => openAccountGroup('adminReview')}
            marginTop={14}
          />
          {/* Admin Team pass (2026-10-02) — reachable to every admin (so a
              permission-less admin can at least see WHO the team is / why
              they can't manage it — AccountGroup's own gate decides what
              renders inside), badge only ever counts real, still-pending
              invites (adminInvites is only populated for a canManageAdmins
              account in the first place — RLS denies the read otherwise,
              so a non-manager's badge is honestly 0/undefined, never a
              guessed number). */}
          <GroupCard
            groupKey="adminTeam" iconKind="users"
            label={T('Đội Ngũ Quản Trị', 'Admin Team')}
            badge={s.adminInvites.filter(i => i.status === 'pending').length}
            onClick={() => openAccountGroup('adminTeam')}
            marginTop={10}
          />
          <ReportsRow label={T('Số Liệu & Báo Cáo', 'Metrics & Reports')} testId="account-reports-admin" onClick={() => openReports('admin', null, 'profile')} />
          <div style={{ height: 24 }} />
        </div>
      )}
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
      />
    </div>
  );
}

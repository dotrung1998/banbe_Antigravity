import { useEffect, useState } from 'react';
import QRCode from 'qrcode';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, ink2, display, cardGlass, surface2, clay, clayBg, attn, divider, RADIUS, SPACE } from '../theme.js';
import { EVENTS } from '../data/events.js';
import { roleLabel, dedupeChips, profileStats, upcomingEvents, CARD_TINT, CARD_GLOW } from '../lib/profileCard.js';
import { PROFILE_PALETTE_COLORS } from '../lib/profileTheme.js';
import { KeychainFrame, useProfileKeychain } from '../components/KeychainCharm.jsx';
import { keychainFocus } from '../lib/keychain.js';
import { APP_STORE_URL } from '../lib/appStore.js';
import ProfileShareSheet, { profileShareLinks } from './sheets/ProfileShareSheet.jsx';
import { LongIntroPreview, SocialLinksRow } from './LongIntro.jsx';

// TASK D — "app not installed" fallback (rule D3): a shared /u/<handle>
// link that doesn't open the native app (no universal-link verification,
// or simply opened in a desktop browser where there's no app to open)
// lands here instead — this banner is that fallback's own visible CTA,
// not a silent dead end. Mobile-only heuristic since a desktop visitor has
// nothing to install.
const isMobileBrowser = typeof navigator !== 'undefined' && /iPhone|iPad|Android/i.test(navigator.userAgent || '');

// Personal-vs-organizer hierarchy pass (2026-09-27) — this screen is now
// PERSONAL ONLY: what anyone (signed in or not, see get_public_profile()'s
// anon grant, migration 079) sees at https://banbe.app/u/<handle>. It
// always leads with profiles.display_name — never organizers.name — and
// carries no organizer edit/guest-preview affordance at all any more; the
// organizer's own separate public page (real avatar/stats/upcoming
// events/photos, its own shareable /org/<id> link, its own owner-only
// edit) is OrganizerProfile.jsx, reached from the management page
// (Dashboard.jsx's "Hồ sơ công khai của tổ chức" button), never from here.
function ProfileActionButton({ testId, label, onClick, children }) {
  // Note 68: one row of equal 44pt pills under the card (icon + label), outside the card itself.
  return (
    <button type="button" onClick={onClick} data-testid={testId} aria-label={label}
      style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, height: 44, boxSizing: 'border-box', padding: '0 10px', background: surface2, color: ink, border: 'none', borderRadius: RADIUS.pill, cursor: 'pointer', fontFamily: 'inherit' }}>
      <svg width="18" height="18" style={{ flex: 'none' }} viewBox="0 0 24 24" fill="none" stroke={ink} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{children}</svg>
      <span style={{ fontSize: 13, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{label}</span>
    </button>
  );
}

// Alpha as a 2-digit hex suffix for a #RRGGBB colour.
const alphaHex = (a) => Math.round(a * 255).toString(16).padStart(2, '0');
const sectionTitle = display(17, { lineHeight: 1.3 });

export default function PublicProfile() {
  const { state, T, trStatus, backFromPublicProfile, sharePublicProfile, openEditProfile, openOrganizerTeam, goEvent, goHome, rewardsEnabled, loadRewards } = useBanBe();
  const s = state;
  const [qrOpen, setQrOpen] = useState(false);
  const [shareCardOpen, setShareCardOpen] = useState(false);
  const [qrSrc, setQrSrc] = useState(null);
  const p = s.publicProfile;
  const theirKeychain = useProfileKeychain(p?.handle);

  const isOwn = !!(p && s.user?.id === p.id);
  // Own profile with Rewards on: the earned-badge count for the stats strip (loaded once, like Account does).
  useEffect(() => {
    if (isOwn && rewardsEnabled && s.rewardsStatus === 'idle') loadRewards();
  }, [isOwn, rewardsEnabled, s.rewardsStatus, loadRewards]);

  useEffect(() => {
    if (!qrOpen || !p?.handle) return;
    let active = true;
    QRCode.toDataURL(`https://banbe.app/u/${p.handle}`, { margin: 1, width: 220, color: { dark: '#000000', light: '#FFFFFF' } })
      .then(url => { if (active) setQrSrc(url); });
    return () => { active = false; };
  }, [qrOpen, p?.handle]);

  if (s.publicProfileLoading) {
    return <div style={{ minHeight: '100%', background: paper }} data-screen-label="Public profile" />;
  }
  if (s.publicProfileError || !p) {
    return (
      <div style={{ minHeight: '100%', background: paper, display: 'flex', flexDirection: 'column' }} data-screen-label="Public profile">
        <div style={{ padding: '66px 20px 0' }}>
          <span onClick={backFromPublicProfile} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>{T('‹ Quay lại', '‹ Back')}</span>
        </div>
        <p style={{ textAlign: 'center', fontSize: 13, color: ink, marginTop: 60 }}>{s.publicProfileError}</p>
      </div>
    );
  }

  const paletteColor = PROFILE_PALETTE_COLORS[p.profile_theme] || PROFILE_PALETTE_COLORS.default;
  const monogram = (p.display_name || p.handle || '?').trim()[0]?.toUpperCase() || '?';
  const isOwnProfile = s.user?.id === p.id;
  // Only ever populated when THIS profile genuinely owns that organizer
  // (get_public_profile's own owner_id/user_id join) — never guessed, never
  // any other account's organizer.
  const org = p.organizer;

  const vi = T(true, false);
  const hostMode = !!(org && p.organizer_mode);
  const role = roleLabel({ organizerName: org?.name, organizerMode: p.organizer_mode }, vi);
  const interests = dedupeChips(p.interests || [], [role, p.bio, p.display_name]);
  // Upcoming (note 68), from what the app already has: this person's own hosted events still ahead (public), and for
  // the owner only, the events they are going to. Never anyone else's bookings.
  const upcoming = upcomingEvents({
    events: EVENTS.map(e => ({ key: e.key, name: e.name, when: e.when, img: e.img, organizerId: e.organizerId ?? s.realEventsById[e.key]?.organizerId ?? null,
      start: e.startDate ? e.startDate.getTime() : null, ended: e.endedHoursAgo != null, cancelled: !!e.cancelled })),
    organizerId: org?.id, organizerMode: !!p.organizer_mode, isOwner: isOwnProfile, goingKeys: s.attending || [],
  });
  const goingCount = isOwnProfile ? (s.attending || []).map(k => EVENTS.find(e => e.key === k)).filter(e => e && e.endedHoursAgo == null).length : null;
  const badgeCount = isOwnProfile && rewardsEnabled && s.rewards?.badges ? s.rewards.badges.filter(b => b.earned).length : null;
  const stats = profileStats({ organizer: org, organizerMode: !!p.organizer_mode, isOwner: isOwnProfile, rewardsOn: !!rewardsEnabled, badgeCount, upcomingCount: goingCount });
  const statLabel = { hosted: T('Sự kiện', 'Hosted'), followers: T('Người theo dõi', 'Followers'), since: T('Từ năm', 'Since'), badges: T('Huy hiệu', 'Badges'), upcoming: T('Sắp tới', 'Upcoming') };
  const charmLeft = theirKeychain?.enabled && String(theirKeychain?.anchor || '').endsWith('left');
  // The card surface (src/lib/profileCard.js cardSurface, contrast-tested): surface2, the person's palette colour as a
  // light tint, a soft clay glow in the charm's corner, and a hairline highlight instead of a border.
  const cardBg = [
    `radial-gradient(circle at ${charmLeft ? '0% 0%' : '100% 0%'}, rgba(var(--bb-clay-rgb), ${CARD_GLOW}), transparent 60%)`,
    `linear-gradient(${paletteColor}${alphaHex(CARD_TINT)}, ${paletteColor}${alphaHex(CARD_TINT)})`,
    surface2,
  ].join(', ');

  return (
    <div style={{ minHeight: '100%', background: paper, display: 'flex', flexDirection: 'column', paddingBottom: SPACE.xl }} data-screen-label="Public profile">
      {isMobileBrowser && (
        <a href={APP_STORE_URL} data-testid="public-profile-get-app" style={{ display: 'block', textDecoration: 'none', textAlign: 'center', fontSize: 13, fontWeight: 600, color: paper, background: ink, padding: '9px 0' }}>
          {T('Mở trong ứng dụng banbe ›', 'Open in the banbe app ›')}
        </a>
      )}
      <div style={{ padding: '56px 16px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <button type="button" onClick={backFromPublicProfile} data-testid="public-profile-back" style={{ minHeight: 44, padding: 0, border: 'none', background: 'none', fontFamily: 'inherit', fontSize: 15, color: ink, cursor: 'pointer' }}>{T('‹ Quay lại', '‹ Back')}</button>
        <button type="button" onClick={() => setShareCardOpen(true)} data-testid="public-profile-share" style={{ minHeight: 44, padding: 0, border: 'none', background: 'none', fontFamily: 'inherit', fontSize: 15, fontWeight: 600, color: ink, cursor: 'pointer' }}>
          {T('Chia sẻ', 'Share')}
        </button>
      </div>

      {/* Identity card (note 68): left-aligned, full width. Avatar with a clay→gold ring, the name as the largest
          text, one role line, @handle · city, the bio, then the stats strip inside the card. The charm hangs in the
          corner the owner chose; the text column keeps clear of it. Owner actions sit OUTSIDE the card. */}
      <KeychainFrame config={theirKeychain} margin={`${SPACE.s}px 16px 0`} cardHeight={216} testId="public-profile-keychain-frame"
        label={T(`Móc khoá của ${p.display_name || p.handle}`, `${p.display_name || p.handle}'s keychain`)}>
        {({ reserveLeft, reserveRight }) => (
          <div data-testid="public-profile-card"
            style={{ margin: 0, padding: 20, borderRadius: 20, background: cardBg, boxShadow: 'inset 0 0 0 1px rgba(var(--bb-fg-rgb),0.06)', color: ink, display: 'flex', flexDirection: 'column', gap: SPACE.m }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: SPACE.l, paddingLeft: reserveLeft, paddingRight: reserveRight }}>
              <span aria-hidden style={{ flex: 'none', width: 80, height: 80, borderRadius: '50%', padding: 2, background: `linear-gradient(135deg, ${clay}, ${attn})`, boxSizing: 'border-box' }}>
                <span style={{ display: 'block', width: '100%', height: '100%', borderRadius: '50%', padding: 2, background: paper, boxSizing: 'border-box' }}>
                  {p.avatar_url ? (
                    <img src={p.avatar_url} alt="" style={{ display: 'block', width: '100%', height: '100%', borderRadius: '50%', objectFit: 'cover' }} />
                  ) : (
                    <span style={{ display: 'flex', width: '100%', height: '100%', borderRadius: '50%', background: ink, color: paper, alignItems: 'center', justifyContent: 'center', fontSize: 26, fontWeight: 600 }}>{monogram}</span>
                  )}
                </span>
              </span>
              <div style={{ minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                {/* Always the PERSON's own name first (never swapped for organizers.name). Wraps, never truncates. */}
                <span style={{ ...display(26, { lineHeight: 1.15 }), overflowWrap: 'anywhere' }} data-testid="public-profile-display-name">{p.display_name}</span>
                {/* One role line. "Organizer mode OFF means host UI is OFF" reaches this line too (migration 096). */}
                <span style={{ fontSize: 13, color: ink2 }} data-testid={hostMode ? 'public-profile-founder-line' : 'public-profile-role'}>{role}</span>
                <span style={{ fontSize: 13, color: ink2, overflowWrap: 'anywhere' }}>@{p.handle}{p.city ? ' · ' + p.city : ''}</span>
              </div>
            </div>
            {p.bio && <p data-testid="public-profile-bio" style={{ fontSize: 15, lineHeight: 1.45, color: ink, margin: 0 }}>{p.bio}</p>}
            {stats.length > 0 && (
              <div data-testid="public-profile-stats" style={{ display: 'flex', borderTop: `1px solid ${divider}`, paddingTop: SPACE.m }}>
                {stats.map((st, i) => (
                  <div key={st.id} data-testid={`public-profile-stat-${st.id}`} style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2, paddingLeft: i ? SPACE.m : 0, borderLeft: i ? `1px solid ${divider}` : 'none' }}>
                    <span style={{ fontSize: 17, fontWeight: 600, color: ink, fontVariantNumeric: 'tabular-nums' }}>{st.value}</span>
                    <span style={{ fontSize: 13, color: ink2 }}>{statLabel[st.id]}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </KeychainFrame>

      {/* Own profile: QR / Edit profile / Edit charm as one row of equal pills. Visitors only get the QR button.
          Edit profile touches profiles fields ONLY (organizer fields live on OrganizerProfile.jsx). */}
      <div style={{ margin: `${SPACE.m}px 16px 0`, display: 'flex', gap: SPACE.s }}>
        <ProfileActionButton testId="public-profile-qr-cta" label={T('Mã QR', 'QR code')} onClick={() => setQrOpen(true)}>
          <><rect x="4" y="4" width="6" height="6" rx="1" /><rect x="14" y="4" width="6" height="6" rx="1" /><rect x="4" y="14" width="6" height="6" rx="1" /><path d="M14 14h2.5v2.5H14zM18 18h2M17.5 20v-1.5" /></>
        </ProfileActionButton>
        {isOwnProfile && (
          <ProfileActionButton testId="public-profile-edit-personal" label={T('Sửa hồ sơ', 'Edit profile')} onClick={openEditProfile}>
            <path d="M15.2 4.3l4.5 4.5L8.4 20.1H4v-4.4z" />
          </ProfileActionButton>
        )}
        {isOwnProfile && (
          <ProfileActionButton testId="public-profile-edit-charm" label={T('Sửa móc khoá', 'Edit charm')}
            onClick={() => { keychainFocus.pending = true; openEditProfile(); }}>
            <><circle cx="8" cy="12" r="3.6" /><path d="M11.6 12H21M17.5 12v3M20.8 12v2.2" /></>
          </ProfileActionButton>
        )}
      </div>

      {/* Below the card (note 68): what used to be crammed inside it, then Upcoming and credits. 24 between sections. */}
      <div style={{ margin: `${SPACE.xl}px 16px 0`, display: 'flex', flexDirection: 'column', gap: SPACE.xl }}>
        {(p.intro_long || (p.social_links || []).length > 0) && (
          <section data-testid="public-profile-about" style={{ display: 'flex', flexDirection: 'column', gap: SPACE.s, alignItems: 'flex-start' }}>
            <span style={sectionTitle}>{T('Giới thiệu', 'About')}</span>
            {/* Organizer Team pass (2026-09-27, Stage 3) — a SEPARATE long-form intro; the short bio is untouched. */}
            <LongIntroPreview T={T} text={p.intro_long} />
            <SocialLinksRow links={p.social_links} />
          </section>
        )}
        {(interests.length > 0 || (p.team_badges || []).length > 0) && (
          <section style={{ display: 'flex', flexDirection: 'column', gap: SPACE.s }}>
            <span style={sectionTitle}>{T('Sở thích & nhóm', 'Interests & teams')}</span>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: SPACE.s }}>
              {interests.map(tag => (
                <span key={tag} style={{ fontSize: 13, fontWeight: 600, color: ink, background: surface2, padding: '6px 12px', borderRadius: RADIUS.pill }}>{tag}</span>
              ))}
              {/* Organizer Team pass (2026-09-27, Stage 2) — ONLY this profile's OWN opted-in choice (team_badges,
                  get_public_profile 100): accepted AND currently public_visible. */}
              {(p.team_badges || []).map(b => (
                <span
                  key={b.organizer_id}
                  role="button"
                  onClick={() => {
                    // iPhone fix pass (2026-09-27), Issue 3 — one shared `organizerTeamBack` field (no real navigation
                    // stack): reaching this profile FROM that same organizer's Team, the badge pops back to that Team
                    // screen instead of pushing a second one that would clobber its own back target.
                    if (s.organizerTeamOrganizerId === b.organizer_id && s.publicProfileBack === 'organizerTeam') {
                      backFromPublicProfile();
                    } else {
                      openOrganizerTeam(b.organizer_id, 'publicProfile');
                    }
                  }}
                  data-testid={`public-profile-team-badge-${b.organizer_id}`}
                  style={{ fontSize: 13, fontWeight: 600, color: clay, background: clayBg, padding: '6px 12px', borderRadius: RADIUS.pill, cursor: 'pointer' }}
                >
                  {T(`Thành viên của ${b.organizer_name} Team`, `Member of the ${b.organizer_name} Team`)}
                </span>
              ))}
            </div>
          </section>
        )}
        {(upcoming.length > 0 || isOwnProfile) && (
          <section data-testid="public-profile-upcoming" style={{ display: 'flex', flexDirection: 'column', gap: SPACE.s }}>
            <span style={sectionTitle}>{T('Sắp tới', 'Upcoming')}</span>
            {upcoming.length > 0 ? (
              <div style={{ display: 'flex', flexDirection: 'column', borderRadius: RADIUS.card, background: surface2, overflow: 'hidden' }}>
                {upcoming.map((e, i) => (
                  <div key={e.key} role="button" onClick={() => goEvent(e.key)} data-testid={`public-profile-upcoming-${i}`}
                    style={{ display: 'flex', alignItems: 'center', gap: SPACE.m, padding: `${SPACE.m}px ${SPACE.l}px`, minHeight: 44, borderTop: i ? `1px solid ${divider}` : 'none', cursor: 'pointer' }}>
                    <span style={{ minWidth: 0, flex: 1, display: 'flex', flexDirection: 'column', gap: 2 }}>
                      <span style={{ fontSize: 15, fontWeight: 600, color: ink, overflowWrap: 'anywhere' }}>{e.name}</span>
                      <span style={{ fontSize: 13, color: ink2 }}>{trStatus(e.when || '')}</span>
                    </span>
                    <span style={{ flex: 'none', fontSize: 13, fontWeight: 600, color: e.role === 'hosting' ? clay : ink2, background: e.role === 'hosting' ? clayBg : 'transparent', padding: '4px 10px', borderRadius: RADIUS.pill }}>
                      {e.role === 'hosting' ? T('Tổ chức', 'Hosting') : T('Sẽ đi', 'Going')}
                    </span>
                    <span aria-hidden style={{ color: ink2, fontSize: 17 }}>›</span>
                  </div>
                ))}
              </div>
            ) : (
              // Owner empty state: say what this is and where to go next.
              <div data-testid="public-profile-upcoming-empty" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: SPACE.m, padding: `${SPACE.m}px ${SPACE.l}px`, borderRadius: RADIUS.card, background: surface2 }}>
                <span style={{ fontSize: 15, color: ink2 }}>{T('Chưa có sự kiện sắp tới', 'Nothing coming up yet')}</span>
                <button type="button" onClick={goHome} data-testid="public-profile-browse" style={{ minHeight: 44, padding: '0 4px', border: 'none', background: 'none', fontFamily: 'inherit', fontSize: 15, fontWeight: 600, color: clay, cursor: 'pointer' }}>{T('Xem sự kiện ›', 'Browse events ›')}</button>
              </div>
            )}
          </section>
        )}
        {/* Real, explicit, ACCEPTED event contributions only — never derived from ticket attendance/bookings/check-ins. */}
        {!!(p.credited_events || []).length && (
          <section data-testid="public-profile-credited-events" style={{ display: 'flex', flexDirection: 'column', gap: SPACE.s }}>
            <span style={sectionTitle}>{T('Đã tham gia tổ chức', 'Helped organize')}</span>
            <div style={{ display: 'flex', flexDirection: 'column', gap: SPACE.s }}>
              {p.credited_events.map(e => (
                <div key={e.event_id} onClick={() => goEvent(e.event_id)} style={{ ...cardGlass({ padding: '12px 16px', cursor: 'pointer' }) }}>
                  <span style={{ fontSize: 15, color: ink }}>{e.event_name}</span>
                  <span style={{ fontSize: 13, color: ink2, display: 'block' }}>{e.organizer_name}</span>
                </div>
              ))}
            </div>
          </section>
        )}
      </div>

      {qrOpen && (
        <div onClick={() => setQrOpen(false)} style={{ position: 'fixed', inset: 0, background: 'rgba(27,25,22,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 50 }}>
          <div onClick={(e) => e.stopPropagation()} style={{ background: paper, borderRadius: 20, padding: 24, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
            {qrSrc ? <img src={qrSrc} alt="QR" style={{ width: 220, height: 220 }} /> : <div style={{ width: 220, height: 220 }} />}
            <span style={{ fontSize: 12, color: ink }}>@{p.handle}</span>
          </div>
        </div>
      )}

      {s.profileLinkCopiedFlash && (
        <p style={{ textAlign: 'center', fontSize: 11.5, color: ink, opacity: 0.7, margin: '10px 0 0' }}>{T('Đã sao chép link hồ sơ', 'Profile link copied')}</p>
      )}
      <ProfileShareSheet
        open={shareCardOpen}
        onClose={() => setShareCardOpen(false)}
        kindLabel={T('Thành viên', 'Member')}
        name={p.display_name || ''}
        subtitle={p.handle ? `@${p.handle}` : ''}
        detail={p.bio || ''}
        avatarUrl={p.avatar_url || ''}
        roundAvatar
        link={profileShareLinks().member(p.handle)}
        idPrefix="public-profile-share-card"
        kind="member"
        publishId={p.handle || ''}
        isOwner={!!(p.handle && s.user?.handle && p.handle.toLowerCase() === s.user.handle.toLowerCase())}
      />
    </div>
  );
}

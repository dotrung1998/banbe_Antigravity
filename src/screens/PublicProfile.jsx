import { useEffect, useState } from 'react';
import QRCode from 'qrcode';
import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, display, cardGlass } from '../theme.js';
import { PROFILE_PALETTE_COLORS } from '../lib/profileTheme.js';
import { APP_STORE_URL } from '../lib/appStore.js';
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
export default function PublicProfile() {
  const { state, T, backFromPublicProfile, sharePublicProfile, openEditProfile, openOrganizerTeam, goEvent } = useGoc();
  const s = state;
  const [qrOpen, setQrOpen] = useState(false);
  const [qrSrc, setQrSrc] = useState(null);
  const p = s.publicProfile;

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

  return (
    <div style={{ minHeight: '100%', background: paper, display: 'flex', flexDirection: 'column' }} data-screen-label="Public profile">
      {isMobileBrowser && (
        <a href={APP_STORE_URL} data-testid="public-profile-get-app" style={{ display: 'block', textDecoration: 'none', textAlign: 'center', fontSize: 12, fontWeight: 600, color: paper, background: ink, padding: '9px 0' }}>
          {T('Mở trong ứng dụng banbe ›', 'Open in the banbe app ›')}
        </a>
      )}
      <div style={{ padding: '66px 20px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span onClick={backFromPublicProfile} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>{T('‹ Quay lại', '‹ Back')}</span>
        <span onClick={() => sharePublicProfile(p.handle, p.display_name)} data-testid="public-profile-share" style={{ fontSize: 12, fontWeight: 600, color: ink, cursor: 'pointer' }}>
          {T('Chia sẻ', 'Share')}
        </span>
      </div>

      {/* iPhone fix pass (2026-09-27), Item 3 — top margin bumped 20→22,
          same existing spacing value Account.jsx's own profile/org cards
          already use for this exact "gap below a top bar" (not a new
          token). */}
      <div
        data-testid="public-profile-card"
        style={{
          ...cardGlass({ margin: '22px 20px 0', padding: '28px 22px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }),
          background: `linear-gradient(165deg, ${paletteColor}CC, ${paletteColor}55)`,
        }}
      >
        {p.avatar_url ? (
          <img src={p.avatar_url} alt="" style={{ width: 88, height: 88, borderRadius: '50%', objectFit: 'cover', border: `3px solid ${paper}` }} />
        ) : (
          <div style={{ width: 88, height: 88, borderRadius: '50%', background: ink, color: paper, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 32, fontWeight: 700, border: `3px solid ${paper}` }}>
            {monogram}
          </div>
        )}
        {/* Personal-vs-organizer hierarchy pass — always the PERSON's own
            name first (never swapped for organizers.name any more). */}
        <span style={{ ...display(21) }} data-testid="public-profile-display-name">{p.display_name}</span>
        {/* Only when this profile truly owns that organizer — a plain
            pointer to who they are, not a second mini-dashboard (event/
            follower stats and the follow CTA now live on the organizer's
            own separate page, OrganizerProfile.jsx). Account extension
            (2026-09-27, Stage 1) — "organizer mode OFF means host UI is
            OFF" reaches this line too: hidden for every visitor (not just
            the owner) while THIS profile's own organizer_mode is off,
            same real preference Account's own toggle writes (migration
            096 exposes it read-only here). */}
        {org && p.organizer_mode && (
          <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }} data-testid="public-profile-founder-line">
            {T(`Founder tổ chức: ${org.name}`, `Founder of ${org.name}`)}
          </span>
        )}
        <span style={{ fontSize: 12.5, color: ink, opacity: 0.75 }}>@{p.handle}{p.city ? ' ▪︎ ' + p.city : ''}</span>
        {p.bio && <p style={{ fontSize: 12.5, lineHeight: 1.5, color: ink, textAlign: 'center', margin: '4px 0 0' }}>{p.bio}</p>}
        {/* Organizer Team pass (2026-09-27, Stage 3) — a SEPARATE
            long-form intro; the short bio above is untouched. */}
        <LongIntroPreview T={T} text={p.intro_long} />
        <SocialLinksRow links={p.social_links} />
        {!!(p.interests || []).length && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, justifyContent: 'center', marginTop: 4 }}>
            {p.interests.map(tag => (
              <span key={tag} style={{ fontSize: 10.5, fontWeight: 600, color: ink, background: 'rgba(255,255,255,0.5)', padding: '5px 10px', borderRadius: 999 }}>{tag}</span>
            ))}
          </div>
        )}
        {/* Organizer Team pass (2026-09-27, Stage 2) — ONLY this profile's
            OWN opted-in choice (team_badges, get_public_profile 100):
            accepted AND currently public_visible. Hiding Team association
            removes this badge (and the event credits below) in the same
            instant server-side — nothing here is a client-side guess. */}
        {!!(p.team_badges || []).length && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, justifyContent: 'center', marginTop: 6 }}>
            {p.team_badges.map(b => (
              <span
                key={b.organizer_id}
                onClick={() => openOrganizerTeam(b.organizer_id, 'profile')}
                data-testid={`public-profile-team-badge-${b.organizer_id}`}
                style={{ fontSize: 10.5, fontWeight: 600, color: ink, background: 'rgba(255,255,255,0.7)', padding: '6px 12px', borderRadius: 999, cursor: 'pointer', border: `1px solid ${rule}` }}
              >
                {T(`Thành viên của ${b.organizer_name} Team`, `Member of the ${b.organizer_name} Team`)}
              </span>
            ))}
          </div>
        )}
      </div>

      {/* Real, explicit, ACCEPTED event contributions only — never derived
          from ticket attendance/bookings/check-ins. Empty if none. */}
      {!!(p.credited_events || []).length && (
        <div style={{ margin: '14px 20px 0' }} data-testid="public-profile-credited-events">
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.7 }}>{T('Đã tham gia tổ chức', 'Helped organize')}</span>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 6 }}>
            {p.credited_events.map(e => (
              <div key={e.event_id} onClick={() => goEvent(e.event_id)} style={{ ...cardGlass({ padding: '10px 14px', cursor: 'pointer' }) }}>
                <span style={{ fontSize: 12.5, color: ink }}>{e.event_name}</span>
                <span style={{ fontSize: 11, color: ink, opacity: 0.6, display: 'block' }}>{e.organizer_name}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      <div onClick={() => setQrOpen(true)} data-testid="public-profile-qr-cta" style={{ margin: '16px 20px 0', textAlign: 'center', fontSize: 12.5, fontWeight: 600, color: ink, padding: '13px 0', border: `1px solid ${rule}`, borderRadius: 12, cursor: 'pointer' }}>
        {T('Hiển thị mã QR', 'Show QR code')}
      </div>

      {/* iPhone fix pass — "Chỉnh sửa hồ sơ" beneath "Hiển thị mã QR",
          own-profile only (never rendered for a visitor viewing someone
          else's page — `isOwnProfile` is a server-independent client
          check, but the actual edit RPC is owner-gated server-side
          regardless). Edits profiles fields ONLY — never
          organizers.name/about/avatar_path, which live on the organizer's
          own separate editor now (OrganizerProfile.jsx). */}
      {isOwnProfile && (
        <div onClick={openEditProfile} data-testid="public-profile-edit-personal" style={{ margin: '10px 20px 0', textAlign: 'center', fontSize: 12.5, fontWeight: 600, color: ink, padding: '13px 0', border: `1px solid ${rule}`, borderRadius: 12, cursor: 'pointer' }}>
          {T('Chỉnh sửa hồ sơ', 'Edit profile')}
        </div>
      )}

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
    </div>
  );
}

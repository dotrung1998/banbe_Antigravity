import { useEffect, useRef, useState } from 'react';
import QRCode from 'qrcode';
import { useGoc } from '../state/GocContext.jsx';
import { supabase } from '../lib/supabase.js';
import { paper, ink, rule, display, cardGlass, inkButton, alert } from '../theme.js';
import { PROFILE_PALETTE_COLORS } from '../lib/profileTheme.js';
import { APP_STORE_URL } from '../lib/appStore.js';

function organizerAvatarUrl(path) {
  if (!path) return '';
  return supabase.storage.from('organizer-photos').getPublicUrl(path).data.publicUrl;
}

// TASK D — "app not installed" fallback (rule D3): a shared /u/<handle>
// link that doesn't open the native app (no universal-link verification,
// or simply opened in a desktop browser where there's no app to open)
// lands here instead — this banner is that fallback's own visible CTA,
// not a silent dead end. Mobile-only heuristic since a desktop visitor has
// nothing to install.
const isMobileBrowser = typeof navigator !== 'undefined' && /iPhone|iPad|Android/i.test(navigator.userAgent || '');

// TASK D (2026-10-01 UX foundation pass) — what anyone (signed in or not,
// see get_public_profile()'s anon grant, migration 079) sees at
// https://banbe.app/u/<handle>. Organizer mode transforms the SAME card
// into the organizer presentation (event/follower stats, follow CTA)
// rather than a second, conflicting persona.
export default function PublicProfile() {
  const {
    state, T, backFromPublicProfile, toggleFollowOrganizer, sharePublicProfile,
    openEditProfile, orgRegNameType, orgRegDescType, saveOrganizerProfile,
  } = useGoc();
  const s = state;
  const [qrOpen, setQrOpen] = useState(false);
  const [qrSrc, setQrSrc] = useState(null);
  // iPhone fix pass (2026-09-26) — inline editing for the ORGANIZER half of
  // this same page, mirroring Account.jsx's own host-tab card exactly
  // (same orgRegName/orgRegDesc/saveOrganizerProfile — this account has at
  // most one organizer, s.myOrganizerId, same standing assumption as
  // everywhere else). A SEPARATE entry from "Chỉnh sửa hồ sơ" (personal,
  // -> EditProfile) — never the same action, since they edit different
  // rows in different tables.
  const [orgEditing, setOrgEditing] = useState(false);
  const [orgAvatarFile, setOrgAvatarFile] = useState(null);
  const [orgAvatarPreview, setOrgAvatarPreview] = useState('');
  const orgAvatarInputRef = useRef(null);
  const onPickOrgAvatar = (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    if (orgAvatarPreview) URL.revokeObjectURL(orgAvatarPreview);
    setOrgAvatarFile(file);
    setOrgAvatarPreview(URL.createObjectURL(file));
  };
  const doSaveOrg = async () => {
    await saveOrganizerProfile(orgAvatarFile);
    setOrgEditing(false);
    setOrgAvatarFile(null);
    if (orgAvatarPreview) { URL.revokeObjectURL(orgAvatarPreview); setOrgAvatarPreview(''); }
  };
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

      <div
        data-testid="public-profile-card"
        style={{
          ...cardGlass({ margin: '20px 20px 0', padding: '28px 22px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }),
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
        <span style={{ ...display(21) }}>{p.display_name}</span>
        <span style={{ fontSize: 12.5, color: ink, opacity: 0.75 }}>@{p.handle}{p.city ? ' ▪︎ ' + p.city : ''}</span>
        {p.bio && <p style={{ fontSize: 12.5, lineHeight: 1.5, color: ink, textAlign: 'center', margin: '4px 0 0' }}>{p.bio}</p>}
        {!!(p.interests || []).length && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, justifyContent: 'center', marginTop: 4 }}>
            {p.interests.map(tag => (
              <span key={tag} style={{ fontSize: 10.5, fontWeight: 600, color: ink, background: 'rgba(255,255,255,0.5)', padding: '5px 10px', borderRadius: 999 }}>{tag}</span>
            ))}
          </div>
        )}

        {org && (
          <>
            <div style={{ display: 'flex', gap: 20, marginTop: 10 }}>
              <Stat value={org.event_count} label={T('Sự kiện', 'Events')} />
              <Stat value={org.follower_count} label={T('Người theo dõi', 'Followers')} />
              {org.verified && <Stat value="✓" label={T('Đã xác minh', 'Verified')} />}
            </div>
            {/* iPhone fix pass — derived from the earliest REAL published
                (live/ended) event, never the organizer's own stored
                hosting_since text (get_public_profile, migration 091). An
                organizer with nothing published yet gets an honest empty
                line, never a fabricated year. */}
            <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>
              {org.hosting_since_year
                ? T(`Tổ chức từ ${org.hosting_since_year}`, `Hosting since ${org.hosting_since_year}`)
                : T('Chưa có sự kiện công khai nào', 'No published events yet')}
            </span>
          </>
        )}

        {org && !isOwnProfile && (
          <div
            onClick={() => toggleFollowOrganizer(org.id)}
            data-testid="public-profile-follow"
            style={{
              marginTop: 10, fontSize: 13, fontWeight: 600, padding: '10px 24px', borderRadius: 999, cursor: 'pointer',
              background: org.following ? 'transparent' : ink, color: org.following ? ink : paper,
              border: org.following ? `1px solid ${rule}` : 'none',
            }}
          >
            {org.following ? T('Đang theo dõi', 'Following') : T('Theo dõi', 'Follow')}
          </div>
        )}
      </div>

      <div onClick={() => setQrOpen(true)} data-testid="public-profile-qr-cta" style={{ margin: '16px 20px 0', textAlign: 'center', fontSize: 12.5, fontWeight: 600, color: ink, padding: '13px 0', border: `1px solid ${rule}`, borderRadius: 12, cursor: 'pointer' }}>
        {T('Hiển thị mã QR', 'Show QR code')}
      </div>

      {/* iPhone fix pass — "Chỉnh sửa hồ sơ" beneath "Hiển thị mã QR",
          own-profile only (never rendered for a visitor viewing someone
          else's page — `isOwnProfile` is a server-independent client
          check, but the actual edit RPCs below are owner/admin-gated
          server-side regardless, same as Account.jsx's own card). */}
      {isOwnProfile && (
        <div onClick={openEditProfile} data-testid="public-profile-edit-personal" style={{ margin: '10px 20px 0', textAlign: 'center', fontSize: 12.5, fontWeight: 600, color: ink, padding: '13px 0', border: `1px solid ${rule}`, borderRadius: 12, cursor: 'pointer' }}>
          {T('Chỉnh sửa hồ sơ', 'Edit profile')}
        </div>
      )}

      {/* Organizer's own edit — a SEPARATE row/action from the personal one
          above; edits organizers.name/about/avatar_path only (migration
          090's update_organizer_profile), never profiles.*. */}
      {/* `org.id === s.myOrganizerId` — never editing on the strength of
          `isOwnProfile` alone. Both should already agree (one organizer
          per account, everywhere else in this codebase), but this is the
          one place a mismatch would silently edit the WRONG organizer's
          row, so it's checked explicitly rather than assumed. */}
      {isOwnProfile && org && org.id === s.myOrganizerId && (
        <div style={{ ...cardGlass({ margin: '14px 20px 0', padding: 16, display: 'flex', flexDirection: 'column', gap: 10 }) }} data-testid="public-profile-org-edit-card">
          {orgEditing ? (
            <>
              <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
                <div
                  onClick={() => orgAvatarInputRef.current?.click()}
                  style={{ flex: 'none', width: 52, height: 52, borderRadius: 12, overflow: 'hidden', cursor: 'pointer', background: 'rgba(0,0,0,0.05)' }}
                >
                  {(orgAvatarPreview || organizerAvatarUrl(s.myOrganizerAvatarPath)) && (
                    <img src={orgAvatarPreview || organizerAvatarUrl(s.myOrganizerAvatarPath)} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  )}
                </div>
                <span onClick={() => orgAvatarInputRef.current?.click()} style={{ fontSize: 12, color: ink, textDecoration: 'underline', cursor: 'pointer' }}>{T('Đổi ảnh', 'Change photo')}</span>
                <input ref={orgAvatarInputRef} type="file" accept="image/jpeg,image/png,image/webp" style={{ display: 'none' }} onChange={onPickOrgAvatar} />
              </div>
              <input
                value={s.orgRegName} onChange={orgRegNameType} data-testid="public-profile-org-name-input"
                style={{ fontSize: 14, fontWeight: 600, color: ink, border: `1px solid ${rule}`, borderRadius: 10, padding: '9px 11px', outline: 'none' }}
              />
              <textarea
                value={s.orgRegDesc} onChange={orgRegDescType} rows={3} maxLength={2000}
                placeholder={T('Giới thiệu ngắn về bạn/nhóm tổ chức…', 'A short introduction to you/your host team…')}
                data-testid="public-profile-org-intro-input"
                style={{ fontSize: 13, color: ink, border: `1px solid ${rule}`, borderRadius: 10, padding: '10px 12px', outline: 'none', resize: 'vertical', lineHeight: 1.5 }}
              />
              <div style={{ display: 'flex', gap: 8 }}>
                <span
                  onClick={doSaveOrg}
                  data-testid="public-profile-org-save"
                  style={{ flex: 1, textAlign: 'center', fontSize: 12.5, fontWeight: 600, color: paper, background: ink, padding: '10px 0', borderRadius: 10, cursor: 'pointer', opacity: s.orgProfileSaving ? 0.6 : 1 }}
                >
                  {s.orgProfileSaving ? T('Đang lưu…', 'Saving…') : T('Lưu', 'Save')}
                </span>
                <span onClick={() => setOrgEditing(false)} style={{ flex: 1, textAlign: 'center', fontSize: 12.5, fontWeight: 600, color: ink, padding: '10px 0', borderRadius: 10, cursor: 'pointer', border: `1px solid ${rule}` }}>
                  {T('Huỷ', 'Cancel')}
                </span>
              </div>
              {s.orgProfileError && <p style={{ fontSize: 11.5, color: alert, margin: 0 }}>{s.orgProfileError}</p>}
            </>
          ) : (
            <div onClick={() => setOrgEditing(true)} data-testid="public-profile-edit-org" style={{ textAlign: 'center', fontSize: 12.5, fontWeight: 600, color: ink, cursor: 'pointer' }}>
              {T('Chỉnh sửa hồ sơ tổ chức', 'Edit host profile')}
            </div>
          )}
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

function Stat({ value, label }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2 }}>
      <span style={{ ...display(17) }}>{value}</span>
      <span style={{ fontSize: 10, color: ink, opacity: 0.7 }}>{label}</span>
    </div>
  );
}

import { useEffect, useRef, useState } from 'react';
import QRCode from 'qrcode';
import { useBanBe } from '../state/BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { organizerAvatarPublicUrl, publicEventPhotoUrl } from '../lib/mediaUrls.js';
import { paper, ink, ink2, rule, alert, display, cardGlass, surface2, clay, attn, divider, RADIUS, SPACE } from '../theme.js';
import { CARD_GLOW } from '../lib/profileCard.js';
import { bg } from '../data/events.js';
import { SocialLinksEditor } from './SocialLinksEditor.jsx';
import ProfileShareSheet, { profileShareLinks } from './sheets/ProfileShareSheet.jsx';
import { LongIntroPreview, SocialLinksRow } from './LongIntro.jsx';

function organizerAvatarUrl(path, r2Ref, variant = 'card') {
  return organizerAvatarPublicUrl(path, r2Ref, variant);
}
function organizerPhotoUrl(path, r2Ref) {
  return publicEventPhotoUrl(path, r2Ref, 'card') || '';
}

// Personal-vs-organizer hierarchy pass (2026-09-27) — the organizer's own,
// SEPARATE public profile, reached from the management page's "Hồ sơ công
// khai của tổ chức" button (Dashboard.jsx) or a shared /org/<organizer_id>
// link — never from the personal profile any more (PublicProfile.jsx).
// Real organizer data only: avatar, name, intro, genuine hosting-since
// year, published-event/follower counts, a concise real-upcoming-events
// preview and a handful of real photos. No location/category fields —
// `organizers` doesn't store either, and this ticket's own rule is to
// hide what's missing rather than invent it.
export default function OrganizerProfile() {
  const {
    state, T, backFromOrganizerProfile, shareOrganizerProfile, toggleFollowOrganizer,
    loadOrganizerProfileExtras, loadOrganizerPhotos, openPhoto, goEvent, orgRegNameType, orgRegDescType, saveOrganizerProfile,
    openOrganizerTeam,
    orgRegIntroLongType, toggleOrgRegLinksOpen, addOrgRegLink, setOrgRegLink, removeOrgRegLink,
  } = useBanBe();
  const s = state;
  const [qrOpen, setQrOpen] = useState(false);
  const [pastOpen, setPastOpen] = useState(false);
  const [shareCardOpen, setShareCardOpen] = useState(false);
  const [qrSrc, setQrSrc] = useState(null);
  const [editing, setEditing] = useState(false);
  const [avatarFile, setAvatarFile] = useState(null);
  const [avatarPreview, setAvatarPreview] = useState('');
  const avatarInputRef = useRef(null);
  const org = s.organizerProfile;
  const isOwner = !!(org && org.id === s.myOrganizerId);
  // The canonical follow list (same one Account > Following edits) once loaded; the RPC's own flag until then.
  const following = !!org && (s.followedStatus === 'loaded' ? s.followedOrgIds.includes(org.id) : !!org.following);
  // Who may EDIT + publish this host's share card (migration 155 checks
  // owner_id/user_id server-side too). Wider than `isOwner` on purpose: an
  // account owning several organizers still owns each one's card.
  const isCardOwner = !!(org && (org.id === s.myOrganizerId || (s.myOrganizerIds || []).includes(org.id)));

  useEffect(() => {
    if (s.organizerProfileId) loadOrganizerProfileExtras(s.organizerProfileId);
  }, [s.organizerProfileId, loadOrganizerProfileExtras]);

  // The photo library (merged in from the retired Organizer screen) —
  // re-fetched whenever the viewed organizer changes.
  useEffect(() => {
    if (s.organizerProfileId) loadOrganizerPhotos(s.organizerProfileId);
  }, [s.organizerProfileId, loadOrganizerPhotos]);

  useEffect(() => {
    if (!qrOpen || !org?.id) return;
    let active = true;
    QRCode.toDataURL(`https://banbe.app/org/${org.id}`, { margin: 1, width: 220, color: { dark: '#000000', light: '#FFFFFF' } })
      .then(url => { if (active) setQrSrc(url); });
    return () => { active = false; };
  }, [qrOpen, org?.id]);

  const onPickAvatar = (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    if (avatarPreview) URL.revokeObjectURL(avatarPreview);
    setAvatarFile(file);
    setAvatarPreview(URL.createObjectURL(file));
  };
  const doSave = async () => {
    await saveOrganizerProfile(avatarFile);
    setEditing(false);
    setAvatarFile(null);
    if (avatarPreview) { URL.revokeObjectURL(avatarPreview); setAvatarPreview(''); }
  };

  if (s.organizerProfileLoading) {
    return <div style={{ minHeight: '100%', background: paper }} data-screen-label="Organizer profile" />;
  }
  if (s.organizerProfileError || !org) {
    return (
      <div style={{ minHeight: '100%', background: paper, display: 'flex', flexDirection: 'column' }} data-screen-label="Organizer profile">
        <div style={{ padding: '66px 20px 0' }}>
          <span onClick={backFromOrganizerProfile} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>{T('‹ Quay lại', '‹ Back')}</span>
        </div>
        <p style={{ textAlign: 'center', fontSize: 13, color: ink, marginTop: 60 }}>{s.organizerProfileError}</p>
      </div>
    );
  }

  // Photo identity fix (carried over from the retired Organizer screen) —
  // this grid spans the organizer's OTHER events too, so every photo carries
  // its own real `event_id` for PhotoViewer's "save event" action.
  const orgPhotos = (s.organizerPhotos || []).map(p => ({ id: p.id, url: organizerPhotoUrl(p.storage_path, p.r2_ref), eventId: p.event_id }));
  const monogram = (org.name || '?').trim()[0]?.toUpperCase() || '?';
  const avatarSrc = avatarPreview || organizerAvatarUrl(org.avatar_path, org.avatar_r2_ref || (org.id === s.myOrganizerId ? s.myOrganizerAvatarR2Ref : ''));

  return (
    <div style={{ minHeight: '100%', background: paper, display: 'flex', flexDirection: 'column' }} data-screen-label="Organizer profile">
      <div style={{ padding: '66px 20px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span onClick={backFromOrganizerProfile} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>{T('‹ Quay lại', '‹ Back')}</span>
        <span onClick={() => setShareCardOpen(true)} data-testid="organizer-profile-share" style={{ fontSize: 12, fontWeight: 600, color: ink, cursor: 'pointer' }}>
          {T('Chia sẻ', 'Share')}
        </span>
      </div>

      {s.arrivedFromSharedLink && s.eventKey && (
        // Only shown to someone who followed a shared "?org=" link (kept
        // from the retired Organizer screen). The banbe:// scheme opens the
        // installed app straight to this host; there's no App Store listing
        // to fall back to yet, so the second line points at the web app
        // someone is already looking at rather than at a link that would 404.
        <div style={{ ...cardGlass({ margin: '14px 20px 0', padding: '14px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12 }) }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
            <span style={{ fontSize: 13, color: ink }}>{T('Xem trong ứng dụng banbe', 'Open in the banbe app')}</span>
            <span style={{ fontSize: 11.5, lineHeight: 1.45, color: ink, opacity: 0.7 }}>{T('Chưa có ứng dụng? Bạn vẫn xem được mọi thứ ngay tại đây.', "Don't have it? Everything here works in the browser too.")}</span>
          </div>
          <a
            href={`banbe://organizer/${s.eventKey}`}
            style={{ flex: 'none', fontSize: 12, fontWeight: 600, color: paper, background: ink, borderRadius: 999, padding: '9px 16px', textDecoration: 'none' }}
          >{T('Mở', 'Open')}</a>
        </div>
      )}

      {/* iPhone fix pass (2026-09-27), Item 3 — top margin bumped 20→22 to
          match the same gap Account.jsx's own profile/org cards already
          use above their back/share-adjacent rows (an existing spacing
          value, not a new one), giving this row and the card a touch more
          breathing room. */}
      {/* Same identity card as the personal profile (note 68): left-aligned, full width, ring avatar, name as the
          largest text, a role line, the about text, then the stats strip inside the card; Follow under it. */}
      <div data-testid="organizer-profile-card" style={{ margin: `${SPACE.s}px 16px 0`, padding: 20, borderRadius: 20, color: ink, display: 'flex', flexDirection: 'column', gap: SPACE.m,
        background: `radial-gradient(circle at 100% 0%, rgba(var(--bb-clay-rgb), ${CARD_GLOW}), transparent 60%), ${surface2}`, boxShadow: 'inset 0 0 0 1px rgba(var(--bb-fg-rgb),0.06)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: SPACE.l }}>
          <span aria-hidden style={{ flex: 'none', width: 80, height: 80, borderRadius: '50%', padding: 2, background: `linear-gradient(135deg, ${clay}, ${attn})`, boxSizing: 'border-box' }}>
            <span style={{ display: 'block', width: '100%', height: '100%', borderRadius: '50%', padding: 2, background: paper, boxSizing: 'border-box' }}>
              {avatarSrc ? (
                <img src={avatarSrc} alt="" data-testid="organizer-profile-avatar" style={{ display: 'block', width: '100%', height: '100%', borderRadius: '50%', objectFit: 'cover' }} />
              ) : (
                <span style={{ display: 'flex', width: '100%', height: '100%', borderRadius: '50%', background: ink, color: paper, alignItems: 'center', justifyContent: 'center', fontSize: 26, fontWeight: 600 }}>{monogram}</span>
              )}
            </span>
          </span>
          <div style={{ minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
            <span style={{ ...display(26, { lineHeight: 1.15 }), overflowWrap: 'anywhere' }} data-testid="organizer-profile-name">{org.name}</span>
            <span style={{ fontSize: 13, color: ink2 }}>{T('Host', 'Host')}{org.verified ? ` · ✓ ${T('Đã xác minh', 'Verified')}` : ''}</span>
            {/* Derived from the earliest real published (live/ended) event — never the free-text hosting_since column
                (get_organizer_profile, migration 095); nothing published yet gets an honest line, never a made-up year. */}
            {!org.hosting_since_year && <span style={{ fontSize: 13, color: ink2 }}>{T('Chưa có sự kiện công khai nào', 'No published events yet')}</span>}
          </div>
        </div>
        {org.about && <p style={{ fontSize: 15, lineHeight: 1.45, color: ink, margin: 0 }}>{org.about}</p>}
        <div data-testid="organizer-profile-stats" style={{ display: 'flex', borderTop: `1px solid ${divider}`, paddingTop: SPACE.m }}>
          {[[org.event_count ?? 0, T('Sự kiện', 'Events')], [org.follower_count ?? 0, T('Người theo dõi', 'Followers')],
            ...(org.hosting_since_year ? [[org.hosting_since_year, T('Từ năm', 'Since')]] : [])].map(([v, l], i) => (
            <div key={l} style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2, paddingLeft: i ? SPACE.m : 0, borderLeft: i ? `1px solid ${divider}` : 'none' }}>
              <span style={{ fontSize: 17, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{v}</span>
              <span style={{ fontSize: 13, color: ink2 }}>{l}</span>
            </div>
          ))}
        </div>
        {!isOwner && s.user?.id && (
          <div
            onClick={() => toggleFollowOrganizer(org.id)}
            data-testid="organizer-profile-follow"
            role="button"
            aria-pressed={following}
            style={{
              minHeight: 44, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, fontWeight: 600, borderRadius: RADIUS.pill, cursor: 'pointer',
              background: following ? 'transparent' : ink, color: following ? ink : paper,
              border: following ? `1px solid ${rule}` : 'none',
            }}
          >
            {following ? <><span aria-hidden="true">✓ </span>{T('Đang theo dõi', 'Following')}</> : T('Theo dõi', 'Follow')}
          </div>
        )}
        {!isOwner && s.followWriteError && (
          <span role="alert" data-testid="organizer-profile-follow-error" style={{ fontSize: 13, color: alert }}>{s.followWriteError}</span>
        )}
      </div>

      {(org.intro_long || (org.social_links || []).length > 0) && (
        <section style={{ margin: `${SPACE.xl}px 16px 0`, display: 'flex', flexDirection: 'column', gap: SPACE.s, alignItems: 'flex-start' }}>
          <span style={display(17, { lineHeight: 1.3 })}>{T('Giới thiệu', 'About')}</span>
          {/* Organizer Team pass (2026-09-27, Stage 3) — a SEPARATE long-form intro; org.about is untouched. */}
          <LongIntroPreview T={T} text={org.intro_long} />
          <SocialLinksRow links={org.social_links} />
        </section>
      )}

      {/* Organizer Team pass (2026-09-27, Stage 2) — a prominent, large
          tappable row using the organizer's own real name (never the
          founder's personal name — that stays governed entirely by the
          founder's OWN personal-profile organizer_mode toggle, an
          unrelated mechanism this label never touches). Opens the public
          Team page (get_organizer_team, 098/101) — accepted AND
          public_visible members only.
          iPhone fix pass (2026-09-27), Item 2 — moved to be the FIRST
          action directly below the card, ahead of the QR/edit rows below
          (was after QR) — same row, same real member logic, no
          duplication, just reordered. */}
      <div
        onClick={() => openOrganizerTeam(org.id, 'organizerProfile')}
        data-testid="organizer-profile-team-row"
        style={{ margin: `${SPACE.xl}px 16px 0`, padding: `${SPACE.m}px ${SPACE.l}px`, minHeight: 44, boxSizing: 'border-box', borderRadius: RADIUS.card, background: surface2, display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }}
      >
        <span style={{ fontSize: 15, fontWeight: 600, color: ink }}>{T(`Bởi ${org.name} Team`, `By the ${org.name} Team`)}</span>
        <span aria-hidden style={{ fontSize: 20, color: ink, opacity: 0.55 }}>›</span>
      </div>

      <div onClick={() => setQrOpen(true)} data-testid="organizer-profile-qr-cta" role="button" style={{ margin: `${SPACE.m}px 16px 0`, minHeight: 44, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, fontWeight: 600, color: ink, background: surface2, borderRadius: RADIUS.pill, cursor: 'pointer' }}>
        {T('Hiển thị mã QR tổ chức', "Show the organizer's QR code")}
      </div>

      {/* Owner only — edits organizers.name/about/avatar_path (migration
          090's update_organizer_profile), never profiles.* / save_profile().
          `org.id === s.myOrganizerId` gates this, never a personal-profile
          check — there's no such concept on this screen. */}
      {isOwner && (
        <div style={{ margin: `${SPACE.s}px 16px 0` }}>
          {editing ? (
            <div style={{ ...cardGlass({ padding: 16, display: 'flex', flexDirection: 'column', gap: 10 }) }} data-testid="organizer-profile-edit-card">
              <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
                <div
                  onClick={() => avatarInputRef.current?.click()}
                  style={{ flex: 'none', width: 52, height: 52, borderRadius: 12, overflow: 'hidden', cursor: 'pointer', background: 'rgba(0,0,0,0.05)' }}
                >
                  {avatarSrc && <img src={avatarSrc} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />}
                </div>
                <span onClick={() => avatarInputRef.current?.click()} style={{ fontSize: 12, color: ink, textDecoration: 'underline', cursor: 'pointer' }}>{T('Đổi ảnh', 'Change photo')}</span>
                <input ref={avatarInputRef} type="file" accept="image/jpeg,image/png,image/webp" data-testid="organizer-profile-avatar-input" style={{ display: 'none' }} onChange={onPickAvatar} />
              </div>
              <input
                value={s.orgRegName} onChange={orgRegNameType} data-testid="organizer-profile-name-input"
                style={{ fontSize: 14, fontWeight: 600, color: ink, border: `1px solid ${rule}`, borderRadius: 10, padding: '9px 11px', outline: 'none' }}
              />
              <textarea
                value={s.orgRegDesc} onChange={orgRegDescType} rows={3} maxLength={2000}
                placeholder={T('Giới thiệu ngắn về bạn/nhóm tổ chức…', 'A short introduction to you/your host team…')}
                data-testid="organizer-profile-intro-input"
                style={{ fontSize: 13, color: ink, border: `1px solid ${rule}`, borderRadius: 10, padding: '10px 12px', outline: 'none', resize: 'vertical', lineHeight: 1.5 }}
              />
              {/* Organizer Team pass (2026-09-27, Stage 3) — a SEPARATE
                  long-form intro, never overwriting orgRegDesc above. */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>{T('Giới thiệu chi tiết (không bắt buộc)', 'Long-form intro (optional)')}</span>
                <textarea
                  value={s.orgRegIntroLong} onChange={orgRegIntroLongType} rows={5} maxLength={4000}
                  data-testid="organizer-profile-intro-long-input"
                  style={{ fontSize: 13, color: ink, border: `1px solid ${rule}`, borderRadius: 10, padding: '10px 12px', outline: 'none', resize: 'vertical', lineHeight: 1.5 }}
                />
              </div>
              <SocialLinksEditor
                T={T} links={s.orgRegLinks} open={s.orgRegLinksOpen}
                onToggleOpen={toggleOrgRegLinksOpen} onAdd={addOrgRegLink}
                onSetField={setOrgRegLink} onRemove={removeOrgRegLink}
                testPrefix="organizer-profile-link"
              />
              <div style={{ display: 'flex', gap: 8 }}>
                <span
                  onClick={doSave}
                  data-testid="organizer-profile-save"
                  style={{ flex: 1, textAlign: 'center', fontSize: 12.5, fontWeight: 600, color: paper, background: ink, padding: '10px 0', borderRadius: 10, cursor: 'pointer', opacity: s.orgProfileSaving ? 0.6 : 1 }}
                >
                  {s.orgProfileSaving ? T('Đang lưu…', 'Saving…') : T('Lưu', 'Save')}
                </span>
                <span onClick={() => setEditing(false)} style={{ flex: 1, textAlign: 'center', fontSize: 12.5, fontWeight: 600, color: ink, padding: '10px 0', borderRadius: 10, cursor: 'pointer', border: `1px solid ${rule}` }}>
                  {T('Huỷ', 'Cancel')}
                </span>
              </div>
              {s.orgProfileError && <p style={{ fontSize: 11.5, color: alert, margin: 0 }}>{s.orgProfileError}</p>}
            </div>
          ) : (
            <div onClick={() => setEditing(true)} data-testid="organizer-profile-edit" role="button" style={{ minHeight: 44, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, fontWeight: 600, color: ink, background: surface2, borderRadius: RADIUS.pill, cursor: 'pointer' }}>
              {T('Chỉnh sửa hồ sơ tổ chức', "Edit organizer profile")}
            </div>
          )}
        </div>
      )}

      {!!s.organizerProfileUpcoming.length && (
        <div style={{ margin: '22px 20px 0' }}>
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Sự kiện sắp tới', 'Upcoming events')}</span>
          <div style={{ display: 'flex', flexDirection: 'column', marginTop: 8 }}>
            {s.organizerProfileUpcoming.map((e, i, arr) => (
              <div key={e.key} onClick={() => goEvent(e.key)} style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '10px 0', borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none', cursor: 'pointer' }}>
                <div style={bg(e.img, { flex: 'none', width: 48, height: 48, borderRadius: 10 })} />
                <span style={{ ...display(14, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{e.name}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {!!s.organizerProfilePast.length && (
        <div style={{ margin: '22px 20px 0' }}>
          <div
            role="button"
            aria-expanded={pastOpen}
            data-testid="organizer-past-toggle"
            onClick={() => setPastOpen(o => !o)}
            style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}
          >
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Sự kiện đã qua', 'Past events')}</span>
            <span style={{ fontSize: 11, fontWeight: 600, color: ink, background: 'rgba(27,25,22,0.08)', borderRadius: 999, padding: '2px 7px' }}>{s.organizerProfilePast.length}</span>
            <span style={{ marginLeft: 'auto', fontSize: 11, color: ink, display: 'inline-block', transform: pastOpen ? 'rotate(180deg)' : 'none', transition: 'transform .2s' }}>▾</span>
          </div>
          {pastOpen && (
            <div style={{ display: 'flex', flexDirection: 'column', marginTop: 8 }}>
              {s.organizerProfilePast.map((e, i, arr) => (
                <div key={e.key} onClick={() => goEvent(e.key)} style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '10px 0', borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none', cursor: 'pointer' }}>
                  <div style={bg(e.img, { flex: 'none', width: 48, height: 48, borderRadius: 10 })} />
                  <span style={{ ...display(14, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{e.name}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      <div style={{ margin: '22px 20px 30px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <span style={{ fontSize: 11.5, color: ink }}>{T('Ảnh của', 'Photos by')} {org.name}</span>
          <span style={{ fontSize: 11, color: ink }}>{T('do người tổ chức đăng', 'posted by the organizer')}</span>
        </div>
        {/* STAGE B (2026-09-25) — real event_photos rows (loadOrganizerPhotos
            above), not the static demo `orgGallery` this used to render.
            Scoped server-query-side to live+public events for a visitor,
            every one of the organizer's own events (any status, Task 1's
            own "ended must stay in the library" rule) for the owner. A
            genuinely empty result shows plain text, never a fake/demo
            photo standing in for a real one. (Moved here unchanged from
            the retired Organizer screen.) */}
        {s.organizerPhotosLoading ? (
          <p style={{ fontSize: 12.5, color: ink, opacity: 0.6, margin: '14px 0 0' }}>{T('Đang tải…', 'Loading…')}</p>
        ) : orgPhotos.length ? (
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 6, marginTop: 14 }}>
            {orgPhotos.map((p, i) => (
              <div key={p.id} data-photo-thumb={p.id} onClick={(e) => openPhoto(orgPhotos, i, org.name, e.currentTarget.getBoundingClientRect())} style={{ position: 'relative', cursor: 'pointer' }}>
                <div style={bg(p.url, { width: '100%', height: 158 })} />
                {s.photoEngagement[p.id]?.likedByMe && (
                  <span style={{ position: 'absolute', top: 8, right: 8, color: '#fff', filter: 'drop-shadow(0 1px 2px rgba(0,0,0,0.55))', pointerEvents: 'none' }}>
                    <svg width={15} height={15} viewBox="0 0 24 24" fill="currentColor"><path d="M12 20.5S3.5 15 3.5 9.2A4.7 4.7 0 0 1 12 6.5a4.7 4.7 0 0 1 8.5 2.7c0 5.8-8.5 11.3-8.5 11.3Z" /></svg>
                  </span>
                )}
              </div>
            ))}
          </div>
        ) : (
          <p style={{ fontSize: 12.5, color: ink, opacity: 0.6, margin: '14px 0 0' }}>{T('Người tổ chức chưa đăng ảnh nào.', 'This organizer hasn’t posted any photos yet.')}</p>
        )}
      </div>

      {qrOpen && (
        <div onClick={() => setQrOpen(false)} style={{ position: 'fixed', inset: 0, background: 'rgba(27,25,22,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 50 }}>
          <div onClick={(e) => e.stopPropagation()} style={{ background: paper, borderRadius: 20, padding: 24, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
            {qrSrc ? <img src={qrSrc} alt="QR" style={{ width: 220, height: 220 }} /> : <div style={{ width: 220, height: 220 }} />}
            <span style={{ fontSize: 12, color: ink }}>{org.name}</span>
          </div>
        </div>
      )}

      <ProfileShareSheet
        open={shareCardOpen}
        onClose={() => setShareCardOpen(false)}
        kindLabel={T('Tổ chức', 'Host')}
        name={org.name || ''}
        subtitle={T(`${org.event_count ?? 0} sự kiện · ${org.follower_count ?? 0} người theo dõi`, `${org.event_count ?? 0} events · ${org.follower_count ?? 0} followers`)}
        detail={org.about || ''}
        avatarUrl={organizerAvatarUrl(org.avatar_path, org.avatar_r2_ref || (org.id === s.myOrganizerId ? s.myOrganizerAvatarR2Ref : ''))}
        roundAvatar={false}
        link={profileShareLinks().host(org.id)}
        idPrefix="organizer-profile-share-card"
        kind="host"
        publishId={org.id}
        isOwner={isCardOwner}
      />

      {s.profileLinkCopiedFlash && (
        <p style={{ textAlign: 'center', fontSize: 11.5, color: ink, opacity: 0.7, margin: '10px 0 0' }}>{T('Đã sao chép link tổ chức', "Organizer link copied")}</p>
      )}
    </div>
  );
}

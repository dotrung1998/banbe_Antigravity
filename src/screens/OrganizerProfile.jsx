import { useEffect, useRef, useState } from 'react';
import QRCode from 'qrcode';
import { useGoc } from '../state/GocContext.jsx';
import { supabase } from '../lib/supabase.js';
import { paper, ink, rule, alert, display, cardGlass } from '../theme.js';
import { bg } from '../data/events.js';
import { SocialLinksEditor } from './SocialLinksEditor.jsx';
import { LongIntroPreview, SocialLinksRow } from './LongIntro.jsx';

function organizerAvatarUrl(path) {
  if (!path) return '';
  return supabase.storage.from('organizer-photos').getPublicUrl(path).data.publicUrl;
}
function organizerPhotoUrl(path) {
  const relative = (path || '').replace(/^event-photos\//, '');
  return supabase.storage.from('event-photos').getPublicUrl(relative).data.publicUrl;
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
    loadOrganizerProfileExtras, goEvent, orgRegNameType, orgRegDescType, saveOrganizerProfile,
    openOrganizerTeam,
    orgRegIntroLongType, toggleOrgRegLinksOpen, addOrgRegLink, setOrgRegLink, removeOrgRegLink,
  } = useGoc();
  const s = state;
  const [qrOpen, setQrOpen] = useState(false);
  const [qrSrc, setQrSrc] = useState(null);
  const [editing, setEditing] = useState(false);
  const [avatarFile, setAvatarFile] = useState(null);
  const [avatarPreview, setAvatarPreview] = useState('');
  const avatarInputRef = useRef(null);
  const org = s.organizerProfile;
  const isOwner = !!(org && org.id === s.myOrganizerId);

  useEffect(() => {
    if (s.organizerProfileId) loadOrganizerProfileExtras(s.organizerProfileId);
  }, [s.organizerProfileId, loadOrganizerProfileExtras]);

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

  const monogram = (org.name || '?').trim()[0]?.toUpperCase() || '?';
  const avatarSrc = avatarPreview || organizerAvatarUrl(org.avatar_path);

  return (
    <div style={{ minHeight: '100%', background: paper, display: 'flex', flexDirection: 'column' }} data-screen-label="Organizer profile">
      <div style={{ padding: '66px 20px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span onClick={backFromOrganizerProfile} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>{T('‹ Quay lại', '‹ Back')}</span>
        <span onClick={() => shareOrganizerProfile(org.id, org.name)} data-testid="organizer-profile-share" style={{ fontSize: 12, fontWeight: 600, color: ink, cursor: 'pointer' }}>
          {T('Chia sẻ', 'Share')}
        </span>
      </div>

      {/* iPhone fix pass (2026-09-27), Item 3 — top margin bumped 20→22 to
          match the same gap Account.jsx's own profile/org cards already
          use above their back/share-adjacent rows (an existing spacing
          value, not a new one), giving this row and the card a touch more
          breathing room. */}
      <div data-testid="organizer-profile-card" style={{ ...cardGlass({ margin: '22px 20px 0', padding: '28px 22px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }) }}>
        {avatarSrc ? (
          <img src={avatarSrc} alt="" style={{ width: 88, height: 88, borderRadius: 20, objectFit: 'cover', border: `3px solid ${paper}` }} />
        ) : (
          <div style={{ width: 88, height: 88, borderRadius: 20, background: ink, color: paper, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 32, fontWeight: 700, border: `3px solid ${paper}` }}>
            {monogram}
          </div>
        )}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ ...display(21) }} data-testid="organizer-profile-name">{org.name}</span>
          {org.verified && <span style={{ fontSize: 11, fontWeight: 600, color: ink, opacity: 0.7 }}>✓ {T('Đã xác minh', 'Verified')}</span>}
        </div>
        {org.about && <p style={{ fontSize: 12.5, lineHeight: 1.5, color: ink, textAlign: 'center', margin: '4px 0 0' }}>{org.about}</p>}
        {/* Organizer Team pass (2026-09-27, Stage 3) — a SEPARATE
            long-form intro; org.about (the short one) is untouched. */}
        <LongIntroPreview T={T} text={org.intro_long} />
        <SocialLinksRow links={org.social_links} />

        <div style={{ display: 'flex', gap: 20, marginTop: 10 }}>
          <Stat value={org.event_count} label={T('Sự kiện', 'Events')} />
          <Stat value={org.follower_count} label={T('Người theo dõi', 'Followers')} />
        </div>
        {/* Derived from the earliest real published (live/ended) event —
            never the organizer's own free-text hosting_since column,
            which nothing ever actually sets (get_organizer_profile,
            migration 095). An organizer with nothing published yet gets
            an honest empty line, never a fabricated year. */}
        <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>
          {org.hosting_since_year
            ? T(`Tổ chức từ ${org.hosting_since_year}`, `Hosting since ${org.hosting_since_year}`)
            : T('Chưa có sự kiện công khai nào', 'No published events yet')}
        </span>

        {!isOwner && s.user?.id && (
          <div
            onClick={() => toggleFollowOrganizer(org.id)}
            data-testid="organizer-profile-follow"
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
        style={{ ...cardGlass({ margin: '16px 20px 0', padding: '16px 18px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }) }}
      >
        <span style={{ fontSize: 14, fontWeight: 600, color: ink }}>{T(`Bởi ${org.name} Team`, `By the ${org.name} Team`)}</span>
        <span aria-hidden style={{ fontSize: 20, color: ink, opacity: 0.55 }}>›</span>
      </div>

      <div onClick={() => setQrOpen(true)} data-testid="organizer-profile-qr-cta" style={{ margin: '12px 20px 0', textAlign: 'center', fontSize: 12.5, fontWeight: 600, color: ink, padding: '13px 0', border: `1px solid ${rule}`, borderRadius: 12, cursor: 'pointer' }}>
        {T('Hiển thị mã QR tổ chức', "Show the organizer's QR code")}
      </div>

      {/* Owner only — edits organizers.name/about/avatar_path (migration
          090's update_organizer_profile), never profiles.* / save_profile().
          `org.id === s.myOrganizerId` gates this, never a personal-profile
          check — there's no such concept on this screen. */}
      {isOwner && (
        <div style={{ margin: '10px 20px 0' }}>
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
                <input ref={avatarInputRef} type="file" accept="image/jpeg,image/png,image/webp" style={{ display: 'none' }} onChange={onPickAvatar} />
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
            <div onClick={() => setEditing(true)} data-testid="organizer-profile-edit" style={{ textAlign: 'center', fontSize: 12.5, fontWeight: 600, color: ink, padding: '13px 0', border: `1px solid ${rule}`, borderRadius: 12, cursor: 'pointer' }}>
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

      {!!s.organizerProfilePhotos.length && (
        <div style={{ margin: '22px 20px 30px' }}>
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Ảnh', 'Photos')}</span>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 6, marginTop: 8 }}>
            {s.organizerProfilePhotos.map(p => (
              <div key={p.id} style={bg(organizerPhotoUrl(p.storage_path), { width: '100%', height: 100, borderRadius: 8 })} />
            ))}
          </div>
        </div>
      )}

      {qrOpen && (
        <div onClick={() => setQrOpen(false)} style={{ position: 'fixed', inset: 0, background: 'rgba(27,25,22,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 50 }}>
          <div onClick={(e) => e.stopPropagation()} style={{ background: paper, borderRadius: 20, padding: 24, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
            {qrSrc ? <img src={qrSrc} alt="QR" style={{ width: 220, height: 220 }} /> : <div style={{ width: 220, height: 220 }} />}
            <span style={{ fontSize: 12, color: ink }}>{org.name}</span>
          </div>
        </div>
      )}

      {s.profileLinkCopiedFlash && (
        <p style={{ textAlign: 'center', fontSize: 11.5, color: ink, opacity: 0.7, margin: '10px 0 0' }}>{T('Đã sao chép link tổ chức', "Organizer link copied")}</p>
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

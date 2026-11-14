// Host profile in the v2.3 look (note 81, switch home_v23), from the prototype's host profile: a centred face with a
// clay ring that springs in, the name in the serif, a role line and tags, a stats block (events · followers · since),
// two actions (the one that matters most is primary: Follow for a visitor, Edit profile for the owner; Share beside
// it), then About, Upcoming as v2.3 event rows, Past (collapsed) and the photos. The rarer actions (QR code, the team
// page, copying the link) sit in a ⋯ menu at the top right next to Share, so the page shows only the important ones.
// Presentational: OrganizerProfile.jsx owns the data and handlers.
import { useState } from 'react';
import { bg } from '../../data/events.js';
import { SERIF } from '../event/v23Style.js';
import GlassMenu, { GlassMenuItem } from '../GlassMenu.jsx';
import EventRowV23 from '../list/EventRowV23.jsx';

const CSS = `
@keyframes bbHpFace { from { opacity: 0; transform: scale(.7); } to { opacity: 1; transform: none; } }
@keyframes bbHpRise { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: none; } }
.bb-hp-face { animation: bbHpFace .56s cubic-bezier(.2,1.04,.3,1) both; }
.bb-hp-rise { animation: bbHpRise .38s cubic-bezier(.2,.9,.3,1) both; }
.bb-hp-btn { transition: transform .11s cubic-bezier(.22,.61,.36,1), background-color .18s, color .18s; }
.bb-hp-btn:active { transform: scale(.96); }
@media (prefers-reduced-motion: reduce) { .bb-hp-face, .bb-hp-rise { animation: none; } }
`;
const ico = { fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round', viewBox: '0 0 24 24', 'aria-hidden': true };
const IconBack = () => (<svg {...ico} width={19} height={19} strokeWidth={2}><path d="m15 5-7 7 7 7" /></svg>);
const IconShare = () => (<svg {...ico} width={19} height={19}><path d="M12 16V4M12 4 8 8M12 4l4 4" /><path d="M5 14v5a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-5" /></svg>);
const IconMore = () => (<svg {...ico} width={19} height={19}><circle cx="5.5" cy="12" r="1.3" fill="currentColor" /><circle cx="12" cy="12" r="1.3" fill="currentColor" /><circle cx="18.5" cy="12" r="1.3" fill="currentColor" /></svg>);
const IconQr = () => (<svg {...ico} width={18} height={18}><rect x="4" y="4" width="6" height="6" rx="1" /><rect x="14" y="4" width="6" height="6" rx="1" /><rect x="4" y="14" width="6" height="6" rx="1" /><path d="M14 14h2v2h-2zM18 18h2v2h-2z" /></svg>);
const IconTeam = () => (<svg {...ico} width={18} height={18}><circle cx="9" cy="9" r="3.2" /><path d="M3.5 19c.9-3 3-4.5 5.5-4.5s4.6 1.5 5.5 4.5" /><circle cx="17" cy="8" r="2.5" /><path d="M16 13.6c2.2.2 3.8 1.6 4.5 4" /></svg>);
const IconLink = () => (<svg {...ico} width={18} height={18}><path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1" /><path d="M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1" /></svg>);
const IconPlus = () => (<svg {...ico} width={16} height={16} strokeWidth={2.2}><path d="M12 6v12M6 12h12" /></svg>);
const IconCheck = () => (<svg {...ico} width={16} height={16} strokeWidth={2.2}><path d="m6 12.5 4 4 8-9" /></svg>);
const IconEdit = () => (<svg {...ico} width={16} height={16}><path d="M4 20h4L19 9l-4-4L4 16v4Z" /><path d="m13.5 6.5 4 4" /></svg>);
const IconChev = ({ open }) => (<svg {...ico} width={14} height={14} style={{ transform: open ? 'rotate(180deg)' : 'none', transition: 'transform .28s cubic-bezier(.2,1.04,.3,1)' }}><path d="m6 9 6 6 6-6" /></svg>);

const circle = { width: 44, height: 44, borderRadius: '50%', border: 'none', background: 'var(--bb-surface-2)', color: 'var(--bb-fg)', display: 'grid', placeItems: 'center', cursor: 'pointer', padding: 0, flex: 'none' };
const H = ({ children, action }) => (
  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, margin: '0 0 10px' }}>
    <h2 style={{ margin: 0, fontSize: 11, letterSpacing: '0.13em', textTransform: 'uppercase', color: 'var(--bb-fg-3)', fontWeight: 700 }}>{children}</h2>
    {action}
  </div>
);

export default function OrganizerProfileV23(p) {
  const { T, org, avatarSrc, monogram, isOwner, following, followError, onBack, onFollow, onShare, onCopyLink, onQr, onTeam, editing, onEdit, editCard,
    upcoming, past, toRow, onOpenEvent, photos, photosLoading, onOpenPhoto, likedOf, aboutExtra, overlays, guest } = p;
  const [menuOpen, setMenuOpen] = useState(false);
  const [pastOpen, setPastOpen] = useState(false);
  const areas = [...new Set(upcoming.map(e => e.area).filter(Boolean))].slice(0, 3);
  const stats = [
    [org.event_count ?? 0, T('Sự kiện', 'Events')],
    [org.follower_count ?? 0, T('Người theo dõi', 'Followers')],
    ...(org.hosting_since_year ? [[org.hosting_since_year, T('Từ năm', 'Since')]] : [[upcoming.length, T('Sắp tới', 'Upcoming')]]),
  ];
  // The stats and the two actions rise in one after another (45 ms apart), like the prototype.
  const delay = (i) => ({ animationDelay: `${120 + i * 45}ms` });
  const primary = isOwner
    ? { testId: 'organizer-profile-edit', onClick: onEdit, icon: <IconEdit />, label: T('Sửa hồ sơ', 'Edit profile'), solid: !editing }
    : { testId: 'organizer-profile-follow', onClick: onFollow, icon: following ? <IconCheck /> : <IconPlus />, label: following ? T('Đang theo dõi', 'Following') : T('Theo dõi', 'Follow'), solid: !following, pressed: following };

  return (
    <div className="bbv23" data-screen-label="Organizer profile" data-testid="organizer-profile-v23" style={{ minHeight: '100%', background: 'var(--bb-bg)', color: 'var(--bb-fg)', paddingBottom: 40 }}>
      <style>{CSS}</style>
      <div style={{ padding: 'max(12px, calc(58px - var(--bb-status-trim, 0px))) 16px 0', display: 'flex', alignItems: 'center', gap: 8 }}>
        <button type="button" onClick={onBack} aria-label={T('Quay lại', 'Back')} data-testid="organizer-profile-back" className="bb-hp-btn" style={circle}><IconBack /></button>
        <span style={{ flex: 1 }} />
        <button type="button" onClick={onShare} aria-label={T('Chia sẻ', 'Share')} data-testid="organizer-profile-share" className="bb-hp-btn" style={circle}><IconShare /></button>
        <GlassMenu open={menuOpen} onOpenChange={setMenuOpen} top={50} label={T('Thêm', 'More')} menuTestId="organizer-profile-menu"
          trigger={<button type="button" onClick={() => setMenuOpen(o => !o)} aria-haspopup="menu" aria-expanded={menuOpen} aria-label={T('Thêm', 'More')} data-testid="organizer-profile-more" className="bb-hp-btn" style={circle}><IconMore /></button>}>
          <GlassMenuItem icon={<IconQr />} onClick={onQr} testId="organizer-profile-qr-cta">{T('Mã QR tổ chức', 'Host QR code')}</GlassMenuItem>
          <GlassMenuItem icon={<IconTeam />} onClick={onTeam} testId="organizer-profile-team-row">{T(`Đội ngũ ${org.name}`, `The ${org.name} team`)}</GlassMenuItem>
          <GlassMenuItem icon={<IconLink />} onClick={onCopyLink} testId="organizer-profile-copy-link">{T('Sao chép link', 'Copy link')}</GlassMenuItem>
        </GlassMenu>
      </div>

      <div data-testid="organizer-profile-card" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', padding: '6px 20px 18px' }}>
        <span className="bb-hp-face" style={{ width: 88, height: 88, borderRadius: '50%', overflow: 'hidden', flex: 'none', boxShadow: '0 0 0 4px var(--bb-bg), 0 0 0 5.5px color-mix(in srgb, var(--bb-clay) 45%, transparent)', background: 'var(--bb-clay)', color: '#fff', display: 'grid', placeItems: 'center', fontSize: 32, fontWeight: 600 }}>
          {avatarSrc ? <img src={avatarSrc} alt="" data-testid="organizer-profile-avatar" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : monogram}
        </span>
        <h1 data-testid="organizer-profile-name" style={{ fontFamily: SERIF, fontSize: 30, fontWeight: 400, letterSpacing: '-0.02em', lineHeight: 1.1, margin: '16px 0 4px', overflowWrap: 'anywhere' }}>{org.name}</h1>
        <span style={{ fontSize: 13, color: 'var(--bb-fg-2)' }}>
          {[T('Chủ nhà', 'Host'), org.hosting_since_year ? T(`từ ${org.hosting_since_year}`, `since ${org.hosting_since_year}`) : T('chưa có sự kiện công khai', 'no published events yet'), org.verified ? `✓ ${T('Đã xác minh', 'Verified')}` : null].filter(Boolean).join(' · ')}
        </span>
        {(areas.length > 0 || upcoming.length > 0) && (
          <span style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'center', gap: 6, marginTop: 12 }}>
            {areas.map(a => <span key={a} style={{ height: 28, padding: '0 11px', borderRadius: 999, background: 'var(--bb-surface-2)', fontSize: 12, fontWeight: 600, display: 'inline-flex', alignItems: 'center' }}>{a}</span>)}
            {upcoming.length > 0 && <span style={{ height: 28, padding: '0 11px', borderRadius: 999, background: 'var(--bb-surface-2)', fontSize: 12, fontWeight: 600, display: 'inline-flex', alignItems: 'center' }}>{T(`${upcoming.length} sắp tới`, `${upcoming.length} coming up`)}</span>}
          </span>
        )}
      </div>

      <div style={{ padding: '0 16px' }}>
        <div data-testid="organizer-profile-stats" style={{ display: 'grid', gridTemplateColumns: `repeat(${stats.length}, 1fr)`, borderRadius: 18, background: 'var(--bb-surface-2)', padding: '14px 4px', marginBottom: 14 }}>
          {stats.map(([v, l], i) => (
            <div key={l} className="bb-hp-rise" style={{ ...delay(i), textAlign: 'center', borderLeft: i ? '1px solid var(--bb-rule)' : 'none' }}>
              <b style={{ display: 'block', fontFamily: SERIF, fontSize: 23, fontWeight: 400, letterSpacing: '-0.02em', fontVariantNumeric: 'tabular-nums' }}>{v}</b>
              <small style={{ display: 'block', fontSize: 11, color: 'var(--bb-fg-3)', letterSpacing: '0.06em', textTransform: 'uppercase', marginTop: 2, fontWeight: 600 }}>{l}</small>
            </div>
          ))}
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, marginBottom: followError || editing ? 10 : 24 }}>
          <button type="button" data-testid={primary.testId} onClick={primary.onClick} aria-pressed={primary.pressed} className="bb-hp-btn bb-hp-rise"
            style={{ ...delay(stats.length), minHeight: 46, borderRadius: 999, fontFamily: 'inherit', fontSize: 14.5, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, cursor: 'pointer',
              border: primary.solid ? '1px solid transparent' : '1px solid var(--bb-rule)', background: primary.solid ? 'var(--bb-fg)' : 'transparent', color: primary.solid ? 'var(--bb-bg)' : 'var(--bb-fg)' }}>
            {primary.icon}{primary.label}
          </button>
          <button type="button" data-testid="organizer-profile-share-card" onClick={onShare} className="bb-hp-btn bb-hp-rise"
            style={{ ...delay(stats.length + 1), minHeight: 46, borderRadius: 999, border: '1px solid var(--bb-rule)', background: 'transparent', color: 'var(--bb-fg)', fontFamily: 'inherit', fontSize: 14.5, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, cursor: 'pointer' }}>
            <IconShare />{T('Chia sẻ', 'Share')}
          </button>
        </div>
        {followError && <p role="alert" data-testid="organizer-profile-follow-error" style={{ fontSize: 13, color: 'var(--bb-alert)', margin: '0 0 14px' }}>{followError}</p>}
        {guest && !isOwner && <p style={{ fontSize: 12.5, color: 'var(--bb-fg-3)', margin: '-14px 0 22px', textAlign: 'center' }}>{T('Đăng nhập để theo dõi chủ nhà này.', 'Sign in to follow this host.')}</p>}
        {editing && <div style={{ marginBottom: 24 }}>{editCard}</div>}

        {(org.about || aboutExtra) && (
          <section style={{ marginBottom: 24 }}>
            <H>{T('Giới thiệu', 'About')}</H>
            {org.about && <p style={{ fontSize: 14.5, lineHeight: 1.6, color: 'var(--bb-fg-2)', margin: 0 }}>{org.about}</p>}
            {aboutExtra && <div style={{ marginTop: 10, display: 'flex', flexDirection: 'column', gap: 8, alignItems: 'flex-start' }}>{aboutExtra}</div>}
          </section>
        )}
      </div>

      {upcoming.length > 0 && (
        <section style={{ marginBottom: 18 }} data-testid="organizer-profile-upcoming">
          <div style={{ padding: '0 16px' }}><H>{T('Sắp diễn ra', 'Coming up')}</H></div>
          {upcoming.map(e => <EventRowV23 key={e.key} row={toRow(e)} onOpen={() => onOpenEvent(e.key)} testId={`organizer-upcoming-${e.key}`} />)}
        </section>
      )}

      {past.length > 0 && (
        <section style={{ marginBottom: 18 }}>
          <div style={{ padding: '0 16px' }}>
            <H action={(
              <button type="button" onClick={() => setPastOpen(o => !o)} aria-expanded={pastOpen} data-testid="organizer-past-toggle"
                style={{ minHeight: 44, margin: '-12px 0', padding: 0, border: 'none', background: 'none', color: 'var(--bb-fg-2)', fontFamily: 'inherit', fontSize: 13, fontWeight: 600, display: 'inline-flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
                {pastOpen ? T('Thu gọn', 'Hide') : T(`Xem ${past.length}`, `Show ${past.length}`)}<IconChev open={pastOpen} />
              </button>
            )}>{T('Đã diễn ra', 'Past events')}</H>
          </div>
          {pastOpen && past.map(e => <EventRowV23 key={e.key} row={toRow(e, true)} onOpen={() => onOpenEvent(e.key)} testId={`organizer-past-${e.key}`} />)}
        </section>
      )}

      <section style={{ padding: '0 16px' }}>
        <H>{T('Ảnh', 'Photos')}{photos.length ? ` · ${photos.length}` : ''}</H>
        {photosLoading ? (
          <p style={{ fontSize: 13, color: 'var(--bb-fg-3)', margin: 0 }}>{T('Đang tải…', 'Loading…')}</p>
        ) : photos.length ? (
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
            {photos.map((ph, i) => (
              <div key={ph.id} data-photo-thumb={ph.id} role="button" aria-label={T(`Ảnh ${i + 1}`, `Photo ${i + 1}`)} onClick={(e) => onOpenPhoto(i, e.currentTarget.getBoundingClientRect())}
                style={bg(ph.url, { position: 'relative', height: 158, borderRadius: 14, cursor: 'pointer', backgroundColor: 'var(--bb-surface-2)' })}>
                {likedOf(ph.id) && (
                  <span style={{ position: 'absolute', top: 8, right: 8, color: '#fff', filter: 'drop-shadow(0 1px 2px rgba(0,0,0,0.55))' }}>
                    <svg width={15} height={15} viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M12 20.5S3.5 15 3.5 9.2A4.7 4.7 0 0 1 12 6.5a4.7 4.7 0 0 1 8.5 2.7c0 5.8-8.5 11.3-8.5 11.3Z" /></svg>
                  </span>
                )}
              </div>
            ))}
          </div>
        ) : (
          <p style={{ fontSize: 13, color: 'var(--bb-fg-3)', margin: 0 }}>{T('Chủ nhà chưa đăng ảnh nào.', 'This host hasn’t posted any photos yet.')}</p>
        )}
      </section>
      {overlays}
    </div>
  );
}

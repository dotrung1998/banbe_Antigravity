import { useEffect } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { EVENTS, bg } from '../data/events.js';
import { liveEventOverrides } from '../lib/countdown.js';
import { supabase } from '../lib/supabase.js';
import { paper, ink, rule, display, cardGlass, inkButton } from '../theme.js';

function organizerPhotoUrl(path) {
  const relative = path.replace(/^event-photos\//, '');
  return supabase.storage.from('event-photos').getPublicUrl(relative).data.publicUrl;
}

export default function Organizer() {
  const { state, T, trStatus, stripKm, curEvent: ev, backToEvent, goEvent, goChat, toggleFollow, openPhoto, loadHomeLiveEvents, loadOrganizerPhotos } = useGoc();
  const s = state;
  // 2026-09-25 fix pass (Task 0 audit) — see `orgEvents`' own comment
  // below; this screen never fetched live status before, so it's fetched
  // here the same way Dashboard.jsx fetches it for its own event lists.
  useEffect(() => { loadHomeLiveEvents(); }, [loadHomeLiveEvents]);
  // STAGE B (2026-09-25) — the real photo library, replacing the static
  // `ev.orgGallery` render below. Re-fetched whenever the viewed event
  // changes (a shared link/back-navigation can land here for a different
  // organizer entirely).
  useEffect(() => { loadOrganizerPhotos(ev.key); }, [ev.key, loadOrganizerPhotos]);
  // Photo identity fix — a REAL bug found while tracing this: every photo
  // here used to be handed to PhotoViewer tagged with THIS screen's own
  // `ev.key`, even though this grid spans the organizer's OTHER events too
  // (`loadOrganizerPhotos` fetches by organizer, not by event) — so "Lưu sự
  // kiện" on a photo from a different event silently saved/showed the
  // WRONG event. Each photo now carries its own real `event_id` (already
  // fetched, just previously discarded).
  const orgPhotos = (s.organizerPhotos || []).map(p => ({ id: p.id, url: organizerPhotoUrl(p.storage_path), eventId: p.event_id }));

  const evOrgStats = T('Tổ chức từ ' + ev.orgSince + ' ▪︎ ' + ev.orgCount + ' sự kiện', 'Hosting since ' + ev.orgSince + ' ▪︎ ' + ev.orgCount + ' events');
  const following = s.following.includes(ev.key);
  // 2026-09-25 fix pass (Task 0 audit) — real, user-visible bug: this
  // organizer's OTHER "current events" (shown to every visitor of this
  // public page) used to read the raw static catalogue — both the
  // `!e.cancelled`/`endedHoursAgo == null` eligibility check and every
  // displayed date via `e.meta` — never the real `starts_at`/`status`.
  const orgEvents = EVENTS
    .map(e => { const overrides = liveEventOverrides(s.homeLiveEvents[e.key], e); return overrides ? { ...e, ...overrides } : e; })
    .filter(e => e.orgName === ev.orgName && !e.cancelled && e.endedHoursAgo == null);

  return (
    <div style={{ animation: 'gocFade 0.3s ease both', height: '100%', display: 'flex', flexDirection: 'column', background: paper }} data-screen-label="Organizer">
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>
      <div onClick={backToEvent} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {ev.name}</div>
      {s.arrivedFromSharedLink && (
        // Only shown to someone who followed a shared "?org=" link. The
        // banbe:// scheme opens the installed app straight to this page;
        // there's no App Store listing to fall back to yet, so the second
        // line points at the web app someone is already looking at rather
        // than at a link that would 404.
        <div style={{ ...cardGlass({ margin: '14px 22px 0', padding: '14px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12 }) }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
            <span style={{ fontSize: 13, color: ink }}>{T('Xem trong ứng dụng banbe', 'Open in the banbe app')}</span>
            <span style={{ fontSize: 11.5, lineHeight: 1.45, color: ink, opacity: 0.7 }}>{T('Chưa có ứng dụng? Bạn vẫn xem được mọi thứ ngay tại đây.', "Don't have it? Everything here works in the browser too.")}</span>
          </div>
          <a
            href={`banbe://organizer/${ev.key}`}
            style={{ flex: 'none', fontSize: 12, fontWeight: 600, color: paper, background: ink, borderRadius: 999, padding: '9px 16px', textDecoration: 'none' }}
          >{T('Mở', 'Open')}</a>
        </div>
      )}
      <div style={{ padding: '16px 22px 30px' }}>
        <span style={{ fontSize: 11.5, color: ink }}>{T('Người tổ chức', 'Organizer')}</span>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginTop: 8 }}>
          <h1 style={{ ...display(29, { lineHeight: 1.2, margin: 0 }) }}>{ev.orgName}</h1>
          {ev.orgTrusted && (
            <span style={{ fontSize: 13, fontWeight: 500, color: ink, whiteSpace: 'nowrap' }}>{T('Tổ chức lâu năm', 'Established host')}</span>
          )}
        </div>
        {ev.orgTrusted && <div style={{ fontSize: 12, color: ink, marginTop: 4 }}>{evOrgStats}</div>}
        <div style={{ display: 'flex', gap: 14, alignItems: 'center', marginTop: 10 }}>
          <a href={'https://instagram.com/' + (ev.orgIg || '').replace('@', '')} target="_blank" rel="noopener" style={{ fontSize: 13, color: ink, textDecoration: 'none' }}>{ev.orgIg}</a>
          <span
            onClick={() => toggleFollow(ev.key)}
            style={{ fontSize: 12, fontWeight: 600, cursor: 'pointer', padding: '7px 14px', borderRadius: 999, border: following ? '1px solid transparent' : `1px solid ${rule}`, color: ink, background: 'transparent' }}
          >
            {following ? T('Đang theo dõi ▪︎ sẽ báo sự kiện mới', 'Following ▪︎ new events by email') : T('Theo dõi', 'Follow')}
          </span>
        </div>
        <p style={{ fontSize: 14, lineHeight: 1.555, color: ink, margin: '16px 0 0' }}>{ev.orgDesc}</p>
        <div style={{ marginTop: 26 }}>
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Sự kiện đang mở', 'Current events')}</span>
          <div style={{ display: 'flex', flexDirection: 'column', marginTop: 6 }}>
            {orgEvents.map((e, i, arr) => (
              <div key={e.key} onClick={() => goEvent(e.key)} style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '12px 0', borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none', cursor: 'pointer' }}>
                <div style={bg(e.img, { flex: 'none', width: 52, height: 52 })} />
                <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                  <span style={{ ...display(15, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{e.name}</span>
                  <span style={{ fontSize: 11.5, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{trStatus(stripKm(e.meta, e))}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginTop: 30 }}>
          <span style={{ fontSize: 11.5, color: ink }}>{T('Ảnh của', 'Photos by')} {ev.orgName}</span>
          <span style={{ fontSize: 11, color: ink }}>{T('do người tổ chức đăng', 'posted by the organizer')}</span>
        </div>
        {/* STAGE B (2026-09-25) — real event_photos rows (loadOrganizerPhotos
            above), not the static demo `orgGallery` this used to render.
            Scoped server-query-side to live+public events for a visitor,
            every one of the organizer's own events (any status, Task 1's
            own "ended must stay in the library" rule) for the owner. A
            genuinely empty result shows plain text, never a fake/demo
            photo standing in for a real one. */}
        {s.organizerPhotosLoading ? (
          <p style={{ fontSize: 12.5, color: ink, opacity: 0.6, margin: '14px 0 0' }}>{T('Đang tải…', 'Loading…')}</p>
        ) : orgPhotos.length ? (
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 6, marginTop: 14 }}>
            {orgPhotos.map((p, i) => (
              <div key={p.id} onClick={(e) => openPhoto(orgPhotos, i, ev.orgName, e.currentTarget.getBoundingClientRect())} style={{ position: 'relative', cursor: 'pointer' }}>
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
      </div>
      <div onClick={goChat} data-testid="organizer-message" style={{ ...inkButton({ flex: 'none', margin: '0 20px 22px', padding: '15px 0' }) }}>
        {T('Nhắn cho', 'Message')} {ev.hostShort}
      </div>
    </div>
  );
}

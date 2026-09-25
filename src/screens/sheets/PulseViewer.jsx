import { useGoc } from '../../state/GocContext.jsx';
import { supabase } from '../../lib/supabase.js';
import { paper, ink, rule, display, cardGlass } from '../../theme.js';

function eventPhotoUrl(path) {
  if (!path) return null;
  const relative = path.replace(/^event-photos\//, '');
  return supabase.storage.from('event-photos').getPublicUrl(relative).data.publicUrl;
}

// 2026-09-25 fix pass (photo viewer task) — same heart glyph/path
// `src/screens/sheets/PhotoViewer.jsx`'s own `Icon({name:'heart'})` already
// draws (this app's one existing heart-fill asset) — not a new icon style.
// Deliberately has no "outline" caller anywhere in this file: the rule this
// task adds is that an UNLIKED photo renders no heart glyph at all, only
// this filled one once liked.
function FilledHeart({ size = 16 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 20.5S3.5 15 3.5 9.2A4.7 4.7 0 0 1 12 6.5a4.7 4.7 0 0 1 8.5 2.7c0 5.8-8.5 11.3-8.5 11.3Z" />
    </svg>
  );
}

// TASK E (2026-10-01 UX foundation pass) — Banbe Pulse: two tabs ("Hôm
// nay"/"Tuần này") of ranked public event/organizer cards. Tapping an
// unfollowed organizer's identity opens a compact sheet with a Follow CTA
// (never navigates away immediately — rule E8); tapping the event card
// itself navigates straight to the event page.
// 2026-09-25 fix pass — a THIRD tab ("Ảnh nổi bật"), a separate ranking of
// individual event photos by real engagement (photo_likes/photo_shares,
// migration 083) — never merged into the event-level list/signals above.
const TABS = [
  { key: 'daily', vi: 'Hôm nay', en: 'Today' },
  { key: 'weekly', vi: 'Tuần này', en: 'This week' },
  { key: 'photos', vi: 'Ảnh nổi bật', en: 'Featured photos' },
];

export default function PulseViewer() {
  const {
    state, T, closePulseViewer, setPulseTab, openPulseOrganizerSheet, closePulseOrganizerSheet, followPulseOrganizer,
    openPulsePhotoSheet, closePulsePhotoSheet, togglePulsePhotoLike, sharePulsePhoto, goEvent,
  } = useGoc();
  const s = state;
  if (!s.pulseOpen) return null;
  const isPhotoTab = s.pulseTab === 'photos';
  const items = isPhotoTab ? s.pulsePhotos : (s.pulseTab === 'weekly' ? s.pulseWeekly : s.pulseDaily);
  // TASK A5 (2026-10-03 fix pass) — a real bug (a shared request-sequence
  // counter dropping legitimate responses, see loadPulse's own comment)
  // used to make the daily tab flash "Nothing ranked yet." even when data
  // was already on its way. Now a genuine, per-tab loading state, so a
  // still-fetching tab never gets misread as a genuinely empty one.
  const loading = isPhotoTab ? s.pulsePhotosLoading : (s.pulseTab === 'weekly' ? s.pulseWeeklyLoading : s.pulseDailyLoading);

  return (
    <div style={{ position: 'fixed', inset: 0, background: paper, zIndex: 60, display: 'flex', flexDirection: 'column' }} data-testid="pulse-viewer">
      <div style={{ padding: '20px 20px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ ...display(20) }}>{T('Banbe Pulse', 'Banbe Pulse')}</span>
        <span onClick={closePulseViewer} data-testid="pulse-close" style={{ fontSize: 22, color: ink, cursor: 'pointer' }}>×</span>
      </div>

      <div style={{ display: 'flex', gap: 8, padding: '16px 20px 0' }}>
        {TABS.map(tab => (
          <span
            key={tab.key}
            onClick={() => setPulseTab(tab.key)}
            data-testid={`pulse-tab-${tab.key}`}
            style={{
              fontSize: 12.5, fontWeight: 600, padding: '9px 16px', borderRadius: 999, cursor: 'pointer',
              background: s.pulseTab === tab.key ? ink : 'transparent',
              color: s.pulseTab === tab.key ? paper : ink,
              border: s.pulseTab === tab.key ? 'none' : `1px solid ${rule}`,
              whiteSpace: 'nowrap',
            }}
          >
            {T(tab.vi, tab.en)}
          </span>
        ))}
      </div>

      <div style={{ flex: 1, overflowY: 'auto', padding: '16px 20px 40px', display: 'flex', flexDirection: 'column', gap: 10 }} data-testid="pulse-list" data-loading={loading ? 'true' : 'false'}>
        {loading ? (
          <p style={{ fontSize: 13, color: ink, opacity: 0.6, textAlign: 'center', marginTop: 60 }} data-testid="pulse-loading">
            {T('Đang tải…', 'Loading…')}
          </p>
        ) : !items.length && (
          <p style={{ fontSize: 13, color: ink, opacity: 0.7, textAlign: 'center', marginTop: 60 }} data-testid="pulse-empty">
            {T('Chưa có dữ liệu xếp hạng.', 'Nothing ranked yet.')}
          </p>
        )}
        {!loading && !isPhotoTab && items.map((item, i) => (
          <div key={item.event_id} style={{ ...cardGlass({ padding: 0, display: 'flex', overflow: 'hidden' }) }} data-testid="pulse-card">
            <div onClick={() => { closePulseViewer(); goEvent(item.event_id); }} style={{ width: 88, height: 88, flex: 'none', cursor: 'pointer', background: `center/cover url(${eventPhotoUrl(item.photo_path)})` }} />
            <div style={{ flex: 1, minWidth: 0, padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 4 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ fontSize: 11, fontWeight: 700, color: ink, opacity: 0.5 }}>#{i + 1}</span>
                <span onClick={() => { closePulseViewer(); goEvent(item.event_id); }} style={{ ...display(14, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', cursor: 'pointer' }) }}>{item.event_name}</span>
              </div>
              <span
                onClick={() => openPulseOrganizerSheet(item)}
                data-testid="pulse-organizer-identity"
                style={{ fontSize: 11.5, color: ink, opacity: 0.75, cursor: 'pointer' }}
              >
                {item.organizer_name}{item.organizer_verified ? ' ✓' : ''}
              </span>
            </div>
          </div>
        ))}
        {/* TASK 4/5 (2026-09-25 fix pass) — ranked photos: rank + like/share
            counts on the row itself; tapping opens the compact popup below
            (not immediate navigation — matches the organizer-identity
            sheet's own "never navigate away immediately" rule). */}
        {!loading && isPhotoTab && items.map((item, i) => (
          <div
            key={item.photo_id}
            onClick={() => openPulsePhotoSheet(item)}
            data-testid="pulse-photo-card"
            style={{ ...cardGlass({ padding: 0, display: 'flex', overflow: 'hidden', cursor: 'pointer' }) }}
          >
            <div style={{ width: 88, height: 88, flex: 'none', position: 'relative', background: `center/cover url(${eventPhotoUrl(item.photo_path)})` }}>
              {/* Heart rule (Task 3): rendered ONLY when this user has
                  liked the photo — no outline/placeholder heart otherwise. */}
              {s.pulsePhotoLiked[item.photo_id] && (
                <span style={{ position: 'absolute', top: 6, right: 6, color: '#fff', filter: 'drop-shadow(0 1px 2px rgba(0,0,0,0.55))' }} data-testid="pulse-photo-card-liked">
                  <FilledHeart size={15} />
                </span>
              )}
            </div>
            <div style={{ flex: 1, minWidth: 0, padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 4, justifyContent: 'center' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ fontSize: 11, fontWeight: 700, color: ink, opacity: 0.5 }}>#{i + 1}</span>
                <span style={{ ...display(14, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{item.event_name}</span>
              </div>
              <span style={{ fontSize: 11.5, color: ink, opacity: 0.75 }}>{item.organizer_name}{item.organizer_verified ? ' ✓' : ''}</span>
              <span style={{ fontSize: 11, color: ink, opacity: 0.6 }}>
                {T(`${item.like_count} lượt thích ▪︎ ${item.share_count} lượt chia sẻ`, `${item.like_count} likes ▪︎ ${item.share_count} shares`)}
              </span>
            </div>
          </div>
        ))}
      </div>

      {/* TASK 5 (2026-09-25 fix pass) — the ranked-photo popup: photo,
          organizer identity/verified badge, a real like toggle, share, and
          a clear "view event" action that navigates and closes both this
          popup and the Pulse viewer itself, same as the organizer sheet's
          own "Xem sự kiện" already does. */}
      {s.pulsePhotoSheet && (
        <div onClick={closePulsePhotoSheet} style={{ position: 'fixed', inset: 0, background: 'rgba(27,25,22,0.45)', display: 'flex', alignItems: 'flex-end', zIndex: 70 }} data-testid="pulse-photo-sheet">
          <div onClick={(e) => e.stopPropagation()} style={{ background: paper, width: '100%', borderRadius: '18px 18px 0 0', padding: '20px 22px 34px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
            <div style={{ width: 36, height: 4, background: rule, borderRadius: 2 }} />
            <div style={{ width: 160, height: 160, borderRadius: 14, marginTop: 8, background: `center/cover url(${eventPhotoUrl(s.pulsePhotoSheet.photo_path)})` }} />
            <span style={{ ...display(17), marginTop: 4 }}>{s.pulsePhotoSheet.organizer_name}{s.pulsePhotoSheet.organizer_verified ? ' ✓' : ''}</span>
            {s.pulsePhotoSheet.organizer_verified && (
              <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>{T('Đã xác minh', 'Verified')}</span>
            )}
            <div style={{ display: 'flex', gap: 10, marginTop: 6 }}>
              {/* Heart rule (Task 3) — the glyph itself only ever renders
                  filled (liked) or not at all (not liked); no outline/empty
                  heart state, no transitional animation beyond the plain
                  fade this button's own background/color already do. The
                  tap target (this whole pill) is identical either way. */}
              <div
                onClick={() => togglePulsePhotoLike(s.pulsePhotoSheet.photo_id)}
                data-testid="pulse-photo-like"
                style={{
                  fontSize: 13, fontWeight: 600, padding: '10px 20px', borderRadius: 999, cursor: 'pointer',
                  display: 'flex', alignItems: 'center', gap: 6,
                  background: s.pulsePhotoLiked[s.pulsePhotoSheet.photo_id] ? ink : 'transparent',
                  color: s.pulsePhotoLiked[s.pulsePhotoSheet.photo_id] ? paper : ink,
                  border: s.pulsePhotoLiked[s.pulsePhotoSheet.photo_id] ? 'none' : `1px solid ${rule}`,
                  opacity: s.pulsePhotoBusy[s.pulsePhotoSheet.photo_id] ? 0.6 : 1,
                  transition: 'opacity .15s ease',
                }}
              >
                {s.pulsePhotoLiked[s.pulsePhotoSheet.photo_id] && <FilledHeart size={14} />}
                <span>{T('Thích', 'Like')} · {s.pulsePhotoSheet.like_count}</span>
              </div>
              <div
                onClick={() => sharePulsePhoto(s.pulsePhotoSheet)}
                data-testid="pulse-photo-share"
                style={{ fontSize: 13, fontWeight: 600, padding: '10px 20px', borderRadius: 999, cursor: 'pointer', border: `1px solid ${rule}`, color: ink }}
              >
                {T('Chia sẻ', 'Share')} · {s.pulsePhotoSheet.share_count}
              </div>
            </div>
            <div
              onClick={() => { closePulsePhotoSheet(); closePulseViewer(); goEvent(s.pulsePhotoSheet.event_id); }}
              data-testid="pulse-photo-view-event"
              style={{ marginTop: 4, fontSize: 12, color: ink, textDecoration: 'underline', cursor: 'pointer' }}
            >
              {T('Xem sự kiện / trang tổ chức', 'View event / host page')}
            </div>
          </div>
        </div>
      )}

      {s.pulseOrganizerSheet && (
        <div onClick={closePulseOrganizerSheet} style={{ position: 'fixed', inset: 0, background: 'rgba(27,25,22,0.45)', display: 'flex', alignItems: 'flex-end', zIndex: 70 }}>
          <div onClick={(e) => e.stopPropagation()} style={{ background: paper, width: '100%', borderRadius: '18px 18px 0 0', padding: '20px 22px 34px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
            <div style={{ width: 36, height: 4, background: rule, borderRadius: 2 }} />
            <span style={{ ...display(19), marginTop: 8 }}>{s.pulseOrganizerSheet.organizer_name}</span>
            {s.pulseOrganizerSheet.organizer_verified && (
              <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>{T('Đã xác minh', 'Verified')}</span>
            )}
            <div
              onClick={() => followPulseOrganizer(s.pulseOrganizerSheet.organizer_id)}
              data-testid="pulse-follow"
              style={{
                marginTop: 8, fontSize: 13, fontWeight: 600, padding: '10px 28px', borderRadius: 999, cursor: 'pointer',
                background: s.pulseOrganizerSheet.following ? 'transparent' : ink,
                color: s.pulseOrganizerSheet.following ? ink : paper,
                border: s.pulseOrganizerSheet.following ? `1px solid ${rule}` : 'none',
              }}
            >
              {s.pulseOrganizerSheet.following ? T('Đang theo dõi', 'Following') : T('Theo dõi', 'Follow')}
            </div>
            <div
              onClick={() => { closePulseViewer(); goEvent(s.pulseOrganizerSheet.event_id); }}
              style={{ marginTop: 4, fontSize: 12, color: ink, textDecoration: 'underline', cursor: 'pointer' }}
            >
              {T('Xem sự kiện', 'View event')}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

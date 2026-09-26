import { useGoc } from '../../state/GocContext.jsx';
import { supabase } from '../../lib/supabase.js';
import { paper, ink, rule, fieldSolid, display, cardGlass } from '../../theme.js';

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

function ShareGlyph({ size = 15 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 15.5V3.5m0 0L7.75 7.75M12 3.5l4.25 4.25M4.5 13.5v5.25a1.5 1.5 0 0 0 1.5 1.5h12a1.5 1.5 0 0 0 1.5-1.5V13.5" />
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
// Photo-interactions redesign pass — B: tapping a ranked EVENT card now
// always opens the follow/view sheet (was: only the organizer-name text did
// that; photo/name used to navigate immediately) — one consistent target
// per rule B3. The card's own right-hand column shows a transparent
// breakdown of the REAL score components migration 086 returns (never a
// fabricated metric), plus the event's own category and "bao gồm" field.
const TABS = [
  { key: 'daily', vi: 'Hôm nay', en: 'Today' },
  { key: 'weekly', vi: 'Tuần này', en: 'This week' },
  { key: 'photos', vi: 'Ảnh nổi bật', en: 'Featured photos' },
];

export default function PulseViewer() {
  const {
    state, T, closePulseViewer, setPulseTab, openPulseOrganizerSheet, closePulseOrganizerSheet, followPulseOrganizer,
    openPulsePhotoSheet, closePulsePhotoSheet, togglePhotoLike, sharePhoto, goEvent,
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
        {/* B1 — same rounded corners on all four sides for every card in
            all three tabs: `cardGlass`'s own `borderRadius: 12` +
            `overflow: 'hidden'` already clips every child (including the
            flush-left photo tile) to that shape — kept as ONE recipe for
            all three lists below rather than three near-duplicates, so a
            future radius change can't drift between tabs again. */}
        {!loading && !isPhotoTab && items.map((item, i) => (
          <div
            key={item.event_id}
            onClick={() => openPulseOrganizerSheet(item)}
            data-testid="pulse-card"
            style={{ ...cardGlass({ padding: 0, display: 'flex', overflow: 'hidden', cursor: 'pointer' }) }}
          >
            <div style={{ width: 88, height: 88, flex: 'none', background: `center/cover url(${eventPhotoUrl(item.photo_path)})` }} />
            <div style={{ flex: 1, minWidth: 0, padding: '10px 10px 10px 14px', display: 'flex', flexDirection: 'column', gap: 3, justifyContent: 'center' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ fontSize: 11, fontWeight: 700, color: ink, opacity: 0.5 }}>#{i + 1}</span>
                <span style={{ ...display(14, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{item.event_name}</span>
              </div>
              <span data-testid="pulse-organizer-identity" style={{ fontSize: 11.5, color: ink, opacity: 0.75 }}>
                {item.organizer_name}{item.organizer_verified ? ' ✓' : ''}
              </span>
              {!!item.included && (
                <span style={{ fontSize: 10, color: ink, opacity: 0.55, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                  {T('Bao gồm: ', 'Includes: ')}{item.included}
                </span>
              )}
            </div>
            {/* B2 — the unused right-side space: a transparent breakdown of
                the REAL score components goc_pulse_ranked() (086) returns —
                confirmed bookings + check-ins this window, plus the
                organizer's follower count (the query's own honest proxy
                for "new follows," documented in the RPC itself — never
                relabelled as period-scoped here) and event saves, and the
                event's own category chip. Nothing here is invented: every
                number is a field the RPC actually returns. */}
            <div style={{ width: 82, flex: 'none', padding: '10px 12px 10px 0', display: 'flex', flexDirection: 'column', alignItems: 'flex-end', justifyContent: 'center', gap: 3 }} data-testid="pulse-rank-breakdown">
              {!!item.cat_label && (
                <span style={{ fontSize: 9.5, fontWeight: 600, padding: '3px 7px', borderRadius: 999, background: fieldSolid, color: ink, whiteSpace: 'nowrap' }}>
                  {item.cat_label}
                </span>
              )}
              <span style={{ fontSize: 9.5, color: ink, opacity: 0.65, whiteSpace: 'nowrap' }}>
                {T(`${item.booking_count ?? 0} vé`, `${item.booking_count ?? 0} bkgs`)}
              </span>
              <span style={{ fontSize: 9.5, color: ink, opacity: 0.65, whiteSpace: 'nowrap' }}>
                {T(`${item.checkin_count ?? 0} check-in`, `${item.checkin_count ?? 0} chk-in`)}
              </span>
              <span style={{ fontSize: 9.5, color: ink, opacity: 0.5, whiteSpace: 'nowrap' }}>
                {T(`${item.follow_count ?? 0} theo dõi`, `${item.follow_count ?? 0} follows`)}
              </span>
            </div>
          </div>
        ))}
        {/* TASK 4/5 (2026-09-25 fix pass), B4 — ranked photos: rank +
            like/share quick actions live on the card itself now (not just
            inside the popup), each stopping propagation so tapping a
            control never also opens the sheet. Tapping anywhere else on
            the card still opens the photo sheet. */}
        {!loading && isPhotoTab && items.map((item, i) => {
          const eng = s.photoEngagement[item.photo_id] || { likeCount: item.like_count, shareCount: item.share_count, likedByMe: false };
          return (
            <div
              key={item.photo_id}
              onClick={() => openPulsePhotoSheet(item)}
              data-testid="pulse-photo-card"
              style={{ ...cardGlass({ padding: 0, display: 'flex', overflow: 'hidden', cursor: 'pointer' }) }}
            >
              <div style={{ width: 88, height: 88, flex: 'none', position: 'relative', background: `center/cover url(${eventPhotoUrl(item.photo_path)})` }}>
                {/* Heart rule (Task 3): rendered ONLY when this user has
                    liked the photo — no outline/placeholder heart otherwise. */}
                {eng.likedByMe && (
                  <span style={{ position: 'absolute', top: 6, right: 6, color: '#fff', filter: 'drop-shadow(0 1px 2px rgba(0,0,0,0.55))' }} data-testid="pulse-photo-card-liked">
                    <FilledHeart size={15} />
                  </span>
                )}
              </div>
              <div style={{ flex: 1, minWidth: 0, padding: '10px 10px 10px 14px', display: 'flex', flexDirection: 'column', gap: 3, justifyContent: 'center' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <span style={{ fontSize: 11, fontWeight: 700, color: ink, opacity: 0.5 }}>#{i + 1}</span>
                  <span style={{ ...display(14, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{item.event_name}</span>
                </div>
                <span style={{ fontSize: 11.5, color: ink, opacity: 0.75 }}>{item.organizer_name}{item.organizer_verified ? ' ✓' : ''}</span>
              </div>
              {/* B4 — quick like/share, own tap targets. */}
              <div style={{ width: 60, flex: 'none', padding: '10px 12px 10px 0', display: 'flex', flexDirection: 'column', alignItems: 'flex-end', justifyContent: 'center', gap: 8 }}>
                <span
                  onClick={(e) => { e.stopPropagation(); togglePhotoLike(item.photo_id); }}
                  data-testid="pulse-photo-quick-like"
                  style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 11, color: ink, cursor: 'pointer' }}
                >
                  <span>{eng.likeCount}</span>
                  <span style={{ display: 'flex', color: eng.likedByMe ? ink : ink, opacity: eng.likedByMe ? 1 : 0.55 }}>
                    {eng.likedByMe ? <FilledHeart size={14} /> : T('Thích', 'Like')}
                  </span>
                </span>
                <span
                  onClick={(e) => { e.stopPropagation(); sharePhoto(item); }}
                  data-testid="pulse-photo-quick-share"
                  style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 11, color: ink, opacity: 0.7, cursor: 'pointer' }}
                >
                  <span>{eng.shareCount}</span>
                  <ShareGlyph size={13} />
                </span>
              </div>
            </div>
          );
        })}
      </div>

      {/* B5 — the ranked-photo sheet: top 2/3 a large, clear image (a real
          <img> with object-fit:contain, never a cropping background-cover,
          so portrait/landscape photos both show honestly); bottom 1/3 the
          existing host identity, counts, like/share, view-event actions. */}
      {s.pulsePhotoSheet && (
        <div onClick={closePulsePhotoSheet} style={{ position: 'fixed', inset: 0, background: 'rgba(12,12,12,0.6)', display: 'flex', alignItems: 'flex-end', zIndex: 70 }} data-testid="pulse-photo-sheet">
          <div
            onClick={(e) => e.stopPropagation()}
            style={{ background: paper, width: '100%', height: '66vh', borderRadius: '18px 18px 0 0', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}
          >
            <div style={{ position: 'relative', flex: '2 1 0', minHeight: 0, background: '#0C0B09', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <img src={eventPhotoUrl(s.pulsePhotoSheet.photo_path)} alt="" style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain' }} />
              <div style={{ position: 'absolute', top: 10, left: '50%', transform: 'translateX(-50%)', width: 36, height: 4, background: 'rgba(255,255,255,0.55)', borderRadius: 2 }} />
              <span
                onClick={closePulsePhotoSheet}
                data-testid="pulse-photo-sheet-close"
                style={{ position: 'absolute', top: 12, right: 12, width: 30, height: 30, borderRadius: 999, background: 'rgba(12,12,12,0.5)', color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', fontSize: 18 }}
              >×</span>
            </div>
            <div style={{ flex: '1 1 0', minHeight: 0, overflowY: 'auto', padding: '14px 22px 26px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
              <span style={{ ...display(16) }}>{s.pulsePhotoSheet.organizer_name}{s.pulsePhotoSheet.organizer_verified ? ' ✓' : ''}</span>
              {s.pulsePhotoSheet.organizer_verified && (
                <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>{T('Đã xác minh', 'Verified')}</span>
              )}
              <div style={{ display: 'flex', gap: 10, marginTop: 4 }}>
                {/* Heart rule (Task 3) — the glyph itself only ever renders
                    filled (liked) or not at all (not liked); no outline/empty
                    heart state. */}
                <div
                  onClick={() => togglePhotoLike(s.pulsePhotoSheet.photo_id)}
                  data-testid="pulse-photo-like"
                  style={{
                    fontSize: 13, fontWeight: 600, padding: '10px 20px', borderRadius: 999, cursor: 'pointer',
                    display: 'flex', alignItems: 'center', gap: 6,
                    background: s.photoEngagement[s.pulsePhotoSheet.photo_id]?.likedByMe ? ink : 'transparent',
                    color: s.photoEngagement[s.pulsePhotoSheet.photo_id]?.likedByMe ? paper : ink,
                    border: s.photoEngagement[s.pulsePhotoSheet.photo_id]?.likedByMe ? 'none' : `1px solid ${rule}`,
                    opacity: s.photoEngagementBusy[s.pulsePhotoSheet.photo_id] ? 0.6 : 1,
                    transition: 'opacity .15s ease',
                  }}
                >
                  {s.photoEngagement[s.pulsePhotoSheet.photo_id]?.likedByMe && <FilledHeart size={14} />}
                  <span>{T('Thích', 'Like')} · {s.photoEngagement[s.pulsePhotoSheet.photo_id]?.likeCount ?? s.pulsePhotoSheet.like_count}</span>
                </div>
                <div
                  onClick={() => sharePhoto(s.pulsePhotoSheet)}
                  data-testid="pulse-photo-share"
                  style={{ fontSize: 13, fontWeight: 600, padding: '10px 20px', borderRadius: 999, cursor: 'pointer', border: `1px solid ${rule}`, color: ink }}
                >
                  {T('Chia sẻ', 'Share')} · {s.photoEngagement[s.pulsePhotoSheet.photo_id]?.shareCount ?? s.pulsePhotoSheet.share_count}
                </div>
              </div>
              <div
                onClick={() => { closePulsePhotoSheet(); closePulseViewer(); goEvent(s.pulsePhotoSheet.event_id); }}
                data-testid="pulse-photo-view-event"
                style={{ marginTop: 2, fontSize: 12, color: ink, textDecoration: 'underline', cursor: 'pointer' }}
              >
                {T('Xem sự kiện / trang tổ chức', 'View event / host page')}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* B3 — tapping a ranked EVENT card opens this sheet (was previously
          only reachable via the organizer-name text); two large, equal,
          adjacent rounded buttons, same visual language as the app's other
          confirmation buttons (solid ink primary, ink-bordered ghost
          secondary) rather than a new one. */}
      {s.pulseOrganizerSheet && (
        <div onClick={closePulseOrganizerSheet} style={{ position: 'fixed', inset: 0, background: 'rgba(27,25,22,0.45)', display: 'flex', alignItems: 'flex-end', zIndex: 70 }}>
          <div onClick={(e) => e.stopPropagation()} style={{ background: paper, width: '100%', borderRadius: '18px 18px 0 0', padding: '20px 22px 34px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
            <div style={{ width: 36, height: 4, background: rule, borderRadius: 2 }} />
            <span style={{ ...display(19), marginTop: 8 }}>{s.pulseOrganizerSheet.organizer_name}</span>
            {s.pulseOrganizerSheet.organizer_verified && (
              <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>{T('Đã xác minh', 'Verified')}</span>
            )}
            <div style={{ display: 'flex', gap: 10, width: '100%', marginTop: 10 }}>
              <div
                onClick={() => followPulseOrganizer(s.pulseOrganizerSheet.organizer_id)}
                data-testid="pulse-follow"
                style={{
                  flex: 1, textAlign: 'center', fontSize: 13.5, fontWeight: 600, padding: '14px 10px', borderRadius: 18, cursor: 'pointer',
                  background: s.pulseOrganizerSheet.following ? 'transparent' : ink,
                  color: s.pulseOrganizerSheet.following ? ink : paper,
                  border: s.pulseOrganizerSheet.following ? `1px solid ${rule}` : 'none',
                }}
              >
                {s.pulseOrganizerSheet.following ? T('Đang theo dõi', 'Following') : T('Theo dõi', 'Follow')}
              </div>
              <div
                onClick={() => { closePulseViewer(); goEvent(s.pulseOrganizerSheet.event_id); }}
                data-testid="pulse-view-event"
                style={{ flex: 1, textAlign: 'center', fontSize: 13.5, fontWeight: 600, padding: '14px 10px', borderRadius: 18, cursor: 'pointer', background: ink, color: paper }}
              >
                {T('Xem sự kiện', 'View event')}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

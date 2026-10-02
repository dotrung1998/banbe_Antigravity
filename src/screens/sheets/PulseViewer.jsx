import { useCallback, useEffect, useRef, useState } from 'react';
import { useGoc } from '../../state/GocContext.jsx';
import { supabase } from '../../lib/supabase.js';
import { paper, ink, rule, fieldSolid, display, cardGlass } from '../../theme.js';
import BanbeLoadingVisual from '../BanbeLoadingVisual.jsx';

// White-flash fix (2026-09-28 pass) — root cause confirmed by reading the
// code, not guessed: each card's thumbnail painted `background: center/
// cover url(...)` with NO fallback color, so while that specific photo's
// bytes were still downloading/decoding the tile showed whatever's behind
// it (the page's own paper background) — a visible blank/white flash,
// worst on a tab seen for the first time. This hook tracks which photo
// URLs have actually finished decoding (`HTMLImageElement.decode()`,
// falling back to `onload` on engines without it) so a card only ever
// swaps from a neutral, themed placeholder fill to the real photo once
// the bitmap is genuinely ready — never mid-paint. Scoped to the
// CURRENTLY active tab's own items only (never "everything") — prefetches
// exactly the small set of assets the ticket asks for, and skips a URL
// already marked decoded/errored so switching tabs back and forth never
// re-fetches identical data.
//
// Loading-GIF pass (same-day follow-up) — the solid fallback fill above
// stops the literal white flash, but a real-device report correctly
// pointed out it's NOT the same thing as "show the existing loading
// asset while a section's images are loading": the fallback fill never
// shows the actual `BanbeLoadingVisual`/GIF at all for a section whose
// photos simply haven't decoded yet (as opposed to the tab having zero
// ranked items, the only case the GIF was ever shown for before this
// pass). Now also tracks decode FAILURES (`errored`) separately from
// successes, so a genuinely broken image doesn't leave the section
// loader spinning forever — see `sectionImagesLoading` below, which is
// the actual gate this pass adds.
function usePulseImageDecode(urls) {
  const [decoded, setDecoded] = useState(() => new Set());
  const [errored, setErrored] = useState(() => new Set());
  useEffect(() => {
    let cancelled = false;
    urls.forEach((url) => {
      if (!url || decoded.has(url) || errored.has(url)) return;
      const img = new Image();
      const markDecoded = () => {
        if (cancelled) return;
        setDecoded((prev) => (prev.has(url) ? prev : new Set(prev).add(url)));
      };
      const markErrored = () => {
        if (cancelled) return;
        setErrored((prev) => (prev.has(url) ? prev : new Set(prev).add(url)));
      };
      img.src = url;
      if (img.decode) img.decode().then(markDecoded).catch(markErrored);
      else { img.onload = markDecoded; img.onerror = markErrored; }
    });
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [urls.join('|')]);
  return { decoded, errored };
}

// A2 (2026-09-27 Pulse/loading UX pass) — the left-edge-swipe-or-X
// interactive dismiss. `pulseOpen` never touches `state.screen` (Home
// stays the active, mounted screen underneath the whole time — see
// App.jsx: `{state.pulseOpen && <PulseViewer />}` renders this as a
// sibling OVERLAY of whatever `SCREENS[state.screen]` already rendered,
// unlike a route change), so translating THIS component's own root by
// `transform: translateX(...)` continuously reveals the real, live Home
// underneath — never a snapshot, never white — for both the X tap and an
// edge-swipe, as ONE shared animation, never a second/different one
// depending on which control triggered it. `EDGE_ZONE_PX` mirrors
// RootView's iOS `edgeSwipeZoneWidth`/MapExplore's own touch-scoping
// convention: only a touch starting in that thin leading strip is ever
// offered this gesture at all, so the scrollable card list's own vertical
// scroll and every tab/card tap elsewhere are untouched.
const EDGE_ZONE_PX = 24;
const DISMISS_DURATION_MS = 260;

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

// Expanded-panel redesign (2026-10-02) — "IMG_6770 still has wide filler
// panels around the featured photo" + iOS's expanded media control (Now
// Playing card) as the VISUAL/interaction reference, not an audio player.
// Replaces BOTH the oversized bottom-sheet (`pulse-photo-sheet`, 66vh with
// a fixed 2:1 media/footer split regardless of the real photo's aspect
// ratio) and the plain no-image bottom sheet (`pulseOrganizerSheet`) with
// ONE shared, centered floating glass card bounded to the viewport with
// margins. The image sizes itself to its OWN aspect ratio (`maxHeight`
// only, never a fixed box) instead of a fixed media region — mirrors
// `apps/ios/BanbeApp/Views/PulseViewerView.swift`'s `pulseExpandedPanel`
// exactly, same shared-backdrop-image / no-separate-boxed-media-panel
// approach, so preview/expanded behavior matches on both platforms.
function ExpandedPanel({ photoUrl, title, subtitle, metaLine, onClose, closeTestId, testId, children }) {
  return (
    <div
      onClick={onClose}
      data-testid={testId}
      style={{
        position: 'fixed', inset: 0, background: 'rgba(20,18,15,0.55)', backdropFilter: 'blur(6px)', WebkitBackdropFilter: 'blur(6px)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 70, padding: 20,
      }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          position: 'relative', width: '100%', maxWidth: 420, maxHeight: 'calc(100vh - 64px)',
          display: 'flex', flexDirection: 'column', borderRadius: 26, overflow: 'hidden',
          background: 'rgba(250,248,244,0.78)', backdropFilter: 'blur(26px) saturate(160%)', WebkitBackdropFilter: 'blur(26px) saturate(160%)',
          boxShadow: '0 30px 60px rgba(0,0,0,0.32)', border: '1px solid rgba(255,255,255,0.35)',
        }}
        className="pulse-expanded-panel"
      >
        {/* Same-image soft backdrop, as part of the OVERALL panel (one
            surface) rather than a second, visibly-separate rectangle
            behind just the photo. */}
        {photoUrl && (
          <img
            src={photoUrl} alt="" aria-hidden="true"
            style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover', filter: 'blur(46px)', opacity: 0.35, transform: 'scale(1.2)', zIndex: 0 }}
          />
        )}
        <span
          onClick={onClose}
          data-testid={closeTestId}
          style={{
            position: 'absolute', top: 10, right: 10, width: 44, height: 44, borderRadius: 999,
            background: 'rgba(12,12,12,0.5)', color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center',
            cursor: 'pointer', fontSize: 18, zIndex: 2,
          }}
        >×</span>
        <div style={{ position: 'relative', zIndex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
          {photoUrl && (
            // image-aware sizing: maxHeight only — never a fixed box, so a
            // portrait photo stays tall/narrow and a landscape photo stays
            // short/wide, both fully visible and un-cropped.
            <img src={photoUrl} alt="" style={{ display: 'block', width: 'auto', maxWidth: '100%', maxHeight: '52vh', objectFit: 'contain', marginTop: 18 }} />
          )}
          <div style={{ padding: '14px 22px 22px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8, width: '100%', boxSizing: 'border-box' }}>
            <span style={{ ...display(18), textAlign: 'center' }}>{title}</span>
            {subtitle && <span style={{ fontSize: 12.5, color: ink, opacity: 0.75, textAlign: 'center' }}>{subtitle}</span>}
            {metaLine && <span style={{ fontSize: 11, color: ink, opacity: 0.6, textAlign: 'center' }}>{metaLine}</span>}
            <div style={{ marginTop: 6, width: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>{children}</div>
          </div>
        </div>
      </div>
    </div>
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
    openPulsePhotoSheet, closePulsePhotoSheet, togglePhotoLike, sharePhoto, goEvent, openOrganizerProfile,
  } = useGoc();
  const s = state;
  const [dragX, setDragX] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const [isCommitting, setIsCommitting] = useState(false);
  const dragRef = useRef({ active: false, startX: 0, pointerId: null });

  const commitDismiss = useCallback(() => {
    setIsCommitting(true);
    setTimeout(() => { closePulseViewer(); }, DISMISS_DURATION_MS);
  }, [closePulseViewer]);

  const onEdgePointerDown = (e) => {
    dragRef.current = { active: true, startX: e.clientX, pointerId: e.pointerId };
    setIsDragging(true);
    e.currentTarget.setPointerCapture(e.pointerId);
  };
  const onEdgePointerMove = (e) => {
    const g = dragRef.current;
    if (!g.active || e.pointerId !== g.pointerId) return;
    setDragX(Math.max(0, e.clientX - g.startX));
  };
  const onEdgePointerUp = () => {
    const g = dragRef.current;
    if (!g.active) return;
    g.active = false;
    setIsDragging(false);
    if (dragX > window.innerWidth * 0.3) {
      commitDismiss();
    } else {
      setDragX(0);
    }
  };

  const isPhotoTab = s.pulseTab === 'photos';
  const items = isPhotoTab ? s.pulsePhotos : (s.pulseTab === 'weekly' ? s.pulseWeekly : s.pulseDaily);
  // TASK A5 (2026-10-03 fix pass) — a real bug (a shared request-sequence
  // counter dropping legitimate responses, see loadPulse's own comment)
  // used to make the daily tab flash "Nothing ranked yet." even when data
  // was already on its way. Now a genuine, per-tab loading state, so a
  // still-fetching tab never gets misread as a genuinely empty one.
  const loading = isPhotoTab ? s.pulsePhotosLoading : (s.pulseTab === 'weekly' ? s.pulseWeeklyLoading : s.pulseDailyLoading);
  // White-flash pass — only the currently active tab's own items (never
  // "everything"), and only their photo URLs (a small, bounded set).
  const activeTabPhotoUrls = items.map(item => eventPhotoUrl(item.photo_path)).filter(Boolean);
  const { decoded: decodedPhotoUrls, errored: erroredPhotoUrls } = usePulseImageDecode(activeTabPhotoUrls);
  // Loading-GIF pass — ONE section-level loader for the whole tab's list,
  // never one per thumbnail. Gate: the tab has photos to show but NONE of
  // them have decoded yet (`anyPhotoReady` false) AND at least one is
  // still genuinely in flight (`allPhotosSettled` false — if every photo
  // has either decoded or errored, there's nothing left to wait for, so
  // the loader must not spin forever on a genuinely broken/empty
  // section; the per-card themed fallback fill from the previous pass
  // covers that case instead). Recomputed fresh per tab switch, but a
  // URL already in `decodedPhotoUrls` (kept in this component's own
  // state for the life of this one Pulse-open session) immediately
  // counts as ready — so revisiting a tab whose photos already decoded
  // earlier in this session never replays the loader.
  const anyPhotoReady = activeTabPhotoUrls.some((u) => decodedPhotoUrls.has(u));
  const allPhotosSettled = activeTabPhotoUrls.length > 0
    && activeTabPhotoUrls.every((u) => decodedPhotoUrls.has(u) || erroredPhotoUrls.has(u));
  const sectionImagesLoading = activeTabPhotoUrls.length > 0 && !anyPhotoReady && !allPhotosSettled;

  // This early return only ever fires for one render right after
  // `closePulseViewer()` flips `pulseOpen` false and BEFORE App.jsx's own
  // `{state.pulseOpen && <PulseViewer/>}` unmounts this component on the
  // next commit — kept purely as a defensive guard, placed after every
  // hook call above so hook order never depends on it.
  if (!s.pulseOpen) return null;

  const slideX = isCommitting ? window.innerWidth : dragX;

  return (
    <div
      style={{
        position: 'fixed', inset: 0, background: paper, zIndex: 60, display: 'flex', flexDirection: 'column',
        transform: `translateX(${slideX}px)`,
        transition: isDragging ? 'none' : `transform ${DISMISS_DURATION_MS}ms cubic-bezier(.22,.61,.36,1)`,
      }}
      data-testid="pulse-viewer"
    >
      {/* A2 — the edge-swipe hit zone: a thin leading strip, exactly like
          MapExplore's own pointer-scoped drag handle. Only a touch
          starting here is ever offered this gesture, so the card list's
          ordinary vertical scroll and every tab/card tap are untouched. */}
      <div
        data-testid="pulse-edge-swipe-zone"
        onPointerDown={onEdgePointerDown}
        onPointerMove={onEdgePointerMove}
        onPointerUp={onEdgePointerUp}
        onPointerCancel={onEdgePointerUp}
        style={{ position: 'absolute', top: 0, bottom: 0, left: 0, width: EDGE_ZONE_PX, zIndex: 1, touchAction: 'none' }}
      />
      <div style={{ padding: '20px 20px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        {/* A1 (real-device follow-up) — logo FOLLOWED BY visible text
            "Pulse", one title: the logo alone read as just "banbe" with
            nothing naming this specific screen. `role="heading"` +
            `aria-label` make VoiceOver/screen readers announce the whole
            thing once as "Banbe Pulse" — the logo's own `alt` is now empty
            (decorative) so it isn't announced a second time on its own. */}
        <div role="heading" aria-level="1" aria-label="Banbe Pulse" style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <img src="/banbe-wordmark.png" alt="" crossOrigin="anonymous" style={{ width: 100, height: 'auto', display: 'block' }} />
          <span style={{ ...display(20) }}>{T('Pulse', 'Pulse')}</span>
        </div>
        <span onClick={commitDismiss} data-testid="pulse-close" style={{ fontSize: 22, color: ink, cursor: 'pointer' }}>×</span>
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

      {/* White-flash fix (2026-09-28 pass) — the loading GIF is now shown
          ONLY when there's genuinely nothing displayable yet
          (`items.length === 0`). A tab that already has valid cached items
          but is quietly re-fetching in the background (`loading` true)
          keeps showing them — the old code gated the ENTIRE list on
          `!loading`, so any background refresh of an already-loaded tab
          blanked its real content back to the spinner, which is exactly
          the "flash" this pass fixes, not merely a cosmetic tweak. */}
      <div style={{ flex: 1, overflowY: 'auto', padding: '16px 20px 40px', display: 'flex', flexDirection: 'column', gap: 10, position: 'relative' }} data-testid="pulse-list" data-loading={loading ? 'true' : 'false'} data-images-loading={sectionImagesLoading ? 'true' : 'false'}>
        {items.length === 0 && (
          loading ? (
            <div style={{ display: 'flex', justifyContent: 'center', marginTop: 60 }} data-testid="pulse-loading">
              <BanbeLoadingVisual size={56} />
            </div>
          ) : (
            <p style={{ fontSize: 13, color: ink, opacity: 0.7, textAlign: 'center', marginTop: 60 }} data-testid="pulse-empty">
              {T('Chưa có dữ liệu xếp hạng.', 'Nothing ranked yet.')}
            </p>
          )
        )}
        {/* Loading-GIF pass (same-day follow-up) — this tab genuinely has
            ranked items, but none of their photos have decoded yet: show
            ONE section-level loader for the whole list (never a GIF per
            thumbnail — see `sectionImagesLoading`'s own comment above for
            the exact gate). The real cards still render underneath,
            unchanged, at their own full size (each own 88x88 photo tile +
            text) — this is a fully OPAQUE overlay (`background: paper`)
            positioned over that already-laid-out content, so the space is
            reserved in advance (no layout jump once it lifts) and nothing
            un-decoded is ever visible through it. The overlay disappears
            the INSTANT any one photo in the tab decodes, at which point
            any still-pending thumbnails fall back to the themed solid
            fill from the previous pass — never a second wave of
            individual GIFs. */}
        {items.length > 0 && sectionImagesLoading && (
          <div style={{ position: 'absolute', inset: 0, background: paper, display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 5 }} data-testid="pulse-images-loading">
            <BanbeLoadingVisual size={56} />
          </div>
        )}
        {/* B1 — same rounded corners on all four sides for every card in
            all three tabs: `cardGlass`'s own `borderRadius: 12` +
            `overflow: 'hidden'` already clips every child (including the
            flush-left photo tile) to that shape — kept as ONE recipe for
            all three lists below rather than three near-duplicates, so a
            future radius change can't drift between tabs again.
            Left-corner-rounding fix (2026-09-28 pass) — real root cause:
            the flush-left photo tile relied ENTIRELY on the parent's
            `overflow:hidden` + `borderRadius` to clip it, with no radius
            of its own. That's normally enough, but this tile ALSO used to
            paint a bare `background: url(...)` with no fallback color, so
            before the photo decoded the tile was fully transparent — at
            that instant nothing was actually being clipped (there was no
            paint to clip), so any anti-aliasing/compositing seam on the
            left edge read as square while the right side (never carrying
            image content flush to that edge) never showed it. Giving the
            tile its OWN explicit left-only radius (matching the card's)
            makes the rounding correct and identical regardless of
            load/decode state — belt-and-suspenders with the parent clip,
            not a replacement for it. */}
        {!isPhotoTab && items.map((item, i) => {
          const photoUrl = eventPhotoUrl(item.photo_path);
          const photoReady = photoUrl && decodedPhotoUrls.has(photoUrl);
          return (
          <div
            key={item.event_id}
            onClick={() => openPulseOrganizerSheet(item)}
            data-testid="pulse-card"
            style={{ ...cardGlass({ padding: 0, display: 'flex', overflow: 'hidden', cursor: 'pointer' }) }}
          >
            <div style={{
              width: 88, height: 88, flex: 'none', borderRadius: '12px 0 0 12px',
              background: photoReady ? `center/cover url(${photoUrl})` : 'none',
              backgroundColor: fieldSolid,
            }} />
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
          );
        })}
        {/* TASK 4/5 (2026-09-25 fix pass), B4 — ranked photos: rank +
            like/share quick actions live on the card itself now (not just
            inside the popup), each stopping propagation so tapping a
            control never also opens the sheet. Tapping anywhere else on
            the card still opens the photo sheet. */}
        {isPhotoTab && items.map((item, i) => {
          const eng = s.photoEngagement[item.photo_id] || { likeCount: item.like_count, shareCount: item.share_count, likedByMe: false };
          const photoUrl = eventPhotoUrl(item.photo_path);
          const photoReady = photoUrl && decodedPhotoUrls.has(photoUrl);
          return (
            <div
              key={item.photo_id}
              onClick={() => openPulsePhotoSheet(item)}
              data-testid="pulse-photo-card"
              style={{ ...cardGlass({ padding: 0, display: 'flex', overflow: 'hidden', cursor: 'pointer' }) }}
            >
              <div style={{
                width: 88, height: 88, flex: 'none', position: 'relative', borderRadius: '12px 0 0 12px',
                background: photoReady ? `center/cover url(${photoUrl})` : 'none',
                backgroundColor: fieldSolid,
              }}>
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

      {/* Expanded-panel redesign (2026-10-02) — see ExpandedPanel's own doc
          comment. Like/Share permissions, counts, selected item, and
          dismissal/return-state are all unchanged — only the surrounding
          chrome moved from an oversized bottom-sheet to a centered,
          image-aware floating card. */}
      {s.pulsePhotoSheet && (
        <ExpandedPanel
          testId="pulse-photo-sheet"
          photoUrl={eventPhotoUrl(s.pulsePhotoSheet.photo_path)}
          title={s.pulsePhotoSheet.event_name}
          subtitle={s.pulsePhotoSheet.organizer_name + (s.pulsePhotoSheet.organizer_verified ? ' ✓' : '')}
          onClose={closePulsePhotoSheet}
          closeTestId="pulse-photo-sheet-close"
        >
          <div style={{ display: 'flex', gap: 10 }}>
            {/* Heart rule (Task 3) — the glyph itself only ever renders
                filled (liked) or not at all (not liked); no outline/empty
                heart state. */}
            <div
              onClick={() => togglePhotoLike(s.pulsePhotoSheet.photo_id)}
              data-testid="pulse-photo-like"
              style={{
                fontSize: 13, fontWeight: 600, padding: '10px 20px', minHeight: 44, boxSizing: 'border-box', borderRadius: 999, cursor: 'pointer',
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
              style={{ fontSize: 13, fontWeight: 600, padding: '10px 20px', minHeight: 44, boxSizing: 'border-box', display: 'flex', alignItems: 'center', borderRadius: 999, cursor: 'pointer', border: `1px solid ${rule}`, color: ink }}
            >
              {T('Chia sẻ', 'Share')} · {s.photoEngagement[s.pulsePhotoSheet.photo_id]?.shareCount ?? s.pulsePhotoSheet.share_count}
            </div>
          </div>
          <div
            onClick={() => { closePulsePhotoSheet(); closePulseViewer(); goEvent(s.pulsePhotoSheet.event_id); }}
            data-testid="pulse-photo-view-event"
            style={{ marginTop: 2, fontSize: 12, color: ink, textDecoration: 'underline', cursor: 'pointer', minHeight: 44, display: 'flex', alignItems: 'center' }}
          >
            {T('Xem sự kiện / trang tổ chức', 'View event / host page')}
          </div>
        </ExpandedPanel>
      )}

      {/* B3 — tapping a ranked EVENT card opens this panel; now shows the
          event's own real photo + the same honest rank/category/booking/
          check-in breakdown the card itself already shows (never
          fabricated), plus View Host alongside the existing Follow/View
          event actions. */}
      {s.pulseOrganizerSheet && (
        <ExpandedPanel
          photoUrl={eventPhotoUrl(s.pulseOrganizerSheet.photo_path)}
          title={s.pulseOrganizerSheet.event_name}
          subtitle={s.pulseOrganizerSheet.organizer_name + (s.pulseOrganizerSheet.organizer_verified ? ' ✓' : '')}
          metaLine={[
            s.pulseOrganizerSheet.cat_label,
            T(`${s.pulseOrganizerSheet.booking_count ?? 0} vé`, `${s.pulseOrganizerSheet.booking_count ?? 0} bookings`),
            T(`${s.pulseOrganizerSheet.checkin_count ?? 0} check-in`, `${s.pulseOrganizerSheet.checkin_count ?? 0} check-ins`),
          ].filter(Boolean).join(' ▪︎ ')}
          onClose={closePulseOrganizerSheet}
          closeTestId="pulse-organizer-sheet-close"
        >
          <div style={{ display: 'flex', gap: 10, width: '100%' }}>
            <div
              onClick={() => followPulseOrganizer(s.pulseOrganizerSheet.organizer_id)}
              data-testid="pulse-follow"
              style={{
                flex: 1, textAlign: 'center', fontSize: 13.5, fontWeight: 600, padding: '14px 10px', minHeight: 44, boxSizing: 'border-box', borderRadius: 18, cursor: 'pointer',
                background: s.pulseOrganizerSheet.following ? 'transparent' : ink,
                color: s.pulseOrganizerSheet.following ? ink : paper,
                border: s.pulseOrganizerSheet.following ? `1px solid ${rule}` : 'none',
              }}
            >
              {s.pulseOrganizerSheet.following ? T('Đang theo dõi', 'Following') : T('Theo dõi', 'Follow')}
            </div>
            <div
              onClick={() => { closePulseOrganizerSheet(); closePulseViewer(); goEvent(s.pulseOrganizerSheet.event_id); }}
              data-testid="pulse-view-event"
              style={{ flex: 1, textAlign: 'center', fontSize: 13.5, fontWeight: 600, padding: '14px 10px', minHeight: 44, boxSizing: 'border-box', borderRadius: 18, cursor: 'pointer', background: ink, color: paper }}
            >
              {T('Xem sự kiện', 'View event')}
            </div>
          </div>
          <div
            onClick={() => { closePulseOrganizerSheet(); closePulseViewer(); openOrganizerProfile(s.pulseOrganizerSheet.organizer_id); }}
            data-testid="pulse-view-host"
            style={{ fontSize: 12.5, fontWeight: 600, color: ink, textDecoration: 'underline', cursor: 'pointer', minHeight: 44, display: 'flex', alignItems: 'center' }}
          >
            {T('Xem trang tổ chức', 'View host page')}
          </div>
        </ExpandedPanel>
      )}
    </div>
  );
}

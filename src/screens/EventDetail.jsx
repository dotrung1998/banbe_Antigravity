import { useEffect, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { bg, mapsUrl } from '../data/events.js';
import { supabase } from '../lib/supabase.js';
import { paper, ink, rule, display, photoPill, inkButton } from '../theme.js';
import { isBookingTicket } from '../lib/bookingTicket.js';

function eventPhotoUrl(path) {
  const relative = path.replace(/^event-photos\//, '');
  return supabase.storage.from('event-photos').getPublicUrl(relative).data.publicUrl;
}

export default function EventDetail() {
  const { state, T, trStatus, stripKm, curEvent: ev, eventListTitle, goHome, backFromEvent, goOrganizer, goReserve, goChat, shareEvent, openPhoto, askLocation, openHeld, openEventOnMap, createEventShareStory, loadEventPhotos, isSaved, toggleFav } = useGoc();
  const s = state;
  // Structured "Bao gồm" (migration 087) — up to 3 { label, detail } items.
  // Legacy `ev.included` (plain text) stays readable as before when no
  // structured items exist yet (an event created before this pass); never
  // both at once, and the whole row hides when there's genuinely nothing
  // to show (no invented inclusions).
  const includedItems = ev.includedItems || [];
  const [includedSheetOpen, setIncludedSheetOpen] = useState(false);
  // "Giới thiệu sự kiện" (migration 088) — a separate, longer editorial
  // write-up, never the same field as `ev.desc`/"Mô tả" or the "Bao gồm"
  // block above. Plain text only (paragraphs split on a blank line) —
  // never dangerouslySetInnerHTML, so a host's own text can't inject markup.
  const introParagraphs = (ev.intro || '').split(/\n\s*\n/).map(p => p.trim()).filter(Boolean);
  const [introExpanded, setIntroExpanded] = useState(false);
  // STAGE D (2026-09-25) — real event_photos rows, replacing the static
  // demo `ev.gallery` below.
  useEffect(() => { loadEventPhotos(ev.key); }, [ev.key, loadEventPhotos]);
  // Photo identity fix — each gallery entry now carries its own real
  // event_photos.id + owning event id, not just a URL (see openPhoto's own
  // comment in GocContext.jsx). Every photo here belongs to THIS event, so
  // eventId is just ev.key, but it travels per-photo like Organizer.jsx's
  // gallery does, for the same shape both screens hand to openPhoto.
  const realPhotos = (s.eventPhotos || []).map(p => ({ id: p.id, url: eventPhotoUrl(p.storage_path), eventId: ev.key }));
  const [shareStoryMsg, setShareStoryMsg] = useState('');
  // BUG 4 fix (2026-09-22 follow-up) — "Chia sẻ lên Story" used to publish
  // immediately on tap; per this ticket's own instruction, a real
  // confirmation step now sits in between (Cancel writes nothing at all —
  // no DB row, no storage object, no ring change — only the explicit
  // confirm action calls createEventShareStory()).
  const [shareConfirmOpen, setShareConfirmOpen] = useState(false);
  const doShareEventToStory = async () => {
    setShareConfirmOpen(false);
    const r = await createEventShareStory(ev.key);
    setShareStoryMsg(r?.success ? T('Đã đăng lên story', 'Posted to Story') : T('Không đăng được', "Couldn't post"));
    setTimeout(() => setShareStoryMsg(''), 2400);
  };

  // Event Detail is reached from several different places (the home feed, an
  // organizer's dashboard, an organizer profile, the create-event preview),
  // so its "back" pill returns to whichever of those you actually came from,
  // labelled accordingly. A separate, always-available link below it goes
  // straight to Home instead — the two are kept distinct on purpose.
  const BACK_LABELS = {
    home: 'banbe',
    dashboard: T('Trang của bạn', 'Your dashboard'),
    organizer: T('Trang tổ chức', 'Organizer page'),
    create: T('Tạo sự kiện', 'Create event'),
    // Named after whichever list it is ("Going"/"Saved"/"Completed
    // events"), so the pill says where it actually goes.
    eventList: eventListTitle,
    // Follow-up bug 2 (11-realtime-map.md): `eventBackScreen` already
    // correctly resolves to 'mapExplore' when Event Detail was opened from
    // the map's preview card (goEvent()'s own eventBackScreen logic), and
    // backFromEvent() already navigated there correctly — this table just
    // never had an entry for it, so the pill fell through to the 'banbe'
    // default and *said* Home while *going* to the map.
    mapExplore: T('Bản đồ', 'Map'),
  };
  // BUG 3 fix (2026-09-22 follow-up) — an event opened from a story has
  // exactly one consistent origin: StoryViewer, not whichever screen
  // happened to be showing underneath it. The back label now says so
  // explicitly instead of falling through to BACK_LABELS[eventBackScreen]
  // (which used to read "banbe"/"Home" while the tap actually reopened the
  // story — this ticket's own bug report).
  const backLabel = s.eventBackIsStory
    ? (s.storyReturnHostName ? T('Tin của ' + s.storyReturnHostName, s.storyReturnHostName + '’s story') : T('Story', 'Story'))
    : (BACK_LABELS[s.eventBackScreen] || 'banbe');
  const cameFromHome = !s.eventBackIsStory && (s.eventBackScreen || 'home') === 'home';
  // BUG 3 fix (2026-09-22 fifteenth follow-up, iOS parity) — a SEPARATE,
  // narrower condition just for the Map link: the `!s.eventBackIsStory`
  // exclusion baked into `cameFromHome` above used to hide "Xem trên bản
  // đồ" entirely whenever Event Detail was reached from a story, even
  // though `goEventFromStory()` sets `eventBackScreen` to whichever screen
  // the story was opened over (Home, in the common case) — the exact same
  // value a Home-origin open would have. Not an intentional "no map from
  // story" decision, an origin-visibility bug — this event's own
  // coordinates are just as valid either way. Kept separate from
  // `cameFromHome` itself so the unrelated "▪︎ Về trang chính" shortcut
  // above (which SHOULD keep showing for a story origin, same as before)
  // stays untouched.
  const showOpenInMap = (s.eventBackScreen || 'home') === 'home';

  const evCat = trStatus(ev.cat);
  const evWhere = trStatus(stripKm(ev.where, ev));
  const evMapsUrl = mapsUrl(ev);
  const evSeatsLong = trStatus(ev.soldOut ? 'Hết chỗ' : ev.seatsLong);
  const evOrgStats = T('Tổ chức từ ' + ev.orgSince + ' ▪︎ ' + ev.orgCount + ' sự kiện', 'Hosting since ' + ev.orgSince + ' ▪︎ ' + ev.orgCount + ' events');
  const showRefund = !ev.cancelled && ev.endedHoursAgo == null && !/Miễn phí|Free/.test(ev.price);
  const refundNote = T('Nếu sự kiện bị hủy, bạn được hoàn tiền tự động 100%.', 'If the event is cancelled, you are automatically refunded in full.');

  // If the signed-in user already holds a live booking for this exact event,
  // the bar should open their ticket (QR + entry code) instead of running
  // them through Reserve again — this used to show "Reserve" regardless.
  const myBooking = s.booking && s.booking.event_id === ev.key && ['pending', 'confirmed', 'attended'].includes(s.booking.status)
    ? s.booking
    : null;
  // TASK B (2026-10-01 UX foundation pass) — a held/pending booking is NOT
  // a ticket yet. `myBooking.status` alone (checked above) can be
  // 'pending' while payment is still just holding/awaiting verification —
  // this bar used to unconditionally read "Xem vé của bạn ▪︎ mã {code}"
  // for any of those, announcing a ticket + exposing the entry code before
  // there was one. The only source of truth for "ticket exists" is BOTH
  // booking.status === 'confirmed' AND payment_state === 'confirmed'.
  const myBookingIsTicket = isBookingTicket(myBooking);

  // A completed event has nothing left to reserve — showing "Reserve"
  // (or even "Sold out ▪︎ message for waitlist") on something that already
  // happened reads as broken, not just unnecessary.
  const ended = ev.endedHoursAgo != null;
  // Bug 2b (01-hold-payment.md follow-up): `ev.cancelled` already existed
  // and was already used above for `showRefund`, but this bar never
  // checked it — a cancelled event (e.g. "Bàn Dài №4") fell through to the
  // live "Giữ chỗ" default, which then only ever failed later, server-side,
  // via hold_seats()'s own EVENT_NOT_LIVE check. Checked before `ended`/
  // `soldOut` since a cancelled event's stale `seats_remaining` can still
  // read as available or as "sold out" — neither reads as honest here.
  const reserveBarLabel = myBookingIsTicket
    ? T('Xem vé của bạn ▪︎ mã ' + myBooking.code, 'View your ticket ▪︎ code ' + myBooking.code)
    : myBooking
    ? T('Xem trạng thái thanh toán', 'View payment status')
    : ev.cancelled
    ? T('Sự kiện đã bị huỷ', 'Event has been cancelled')
    : ended
    ? T('Sự kiện đã kết thúc', 'Event has ended')
    : ev.soldOut
    ? T('Hết chỗ ▪︎ nhắn để vào danh sách chờ', 'Sold out ▪︎ message for waitlist')
    : (T('Giữ chỗ ▪︎ ', 'Reserve ▪︎ ') + trStatus(ev.price));
  const reserveBarTap = myBooking ? openHeld : (ev.cancelled || ended) ? undefined : (ev.soldOut ? goChat : goReserve);
  const reserveBarStyle = (myBooking || (!ev.soldOut && !ended && !ev.cancelled))
    ? { ...inkButton({ flex: 'none', margin: '0 20px 22px', padding: '15px 0' }) }
    : { flex: 'none', margin: '0 20px 22px', fontSize: 15, fontWeight: 600, textAlign: 'center', padding: '15px 0', borderRadius: 18, cursor: (ended || ev.cancelled) ? 'default' : 'pointer', background: 'rgba(238,232,218,0.92)', color: ink };

  return (
    <div style={{ animation: 'gocFade 0.32s ease both', height: '100%', display: 'flex', flexDirection: 'column', background: paper }} data-screen-label="Event">
      {/* Task 3 (14-photo-viewer.md follow-up notes / 06-design-tokens.md):
          moved out of the photo header (which scrolls away with the rest
          of the content, inside this screen's OWN scroll container below —
          not the shared Shell-level one) into a fixed overlay, so both
          stay visible/tappable the whole time the user scrolls. */}
      <div onClick={backFromEvent} data-testid="event-detail-back" style={photoPill({ position: 'fixed', top: 66, left: 16, padding: '8px 13px', zIndex: 5 })}>‹ {backLabel}</div>
      <div onClick={() => shareEvent(ev)} style={photoPill({ position: 'fixed', top: 66, right: 16, padding: '8px 13px', zIndex: 5 })}>
        {s.shared ? T('Đã sao chép link', 'Link copied') : T('Chia sẻ', 'Share')}
      </div>
      {/* Blocker fix (retention roadmap follow-up) — EventDetail had no save
          affordance at all before this pass, so a real event opened
          directly (not via a card that already has its own "Lưu" chip,
          e.g. a shared link) had no way to be saved from here. Uses Stage
          1's exact same isSaved/toggleFav — already catalogue-agnostic
          (both key off the real `favorites` table by event id), so this
          works identically for a static demo event and a real host-created
          one with no special-casing. */}
      <div
        onClick={() => toggleFav(ev.key)}
        data-testid="event-detail-save"
        style={photoPill({ position: 'fixed', top: 112, right: 16, padding: '8px 13px', zIndex: 5 })}
      >
        {isSaved(ev.key) ? T('Đã lưu', 'Saved') : T('Lưu', 'Save')}
      </div>
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>
      <div style={{ position: 'relative', height: 400 }}>
        {ev.img ? (
          <div style={bg(ev.img, { width: '100%', height: '100%', borderRadius: 0 })} />
        ) : (
          // A real event with no photo yet (or one still loading/
          // unavailable) — an honest neutral block, never a wrong demo
          // event's photo standing in for it.
          <div style={{ width: '100%', height: '100%', background: rule }} />
        )}
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 78, pointerEvents: 'none', background: `linear-gradient(to bottom, rgba(247,244,236,0) 0%, rgba(247,244,236,0.3) 62%, ${paper} 100%)` }} />
      </div>
      <div style={{ padding: '22px 22px 30px', display: 'flex', flexDirection: 'column' }}>
        {!cameFromHome && (
          <div onClick={goHome} style={{ fontSize: 11.5, color: ink, opacity: 0.65, cursor: 'pointer', marginBottom: 10 }}>{T('▪︎ Về trang chính', '▪︎ Back to home')}</div>
        )}
        {/* Task 1a: only when this screen was reached from Home, not from
            tapping the event inside Map's own sheet list — reuses the
            exact same `cameFromHome`/`eventBackScreen` convention the
            "Về trang chính" link right above already established, just
            the opposite condition (that one hides FROM home; this one
            shows only FROM home). MapExplore's own info card for this
            pin — the same `selectedEvent` card `MapExplore.jsx` already
            renders for a pin/list tap — appears automatically once there,
            since `openEventOnMap` sets `selectedId` the same way. */}
        {showOpenInMap && (
          <div data-testid="event-open-in-map" onClick={() => openEventOnMap(ev)} style={{ fontSize: 11.5, color: ink, opacity: 0.65, cursor: 'pointer', marginBottom: 10 }}>{T('▪︎ Xem trên bản đồ', '▪︎ Open in map')}</div>
        )}
        {/* Task 4B (2026-09-22 follow-up) — only when the signed-in
            account actually owns/manages this exact event's organizer
            (s.myOrgEventKeys, loaded at sign-in from the real
            event -> organizer -> owner_id/user_id relationship) — never
            for a goer, no matter how they reached this event. This is a
            UI nicety only; create_event_share_story() (migration 068)
            re-checks ownership server-side regardless. */}
        {s.myOrgEventKeys.includes(ev.key) && (
          <div
            data-testid="event-share-to-story"
            onClick={s.storyCreateBusy ? undefined : () => setShareConfirmOpen(true)}
            style={{ fontSize: 11.5, color: ink, opacity: s.storyCreateBusy ? 0.4 : 0.65, cursor: s.storyCreateBusy ? 'default' : 'pointer', marginBottom: 10 }}
          >
            {s.storyCreateBusy ? T('Đang đăng…', 'Posting…') : T('▪︎ Chia sẻ lên Story', '▪︎ Share to Story')}
          </div>
        )}
        {shareStoryMsg && (
          <div style={{ fontSize: 11, color: ink, opacity: 0.7, marginBottom: 10 }}>{shareStoryMsg}</div>
        )}
        {/* BUG 4 fix — a real confirm step, same bottom-sheet visual
            convention ReasonSheet.jsx already established (dim overlay +
            a paper panel sliding up). Cancel writes nothing at all. */}
        {shareConfirmOpen && (
          <div onClick={s.storyCreateBusy ? undefined : () => setShareConfirmOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 40, background: 'rgba(12,12,12,0.55)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'gocFade 0.2s ease both' }}>
            <div onClick={(e) => e.stopPropagation()} style={{ background: paper, padding: '20px 20px 30px', animation: 'gocSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
              <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
                <div style={bg(ev.img, { width: 64, height: 64, borderRadius: 12, flex: 'none' })} />
                <div style={{ minWidth: 0 }}>
                  <div style={{ ...display(15, { lineHeight: 1.2 }) }}>{ev.name}</div>
                  <div style={{ fontSize: 11.5, color: ink, opacity: 0.7, marginTop: 2 }}>{ev.when}</div>
                </div>
              </div>
              <p style={{ fontSize: 12, lineHeight: 1.5, color: ink, opacity: 0.7, margin: '14px 0 0' }}>
                {T('Sẽ hiển thị dưới dạng story trong 24 giờ.', 'This will be visible as a story for 24 hours.')}
              </p>
              <div style={{ display: 'flex', gap: 8, marginTop: 16 }}>
                <div
                  onClick={() => setShareConfirmOpen(false)}
                  data-testid="event-share-to-story-cancel"
                  style={{ flex: 1, textAlign: 'center', fontSize: 13, fontWeight: 600, padding: '11px 12px', borderRadius: 12, cursor: 'pointer', border: `1px solid ${rule}`, color: ink }}
                >
                  {T('Hủy', 'Cancel')}
                </div>
                <div
                  onClick={doShareEventToStory}
                  data-testid="event-share-to-story-confirm"
                  style={{ flex: 1, textAlign: 'center', fontSize: 13, fontWeight: 600, padding: '11px 12px', borderRadius: 12, cursor: 'pointer', background: ink, color: paper }}
                >
                  {T('Đăng Story', 'Post Story')}
                </div>
              </div>
            </div>
          </div>
        )}
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ fontSize: 11.5, color: ink }}>{evCat}</span>
          {ev.inviteOnly && (
            <span style={{ fontSize: 10, fontWeight: 600, letterSpacing: '0.04em', color: paper, background: ink, padding: '3px 8px' }}>{T('Riêng tư ▪︎ theo lời mời', 'Private ▪︎ invite only')}</span>
          )}
        </div>
        <h1 style={{ ...display(29, { lineHeight: 1.2, margin: '8px 0 10px' }) }}>{ev.name}</h1>
        {evMapsUrl ? (
          <a
            href={evMapsUrl}
            target="_blank"
            rel="noopener noreferrer"
            // Opening directions is the natural moment to also offer to show
            // the distance, if that hasn't been decided yet — this never
            // blocks the click itself, since the maps link still opens via
            // the normal href navigation regardless of what's clicked here.
            onClick={() => { if (s.located === null) askLocation(); }}
            style={{ fontSize: 13, color: ink, textDecoration: 'underline', textDecorationColor: 'rgba(27,25,22,0.35)', textUnderlineOffset: 2 }}
          >
            {evWhere} ↗
          </a>
        ) : (
          <div style={{ fontSize: 13, color: ink }}>{evWhere}</div>
        )}
        <div style={{ fontSize: 13, color: ink, marginTop: 5 }}>{evSeatsLong}</div>
        {ev.inviteOnly && (
          <div style={{ fontSize: 12.5, color: ink, marginTop: 6 }}>{T('Bạn có thể mời thêm 1 người.', 'You can bring one +1.')}</div>
        )}
        <p style={{ fontSize: 14, lineHeight: 1.55, color: ink, margin: '20px 0 0' }}>{ev.desc}</p>
        {introParagraphs.length > 0 && (
          <div data-testid="event-intro-section" style={{ marginTop: 18 }}>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Giới thiệu sự kiện', 'About this event')}</span>
            <div style={{ marginTop: 8, overflow: 'hidden', maxHeight: introExpanded ? 'none' : 90, position: 'relative' }}>
              {(introExpanded ? introParagraphs : introParagraphs.slice(0, 1)).map((p, i) => (
                <p key={i} style={{ fontSize: 13.5, lineHeight: 1.6, color: ink, margin: i === 0 ? 0 : '10px 0 0', whiteSpace: 'pre-wrap' }}>{p}</p>
              ))}
              {!introExpanded && (
                <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, height: 36, background: `linear-gradient(to bottom, transparent, ${paper})` }} />
              )}
            </div>
            {(introExpanded || introParagraphs.length > 1 || introParagraphs[0]?.length > 160) && (
              <span
                onClick={() => setIntroExpanded(v => !v)}
                data-testid="event-intro-toggle"
                style={{ fontSize: 12.5, fontWeight: 600, color: ink, textDecoration: 'underline', cursor: 'pointer', display: 'inline-block', marginTop: 6 }}
              >
                {introExpanded ? T('Thu gọn', 'Show less') : T('Đọc thêm', 'Read more')}
              </span>
            )}
          </div>
        )}
        <div style={{ marginTop: 22, borderTop: `1px solid ${rule}` }}>
          {includedItems.length > 0 ? (
            // The whole section is tappable — opens a sheet with each
            // item's full label as a heading and its detail beneath.
            <div
              onClick={() => setIncludedSheetOpen(true)}
              data-testid="event-included-section"
              style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 18, padding: '12px 0', borderBottom: `1px solid ${rule}`, fontSize: 13, cursor: 'pointer' }}
            >
              <span style={{ color: ink, flex: 'none' }}>{T('Bao gồm', 'Included')}</span>
              <span style={{ color: ink, textAlign: 'right', display: 'flex', flexWrap: 'wrap', justifyContent: 'flex-end', gap: '2px 6px' }}>
                {includedItems.map((it, i) => (
                  <span key={i}>{it.label}{i < includedItems.length - 1 ? ' ▪︎' : ''}</span>
                ))}
                <span style={{ opacity: 0.55 }}>›</span>
              </span>
            </div>
          ) : ev.included ? (
            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 18, padding: '12px 0', borderBottom: `1px solid ${rule}`, fontSize: 13 }}>
              <span style={{ color: ink, flex: 'none' }}>{T('Bao gồm', 'Included')}</span>
              <span style={{ color: ink, textAlign: 'right' }}>{ev.included}</span>
            </div>
          ) : null}
          <div onClick={goOrganizer} style={{ display: 'flex', justifyContent: 'space-between', padding: '12px 0', borderBottom: `1px solid ${rule}`, fontSize: 13, cursor: 'pointer' }}>
            <span style={{ color: ink }}>{T('Người tổ chức', 'Organizer')}</span>
            <span style={{ color: ink }}>{T('Ghé', 'Visit')} {ev.orgName} ›</span>
          </div>
          {ev.orgTrusted && (
            <div style={{ display: 'flex', justifyContent: 'space-between', padding: '12px 0', borderBottom: `1px solid ${rule}`, fontSize: 12 }}>
              <span style={{ color: ink }}>{T('Uy tín', 'Track record')}</span>
              <span style={{ color: ink }}>{evOrgStats}</span>
            </div>
          )}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', padding: '16px 0 0' }}>
            <span style={{ fontSize: 13, color: ink }}>{T('Giá', 'Price')}</span>
            <span style={{ ...display(23) }}>{trStatus(ev.price)}</span>
          </div>
        </div>
        {showRefund && <p style={{ margin: '14px 0 0', fontSize: 11.5, lineHeight: 1.5, color: ink, textAlign: 'center' }}>{refundNote}</p>}
        <div style={{ marginTop: 28 }}>
          <span style={{ fontSize: 11.5, color: ink }}>{T('Hình ảnh', 'Photos')}</span>
          {/* STAGE D (2026-09-25) — real event_photos rows, not the static
              demo `ev.gallery`. A genuinely photo-less real event shows
              plain text, never a fake/demo photo standing in for a real
              one. */}
          {s.eventPhotosLoading ? (
            <p style={{ fontSize: 12.5, color: ink, opacity: 0.6, marginTop: 12 }}>{T('Đang tải…', 'Loading…')}</p>
          ) : realPhotos.length ? (
            <div style={{ display: 'flex', gap: 8, overflowX: 'auto', marginTop: 12, paddingBottom: 4 }}>
              {realPhotos.map((p, i) => (
                <div key={p.id} onClick={(e) => openPhoto(realPhotos, i, ev.orgName, e.currentTarget.getBoundingClientRect())} style={{ position: 'relative', flex: 'none' }}>
                  <div style={bg(p.url, { width: 148, height: 186, cursor: 'pointer' })} />
                  {/* A.7 — a liked photo gets a filled heart badge; an
                      unliked one shows no heart glyph at all here (only the
                      full-screen viewer's own like button, opened by
                      tapping the photo, is the discoverable way to like
                      it). */}
                  {s.photoEngagement[p.id]?.likedByMe && (
                    <span style={{ position: 'absolute', top: 8, right: 8, color: '#fff', filter: 'drop-shadow(0 1px 2px rgba(0,0,0,0.55))', pointerEvents: 'none' }}>
                      <svg width={15} height={15} viewBox="0 0 24 24" fill="currentColor"><path d="M12 20.5S3.5 15 3.5 9.2A4.7 4.7 0 0 1 12 6.5a4.7 4.7 0 0 1 8.5 2.7c0 5.8-8.5 11.3-8.5 11.3Z" /></svg>
                    </span>
                  )}
                </div>
              ))}
            </div>
          ) : (
            <p style={{ fontSize: 12.5, color: ink, opacity: 0.6, marginTop: 12 }}>{T('Chưa có ảnh nào cho sự kiện này.', 'No photos for this event yet.')}</p>
          )}
        </div>
      </div>
      </div>
      <div onClick={reserveBarTap} style={reserveBarStyle}>{reserveBarLabel}</div>
      {includedSheetOpen && (
        <div
          onClick={() => setIncludedSheetOpen(false)}
          data-testid="event-included-sheet"
          style={{ position: 'fixed', inset: 0, background: 'rgba(27,25,22,0.45)', display: 'flex', alignItems: 'flex-end', zIndex: 40 }}
        >
          <div
            onClick={(e) => e.stopPropagation()}
            style={{ background: paper, width: '100%', maxHeight: '70vh', overflowY: 'auto', borderRadius: '18px 18px 0 0', padding: '20px 22px 34px', display: 'flex', flexDirection: 'column', gap: 16 }}
          >
            <div style={{ width: 36, height: 4, background: rule, borderRadius: 2, alignSelf: 'center' }} />
            <span style={{ ...display(18) }}>{T('Bao gồm', 'What’s included')}</span>
            {includedItems.map((it, i) => (
              <div key={i} style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                <span style={{ ...display(15) }}>{it.label}</span>
                {it.detail && <span style={{ fontSize: 13, lineHeight: 1.55, color: ink }}>{it.detail}</span>}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

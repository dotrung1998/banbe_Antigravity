import { useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { bg, mapsUrl } from '../data/events.js';
import { paper, ink, rule, display, photoPill, inkButton } from '../theme.js';

export default function EventDetail() {
  const { state, T, trStatus, stripKm, curEvent: ev, eventListTitle, goHome, backFromEvent, goOrganizer, goReserve, goChat, shareEvent, openPhoto, askLocation, openHeld, openEventOnMap, createEventShareStory } = useGoc();
  const s = state;
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
  const reserveBarLabel = myBooking
    ? T('Xem vé của bạn ▪︎ mã ' + myBooking.code, 'View your ticket ▪︎ code ' + myBooking.code)
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
      <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>
      <div style={{ position: 'relative', height: 400 }}>
        <div style={bg(ev.img, { width: '100%', height: '100%', borderRadius: 0 })} />
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
        {cameFromHome && (
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
        <div style={{ marginTop: 22, borderTop: `1px solid ${rule}` }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', gap: 18, padding: '12px 0', borderBottom: `1px solid ${rule}`, fontSize: 13 }}>
            <span style={{ color: ink, flex: 'none' }}>{T('Bao gồm', 'Included')}</span>
            <span style={{ color: ink, textAlign: 'right' }}>{ev.included}</span>
          </div>
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
          <div style={{ display: 'flex', gap: 8, overflowX: 'auto', marginTop: 12, paddingBottom: 4 }}>
            {ev.gallery.map((u, i) => (
              <div key={i} onClick={(e) => openPhoto(ev.gallery, i, ev.orgName, ev.key, e.currentTarget.getBoundingClientRect())} style={bg(u, { flex: 'none', width: 148, height: 186, cursor: 'pointer' })} />
            ))}
          </div>
        </div>
      </div>
      </div>
      <div onClick={reserveBarTap} style={reserveBarStyle}>{reserveBarLabel}</div>
    </div>
  );
}

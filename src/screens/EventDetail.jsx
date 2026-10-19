import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { recentZoomOrigin } from '../lib/zoomOrigin.js';
import { useBanBe } from '../state/BanBeContext.jsx';
import { bg, mapsUrl } from '../data/events.js';
import { paper, ink, rule, display, photoPill, inkButton, barGlass, RADIUS } from '../theme.js';
import { isBookingTicket } from '../lib/bookingTicket.js';
import { useReservationCriteria, WhoCanReserve, CriteriaUnmetCard } from './ReservationCriteria.jsx';
import FollowingBadge from '../components/FollowingBadge.jsx';
import EventPlanTitle from './EventPlanActions.jsx';
import { organizerAvatarPublicUrl } from '../lib/mediaUrls.js';
import { reserveBarState, totalPrice, clampQty, QTY_PRESETS, MAX_QTY } from '../lib/reserveBar.js';
import { CountStepper } from '../components/ui/FormControls.jsx';

// Airbnb-style layout (mirrors iOS EventDetailView): the photo is a pinned backdrop that fades out while the
// rounded info sheet scrolls up over it; pulling down from the very top closes the screen with a shrink.
const HERO_H = 400;
const SHEET_OVERLAP = 40;
const SHEET_RADIUS = 46; // the iPhone's own screen-corner curvature
const PINNED_STRIP = 120; // with the info fully pulled up, this much of the photo stays visible above it

const ico = { width: 16, height: 16, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 1.6, strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': true };
const IconShare = () => (<svg {...ico} width={18} height={18}><path d="M12 15V3M8 7l4-4 4 4" /><path d="M5 11v8a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-8" /></svg>);
const IconHeart = ({ filled }) => (<svg {...ico} width={18} height={18} fill={filled ? '#C8372D' : 'none'} stroke={filled ? '#C8372D' : 'currentColor'}><path d="M12 20.5S3.5 15 3.5 9.2A4.7 4.7 0 0 1 12 6.5a4.7 4.7 0 0 1 8.5 2.7c0 5.8-8.5 11.3-8.5 11.3Z" /></svg>);
const IconHouse = () => (<svg {...ico}><path d="M4 11l8-7 8 7" /><path d="M6 10v10h12V10" /></svg>);
const IconMap = () => (<svg {...ico}><path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2z" /><path d="M9 4v14M15 6v14" /></svg>);
const IconCamera = () => (<svg {...ico}><path d="M4 8h3l2-3h6l2 3h3v11H4z" /><circle cx="12" cy="13" r="3.4" /></svg>);
const IconList = () => (<svg {...ico}><path d="M4 7l1.6 1.6L8 6M4 15l1.6 1.6L8 14" /><path d="M11 7h9M11 15h9" /></svg>);
const IconChat = () => (<svg {...ico}><path d="M5 5h14a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1h-8l-5 4v-4H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z" /></svg>);
const iconCol = { flex: 'none', width: 22, display: 'inline-flex', justifyContent: 'center', color: ink, opacity: 0.8 };
// One hairline weight for the page's own dividers: softer than `rule`, so sections read as one surface, not blocks.
const softRule = 'rgba(var(--bb-fg-rgb),0.10)';
const sectionLabel = { fontSize: 12, fontWeight: 600, letterSpacing: '0.08em', textTransform: 'uppercase', color: ink, opacity: 0.7 };
const listRow = { display: 'flex', alignItems: 'center', gap: 12, padding: '14px 0', borderBottom: `1px solid ${softRule}`, fontSize: 14, color: ink };
// Top of the floating round controls: the old fixed 66px, but never closer to the notch than inset + 16.
const OVERLAY_TOP = 'max(66px, calc(env(safe-area-inset-top, 0px) + 16px))';
const SR_ONLY = { position: 'absolute', width: 1, height: 1, overflow: 'hidden', clip: 'rect(0 0 0 0)', whiteSpace: 'nowrap' };
const IconMore = () => (<svg {...ico} width={18} height={18}><circle cx="5.5" cy="12" r="1.2" fill="currentColor" /><circle cx="12" cy="12" r="1.2" fill="currentColor" /><circle cx="18.5" cy="12" r="1.2" fill="currentColor" /></svg>);
const IconClock = () => (<svg {...ico}><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 2" /></svg>);
const IconPin = () => (<svg {...ico}><path d="M12 21s6.5-5.6 6.5-11a6.5 6.5 0 0 0-13 0C5.5 15.4 12 21 12 21Z" /><circle cx="12" cy="10" r="2.3" /></svg>);
const IconTag = () => (<svg {...ico}><path d="M3.5 12.2V4.5a1 1 0 0 1 1-1h7.7l8.3 8.3-8.7 8.7z" /><circle cx="8" cy="8" r="1.3" /></svg>);
const IconSeat = () => (<svg {...ico}><path d="M6 11V6a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v5" /><path d="M4 11h16v4H4zM6 15v4M18 15v4" /></svg>);
// One row for the "key facts" block: icon column, label-free value, optional tap target.
const FactRow = ({ icon, onClick, testId, children }) => (
  <div onClick={onClick} data-testid={testId} style={{ display: 'flex', alignItems: 'flex-start', gap: 12, padding: '7px 0', fontSize: 14, lineHeight: 1.4, color: ink, cursor: onClick ? 'pointer' : 'default' }}>
    <span style={{ ...iconCol, height: 20, alignItems: 'center' }}>{icon}</span>
    <span style={{ flex: 1, minWidth: 0 }}>{children}</span>
  </div>
);

export default function EventDetail() {
  const { state, T, trStatus, stripKm, curEvent: ev, eventListTitle, goHome, backFromEvent, openOrganizerOfEvent, loadEventOrgStats, goReserve, setQty, goChat, shareEvent, openPhoto, askLocation, openHeld, openEventOnMap, createEventShareStory, loadEventPhotos, isSaved, toggleFav } = useBanBe();
  const s = state;
  const scrollerRef = useRef(null);
  const heroRef = useRef(null);
  const heroImgRef = useRef(null);
  const cardRef = useRef(null);
  const dimRef = useRef(null);
  // (The open animation uses fill-mode `backwards`: a filling transform animation would override the drag/close inline transform.)
  const dragRef = useRef({ active: false, startY: 0, startX: 0, dy: 0, closing: false });
  // Zoom out of the tapped card (and back into it on close), like iOS. `null` when opened from anywhere without one.
  const zoomRef = useRef(undefined);
  if (zoomRef.current === undefined) zoomRef.current = recentZoomOrigin();
  const zoomPose = (o, R) => {
    const sc = Math.max(0.05, o.width / R.width);
    return {
      transformOrigin: '0 0',
      transform: `translate(${o.left - R.left}px, ${o.top - R.top}px) scale(${sc})`,
      clipPath: `inset(0px 0px ${Math.max(0, R.height - o.height / sc)}px 0px round ${14 / sc}px)`,
    };
  };
  const ZOOM_MS = 560;
  const ZOOM_EASE = 'cubic-bezier(.22,.9,.3,1)';
  // The photo is the shared element: it grows out of the tapped card to the full-bleed cover. The page itself
  // (background, info sheet, buttons: everything marked data-fade) fades in after the photo has started to move.
  const fadeEls = () => Array.from(cardRef.current?.querySelectorAll('[data-fade]') || []);
  useLayoutEffect(() => {
    const o = zoomRef.current; const hero = heroRef.current;
    if (!o || !hero || !hero.animate) return;
    const R = hero.getBoundingClientRect();
    if (!R.width || !R.height) return;
    hero.animate([zoomPose(o, R), { transformOrigin: '0 0', transform: 'translate(0px, 0px) scale(1)', clipPath: 'inset(0px 0px 0px 0px round 0px)' }], { duration: ZOOM_MS, easing: ZOOM_EASE });
    fadeEls().forEach(el => el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 360, delay: 200, easing: 'ease-out', fill: 'backwards' }));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  // A small physical tap (where the device supports it) as the screen opens and closes, like iOS.
  const buzz = () => { try { navigator.vibrate?.(10); } catch { /* unsupported */ } };
  useEffect(() => { buzz(); }, []);
  // Close with the same shrink-and-fade the pull-down finishes with, then navigate back.
  const closeWithShrink = () => {
    const card = cardRef.current;
    const d = dragRef.current;
    if (d.closing) return;
    d.closing = true;
    buzz();
    if (!card) { backFromEvent(); return; }
    const o = zoomRef.current; const hero = heroRef.current;
    if (o && hero?.animate) {
      // Drop any pull-down pose, fade the page out first, then shrink the photo back into the card it came from.
      card.style.transition = 'none'; card.style.transform = ''; card.style.borderRadius = ''; card.style.overflow = '';
      fadeEls().forEach(el => el.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 220, easing: 'ease-in', fill: 'forwards' }));
      const R = hero.getBoundingClientRect();
      hero.animate([{ transformOrigin: '0 0', transform: 'translate(0px, 0px) scale(1)', clipPath: 'inset(0px 0px 0px 0px round 0px)' }, zoomPose(o, R)], { duration: ZOOM_MS - 40, easing: 'cubic-bezier(.4,0,.2,1)', fill: 'forwards' });
      setTimeout(() => backFromEvent(), ZOOM_MS - 60);
      return;
    }
    card.style.transition = 'transform 0.44s cubic-bezier(.4,0,.6,1), opacity 0.4s ease, border-radius 0.3s ease';
    card.style.transform = 'translateY(60px) scale(0.86)';
    card.style.opacity = '0';
    card.style.borderRadius = `${SHEET_RADIUS}px`;
    card.style.overflow = 'hidden';
    setTimeout(() => backFromEvent(), 430);
  };
  // Host reservation criteria (migration 162). Not gated on "real" events: a demo-catalogue key
  // (e.g. 'bepnho') can also be a real DB row with criteria; a key with no row resolves to Everyone.
  const crit = useReservationCriteria(ev.key);
  // Structured "Bao gồm" (migration 087) — up to 3 { label, detail } items.
  // Legacy `ev.included` (plain text) stays readable as before when no
  // structured items exist yet (an event created before this pass); never
  // both at once, and the whole row hides when there's genuinely nothing
  // to show (no invented inclusions).
  const includedItems = ev.includedItems || [];
  const [includedSheetOpen, setIncludedSheetOpen] = useState(false);
  const canClamp = (includedItems.length > 0 || (ev.intro || '').trim().length > 0) && (ev.desc || '').length > 180;
  // "Giới thiệu sự kiện" (migration 088) — a separate, longer editorial
  // write-up, never the same field as `ev.desc`/"Mô tả" or the "Bao gồm"
  // block above. Plain text only (paragraphs split on a blank line) —
  // never dangerouslySetInnerHTML, so a host's own text can't inject markup.
  const introParagraphs = (ev.intro || '').split(/\n\s*\n/).map(p => p.trim()).filter(Boolean);
  // STAGE D (2026-09-25) — real event_photos rows, replacing the static
  // demo `ev.gallery` below.
  useEffect(() => { loadEventPhotos(ev.key); }, [ev.key, loadEventPhotos]);
  // Photo identity fix — each gallery entry now carries its own real
  // event_photos.id + owning event id, not just a URL (see openPhoto's own
  // comment in BanBeContext.jsx). Every photo here belongs to THIS event, so
  // eventId is just ev.key, but it travels per-photo like Organizer.jsx's
  // gallery does, for the same shape both screens hand to openPhoto.
  const realPhotos = (s.eventPhotos || []).filter(p => p.url).map(p => ({ id: p.id, url: p.url, eventId: ev.key }));
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
    organizerProfile: T('Trang tổ chức', 'Organizer page'),
    create: T('Tạo Sự Kiện', 'Create Event'),
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
  // `where` is "area ▪︎ distance ▪︎ day ▪︎ time" (one line on the old layout); the date now has its own fact row, so
  // the location row keeps only the place and, once located, the distance.
  const evWhere = trStatus(stripKm(ev.where, ev).split(' ▪︎ ').filter((seg, i) => i === 0 || / km/.test(seg)).join(' ▪︎ '));
  const evMapsUrl = mapsUrl(ev);
  const evSeatsLong = trStatus(ev.soldOut ? 'Hết chỗ' : ev.seatsLong);
  // Track record is live (get_organizer_profile via loadEventOrgStats), not the
  // catalogue's baked-in orgSince/orgCount; the row is hidden until real stats
  // exist for this host.
  // Real events carry their organizer id; the demo catalogue has none (never marked followed).
  const evOrganizerId = s.realEventsById[ev.key]?.organizerId;
  const evOrgFollowed = !!evOrganizerId && s.followedOrgIds.includes(evOrganizerId);
  const orgStats = s.eventOrgStats[ev.key];
  const evOrgStats = orgStats && orgStats.count > 0
    ? (orgStats.sinceYear
      ? T(`Tổ chức từ ${orgStats.sinceYear} ▪︎ ${orgStats.count} sự kiện`, `Hosting since ${orgStats.sinceYear} ▪︎ ${orgStats.count} events`)
      : T(`${orgStats.count} sự kiện`, `${orgStats.count} events`))
    : null;
  useEffect(() => { loadEventOrgStats(ev.key); }, [ev.key, loadEventOrgStats]);
  const showRefund = !ev.cancelled && ev.endedHoursAgo == null && !/Miễn phí|Free/.test(ev.price);

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
  // Blocked only when the server said ineligible and there is no booking/closed state to show.
  const criteriaBlocked = crit.blocked && !myBooking && !ev.cancelled && !ended && !ev.soldOut;
  // One state for the sticky bar (src/lib/reserveBar.js, mirrored on iOS). Cancelled is checked before ended/sold
  // out because a cancelled event's stale `seats_remaining` can still read as available or as "sold out".
  const barState = reserveBarState({ booking: !!myBooking, ticket: myBookingIsTicket, cancelled: !!ev.cancelled, ended, soldOut: !!ev.soldOut, blocked: criteriaBlocked });
  const qty = clampQty(s.qty);
  const totalStr = trStatus(totalPrice(ev.price, qty));
  const [qtyMore, setQtyMore] = useState(() => !QTY_PRESETS.includes(qty));
  const critRef = useRef(null);
  const reserveBarLabel = {
    ticket: () => T('Xem vé của bạn ▪︎ mã ' + myBooking.code, 'View your ticket ▪︎ code ' + myBooking.code),
    pending: () => T('Xem trạng thái thanh toán', 'View payment status'),
    cancelled: () => T('Sự kiện đã bị huỷ', 'Event has been cancelled'),
    ended: () => T('Sự kiện đã kết thúc', 'Event has ended'),
    soldOut: () => T('Hết chỗ ▪︎ nhắn để vào danh sách chờ', 'Sold out ▪︎ message for waitlist'),
    // The bar says WHY it can't be used, and tapping shows the full explanation card instead of doing nothing.
    blocked: () => T('Chưa đủ điều kiện ▪︎ xem lý do', 'Not eligible yet ▪︎ see why'),
    // Outcome + total before the tap (the user knows what they are about to hold and pay).
    reserve: () => (qty === 1 ? T('Giữ chỗ ▪︎ ', 'Reserve ▪︎ ') : T(`Giữ ${qty} chỗ ▪︎ `, `Reserve ${qty} seats ▪︎ `)) + totalStr,
  }[barState]();
  const showCriteriaWhy = () => critRef.current?.scrollIntoView?.({ behavior: 'smooth', block: 'center' });
  const reserveBarTap = { ticket: openHeld, pending: openHeld, cancelled: undefined, ended: undefined, soldOut: goChat, blocked: showCriteriaWhy, reserve: goReserve }[barState];
  const ctaBase = { fontSize: 15, fontWeight: 600, textAlign: 'center', padding: '15px 12px', borderRadius: 18, color: ink };
  const reserveBarStyle = (barState === 'reserve' || barState === 'ticket' || barState === 'pending')
    ? inkButton({ padding: '15px 12px' })
    : { ...ctaBase, background: 'var(--bb-field)', cursor: reserveBarTap ? 'pointer' : 'default', opacity: barState === 'blocked' ? 0.85 : 1 };
  // One honest line under the CTA: what happens on tap, and the refund promise (was a floating note mid-page).
  const trustLine = barState !== 'reserve' ? null
    : T('Giữ chỗ 30 phút để thanh toán', 'Held 30 min while you pay')
      + (showRefund ? T(' ▪︎ hoàn 100% nếu huỷ', ' ▪︎ full refund if cancelled') : '');
  const qtyChip = (n, label) => {
    const on = qty === n;
    return (
      <div key={label || n} role="radio" aria-checked={on} onClick={() => { setQty(n); setQtyMore(false); }} data-testid={`event-qty-${n}`}
        style={{ minWidth: 40, height: 32, padding: '0 10px', borderRadius: RADIUS.pill, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 14, fontWeight: 600, cursor: 'pointer', border: `1px solid ${on ? ink : rule}`, background: on ? ink : 'transparent', color: on ? paper : ink }}>
        {label || n}
      </div>
    );
  };

  // The photo backdrop fades to the page colour and drifts up slowly as the sheet rises over it.
  const onSheetScroll = (e) => {
    const t = Math.max(0, e.currentTarget.scrollTop);
    // Fades only part-way: the strip left above the pulled-up info stays clearly visible.
    if (heroRef.current) heroRef.current.style.opacity = String(1 - 0.4 * Math.min(1, t / (HERO_H * 0.62)));
    if (heroImgRef.current) heroImgRef.current.style.transform = `translateY(${-Math.min(t, HERO_H) * 0.3}px)`;
  };

  // Pull down from the very top to close: the screen follows the finger (shrinking, rounding, dimming); a long
  // pull or a flick finishes with the same shrink-and-fade, anything else springs back. Never starts mid-scroll
  // (so it also replaces the app-wide pull-to-refresh here, which App.jsx skips for this screen).
  useEffect(() => {
    const scroller = scrollerRef.current;
    const card = cardRef.current;
    if (!scroller || !card) return undefined;
    const d = dragRef.current;
    const apply = (dy, animate) => {
      const p = Math.min(1, Math.max(0, dy / 320));
      card.style.transition = animate ? 'transform 0.34s cubic-bezier(.22,.61,.36,1), opacity 0.24s ease, border-radius 0.3s ease' : 'none';
      card.style.transform = dy ? `translateY(${dy * 0.35}px) scale(${1 - 0.16 * p})` : '';
      card.style.borderRadius = dy ? `${Math.min(SHEET_RADIUS, p * 120)}px` : '';
      card.style.overflow = dy ? 'hidden' : '';
      if (dimRef.current) { dimRef.current.style.transition = animate ? 'opacity 0.3s ease' : 'none'; dimRef.current.style.opacity = String(dy ? 0.42 * (1 - p * 0.6) : 0); }
    };
    const begin = (x, y) => { d.active = false; d.startX = x; d.startY = y; d.dy = 0; d.tracking = scroller.scrollTop <= 1 && !d.closing; };
    const move = (x, y, e) => {
      if (!d.tracking || d.closing) return;
      // Once this touch has scrolled the sheet at all, it is a scroll for the rest of the gesture: scrolling up and
      // back down to the top in one go must never turn into pull-down-to-close.
      if (scroller.scrollTop > 1) { d.tracking = false; return; }
      const dx = x - d.startX; const dy = y - d.startY;
      if (!d.active) {
        if (dy > 10 && dy > Math.abs(dx) * 1.2 && scroller.scrollTop <= 1) d.active = true; else return;
      }
      d.dy = Math.max(0, dy);
      if (e.cancelable) e.preventDefault();
      apply(d.dy, false);
    };
    const finish = (velocityPx) => {
      if (!d.active) { d.tracking = false; return; }
      d.active = false; d.tracking = false;
      if (d.dy > 140 || velocityPx > 0.9) {
        d.closing = true;
        d.closing = false;
        closeWithShrink();
      } else {
        apply(0, true);
      }
    };
    let last = { y: 0, t: 0, v: 0 };
    const track = (y) => { const now = performance.now(); if (last.t) last.v = (y - last.y) / Math.max(1, now - last.t); last = { y, t: now, v: last.v }; };
    const ts = (e) => { const t = e.touches[0]; last = { y: t.clientY, t: 0, v: 0 }; begin(t.clientX, t.clientY); };
    const tm = (e) => { const t = e.touches[0]; track(t.clientY); move(t.clientX, t.clientY, e); };
    const te = () => finish(last.v);
    scroller.addEventListener('touchstart', ts, { passive: true });
    scroller.addEventListener('touchmove', tm, { passive: false });
    scroller.addEventListener('touchend', te);
    scroller.addEventListener('touchcancel', te);
    // Mouse (desktop) — same gesture, tracked on the window while the button is down.
    const mm = (e) => { track(e.clientY); move(e.clientX, e.clientY, e); };
    const mu = () => { window.removeEventListener('mousemove', mm); window.removeEventListener('mouseup', mu); finish(last.v); };
    const md = (e) => { if (e.button !== 0) return; last = { y: e.clientY, t: 0, v: 0 }; begin(e.clientX, e.clientY); window.addEventListener('mousemove', mm); window.addEventListener('mouseup', mu); };
    scroller.addEventListener('mousedown', md);
    return () => {
      scroller.removeEventListener('touchstart', ts); scroller.removeEventListener('touchmove', tm);
      scroller.removeEventListener('touchend', te); scroller.removeEventListener('touchcancel', te);
      scroller.removeEventListener('mousedown', md);
      window.removeEventListener('mousemove', mm); window.removeEventListener('mouseup', mu);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const orgAvatarUrl = orgStats ? organizerAvatarPublicUrl(orgStats.avatarPath, orgStats.avatarR2Ref, 'thumb') : '';
  const orgInitial = (ev.orgName || '').trim().slice(0, 1).toUpperCase();
  // Round icon buttons, top-right, side by side (Share, then Save) — same glass disc as the back pill.
  const iconBtn = (extra) => photoPill({ position: 'fixed', top: OVERLAY_TOP, width: 40, height: 40, padding: 0, zIndex: 5, borderRadius: 20, display: 'flex', alignItems: 'center', justifyContent: 'center', ...extra });
  // "More" menu (⋯): the secondary text links that used to stack above the title now live here.
  const [menuOpen, setMenuOpen] = useState(false);
  const menuItem = { display: 'flex', alignItems: 'center', gap: 10, padding: '11px 14px', fontSize: 13, color: ink, cursor: 'pointer', whiteSpace: 'nowrap' };
  const hasMenu = !cameFromHome || showOpenInMap || s.myOrgEventKeys.includes(ev.key);

  return (
    // `absolute, inset 0` (like Chat): fills the app's scroll viewport exactly, whatever the surrounding grid does
    // with percentage heights, so the sheet below scrolls INSIDE this screen instead of the page growing.
    <div style={{ position: 'absolute', inset: 0 }} data-screen-label="Event">
      <div ref={dimRef} aria-hidden style={{ position: 'fixed', inset: 0, background: 'rgb(12,12,12)', opacity: 0, pointerEvents: 'none', zIndex: 0 }} />
    <div ref={cardRef} style={{ animation: zoomRef.current ? undefined : 'banbeEventIn 0.55s cubic-bezier(.34,1.2,.5,1) backwards', height: '100%', display: 'flex', flexDirection: 'column', position: 'relative', zIndex: 1 }}>
      <div data-fade aria-hidden style={{ position: 'absolute', inset: 0, background: paper, zIndex: -1 }} />
      {/* Task 3 (14-photo-viewer.md follow-up notes / 06-design-tokens.md):
          moved out of the photo header (which scrolls away with the rest
          of the content, inside this screen's OWN scroll container below —
          not the shared Shell-level one) into a fixed overlay, so both
          stay visible/tappable the whole time the user scrolls. */}
      {/* Top scrim: keeps the round controls legible on bright photos (they used to rely on one dark sample image). */}
      <div data-fade aria-hidden style={{ position: 'fixed', top: 0, left: 0, right: 0, height: 140, zIndex: 4, pointerEvents: 'none', background: 'linear-gradient(180deg, rgba(12,12,12,0.34) 0%, rgba(12,12,12,0) 100%)' }} />
      {/* Icon-only 40pt disc like Share/Save; the destination name stays as visually-hidden text (screen readers, tests). */}
      <div data-fade onClick={closeWithShrink} role="button" aria-label={backLabel} data-testid="event-detail-back" style={iconBtn({ left: 16 })}>
        <svg {...ico} width={20} height={20}><path d="M14.5 5.5 8 12l6.5 6.5" /></svg>
        <span style={SR_ONLY}>{backLabel}</span>
      </div>
      <div data-fade onClick={() => shareEvent(ev)} role="button" aria-label={T('Chia sẻ', 'Share')} data-testid="event-detail-share" style={iconBtn({ right: 64 })}><IconShare /></div>
      {/* Blocker fix (retention roadmap follow-up) — EventDetail had no save
          affordance at all before this pass. Uses Stage 1's exact same
          isSaved/toggleFav — already catalogue-agnostic (both key off the
          real `favorites` table by event id), so this works identically for
          a static demo event and a real host-created one. */}
      <div data-fade onClick={() => toggleFav(ev.key)} role="button" aria-label={isSaved(ev.key) ? T('Đã lưu', 'Saved') : T('Lưu', 'Save')} data-testid="event-detail-save" style={iconBtn({ right: 16 })}><IconHeart filled={isSaved(ev.key)} /></div>
      {hasMenu && (
        <>
          <div data-fade onClick={() => setMenuOpen(o => !o)} role="button" aria-label={T('Thêm', 'More')} aria-expanded={menuOpen} data-testid="event-detail-more" style={iconBtn({ right: 112 })}><IconMore /></div>
          {menuOpen && (
            <>
              <div onClick={() => setMenuOpen(false)} aria-hidden style={{ position: 'fixed', inset: 0, zIndex: 5 }} />
              <div role="menu" style={photoPill({ position: 'fixed', top: `calc(${OVERLAY_TOP} + 48px)`, right: 16, zIndex: 6, borderRadius: 14, padding: '4px 0', background: 'rgba(var(--bb-bg-rgb),0.96)', fontSize: 13 })}>
                {!cameFromHome && (
                  <div role="menuitem" onClick={() => { setMenuOpen(false); goHome(); }} style={menuItem}><IconHouse />{T('Về trang chính', 'Back to home')}</div>
                )}
                {showOpenInMap && (
                  <div role="menuitem" data-testid="event-open-in-map" onClick={() => { setMenuOpen(false); openEventOnMap(ev); }} style={menuItem}><IconMap />{T('Xem trên bản đồ', 'Open in map')}</div>
                )}
                {s.myOrgEventKeys.includes(ev.key) && (
                  <div role="menuitem" data-testid="event-share-to-story" onClick={s.storyCreateBusy ? undefined : () => { setMenuOpen(false); setShareConfirmOpen(true); }} style={{ ...menuItem, opacity: s.storyCreateBusy ? 0.5 : 1 }}><IconCamera />{s.storyCreateBusy ? T('Đang đăng…', 'Posting…') : T('Chia sẻ lên Story', 'Share to Story')}</div>
                )}
              </div>
            </>
          )}
        </>
      )}
      {s.shared && (
        <div style={{ position: 'fixed', top: `calc(${OVERLAY_TOP} + 48px)`, right: 16, zIndex: 5, fontSize: 11.5, color: ink, background: 'rgba(var(--bb-bg-rgb),0.9)', borderRadius: 999, padding: '5px 10px' }}>{T('Đã sao chép link', 'Link copied')}</div>
      )}
      {/* The photo is pinned behind everything; the scrolling sheet starts PINNED_STRIP down the screen (rounded top),
          so a band of the photo stays visible above the info however far it is pulled up. */}
      <div ref={heroRef} style={{ position: 'absolute', top: 0, left: 0, right: 0, height: HERO_H, zIndex: 0, pointerEvents: 'none' }}>
        {ev.img ? (
          <div ref={heroImgRef} style={bg(ev.img, { width: '100%', height: '100%', borderRadius: 0 })} />
        ) : (
          // A real event with no photo yet (or one still loading/
          // unavailable) — an honest neutral block, never a wrong demo
          // event's photo standing in for it.
          <div style={{ width: '100%', height: '100%', background: rule }} />
        )}
      </div>
      <div ref={scrollerRef} data-fade onScroll={onSheetScroll} style={{ position: 'relative', zIndex: 1, flex: 1, minHeight: 0, marginTop: PINNED_STRIP, borderRadius: `${SHEET_RADIUS}px ${SHEET_RADIUS}px 0 0`, overflowY: 'auto', WebkitOverflowScrolling: 'touch', overscrollBehaviorY: 'contain' }}>
      <div style={{ height: HERO_H - SHEET_OVERLAP - PINNED_STRIP }} aria-hidden />
      <div style={{ position: 'relative', zIndex: 1, background: paper, borderRadius: `${SHEET_RADIUS}px ${SHEET_RADIUS}px 0 0`, boxShadow: '0 -4px 14px rgba(0,0,0,0.10)', padding: '30px 22px 30px', display: 'flex', flexDirection: 'column' }}>
        {shareStoryMsg && (
          <div style={{ fontSize: 11, color: ink, opacity: 0.7, marginBottom: 10 }}>{shareStoryMsg}</div>
        )}
        {/* BUG 4 fix — a real confirm step, same bottom-sheet visual
            convention ReasonSheet.jsx already established (dim overlay +
            a paper panel sliding up). Cancel writes nothing at all. */}
        {shareConfirmOpen && (
          <div onClick={s.storyCreateBusy ? undefined : () => setShareConfirmOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 40, background: 'rgba(12,12,12,0.55)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', animation: 'banbeFade 0.2s ease both' }}>
            <div onClick={(e) => e.stopPropagation()} style={{ background: paper, padding: '20px 20px 30px', animation: 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
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
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <span style={sectionLabel}>{evCat}</span>
          {ev.inviteOnly && (
            <span data-testid="event-invite-chip" style={{ fontSize: 11, fontWeight: 600, letterSpacing: '0.02em', color: paper, background: ink, padding: '3px 10px', borderRadius: RADIUS.pill }}>{T('Riêng tư ▪︎ theo lời mời', 'Private ▪︎ invite only')}</span>
          )}
        </div>
        {/* Title + compact plan pill on one row (iOS EventPlanTitleRow). */}
        <EventPlanTitle eventKey={ev.key} title={ev.name} titleStyle={display(28, { lineHeight: 1.2 })} />
        {/* Key facts (date/time first: the one fact an event page must never leave out), one icon column, one grid. */}
        <div data-testid="event-facts" style={{ marginTop: 12, display: 'flex', flexDirection: 'column' }}>
          {ev.when && <FactRow icon={<IconClock />} testId="event-fact-when">{ev.when}</FactRow>}
          <FactRow icon={<IconPin />} testId="event-fact-where">
            {evMapsUrl ? (
              <a
                href={evMapsUrl}
                target="_blank"
                rel="noopener noreferrer"
                // Opening directions is the natural moment to also offer to show the distance, if that hasn't been
                // decided yet — never blocks the click itself (the maps link still opens via the normal href).
                onClick={() => { if (s.located === null) askLocation(); }}
                style={{ color: ink, textDecoration: 'underline', textDecorationColor: 'rgba(var(--bb-fg-rgb),0.35)', textUnderlineOffset: 2 }}
              >
                {evWhere} ↗
              </a>
            ) : evWhere}
          </FactRow>
          <FactRow icon={<IconSeat />} testId="event-fact-seats">{evSeatsLong}</FactRow>
          {ev.price && <FactRow icon={<IconTag />} testId="event-fact-price"><span style={{ ...display(17) }}>{trStatus(ev.price)}</span></FactRow>}
        </div>
        <WhoCanReserve criteria={crit.criteria} style={{ marginTop: 6 }} />
        {crit.restricted && crit.blocked && !myBooking && !ev.cancelled && !ended && (
          <div ref={critRef} style={{ marginTop: 12, scrollMarginBottom: 160 }}><CriteriaUnmetCard eligibility={crit.eligibility} returnTo="event" /></div>
        )}
        {/* Body copy supports the title instead of competing with it: roomier leading, slightly softer ink. Long
            descriptions clamp to 4 lines when there is a fuller write-up behind "Read more" (About & Included sheet). */}
        <p style={{ fontSize: 14.5, lineHeight: 1.6, color: ink, opacity: 0.85, margin: '18px 0 0', ...(canClamp ? { display: '-webkit-box', WebkitLineClamp: 4, WebkitBoxOrient: 'vertical', overflow: 'hidden' } : null) }}>{ev.desc}</p>
        {canClamp && (
          <div onClick={() => setIncludedSheetOpen(true)} data-testid="event-read-more" style={{ marginTop: 6, fontSize: 13, fontWeight: 600, color: ink, cursor: 'pointer' }}>{T('Xem thêm', 'Read more')}</div>
        )}
        {/* Host card: who runs this, how trusted, and a one-tap way to ask (moved up from the bottom rows). */}
        <div style={{ marginTop: 22, display: 'flex', alignItems: 'center', gap: 12, padding: '14px 0', borderTop: `1px solid ${softRule}`, borderBottom: `1px solid ${softRule}` }}>
          <div onClick={() => openOrganizerOfEvent(ev.key, 'event')} data-testid="event-organizer-row" role="button" aria-label={T('Trang tổ chức của ', 'Host page of ') + (ev.orgName || '')} style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer' }}>
            <span style={{ flex: 'none', width: 40, height: 40, borderRadius: '50%', overflow: 'hidden', background: 'var(--bb-field)', border: `0.5px solid ${rule}`, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, fontWeight: 600, color: ink }}>
              {orgAvatarUrl ? <img src={orgAvatarUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : orgInitial}
            </span>
            <span style={{ minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
              <span style={{ fontSize: 12, color: ink, opacity: 0.65 }}>{T('Tổ chức bởi', 'Hosted by')}</span>
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
                <span style={{ fontSize: 15, fontWeight: 600, color: ink, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{ev.orgName}</span>
                {evOrgFollowed && <FollowingBadge T={T} testId="event-organizer-following" />}
              </span>
              {evOrgStats && <span data-testid="event-organizer-stats" style={{ fontSize: 12, color: ink, opacity: 0.65 }}>{evOrgStats}</span>}
            </span>
          </div>
          {/* Moved here from the retired Organizer screen (merged into the host profile): message the host from the event. */}
          <div onClick={goChat} data-testid="organizer-message" role="button" aria-label={T('Nhắn cho ', 'Message ') + (ev.orgName || '')} style={{ flex: 'none', display: 'inline-flex', alignItems: 'center', gap: 6, padding: '8px 12px', borderRadius: RADIUS.pill, border: `1px solid ${rule}`, fontSize: 13, fontWeight: 600, color: ink, cursor: 'pointer' }}>
            <IconChat />{T('Nhắn tin', 'Message')}
          </div>
        </div>
        {/* Photos sit right under the story they illustrate, with a count, instead of after everything else. */}
        <div style={{ marginTop: 24 }}>
          <div style={sectionLabel}>{T('Hình ảnh', 'Photos')}{realPhotos.length > 0 ? ` ▪︎ ${realPhotos.length}` : ''}</div>
          {/* STAGE D (2026-09-25) — real event_photos rows, not the static demo `ev.gallery`. A genuinely photo-less
              real event shows plain text, never a fake/demo photo standing in for a real one. */}
          {s.eventPhotosLoading ? (
            <p style={{ fontSize: 13, color: ink, opacity: 0.6, margin: '10px 0 0' }}>{T('Đang tải…', 'Loading…')}</p>
          ) : realPhotos.length ? (
            <div style={{ display: 'flex', gap: 8, overflowX: 'auto', marginTop: 10, paddingBottom: 4 }}>
              {realPhotos.map((p, i) => (
                <div key={p.id} onClick={(e) => openPhoto(realPhotos, i, ev.orgName, e.currentTarget.getBoundingClientRect())} style={{ position: 'relative', flex: 'none' }}>
                  <div style={bg(p.url, { width: 132, height: 166, borderRadius: RADIUS.thumb, cursor: 'pointer' })} />
                  {/* A.7 — a liked photo gets a filled heart badge; an unliked one shows none here (the full-screen
                      viewer's own like button is the discoverable way to like it). */}
                  {s.photoEngagement[p.id]?.likedByMe && (
                    <span style={{ position: 'absolute', top: 8, right: 8, color: '#fff', filter: 'drop-shadow(0 1px 2px rgba(0,0,0,0.55))', pointerEvents: 'none' }}>
                      <svg width={15} height={15} viewBox="0 0 24 24" fill="currentColor"><path d="M12 20.5S3.5 15 3.5 9.2A4.7 4.7 0 0 1 12 6.5a4.7 4.7 0 0 1 8.5 2.7c0 5.8-8.5 11.3-8.5 11.3Z" /></svg>
                    </span>
                  )}
                </div>
              ))}
            </div>
          ) : (
            <p style={{ fontSize: 13, color: ink, opacity: 0.6, margin: '10px 0 0' }}>{T('Chưa có ảnh nào cho sự kiện này.', 'No photos for this event yet.')}</p>
          )}
        </div>
        {/* One tappable "About & Included" row + sheet (intro first, included items below) whenever EITHER exists,
            matching iOS. `ev.included` (legacy flat string) is the fallback for an event with neither. Only tappable
            rows get a chevron. */}
        {(includedItems.length > 0 || introParagraphs.length > 0) ? (
          <div
            onClick={() => setIncludedSheetOpen(true)}
            data-testid="event-included-section"
            aria-label={T('Giới thiệu và bao gồm, xem thêm', 'Introduction and included, view more')}
            style={{ ...listRow, marginTop: 20, borderTop: `1px solid ${softRule}`, cursor: 'pointer' }}
          >
            <span style={iconCol}><IconList /></span>
            <span style={{ flex: 1, minWidth: 0 }}>
              <span style={{ display: 'block', fontWeight: 600 }}>{T('Giới thiệu & bao gồm', 'About & included')}</span>
              {includedItems.length > 0 && (
                <span style={{ display: 'block', fontSize: 13, opacity: 0.7, marginTop: 2 }}>{includedItems.map(it => it.label).join(' ▪︎ ')}</span>
              )}
            </span>
            <span aria-hidden style={{ flex: 'none', opacity: 0.5, fontSize: 18, lineHeight: 1 }}>›</span>
          </div>
        ) : ev.included ? (
          <div style={{ ...listRow, marginTop: 20, borderTop: `1px solid ${softRule}` }}>
            <span style={iconCol}><IconList /></span>
            <span style={{ flex: 1, minWidth: 0 }}>
              <span style={{ display: 'block', fontWeight: 600 }}>{T('Bao gồm', 'Included')}</span>
              <span style={{ display: 'block', fontSize: 13, opacity: 0.7, marginTop: 2 }}>{ev.included}</span>
            </span>
          </div>
        ) : null}
      </div>
      </div>
      {/* Sticky action area: always on screen, so the decision can happen wherever the reader is convinced. Seat
          presets + the live total live next to the CTA instead of a separate step (Reserve opens pre-filled). */}
      <div data-fade data-testid="event-action-area" style={barGlass({ flex: 'none', position: 'relative', zIndex: 2, borderTop: `1px solid ${softRule}`, padding: '10px 16px calc(12px + env(safe-area-inset-bottom, 0px))' })}>
        {barState === 'reserve' && (
          <div data-testid="event-qty" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, marginBottom: 8 }}>
            <span style={{ fontSize: 13, color: ink, opacity: 0.75 }}>{T('Số chỗ', 'Seats')}</span>
            {qtyMore ? (
              <CountStepper value={qty} min={1} max={MAX_QTY} unit={T('chỗ', 'seats')} testId="event-qty-stepper" onChange={setQty} />
            ) : (
              <div role="radiogroup" aria-label={T('Số chỗ', 'Seats')} style={{ display: 'flex', gap: 6 }}>
                {QTY_PRESETS.map(n => qtyChip(n))}
                <div role="button" onClick={() => setQtyMore(true)} data-testid="event-qty-more" aria-label={T('Số khác', 'Other amount')}
                  style={{ minWidth: 40, height: 32, padding: '0 10px', borderRadius: RADIUS.pill, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 14, cursor: 'pointer', border: `1px solid ${rule}`, color: ink }}>
                  {T('Khác', 'More')}
                </div>
              </div>
            )}
          </div>
        )}
        <div onClick={reserveBarTap} role="button" style={reserveBarStyle} data-testid="event-reserve-bar" data-state={barState} aria-disabled={!reserveBarTap || undefined}>{reserveBarLabel}</div>
        {trustLine && <div data-testid="event-trust-line" style={{ marginTop: 6, fontSize: 12, lineHeight: 1.4, color: ink, opacity: 0.7, textAlign: 'center' }}>{trustLine}</div>}
      </div>
      {includedSheetOpen && (
        <div
          onClick={() => setIncludedSheetOpen(false)}
          data-testid="event-included-sheet"
          style={{ position: 'fixed', inset: 0, background: 'rgba(27,25,22,0.5)', display: 'flex', alignItems: 'flex-end', zIndex: 70, animation: 'banbeFade 0.22s ease both' }}
        >
          <div
            onClick={(e) => e.stopPropagation()}
            role="dialog" aria-modal="true" aria-label={T('Giới thiệu & Bao gồm', 'About & Included')}
            style={{ background: paper, width: '100%', maxHeight: '94%', overflowY: 'auto', borderRadius: '18px 18px 0 0', padding: '10px 20px 28px', boxSizing: 'border-box', display: 'flex', flexDirection: 'column', gap: 20, animation: 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}
          >
            <div style={{ width: 36, height: 4, background: rule, borderRadius: 2, margin: '6px auto 0', flex: 'none' }} />
            {/* Same header as the Share card sheet: centred title, but an X on the right instead of a Close pill. */}
            <div style={{ position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: 36, flex: 'none' }}>
              <span style={{ ...display(17) }}>{T('Giới thiệu & Bao gồm', 'About & Included')}</span>
              <span
                onClick={() => setIncludedSheetOpen(false)}
                role="button"
                aria-label={T('Đóng', 'Close')}
                data-testid="event-included-sheet-close"
                style={{ position: 'absolute', right: 0, top: '50%', transform: 'translateY(-50%)', width: 36, height: 36, borderRadius: '50%', background: 'rgba(120,120,128,0.16)', backdropFilter: 'blur(14px) saturate(1.6)', WebkitBackdropFilter: 'blur(14px) saturate(1.6)', boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,0.35), 0 1px 4px rgba(0,0,0,0.12)', color: ink, fontSize: 15, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}
              >
                ✕
              </span>
            </div>
            {/* Intro/included-presentation pass (2026-09-28) — intro FIRST,
                Included items separately below, matching iOS's own sheet
                exactly. The old truncate-at-90px/"Đọc thêm" toggle is gone
                — this sheet is already its own scrollable surface, so the
                full text just shows directly, no expand affordance needed. */}
            {introParagraphs.length > 0 && (
              <div data-testid="event-intro-section" style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Giới thiệu sự kiện', 'About this event')}</span>
                {introParagraphs.map((p, i) => (
                  <p key={i} style={{ fontSize: 13.5, lineHeight: 1.6, color: ink, margin: 0, whiteSpace: 'pre-wrap' }}>{p}</p>
                ))}
              </div>
            )}
            {includedItems.length > 0 && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
                <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Bao gồm', 'Included')}</span>
                {includedItems.map((it, i) => (
                  <div key={i} style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                    <span style={{ ...display(15) }}>{it.label}</span>
                    {it.detail && <span style={{ fontSize: 13, lineHeight: 1.55, color: ink }}>{it.detail}</span>}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
    </div>
  );
}

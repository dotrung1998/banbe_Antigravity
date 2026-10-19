import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { recentZoomOrigin } from '../lib/zoomOrigin.js';
import { useBanBe } from '../state/BanBeContext.jsx';
import { bg, mapsUrl } from '../data/events.js';
import { paper, ink, rule, display, inkButton, clay, clayBg, RADIUS } from '../theme.js';
import { isBookingTicket } from '../lib/bookingTicket.js';
import { useReservationCriteria, WhoCanReserve, CriteriaUnmetCard } from './ReservationCriteria.jsx';
import FollowingBadge from '../components/FollowingBadge.jsx';
import EventPlanTitle from './EventPlanActions.jsx';
import { organizerAvatarPublicUrl } from '../lib/mediaUrls.js';
import { reserveBarState, totalPrice, clampQty, parsePrice, QTY_PRESETS, MAX_QTY } from '../lib/reserveBar.js';
import GlassMenu, { GlassMenuItem, GlassMenuDivider } from '../components/GlassMenu.jsx';

// Airbnb-style layout (mirrors iOS EventDetailView): the photo is a pinned backdrop that fades out while the
// rounded info sheet scrolls up over it; pulling down from the very top closes the screen with a shrink.
const HERO_H = 400;
const SHEET_OVERLAP = 40;
const SHEET_RADIUS = 46; // the iPhone's own screen-corner curvature
const PINNED_STRIP = 120; // with the info fully pulled up, this much of the photo stays visible above it

const ico = { width: 16, height: 16, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 1.6, strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': true };
const IconShare = () => (<svg {...ico} width={18} height={18} strokeWidth={1.8}><path d="M12 15V3M8 7l4-4 4 4" /><path d="M5 11v8a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-8" /></svg>);
const IconHeart = ({ filled }) => (<svg {...ico} width={18} height={18} strokeWidth={1.8} fill={filled ? 'currentColor' : 'none'}><path d="M12 20.5S3.5 15 3.5 9.2A4.7 4.7 0 0 1 12 6.5a4.7 4.7 0 0 1 8.5 2.7c0 5.8-8.5 11.3-8.5 11.3Z" /></svg>);
const IconMore = () => (<svg {...ico} width={18} height={18}><circle cx="5.5" cy="12" r="1.3" fill="currentColor" /><circle cx="12" cy="12" r="1.3" fill="currentColor" /><circle cx="18.5" cy="12" r="1.3" fill="currentColor" /></svg>);
const IconBack = () => (<svg {...ico} width={18} height={18} strokeWidth={2}><path d="M14.5 5.5 8 12l6.5 6.5" /></svg>);
const IconHouse = () => (<svg {...ico} width={18} height={18}><path d="M4 11l8-7 8 7" /><path d="M6 10v10h12V10" /></svg>);
const IconMap = () => (<svg {...ico} width={18} height={18}><path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2z" /><path d="M9 4v14M15 6v14" /></svg>);
const IconCamera = () => (<svg {...ico} width={18} height={18}><path d="M4 8h3l2-3h6l2 3h3v11H4z" /><circle cx="12" cy="13" r="3.4" /></svg>);
const IconLink = () => (<svg {...ico} width={18} height={18}><path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1" /><path d="M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1" /></svg>);
const IconChat = () => (<svg {...ico}><path d="M5 5h14a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1h-8l-5 4v-4H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z" /></svg>);
const IconCalendar = () => (<svg {...ico} width={18} height={18}><rect x="3.5" y="5" width="17" height="15.5" rx="2.3" /><path d="M3.5 9.7h17M8 3v4M16 3v4" /></svg>);
const IconClock = () => (<svg {...ico} width={18} height={18}><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 2" /></svg>);
const IconPin = () => (<svg {...ico} width={18} height={18}><path d="M12 21s6.5-5.6 6.5-11a6.5 6.5 0 0 0-13 0C5.5 15.4 12 21 12 21Z" /><circle cx="12" cy="10" r="2.3" /></svg>);
const IconHost = () => (<svg {...ico} width={15} height={15}><circle cx="12" cy="8" r="3.6" /><path d="M5 20c1.3-3.6 3.9-5.3 7-5.3s5.7 1.7 7 5.3" /></svg>);
const IconShield = () => (<svg {...ico} width={15} height={15}><path d="M12 3l7 3v5.5c0 4.3-3 7.8-7 9.5-4-1.7-7-5.2-7-9.5V6z" /><path d="M9 12l2 2 4-4" /></svg>);
// One hairline weight for the page's own dividers: softer than `rule`, so sections read as one surface, not blocks.
const softRule = 'rgba(var(--bb-fg-rgb),0.10)';
const sectionHeading = display(20, { lineHeight: 1.25 });
// Top of the floating round controls: the old fixed 66px, but never closer to the notch than inset + 16.
const OVERLAY_TOP = 'max(66px, calc(env(safe-area-inset-top, 0px) + 16px))';
// Scrolled this far, the title has gone under the top edge: the solid nav bar (mockup "02 · Khi cuộn xuống") fades in.
const COLLAPSE_AT = HERO_H - SHEET_OVERLAP - PINNED_STRIP + 70;
// Glass over the photo, tinted with the clay accent (white glyph): legible on bright and dark covers alike.
const clayGlass = {
  background: 'linear-gradient(165deg, rgba(255,255,255,0.22) 0%, rgba(255,255,255,0.04) 45%, rgba(255,255,255,0) 70%), rgba(var(--bb-clay-rgb),0.72)',
  backdropFilter: 'blur(16px) saturate(1.5)', WebkitBackdropFilter: 'blur(16px) saturate(1.5)',
  border: '1px solid rgba(255,255,255,0.32)', boxShadow: '0 6px 16px rgba(0,0,0,0.22)', color: '#fff',
};
// The same controls once the nav bar is solid: no fill, clay glyphs.
const navPlain = { background: 'transparent', backdropFilter: 'none', WebkitBackdropFilter: 'none', border: '1px solid transparent', boxShadow: 'none', color: clay };
// Ngày / Giờ / Địa điểm tile (mockup): soft fill, clay icon, small label over the value. All three share one width.
// `action` is an optional icon-only link in the tile's top-right corner (no text, to save space).
const Tile = ({ icon, label, action, testId, children }) => (
  <div data-testid={testId} style={{ position: 'relative', flex: '1 1 0', minWidth: 0, padding: '12px 12px 11px', borderRadius: RADIUS.tile, background: 'rgba(var(--bb-fg-rgb),0.045)', border: `1px solid ${softRule}`, color: ink }}>
    <span style={{ color: clay, display: 'inline-flex' }}>{icon}</span>
    {action}
    <div style={{ fontSize: 12.5, opacity: 0.62, marginTop: 8 }}>{label}</div>
    <div style={{ fontSize: 14.5, lineHeight: 1.35, marginTop: 2, overflowWrap: 'anywhere' }}>{children}</div>
  </div>
);
const IconDirections = () => (<svg {...ico} width={15} height={15} strokeWidth={2}><path d="M7 17 17 7M9 7h8v8" /></svg>);
const pillBtn = { display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 6, borderRadius: RADIUS.pill, cursor: 'pointer', fontFamily: 'inherit', whiteSpace: 'nowrap' };

// The event this screen last showed and how far it was scrolled, so coming BACK to it (host page, chat, Reserve…) lands
// exactly where it was, with no re-entrance animation. Cleared when the event is closed (Back / pull-down).
let lastVisit = null;

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
  // A return (not a fresh open from a card): the saved scroll offset; null for a fresh open.
  const returnRef = useRef(undefined);
  if (returnRef.current === undefined) returnRef.current = !zoomRef.current && lastVisit?.key === ev.key ? lastVisit.scrollTop : null;
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
  useEffect(() => { if (returnRef.current == null) buzz(); }, []);
  // Coming back: put the scroll position straight back (and the title/nav-bar state with it) before the first paint.
  useLayoutEffect(() => {
    const sc = scrollerRef.current;
    if (returnRef.current == null) { lastVisit = { key: ev.key, scrollTop: 0 }; return; }
    if (sc) { sc.scrollTop = returnRef.current; onSheetScroll({ currentTarget: sc }); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  // Close with the same shrink-and-fade the pull-down finishes with, then navigate back.
  const closeWithShrink = () => {
    lastVisit = null;
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
  const isFree = parsePrice(ev.price).free;
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
  // One honest line above the CTA: the refund promise for open paid events, else what holding means.
  const trustLine = barState !== 'reserve' ? null
    : showRefund
      ? T('Hoàn tiền tự động 100% nếu sự kiện bị hủy', 'Automatic full refund if the event is cancelled')
      : T('Chỗ được giữ 30 phút để bạn xác nhận', 'Seats are held for 30 minutes while you confirm');

  // Ngày / Giờ tiles: `when` is "Th 4, 04.11 ▪︎ 20:00" for both catalogue and real events.
  const [whenDate, whenTime] = (ev.when || '').split(' ▪︎ ');
  // Seats bar: only when capacity AND what is left are both known (live fill from migration 186 first, else the
  // row's own seats_remaining). Never an invented capacity — the plain "N left" text stays otherwise.
  const realRow = s.realEventsById[ev.key];
  const fill = s.eventFill?.[ev.key];
  const capacity = fill?.capacity ?? realRow?.capacity ?? null;
  const remaining = fill ? Math.max(0, fill.capacity - fill.booked) : (realRow?.seatsRemaining ?? null);
  const fillRatio = capacity > 0 && remaining != null ? Math.min(1, Math.max(0, (capacity - remaining) / capacity)) : null;
  const seatsText = ev.soldOut ? trStatus('Hết chỗ') : remaining != null ? T(`Còn ${remaining} chỗ`, `${remaining} seats left`) : evSeatsLong;
  // Track-record line under the description (mockup's rating row, real data only — banbe has no ratings).
  const trackParts = [ev.orgName, orgStats?.count > 0 ? T(`${orgStats.count} sự kiện`, `${orgStats.count} events`) : null,
    orgStats?.sinceYear ? T(`từ ${orgStats.sinceYear}`, `since ${orgStats.sinceYear}`) : null].filter(Boolean);
  // Host card subline (real stats only).
  const hostSubline = [orgStats?.sinceYear ? T(`Tham gia từ ${orgStats.sinceYear}`, `Joined ${orgStats.sinceYear}`) : null,
    orgStats?.count > 0 ? T(`Đã tổ chức ${orgStats.count} sự kiện`, `Hosted ${orgStats.count} events`) : null].filter(Boolean).join(' · ');
  const includedChips = includedItems.length > 0
    ? includedItems.map(it => it.label)
    : (ev.included || '').split(/\s*(?:▪︎|,|·)\s*/).map(x => x.trim()).filter(Boolean);
  const hasAboutSheet = includedItems.length > 0 || introParagraphs.length > 0;

  // Collapsing nav bar: flips once when the title passes under the top edge (state only changes at the threshold).
  const [collapsed, setCollapsed] = useState(false);
  const collapsedRef = useRef(false);
  const titleWrapRef = useRef(null);
  const navBgRef = useRef(null);
  const navTitleRef = useRef(null);
  const [linkCopied, setLinkCopied] = useState(false);
  const copyLink = () => {
    const url = `https://www.banbe.app/api/photo-share?eid=${encodeURIComponent(ev.key)}`;
    const done = () => { setLinkCopied(true); setTimeout(() => setLinkCopied(false), 1800); };
    try { navigator.clipboard?.writeText(url).then(done, done); } catch { done(); }
  };

  // The photo backdrop fades to the page colour and drifts up slowly as the sheet rises over it.
  // 0 while the title is comfortably below the bar, 1 once it has fully passed under it.
  const titleProgress = (t) => {
    const w = titleWrapRef.current;
    if (!w) return t > COLLAPSE_AT ? 1 : 0;
    const top = (HERO_H - SHEET_OVERLAP - PINNED_STRIP) + w.offsetTop; // title top inside the scroller's content
    const lead = 36; // starts this far before the title reaches the bar
    return Math.min(1, Math.max(0, (t - (top - lead)) / (w.offsetHeight + lead)));
  };
  const onSheetScroll = (e) => {
    const t = Math.max(0, e.currentTarget.scrollTop);
    lastVisit = { key: ev.key, scrollTop: t };
    // Fades only part-way while the strip is visible; gone once the solid nav bar covers it (so the photo never peeks
    // through the sheet's rounded top corners under the bar).
    const p = titleProgress(t);
    if (heroRef.current) heroRef.current.style.opacity = p >= 1 ? '0' : String(1 - 0.4 * Math.min(1, t / (HERO_H * 0.62)));
    if (heroImgRef.current) heroImgRef.current.style.transform = `translateY(${-Math.min(t, HERO_H) * 0.3}px)`;
    // The event name moves up and shrinks into the bar instead of being covered and swapped: as the in-sheet title
    // reaches the top it rises, shrinks and fades while the bar's own title grows into place from just below it, both
    // driven by the same scroll progress (inline styles only, no re-render per frame).
    if (titleWrapRef.current) {
      titleWrapRef.current.style.opacity = String(1 - p);
      titleWrapRef.current.style.transform = `translateY(${-p * 12}px) scale(${1 - 0.3 * p})`;
    }
    if (navBgRef.current) navBgRef.current.style.opacity = String(p);
    if (navTitleRef.current) {
      navTitleRef.current.style.opacity = String(p);
      navTitleRef.current.style.transform = `translateY(${(1 - p) * 30}px) scale(${1 + 0.6 * (1 - p)})`;
    }
    const c = p > 0.6;
    if (c !== collapsedRef.current) { collapsedRef.current = c; setCollapsed(c); }
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
  const [menuOpen, setMenuOpen] = useState(false);
  // Round controls over the photo; once the nav bar is solid they lose their glass and become plain clay glyphs.
  const ctl = (extra) => ({ height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', transition: 'background .2s ease, color .2s ease, box-shadow .2s ease, border-color .2s ease', ...(collapsed ? navPlain : clayGlass), ...extra });
  const disc = (extra) => ctl({ width: 40, borderRadius: 20, ...extra });

  return (
    // `absolute, inset 0` (like Chat): fills the app's scroll viewport exactly, whatever the surrounding grid does
    // with percentage heights, so the sheet below scrolls INSIDE this screen instead of the page growing.
    <div style={{ position: 'absolute', inset: 0 }} data-screen-label="Event">
      <div ref={dimRef} aria-hidden style={{ position: 'fixed', inset: 0, background: 'rgb(12,12,12)', opacity: 0, pointerEvents: 'none', zIndex: 0 }} />
    <div ref={cardRef} style={{ animation: (zoomRef.current || returnRef.current != null) ? undefined : 'banbeEventIn 0.55s cubic-bezier(.34,1.2,.5,1) backwards', height: '100%', display: 'flex', flexDirection: 'column', position: 'relative', zIndex: 1 }}>
      <div data-fade aria-hidden style={{ position: 'absolute', inset: 0, background: paper, zIndex: -1 }} />
      {/* Task 3 (14-photo-viewer.md follow-up notes / 06-design-tokens.md):
          moved out of the photo header (which scrolls away with the rest
          of the content, inside this screen's OWN scroll container below —
          not the shared Shell-level one) into a fixed overlay, so both
          stay visible/tappable the whole time the user scrolls. */}
      {/* Top scrim: keeps the round controls legible on bright photos (they used to rely on one dark sample image). */}
      <div data-fade aria-hidden style={{ position: 'fixed', top: 0, left: 0, right: 0, height: 140, zIndex: 4, pointerEvents: 'none', background: 'linear-gradient(180deg, rgba(12,12,12,0.34) 0%, rgba(12,12,12,0) 100%)', opacity: collapsed ? 0 : 1, transition: 'opacity .2s ease' }} />
      {/* Collapsing nav bar (mockup "02 · Khi cuộn xuống"): once the title has scrolled away, a solid paper bar covers
          the pinned photo strip and repeats the event name, so the reader never loses context. */}
      <div aria-hidden={!collapsed} data-testid="event-nav-bar" style={{ position: 'fixed', top: 0, left: 0, right: 0, height: PINNED_STRIP, zIndex: 4, pointerEvents: 'none' }}>
        <div ref={navBgRef} style={{ position: 'absolute', inset: 0, background: paper, borderBottom: `1px solid ${softRule}`, opacity: 0 }} />
        <div style={{ position: 'absolute', top: OVERLAY_TOP, left: 64, right: 164, height: 40, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <span ref={navTitleRef} style={{ ...display(16), overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', opacity: 0, transformOrigin: 'center bottom', willChange: 'transform, opacity' }}>{ev.name}</span>
        </div>
      </div>
      {/* Back pill "‹ {where you came from}" (mockup); collapses to just the chevron in the nav bar to give the title room. */}
      <div data-fade onClick={closeWithShrink} role="button" aria-label={backLabel} data-testid="event-detail-back"
        style={ctl({ position: 'fixed', top: OVERLAY_TOP, left: 16, zIndex: 5, gap: 2, padding: collapsed ? '0 8px' : '0 14px 0 9px', borderRadius: RADIUS.pill, fontSize: 14, fontWeight: 600, maxWidth: 170 })}>
        <IconBack />
        <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: collapsed ? 0 : 130, transition: 'max-width .2s ease' }}>{backLabel}</span>
      </div>
      {/* ⋯ opens the same frosted pop-up as the calendar pill beside the title (GlassMenu), anchored under the disc. */}
      <GlassMenu open={menuOpen} onOpenChange={setMenuOpen} top={48} label={T('Tuỳ chọn sự kiện', 'Event options')}
        wrapStyle={{ position: 'fixed', top: OVERLAY_TOP, right: 112, zIndex: 6 }} menuTestId="event-detail-menu"
        trigger={(
          <div data-fade onClick={() => setMenuOpen(o => !o)} role="button" aria-haspopup="menu" aria-label={T('Thêm', 'More')} aria-expanded={menuOpen} data-testid="event-detail-more" style={disc()}><IconMore /></div>
        )}>
        {showOpenInMap && <GlassMenuItem icon={<IconMap />} onClick={() => openEventOnMap(ev)} testId="event-open-in-map">{T('Xem trên bản đồ', 'Open in map')}</GlassMenuItem>}
        {!cameFromHome && <GlassMenuItem icon={<IconHouse />} onClick={goHome} testId="event-back-home">{T('Về trang chính', 'Back to home')}</GlassMenuItem>}
        {s.myOrgEventKeys.includes(ev.key) && (
          <GlassMenuItem icon={<IconCamera />} disabled={s.storyCreateBusy} onClick={() => setShareConfirmOpen(true)} testId="event-share-to-story">
            {s.storyCreateBusy ? T('Đang đăng…', 'Posting…') : T('Chia sẻ lên Story', 'Share to Story')}
          </GlassMenuItem>
        )}
        {(showOpenInMap || !cameFromHome || s.myOrgEventKeys.includes(ev.key)) && <GlassMenuDivider />}
        <GlassMenuItem icon={<IconLink />} onClick={copyLink} testId="event-copy-link">{T('Sao chép link', 'Copy link')}</GlassMenuItem>
      </GlassMenu>
      <div data-fade onClick={() => shareEvent(ev)} role="button" aria-label={T('Chia sẻ', 'Share')} data-testid="event-detail-share" style={disc({ position: 'fixed', top: OVERLAY_TOP, right: 64, zIndex: 5 })}><IconShare /></div>
      {/* Save uses the same isSaved/toggleFav as Home (keys off the real `favorites` table by event id). */}
      <div data-fade onClick={() => toggleFav(ev.key)} role="button" aria-label={isSaved(ev.key) ? T('Đã lưu', 'Saved') : T('Lưu', 'Save')} aria-pressed={isSaved(ev.key)} data-testid="event-detail-save" style={disc({ position: 'fixed', top: OVERLAY_TOP, right: 16, zIndex: 5 })}><IconHeart filled={isSaved(ev.key)} /></div>
      {(s.shared || linkCopied) && (
        <div role="status" style={{ position: 'fixed', top: `calc(${OVERLAY_TOP} + 48px)`, right: 16, zIndex: 5, fontSize: 12, color: ink, background: 'rgba(var(--bb-bg-rgb),0.94)', borderRadius: 999, padding: '6px 12px', boxShadow: '0 4px 12px rgba(0,0,0,0.12)' }}>{T('Đã sao chép link', 'Link copied')}</div>
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
          {/* Category as an ink chip (mockup); invite-only beside it in clay. */}
          {evCat && <span data-testid="event-category" style={{ fontSize: 11.5, fontWeight: 600, letterSpacing: '0.06em', textTransform: 'uppercase', color: paper, background: ink, padding: '5px 12px', borderRadius: RADIUS.pill }}>{evCat}</span>}
          {ev.inviteOnly && (
            <span data-testid="event-invite-chip" style={{ fontSize: 11.5, fontWeight: 600, color: clay, background: clayBg, padding: '5px 12px', borderRadius: RADIUS.pill }}>{T('Riêng tư ▪︎ theo lời mời', 'Private ▪︎ invite only')}</span>
          )}
        </div>
        {/* Title + the calendar pill on one row (iOS EventPlanTitleRow). */}
        <div ref={titleWrapRef} style={{ transformOrigin: 'left bottom', willChange: 'transform, opacity' }}>
          <EventPlanTitle eventKey={ev.key} title={ev.name} titleStyle={display(28, { lineHeight: 1.2 })} />
        </div>
        {/* Body copy supports the title instead of competing with it. Long descriptions clamp to 4 lines when the
            fuller write-up is one tap away (About & Included sheet). */}
        <p style={{ fontSize: 15, lineHeight: 1.55, color: ink, opacity: 0.85, margin: '4px 0 0', ...(canClamp ? { display: '-webkit-box', WebkitLineClamp: 4, WebkitBoxOrient: 'vertical', overflow: 'hidden' } : null) }}>{ev.desc}</p>
        {canClamp && (
          <div onClick={() => setIncludedSheetOpen(true)} data-testid="event-read-more" style={{ marginTop: 6, fontSize: 13, fontWeight: 600, color: ink, cursor: 'pointer' }}>{T('Xem thêm', 'Read more')}</div>
        )}
        {/* Host track record in clay — where the mockup puts its rating row. Real data only: banbe has no ratings. */}
        {trackParts.length > 0 && (
          <div onClick={() => openOrganizerOfEvent(ev.key, 'event')} role="button" data-testid="event-track-record" style={{ marginTop: 10, display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap', fontSize: 14, color: clay, cursor: 'pointer' }}>
            <IconHost /><span>{trackParts.join(' · ')}</span>
            {evOrgFollowed && <FollowingBadge T={T} testId="event-organizer-following" />}
          </div>
        )}
        {ev.price && (
          <div data-testid="event-price" style={{ marginTop: 12, display: 'flex', alignItems: 'baseline', gap: 6 }}>
            <span style={display(26)}>{trStatus(ev.price)}</span>
            {!isFree && <span style={{ fontSize: 13, color: ink, opacity: 0.6 }}>{T('/ vé', '/ ticket')}</span>}
          </div>
        )}
        {/* Ngày / Giờ / Địa điểm: three equal tiles; directions is an icon-only link in the place tile's corner. */}
        <div data-testid="event-facts" style={{ marginTop: 14, display: 'flex', gap: 8 }}>
          {whenDate && <Tile icon={<IconCalendar />} label={T('Ngày', 'Date')} testId="event-fact-when">{whenDate}</Tile>}
          {whenTime && <Tile icon={<IconClock />} label={T('Giờ', 'Time')} testId="event-fact-time">{whenTime}</Tile>}
          <Tile icon={<IconPin />} label={T('Địa điểm', 'Place')} testId="event-fact-where"
            action={evMapsUrl && (
              <a href={evMapsUrl} target="_blank" rel="noopener noreferrer" data-testid="event-maps-link" aria-label={T('Xem bản đồ', 'Directions')} title={T('Xem bản đồ', 'Directions')}
                // Opening directions is the natural moment to also offer to show the distance, if undecided — never
                // blocks the click itself (the maps link still opens via the normal href).
                onClick={() => { if (s.located === null) askLocation(); }}
                style={{ position: 'absolute', top: 8, right: 8, width: 28, height: 28, borderRadius: '50%', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: clay, background: clayBg }}>
                <IconDirections />
              </a>
            )}>
            {evWhere}
          </Tile>
        </div>
        {/* Seats: a thin clay bar when capacity is known, otherwise just the text. */}
        <div data-testid="event-fact-seats" style={{ marginTop: 12, display: 'flex', alignItems: 'center', gap: 12 }}>
          {fillRatio != null && (
            <div aria-hidden style={{ flex: 1, height: 5, borderRadius: 3, background: 'rgba(var(--bb-fg-rgb),0.08)', overflow: 'hidden' }}>
              <div style={{ width: `${Math.max(4, fillRatio * 100)}%`, height: '100%', borderRadius: 3, background: `linear-gradient(90deg, rgba(var(--bb-clay-rgb),0.75), ${clay})` }} />
            </div>
          )}
          <span style={{ flex: fillRatio != null ? 'none' : 1, fontSize: 13.5, color: ev.soldOut ? ink : clay, textAlign: fillRatio != null ? 'right' : 'left' }}>{seatsText}</span>
        </div>
        <WhoCanReserve criteria={crit.criteria} style={{ marginTop: 10 }} />
        {crit.restricted && crit.blocked && !myBooking && !ev.cancelled && !ended && (
          <div ref={critRef} style={{ marginTop: 12, scrollMarginBottom: 160 }}><CriteriaUnmetCard eligibility={crit.eligibility} returnTo="event" /></div>
        )}
        {/* Sections below are separated by whitespace only (no rules): 28 between sections, 8–10 from a heading to its
            content, so related things sit together and the page reads as one calm surface (transcript lessons 3/11/12). */}
        {/* "Bao gồm": one line of text, items separated by the signature ▪︎; the full intro + item details stay one tap
            away in the About & Included sheet. */}
        {(includedChips.length > 0 || hasAboutSheet) && (
          <div onClick={hasAboutSheet ? () => setIncludedSheetOpen(true) : undefined} data-testid="event-included-section"
            aria-label={hasAboutSheet ? T('Giới thiệu và bao gồm, xem thêm', 'Introduction and included, view more') : undefined}
            style={{ marginTop: 20, cursor: hasAboutSheet ? 'pointer' : 'default' }}>
            <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12 }}>
              <span style={sectionHeading}>{includedChips.length > 0 ? T('Bao gồm', 'Included') : T('Giới thiệu', 'About')}</span>
              {hasAboutSheet && <span style={{ fontSize: 13, fontWeight: 600, color: clay, whiteSpace: 'nowrap' }}>{T('Xem thêm', 'More')} ›</span>}
            </div>
            {includedChips.length > 0 && (
              <p style={{ margin: '8px 0 0', fontSize: 15, lineHeight: 1.55, color: ink }}>
                {includedChips.map((label, i) => (
                  <span key={i}>{i > 0 && <span aria-hidden style={{ color: clay, margin: '0 8px' }}>▪︎</span>}{label}</span>
                ))}
              </p>
            )}
          </div>
        )}
        {/* "Người tổ chức": its own section — heading, then a soft card with the host and two actions (same outlined clay
            buttons as before). */}
        <div data-testid="event-host-section" style={{ marginTop: 32 }}>
          <div style={sectionHeading}>{T('Người tổ chức', 'Host')}</div>
          <div style={{ marginTop: 10, padding: 14, borderRadius: RADIUS.card, background: 'rgba(var(--bb-fg-rgb),0.045)', border: `1px solid ${softRule}` }}>
            <div onClick={() => openOrganizerOfEvent(ev.key, 'event')} data-testid="event-organizer-row" role="button" aria-label={T('Trang của ', 'Page of ') + (ev.orgName || T('người tổ chức', 'the host'))} style={{ display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer' }}>
              <span style={{ flex: 'none', width: 44, height: 44, borderRadius: '50%', overflow: 'hidden', background: 'var(--bb-field)', border: `0.5px solid ${rule}`, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 16, fontWeight: 600, color: ink }}>
                {orgAvatarUrl ? <img src={orgAvatarUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : orgInitial}
              </span>
              <span style={{ minWidth: 0, display: 'flex', flexDirection: 'column', gap: 3 }}>
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
                  <span style={{ ...display(16), overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{ev.orgName || T('Người tổ chức', 'Host')}</span>
                  {evOrgFollowed && <FollowingBadge T={T} testId="event-host-following" />}
                </span>
                {hostSubline && <span data-testid="event-organizer-stats" style={{ fontSize: 12.5, color: ink, opacity: 0.65 }}>{hostSubline}</span>}
              </span>
            </div>
            <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
              <div onClick={() => openOrganizerOfEvent(ev.key, 'event')} data-testid="event-organizer-profile" role="button"
                style={{ ...pillBtn, flex: 1, padding: '9px 14px', border: `1px solid ${clay}`, fontSize: 13.5, fontWeight: 600, color: clay }}>
                <IconHost />{T('Xem hồ sơ', 'View profile')}
              </div>
              {/* Moved here from the retired Organizer screen (merged into the host profile): message the host from the event. */}
              <div onClick={goChat} data-testid="organizer-message" role="button" aria-label={T('Nhắn cho ', 'Message ') + (ev.orgName || '')}
                style={{ ...pillBtn, flex: 1, padding: '9px 14px', border: `1px solid ${clay}`, fontSize: 13.5, fontWeight: 600, color: clay }}>
                <IconChat />{T('Nhắn tin', 'Message')}
              </div>
            </div>
          </div>
        </div>
        {/* "Hình ảnh": the horizontal photo strip. */}
        <div style={{ marginTop: 28 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
            <span style={sectionHeading}>{T('Hình ảnh', 'Photos')}</span>
            {realPhotos.length > 0 && <span style={{ fontSize: 13, color: ink, opacity: 0.6 }}>{realPhotos.length}</span>}
          </div>
          {/* STAGE D (2026-09-25) — real event_photos rows, not the static demo `ev.gallery`. A genuinely photo-less
              real event shows plain text, never a fake/demo photo standing in for a real one. */}
          {s.eventPhotosLoading ? (
            <p style={{ fontSize: 13, color: ink, opacity: 0.6, margin: '10px 0 0' }}>{T('Đang tải…', 'Loading…')}</p>
          ) : realPhotos.length ? (
            <div data-testid="event-photo-strip" style={{ display: 'flex', gap: 8, overflowX: 'auto', marginTop: 10, paddingBottom: 4 }}>
              {realPhotos.map((p, i) => (
                <div key={p.id} onClick={(e) => openPhoto(realPhotos, i, ev.orgName, e.currentTarget.getBoundingClientRect())} data-testid={`event-photo-${i}`} data-photo-thumb={p.id} style={{ position: 'relative', flex: 'none' }}>
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
      </div>
      </div>
      {/* Sticky action area (mockup): seat chips + stepper, the refund promise, and the CTA with the live total —
          always on screen, so the decision can happen wherever the reader is convinced. Reserve opens pre-filled. */}
      <div data-fade data-testid="event-action-area" style={{ touchAction: 'none', overscrollBehavior: 'contain', flex: 'none', position: 'relative', zIndex: 2, background: paper, borderRadius: '22px 22px 0 0', boxShadow: '0 -8px 24px rgba(27,25,22,0.10)', padding: '12px 16px calc(12px + env(safe-area-inset-bottom, 0px))' }}>
        {barState === 'reserve' && (
          <div data-testid="event-qty" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8, marginBottom: 10 }}>
            <div role="radiogroup" aria-label={T('Số vé', 'Tickets')} style={{ display: 'flex', gap: 6, minWidth: 0 }}>
              {QTY_PRESETS.map(n => {
                const on = qty === n;
                return (
                  <div key={n} role="radio" aria-checked={on} onClick={() => setQty(n)} data-testid={`event-qty-${n}`}
                    style={{ ...pillBtn, height: 34, padding: '0 13px', fontSize: 14, fontWeight: on ? 600 : 500, background: on ? ink : 'rgba(var(--bb-fg-rgb),0.06)', color: on ? paper : ink, transition: 'background .15s ease, color .15s ease' }}>
                    {T(`${n} vé`, n === 1 ? '1 ticket' : `${n} tickets`)}
                  </div>
                );
              })}
            </div>
            <div data-testid="event-qty-stepper" role="group" aria-label={T('Số vé', 'Tickets')} style={{ flex: 'none', display: 'inline-flex', alignItems: 'center', height: 34, borderRadius: RADIUS.pill, border: `1px solid ${clay}`, color: clay }}>
              <button type="button" onClick={() => setQty(qty - 1)} disabled={qty <= 1} aria-label={T('Bớt một vé', 'One ticket fewer')} data-testid="event-qty-minus"
                style={{ width: 34, height: 32, border: 'none', background: 'none', color: 'inherit', fontSize: 18, cursor: qty <= 1 ? 'default' : 'pointer', opacity: qty <= 1 ? 0.35 : 1, fontFamily: 'inherit' }}>−</button>
              <span aria-live="polite" data-testid="event-qty-value" style={{ minWidth: 18, textAlign: 'center', fontSize: 15, fontWeight: 600, color: ink }}>{qty}</span>
              <button type="button" onClick={() => setQty(qty + 1)} disabled={qty >= MAX_QTY} aria-label={T('Thêm một vé', 'One more ticket')} data-testid="event-qty-plus"
                style={{ width: 34, height: 32, border: 'none', background: 'none', color: 'inherit', fontSize: 18, cursor: qty >= MAX_QTY ? 'default' : 'pointer', opacity: qty >= MAX_QTY ? 0.35 : 1, fontFamily: 'inherit' }}>+</button>
            </div>
          </div>
        )}
        {trustLine && (
          <div data-testid="event-trust-line" style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 10, fontSize: 12.5, lineHeight: 1.35, color: ink, opacity: 0.8 }}>
            <span style={{ color: clay, display: 'inline-flex', flex: 'none' }}><IconShield /></span>{trustLine}
          </div>
        )}
        <div onClick={reserveBarTap} role="button" style={reserveBarStyle} data-testid="event-reserve-bar" data-state={barState} aria-disabled={!reserveBarTap || undefined}>{reserveBarLabel}</div>
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

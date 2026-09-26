import { useEffect, useMemo } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { EVENTS, bg, agoLabel } from '../data/events.js';
import { formatCountdown, msUntil, pickSoonest, useTicking, liveEventOverrides, formatVnEventDate } from '../lib/countdown.js';
import { paper, ink, rule, display, fieldGlass, CHIP_COLORS, photoChip, lightChip, alert, cardGlass } from '../theme.js';
import { buildActionCenterItems, sortActionCenterItems } from '../lib/actionCenter.js';
import { formatVnd } from '../lib/paymentDocument.js';
import ActionCenter from './ActionCenter.jsx';

// Second, independent chip row (12-home-filters.md) — multi-select,
// AND-combined with FILTER_DEFS' category row and the area picker, not a
// third incompatible filter system: each reuses an existing definition
// (isGoing's status set from note 04, isSaved's favorites, e.soldOut's
// static catalogue flag) rather than recomputing any of them.
//
// 2026-09-21 follow-up (07-notifications.md) — extended with notConfirmed
// (a refinement of the original three, now that isGoing is scoped to
// genuinely-confirmed — see GocContext.jsx's own comment on isGoing) plus
// upcoming/ended, using the same live-status data the "Sự kiện của bạn"
// strip's real 48h expiry now needs anyway (homeLiveEvents) — not a
// separate concept.
//
// Second follow-up (same day): notAttending/notSaved removed entirely per
// this ticket's own instruction (redundant inverses that cluttered the
// row without earning their keep) — Upcoming/Saved/Attending reordered to
// lead, Ended kept last.
const HOME_EXTRA_FILTERS = [
  { key: 'upcoming', vi: 'Sắp diễn ra', en: 'Upcoming' },
  { key: 'saved', vi: 'Đã lưu', en: 'Saved' },
  { key: 'attending', vi: 'Đang tham gia', en: 'Attending' },
  { key: 'notConfirmed', vi: 'Chưa xác nhận', en: 'Not confirmed' },
  { key: 'soldOut', vi: 'Hết chỗ', en: 'Sold out' },
  { key: 'ended', vi: 'Đã kết thúc', en: 'Ended' },
];

export const FILTER_DEFS = [
  { key: 'all', vi: 'Tất cả', en: 'All' },
  { key: 'supper', vi: 'Supper club', en: 'Supper club' },
  { key: 'fashion', vi: 'Thời trang', en: 'Fashion' },
  { key: 'gallery', vi: 'Phòng tranh', en: 'Gallery' },
  { key: 'music', vi: 'Nhạc', en: 'Music' },
];

export default function Home() {
  const {
    state, set, T, trStatus, stripKm, curArea, isSaved, isGoing, isAwaitingConfirmation, toggleFav,
    goEvent, openArea, toggleLang, toggleTheme, pickFilter, clearFilters, toggleHomeFilter,
    becomeHost, switchToHost,
    canHost, loadPaymentBookings, loadVerifications, loadOrganizerHoldingSummary, loadHomeLiveEvents,
    openPaymentDetails, openVerifications, goDashboard, forfeitExpiredHold,
    loadHomeStories, openStoryViewer,
    loadMyRefunds, openMyRefunds, loadRefundQueue, goNotifications,
    openPulseViewer, loadWeekendEvents, loadDiscoveryEvents, loadRealEventsById,
  } = useGoc();

  const s = state;
  const hasHosted = s.hasHosted;
  const openSaved = (sv) => (sv.toEvent === 'event' ? goEvent(sv.key) : set({ screen: sv.toEvent, eventKey: sv.key }));
  const heldEv = s.holdDeadline && s.holdDeadline > s.now ? EVENTS.find(e => e.key === s.eventKey) : null;

  // Both phases, both roles: what this account is waiting on right now, as
  // a participant (their own bookings) and — separately — as the organizer
  // of events other people are booking. Loaded once signed in, refreshed
  // each time Home mounts (a hold or a verification can settle anywhere:
  // another tab, the organizer's Telegram bot, the bank webhook).
  useEffect(() => {
    if (!s.user?.id) return;
    loadPaymentBookings();
    loadMyRefunds();
    if (canHost) {
      loadVerifications();
      loadOrganizerHoldingSummary();
      loadRefundQueue();
    }
  }, [s.user?.id, canHost, loadPaymentBookings, loadVerifications, loadOrganizerHoldingSummary, loadMyRefunds, loadRefundQueue]);

  // 2026-09-21 follow-up — real (not baked-in) ended/cancelled status for
  // every catalogue event Home might show, public info so this runs for
  // every visitor (see GocContext.jsx's own comment on loadHomeLiveEvents).
  useEffect(() => { loadHomeLiveEvents(); }, [loadHomeLiveEvents]);
  // Discovery-bug fix — fires on every Home mount, same as every other
  // real-events loader on this screen (App.jsx's Shell remounts the whole
  // screen component on a `screen` change, so navigating away and back
  // already re-fires this — a fresh admin approval is visible the very
  // next time this screen mounts, with no separate "refresh" affordance
  // needed).
  useEffect(() => { loadDiscoveryEvents(); }, [loadDiscoveryEvents]);
  // Retention roadmap P1 — "Cuối tuần này". Public info, same as
  // loadHomeLiveEvents above (runs for every visitor); re-fires on sign-in/
  // out too, since loadWeekendEvents' own followed-host sort depends on
  // `s.user` and is part of that function's dependency list.
  useEffect(() => { loadWeekendEvents(); }, [loadWeekendEvents]);
  // Task 3.3 (07-notifications.md) — active stories row.
  useEffect(() => { if (s.user?.id) loadHomeStories(); }, [s.user?.id, loadHomeStories]);
  // Merges a real DB row's live status onto a static catalogue event —
  // same idea as curEvent's own single-event version (GocContext.jsx), just
  // applied to every event this screen might list instead of one.
  const withLive = (e) => {
    const overrides = liveEventOverrides(s.homeLiveEvents[e.key], e);
    return overrides ? { ...e, ...overrides } : e;
  };

  const myHolding = pickSoonest(s.paymentBookings, 'holding', 'hold_expires_at');
  const myPendingVerification = (s.paymentBookings || [])
    .filter(b => b.payment_state === 'pending_verification')
    .sort((a, b) => new Date(a.proof_uploaded_at || 0) - new Date(b.proof_uploaded_at || 0))[0] || null;

  const orgPendingCount = (s.verifications || []).length;
  const orgSoonestVerifyDue = (s.verifications || [])
    .map(v => v.verify_due_at).filter(Boolean).sort()[0] || null;
  const orgHolding = s.organizerHoldingSummary;

  // Any of these five countdown-relevant items ticking is reason enough to
  // re-render every second; none of them showing means no clock runs at all.
  const anyCountdownVisible = !!(heldEv || myHolding || myPendingVerification || orgPendingCount || orgHolding);
  const tickNow = useTicking(anyCountdownVisible);

  // TASK A (2026-10-01 UX foundation pass) — replaces the old fixed
  // "always show all four PhaseBanners" block: goer items (this account's
  // own bookings/refunds) always considered, host items only while
  // `canHost`, merged and re-sorted together by buildActionCenterItems()'s
  // shared priority order, capped to 3 + "Xem tất cả" by <ActionCenter>.
  const actionItems = useMemo(() => sortActionCenterItems([
    ...buildActionCenterItems({
      role: 'goer', T, now: tickNow,
      myHolding, myPendingVerification, myRefunds: s.myRefunds || [],
      onOpenPayment: (bookingId) => openPaymentDetails(bookingId, 'home'),
      onOpenMyRefunds: () => openMyRefunds('home'),
    }),
    ...(canHost ? buildActionCenterItems({
      role: 'host', T, now: tickNow,
      verifications: s.verifications || [], refundQueue: s.refundQueue || [], orgHolding,
      onOpenVerifications: () => openVerifications('home'),
      onOpenRefundCenter: () => openVerifications('home'),
      onOpenDashboard: goDashboard,
    }) : []),
  ]), [T, tickNow, myHolding, myPendingVerification, s.myRefunds, canHost, s.verifications, s.refundQueue, orgHolding, openPaymentDetails, openMyRefunds, openVerifications, goDashboard]);

  // Home is often the screen a buyer is sitting on when a hold's countdown
  // reaches zero — not just the ticket screen. myHolding above already
  // excludes a lapsed row (that's what makes the banner disappear on time),
  // which means it can't be used to notice the transition; this checks the
  // raw list directly so Home can forfeit it the same instant the banner
  // for it vanishes, rather than leaving that to whichever other screen the
  // buyer happens to open next.
  useEffect(() => {
    const justLapsed = (s.paymentBookings || []).find(
      b => b.payment_state === 'holding' && b.hold_expires_at && msUntil(b.hold_expires_at, tickNow) === 0
    );
    if (justLapsed) forfeitExpiredHold(justLapsed);
  }, [s.paymentBookings, tickNow, forfeitExpiredHold]);

  const filters = FILTER_DEFS.map(f => ({
    key: f.key,
    label: T(f.vi, f.en),
    style: {
      fontSize: 12.5, cursor: 'pointer', paddingBottom: 6, color: ink,
      fontWeight: s.filter === f.key ? 600 : 400,
      borderBottom: s.filter === f.key ? `2px solid ${ink}` : '2px solid transparent',
    },
  }));

  // Discovery-bug fix — every real event (loadDiscoveryEvents above),
  // reshaped to the exact same card fields the static catalogue's own
  // `withLive` output has, so it flows through the SAME filter/sort/map
  // pipeline below (category, area, saved/attending/soldOut/upcoming/ended
  // chips, card markup) with no second, parallel rendering path to drift
  // out of sync with the static one. Deduped against the static catalogue
  // by key (real ids are a slug + random suffix and practically never
  // collide, but a real event is authoritative if they ever did).
  // `liveEventOverrides` is reused here exactly as `withLive` reuses it for
  // a static row — the only difference is there's no static counterpart to
  // merge onto, so it's called with `staticEv: null`.
  const discoveryShaped = useMemo(() => (s.discoveryEvents || [])
    .filter(e => !EVENTS.some(se => se.key === e.key))
    .map(e => {
      const overrides = liveEventOverrides(
        { starts_at: e.startsAt, status: e.status, cancelled_at: e.cancelledAt }, null
      ) || {};
      const seatsText = e.seatsRemaining != null ? `${e.seatsRemaining} chỗ trống` : '';
      return {
        key: e.key,
        name: e.name,
        img: e.photoUrl,
        isReal: true,
        catKey: e.catKey,
        cat2Key: null,
        // No static "invite-only" demo concept — a real non-public event
        // (draft/review/invite) is excluded from discovery the same honest
        // way the ticket asks for: it just never enters this array at all
        // (the query itself is `visibility='public'`), this flag only
        // covers the theoretical case of a future non-public real row
        // reaching this far.
        inviteOnly: e.visibility !== 'public',
        area: e.area,
        meta: `${e.area}${e.area && overrides.when ? ' ▪︎ ' : ''}${overrides.when || ''}`,
        catDisplay: e.catLabel || e.catKey,
        price: e.priceVnd ? formatVnd(e.priceVnd) : 'Miễn phí',
        seats: seatsText,
        soldOut: e.soldOut,
        cancelled: overrides.cancelled ?? false,
        cancelledHoursAgo: overrides.cancelledHoursAgo ?? null,
        endedHoursAgo: overrides.endedHoursAgo ?? null,
        until: overrides.until ?? null,
        untilLabel: overrides.untilLabel ?? '',
        agoLabel,
      };
    }), [s.discoveryEvents]);

  const demoted = e => (e.cancelled && (e.cancelledHoursAgo == null || e.cancelledHoursAgo >= 2)) ? 1 : 0;
  const feed = useMemo(() => [...EVENTS, ...discoveryShaped]
    .map(withLive)
    .filter(e => !e.inviteOnly && (s.filter === 'all' || e.catKey === s.filter || e.cat2Key === s.filter) && curArea.match(e))
    .filter(e => !s.filterAttending || isGoing(e.key))
    .filter(e => !s.filterNotConfirmed || isAwaitingConfirmation(e.key))
    .filter(e => !s.filterSaved || isSaved(e.key))
    .filter(e => !s.filterSoldOut || e.soldOut)
    .filter(e => !s.filterUpcoming || (!e.cancelled && e.endedHoursAgo == null))
    .filter(e => !s.filterEnded || e.endedHoursAgo != null)
    .sort((a, b) => demoted(a) - demoted(b))
    .map(e => {
      let seats = e.seats;
      if (e.cancelled) seats = 'Đã hủy';
      else if (e.soldOut) seats = 'Hết chỗ';
      else if (e.endedHoursAgo != null) seats = e.agoLabel(e.endedHoursAgo);
      else if (e.until != null) seats = e.seats + ' ▪︎ ' + e.untilLabel.replace(/^Còn /, '');
      const saved = isSaved(e.key);
      const going = isGoing(e.key) && !e.cancelled && e.endedHoursAgo == null;
      return {
        ...e,
        metaDisplay: trStatus(e.catDisplay) + ' ▪︎ ' + trStatus(stripKm(e.meta, e)),
        seatsDisplay: trStatus(seats),
        saved, going,
        goingLabel: trStatus('Đang tham gia' + ((s.tickets[e.key] || 1) > 1 ? ' ▪︎ ' + s.tickets[e.key] + ' vé' : '')),
        saveLabel: saved ? T('Đã lưu', 'Saved') : T('Lưu', 'Save'),
      };
    }), [discoveryShaped, s.filter, s.filterAttending, s.filterNotConfirmed, s.filterSaved, s.filterSoldOut, s.filterUpcoming, s.filterEnded, s.tickets, s.homeLiveEvents, curArea, isSaved, isGoing, isAwaitingConfirmation, trStatus, stripKm, T]);

  // Retention roadmap P1 ("Cuối tuần này") — reuses the SAME district
  // (curArea) and category (s.filter) picks already driving the main feed
  // above, rather than inventing a separate preference of its own; there is
  // no existing price preference anywhere in this app to reuse, so price
  // isn't filtered here, only displayed. `weekendEvents` itself is already
  // real-events-only and pre-sorted (followed hosts first, then soonest —
  // see loadWeekendEvents' own comment); this only narrows by the two
  // shared filters and caps it to a compact strip.
  const AREA_DISTRICT_MATCH = {
    q1: a => a.includes('Quận 1'),
    thaodien: a => a.includes('Thảo Điền'),
    binhthanh: a => a.includes('Bình Thạnh'),
    other: a => !a.includes('Quận 1') && !a.includes('Thảo Điền') && !a.includes('Bình Thạnh'),
  };
  const weekendList = useMemo(() => (s.weekendEvents || [])
    .filter(e => (AREA_DISTRICT_MATCH[curArea.key] || (() => true))(e.area))
    .filter(e => s.filter === 'all' || e.catKey === s.filter)
    .slice(0, 12)
    .map(e => ({
      ...e,
      saved: isSaved(e.key),
      priceDisplay: e.priceLabel || T('Miễn phí', 'Free'),
      seatsDisplay: e.soldOut ? T('Hết chỗ', 'Sold out') : (e.seatsRemaining != null ? T(e.seatsRemaining + ' chỗ trống', e.seatsRemaining + ' left') : ''),
    })), [s.weekendEvents, curArea.key, s.filter, isSaved, T]);

  const heldKey = heldEv ? heldEv.key : null;
  const savedKeys = [...new Set([...s.favorites, ...s.attending, ...s.invited, ...(heldKey ? [heldKey] : [])])];

  // Blocker fix (retention roadmap follow-up) — a saved/attending/invited
  // event that ISN'T one of the 20 static demo ones (a real, host-created
  // event) used to just vanish here (EVENTS.find returns undefined,
  // filtered out by Boolean below) even though the favorite/booking row
  // itself was completely real. Anything not in the catalogue is now
  // resolved through the SAME canonical realEventsById cache the weekend
  // section uses (loadRealEventsById) — one lookup, not a second one.
  const missingRealKeys = savedKeys.filter(k => !EVENTS.some(e => e.key === k) && !(k in s.realEventsById));
  useEffect(() => {
    if (missingRealKeys.length) loadRealEventsById(missingRealKeys);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [missingRealKeys.join(','), loadRealEventsById]);

  // Task 2a (2026-09-21 follow-up) — real 48h-after-ENDED expiry: `withLive`
  // merges the actual DB row's status/starts_at (homeLiveEvents) so
  // `endedHoursAgo` is a genuinely ticking value instead of the static
  // catalogue's baked-in-forever number — an upcoming/ongoing event's
  // `endedHoursAgo` stays `null` (liveEventOverrides only sets it once
  // `status === 'ended'`), so this clause never fires for anything that
  // hasn't actually finished yet.
  const savedList = savedKeys
    .map(k => {
      const catalogEv = EVENTS.find(e => e.key === k);
      if (catalogEv) {
        const e = withLive(catalogEv);
        const nTix = s.tickets[e.key] || 1;
        const tixStr = nTix > 1 ? ' ▪︎ ' + nTix + ' vé' : '';
        const invited = e.inviteOnly && s.invited.includes(e.key);
        let tag, status, chip;
        if (e.cancelled) { tag = 'Đã hủy'; status = 'Đã hoàn tiền'; chip = CHIP_COLORS.cancelled; }
        else if (e.endedHoursAgo != null) { tag = 'Đã diễn ra'; status = e.agoLabel(e.endedHoursAgo); chip = CHIP_COLORS.past; }
        else if (invited && !isGoing(e.key)) { tag = T('Riêng tư', 'Private'); status = T('Chỉ bạn và +1 ▪︎ ', 'Just you + 1 ▪︎ ') + e.untilLabel; chip = CHIP_COLORS.invite; }
        else if (e.key === heldKey) { tag = 'Đang giữ'; status = 'Trả để xác nhận' + tixStr; chip = CHIP_COLORS.hold; }
        else if (isGoing(e.key)) { tag = 'Đã thanh toán'; status = e.untilLabel + tixStr; chip = CHIP_COLORS.going; }
        else { tag = 'Đã lưu'; status = e.untilLabel; chip = CHIP_COLORS.saved; }
        return {
          key: e.key, name: e.name, photoUrl: e.img, endedHoursAgo: e.endedHoursAgo,
          status: trStatus(status), tag: trStatus(tag), chip,
          canRemove: !isGoing(e.key) && e.key !== heldKey && !invited,
          toEvent: e.cancelled ? 'refunded' : 'event',
        };
      }
      const real = s.realEventsById[k];
      if (real === undefined) return null; // still loading — quiet, no flash
      if (real === null) {
        // Honest "unavailable" — deleted, or RLS no longer lets this
        // account see it. Never invented, never silently dropped.
        return {
          key: k, name: T('Sự kiện không khả dụng', 'Event unavailable'), photoUrl: null,
          status: '', tag: T('Không khả dụng', 'Unavailable'), chip: CHIP_COLORS.cancelled,
          endedHoursAgo: null, canRemove: isSaved(k), toEvent: null, unavailable: true,
        };
      }
      const startsAt = real.startsAt ? new Date(real.startsAt) : null;
      const untilLabel = startsAt ? (() => { const { weekdayShort, dayMonth, time } = formatVnEventDate(startsAt); return `${weekdayShort}, ${dayMonth} ▪︎ ${time}`; })() : '';
      const endedHoursAgo = real.status === 'ended' && startsAt ? Math.max(0, Math.round((Date.now() - startsAt.getTime()) / 3600000)) : null;
      const cancelled = real.status === 'cancelled';
      const invited = real.visibility === 'invite' && s.invited.includes(k);
      let tag, status, chip;
      if (cancelled) { tag = T('Đã hủy', 'Cancelled'); status = T('Đã hoàn tiền', 'Refunded'); chip = CHIP_COLORS.cancelled; }
      else if (endedHoursAgo != null) { tag = T('Đã diễn ra', 'Past'); status = T(endedHoursAgo + ' giờ trước', endedHoursAgo + 'h ago'); chip = CHIP_COLORS.past; }
      else if (invited && !isGoing(k)) { tag = T('Riêng tư', 'Private'); status = T('Chỉ bạn và +1 ▪︎ ', 'Just you + 1 ▪︎ ') + untilLabel; chip = CHIP_COLORS.invite; }
      else if (k === heldKey) { tag = T('Đang giữ', 'Holding'); status = T('Trả để xác nhận', 'Pay to confirm'); chip = CHIP_COLORS.hold; }
      else if (isGoing(k)) { tag = T('Đã thanh toán', 'Paid'); status = untilLabel; chip = CHIP_COLORS.going; }
      else { tag = T('Đã lưu', 'Saved'); status = untilLabel; chip = CHIP_COLORS.saved; }
      return {
        key: k, name: real.name, photoUrl: real.photoUrl, endedHoursAgo,
        status, tag, chip,
        canRemove: !isGoing(k) && k !== heldKey && !invited,
        toEvent: cancelled ? 'refunded' : 'event',
      };
    })
    .filter(Boolean)
    .filter(e => !(e.endedHoursAgo != null && e.endedHoursAgo > 48));

  const feedEmptyMsg = T(
    'Chưa có buổi nào ở ' + (curArea.key === 'all' ? 'mục này' : curArea.label) + ' tuần này, thử mục khác xem sao!',
    'Nothing in ' + (curArea.key === 'all' ? 'this category' : curArea.label) + ' this week, try another one!'
  );

  const homeHostLinkLabel = hasHosted ? T('Trang tổ chức của bạn', 'Your host page') : T('Dành cho người tổ chức ▪︎ hoàn toàn miễn phí', 'For organizers ▪︎ completely free');
  const homeHostLink = hasHosted ? () => switchToHost('home') : becomeHost;

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Home">
      <div style={{ padding: '70px 20px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <img src="/banbe-wordmark.png" alt="banbe" crossOrigin="anonymous" style={{ width: 126, height: 'auto', display: 'block', margin: '0 0 2px' }} />
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6 }}>
          {/* Task 2c (2026-09-21 follow-up) — a quick Appearance (light/dark)
              toggle next to the existing language/area switchers, separated
              by this app's own "▪" glyph (already used throughout its copy,
              e.g. event captions like "Th 5, 09.07 ▪ 21:00") rather than a
              new divider style. Wired to the SAME `toggleTheme` Preferences.jsx
              already uses — no parallel theme state. */}
          <div style={{ display: 'flex', gap: 8, alignItems: 'baseline' }}>
            {/* Task 1 (2026-09-21 follow-up) — bumped 11px -> 13px, just
                enough to read/tap more easily without unbalancing the rest
                of the header row (area/appearance stay at their existing
                size). */}
            <span onClick={toggleLang} style={{ fontSize: 13, fontWeight: 600, color: ink, cursor: 'pointer', letterSpacing: '0.06em', padding: '4px 2px' }}>{T('English', 'Tiếng Việt')}</span>
            <span style={{ fontSize: 9, color: ink, opacity: 0.4 }}>▪</span>
            {/* Task 3 (2026-09-22 twelfth follow-up) — area/appearance bumped to
                match the language toggle's size/weight/hit-area (13px/600,
                4px vertical padding) instead of the smaller 11px/400 they'd
                been left at when the language toggle was enlarged. */}
            <span onClick={openArea} style={{ fontSize: 13, fontWeight: 600, color: ink, cursor: 'pointer', padding: '4px 2px' }}>banbe ▪︎ {curArea.key === 'all' ? 'Sài Gòn' : curArea.label} ▾</span>
            <span style={{ fontSize: 9, color: ink, opacity: 0.4 }}>▪</span>
            <span onClick={toggleTheme} data-testid="home-theme-toggle" style={{ fontSize: 13, fontWeight: 600, color: ink, cursor: 'pointer', padding: '4px 2px' }}>{s.theme === 'dark' ? T('Sáng', 'Light') : T('Tối', 'Dark')}</span>
          </div>
        </div>
      </div>

      {/* TASK A (2026-10-01 UX foundation pass) — replaces the old fixed
          four-banner block: one unified, priority-sorted, 3-card-capped
          Action Center covering both roles this account can hold. See
          src/lib/actionCenter.js for the source list and ordering rule. */}
      <ActionCenter items={actionItems} onSeeAll={goNotifications} T={T} />

      {savedList.length > 0 && (
        <div style={{ padding: '16px 20px 4px', borderBottom: `1px solid ${rule}` }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 10 }}>
            <span style={{ ...display(15) }}>{T('Sự kiện của bạn', 'Your events')}</span>
            <span style={{ fontSize: 11.5, color: ink }}>{T('Sự kiện đã qua sẽ ẩn sau 48h', 'Past events clear after 48h')}</span>
          </div>
          <div style={{ display: 'flex', gap: 10, overflowX: 'auto', paddingBottom: 6 }}>
            {savedList.map(sv => (
              <div key={sv.key} onClick={sv.unavailable ? undefined : () => openSaved(sv)} style={{ flex: 'none', width: 152, cursor: sv.unavailable ? 'default' : 'pointer' }}>
                <div style={{ position: 'relative' }}>
                  {sv.photoUrl ? (
                    <div style={bg(sv.photoUrl, { width: 152, height: 96, borderRadius: 12, filter: 'none' })} />
                  ) : (
                    <div style={{ ...cardGlass({ width: 152, height: 96 }), display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                      <span style={{ fontSize: 10.5, color: ink, opacity: 0.55 }}>{sv.unavailable ? sv.tag : T('Chưa có ảnh', 'No photo yet')}</span>
                    </div>
                  )}
                  <span style={photoChip(sv.chip, { top: 6, left: 6, fontSize: 9, padding: '4px 8px', borderRadius: 12 })}>{sv.tag}</span>
                  {sv.canRemove && (
                    <span onClick={(ev) => { ev.stopPropagation(); toggleFav(sv.key); }} style={lightChip({ top: 6, right: 6, fontSize: 10, padding: '4px 8px', borderRadius: 12 })}>{T('Bỏ', 'Remove')}</span>
                  )}
                </div>
                <div style={{ ...display(15, { marginTop: 7, lineHeight: 1.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{sv.name}</div>
                <div style={{ fontSize: 11, color: ink, marginTop: 1 }}>{sv.status}</div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Task 3.3 (07-notifications.md) — active-story row, between "Your
          events" and the main event list, per this ticket's own placement.
          TASK E (2026-10-01 UX foundation pass) — "Banbe Pulse" is now a
          PERMANENT first entry (index 0), so the row itself is no longer
          conditional on real stories existing — it always shows at least
          Pulse. Never rendered on Map (this row only exists on Home). */}
      <div style={{ display: 'flex', gap: 14, overflowX: 'auto', padding: '14px 20px', borderBottom: `1px solid ${rule}` }}>
        <div
          onClick={openPulseViewer}
          data-testid="home-pulse-avatar"
          style={{ flex: 'none', width: 60, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 5, cursor: 'pointer' }}
        >
          {/* TASK 3 (2026-10-05 fix pass) — a refined multicolor shimmer,
              built from Banbe's own existing dusty-rose/sage gradient
              (the same two colors this used before) plus one warm sand
              stop in the same muted family — never a saturated rainbow.
              A single `hue-rotate` CSS animation, not a per-frame redraw
              loop; `prefers-reduced-motion: reduce` (see the <style> tag
              below) disables it, leaving the gradient's own resting frame
              — still colorful, just not moving — as the static fallback. */}
          <div className="bb-pulse-ring" style={{
            width: 56, height: 56, borderRadius: 15, display: 'flex', alignItems: 'center', justifyContent: 'center',
            background: 'linear-gradient(150deg, #E7C9C2, #E3CFA6 50%, #C8CBB2)',
          }}>
            <span style={{ fontSize: 20, color: '#fff', textShadow: '0 0 6px rgba(255,255,255,0.55)' }}>✦</span>
          </div>
          <style>{`
            @keyframes bb-pulse-hue { from { filter: hue-rotate(0deg); } to { filter: hue-rotate(360deg); } }
            .bb-pulse-ring { animation: bb-pulse-hue 7s linear infinite; }
            @media (prefers-reduced-motion: reduce) { .bb-pulse-ring { animation: none; } }
          `}</style>
          <span style={{ fontSize: 9.5, color: ink, textAlign: 'center', whiteSpace: 'nowrap' }}>{T('Banbe Pulse', 'Banbe Pulse')}</span>
        </div>
        {s.homeStories.length > 0 && (
          s.homeStories.map(g => (
            <div
              key={g.organizerId}
              onClick={(e) => {
                const r = e.currentTarget.getBoundingClientRect();
                openStoryViewer(g.organizerId, { top: r.top, left: r.left, width: r.width, height: r.height });
              }}
              data-testid="home-story-avatar"
              data-org-id={g.organizerId}
              data-story-state={g.allViewed ? 'viewed' : 'unviewed'}
              style={{ flex: 'none', width: 60, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 5, cursor: 'pointer' }}
            >
              <div style={{
                width: 56, height: 56, borderRadius: 15, display: 'flex', alignItems: 'center', justifyContent: 'center',
                border: `2.5px solid ${g.allViewed ? 'transparent' : alert}`,
                boxShadow: g.allViewed ? `inset 0 0 0 2.5px ${rule}` : 'none',
              }}>
                <div style={{ ...fieldGlass({ width: 48, height: 48, borderRadius: 11, display: 'flex', alignItems: 'center', justifyContent: 'center' }), fontSize: 16, fontWeight: 700 }}>
                  {(g.orgName || '?').charAt(0).toUpperCase()}
                </div>
              </div>
              <span style={{ fontSize: 9.5, color: ink, textAlign: 'center', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: 60 }}>{g.orgName}</span>
            </div>
          ))
        )}
      </div>

      <div style={{ display: 'flex', gap: 20, padding: '16px 20px 14px' }}>
        {filters.map(f => (
          <span key={f.key} onClick={() => pickFilter(f.key)} style={f.style}>{f.label}</span>
        ))}
      </div>

      {/* Task 2 (2026-09-21 follow-up) — `flexWrap: 'wrap'` + no
          `overflowX` instead of a horizontally-scrolling single row: every
          chip is now always visible (wraps to a second line if it doesn't
          fit), no swipe needed to see the rest. */}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, padding: '0 20px 14px' }}>
        {HOME_EXTRA_FILTERS.map(f => {
          // Every filter key maps to its state field by simple
          // capitalization (attending -> filterAttending, notConfirmed ->
          // filterNotConfirmed, ...) — see GocContext.jsx's HOME_FILTER_STATE_KEY.
          const active = s['filter' + f.key[0].toUpperCase() + f.key.slice(1)];
          return (
            <span
              key={f.key}
              onClick={() => toggleHomeFilter(f.key)}
              data-testid={`home-filter-${f.key.toLowerCase()}`}
              style={{ ...fieldGlass({}), padding: '6px 12px', fontSize: 12, whiteSpace: 'nowrap', cursor: 'pointer', color: ink, fontWeight: active ? 700 : 400, border: active ? `1px solid ${ink}` : 'none' }}
            >
              {T(f.vi, f.en)}
            </span>
          );
        })}
      </div>

      {feed.map(ev => (
        <div key={ev.key} data-testid={`home-event-${ev.key}`} onClick={() => goEvent(ev.key)} style={{ cursor: 'pointer', paddingBottom: 6 }}>
          <div style={{ position: 'relative' }}>
            {/* Discovery-bug fix — a real event with no uploaded photo yet
                gets the same honest "Chưa có ảnh" placeholder the weekend
                strip already uses below, never a static demo photo standing
                in for a real one. Static catalogue cards always have `img`
                set (bundled imports), so this branch is a no-op for them. */}
            {ev.isReal && !ev.img ? (
              <div style={{ ...cardGlass({ width: 'calc(100% - 40px)', height: 272, margin: '0 20px', borderRadius: '14px 14px 0 0' }), display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <span style={{ fontSize: 12, color: ink, opacity: 0.55 }}>{T('Chưa có ảnh', 'No photo yet')}</span>
              </div>
            ) : (
              <div style={bg(ev.img, { width: 'calc(100% - 40px)', height: 272, margin: '0 20px', borderRadius: '14px 14px 0 0' })} />
            )}
            <div style={{ position: 'absolute', left: 20, right: 20, bottom: 0, height: 58, background: `linear-gradient(to bottom, rgba(247,244,236,0) 0%, rgba(247,244,236,0.3) 62%, ${paper} 100%)`, pointerEvents: 'none' }} />
            <span
              onClick={(e) => { e.stopPropagation(); toggleFav(ev.key); }}
              style={ev.saved ? photoChip(CHIP_COLORS.going, { top: 12, right: 30 }) : lightChip({ top: 12, right: 30 })}
            >{ev.saveLabel}</span>
            {ev.going && (
              <span style={photoChip(CHIP_COLORS.going, { bottom: 12, left: 30 })}>{ev.goingLabel}</span>
            )}
          </div>
          <div style={{ padding: '14px 20px 18px', display: 'grid', gridTemplateColumns: '1fr auto', columnGap: 16 }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 }}>
              <span style={{ ...display(22, { lineHeight: 1.2 }) }}>{ev.name}</span>
              <span style={{ fontSize: 12.5, lineHeight: 1.35, color: ink, marginTop: 1 }}>{ev.metaDisplay}</span>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4, paddingTop: 4 }}>
              <span style={{ fontSize: 13, color: ink, whiteSpace: 'nowrap' }}>{trStatus(ev.price)}</span>
              <span style={{ fontSize: 11.5, color: ink, whiteSpace: 'nowrap', textAlign: 'right' }}>{ev.seatsDisplay}</span>
            </div>
          </div>
        </div>
      ))}

      {feed.length === 0 && (
        <div style={{ padding: '60px 40px 70px', textAlign: 'center' }}>
          <p style={{ fontSize: 14, lineHeight: 1.55, color: ink }}>{feedEmptyMsg}</p>
          <span onClick={clearFilters} style={{ display: 'inline-block', marginTop: 10, fontSize: 12.5, color: ink, cursor: 'pointer' }}>{T('Xem tất cả', 'See all')}</span>
        </div>
      )}

      {feed.length > 0 && (
        <div style={{ padding: '34px 20px 6px', textAlign: 'center', borderTop: `1px solid ${rule}` }}>
          <p style={{ ...display(11.5, { margin: 0 }) }}>{T('Hết rồi, ra ngoài chơi thôi!', "That's it, go have fun!")}</p>
        </div>
      )}

      {/* Retention roadmap P1 ("Cuối tuần này") — real live+public events
          for the applicable weekend (see loadWeekendEvents), never demo
          cards. Placed after the main feed (not the "Sự kiện của bạn"
          strip near the top) on purpose: it's a discovery section, not a
          personal one, and keeping the main feed's own card markup first
          in the DOM avoids collisions with generic "first card containing
          this event's name" test/query patterns already written against
          it. Suppressed during the very first load (list still empty AND
          still loading) so it never flashes the empty state for an
          instant before real data arrives — same "no false state on
          initial load" bar Stage 1's favorites work already holds to. */}
      {!(s.weekendEventsLoading && weekendList.length === 0) && (
        <div data-testid="home-weekend-section" style={{ padding: '16px 20px 4px', borderTop: `1px solid ${rule}` }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 10 }}>
            <span style={{ ...display(15) }}>{T('Cuối tuần này', 'This weekend')}</span>
          </div>
          {weekendList.length > 0 ? (
            <div style={{ display: 'flex', gap: 10, overflowX: 'auto', paddingBottom: 10 }}>
              {weekendList.map(e => (
                <div key={e.key} data-testid={`weekend-event-${e.key}`} onClick={() => goEvent(e.key)} style={{ flex: 'none', width: 168, cursor: 'pointer' }}>
                  <div style={{ position: 'relative' }}>
                    {e.photoUrl ? (
                      <div style={bg(e.photoUrl, { width: 168, height: 110 })} />
                    ) : (
                      // Honest placeholder — never a static demo photo
                      // standing in for a real one (roadmap's own rule).
                      <div style={{ ...cardGlass({ width: 168, height: 110 }), display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                        <span style={{ fontSize: 11, color: ink, opacity: 0.55 }}>{T('Chưa có ảnh', 'No photo yet')}</span>
                      </div>
                    )}
                    <span
                      onClick={(ev) => { ev.stopPropagation(); toggleFav(e.key); }}
                      data-testid={`weekend-save-${e.key}`}
                      style={e.saved ? photoChip(CHIP_COLORS.going, { top: 6, right: 6, fontSize: 9, padding: '4px 8px', borderRadius: 12 }) : lightChip({ top: 6, right: 6, fontSize: 9, padding: '4px 8px', borderRadius: 12 })}
                    >
                      {e.saved ? T('Đã lưu', 'Saved') : T('Lưu', 'Save')}
                    </span>
                    {e.soldOut && (
                      <span style={photoChip(CHIP_COLORS.cancelled, { bottom: 6, left: 6, fontSize: 9, padding: '4px 8px', borderRadius: 12 })}>{T('Hết chỗ', 'Sold out')}</span>
                    )}
                  </div>
                  <div style={{ ...display(14, { marginTop: 7, lineHeight: 1.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{e.name}</div>
                  <div style={{ fontSize: 11, color: ink, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{trStatus(e.when)}{e.area ? ' ▪︎ ' + e.area : ''}</div>
                  <div style={{ fontSize: 11, color: ink, marginTop: 1, display: 'flex', justifyContent: 'space-between', gap: 6 }}>
                    <span>{e.priceDisplay}</span>
                    <span>{e.seatsDisplay}</span>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <p data-testid="weekend-empty" style={{ fontSize: 12.5, color: ink, opacity: 0.7, padding: '4px 0 12px' }}>
              {T('Chưa có sự kiện phù hợp cuối tuần này.', 'No matching events this weekend yet.')}
            </p>
          )}
        </div>
      )}

      <div style={{ padding: '6px 20px 8px', fontSize: 11, color: ink }}>
        {T('Vài buổi vui dành cho riêng bạn tuần này. Không xếp hạng, không quảng cáo, không lướt vô tận.', 'A few fun gatherings made just for you this week. No ratings, no ads, no endless scrolling.')}
      </div>
      <div onClick={homeHostLink} style={{ padding: '4px 20px 44px', fontSize: 14.5, fontWeight: 600, letterSpacing: '-0.01em', color: ink, cursor: 'pointer' }}>{homeHostLinkLabel} ›</div>
    </div>
  );
}


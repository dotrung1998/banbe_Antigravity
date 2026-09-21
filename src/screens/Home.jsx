import { useEffect, useMemo } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { EVENTS, bg } from '../data/events.js';
import { formatCountdown, msUntil, pickSoonest, useTicking, liveEventOverrides } from '../lib/countdown.js';
import { paper, ink, rule, display, fieldGlass, CHIP_COLORS, photoChip, lightChip, alert } from '../theme.js';

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
    if (canHost) {
      loadVerifications();
      loadOrganizerHoldingSummary();
    }
  }, [s.user?.id, canHost, loadPaymentBookings, loadVerifications, loadOrganizerHoldingSummary]);

  // 2026-09-21 follow-up — real (not baked-in) ended/cancelled status for
  // every catalogue event Home might show, public info so this runs for
  // every visitor (see GocContext.jsx's own comment on loadHomeLiveEvents).
  useEffect(() => { loadHomeLiveEvents(); }, [loadHomeLiveEvents]);
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

  const demoted = e => (e.cancelled && (e.cancelledHoursAgo == null || e.cancelledHoursAgo >= 2)) ? 1 : 0;
  const feed = useMemo(() => EVENTS
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
    }), [s.filter, s.filterAttending, s.filterNotConfirmed, s.filterSaved, s.filterSoldOut, s.filterUpcoming, s.filterEnded, s.tickets, s.homeLiveEvents, curArea, isSaved, isGoing, isAwaitingConfirmation, trStatus, stripKm, T]);

  const heldKey = heldEv ? heldEv.key : null;
  const savedKeys = [...new Set([...s.favorites, ...s.attending, ...s.invited, ...(heldKey ? [heldKey] : [])])];
  // Task 2a (2026-09-21 follow-up) — real 48h-after-ENDED expiry: `withLive`
  // merges the actual DB row's status/starts_at (homeLiveEvents) so
  // `endedHoursAgo` is a genuinely ticking value instead of the static
  // catalogue's baked-in-forever number — an upcoming/ongoing event's
  // `endedHoursAgo` stays `null` (liveEventOverrides only sets it once
  // `status === 'ended'`), so this clause never fires for anything that
  // hasn't actually finished yet.
  const savedList = savedKeys
    .map(k => EVENTS.find(e => e.key === k)).filter(Boolean)
    .map(withLive)
    .filter(e => !(e.endedHoursAgo != null && e.endedHoursAgo > 48))
    .map(e => {
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
        key: e.key, name: e.name, img: e.img,
        status: trStatus(status), tag: trStatus(tag), chip,
        canRemove: !isGoing(e.key) && e.key !== heldKey && !invited,
        toEvent: e.cancelled ? 'refunded' : 'event',
      };
    });

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
            <span onClick={toggleLang} style={{ fontSize: 13, fontWeight: 600, color: ink, cursor: 'pointer', letterSpacing: '0.06em' }}>{T('English', 'Tiếng Việt')}</span>
            <span style={{ fontSize: 9, color: ink, opacity: 0.4 }}>▪</span>
            <span onClick={openArea} style={{ fontSize: 11, color: ink, cursor: 'pointer' }}>banbe ▪︎ {curArea.key === 'all' ? 'Sài Gòn' : curArea.label} ▾</span>
            <span style={{ fontSize: 9, color: ink, opacity: 0.4 }}>▪</span>
            <span onClick={toggleTheme} data-testid="home-theme-toggle" style={{ fontSize: 11, color: ink, cursor: 'pointer' }}>{s.theme === 'dark' ? T('Sáng', 'Light') : T('Tối', 'Dark')}</span>
          </div>
        </div>
      </div>

      {/* Both phases of the payment state machine, both roles this account
          can hold: what I (as a buyer) am waiting on, and — separately —
          what my own events' buyers are waiting on me for. Each row only
          renders while there is something real to show. */}
      {!!myHolding && (
        <PhaseBanner
          label={T('Đang giữ chỗ', 'Holding a seat')}
          detail={(myHolding.events?.name || '') + (myHolding.qty > 1 ? ' ▪︎ ' + myHolding.qty + T(' vé', ' tix') : '') + T(' ▪︎ trả để xác nhận', ' ▪︎ pay to confirm')}
          countdown={formatCountdown(msUntil(myHolding.hold_expires_at, tickNow))}
          onClick={() => openPaymentDetails(myHolding.id, 'home')}
        />
      )}
      {!!myPendingVerification && (
        <PhaseBanner
          label={T('Đang chờ xác nhận', 'Awaiting confirmation')}
          detail={(myPendingVerification.events?.name || '') + T(' ▪︎ đồng hồ đã dừng, chỗ được khoá', ' ▪︎ clock stopped, seat locked')}
          countdown={null}
          onClick={() => openPaymentDetails(myPendingVerification.id, 'home')}
        />
      )}
      {!!orgPendingCount && (
        <PhaseBanner
          label={T('Chờ bạn xác nhận thanh toán', 'Payments awaiting your OK')}
          detail={orgPendingCount + T(' khoản', orgPendingCount === 1 ? ' payment' : ' payments') + (orgSoonestVerifyDue ? T(' ▪︎ sớm nhất còn', ' ▪︎ soonest in') : '')}
          countdown={orgSoonestVerifyDue ? formatCountdown(msUntil(orgSoonestVerifyDue, tickNow)) : null}
          urgent={orgSoonestVerifyDue ? msUntil(orgSoonestVerifyDue, tickNow) === 0 : false}
          onClick={openVerifications}
          testId="home-org-verifications-banner"
        />
      )}
      {!!orgHolding && (
        <PhaseBanner
          label={T('Khách đang giữ chỗ', 'Guests holding seats')}
          detail={orgHolding.count + T(' chỗ', orgHolding.count === 1 ? ' seat' : ' seats') + T(' ▪︎ sớm nhất hết hạn trong', ' ▪︎ soonest expires in')}
          countdown={orgHolding.soonestHoldExpiresAt ? formatCountdown(msUntil(orgHolding.soonestHoldExpiresAt, tickNow)) : null}
          onClick={goDashboard}
          testId="home-org-holding-banner"
        />
      )}

      {savedList.length > 0 && (
        <div style={{ padding: '16px 20px 4px', borderBottom: `1px solid ${rule}` }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 10 }}>
            <span style={{ ...display(15) }}>{T('Sự kiện của bạn', 'Your events')}</span>
            <span style={{ fontSize: 11.5, color: ink }}>{T('Sự kiện đã qua sẽ ẩn sau 48h', 'Past events clear after 48h')}</span>
          </div>
          <div style={{ display: 'flex', gap: 10, overflowX: 'auto', paddingBottom: 6 }}>
            {savedList.map(sv => (
              <div key={sv.key} onClick={() => openSaved(sv)} style={{ flex: 'none', width: 152, cursor: 'pointer' }}>
                <div style={{ position: 'relative' }}>
                  <div style={bg(sv.img, { width: 152, height: 96, borderRadius: 12, filter: 'none' })} />
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
          events" and the main event list, per this ticket's own placement. */}
      {s.homeStories.length > 0 && (
        <div style={{ display: 'flex', gap: 14, overflowX: 'auto', padding: '14px 20px', borderBottom: `1px solid ${rule}` }}>
          {s.homeStories.map(g => (
            <div key={g.organizerId} onClick={() => openStoryViewer(g.organizerId)} data-testid="home-story-avatar" data-story-state={g.allViewed ? 'viewed' : 'unviewed'} style={{ flex: 'none', width: 60, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 5, cursor: 'pointer' }}>
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
          ))}
        </div>
      )}

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
            <div style={bg(ev.img, { width: 'calc(100% - 40px)', height: 272, margin: '0 20px', borderRadius: '14px 14px 0 0' })} />
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

      <div style={{ padding: '6px 20px 8px', fontSize: 11, color: ink }}>
        {T('Vài buổi vui dành cho riêng bạn tuần này. Không xếp hạng, không quảng cáo, không lướt vô tận.', 'A few fun gatherings made just for you this week. No ratings, no ads, no endless scrolling.')}
      </div>
      <div onClick={homeHostLink} style={{ padding: '4px 20px 44px', fontSize: 14.5, fontWeight: 600, letterSpacing: '-0.01em', color: ink, cursor: 'pointer' }}>{homeHostLinkLabel} ›</div>
    </div>
  );
}

// One row shape for every payment-phase banner Home shows, on either side
// of the transaction. `countdown` is optional — PHASE 2 for a buyer has
// nothing productive to count down (their clock already stopped), so that
// row renders with no timer rather than a fake or misleading one.
function PhaseBanner({ label, detail, countdown, onClick, urgent, testId }) {
  return (
    <div
      onClick={onClick}
      data-testid={testId}
      style={{ ...fieldGlass({ margin: '10px 20px 0', padding: '12px 14px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, cursor: 'pointer' }) }}
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{label}</span>
        <span style={{ fontSize: 12.5, lineHeight: 1.4, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {detail}
        </span>
      </div>
      {countdown && (
        <span style={{ ...display(19, { fontVariantNumeric: 'tabular-nums', flex: 'none', marginLeft: 12, color: urgent ? alert : ink }) }}>
          {countdown}
        </span>
      )}
    </div>
  );
}

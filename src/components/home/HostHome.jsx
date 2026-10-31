// Simple Shell (switch simple_shell, note 66): Home while Hosting is selected. One hero, then the host's to-dos.
//   1. HERO: the next event you host (src/lib/homeHero.js pickHostHero) with seats taken, Check-in and Message guests;
//      none → "Plan your next event" → Create.
//   2. Host Action Center (verifications, refunds, holds; the same builder Dashboard uses).
//   3. Submitted events: pending / needs fixing / live counts → the host dashboard.
//   4. Up to 3 numbers from Reports. Note 69: loaded here when no host report is in hand (they used to appear only
//      after Reports had been opened). Also note 69: an icon shortcut row, a "Coming up" list, one-line plan card, and
//      each Submitted tile is its own button into the dashboard. Twin of iOS HostHomeSections.
// Reuses what Dashboard.jsx already loads (myOrgEventKeys, realEventsById, verifications, refundQueue,
// organizerHoldingSummary, useSubmittedEvents); the only read is get_public_event_fill for the hero's seat count, the
// same public RPC Home's "Saved, coming up" already calls.
import { useEffect, useMemo } from 'react';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { EVENTS, catalogStartMs } from '../../data/events.js';
import { formatVnEventDate } from '../../lib/countdown.js';
import { pickHostHero } from '../../lib/homeHero.js';
import { buildActionCenterItems, sortActionCenterItems } from '../../lib/actionCenter.js';
import { useSubmittedEvents } from '../../lib/submittedEvents.jsx';
import { dashboard as reportDashboard, reportRole } from '../../lib/reportsPresentation.js';
import { supabase } from '../../lib/supabase.js';
import ActionCenter from '../../screens/ActionCenter.jsx';
import { ink, paper, ink2, block, blockInset, divider, display, RADIUS } from '../../theme.js';
import { shortMetricLabel } from '../../lib/reportMetricLabels.js';
import { comingUpEmptyVariant, kpiSectionState, kpiRangeHeading } from '../../lib/hostHomeEmpty.js';
import InlineEmpty from '../ui/InlineEmpty.jsx';

const ENDED_AFTER_MS = 12 * 3600000;

// Note 66 follow-up: every block on paper uses the `block` fill (light #EEE8DA, dark unchanged); anything nested in a
// block uses `blockInset`, so there is no beige-on-beige.
function Card({ children, testId, style, ...rest }) {
  return (
    <section data-testid={testId} style={{ margin: '12px 20px 0', padding: 16, borderRadius: RADIUS.card, background: block, color: ink, ...style }} {...rest}>
      {children}
    </section>
  );
}

// KPI / Submitted tiles: three equal columns, 88 tall, 16 padding, 8 gap; value 20/600, label 13 wrapping (no
// ellipsis, short labels keep it to 2 lines). Twin of iOS SimpleShellHomeViews' tile grid.
const TILE_GRID = { display: 'grid', gridTemplateColumns: 'repeat(3, minmax(0, 1fr))', gap: 8, marginTop: 10 };
const TILE = {
  minWidth: 0, minHeight: 88, padding: 16, boxSizing: 'border-box', borderRadius: 12, background: block,
  display: 'flex', flexDirection: 'column', alignItems: 'flex-start', justifyContent: 'flex-start', gap: 4,
};
const TILE_VALUE = { fontSize: 20, fontWeight: 600, lineHeight: 1.2, fontVariantNumeric: 'tabular-nums', color: ink };
const TILE_LABEL = { fontSize: 13, fontWeight: 400, lineHeight: 1.3, color: ink2, overflowWrap: 'break-word', hyphens: 'auto', maxWidth: '100%' };

function SectionHead({ title }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8, minHeight: 24 }}>
      <h2 style={{ ...display(17), margin: 0 }}>{title}</h2>
      <span aria-hidden="true" style={{ color: ink2, fontSize: 16 }}>›</span>
    </div>
  );
}

const QUICK_PATHS = {
  plus: <path d="M12 5v14M5 12h14" />,
  guests: <><circle cx="9" cy="8" r="3.2" /><path d="M3.5 19c.6-3 2.8-4.6 5.5-4.6s4.9 1.6 5.5 4.6" /><circle cx="17" cy="9" r="2.6" /><path d="M16 14.6c2.3.1 3.9 1.5 4.5 4.4" /></>,
  refund: <><path d="M9 7H5V3" /><path d="M5.3 7A8 8 0 1 1 4 12" /></>,
  camera: <><path d="M4 8.5A1.5 1.5 0 0 1 5.5 7h2l1.5-2h6l1.5 2h2A1.5 1.5 0 0 1 20 8.5v9a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 17.5z" /><circle cx="12" cy="13" r="3.5" /></>,
  bulb: <><path d="M9 18h6M10 21h4" /><path d="M12 3a6 6 0 0 0-3.5 10.9c.6.5 1 1.2 1 2V16h5v-.1c0-.8.4-1.5 1-2A6 6 0 0 0 12 3z" /></>,
  store: <><path d="M4 9.5 5.5 4h13L20 9.5" /><path d="M4 9.5a2.7 2.7 0 0 0 5.3 0 2.7 2.7 0 0 0 5.4 0 2.7 2.7 0 0 0 5.3 0" /><path d="M5.5 12v8h13v-8M10 20v-5h4v5" /></>,
  chart: <path d="M5 20V12M10 20V6M15 20v-9M20 20V9" />,
};
function QuickIcon({ name }) {
  return (
    <svg aria-hidden="true" width={22} height={22} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.1} strokeLinecap="round" strokeLinejoin="round">
      {QUICK_PATHS[name]}
    </svg>
  );
}

const btn = (primary) => ({
  flex: '1 1 0', minHeight: 44, borderRadius: 999, border: 'none', cursor: 'pointer', fontFamily: 'inherit', fontSize: 14, fontWeight: 600,
  background: primary ? ink : blockInset, color: primary ? paper : ink, padding: '0 14px',
});

export default function HostHome() {
  const {
    state: s, set, T, goCreate, goEvent, goDashboard, goInbox, openAttendance, openVerifications, openReports,
    loadRealEventsById, loadVerifications, loadRefundQueue, loadOrganizerHoldingSummary, loadHomeLiveEvents,
    loadHostHomeKpis, openVerificationsRefunds, openStoryLibraryPicker, goSurveysHosting, openOrganizerProfile, shareOrganizerProfile,
  } = useBanBe();

  useEffect(() => {
    if (!s.user?.id) return;
    loadVerifications(); loadRefundQueue(); loadOrganizerHoldingSummary();
  }, [s.user?.id, loadVerifications, loadRefundQueue, loadOrganizerHoldingSummary]);
  useEffect(() => { loadHomeLiveEvents(); }, [loadHomeLiveEvents]);

  const keys = s.myOrgEventKeys || [];
  const missingReal = keys.filter(k => !EVENTS.some(e => e.key === k) && !(k in s.realEventsById));
  useEffect(() => {
    if (missingReal.length) loadRealEventsById(missingReal);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [missingReal.join(','), loadRealEventsById]);

  // The host's own events in the pickHostHero shape, keeping the display fields alongside.
  const mine = useMemo(() => keys.map(k => {
    const cat = EVENTS.find(e => e.key === k);
    if (cat) {
      const live = s.homeLiveEvents[k];
      const startsAt = catalogStartMs(cat, live?.starts_at);
      return { key: k, name: cat.name, startsAt: Number.isFinite(startsAt) ? startsAt : NaN, status: live?.status || (cat.cancelled ? 'cancelled' : 'live'), tz: null, capacity: cat.capacity ?? null };
    }
    const r = s.realEventsById[k];
    if (!r) return null;
    const startsAt = r.startsAt ? Date.parse(r.startsAt) : NaN;
    return { key: k, name: r.name, startsAt, status: r.status, tz: r.tz || null, capacity: r.capacity ?? null, seatsRemaining: r.seatsRemaining };
  }).filter(Boolean), [keys, s.homeLiveEvents, s.realEventsById]); // eslint-disable-line react-hooks/exhaustive-deps
  const now = Date.now();
  // Only events that are actually on (live): a draft or one in review is not "your next event" yet.
  const hero = pickHostHero(mine.filter(e => e.status === 'live' || e.status === 'ended'), now);
  const liveCount = mine.filter(e => e.status === 'live' && Number.isFinite(e.startsAt) && e.startsAt + ENDED_AFTER_MS > now).length;

  const heroFill = hero ? s.eventFill[hero.key] : null;
  useEffect(() => {
    if (!hero || hero.key in s.eventFill) return undefined;
    let alive = true;
    supabase.rpc('get_public_event_fill', { p_event_ids: [hero.key] }).then(({ data, error }) => {
      if (!alive || error || !Array.isArray(data)) return;
      set(prev => ({ eventFill: { ...prev.eventFill, ...Object.fromEntries(data.map(r => [r.event_id, { booked: r.booked, capacity: r.capacity }])) } }));
    }, () => {});
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hero?.key]);
  const capacity = heroFill?.capacity ?? hero?.capacity ?? null;
  const booked = heroFill?.booked ?? (capacity != null && hero?.seatsRemaining != null ? capacity - hero.seatsRemaining : null);

  const actionItems = sortActionCenterItems(buildActionCenterItems({
    role: 'host', T, now: s.now || now,
    verifications: s.verifications || [], refundQueue: s.refundQueue || [], orgHolding: s.organizerHoldingSummary,
    onOpenVerifications: () => openVerifications('home'),
    onOpenRefundCenter: () => openVerifications('home'),
    onOpenDashboard: () => goDashboard('home'),
  }));

  const submitted = useSubmittedEvents(true);

  // Note 69: load the host numbers when nothing host-scoped is in hand (same RPC and range as Reports).
  const hasHostReport = !!s.reportsData && reportRole(s.reportsData.scope || s.reportsScope) === 'host';
  useEffect(() => {
    if (s.myOrganizerId && !hasHostReport && !s.reportsLoading) loadHostHomeKpis(s.myOrganizerId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [s.myOrganizerId]);
  const kpis = useMemo(() => {
    if (!s.reportsData || reportRole(s.reportsData.scope || s.reportsScope) !== 'host') return [];
    const d = reportDashboard(s.reportsData, 'host', T);
    return [d.primary, ...d.overview].filter(Boolean).slice(0, 3);
  }, [s.reportsData, s.reportsScope, T]);

  // Note 69: what "start from your last event" copies, and the next few events after the hero.
  const last = mine.filter(e => e.status !== 'cancelled' && Number.isFinite(e.startsAt) && e.startsAt < now)
    .sort((a, b) => b.startsAt - a.startsAt)[0] || null;
  const upcoming = mine.filter(e => e.status === 'live' && Number.isFinite(e.startsAt) && e.startsAt > now && e.key !== hero?.key)
    .sort((a, b) => a.startsAt - b.startsAt).slice(0, 3);
  const upcomingKeys = upcoming.map(e => e.key).filter(k => !(k in s.eventFill)).join(',');
  useEffect(() => {
    if (!upcomingKeys) return undefined;
    let alive = true;
    supabase.rpc('get_public_event_fill', { p_event_ids: upcomingKeys.split(',') }).then(({ data, error }) => {
      if (!alive || error || !Array.isArray(data)) return;
      set(prev => ({ eventFill: { ...prev.eventFill, ...Object.fromEntries(data.map(r => [r.event_id, { booked: r.booked, capacity: r.capacity }])) } }));
    }, () => {});
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [upcomingKeys]);
  // Calm Pass: "Coming up" never vanishes into blank space; src/lib/hostHomeEmpty.js picks what is true (null = the
  // list, or the hero, already says it). The numbers section likewise shows loading / error / empty states.
  const comingUpEmpty = comingUpEmptyVariant({
    upcoming: upcoming.length, hasHero: !!hero, pending: submitted.pending.length, needsFix: submitted.needsFix.length,
  });
  const openSubmitted = () => { set({ dashboardOpenSubmitted: true }); goDashboard('home'); };
  const kpiState = kpiSectionState({
    hasOrganizer: !!s.myOrganizerId, loading: !!s.reportsLoading, error: !!s.reportsError, tiles: kpis.length, hasReport: hasHostReport,
  });
  const openHostReports = () => openReports('host', s.myOrganizerId, 'home');

  // Create joins the shortcuts only when a hero event shows (the plan card has its own Create button); the hero has
  // its own Check-in and Message buttons.
  const quick = [
    ...(hero ? [{ id: 'create', short: T('Tạo', 'Create'), title: T('Tạo sự kiện', 'Create event'), icon: 'plus', run: goCreate }] : []),
    { id: 'guests', short: T('Khách', 'Guests'), title: T('Khách & thanh toán', 'Guests & payments'), icon: 'guests', run: () => openVerifications('home') },
    { id: 'refunds', short: T('Hoàn tiền', 'Refunds'), title: T('Hoàn tiền', 'Refunds'), icon: 'refund', run: () => openVerificationsRefunds('home') },
    { id: 'story', short: 'Story', title: T('Đăng story', 'Post a story'), icon: 'camera', run: openStoryLibraryPicker },
    { id: 'surveys', short: T('Khảo sát', 'Surveys'), title: T('Khảo sát & ý tưởng', 'Surveys & ideas'), icon: 'bulb', run: goSurveysHosting },
    ...(s.myOrganizerId ? [
      { id: 'profile', short: T('Hồ sơ', 'Profile'), title: T('Hồ sơ tổ chức', 'Host profile'), icon: 'store', run: () => openOrganizerProfile(s.myOrganizerId, 'home') },
      { id: 'reports', short: T('Báo cáo', 'Reports'), title: T('Báo cáo', 'Reports'), icon: 'chart', run: () => openReports('host', s.myOrganizerId, 'home') },
    ] : []),
  ];

  const when = hero && Number.isFinite(hero.startsAt) ? (() => {
    const { weekdayShort, dayMonth, time } = formatVnEventDate(new Date(hero.startsAt), hero.tz);
    return `${weekdayShort}, ${dayMonth} · ${time}`;
  })() : '';

  return (
    <div data-testid="home-host">
      {hero ? (
        <Card testId="home-host-hero" aria-labelledby="home-host-hero-title">
          <div style={{ fontSize: 13, color: ink2, fontWeight: 600 }}>{T('Sự kiện tiếp theo của bạn', 'Your next event')}</div>
          <h2 id="home-host-hero-title" onClick={() => goEvent(hero.key)} style={{ ...display(20), margin: '4px 0 0', cursor: 'pointer', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{hero.name}</h2>
          <div style={{ fontSize: 13, color: ink2, marginTop: 4, display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {when && <span>{when}</span>}
            {booked != null && capacity != null && (
              <span data-testid="home-host-hero-seats">{T(`${booked}/${capacity} chỗ đã đặt`, `${booked}/${capacity} seats taken`)}</span>
            )}
          </div>
          {booked != null && capacity > 0 && (
            <div aria-hidden="true" style={{ marginTop: 10, height: 6, borderRadius: 3, background: blockInset, overflow: 'hidden' }}>
              <div style={{ width: `${Math.min(100, Math.round((booked / capacity) * 100))}%`, height: '100%', background: ink, borderRadius: 3 }} />
            </div>
          )}
          <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
            <button type="button" className="bb-press" onClick={() => openAttendance(hero.key, 'home')} data-testid="home-host-checkin" style={btn(true)}>
              {T('Điểm danh', 'Check-in')}
            </button>
            <button type="button" className="bb-press" onClick={goInbox} data-testid="home-host-message" style={btn(false)}>
              {T('Nhắn khách', 'Message guests')}
            </button>
          </div>
        </Card>
      ) : (
        <Card testId="home-host-plan">
          <h2 style={{ ...display(20), margin: 0 }}>{T('Lên kế hoạch cho sự kiện tiếp theo', 'Plan your next event')}</h2>
          {/* Note 69: one short line; names the event that will be copied when there is one. */}
          <p data-testid={last ? 'home-host-plan-last' : undefined} style={{ fontSize: 13.5, color: ink2, margin: '6px 0 14px', lineHeight: 1.45, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {last ? T(`Sao chép "${last.name}" · khoảng 5 phút`, `Copy "${last.name}" · about 5 min`) : T('Khoảng 5 phút', 'About 5 minutes')}
          </p>
          <button type="button" className="bb-press" onClick={goCreate} data-testid="home-host-plan-create" style={{ ...btn(true), width: '100%' }}>
            ＋ {T('Tạo sự kiện', 'Create event')}
          </button>
        </Card>
      )}

      {/* Note 69: icon shortcuts. The row scrolls by itself: data-hscroll keeps a drag here from switching tabs. */}
      <div data-hscroll data-testid="home-host-quick" role="group" aria-label={T('Lối tắt tổ chức', 'Hosting shortcuts')}
        style={{ display: 'flex', gap: 12, overflowX: 'auto', overscrollBehaviorX: 'contain', padding: '16px 20px 2px', scrollbarWidth: 'none' }}>
        {quick.map(a => (
          <button key={a.id} type="button" className="bb-press" onClick={a.run} data-testid={`home-host-quick-${a.id}`} aria-label={a.title}
            style={{ flex: 'none', width: 64, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, padding: 0, border: 'none', background: 'none', color: ink, cursor: 'pointer', fontFamily: 'inherit' }}>
            <span aria-hidden="true" style={{ width: 56, height: 56, borderRadius: 18, background: block, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <QuickIcon name={a.icon} />
            </span>
            <span aria-hidden="true" style={{ fontSize: 12, fontWeight: 600, color: ink2, whiteSpace: 'nowrap', maxWidth: 64, overflow: 'hidden', textOverflow: 'ellipsis' }}>{a.short}</span>
          </button>
        ))}
      </div>

      <div style={{ marginTop: 4 }}>
        <ActionCenter items={actionItems} onSeeAll={() => goDashboard('home')} T={T} />
      </div>

      {comingUpEmpty && (
        <section data-testid="home-host-upcoming" style={{ margin: '16px 20px 0', color: ink }}>
          <h2 style={{ ...display(17), margin: '0 0 10px' }}>{T('Sắp tới', 'Coming up')}</h2>
          {comingUpEmpty === 'needsFix' && (
            <InlineEmpty testId="home-host-upcoming-empty-needsFix" actionTestId="home-host-upcoming-empty-action"
              title={submitted.needsFix.length === 1 ? T('Có 1 sự kiện cần sửa', '1 event needs a fix')
                : T(`Có ${submitted.needsFix.length} sự kiện cần sửa`, `${submitted.needsFix.length} events need a fix`)}
              message={T('Sửa và gửi lại để duyệt. Sự kiện sẽ hiện ở đây khi được mở.', "Fix it and send it back for review. It shows here once it's live.")}
              actionLabel={T('Sửa ngay', 'Fix now')} onAction={openSubmitted} />
          )}
          {comingUpEmpty === 'pending' && (
            <InlineEmpty testId="home-host-upcoming-empty-pending" actionTestId="home-host-upcoming-empty-action"
              title={submitted.pending.length === 1 ? T('1 sự kiện đang chờ duyệt', '1 event is in review')
                : T(`${submitted.pending.length} sự kiện đang chờ duyệt`, `${submitted.pending.length} events are in review`)}
              message={T('banbe đang xem xét. Sự kiện sẽ hiện ở đây khi được mở.', "banbe is checking them. They show here once they're live.")}
              actionLabel={T('Xem sự kiện đã gửi', 'See submitted')} onAction={openSubmitted} />
          )}
          {comingUpEmpty === 'quiet' && (
            // The plan card above already offers Create, so this offers the other useful step.
            <InlineEmpty testId="home-host-upcoming-empty-quiet" actionTestId="home-host-upcoming-empty-action"
              title={T('Chưa có lịch sắp tới', 'Nothing scheduled yet')}
              message={T('Chia sẻ trang tổ chức để khách theo dõi bạn trước sự kiện tiếp theo.', 'Share your host page so guests can follow you before your next event.')}
              actionLabel={s.myOrganizerId ? T('Chia sẻ trang tổ chức', 'Share host page') : null}
              onAction={s.myOrganizerId ? () => shareOrganizerProfile(s.myOrganizerId, s.orgRegName) : null} />
          )}
        </section>
      )}

      {!comingUpEmpty && upcoming.length > 0 && (
        <section data-testid="home-host-upcoming" style={{ margin: '16px 20px 0', color: ink }}>
          <h2 style={{ ...display(17), margin: 0 }}>{T('Sắp tới', 'Coming up')}</h2>
          <div style={{ marginTop: 10, borderRadius: 14, background: block, overflow: 'hidden' }}>
            {upcoming.map((e, i) => {
              const fill = s.eventFill[e.key];
              const { weekdayShort, dayMonth, time } = formatVnEventDate(new Date(e.startsAt), e.tz);
              return (
                <button key={e.key} type="button" onClick={() => goEvent(e.key)} data-testid={`home-host-upcoming-${e.key}`}
                  style={{ width: '100%', minHeight: 56, display: 'flex', alignItems: 'center', gap: 12, padding: '10px 14px', border: 'none', borderTop: i ? `1px solid ${divider}` : 'none', background: 'none', color: ink, textAlign: 'left', cursor: 'pointer', fontFamily: 'inherit' }}>
                  <span style={{ flex: 1, minWidth: 0 }}>
                    <span style={{ display: 'block', fontSize: 14.5, fontWeight: 600, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{e.name}</span>
                    <span style={{ display: 'block', fontSize: 12.5, color: ink2 }}>{`${weekdayShort}, ${dayMonth} · ${time}`}</span>
                  </span>
                  {fill && fill.capacity > 0 && (
                    <span style={{ fontSize: 12.5, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}
                      aria-label={T(`${fill.booked} trên ${fill.capacity} chỗ đã đặt`, `${fill.booked} of ${fill.capacity} seats taken`)}>{fill.booked}/{fill.capacity}</span>
                  )}
                  <span aria-hidden="true" style={{ color: ink2 }}>›</span>
                </button>
              );
            })}
          </div>
        </section>
      )}

      {/* Submitted events and Reports: a heading row, then equal block tiles straight on paper (no wrapping card). */}
      {/* Note 69: the heading opens the dashboard; each tile is its own button (Pending / Needs fixing open it with
          Submitted events expanded). */}
      <section data-testid="home-host-submitted" style={{ margin: '16px 20px 0', color: ink }}>
        <button type="button" onClick={() => goDashboard('home')} data-testid="home-host-submitted-open"
          style={{ display: 'block', width: '100%', padding: 0, border: 'none', background: 'none', color: ink, textAlign: 'left', cursor: 'pointer', fontFamily: 'inherit', minHeight: 44 }}>
          <SectionHead title={T('Sự kiện đã gửi', 'Submitted events')} />
        </button>
        <div style={TILE_GRID}>
          {[
            ['pending', submitted.pending.length, T('Đang chờ duyệt', 'Pending')],
            ['fix', submitted.needsFix.length, T('Cần sửa', 'Needs fixing')],
            ['live', liveCount, T('Đang mở', 'Live')],
          ].map(([k, n, label]) => (
            <button key={k} type="button" data-testid={`home-host-submitted-${k}`} className="bb-press"
              aria-label={`${label}: ${n}`}
              onClick={() => { set({ dashboardOpenSubmitted: k !== 'live' }); goDashboard('home'); }}
              style={{ ...TILE, border: 'none', cursor: 'pointer', fontFamily: 'inherit', textAlign: 'left' }}>
              <div style={TILE_VALUE}>{n}</div>
              <div style={TILE_LABEL}>{label}</div>
            </button>
          ))}
        </div>
      </section>

      {kpiState !== 'hidden' && (
        <section data-testid="home-host-kpis" style={{ margin: '16px 20px 0', color: ink }}>
          {/* The heading names the range Reports used (it said "Reports"; iOS said "This month" for the last 30 days). */}
          <button type="button" onClick={openHostReports} data-testid="home-host-reports"
            style={{ display: 'block', width: '100%', padding: 0, border: 'none', background: 'none', color: ink, textAlign: 'left', cursor: 'pointer', fontFamily: 'inherit', minHeight: 44 }}>
            <SectionHead title={kpiRangeHeading(s.reportsRangeDays, T)} />
          </button>
          {kpiState === 'tiles' && (
            <div style={TILE_GRID} role="button" tabIndex={0} onClick={openHostReports}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openHostReports(); } }}>
              {kpis.map(m => {
                // Short tile label (reportMetricLabels.js); the full label stays in Reports and in the accessible name.
                const short = shortMetricLabel(m.key, T) || m.title;
                return (
                  <div key={m.key} data-testid={`home-host-kpi-${m.key}`} style={{ ...TILE, cursor: 'pointer' }} aria-label={`${short}: ${m.accessibilityValue}`}>
                    <div style={{ ...TILE_VALUE, overflowWrap: 'anywhere' }}>{m.valueText}</div>
                    <div data-testid={`home-host-kpi-${m.key}-label`} style={TILE_LABEL}>{short}</div>
                  </div>
                );
              })}
            </div>
          )}
          {kpiState === 'loading' && (
            <div data-testid="home-host-kpis-loading" style={TILE_GRID} role="status" aria-label={T('Đang tải số liệu', 'Loading numbers')}>
              {[0, 1, 2].map(i => (
                <div key={i} aria-hidden="true" style={TILE}>
                  <div style={{ width: 28, height: 20, borderRadius: 6, background: blockInset }} />
                  <div style={{ width: '70%', height: 12, borderRadius: 6, background: blockInset, marginTop: 4 }} />
                </div>
              ))}
            </div>
          )}
          {kpiState === 'error' && (
            <InlineEmpty testId="home-host-kpis-error" actionTestId="home-host-kpis-retry"
              title={T('Chưa tải được số liệu', "Couldn't load your numbers")}
              message={T('Kiểm tra kết nối rồi thử lại.', 'Check your connection and try again.')}
              actionLabel={T('Thử lại', 'Retry')} actionIcon="↻" onAction={() => loadHostHomeKpis(s.myOrganizerId)} />
          )}
          {kpiState === 'empty' && (
            <InlineEmpty testId="home-host-kpis-empty"
              title={T('Chưa có lượt đặt chỗ', 'No bookings in this period')}
              message={T('Số liệu sẽ hiện ở đây khi khách bắt đầu đặt chỗ.', 'Your numbers show here once guests start booking.')} />
          )}
        </section>
      )}
      <div aria-hidden="true" style={{ height: 1, margin: '20px 20px 0', background: divider }} />
    </div>
  );
}

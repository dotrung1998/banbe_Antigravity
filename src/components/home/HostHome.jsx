// Simple Shell (switch simple_shell, note 66): Home while Hosting is selected. One hero, then the host's to-dos.
//   1. HERO: the next event you host (src/lib/homeHero.js pickHostHero) with seats taken, Check-in and Message guests;
//      none → "Plan your next event" → Create.
//   2. Host Action Center (verifications, refunds, holds; the same builder Dashboard uses).
//   3. Submitted events: pending / needs fixing / live counts → the host dashboard.
//   4. Up to 3 numbers from Reports, only when that report is already loaded (no fetch from here).
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

const btn = (primary) => ({
  flex: '1 1 0', minHeight: 44, borderRadius: 999, border: 'none', cursor: 'pointer', fontFamily: 'inherit', fontSize: 14, fontWeight: 600,
  background: primary ? ink : blockInset, color: primary ? paper : ink, padding: '0 14px',
});

export default function HostHome() {
  const {
    state: s, set, T, goCreate, goEvent, goDashboard, goInbox, openAttendance, openVerifications, openReports,
    loadRealEventsById, loadVerifications, loadRefundQueue, loadOrganizerHoldingSummary, loadHomeLiveEvents,
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

  // Reports: only a host report that is already loaded (Account › Reports fetched it); never fetched from Home.
  const kpis = useMemo(() => {
    if (!s.reportsData || reportRole(s.reportsData.scope || s.reportsScope) !== 'host') return [];
    const d = reportDashboard(s.reportsData, 'host', T);
    return [d.primary, ...d.overview].filter(Boolean).slice(0, 3);
  }, [s.reportsData, s.reportsScope, T]);

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
          <p style={{ fontSize: 13.5, color: ink2, margin: '6px 0 14px', lineHeight: 1.45 }}>
            {T('Tạo sự kiện trong 5 bước. Bạn có thể lưu nháp và quay lại sau.', 'Create an event in 5 steps. You can save a draft and come back later.')}
          </p>
          <button type="button" className="bb-press" onClick={goCreate} data-testid="home-host-plan-create" style={{ ...btn(true), width: '100%' }}>
            ＋ {T('Tạo sự kiện', 'Create event')}
          </button>
        </Card>
      )}

      <div style={{ marginTop: 4 }}>
        <ActionCenter items={actionItems} onSeeAll={() => goDashboard('home')} T={T} />
      </div>

      {/* Submitted events and Reports: a heading row, then equal block tiles straight on paper (no wrapping card). */}
      <section data-testid="home-host-submitted" role="button" tabIndex={0} onClick={() => goDashboard('home')}
        aria-label={T(`Sự kiện đã gửi: ${submitted.pending.length} đang chờ duyệt, ${submitted.needsFix.length} cần sửa, ${liveCount} đang mở`,
          `Submitted events: ${submitted.pending.length} pending, ${submitted.needsFix.length} needs fixing, ${liveCount} live`)}
        onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); goDashboard('home'); } }}
        style={{ margin: '16px 20px 0', cursor: 'pointer', color: ink }}>
        <SectionHead title={T('Sự kiện đã gửi', 'Submitted events')} />
        <div style={TILE_GRID}>
          {[
            ['pending', submitted.pending.length, T('Đang chờ duyệt', 'Pending')],
            ['fix', submitted.needsFix.length, T('Cần sửa', 'Needs fixing')],
            ['live', liveCount, T('Đang mở', 'Live')],
          ].map(([k, n, label]) => (
            <div key={k} data-testid={`home-host-submitted-${k}`} style={TILE}>
              <div style={TILE_VALUE}>{n}</div>
              <div style={TILE_LABEL}>{label}</div>
            </div>
          ))}
        </div>
      </section>

      {kpis.length > 0 && (
        <section data-testid="home-host-kpis" role="button" tabIndex={0} onClick={() => openReports('host', s.myOrganizerId, 'home')}
          onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openReports('host', s.myOrganizerId, 'home'); } }}
          style={{ margin: '16px 20px 0', cursor: 'pointer', color: ink }}>
          <SectionHead title={T('Số liệu', 'Reports')} />
          <div style={TILE_GRID}>
            {kpis.map(m => {
              // Short tile label (reportMetricLabels.js); the full label stays in Reports and in the accessible name.
              const short = shortMetricLabel(m.key, T) || m.title;
              return (
                <div key={m.key} data-testid={`home-host-kpi-${m.key}`} style={TILE} aria-label={`${short}: ${m.accessibilityValue}`}>
                  <div style={{ ...TILE_VALUE, overflowWrap: 'anywhere' }}>{m.valueText}</div>
                  <div data-testid={`home-host-kpi-${m.key}-label`} style={TILE_LABEL}>{short}</div>
                </div>
              );
            })}
          </div>
        </section>
      )}
      <div aria-hidden="true" style={{ height: 1, margin: '20px 20px 0', background: divider }} />
    </div>
  );
}

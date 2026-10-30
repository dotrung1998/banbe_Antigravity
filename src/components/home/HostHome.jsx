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
import { ink, paper, ink2, surface1, surface2, divider, display, RADIUS } from '../../theme.js';

const ENDED_AFTER_MS = 12 * 3600000;

function Card({ children, testId, style, ...rest }) {
  return (
    <section data-testid={testId} style={{ margin: '12px 20px 0', padding: 16, borderRadius: RADIUS.card, background: surface1, color: ink, ...style }} {...rest}>
      {children}
    </section>
  );
}

const btn = (primary) => ({
  flex: '1 1 0', minHeight: 44, borderRadius: 999, border: 'none', cursor: 'pointer', fontFamily: 'inherit', fontSize: 14, fontWeight: 600,
  background: primary ? ink : surface2, color: primary ? paper : ink, padding: '0 14px',
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
            <div aria-hidden="true" style={{ marginTop: 10, height: 6, borderRadius: 3, background: surface2, overflow: 'hidden' }}>
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

      <Card testId="home-host-submitted" role="button" tabIndex={0} onClick={() => goDashboard('home')}
        onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); goDashboard('home'); } }}
        style={{ cursor: 'pointer' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
          <h2 style={{ ...display(17), margin: 0 }}>{T('Sự kiện đã gửi', 'Submitted events')}</h2>
          <span aria-hidden="true" style={{ color: ink2, fontSize: 16 }}>›</span>
        </div>
        <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
          {[
            ['pending', submitted.pending.length, T('Đang chờ duyệt', 'Pending')],
            ['fix', submitted.needsFix.length, T('Cần sửa', 'Needs fixing')],
            ['live', liveCount, T('Đang mở', 'Live')],
          ].map(([k, n, label]) => (
            <div key={k} data-testid={`home-host-submitted-${k}`} style={{ flex: '1 1 0', padding: '10px 12px', borderRadius: 12, background: surface2 }}>
              <div style={{ ...display(20), fontVariantNumeric: 'tabular-nums' }}>{n}</div>
              <div style={{ fontSize: 12.5, color: ink2 }}>{label}</div>
            </div>
          ))}
        </div>
      </Card>

      {kpis.length > 0 && (
        <Card testId="home-host-kpis" role="button" tabIndex={0} onClick={() => openReports('host', s.myOrganizerId, 'home')}
          onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openReports('host', s.myOrganizerId, 'home'); } }}
          style={{ cursor: 'pointer' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
            <h2 style={{ ...display(17), margin: 0 }}>{T('Số liệu', 'Reports')}</h2>
            <span aria-hidden="true" style={{ color: ink2, fontSize: 16 }}>›</span>
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
            {kpis.map(m => (
              <div key={m.key} style={{ flex: '1 1 0', minWidth: 0, padding: '10px 12px', borderRadius: 12, background: surface2 }}
                aria-label={`${m.title}: ${m.accessibilityValue}`}>
                <div style={{ ...display(20), fontVariantNumeric: 'tabular-nums', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{m.valueText}</div>
                <div style={{ fontSize: 12.5, color: ink2, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{m.title}</div>
              </div>
            ))}
          </div>
        </Card>
      )}
      <div aria-hidden="true" style={{ height: 1, margin: '20px 20px 0', background: divider }} />
    </div>
  );
}

// banbe Schedule — web port of iOS ScheduleView (notes 44/45). A dock screen: My schedule (booked / awaiting /
// holding / hosting / added by you) and Discover (upcoming public events), a week strip (swipe or arrows to change
// week), a month view, and per-event "Add to banbe Schedule" + "Add to calendar" (.ics download / Google).
// All rules live in lib/schedulePresentation.js (unit-tested). Manual adds are kept in this browser only.

import { useEffect, useMemo, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, display } from '../theme.js';
import * as SP from '../lib/schedulePresentation.js';
import { calendarDraft, downloadIcs, googleCalendarUrl } from '../lib/calendarExport.js';
import { track } from '../lib/analytics.js';
import EmptyState from '../components/ui/EmptyState.jsx';

const muted = (a) => `rgba(var(--bb-fg-rgb), ${a})`;
const segBtn = (selected) => ({
  border: 'none', fontFamily: 'inherit', fontSize: 13, fontWeight: 600, padding: '9px 16px', minHeight: 38, borderRadius: 999,
  cursor: 'pointer', flex: 1, background: selected ? ink : 'transparent', color: selected ? paper : ink,
});
const linkBtn = { border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 13, fontWeight: 600, cursor: 'pointer', padding: '8px 0', minHeight: 36 };

/** "Add to calendar" for one event: .ics (Apple Calendar, Outlook, any app) or Google. Honest about no end time. */
export function CalendarExportButtons({ info, T, compact = false }) {
  const [msg, setMsg] = useState('');
  const draft = info ? calendarDraft({ title: info.title, start: info.start, end: info.end, location: info.location, eventKey: info.key, origin: window.location.origin }, T) : null;
  const flash = (m) => { setMsg(m); setTimeout(() => setMsg(''), 6000); };
  const ics = () => {
    track('system_calendar_editor_opened');
    if (!draft) { flash(T('Sự kiện này chưa có giờ bắt đầu nên chưa thêm vào lịch được.', "This event has no start time yet, so it can't be added to a calendar.")); return; }
    downloadIcs(draft, `banbe-${info.key}.ics`, { uid: info.key });
    flash(T('Đã tải file lịch (.ics). Mở file để thêm vào ứng dụng lịch của bạn.', 'Calendar file (.ics) downloaded. Open it to add the event to your calendar app.'));
  };
  const google = () => {
    if (!draft) { flash(T('Sự kiện này chưa có giờ bắt đầu nên chưa thêm vào lịch được.', "This event has no start time yet, so it can't be added to a calendar.")); return; }
    window.open(googleCalendarUrl(draft), '_blank', 'noopener');
  };
  return (
    <div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: compact ? 12 : 16 }}>
        <button type="button" onClick={ics} data-testid={`calendar-ics-${info?.key}`} style={linkBtn}>📅 {T('Thêm vào lịch (.ics)', 'Add to calendar (.ics)')}</button>
        <button type="button" onClick={google} data-testid={`calendar-google-${info?.key}`} style={linkBtn}>{T('Google Lịch', 'Google Calendar')} ↗</button>
      </div>
      {msg && <p role="status" style={{ fontSize: 12, color: muted(0.75), margin: '2px 0 0' }}>{msg}</p>}
    </div>
  );
}

function MonthSheet({ events, selected, firstDay, vi, T, onPick, onClose, mode, onMode }) {
  const [month, setMonth] = useState(() => SP.monthStart(selected));
  const grid = useMemo(() => SP.monthGrid(month, firstDay), [month, firstDay]);
  const counts = useMemo(() => SP.dayCounts(events, grid), [events, grid]);
  const agenda = useMemo(() => SP.monthAgenda(events, month, firstDay), [events, month, firstDay]);
  const selWeek = new Set(SP.week(selected, firstDay).map(d => d.getTime()));
  const today = SP.startOfDay(new Date()).getTime();
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div role="dialog" aria-modal="true" aria-label={SP.monthTitle(month, vi)} data-testid="schedule-month" onClick={onClose}
      style={{ position: 'fixed', inset: 0, zIndex: 2100, background: 'rgba(0,0,0,0.32)', display: 'flex', alignItems: 'flex-end', justifyContent: 'center' }}>
      <div onClick={e => e.stopPropagation()} style={{ width: '100%', maxWidth: 520, maxHeight: '90vh', overflowY: 'auto', background: paper, color: ink, borderRadius: '24px 24px 0 0', padding: '16px 18px 28px', boxSizing: 'border-box' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <button type="button" aria-label={T('Tháng trước', 'Previous month')} onClick={() => setMonth(m => SP.addMonths(m, -1))} style={{ ...linkBtn, width: 44, fontSize: 20 }}>‹</button>
          <h2 style={display(19, { flex: 1, margin: 0, textAlign: 'center' })}>{SP.monthTitle(month, vi)}</h2>
          <button type="button" aria-label={T('Tháng sau', 'Next month')} onClick={() => setMonth(m => SP.addMonths(m, 1))} style={{ ...linkBtn, width: 44, fontSize: 20 }}>›</button>
          <button type="button" aria-label={T('Đóng', 'Close')} data-testid="schedule-month-close" onClick={onClose}
            style={{ border: 'none', width: 36, height: 36, borderRadius: '50%', background: muted(0.08), color: ink, cursor: 'pointer' }}>✕</button>
        </div>
        <div style={{ display: 'flex', gap: 4, padding: 4, borderRadius: 999, background: 'var(--bb-field)', margin: '12px 0' }}>
          <button type="button" style={segBtn(mode === 'mine')} aria-pressed={mode === 'mine'} onClick={() => onMode('mine')}>{T('Lịch của tôi', 'My schedule')}</button>
          <button type="button" style={segBtn(mode === 'discover')} aria-pressed={mode === 'discover'} onClick={() => onMode('discover')}>{T('Khám phá', 'Discover')}</button>
        </div>
        <div role="grid" style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 2 }}>
          {grid[0].map(d => <div key={`h${d.date.getDay()}`} role="columnheader" style={{ textAlign: 'center', fontSize: 11.5, fontWeight: 600, color: muted(0.7), padding: '4px 0' }}>{SP.weekdayLetter(d.date, vi)}</div>)}
          {grid.flat().map(d => {
            const t = d.date.getTime();
            const n = counts.get(t) || 0;
            const isSel = SP.sameDay(d.date, selected);
            return (
              <button key={t} type="button" role="gridcell" aria-selected={isSel} onClick={() => onPick(d.date)}
                aria-label={`${SP.dayTitle(d.date, vi)}${n ? `, ${n} ${T('sự kiện', n === 1 ? 'event' : 'events')}` : ''}`}
                style={{
                  border: 'none', fontFamily: 'inherit', cursor: 'pointer', minHeight: 48, borderRadius: 10, padding: '6px 0',
                  background: isSel ? ink : selWeek.has(t) ? muted(0.06) : 'transparent', color: isSel ? paper : ink,
                  opacity: d.inMonth ? 1 : 0.4, fontWeight: t === today ? 700 : 400,
                }}>
                <div style={{ fontSize: 14 }}>{d.date.getDate()}</div>
                <div aria-hidden style={{ display: 'flex', gap: 2, justifyContent: 'center', height: 5, marginTop: 3 }}>
                  {Array.from({ length: Math.min(n, 3) }).map((_, i) => <span key={i} style={{ width: 4, height: 4, borderRadius: 2, background: isSel ? paper : ink }} />)}
                </div>
              </button>
            );
          })}
        </div>
        <div style={{ marginTop: 18 }}>
          {agenda.length === 0 && <p style={{ fontSize: 13, color: muted(0.7) }}>{T('Không có sự kiện nào trong tháng này.', 'Nothing this month.')}</p>}
          {agenda.map(g => (
            <div key={g.day.getTime()} style={{ marginTop: 12 }}>
              <div style={{ fontSize: 12.5, fontWeight: 600, color: muted(0.7) }}>{SP.dayTitle(g.day, vi)}</div>
              {g.events.map(e => (
                <button key={e.key} type="button" onClick={() => onPick(g.day)}
                  style={{ display: 'flex', gap: 10, width: '100%', textAlign: 'left', border: 'none', background: 'none', color: ink, fontFamily: 'inherit', padding: '8px 0', cursor: 'pointer', fontSize: 14 }}>
                  <span style={{ width: 64, fontVariantNumeric: 'tabular-nums', color: muted(0.7) }}>{SP.timeText(e.start, vi)}</span>
                  <span style={{ flex: 1 }}>{e.title}</span>
                </button>
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

export default function Schedule() {
  const {
    state: s, T, scheduleSnapshot, goEvent, addToBanbeSchedule, removeFromBanbeSchedule,
    loadPaymentBookings, loadDiscoveryEvents, loadRealEventsById, goMapExplore,
  } = useBanBe();
  const vi = s.lang !== 'en';
  const firstDay = SP.firstWeekday(s.lang);
  const [mode, setMode] = useState('mine');
  const [selected, setSelected] = useState(() => SP.startOfDay(new Date()));
  const [monthOpen, setMonthOpen] = useState(false);
  // Note 48 (iOS parity): the week strip unfolds into the whole month in place (swipe down / grabber).
  const [monthExpanded, setMonthExpanded] = useState(false);
  const [slideDir, setSlideDir] = useState(null); // 'r' | 'l' — which side the next day slides in from
  const [notice, setNotice] = useState('');
  const { mine, discover, missingKeys } = scheduleSnapshot;
  const weekDays = useMemo(() => SP.week(selected, firstDay), [selected, firstDay]);
  const today = SP.startOfDay(new Date());

  // Load once on open (throttled per session like iOS); events the schedule references but hasn't loaded come next.
  const loadedAt = useRef(0);
  useEffect(() => {
    if (Date.now() - loadedAt.current < 45000) return;
    loadedAt.current = Date.now();
    if (s.user?.id) loadPaymentBookings?.();
    if (!(s.discoveryEvents || []).length) loadDiscoveryEvents?.();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  useEffect(() => { if (missingKeys.length) loadRealEventsById?.(missingKeys); }, [missingKeys.join('|')]); // eslint-disable-line react-hooks/exhaustive-deps

  const grid = useMemo(() => SP.monthGrid(selected, firstDay), [selected, firstDay]);
  const stripDays = useMemo(() => (monthExpanded ? grid.flat().map(d => d.date) : weekDays), [monthExpanded, grid, weekDays]);
  const busyMine = useMemo(() => SP.busyDays(stripDays, mine.items), [stripDays, mine.items]);
  const busyDiscover = useMemo(() => SP.busyDays(stripDays, discover.map(e => ({ event: e }))), [stripDays, discover]);
  const busy = mode === 'mine' ? busyMine : busyDiscover;

  const pickDay = (d) => {
    const day = SP.startOfDay(d);
    setSlideDir(day.getTime() >= selected.getTime() ? 'r' : 'l');
    setSelected(day);
    track('schedule_day_selected', { bucket: SP.dayBucket(d) });
  };
  const stepWeek = (n) => { setSlideDir(n > 0 ? 'r' : 'l'); setSelected(d => SP.addDays(d, n)); };
  const stepMonth = (n) => {
    setSlideDir(n > 0 ? 'r' : 'l');
    setSelected(d => {
      const last = new Date(d.getFullYear(), d.getMonth() + n + 1, 0).getDate();
      return new Date(d.getFullYear(), d.getMonth() + n, Math.min(d.getDate(), last));
    });
  };
  const switchMode = (m) => {
    setMode(m);
    track('schedule_mode_selected', { mode: m });
    window.dispatchEvent(new Event('bb:section-change')); // dock back to full size (App.jsx)
  };

  // Gestures (note 48, iOS parity). The whole screen is `data-hscroll`, so a horizontal swipe here never hops to
  // another dock section. Week strip: left/right = week (month when expanded), down/up = open/close the month.
  // Below it: left/right = previous/next day. A swipe never also "clicks" the day/event under the finger.
  const swipe = useRef(null);
  const swallowClick = useRef(false);
  const onSwipeDown = (zone) => (e) => { swipe.current = { zone, x: e.clientX, y: e.clientY }; swallowClick.current = false; };
  const onSwipeMove = (e) => {
    const st = swipe.current; if (!st) return;
    const dx = Math.abs(e.clientX - st.x), dy = Math.abs(e.clientY - st.y);
    if (st.zone === 'strip' ? Math.max(dx, dy) > 12 : dx > 14 && dx > dy) swallowClick.current = true;
  };
  const onSwipeUp = (e) => {
    const st = swipe.current; swipe.current = null;
    if (!st) return;
    const dx = e.clientX - st.x, dy = e.clientY - st.y;
    const horizontal = Math.abs(dx) >= 50 && Math.abs(dx) > Math.abs(dy) * 1.4;
    const vertical = Math.abs(dy) >= 36 && Math.abs(dy) > Math.abs(dx) * 1.4;
    if (st.zone === 'strip') {
      if (horizontal) (monthExpanded ? stepMonth(dx < 0 ? 1 : -1) : stepWeek(dx < 0 ? 7 : -7));
      else if (vertical) setMonthExpanded(dy > 0);
    } else if (horizontal) {
      stepWeek(dx < 0 ? 1 : -1);
    }
  };
  const onSwipeCancel = () => { swipe.current = null; };
  const onClickCaptureGuard = (e) => {
    if (swallowClick.current) { e.stopPropagation(); e.preventDefault(); swallowClick.current = false; }
  };

  const add = (key) => {
    const r = addToBanbeSchedule(key);
    setNotice(r === 'added' ? T('Đã thêm vào lịch banbe trên trình duyệt này.', 'Added to your banbe Schedule in this browser.')
      : r === 'alreadyThere' ? T('Đã có trong lịch của bạn.', 'Already in your schedule.')
        : r === 'ineligible' ? T('Sự kiện này không thêm vào lịch được.', "This event can't be added.") : '');
    setTimeout(() => setNotice(''), 5000);
  };

  const dayItems = SP.itemsOn(mine.items, selected);
  const dayDiscover = SP.eventsOn(discover, selected);
  // The next day after the selected one that has a discoverable event (≤ 60 days) — the empty state's next step.
  const nextDiscoverDay = useMemo(() => {
    if (!discover.length) return null;
    for (let i = 1; i <= 60; i++) { const d = SP.addDays(selected, i); if (SP.eventsOn(discover, d).length) return d; }
    return null;
  }, [discover, selected]);
  const loading = (s.paymentsLoading && !mine.items.length) || (mode === 'discover' && s.discoveryEventsLoading && !discover.length);

  const timeCol = (e) => (
    <div style={{ width: 64, flex: '0 0 auto', fontSize: 14, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{SP.timeText(e.start, vi)}</div>
  );

  const mineCard = (item) => {
    const e = item.event;
    return (
      <div key={item.id} style={{ display: 'flex', gap: 12 }}>
        {timeCol(e)}
        <div style={{ flex: 1, position: 'relative', background: 'var(--bb-field)', borderRadius: 18, padding: 14 }}>
          <span aria-hidden style={{ position: 'absolute', left: 0, top: 12, bottom: 12, width: 3, borderRadius: 2, background: muted(item.source === 'added' ? 0.35 : 0.9) }} />
          <button type="button" onClick={() => goEvent(e.key)} data-testid={`schedule-item-${e.key}`}
            style={{ display: 'block', width: '100%', textAlign: 'left', border: 'none', background: 'none', color: ink, fontFamily: 'inherit', padding: 0, cursor: 'pointer' }}>
            <span style={{ display: 'block', fontSize: 14.5, fontWeight: 600 }}>{e.title}</span>
            <span style={{ display: 'block', fontSize: 12, fontWeight: 600, marginTop: 4 }}>{SP.sourceLabel(item.source, T)}</span>
            {e.ended && <span style={{ display: 'block', fontSize: 12, opacity: 0.7 }}>{T('Đã kết thúc', 'Ended')}</span>}
            {e.location && <span style={{ display: 'block', fontSize: 12, opacity: 0.7 }}>{e.location}</span>}
            {SP.venueTimeNote(e, vi) && <span style={{ display: 'block', fontSize: 12, opacity: 0.7 }}>{SP.venueTimeNote(e, vi)}</span>}
            {e.end == null && !e.ended && <span style={{ display: 'block', fontSize: 12, opacity: 0.75 }}>{T('Chưa có giờ kết thúc', 'No end time listed')}</span>}
          </button>
          {!e.ended && <CalendarExportButtons info={e} T={T} compact />}
          {item.source === 'added' && (
            <button type="button" onClick={() => removeFromBanbeSchedule(e.key)} data-testid={`schedule-remove-${e.key}`}
              title={T('Chỉ bỏ khỏi lịch banbe trên trình duyệt này', 'Removes it from your banbe Schedule in this browser only')} style={linkBtn}>
              ⊖ {T('Bỏ khỏi lịch', 'Remove')}
            </button>
          )}
        </div>
      </div>
    );
  };

  const discoverCard = (e) => {
    const prox = SP.proximity(e, mine.items);
    const proxText = SP.proximityText(prox, T);
    return (
      <div key={e.key} style={{ display: 'flex', gap: 12 }}>
        {timeCol(e)}
        {/* Dashed outline: a suggestion, never mistakable for a confirmed plan. */}
        <div style={{ flex: 1, borderRadius: 18, padding: 14, border: `1.2px dashed ${muted(0.35)}` }}>
          <button type="button" onClick={() => goEvent(e.key)} data-testid={`schedule-discover-${e.key}`}
            style={{ display: 'block', width: '100%', textAlign: 'left', border: 'none', background: 'none', color: ink, fontFamily: 'inherit', padding: 0, cursor: 'pointer' }}>
            <span style={{ display: 'block', fontSize: 12, fontWeight: 600, opacity: 0.75 }}>✦ {T('Gợi ý khám phá', 'Discover')}</span>
            <span style={{ display: 'block', fontSize: 14.5, fontWeight: 600, marginTop: 2 }}>{e.title}</span>
            {e.location && <span style={{ display: 'block', fontSize: 12, opacity: 0.7 }}>{e.location}</span>}
            {SP.venueTimeNote(e, vi) && <span style={{ display: 'block', fontSize: 12, opacity: 0.7 }}>{SP.venueTimeNote(e, vi)}</span>}
            {proxText && <span data-testid={`schedule-conflict-${e.key}`} style={{ display: 'block', fontSize: 12, fontWeight: 600, marginTop: 2 }}>ⓘ {proxText}</span>}
          </button>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 16, alignItems: 'center' }}>
            {s.user && (
              <button type="button" onClick={() => add(e.key)} data-testid={`schedule-add-${e.key}`} style={linkBtn}
                title={T('Lưu vào lịch trong app. Không phải đặt chỗ.', 'Saves to your in-app schedule. Not a reservation.')}>
                ＋ {T('Thêm vào lịch banbe', 'Add to banbe Schedule')}
              </button>
            )}
            <CalendarExportButtons info={e} T={T} compact />
          </div>
        </div>
      </div>
    );
  };

  return (
    <div data-screen-label="Schedule" data-hscroll style={{ minHeight: '100%', background: paper, color: ink, paddingBottom: 140 }}>
      {/* iOS parity (2026-10-18): logo + title on their own row; the month button ("📅 October 2026 ⌄") and
          Today sit on the row below, like ScheduleView's header. */}
      <div style={{ padding: '58px 20px 0', display: 'flex', alignItems: 'center', gap: 14 }}>
        <img src="/banbe-wordmark.png" alt="banbe" style={{ width: 96, height: 'auto', display: 'block', flex: 'none' }} />
        <h1 data-testid="schedule-title" style={display(27, { margin: 0, flex: 1, minWidth: 0 })}>{T('Lịch', 'Schedule')}</h1>
      </div>
      <div style={{ padding: '10px 20px 0', display: 'flex', alignItems: 'center', gap: 8 }}>
        <button type="button" onClick={() => setMonthOpen(true)} data-testid="schedule-month-open"
          aria-label={`${SP.monthTitle(selected, vi)}. ${T('Mở lịch cả tháng', 'Opens the whole month')}`}
          style={{ border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 15, fontWeight: 600, padding: 0, minHeight: 44, cursor: 'pointer', display: 'inline-flex', alignItems: 'center', gap: 7, opacity: 0.85 }}>
          <svg aria-hidden width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="5" width="17" height="15.5" rx="2.3" /><path d="M3.5 9.7h17M8 3v4M16 3v4" /></svg>
          {SP.monthTitle(selected, vi)}
          <svg aria-hidden width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"><path d="M6 9l6 6 6-6" /></svg>
        </button>
        <span style={{ flex: 1 }} />
        <button type="button" onClick={() => pickDay(new Date())} data-testid="schedule-today" disabled={SP.sameDay(selected, today)}
          style={{ border: '1px solid rgba(var(--bb-fg-rgb),0.10)', background: 'linear-gradient(180deg, rgba(255,255,255,0.55), rgba(255,255,255,0.15)), var(--bb-bg)', boxShadow: '0 4px 14px rgba(27,25,22,0.10)',
            color: ink, fontFamily: 'inherit', fontSize: 14, fontWeight: 600, borderRadius: 999, padding: '0 16px', minHeight: 44, cursor: 'pointer', whiteSpace: 'nowrap', opacity: SP.sameDay(selected, today) ? 0.5 : 1 }}>
          {T('Hôm nay', 'Today')}
        </button>
      </div>

      <div data-hscroll style={{ padding: '14px 20px 0' }}>
        <div role="tablist" style={{ display: 'flex', gap: 4, padding: 4, borderRadius: 999, background: 'var(--bb-field)' }}>
          <button type="button" role="tab" aria-selected={mode === 'mine'} data-testid="schedule-mode-mine" style={segBtn(mode === 'mine')} onClick={() => switchMode('mine')}>{T('Lịch của tôi', 'My schedule')}</button>
          <button type="button" role="tab" aria-selected={mode === 'discover'} data-testid="schedule-mode-discover" style={segBtn(mode === 'discover')} onClick={() => switchMode('discover')}>{T('Khám phá', 'Discover')}</button>
        </div>
        <div data-testid="schedule-week" onPointerDown={onSwipeDown('strip')} onPointerMove={onSwipeMove} onPointerUp={onSwipeUp}
          onPointerCancel={onSwipeCancel} onClickCapture={onClickCaptureGuard}
          style={{ marginTop: 12, touchAction: 'none', userSelect: 'none' }}>
          {monthExpanded && (
            <div className="bb-row-reveal" style={{ display: 'flex', alignItems: 'center', gap: 2, animation: 'bbRowReveal .25s ease-out' }}>
              <span style={{ width: 32 }} />
              {(grid[0] || []).map(d => (
                <div key={d.date.getTime()} style={{ flex: 1, textAlign: 'center', fontSize: 11, fontWeight: 600, opacity: 0.65 }}>{SP.weekdayLetter(d.date, vi)}</div>
              ))}
              <span style={{ width: 32 }} />
            </div>
          )}
          {grid.map((row, ri) => {
            const isSelRow = row.some(d => SP.sameDay(d.date, selected));
            if (!monthExpanded && !isSelRow) return null;
            const showArrows = monthExpanded ? ri === 0 : isSelRow;
            const arrow = (dir) => (showArrows ? (
              <button type="button" onClick={() => (monthExpanded ? stepMonth(dir) : stepWeek(dir * 7))}
                aria-label={monthExpanded ? (dir < 0 ? T('Tháng trước', 'Previous month') : T('Tháng sau', 'Next month')) : (dir < 0 ? T('Tuần trước', 'Previous week') : T('Tuần sau', 'Next week'))}
                data-testid={dir < 0 ? 'schedule-prev-week' : 'schedule-next-week'} style={{ ...linkBtn, width: 32, fontSize: 18 }}>{dir < 0 ? '‹' : '›'}</button>
            ) : <span style={{ width: 32, flex: 'none' }} />);
            return (
              <div key={row[0].date.getTime()} className={monthExpanded && !isSelRow ? 'bb-row-reveal' : undefined}
                style={{ display: 'flex', alignItems: 'center', gap: 2, animation: monthExpanded && !isSelRow ? 'bbRowReveal .28s ease-out' : undefined }}>
                {arrow(-1)}
                {row.map(({ date: d, inMonth }) => {
                  const isSel = SP.sameDay(d, selected), isToday = SP.sameDay(d, today), hasEvents = busy.has(d.getTime());
                  return (
                    <button key={d.getTime()} type="button" onClick={() => pickDay(d)} aria-pressed={isSel}
                      data-testid={monthExpanded ? `schedule-month-day-${d.getDate()}` : undefined}
                      aria-label={[SP.dayTitle(d, vi), isToday ? T('Hôm nay', 'Today') : null, hasEvents ? T('Có sự kiện', 'Has events') : null].filter(Boolean).join(', ')}
                      style={{ flex: 1, minWidth: 0, border: 'none', fontFamily: 'inherit', cursor: 'pointer', borderRadius: 14, padding: monthExpanded ? '6px 0' : '8px 0', minHeight: monthExpanded ? 44 : 60,
                        background: isSel ? ink : 'transparent', color: isSel ? paper : ink, opacity: monthExpanded && !inMonth && !isSel ? 0.35 : 1 }}>
                      {!monthExpanded && <div style={{ fontSize: 11, fontWeight: 600, opacity: isSel ? 0.85 : 0.65 }}>{SP.weekdayLetter(d, vi)}</div>}
                      <div style={{ fontSize: 16, fontWeight: isToday ? 700 : 500, marginTop: monthExpanded ? 0 : 2, textDecoration: isToday && !isSel ? 'underline' : 'none' }}>{d.getDate()}</div>
                      <div aria-hidden style={{ width: 5, height: 5, borderRadius: 3, margin: '4px auto 0', background: hasEvents ? (isSel ? paper : ink) : 'transparent' }} />
                    </button>
                  );
                })}
                {arrow(1)}
              </div>
            );
          })}
          <button type="button" onClick={() => setMonthExpanded(v => !v)} data-testid="schedule-month-toggle"
            aria-label={monthExpanded ? T('Thu gọn về tuần', 'Collapse to week') : T('Mở cả tháng', 'Show the whole month')}
            style={{ display: 'flex', justifyContent: 'center', width: '100%', border: 'none', background: 'none', padding: '6px 0', cursor: 'pointer' }}>
            <span aria-hidden style={{ width: 36, height: 4, borderRadius: 2, background: muted(0.22) }} />
          </button>
        </div>
      </div>

      <div onPointerDown={onSwipeDown('list')} onPointerMove={onSwipeMove} onPointerUp={onSwipeUp} onPointerCancel={onSwipeCancel}
        onClickCapture={onClickCaptureGuard} data-testid="schedule-list"
        style={{ padding: '18px 20px 0', touchAction: 'pan-y', minHeight: '55vh' }}>
        <div key={`${mode}-${selected.getTime()}`} className="bb-slide"
          style={{ animation: slideDir ? `${slideDir === 'r' ? 'bbSlideFromRight' : 'bbSlideFromLeft'} .22s ease-out` : undefined }}>
        <h2 style={{ fontSize: 15, fontWeight: 600, margin: '0 0 12px' }}>{SP.dayTitle(selected, vi)}</h2>
        {notice && <p role="status" style={{ fontSize: 12.5, margin: '0 0 10px', color: muted(0.8) }}>{notice}</p>}
        {mode === 'mine' ? (
          s.paymentBookingsLoadFailed && !dayItems.length ? (
            <p data-testid="schedule-error" style={{ fontSize: 13.5 }}>{T('Chưa tải được đặt chỗ của bạn. Lịch có thể chưa đầy đủ.', "Couldn't load your bookings, so this schedule may be incomplete.")}</p>
          ) : loading ? (
            <p role="status" style={{ fontSize: 13.5, color: muted(0.7) }}>{T('Đang tải lịch…', 'Loading schedule…')}</p>
          ) : dayItems.length === 0 ? (
            <EmptyState scene="freeDay" testId="schedule-empty-mine"
              title={T('Ngày này còn trống!', 'This day is wide open!')}
              message={T('Chưa có kế hoạch nào. Tìm một buổi vui để gặp người mới nhé.', 'Nothing planned yet. Find something fun and meet new people.')}
              actionLabel={T('Khám phá sự kiện ngày này', 'Discover events on this day')} actionTestId="schedule-empty-to-discover"
              onAction={() => switchMode('discover')} />
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{dayItems.map(mineCard)}</div>
          )
        ) : (
          s.discoveryEventsLoadFailed && !discover.length ? (
            <p data-testid="schedule-error" style={{ fontSize: 13.5 }}>{T('Chưa tải được sự kiện. Kéo xuống để thử lại.', "Couldn't load events. Pull down to try again.")}</p>
          ) : loading ? (
            <p role="status" style={{ fontSize: 13.5, color: muted(0.7) }}>{T('Đang tải lịch…', 'Loading schedule…')}</p>
          ) : dayDiscover.length === 0 ? (
            <EmptyState scene="explore" testId="schedule-empty-discover"
              title={discover.length ? T('Hôm nay chưa có buổi nào', 'Nothing on this day') : T('Sắp có buổi mới thôi!', 'New events are on their way!')}
              message={discover.length ? T('Không có sự kiện công khai nào ngày này. Ngày có chấm là ngày có sự kiện.', 'No public events on this day. Days with a dot have events.')
                : T('Hiện chưa có sự kiện công khai sắp tới nào để đặt chỗ. Xem bản đồ hoặc quay lại sau nhé.', 'There are no upcoming public events open for booking right now. Peek at the map or check back soon.')}
              actionIcon={nextDiscoverDay ? '→' : '⌖'}
              actionLabel={nextDiscoverDay ? T(`Tới ${SP.dayTitle(nextDiscoverDay, vi)}`, `Go to ${SP.dayTitle(nextDiscoverDay, vi)}`) : T('Mở bản đồ', 'Open the map')}
              actionTestId="schedule-empty-next"
              onAction={() => (nextDiscoverDay ? pickDay(nextDiscoverDay) : goMapExplore())} />
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{dayDiscover.map(discoverCard)}</div>
          )
        )}
        {mode === 'mine' && mine.undatedCount > 0 && (
          <p style={{ fontSize: 12.5, color: muted(0.7), marginTop: 14 }}>
            {T(`${mine.undatedCount} kế hoạch chưa có ngày giờ nên chưa hiện trên lịch.`, `${mine.undatedCount} plan${mine.undatedCount === 1 ? ' has' : 's have'} no date yet, so not shown on the calendar.`)}
          </p>
        )}
        <p style={{ fontSize: 11.5, color: muted(0.55), marginTop: 18 }}>
          {T('Sự kiện bạn tự thêm chỉ lưu trên trình duyệt này.', 'Events you add yourself are kept in this browser only.')}
        </p>
        </div>
      </div>

      {monthOpen && (
        <MonthSheet events={mode === 'mine' ? mine.items.map(i => i.event) : discover} selected={selected} firstDay={firstDay} vi={vi} T={T}
          mode={mode} onMode={switchMode} onClose={() => setMonthOpen(false)}
          onPick={(d) => { pickDay(d); setMonthOpen(false); }} />
      )}
    </div>
  );
}

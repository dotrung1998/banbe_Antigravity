// Event Detail "plan" control — web twin of iOS EventPlanTitleRow (notes 44/45, compact 2026-10-18): one small
// glass pill beside the event title (calendar icon + "Added" / "Discover") that opens a frosted menu with
// the banbe Schedule status, Add / Remove (manual adds only), Add to calendar (.ics) and Google Calendar.
// Compact, so the title row is only as tall as the title — no gap above the location line.
// Real events only; adding to the banbe Schedule needs an account.
import { useEffect, useRef, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { ink } from '../theme.js';
import { sourceLabel, canAdd } from '../lib/schedulePresentation.js';
import { calendarDraft, downloadIcs, googleCalendarUrl } from '../lib/calendarExport.js';
import { track } from '../lib/analytics.js';

const CalIcon = ({ added }) => (
  <svg aria-hidden width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <rect x="3.5" y="5" width="17" height="15.5" rx="2.3" /><path d="M3.5 9.7h17M8 3v4M16 3v4" />
    {added ? <path d="M9 14.6l2 2 4-4" /> : <path d="M12 12.3v5M9.5 14.8h5" />}
  </svg>
);

/** Title + compact plan pill on one row. Renders just the title for events that can't be planned. */
export default function EventPlanTitle({ eventKey, title, titleStyle }) {
  const { state: s, T, scheduleSnapshot, scheduleInfoFor, addToBanbeSchedule, removeFromBanbeSchedule } = useBanBe();
  const [open, setOpen] = useState(false);
  const [msg, setMsg] = useState('');
  const wrap = useRef(null);
  const real = s.realEventsById?.[eventKey];
  const info = scheduleInfoFor(real);
  useEffect(() => {
    if (!open) return undefined;
    const onDown = (e) => { if (!wrap.current?.contains(e.target)) setOpen(false); };
    const onKey = (e) => { if (e.key === 'Escape') setOpen(false); };
    document.addEventListener('pointerdown', onDown);
    window.addEventListener('keydown', onKey);
    return () => { document.removeEventListener('pointerdown', onDown); window.removeEventListener('keydown', onKey); };
  }, [open]);

  const available = info && info.start && !info.cancelled;
  const item = info ? scheduleSnapshot.mine.items.find(i => i.id === eventKey) : null;
  const flash = (m) => { setMsg(m); setTimeout(() => setMsg(''), 6000); };
  const draft = available ? calendarDraft({ title: info.title, start: info.start, end: info.end, location: info.location, eventKey: info.key, origin: window.location.origin }, T) : null;

  const add = () => {
    const r = addToBanbeSchedule(eventKey);
    flash(r === 'added' ? T('Đã thêm vào lịch banbe trên trình duyệt này. Đây chưa phải đặt chỗ.', "Added to your banbe Schedule in this browser. This isn't a reservation.")
      : r === 'ineligible' ? T('Sự kiện này không thêm vào lịch được.', "This event can't be added.") : '');
  };
  const ics = () => {
    track('system_calendar_editor_opened');
    if (!draft) return;
    downloadIcs(draft, `banbe-${info.key}.ics`, { uid: info.key });
    flash(T('Đã tải file lịch (.ics). Mở file để thêm vào ứng dụng lịch của bạn.', 'Calendar file (.ics) downloaded. Open it to add the event to your calendar app.'));
  };
  const google = () => { if (draft) window.open(googleCalendarUrl(draft), '_blank', 'noopener'); };

  const menuItem = (key, label, onClick, { disabled = false, danger = false, testId } = {}) => (
    <button key={key} type="button" role="menuitem" disabled={disabled} data-testid={testId}
      onClick={() => { setOpen(false); onClick?.(); }}
      style={{ display: 'block', width: '100%', textAlign: 'left', minHeight: 46, padding: '10px 18px', border: 'none', background: 'none', fontFamily: 'inherit',
        fontSize: 15, color: danger ? 'var(--bb-alert)' : ink, opacity: disabled ? 0.6 : 1, cursor: disabled ? 'default' : 'pointer' }}>
      {label}
    </button>
  );

  return (
    <div style={{ margin: '8px 0 6px' }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10 }}>
        <h1 style={{ ...titleStyle, margin: 0, flex: 1, minWidth: 0 }}>{title}</h1>
        {available && (
          <div ref={wrap} style={{ position: 'relative', flex: 'none', marginTop: 2 }} data-testid="event-plan">
            <button type="button" onClick={() => setOpen(v => !v)} aria-haspopup="menu" aria-expanded={open} data-testid="event-plan-button"
              aria-label={item ? T(`Trong lịch banbe (${sourceLabel(item.source, T)}). Mở menu`, `In banbe Schedule (${sourceLabel(item.source, T)}). Open menu`) : T('Khám phá. Thêm vào lịch', 'Discover. Add to calendar')}
              style={{ display: 'inline-flex', alignItems: 'center', gap: 6, height: 36, padding: '0 12px', borderRadius: 999, cursor: 'pointer', color: ink, fontFamily: 'inherit', fontSize: 13, fontWeight: 600, whiteSpace: 'nowrap',
                border: '1px solid rgba(var(--bb-fg-rgb),0.10)', background: 'linear-gradient(180deg, rgba(255,255,255,0.55), rgba(255,255,255,0.15)), var(--bb-bg)', boxShadow: '0 4px 14px rgba(27,25,22,0.10)' }}>
              <CalIcon added={!!item} />
              <span data-testid="event-plan-status">{item ? T('Đã thêm', 'Added') : T('Khám phá', 'Discover')}</span>
            </button>
            {open && (
              <div role="menu" data-testid="event-plan-menu"
                style={{ position: 'absolute', right: 0, top: 42, zIndex: 30, width: 260, padding: '6px 0', borderRadius: 22, color: ink,
                  background: 'color-mix(in srgb, var(--bb-bg) 80%, transparent)', backdropFilter: 'blur(28px) saturate(1.6)', WebkitBackdropFilter: 'blur(28px) saturate(1.6)',
                  border: '1px solid rgba(255,255,255,0.45)', boxShadow: '0 18px 50px rgba(27,25,22,0.28)', animation: 'banbeFade .16s ease-out' }}>
                {item
                  ? menuItem('in', `✓ ${T('Trong lịch của tôi', 'In My schedule')} · ${sourceLabel(item.source, T)}`, null, { disabled: true, testId: 'event-plan-in-mine' })
                  : s.user && canAdd(info) && menuItem('add', `＋ ${T('Thêm vào lịch banbe', 'Add to banbe Schedule')}`, add, { testId: 'event-plan-add' })}
                {item?.source === 'added' && menuItem('remove', `⊖ ${T('Bỏ khỏi lịch banbe', 'Remove from banbe Schedule')}`, () => removeFromBanbeSchedule(eventKey), { danger: true, testId: 'event-plan-remove' })}
                {!info.ended && (
                  <>
                    {(item || (s.user && canAdd(info))) && <div style={{ height: 1, margin: '4px 18px', background: 'rgba(var(--bb-fg-rgb),0.12)' }} />}
                    {menuItem('ics', `📅 ${T('Thêm vào lịch (.ics)', 'Add to calendar (.ics)')}`, ics, { testId: `calendar-ics-${info.key}` })}
                    {menuItem('google', `${T('Google Lịch', 'Google Calendar')} ↗`, google, { testId: `calendar-google-${info.key}` })}
                  </>
                )}
              </div>
            )}
          </div>
        )}
      </div>
      {msg && <p role="status" style={{ fontSize: 12, opacity: 0.75, margin: '4px 0 0', color: ink }}>{msg}</p>}
    </div>
  );
}

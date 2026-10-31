// Event Detail "plan" control — web twin of iOS EventPlanTitleRow (notes 44/45, compact 2026-10-18): one small
// glass pill beside the event title (calendar icon + "Added" / "Discover") that opens a frosted menu with
// the banbe Schedule status, Add / Remove (manual adds only), Add to calendar (.ics) and Google Calendar.
// Compact, so the title row is only as tall as the title — no gap above the location line.
// Real events only; adding to the banbe Schedule needs an account.
import { useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { ink, clay } from '../theme.js';
import GlassMenu, { GlassMenuItem, GlassMenuDivider } from '../components/GlassMenu.jsx';
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
// `onPhoto` (note 70): the title sits on the event photo, so the calendar pill is a clay glass pill with a white glyph.
export default function EventPlanTitle({ eventKey, title, titleStyle, onPhoto = false }) {
  const { state: s, T, scheduleSnapshot, scheduleInfoFor, addToBanbeSchedule, removeFromBanbeSchedule } = useBanBe();
  const [open, setOpen] = useState(false);
  const [msg, setMsg] = useState('');
  const real = s.realEventsById?.[eventKey];
  const info = scheduleInfoFor(real);

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

  return (
    <div style={{ margin: '8px 0 6px' }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 10 }}>
        <h1 style={{ ...titleStyle, margin: 0, flex: 1, minWidth: 0 }}>{title}</h1>
        {available && (
          <GlassMenu open={open} onOpenChange={setOpen} wrapStyle={{ flex: 'none', marginTop: 2 }} wrapTestId="event-plan" menuTestId="event-plan-menu"
            trigger={(
              // Outlined clay pill (note 52 mockup): reads as a secondary action next to the title, not a second CTA.
              <button type="button" onClick={() => setOpen(v => !v)} aria-haspopup="menu" aria-expanded={open} data-testid="event-plan-button"
                aria-label={item ? T(`Trong lịch banbe (${sourceLabel(item.source, T)}). Mở menu`, `In banbe Schedule (${sourceLabel(item.source, T)}). Open menu`) : T('Thêm lịch', 'Add to calendar')}
                style={{ display: 'inline-flex', alignItems: 'center', gap: 6, height: 34, padding: '0 12px', borderRadius: 999, cursor: 'pointer', color: clay, fontFamily: 'inherit', fontSize: 13, fontWeight: 600, whiteSpace: 'nowrap',
                  border: `1px solid ${clay}`, background: 'transparent',
                  ...(onPhoto ? { color: '#fff', border: '1px solid rgba(255,255,255,0.32)', background: 'rgba(var(--bb-clay-rgb),0.82)' } : null) }}>
                <CalIcon added={!!item} />
                <span data-testid="event-plan-status">{item ? T('Đã thêm', 'Added') : T('Thêm lịch', 'Add to calendar')}</span>
              </button>
            )}>
            {item
              ? <GlassMenuItem disabled testId="event-plan-in-mine">{`✓ ${T('Trong lịch của tôi', 'In My schedule')} · ${sourceLabel(item.source, T)}`}</GlassMenuItem>
              : s.user && canAdd(info) && <GlassMenuItem onClick={add} testId="event-plan-add">{`＋ ${T('Thêm vào lịch banbe', 'Add to banbe Schedule')}`}</GlassMenuItem>}
            {item?.source === 'added' && <GlassMenuItem danger onClick={() => removeFromBanbeSchedule(eventKey)} testId="event-plan-remove">{`⊖ ${T('Bỏ khỏi lịch banbe', 'Remove from banbe Schedule')}`}</GlassMenuItem>}
            {!info.ended && (
              <>
                {(item || (s.user && canAdd(info))) && <GlassMenuDivider />}
                <GlassMenuItem onClick={ics} testId={`calendar-ics-${info.key}`}>{`📅 ${T('Thêm vào lịch (.ics)', 'Add to calendar (.ics)')}`}</GlassMenuItem>
                <GlassMenuItem onClick={google} testId={`calendar-google-${info.key}`}>{`${T('Google Lịch', 'Google Calendar')} ↗`}</GlassMenuItem>
              </>
            )}
          </GlassMenu>
        )}
      </div>
      {msg && <p role="status" style={{ fontSize: 12, opacity: 0.75, margin: '4px 0 0', color: ink }}>{msg}</p>}
    </div>
  );
}

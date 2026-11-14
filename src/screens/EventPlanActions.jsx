// Event Detail calendar choices — web twin of iOS EventPlanTitleRow / EventPlanButtons (notes 44/45, note 77).
// The title stands alone; the calendar choices are two tiles inside the ticket stub, each with its own look:
// - banbe Schedule: an ink square (Directions colours) with a calendar glyph and a sparkle (the in-app agenda, not a reservation).
//   One tap adds; once added a tap opens a menu with the status and Remove (manual adds only).
// - Phone calendar: a mini tear-off calendar page (red band, the event's day). A tap opens Google / .ics.
// Real events only; adding to the banbe Schedule needs an account.
import { useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { ink, ink2 } from '../theme.js';
import GlassMenu, { GlassMenuItem } from '../components/GlassMenu.jsx';
import { sourceLabel, canAdd } from '../lib/schedulePresentation.js';
import { calendarDraft, downloadIcs, googleCalendarUrl } from '../lib/calendarExport.js';
import { track } from '../lib/analytics.js';

const CalIcon = ({ added }) => (
  <svg aria-hidden width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <rect x="3.5" y="5" width="17" height="15.5" rx="2.3" /><path d="M3.5 9.7h17M8 3v4M16 3v4" />
    {added ? <path d="M9 14.6l2 2 4-4" /> : <path d="M12 12.3v5M9.5 14.8h5" />}
  </svg>
);
const Sparkle = () => (
  <svg aria-hidden width="11" height="11" viewBox="0 0 24 24" style={{ position: 'absolute', top: -4, right: -4 }}>
    <path d="M12 0c.8 6.4 4.6 10.6 12 12-7.4 1.4-11.2 5.6-12 12-.8-6.4-4.6-10.6-12-12C7.4 10.6 11.2 6.4 12 0Z" fill="#FFD973" />
  </svg>
);
const Check = () => (
  <svg aria-hidden width="15" height="15" viewBox="0 0 24 24" style={{ position: 'absolute', right: -5, bottom: -5 }}>
    <circle cx="12" cy="12" r="11" fill="#339E5C" stroke="#fff" strokeWidth="2" /><path d="m7.5 12.3 3 3 6-6" fill="none" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

/** A tiny tear-off calendar page (red band with the month, the day below): the "phone calendar" icon on Event Detail
 *  and Confirmed. iOS twin: MiniCalendarPage. */
export function MiniCalendarPage({ day, month, size = 44, done = false, fixedLight = false }) {
  // Monochrome Calendar icon (iOS 27 style) in the Directions button's colours: ink tile, paper text.
  return (
    <span aria-hidden style={{ position: 'relative', flex: 'none', display: 'inline-flex', width: size, height: size }}>
      <span style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: size * 0.02, width: '100%', height: '100%', borderRadius: size * 0.25, background: fixedLight ? '#fff' : ink, color: fixedLight ? '#000' : 'var(--bb-bg)', boxShadow: '0 2px 6px rgba(0,0,0,0.18)', fontFamily: 'system-ui, -apple-system, sans-serif', lineHeight: 1 }}>
        <span style={{ opacity: 0.62, fontSize: size * 0.17, fontWeight: 600, letterSpacing: '0.03em', textTransform: 'uppercase' }}>{month || ' '}</span>
        <span style={{ fontSize: size * 0.46, fontWeight: 400 }}>{day || '+'}</span>
      </span>
      {done && <Check />}
    </span>
  );
}

/** The event title alone (note 77: the calendar choices moved into the ticket stub). */
export default function EventPlanTitle({ title, titleStyle }) {
  return <h1 style={{ ...titleStyle, margin: 0 }}>{title}</h1>;
}

const tileBtn = { position: 'relative', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', width: 44, height: 44, padding: 0, border: 'none', background: 'none', cursor: 'pointer', fontFamily: 'inherit' };
const caption = { fontSize: 10, fontWeight: 600, color: ink2, lineHeight: 1, whiteSpace: 'nowrap' };

/** The two calendar tiles. `onMessage(text | '')` gets the status line (the stub shows it full width). */
// `chips` (v2.3, note 81): the same two choices as slim pills for the ticket stub's "Save the date" row.
export function EventPlanButtons({ eventKey, day, month, inert = false, onMessage, chips = false }) {
  const { state: s, T, scheduleSnapshot, scheduleInfoFor, addToBanbeSchedule, removeFromBanbeSchedule } = useBanBe();
  const [schedOpen, setSchedOpen] = useState(false);
  const [calOpen, setCalOpen] = useState(false);
  const real = s.realEventsById?.[eventKey];
  const info = scheduleInfoFor(real);
  const available = info && info.start && !info.cancelled;
  if (!available) return null;
  const item = scheduleSnapshot.mine.items.find(i => i.id === eventKey);
  const flash = (m) => { onMessage?.(m); if (m) setTimeout(() => onMessage?.(''), 6000); };
  const draft = calendarDraft({ title: info.title, start: info.start, end: info.end, location: info.location, eventKey: info.key, origin: window.location.origin }, T);

  const add = () => {
    if (!s.user || !canAdd(info)) { flash(T('Sự kiện này không thêm vào lịch được.', "This event can't be added.")); return; }
    const r = addToBanbeSchedule(eventKey);
    flash(r === 'added' ? T('Đã thêm vào lịch banbe trên trình duyệt này. Đây chưa phải đặt chỗ.', "Added to your banbe Schedule in this browser. This isn't a reservation.")
      : r === 'ineligible' ? T('Sự kiện này không thêm vào lịch được.', "This event can't be added.") : '');
  };
  const ics = () => {
    track('system_calendar_editor_opened');
    downloadIcs(draft, `banbe-${info.key}.ics`, { uid: info.key });
    flash(T('Đã tải file lịch (.ics). Mở file để thêm vào ứng dụng lịch của bạn.', 'Calendar file (.ics) downloaded. Open it to add the event to your calendar app.'));
  };
  const google = () => window.open(googleCalendarUrl(draft), '_blank', 'noopener');

  if (chips) return <PlanChips {...{ T, item, info, inert, add, ics, google, schedOpen, setSchedOpen, calOpen, setCalOpen, flash, eventKey, removeFromBanbeSchedule }} />;
  return (
    <div style={{ flex: 'none', display: 'flex', flexDirection: 'column', gap: 8, alignItems: 'center', ...(inert ? { pointerEvents: 'none' } : null) }} data-testid="event-plan">
      <GlassMenu open={schedOpen} onOpenChange={setSchedOpen} top={50} wrapStyle={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3 }} menuTestId="event-plan-menu"
        trigger={(
          <button type="button" className="bb-press" data-testid="event-plan-button" aria-haspopup={item ? 'menu' : undefined}
            onClick={() => (item ? setSchedOpen(v => !v) : add())}
            aria-label={item ? T(`Trong lịch banbe (${sourceLabel(item.source, T)})`, `In banbe Schedule (${sourceLabel(item.source, T)})`) : T('Thêm vào lịch banbe', 'Add to banbe Schedule')}
            style={{ ...tileBtn, color: 'var(--bb-bg)', borderRadius: 13, background: ink }}>
            <CalIcon added={!!item} /><Sparkle />
            <span data-testid="event-plan-status" hidden>{item ? 'added' : 'none'}</span>
          </button>
        )}>
        {item && <GlassMenuItem disabled testId="event-plan-in-mine">{`✓ ${T('Trong lịch của tôi', 'In My schedule')} · ${sourceLabel(item.source, T)}`}</GlassMenuItem>}
        {item?.source === 'added' && <GlassMenuItem danger onClick={() => { removeFromBanbeSchedule(eventKey); setSchedOpen(false); flash(''); }} testId="event-plan-remove">{`⊖ ${T('Bỏ khỏi lịch banbe', 'Remove from banbe Schedule')}`}</GlassMenuItem>}
      </GlassMenu>
      <span style={{ ...caption, marginTop: -5 }}>banbe</span>
      {!info.ended && (
        <>
          <GlassMenu open={calOpen} onOpenChange={setCalOpen} top={50} menuTestId="event-plan-cal-menu"
            trigger={(
              <button type="button" className="bb-press" data-testid="event-plan-calendar" aria-haspopup="menu" aria-expanded={calOpen}
                onClick={() => setCalOpen(v => !v)} aria-label={T('Thêm vào lịch điện thoại', 'Add to your calendar')} style={tileBtn}>
                <MiniCalendarPage day={day} month={month} />
              </button>
            )}>
            <GlassMenuItem onClick={() => { ics(); setCalOpen(false); }} testId={`calendar-ics-${info.key}`}>{`📅 ${T('Lịch Apple · ứng dụng khác (.ics)', 'Apple Calendar · other apps (.ics)')}`}</GlassMenuItem>
            <GlassMenuItem onClick={() => { google(); setCalOpen(false); }} testId={`calendar-google-${info.key}`}>{`${T('Google Lịch', 'Google Calendar')} ↗`}</GlassMenuItem>
          </GlassMenu>
          <span style={{ ...caption, marginTop: -5 }}>{T('Lịch', 'Calendar')}</span>
        </>
      )}
    </div>
  );
}

// v2.3 "Save the date" chips (note 81): 30 px pills inside a 44 px hit area. banbe turns moss with a check once the event
// is in the banbe Schedule (a tap then opens the same status / Remove menu); Calendar opens the .ics / Google menu.
const chipIco = { width: 13, height: 13, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': true };
const chipBtn = { minHeight: 44, display: 'inline-flex', alignItems: 'center', padding: 0, border: 'none', background: 'none', cursor: 'pointer', fontFamily: 'inherit', color: 'inherit' };
const chipFace = (added) => ({ height: 30, padding: '0 11px', borderRadius: 999, display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 12, fontWeight: 600, whiteSpace: 'nowrap',
  border: added ? '1px solid transparent' : '1px solid var(--bb-rule)', background: added ? 'color-mix(in srgb, var(--bb-update) 16%, transparent)' : 'transparent', color: added ? 'var(--bb-update)' : 'var(--bb-fg)',
  transition: 'background-color .28s, color .28s, border-color .28s' });
function PlanChips({ T, item, info, inert, add, ics, google, schedOpen, setSchedOpen, calOpen, setCalOpen, flash, eventKey, removeFromBanbeSchedule }) {
  const [pop, setPop] = useState(0);
  return (
    <div style={{ display: 'flex', gap: 6, justifyContent: 'flex-end', minWidth: 0, ...(inert ? { pointerEvents: 'none' } : null) }} data-testid="event-plan">
      <GlassMenu open={schedOpen} onOpenChange={setSchedOpen} top={44} menuTestId="event-plan-menu"
        trigger={(
          <button type="button" className="bbv23-press" data-testid="event-plan-button" aria-haspopup={item ? 'menu' : undefined} aria-pressed={!!item}
            onClick={() => { if (item) setSchedOpen(v => !v); else { add(); setPop(x => x + 1); } }}
            aria-label={item ? T(`Trong lịch banbe (${sourceLabel(item.source, T)})`, `In banbe Schedule (${sourceLabel(item.source, T)})`) : T('Thêm vào lịch banbe', 'Add to banbe Schedule')}
            style={chipBtn}>
            <span key={pop} className={pop ? 'bbv23-pop' : undefined} style={chipFace(!!item)}>
              {item ? <svg {...chipIco} strokeWidth={2.4}><path d="m6 12.5 4 4 8-9" /></svg>
                : <svg {...chipIco}><path d="M18 15H6l1.5-2.5V9a4.5 4.5 0 0 1 9 0v3.5L18 15Z" /><path d="M10.5 18a2 2 0 0 0 3 0" /></svg>}
              banbe
            </span>
            <span data-testid="event-plan-status" hidden>{item ? 'added' : 'none'}</span>
          </button>
        )}>
        {item && <GlassMenuItem disabled testId="event-plan-in-mine">{`✓ ${T('Trong lịch của tôi', 'In My schedule')} · ${sourceLabel(item.source, T)}`}</GlassMenuItem>}
        {item?.source === 'added' && <GlassMenuItem danger onClick={() => { removeFromBanbeSchedule(eventKey); setSchedOpen(false); flash(''); }} testId="event-plan-remove">{`⊖ ${T('Bỏ khỏi lịch banbe', 'Remove from banbe Schedule')}`}</GlassMenuItem>}
      </GlassMenu>
      {!info.ended && (
        <GlassMenu open={calOpen} onOpenChange={setCalOpen} top={44} menuTestId="event-plan-cal-menu"
          trigger={(
            <button type="button" className="bbv23-press" data-testid="event-plan-calendar" aria-haspopup="menu" aria-expanded={calOpen}
              onClick={() => setCalOpen(v => !v)} aria-label={T('Thêm vào lịch điện thoại', 'Add to your calendar')} style={chipBtn}>
              <span style={chipFace(false)}>
                <svg {...chipIco}><rect x="3.5" y="5" width="17" height="15" rx="3" /><path d="M8 3v4M16 3v4M3.5 10h17" /><path d="M8 14h2M14 14h2M8 17h2M14 17h2" /></svg>
                {T('Lịch', 'Calendar')}
              </span>
            </button>
          )}>
          <GlassMenuItem onClick={() => { ics(); setCalOpen(false); }} testId={`calendar-ics-${info.key}`}>{`📅 ${T('Lịch Apple · ứng dụng khác (.ics)', 'Apple Calendar · other apps (.ics)')}`}</GlassMenuItem>
          <GlassMenuItem onClick={() => { google(); setCalOpen(false); }} testId={`calendar-google-${info.key}`}>{`${T('Google Lịch', 'Google Calendar')} ↗`}</GlassMenuItem>
        </GlassMenu>
      )}
    </div>
  );
}

/** The same two chips, inert, for the create-event preview (a draft is not a real event yet, so nothing to add). */
export function PlanChipsPreview({ T }) {
  return (
    <div aria-hidden style={{ display: 'flex', gap: 6, justifyContent: 'flex-end', pointerEvents: 'none' }} data-testid="event-plan-preview">
      {[['banbe', <svg key="b" {...chipIco}><path d="M18 15H6l1.5-2.5V9a4.5 4.5 0 0 1 9 0v3.5L18 15Z" /><path d="M10.5 18a2 2 0 0 0 3 0" /></svg>],
        [T('Lịch', 'Calendar'), <svg key="c" {...chipIco}><rect x="3.5" y="5" width="17" height="15" rx="3" /><path d="M8 3v4M16 3v4M3.5 10h17" /><path d="M8 14h2M14 14h2M8 17h2M14 17h2" /></svg>]].map(([label, icon]) => (
        <span key={label} style={{ ...chipBtn, cursor: 'default' }}><span style={chipFace(false)}>{icon}{label}</span></span>
      ))}
    </div>
  );
}

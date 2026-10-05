import { useEffect } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { EVENTS, bg } from '../data/events.js';
import { liveEventOverrides, formatVnEventDate } from '../lib/countdown.js';
import { paper, ink, rule, display, fieldGlass, cardGlass } from '../theme.js';

const EMPTY_MESSAGES = {
  going: ["Bạn chưa tham gia sự kiện nào.", "You're not going to any events yet."],
  saved: ['Bạn chưa lưu sự kiện nào.', "You haven't saved any events yet."],
  completed: ['Bạn chưa hoàn thành sự kiện nào.', "You haven't completed any events yet."],
};
const SCREEN_LABELS = { going: 'Going', saved: 'Saved', completed: 'Completed' };

// Opened from the "Going"/"Saved" cards and the "Sự kiện đã lưu"/"Completed
// events" row on Account — a plain list of the matching events, in its own
// view rather than redirecting to Home, so "back" is a single step to
// Account instead of losing the trip there.
export default function EventList() {
  const { state, T, trStatus, stripKm, eventListTitle, goEvent, backFromEventList, loadHomeLiveEvents, loadRealEventsById } = useGoc();
  const s = state;
  const mode = s.eventListMode;
  // 2026-09-25 fix pass (Task 0 audit) — see `list`'s own comment below;
  // this screen never fetched live status before.
  useEffect(() => { loadHomeLiveEvents(); }, [loadHomeLiveEvents]);

  const keys = mode === 'going' ? s.attending
    : mode === 'completed'
    ? [...new Set([...(s.favorites || []), ...s.attending])]
    : (s.favorites || []);

  // Blocker fix (retention roadmap follow-up) — same canonical realEventsById
  // fallback Home.jsx's own "Sự kiện của bạn" strip uses: a saved/attending
  // key that isn't in the static demo catalogue (a real, host-created
  // event) used to just disappear from this list (EVENTS.find -> undefined,
  // filtered out below) even though the underlying favorite/booking row was
  // completely real.
  const missingRealKeys = keys.filter(k => !EVENTS.some(e => e.key === k) && !(k in s.realEventsById));
  useEffect(() => {
    if (missingRealKeys.length) loadRealEventsById(missingRealKeys);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [missingRealKeys.join(','), loadRealEventsById]);

  // 2026-09-25 fix pass (Task 0 audit) — real bug: Account's own "Going"/
  // "Saved"/"Completed" lists used the raw static catalogue — both the
  // Going/Completed split below (`endedHoursAgo`) and every displayed date
  // via `e.meta` came from the frozen catalogue, never live status.
  let list = keys.map(k => {
    const catalogEv = EVENTS.find(e => e.key === k);
    if (catalogEv) {
      const overrides = liveEventOverrides(s.homeLiveEvents[k], catalogEv);
      const e = overrides ? { ...catalogEv, ...overrides } : catalogEv;
      return { key: e.key, name: e.name, photoUrl: e.img, meta: trStatus(stripKm(e.meta, e)), endedHoursAgo: e.endedHoursAgo };
    }
    const real = s.realEventsById[k];
    if (real === undefined) return null; // still loading — quiet, no flash
    if (real === null) {
      // Honest "unavailable" — deleted, or RLS no longer lets this account
      // see it. Never invented, never silently dropped from the list.
      return { key: k, name: T('Sự kiện không khả dụng', 'Event unavailable'), photoUrl: null, meta: '', endedHoursAgo: null, unavailable: true };
    }
    const startsAt = real.startsAt ? new Date(real.startsAt) : null;
    const endedHoursAgo = real.status === 'ended' && startsAt ? Math.max(0, Math.round((Date.now() - startsAt.getTime()) / 3600000)) : null;
    const when = startsAt ? (() => { const { weekdayShort, dayMonth, time } = formatVnEventDate(startsAt); return `${weekdayShort}, ${dayMonth} ▪︎ ${time}`; })() : '';
    return { key: k, name: real.name, photoUrl: real.photoUrl, meta: [when, real.area].filter(Boolean).join(' ▪︎ '), endedHoursAgo };
  }).filter(Boolean);
  // "Completed" means it already happened — anything still upcoming (or
  // just favorited but never actually attended/held) doesn't belong here.
  // Conversely, "Going" is only what's still ahead — once an event ends it
  // moves to Completed instead of sitting in Going forever.
  if (mode === 'completed') list = list.filter(e => e.endedHoursAgo != null);
  if (mode === 'going') list = list.filter(e => e.endedHoursAgo == null);

  const emptyMsg = T(...EMPTY_MESSAGES[mode]);

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label={SCREEN_LABELS[mode]}>
      <div onClick={backFromEventList} data-testid="event-list-back" style={{ padding: '70px 20px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Tài khoản', 'Account')}</div>
      <div style={{ padding: '10px 20px 0', display: 'flex', alignItems: 'center', gap: 10 }}>
        <svg width={22} height={22} viewBox="0 0 24 24" fill="none" stroke={ink} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" aria-hidden style={{ flex: 'none' }}>
          {mode === 'saved' ? <path d="M6.5 3.5h11v17l-5.5-4.2-5.5 4.2z" />
            : mode === 'completed' ? <><rect x="3.5" y="5" width="17" height="15.5" rx="2.3" /><path d="M3.5 9.7h17" /><path d="M8 3v4M16 3v4" /><path d="M8.7 14.7l2 2 4.3-4.3" /></>
            : <><circle cx="12" cy="12" r="8.5" /><path d="M8.2 12.3l2.6 2.6 5-5.2" /></>}
        </svg>
        <span style={{ ...display(24) }}>{eventListTitle}</span>
      </div>

      {list.length > 0 ? (
        <div style={{ ...fieldGlass({ margin: '20px 20px 0', display: 'flex', flexDirection: 'column' }) }}>
          {list.map((e, i) => (
            <div key={e.key} onClick={e.unavailable ? undefined : () => goEvent(e.key)} style={{ display: 'flex', gap: 12, alignItems: 'center', padding: '13px 16px', borderBottom: i < list.length - 1 ? `1px solid ${rule}` : 'none', cursor: e.unavailable ? 'default' : 'pointer' }}>
              {e.photoUrl ? (
                <div style={bg(e.photoUrl, { flex: 'none', width: 52, height: 52, borderRadius: 10 })} />
              ) : (
                <div style={{ ...cardGlass({ width: 52, height: 52 }), flex: 'none' }} />
              )}
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0, flex: 1 }}>
                <span style={{ ...display(15, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>{e.name}</span>
                <span style={{ fontSize: 11.5, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{e.meta}</span>
              </div>
              {!e.unavailable && <span style={{ fontSize: 15, color: ink, flex: 'none', lineHeight: 1 }}>›</span>}
            </div>
          ))}
        </div>
      ) : (
        <p style={{ fontSize: 13, lineHeight: 1.5, color: ink, padding: '40px 20px', textAlign: 'center' }}>{emptyMsg}</p>
      )}
    </div>
  );
}

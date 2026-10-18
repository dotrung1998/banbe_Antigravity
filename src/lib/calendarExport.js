// "Add to calendar" for ONE event — web twin of iOS `Lib/CalendarExport.swift` (note 44). The browser has no system
// event editor, so this builds a standard .ics file (Apple Calendar, Outlook, Google all open it) and a Google
// Calendar link. Nothing is written anywhere until the person saves it in their own calendar app. An export, not sync.

/** Events carry no end time (note 38): a 2h default, and the note says so. Same as iOS. */
export const DEFAULT_DURATION_MS = 2 * 3600 * 1000;

/** { title, start, end, location, url, notes, endIsEstimated } or null when there's no start time. */
export function calendarDraft({ title, start, end, location, eventKey, origin }, T) {
  if (start == null) return null;
  const realEnd = end != null && end > start ? end : null;
  const url = eventKey ? `${origin}/api/photo-share?eid=${encodeURIComponent(eventKey)}` : null;
  const notes = [T('Sự kiện trên banbe.', 'A banbe event.')];
  if (realEnd == null) notes.push(T('Host chưa ghi giờ kết thúc; banbe tạm đặt 2 giờ, bạn có thể sửa.', "The host didn't list an end time; banbe filled in 2 hours, edit it if needed."));
  if (url) notes.push(url);
  const loc = (location || '').trim();
  return { title, start, end: realEnd ?? start + DEFAULT_DURATION_MS, location: loc || null, url, notes: notes.join('\n'), endIsEstimated: realEnd == null };
}

const pad = (n) => String(n).padStart(2, '0');
/** 20261020T120000Z */
export function icsDate(ms) {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`;
}
/** RFC 5545 TEXT escaping. */
export const icsText = (s) => String(s).replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n');
/** Lines longer than 75 octets are folded (continuation lines start with a space). */
function fold(line) {
  const bytes = new TextEncoder().encode(line);
  if (bytes.length <= 75) return line;
  const out = [];
  let cur = '';
  for (const ch of line) {
    if (new TextEncoder().encode(cur + ch).length > (out.length ? 74 : 75)) { out.push(cur); cur = ch; } else cur += ch;
  }
  out.push(cur);
  return out.join('\r\n ');
}

export function buildIcs(draft, { uid, now = Date.now() } = {}) {
  const lines = [
    'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//banbe//Schedule//EN', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    `UID:${uid || `${draft.start}-${Math.random().toString(36).slice(2)}`}@banbe.app`,
    `DTSTAMP:${icsDate(now)}`,
    `DTSTART:${icsDate(draft.start)}`,
    `DTEND:${icsDate(draft.end)}`,
    `SUMMARY:${icsText(draft.title)}`,
    ...(draft.location ? [`LOCATION:${icsText(draft.location)}`] : []),
    ...(draft.url ? [`URL:${draft.url}`] : []),
    `DESCRIPTION:${icsText(draft.notes)}`,
    'END:VEVENT', 'END:VCALENDAR',
  ];
  return lines.map(fold).join('\r\n') + '\r\n';
}

export function googleCalendarUrl(draft) {
  const p = new URLSearchParams({ action: 'TEMPLATE', text: draft.title, dates: `${icsDate(draft.start)}/${icsDate(draft.end)}`, details: draft.notes });
  if (draft.location) p.set('location', draft.location);
  return `https://calendar.google.com/calendar/render?${p.toString()}`;
}

/** Downloads the .ics (the calendar app the person chooses opens it). */
export function downloadIcs(draft, filename = 'banbe-event.ics', opts) {
  const blob = new Blob([buildIcs(draft, opts)], { type: 'text/calendar;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = filename;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
}

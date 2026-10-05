// Serves a single-event .ics built purely from the query string. The gift
// ticket PDF links here through `webcal://`, which is the one link scheme that
// makes Apple Calendar offer to add an event straight from a PDF (a PDF cannot
// carry a downloadable .ics file itself). Nothing is read from or written to the
// database: the event details are the ones the purchaser's own PDF already shows.
//
//   ?title=&start=<unix seconds>&end=<unix seconds>&loc=&desc=&uid=

const MAX_TEXT = 500;

function clean(value, max = MAX_TEXT) {
  const v = Array.isArray(value) ? value[0] : value;
  return typeof v === 'string' ? v.replace(/[\r\u0000-\u0008\u000b-\u001f]/g, ' ').trim().slice(0, max) : '';
}

function escapeText(str) {
  return str
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\;')
    .replace(/,/g, '\\,')
    .replace(/\n/g, '\\n');
}

function icsDate(seconds) {
  return new Date(seconds * 1000).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
}

export default function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.setHeader('Allow', 'GET, HEAD');
    return res.status(405).end();
  }
  const title = clean(req.query.title, 200);
  const start = Number.parseInt(clean(req.query.start, 12), 10);
  let end = Number.parseInt(clean(req.query.end, 12), 10);
  if (!title || !Number.isFinite(start) || start < 0) return res.status(400).send('Bad event');
  if (!Number.isFinite(end) || end <= start) end = start + 2 * 3600;

  const uid = clean(req.query.uid, 80).replace(/[^A-Za-z0-9-]/g, '') || `${start}-${title.length}`;
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//banbe//banbe web//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    `UID:${uid}@banbe`,
    `DTSTAMP:${icsDate(Math.floor(Date.now() / 1000))}`,
    `DTSTART:${icsDate(start)}`,
    `DTEND:${icsDate(end)}`,
    `SUMMARY:${escapeText(title)}`,
  ];
  const desc = clean(req.query.desc);
  const loc = clean(req.query.loc, 300);
  if (desc) lines.push(`DESCRIPTION:${escapeText(desc)}`);
  if (loc) lines.push(`LOCATION:${escapeText(loc)}`);
  lines.push('STATUS:CONFIRMED', 'END:VEVENT', 'END:VCALENDAR');

  res.setHeader('Content-Type', 'text/calendar; charset=utf-8');
  res.setHeader('Content-Disposition', 'inline; filename="banbe-event.ics"');
  res.setHeader('Cache-Control', 'public, max-age=3600');
  return res.status(200).send(lines.join('\r\n') + '\r\n');
}

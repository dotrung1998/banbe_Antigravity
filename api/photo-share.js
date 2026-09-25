import { createClient } from '@supabase/supabase-js';
import { getRedirectUrl } from './_lib/authLookup.js';
import { escapeHtml } from './_lib/emailTemplate.js';

// The page a shared photo link points at. Its only job is to carry Open
// Graph tags naming *that photo* as the preview image, then send whoever
// opened it into the app at the organizer's page.
//
// Sharing the app's own URL instead (which is what this replaces) left
// WhatsApp/Messages/etc. to scrape index.html, which has no OG tags at
// all — so every shared photo previewed as the site favicon, a black
// square with the banbe mark, rather than the photo someone chose to
// share. Crawlers read the tags below and never run the redirect; people
// never see this page for more than an instant.
//
// Two distinct photo sources share this one endpoint (per the Pulse
// photo-ranking ticket's own "do not invent a second incompatible URL
// scheme" instruction), picked by which query params are present:
//   ?photo=<filename>&org=<eventKey>&by=<name>  — the bundled STATIC demo
//     catalogue (src/data/events.js), served from /photos/<filename>.
//   ?pid=<event_photo uuid>                      — a REAL `event_photos`
//     Storage row (Banbe Pulse's photo-ranking tab). Resolved via a live,
//     anon-key lookup (event_photos/events/organizers are all public-select
//     under RLS already — see 001/079) rather than trusting a client-
//     supplied path/event-key pair, so this can't be pointed at an event
//     that photo doesn't actually belong to.

// Only ever our own files under /photos: a filename, nothing path-like,
// so this can't be pointed at an arbitrary image on another host.
const PHOTO_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,80}\.(jpe?g|png|webp)$/i;
const EVENT_KEY_PATTERN = /^[a-z0-9]{1,40}$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function getText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

// Same public anon-key fallback api/payment-document.js already uses — the
// anon key is meant to be public (RLS-scoped) and is already in the client
// bundle; without the fallback this 404s on a deployment that only set
// VITE_SUPABASE_* at build time, not as an actual Vercel env var.
function anonClient() {
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL
    || 'https://ukchdgdnwytretvqjjqu.supabase.co';
  const anonKey = process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY
    || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVrY2hkZ2Rud3l0cmV0dnFqanF1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg3MjMyMjYsImV4cCI6MjEwNDI5OTIyNn0.TgyEJLTXTZgCa6ulsseY3JlrdSmEfOgqVPNh0nSgu90';
  return createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
}

async function resolveRealPhoto(pid) {
  if (!UUID_PATTERN.test(pid)) return null;
  const { data } = await anonClient()
    .from('event_photos')
    .select('storage_path, events(id, name, organizer_id, organizers(name, verified))')
    .eq('id', pid)
    .maybeSingle();
  if (!data?.events) return null;
  const relative = String(data.storage_path || '').replace(/^event-photos\//, '');
  return {
    eventId: data.events.id,
    organizerName: data.events.organizers?.name || '',
    imagePath: relative,
  };
}

export default async function handler(req, res) {
  const origin = getRedirectUrl(req);
  const pid = getText(req.query?.pid);
  const photo = getText(req.query?.photo);
  const org = getText(req.query?.org);
  const organizerParam = getText(req.query?.by).slice(0, 80);

  let appUrl = EVENT_KEY_PATTERN.test(org) ? `${origin}/?org=${org}` : origin;
  let imageUrl = PHOTO_PATTERN.test(photo) ? `${origin}/photos/${photo}` : `${origin}/banbe-wordmark.png`;
  let organizer = organizerParam;

  if (pid) {
    const real = await resolveRealPhoto(pid);
    if (real) {
      appUrl = `${origin}/?org=${real.eventId}`;
      imageUrl = `${process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || 'https://ukchdgdnwytretvqjjqu.supabase.co'}/storage/v1/object/public/event-photos/${real.imagePath}`;
      organizer = real.organizerName;
    }
  }

  const title = organizer ? `Ảnh của ${organizer} ▪︎ banbe` : 'banbe ▪︎ bạn mới mỗi tuần';
  const description = organizer
    ? `Xem ảnh và các buổi sắp tới của ${organizer} trên banbe.`
    : 'Mỗi tuần một vài buổi hay ho ở Sài Gòn.';

  // No-store: the preview must follow whichever photo was shared, and a
  // cached copy of a previous one would be served under the same path
  // shape for a different query.
  res.setHeader('content-type', 'text/html; charset=utf-8');
  res.setHeader('cache-control', 'public, max-age=0, must-revalidate');

  return res.status(200).send(`<!doctype html>
<html lang="vi">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <title>${escapeHtml(title)}</title>
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="banbe" />
    <meta property="og:title" content="${escapeHtml(title)}" />
    <meta property="og:description" content="${escapeHtml(description)}" />
    <meta property="og:image" content="${escapeHtml(imageUrl)}" />
    <meta property="og:url" content="${escapeHtml(appUrl)}" />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content="${escapeHtml(title)}" />
    <meta name="twitter:description" content="${escapeHtml(description)}" />
    <meta name="twitter:image" content="${escapeHtml(imageUrl)}" />
    <link rel="canonical" href="${escapeHtml(appUrl)}" />
    <script>window.location.replace(${JSON.stringify(appUrl)});</script>
  </head>
  <body style="margin:0;padding:40px 24px;background:#F7F4EC;font-family:system-ui,sans-serif;color:#1B1916;">
    <p style="font-size:15px;line-height:1.6;">
      <a href="${escapeHtml(appUrl)}" style="color:#1B1916;">${escapeHtml(description)}</a>
    </p>
  </body>
</html>`);
}

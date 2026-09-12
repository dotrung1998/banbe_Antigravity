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

// Only ever our own files under /photos: a filename, nothing path-like,
// so this can't be pointed at an arbitrary image on another host.
const PHOTO_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,80}\.(jpe?g|png|webp)$/i;
const EVENT_KEY_PATTERN = /^[a-z0-9]{1,40}$/;

function getText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

export default function handler(req, res) {
  const origin = getRedirectUrl(req);
  const photo = getText(req.query?.photo);
  const org = getText(req.query?.org);
  const organizer = getText(req.query?.by).slice(0, 80);

  const appUrl = EVENT_KEY_PATTERN.test(org) ? `${origin}/?org=${org}` : origin;
  const imageUrl = PHOTO_PATTERN.test(photo) ? `${origin}/photos/${photo}` : `${origin}/banbe-wordmark.png`;

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

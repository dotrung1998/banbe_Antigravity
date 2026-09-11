// Shared HTML shell for every transactional email banbe sends — one place
// for the "warm paper" look (src/theme.js's paper/ink, the same wordmark
// treatment as the app) instead of each endpoint hand-rolling its own
// <p> tags. Keeping every email consistent is most of what keeps them
// from reading as ad-hoc or, worse, phishy.
//
// Deliberately plain, table-based HTML (no external stylesheet, no web
// fonts, no images) — the one thing worse than a plain-looking email is
// one that looks like a template because half its assets got blocked by
// the recipient's mail client.

const PAPER = '#F7F4EC';
const INK = '#1B1916';
const RULE = 'rgba(27,25,22,0.14)';
const MUTED = 'rgba(27,25,22,0.6)';

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[character]));
}

/**
 * @param {object} options
 * @param {string} options.preheader - short hidden preview text (inbox summary line)
 * @param {string} options.eyebrow - small label above the heading, e.g. "Đã điểm danh"
 * @param {string} options.heading - the one big line
 * @param {string[]} options.paragraphs - body copy, already escaped/safe HTML per paragraph
 * @param {{label: string, href: string}} [options.cta] - a single primary button
 * @param {string} [options.code] - a big, spaced-out code (for OTP emails) shown in place of a CTA
 * @param {string} [options.footNote] - small print under the main card (e.g. "if you didn't request this…")
 */
export function renderEmail({ preheader, eyebrow, heading, paragraphs, cta, code, footNote }) {
  const bodyHtml = paragraphs.map((p) => `<p style="margin:0 0 16px;font-size:15px;line-height:1.6;color:${INK};">${p}</p>`).join('');

  const codeHtml = code ? `
    <div style="margin:22px 0;padding:18px 0;text-align:center;background:#FFFFFF;border:1px solid ${RULE};border-radius:12px;">
      <span style="font-family:'SF Mono',Consolas,monospace;font-size:32px;font-weight:700;letter-spacing:8px;color:${INK};">${escapeHtml(code)}</span>
    </div>` : '';

  const ctaHtml = cta ? `
    <div style="margin:24px 0 4px;">
      <a href="${cta.href}" style="display:inline-block;background:${INK};color:${PAPER};text-decoration:none;font-size:15px;font-weight:600;padding:14px 26px;border-radius:999px;">${escapeHtml(cta.label)}</a>
    </div>` : '';

  const footNoteHtml = footNote ? `<p style="margin:20px 0 0;font-size:12.5px;line-height:1.55;color:${MUTED};">${footNote}</p>` : '';

  const html = `<!doctype html>
<html>
  <head><meta charset="utf-8" /><meta name="viewport" content="width=device-width,initial-scale=1" /></head>
  <body style="margin:0;padding:0;background:${PAPER};">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;">${escapeHtml(preheader || '')}</div>
    <div style="max-width:480px;margin:0 auto;padding:40px 24px 32px;">
      <div style="font-family:Georgia,'Times New Roman',serif;font-weight:700;font-size:20px;letter-spacing:-0.01em;color:${INK};margin-bottom:32px;">banbe</div>
      <div style="background:${PAPER};border:1px solid ${RULE};border-radius:16px;padding:28px 26px;">
        ${eyebrow ? `<div style="font-size:11.5px;font-weight:600;letter-spacing:0.03em;color:${MUTED};text-transform:uppercase;margin-bottom:10px;">${escapeHtml(eyebrow)}</div>` : ''}
        <h1 style="margin:0 0 16px;font-family:Georgia,'Times New Roman',serif;font-size:22px;line-height:1.3;color:${INK};font-weight:700;">${escapeHtml(heading)}</h1>
        ${bodyHtml}
        ${codeHtml}
        ${ctaHtml}
        ${footNoteHtml}
      </div>
      <p style="margin:28px 4px 0;font-size:12px;color:${MUTED};">banbe ▪︎ bạn mới mỗi tuần</p>
    </div>
  </body>
</html>`;

  return html;
}

/** Plain-text companion — same content, no markup, for clients that prefer it. */
export function renderEmailText({ heading, paragraphs, cta, code, footNote }) {
  return [
    heading,
    '',
    ...paragraphs.map(stripTags),
    code ? `\nMã: ${code}` : '',
    cta ? `\n${cta.label}: ${cta.href}` : '',
    footNote ? `\n${stripTags(footNote)}` : '',
  ].filter(Boolean).join('\n');
}

function stripTags(html) {
  return String(html).replace(/<[^>]+>/g, '');
}

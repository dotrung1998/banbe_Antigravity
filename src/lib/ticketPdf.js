// Ticket PDFs on the web, matching the iOS ticket page (GiftTicketPDFGenerator.swift).
//
// The page is DRAWN ON A CANVAS and placed in the PDF as an image, because
// jsPDF's built-in fonts have no Vietnamese glyphs ("Nguyễn" would come out
// garbled) while the browser's own text rendering handles them. The QR code is
// drawn at 2x so it scans cleanly off a printout; the "Open in banbe" and
// calendar buttons are real PDF link annotations laid over the image.
import QRCode from 'qrcode';

const W = 1190, H = 1684; // A4 at 2x of 595 x 842 pt
const M = 92;
const INK = '#1C1C1F', MUTED = '#73737A', RULE = '#DEDEE3', ACCENT = '#C95A33', SURFACE = '#F8F8FA';
const FONT = "'Be Vietnam Pro', system-ui, -apple-system, 'Segoe UI', sans-serif";

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function wrapText(ctx, text, maxWidth, maxLines) {
  const words = String(text || '').split(/\s+/).filter(Boolean);
  const lines = [];
  let line = '';
  for (const w of words) {
    const probe = line ? `${line} ${w}` : w;
    if (ctx.measureText(probe).width > maxWidth && line) { lines.push(line); line = w; } else line = probe;
  }
  if (line) lines.push(line);
  if (lines.length > maxLines) { lines.length = maxLines; lines[maxLines - 1] = lines[maxLines - 1].replace(/.{0,2}$/, '…'); }
  return lines;
}

function loadImage(src) {
  return new Promise((resolve) => {
    const im = new Image();
    im.crossOrigin = 'anonymous';
    im.onload = () => resolve(im);
    im.onerror = () => resolve(null); // logo is optional; the ticket still renders
    im.src = src;
  });
}

function drawButton(ctx, rect, label, filled) {
  roundRect(ctx, rect.x, rect.y, rect.w, rect.h, 24);
  if (filled) { ctx.fillStyle = INK; ctx.fill(); } else { ctx.strokeStyle = RULE; ctx.lineWidth = 2; ctx.stroke(); }
  ctx.fillStyle = filled ? '#fff' : INK;
  ctx.font = `600 26px ${FONT}`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(label, rect.x + rect.w / 2, rect.y + rect.h / 2 + 1);
  ctx.textAlign = 'left';
  ctx.textBaseline = 'alphabetic';
}

/**
 * @param {object} t
 * @param {string} t.eventName @param {string} [t.organizer] @param {string} t.whenText @param {string} t.venue
 * @param {string} t.holderName @param {string} t.ticketCode @param {string} t.qrValue  what the door scans
 * @param {string} [t.importUrl]  attendee import link (omit for a ticket with nothing to import)
 * @param {string} [t.calendarUrl] @param {boolean} t.isEN @param {string} t.reference
 * @returns {Promise<Blob>}
 */
export async function renderTicketPdf(t) {
  if (document.fonts?.ready) { try { await document.fonts.ready; } catch { /* fall back to system font */ } }
  const canvas = document.createElement('canvas');
  canvas.width = W; canvas.height = H;
  const ctx = canvas.getContext('2d');
  const L = (vi, en) => (t.isEN ? en : vi);
  const links = []; // { rect, url }

  ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, W, H);

  let y = M;
  const logo = await loadImage('/banbe-wordmark.png');
  if (logo) {
    const lw = 184, lh = (lw * logo.height) / logo.width;
    ctx.drawImage(logo, M, y, lw, lh);
    y += lh;
  } else {
    ctx.fillStyle = INK; ctx.font = `700 44px ${FONT}`; ctx.fillText('banbe', M, y + 40); y += 52;
  }
  const badge = L('VÉ', 'TICKET');
  ctx.font = `700 18px ${FONT}`; ctx.fillStyle = ACCENT;
  if ('letterSpacing' in ctx) ctx.letterSpacing = '2px';
  const bw = ctx.measureText(badge).width;
  ctx.fillText(badge, W - M - bw, y + 6);
  y += 36;
  ctx.fillStyle = RULE; ctx.fillRect(M, y, W - 2 * M, 2);
  y += 60;

  ctx.fillStyle = MUTED; ctx.font = `600 18px ${FONT}`;
  ctx.fillText(L('NGƯỜI SỞ HỮU VÉ', 'TICKET HOLDER'), M, y);
  if ('letterSpacing' in ctx) ctx.letterSpacing = '0px';
  y += 56;
  ctx.fillStyle = INK; ctx.font = `700 50px ${FONT}`;
  ctx.fillText(wrapText(ctx, t.holderName || L('Khách', 'Guest'), W - 2 * M, 1)[0], M, y);
  y += 78;

  // Event card
  const cardH = 262;
  roundRect(ctx, M, y, W - 2 * M, cardH, 28);
  ctx.fillStyle = SURFACE; ctx.fill(); ctx.strokeStyle = RULE; ctx.lineWidth = 2; ctx.stroke();
  const cx = M + 40, cw = W - 2 * M - 80;
  let cy = y + 62;
  ctx.fillStyle = INK; ctx.font = `700 34px ${FONT}`;
  for (const line of wrapText(ctx, t.eventName, cw, 2)) { ctx.fillText(line, cx, cy); cy += 42; }
  cy += 6;
  ctx.font = `400 22px ${FONT}`;
  const row = (label, value, bold) => {
    ctx.fillStyle = MUTED; ctx.font = `400 22px ${FONT}`; ctx.fillText(label, cx, cy);
    const off = ctx.measureText(label).width;
    ctx.fillStyle = INK; ctx.font = `${bold ? 600 : 400} 22px ${FONT}`;
    const lines = wrapText(ctx, value, cw - off, 1);
    ctx.fillText(lines[0] || '', cx + off, cy);
    cy += 36;
  };
  if (t.organizer) row(L('Người tổ chức: ', 'Organized by '), t.organizer);
  row(L('Thời gian: ', 'Date & time '), t.whenText, true);
  row(L('Địa điểm: ', 'Venue: '), t.venue);
  y += cardH + 56;

  // QR — what the door scans
  const qr = 256;
  const qrUrl = await QRCode.toDataURL(t.qrValue, { margin: 1, width: qr * 2, errorCorrectionLevel: 'H' });
  const qrImg = await loadImage(qrUrl);
  const qx = (W - qr) / 2;
  roundRect(ctx, qx - 18, y - 18, qr + 36, qr + 36, 20);
  ctx.fillStyle = '#fff'; ctx.fill(); ctx.strokeStyle = RULE; ctx.lineWidth = 2; ctx.stroke();
  if (qrImg) ctx.drawImage(qrImg, qx, y, qr, qr);
  y += qr + 66;

  if (t.ticketCode) {
    ctx.font = `600 18px ${FONT}`;
    const label = L('MÃ VÀO CỬA  ', 'ENTRY CODE  ');
    ctx.font = `600 18px ${FONT}`; const lw = ctx.measureText(label).width;
    ctx.font = `700 26px ui-monospace, Menlo, Consolas, monospace`; const cw2 = ctx.measureText(t.ticketCode).width;
    const sx = (W - (lw + cw2)) / 2;
    ctx.fillStyle = MUTED; ctx.font = `600 18px ${FONT}`; ctx.fillText(label, sx, y);
    ctx.fillStyle = INK; ctx.font = `700 26px ui-monospace, Menlo, Consolas, monospace`; ctx.fillText(t.ticketCode, sx + lw, y);
    y += 56;
  }

  ctx.fillStyle = MUTED; ctx.font = `400 22px ${FONT}`; ctx.textAlign = 'center';
  ctx.fillText(L('Xuất trình mã QR này ở cửa để vào.', 'Show this QR code at the door to check in.'), W / 2, y);
  ctx.textAlign = 'left';
  y += 60;
  ctx.fillStyle = RULE; ctx.fillRect(M, y, W - 2 * M, 1);
  y += 40;

  // Actions: real links only.
  if (t.calendarUrl) {
    const r = { x: M, y, w: W - 2 * M, h: 76 };
    drawButton(ctx, r, L('Thêm vào Google Calendar', 'Add to Google Calendar'), false);
    links.push({ rect: r, url: t.calendarUrl });
    y += 76 + 24;
  }
  if (t.importUrl) {
    const r = { x: M, y, w: W - 2 * M, h: 76 };
    drawButton(ctx, r, L('Mở trong banbe · Đăng ký & nhập vé', 'Open in banbe · Register & import'), true);
    links.push({ rect: r, url: t.importUrl });
    y += 76 + 18;
    ctx.fillStyle = MUTED; ctx.font = `400 20px ${FONT}`; ctx.textAlign = 'center';
    ctx.fillText(L('Bạn vẫn có thể vào cửa chỉ với mã QR này, không cần tài khoản.', 'You can attend with just this QR — no account needed.'), W / 2, y + 8);
    ctx.textAlign = 'left';
  }

  // Footer
  const fy = H - M;
  ctx.fillStyle = RULE; ctx.fillRect(M, fy - 34, W - 2 * M, 1);
  ctx.fillStyle = MUTED; ctx.font = `400 18px ${FONT}`;
  ctx.fillText(`banbe · ${L('Mã vé', 'Ticket')} ${t.reference}`, M, fy);

  const { jsPDF } = await import('jspdf');
  const doc = new jsPDF({ unit: 'pt', format: 'a4', compress: true });
  doc.addImage(canvas.toDataURL('image/png'), 'PNG', 0, 0, 595, 842, undefined, 'FAST');
  for (const { rect, url } of links) doc.link(rect.x / 2, rect.y / 2, rect.w / 2, rect.h / 2, { url });
  return doc.output('blob');
}

function saveBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = filename;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
}

/** One ticket → one PDF. Several → ONE zip of PDFs (a browser would otherwise
 *  block or prompt on a burst of separate downloads). */
export async function downloadTicketPdfs(tickets, zipName = 'banbe-tickets.zip') {
  const files = [];
  for (const t of tickets) files.push({ name: `banbe-ticket-${t.ticketCode || t.reference}.pdf`, blob: await renderTicketPdf(t) });
  if (files.length === 1) return saveBlob(files[0].blob, files[0].name);
  const { default: JSZip } = await import('jszip');
  const zip = new JSZip();
  for (const f of files) zip.file(f.name, f.blob);
  saveBlob(await zip.generateAsync({ type: 'blob' }), zipName);
}

export function googleCalendarUrl({ title, start, end, location, description }) {
  const p2 = (n) => String(n).padStart(2, '0');
  const d = (x) => `${x.getUTCFullYear()}${p2(x.getUTCMonth() + 1)}${p2(x.getUTCDate())}T${p2(x.getUTCHours())}${p2(x.getUTCMinutes())}${p2(x.getUTCSeconds())}Z`;
  const params = new URLSearchParams({ action: 'TEMPLATE', text: title, dates: `${d(start)}/${d(end)}`, details: description || '', location: location || '' });
  return `https://calendar.google.com/calendar/render?${params.toString()}`;
}

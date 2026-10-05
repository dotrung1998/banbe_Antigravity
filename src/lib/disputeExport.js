// Refund-dispute transcript export (web counterpart of iOS Lib/DisputeExport.swift).
//
// Output: ONE zip containing
//   banbe-refund-dispute-<tag>.pdf   the transcript, drawn on a canvas (jsPDF has
//                                    no Vietnamese glyphs — same approach as ticketPdf.js)
//   banbe-refund-dispute-<tag>.txt   the same transcript as plain text
//   attachments/<n>-<name>.<ext>     the REAL bytes of every attachment, downloaded with
//                                    the caller's own session (storage RLS applies)
// Any attachment that cannot be downloaded fails the WHOLE export — an export that
// silently drops a file would be reported as a complete record when it is not.
import { supabase } from './supabase.js';

const BUCKET = 'dispute-attachments';
const W = 1190, H = 1684, M = 80;
const INK = '#1C1C1F', MUTED = '#73737A', RULE = '#DEDEE3';
const FONT = "'Be Vietnam Pro', system-ui, -apple-system, 'Segoe UI', sans-serif";

const EXT = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'application/pdf': 'pdf' };
const sanitize = (s) => String(s || '').replace(/[^A-Za-z0-9._-]+/g, '_').slice(0, 40) || 'file';

export function attachmentExtension(mime, path) {
  if (EXT[mime]) return EXT[mime];
  const m = /\.([A-Za-z0-9]{2,5})$/.exec(path || '');
  return m ? m[1].toLowerCase() : 'bin';
}

// Cheap magic-byte check so an HTML/JSON error body is never zipped as a "photo".
export function bytesLookValid(buf, mime) {
  const b = new Uint8Array(buf.slice ? buf.slice(0, 12) : buf);
  if (b.length < 4) return false;
  if (mime === 'image/jpeg') return b[0] === 0xff && b[1] === 0xd8;
  if (mime === 'image/png') return b[0] === 0x89 && b[1] === 0x50;
  if (mime === 'application/pdf') return b[0] === 0x25 && b[1] === 0x50;
  if (mime === 'image/webp') return b[0] === 0x52 && b[1] === 0x49 && b[8] === 0x57;
  return true;
}

function fmt(iso) {
  if (!iso) return '-';
  return new Date(iso).toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh' }) + ' GMT+7';
}

function roleName(m, tr, L) {
  if (m.sender_name) return m.sender_name;
  return m.sender_role === 'guest' ? L('Khách', 'Guest') : m.sender_role === 'organizer' ? L('Người tổ chức', 'Organizer') : 'banbe';
}

function planFiles(tr) {
  const files = [];
  let n = 0;
  for (const m of tr.messages || []) {
    if (!m.attachment_path) continue;
    n += 1;
    const base = sanitize((m.attachment_path.split('/').pop() || '').replace(/\.[^.]+$/, '')).slice(0, 12);
    files.push({ message: m, path: m.attachment_path, mime: m.attachment_type, zipName: `attachments/${String(n).padStart(2, '0')}-${base}.${attachmentExtension(m.attachment_type, m.attachment_path)}` });
  }
  return files;
}

export function transcriptText(tr, files, L) {
  const lines = [];
  lines.push(L('BẢN GHI TRANH CHẤP HOÀN TIỀN — banbe', 'REFUND DISPUTE TRANSCRIPT — banbe'));
  lines.push(`${L('Sự kiện', 'Event')}: ${tr.event_name || '-'}`);
  lines.push(`${L('Người tổ chức', 'Organizer')}: ${tr.organizer_label || tr.organizer_name || '-'}`);
  lines.push(`${L('Khách', 'Guest')}: ${tr.guest_label || '-'}`);
  if (tr.booking_code) lines.push(`${L('Mã đặt chỗ', 'Booking code')}: ${tr.booking_code}`);
  if (tr.amount_vnd != null) lines.push(`${L('Số tiền', 'Amount')}: ${Number(tr.amount_vnd).toLocaleString('vi-VN')} VND`);
  if (tr.claim_reason) lines.push(`${L('Lý do', 'Reason')}: ${tr.claim_reason}`);
  lines.push(`${L('Mở lúc', 'Opened')}: ${fmt(tr.disputed_at)}`);
  lines.push(`${L('Xuất lúc', 'Exported')}: ${fmt(tr.exported_at)}`);
  lines.push('');
  const byMsg = new Map(files.map(f => [f.message.id, f]));
  for (const m of tr.messages || []) {
    lines.push(`[${fmt(m.created_at)}] ${roleName(m, tr, L)}`);
    const f = byMsg.get(m.id);
    if (f) lines.push(`  ${L('Tệp đính kèm', 'Attachment')}: ${f.zipName}`);
    if (m.body && !(f && /^Sent a (photo|file)$/.test(m.body))) lines.push(`  ${m.body}`);
    lines.push('');
  }
  if (tr.attachment_notice) lines.push(tr.attachment_notice);
  return lines.join('\n');
}

function wrap(ctx, text, maxW) {
  const out = [];
  for (const para of String(text || '').split('\n')) {
    let line = '';
    for (const w of para.split(/\s+/).filter(Boolean)) {
      const probe = line ? `${line} ${w}` : w;
      if (ctx.measureText(probe).width > maxW && line) { out.push(line); line = w; } else line = probe;
    }
    out.push(line);
  }
  return out;
}

// Paginated canvas rendering of the transcript, one canvas per A4 page.
function renderPages(tr, files, L, images) {
  const pages = [];
  let canvas, ctx, y;
  const newPage = () => {
    canvas = document.createElement('canvas');
    canvas.width = W; canvas.height = H;
    ctx = canvas.getContext('2d');
    ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, W, H);
    ctx.textBaseline = 'alphabetic';
    pages.push(canvas);
    y = M;
  };
  const ensure = (h) => { if (y + h > H - M) newPage(); };
  const text = (s, size, { weight = 400, color = INK, gap = 8, indent = 0 } = {}) => {
    ctx.font = `${weight} ${size}px ${FONT}`;
    ctx.fillStyle = color;
    for (const ln of wrap(ctx, s, W - 2 * M - indent)) {
      ensure(size * 1.4);
      y += size * 1.2;
      ctx.fillText(ln, M + indent, y);
      y += size * 0.2;
    }
    y += gap;
  };
  newPage();
  text(L('Bản ghi tranh chấp hoàn tiền', 'Refund dispute transcript'), 44, { weight: 700, gap: 14 });
  const meta = [
    [L('Sự kiện', 'Event'), tr.event_name],
    [L('Người tổ chức', 'Organizer'), tr.organizer_label || tr.organizer_name],
    [L('Khách', 'Guest'), tr.guest_label],
    [L('Mã đặt chỗ', 'Booking code'), tr.booking_code],
    [L('Số tiền', 'Amount'), tr.amount_vnd != null ? `${Number(tr.amount_vnd).toLocaleString('vi-VN')} VND` : null],
    [L('Lý do', 'Reason'), tr.claim_reason],
    [L('Mở lúc', 'Opened'), fmt(tr.disputed_at)],
    [L('Xuất lúc', 'Exported'), fmt(tr.exported_at)],
  ].filter(([, v]) => v);
  for (const [k, v] of meta) text(`${k}: ${v}`, 24, { gap: 4 });
  y += 10;
  ctx.strokeStyle = RULE; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(M, y); ctx.lineTo(W - M, y); ctx.stroke(); y += 24;

  const byMsg = new Map(files.map(f => [f.message.id, f]));
  for (const m of tr.messages || []) {
    ensure(90);
    text(`${fmt(m.created_at)}  ▪  ${roleName(m, tr, L)}`, 20, { color: MUTED, gap: 4 });
    const f = byMsg.get(m.id);
    if (m.body && !(f && /^Sent a (photo|file)$/.test(m.body))) text(m.body, 26, { gap: 6 });
    if (f) {
      const img = images.get(f.zipName);
      if (img) {
        const maxW = 520, maxH = 420;
        const r = Math.min(maxW / img.width, maxH / img.height, 1);
        const w = img.width * r, h = img.height * r;
        ensure(h + 16);
        ctx.drawImage(img, M, y, w, h);
        y += h + 8;
      }
      text(`${L('Tệp đính kèm', 'Attachment')}: ${f.zipName}`, 20, { color: MUTED, gap: 14 });
    } else y += 8;
  }
  if (tr.attachment_notice) { y += 8; text(tr.attachment_notice, 19, { color: MUTED }); }
  // page footers
  pages.forEach((c, i) => {
    const g = c.getContext('2d');
    g.font = `400 18px ${FONT}`; g.fillStyle = MUTED;
    g.fillText(`banbe  ▪  ${i + 1} / ${pages.length}`, M, H - 40);
  });
  return pages;
}

function loadBitmap(blob) {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(blob);
    const im = new Image();
    im.onload = () => { URL.revokeObjectURL(url); resolve(im); };
    im.onerror = () => { URL.revokeObjectURL(url); resolve(null); };
    im.src = url;
  });
}

/**
 * Fetches the transcript RPC and builds the zip. Returns { blob, fileName, attachmentCount }.
 * Throws Error('...') on any failure (RPC refused, attachment missing/invalid).
 */
export async function buildRefundDisputeExport(claimId, lang) {
  const L = (vi, en) => (lang === 'en' ? en : vi);
  const { data: tr, error } = await supabase.rpc('get_refund_dispute_transcript', { p_claim_id: claimId });
  if (error || !tr || tr.found === false) throw new Error('TRANSCRIPT_UNAVAILABLE');
  const files = planFiles(tr);

  const blobs = new Map();
  for (const f of files) {
    const { data, error: dlErr } = await supabase.storage.from(BUCKET).download(f.path);
    if (dlErr || !data) throw new Error('ATTACHMENT_DOWNLOAD_FAILED');
    const buf = await data.arrayBuffer();
    if (!buf.byteLength || !bytesLookValid(buf, f.mime)) throw new Error('ATTACHMENT_INVALID');
    blobs.set(f.zipName, { buf, blob: new Blob([buf], { type: f.mime || 'application/octet-stream' }) });
  }

  const images = new Map();
  for (const f of files) {
    if (f.mime?.startsWith('image/')) {
      const im = await loadBitmap(blobs.get(f.zipName).blob);
      if (im) images.set(f.zipName, im);
    }
  }
  const pages = renderPages(tr, files, L, images);
  const { jsPDF } = await import('jspdf');
  const doc = new jsPDF({ unit: 'pt', format: 'a4', compress: true });
  pages.forEach((c, i) => {
    if (i > 0) doc.addPage();
    doc.addImage(c.toDataURL('image/jpeg', 0.9), 'JPEG', 0, 0, 595, 842, undefined, 'FAST');
  });
  const pdf = doc.output('arraybuffer');

  const tag = String(claimId).slice(0, 8);
  const { default: JSZip } = await import('jszip');
  const zip = new JSZip();
  zip.file(`banbe-refund-dispute-${tag}.pdf`, pdf);
  zip.file(`banbe-refund-dispute-${tag}.txt`, transcriptText(tr, files, L));
  for (const f of files) zip.file(f.zipName, blobs.get(f.zipName).buf);
  const blob = await zip.generateAsync({ type: 'blob' });
  return { blob, fileName: `banbe-refund-dispute-${tag}.zip`, attachmentCount: files.length };
}

export function saveBlob(blob, fileName) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = fileName;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

// Renders a banbe payment document — an invoice (hoá đơn) or a receipt
// (phiếu thu) — as one self-contained HTML page.
//
// Shared deliberately between the app (viewing and printing) and the API
// (emailing a copy), because a document that looks different depending on
// where you opened it is worse than no document. The look is lifted from
// api/_lib/emailTemplate.js: same paper/ink, same Georgia heading over
// system sans, same wordmark, same "banbe ▪︎ bạn mới mỗi tuần" footer. Like
// the emails it uses no web fonts and no external CSS — this gets printed,
// saved as PDF and forwarded through mail clients, and every one of those
// is somewhere a stylesheet fails to load.
//
// WHAT THIS IS NOT: a Vietnamese VAT e-invoice. A legally valid hoá đơn
// điện tử under Nghị định 123/2020/NĐ-CP + Thông tư 78/2021/TT-BTC must be
// issued through a tax-authority-registered provider and carries a mã của
// cơ quan thuế; nothing generated inside an app can have one. banbe also
// never receives the money — the guest pays the organizer directly — so the
// organizer, not banbe, is the seller on every document. Both facts are
// printed on the page rather than left for someone to discover at audit.

const PAPER = '#F7F4EC';
const INK = '#1B1916';
const RULE = 'rgba(27,25,22,0.14)';
const MUTED = 'rgba(27,25,22,0.6)';
const SANS = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif";
const SERIF = "Georgia,'Times New Roman',serif";

export function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

/** 900000 -> "900.000₫". Vietnamese grouping, symbol last, as everywhere else in the app. */
export function formatVnd(amount) {
  const n = Math.round(Number(amount) || 0);
  return n.toLocaleString('vi-VN') + '₫';
}

const DIGITS = ['không', 'một', 'hai', 'ba', 'bốn', 'năm', 'sáu', 'bảy', 'tám', 'chín'];

/**
 * Reads one 0–999 group. `padded` is true for every group after the leading
 * one, which is why 1.050.000 reads "một triệu không trăm năm mươi nghìn"
 * and not "một triệu năm mươi nghìn" — dropping the empty hundreds is
 * exactly the ambiguity the spelled-out amount exists to remove.
 */
function readTriple(n, padded) {
  const hundreds = Math.floor(n / 100);
  const tens = Math.floor((n % 100) / 10);
  const units = n % 10;
  const out = [];

  if (hundreds > 0) out.push(DIGITS[hundreds], 'trăm');
  else if (padded && (tens > 0 || units > 0)) out.push('không', 'trăm');

  if (tens > 1) {
    out.push(DIGITS[tens], 'mươi');
    // The three sound changes every Vietnamese speaker makes and no
    // digit-by-digit reading does: 21 is "hai mươi mốt", 25 "hai mươi lăm",
    // 24 "hai mươi tư".
    if (units === 1) out.push('mốt');
    else if (units === 4) out.push('tư');
    else if (units === 5) out.push('lăm');
    else if (units > 0) out.push(DIGITS[units]);
  } else if (tens === 1) {
    out.push('mười');
    if (units === 5) out.push('lăm');
    else if (units > 0) out.push(DIGITS[units]);
  } else if (units > 0) {
    if (hundreds > 0 || padded) out.push('lẻ');
    out.push(DIGITS[units]);
  }
  return out.join(' ');
}

function scaleName(groupIndex) {
  if (groupIndex === 0) return '';
  const billions = Math.floor(groupIndex / 3);
  const base = ['', 'nghìn', 'triệu'][groupIndex % 3];
  return [base, ...Array(billions).fill('tỷ')].filter(Boolean).join(' ');
}

/**
 * "Số tiền bằng chữ" — the amount spelled out, which Vietnamese payment
 * documents carry as the authoritative figure precisely because digits can
 * be altered after the fact and words are awkward to.
 */
export function amountInWordsVi(amount) {
  const n = Math.floor(Math.abs(Number(amount) || 0));
  if (n === 0) return 'Không đồng';

  const groups = [];
  let rest = n;
  while (rest > 0) { groups.push(rest % 1000); rest = Math.floor(rest / 1000); }

  const parts = [];
  for (let i = groups.length - 1; i >= 0; i -= 1) {
    if (groups[i] === 0) continue;
    const text = readTriple(groups[i], i !== groups.length - 1);
    const scale = scaleName(i);
    parts.push(scale ? `${text} ${scale}` : text);
  }

  const sentence = parts.join(' ').replace(/\s+/g, ' ').trim();
  return sentence.charAt(0).toUpperCase() + sentence.slice(1) + ' đồng';
}

function formatDate(value) {
  if (!value) return '';
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return String(value);
  return `${String(d.getDate()).padStart(2, '0')}.${String(d.getMonth() + 1).padStart(2, '0')}.${d.getFullYear()}`;
}

const PAY_METHOD_LABELS = {
  bank: ['Chuyển khoản ngân hàng', 'Bank transfer'],
  momo: ['Ví MoMo', 'MoMo wallet'],
  cash: ['Tiền mặt', 'Cash'],
  direct: ['Chuyển khoản trực tiếp', 'Direct transfer'],
};

export function payMethodLabel(method, lang = 'vi') {
  const entry = PAY_METHOD_LABELS[String(method || '').toLowerCase()];
  if (!entry) return method || (lang === 'en' ? 'Direct transfer' : 'Chuyển khoản trực tiếp');
  return lang === 'en' ? entry[1] : entry[0];
}

/** Bilingual label, matching the "vi ▪︎ en" pattern the emails already use. */
const L = (vi, en) => `${vi} <span style="color:${MUTED};font-weight:400;">▪︎ ${en}</span>`;

function partyBlock(title, party, extraRows = []) {
  const rows = [
    ['Tên ▪︎ Name', party.name],
    ['Địa chỉ ▪︎ Address', party.address],
    ['Điện thoại ▪︎ Phone', party.phone],
    ['Mã số thuế ▪︎ Tax code', party.tax_code],
    ...extraRows,
  ].filter(([, value]) => String(value ?? '').trim() !== '');

  return `
    <div style="flex:1 1 210px;min-width:200px;">
      <div style="font-size:10.5px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;color:${MUTED};margin-bottom:8px;">${title}</div>
      <table style="width:100%;border-collapse:collapse;font-size:12.5px;line-height:1.5;color:${INK};">
        ${rows.map(([label, value]) => `
        <tr>
          <td style="padding:2px 10px 2px 0;color:${MUTED};white-space:nowrap;vertical-align:top;">${escapeHtml(label)}</td>
          <td style="padding:2px 0;vertical-align:top;">${escapeHtml(value)}</td>
        </tr>`).join('')}
      </table>
    </div>`;
}

/**
 * @param {object} doc - a payment_documents row (see migration 024): kind,
 *   number, issued_at, seller, buyer, event, lines, total_vnd, pay_method,
 *   paid_at, note. Every party and amount is the frozen snapshot taken when
 *   the document was issued, never a live join.
 * @param {object} [options]
 * @param {'vi'|'en'} [options.lang] - only affects the standalone chrome;
 *   the document body stays bilingual, because one copy gets forwarded to
 *   an accountant and the other to a guest.
 * @param {string} [options.origin] - where the wordmark is loaded from.
 * @returns {string} a complete HTML page
 */
export function renderPaymentDocument(doc, options = {}) {
  const { lang = 'vi', origin = 'https://banbe-two.vercel.app' } = options;
  const isReceipt = doc.kind === 'receipt';

  const title = isReceipt ? 'PHIẾU THU' : 'HOÁ ĐƠN';
  const titleEn = isReceipt ? 'Payment receipt' : 'Invoice';

  const seller = doc.seller || {};
  const buyer = doc.buyer || {};
  const event = doc.event || {};
  const lines = Array.isArray(doc.lines) ? doc.lines : [];
  const total = Number(doc.total_vnd) || 0;

  const bankRows = [
    ['Ngân hàng ▪︎ Bank', seller.bank_name],
    ['Số tài khoản ▪︎ Account', seller.bank_account_no],
    ['Chủ tài khoản ▪︎ Account name', seller.bank_account_name],
    ['MoMo', seller.momo_phone],
  ];

  const lineRows = lines.map((line, i) => `
    <tr>
      <td style="padding:10px 8px;border-bottom:1px solid ${RULE};color:${MUTED};">${i + 1}</td>
      <td style="padding:10px 8px;border-bottom:1px solid ${RULE};">${escapeHtml(line.description)}</td>
      <td style="padding:10px 8px;border-bottom:1px solid ${RULE};text-align:center;">${escapeHtml(line.qty)}</td>
      <td style="padding:10px 8px;border-bottom:1px solid ${RULE};text-align:right;white-space:nowrap;">${escapeHtml(formatVnd(line.unit_vnd))}</td>
      <td style="padding:10px 8px;border-bottom:1px solid ${RULE};text-align:right;white-space:nowrap;font-weight:600;">${escapeHtml(formatVnd(line.amount_vnd))}</td>
    </tr>`).join('');

  const metaRows = [
    ['Số ▪︎ No.', doc.number],
    ['Ngày lập ▪︎ Issued', formatDate(doc.issued_at)],
    isReceipt ? ['Ngày thanh toán ▪︎ Paid', formatDate(doc.paid_at)] : null,
    ['Hình thức ▪︎ Method', payMethodLabel(doc.pay_method, lang)],
    event.booking_code ? ['Mã đặt chỗ ▪︎ Booking', event.booking_code] : null,
  ].filter(Boolean);

  // The signature block Vietnamese documents are expected to carry. A
  // receipt is signed by both sides; an invoice has nothing to acknowledge
  // yet, so it only carries the issuer.
  const signatories = isReceipt
    ? [['Người nộp tiền', 'Payer'], ['Người nhận tiền', 'Payee']]
    : [['Người lập phiếu', 'Issued by']];

  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>${escapeHtml(title)} ${escapeHtml(doc.number)} ▪︎ banbe</title>
<style>
  @page { size: A4; margin: 14mm; }
  @media print {
    /* The page already paints its own paper; letting the browser add a
       second background is what produces the grey band down the side. */
    body { background: #FFFFFF; }
    .bb-sheet { box-shadow: none; margin: 0; max-width: none; }
    .bb-noprint { display: none !important; }
  }
</style>
</head>
<body style="margin:0;padding:0;background:${PAPER};font-family:${SANS};-webkit-font-smoothing:antialiased;">
<div class="bb-sheet" style="max-width:720px;margin:0 auto;padding:32px 28px 40px;background:${PAPER};">

  <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:20px;flex-wrap:wrap;">
    <img src="${origin}/banbe-wordmark.png" alt="banbe" width="104" style="display:block;width:104px;height:auto;" />
    <div style="text-align:right;">
      <div style="font-family:${SERIF};font-size:23px;font-weight:700;letter-spacing:0.02em;color:${INK};">${escapeHtml(title)}</div>
      <div style="font-size:11.5px;color:${MUTED};margin-top:3px;">${escapeHtml(titleEn)}</div>
    </div>
  </div>

  <div style="margin-top:26px;border:1px solid ${RULE};border-radius:16px;padding:24px 22px;background:${PAPER};">

    <table style="width:100%;border-collapse:collapse;font-size:12.5px;line-height:1.5;">
      ${metaRows.map(([label, value]) => `
      <tr>
        <td style="padding:2px 12px 2px 0;color:${MUTED};white-space:nowrap;width:1%;">${escapeHtml(label)}</td>
        <td style="padding:2px 0;color:${INK};font-weight:600;">${escapeHtml(value)}</td>
      </tr>`).join('')}
    </table>

    <div style="display:flex;gap:28px;flex-wrap:wrap;margin-top:24px;padding-top:20px;border-top:1px solid ${RULE};">
      ${partyBlock(L('Bên bán', 'Seller'), seller, bankRows)}
      ${partyBlock(L('Bên mua', 'Buyer'), buyer)}
    </div>

    <div style="margin-top:22px;padding-top:18px;border-top:1px solid ${RULE};">
      <div style="font-size:10.5px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;color:${MUTED};margin-bottom:4px;">${L('Sự kiện', 'Event')}</div>
      <div style="font-family:${SERIF};font-size:17px;color:${INK};">${escapeHtml(event.name)}</div>
      <div style="font-size:12px;color:${MUTED};margin-top:3px;">${escapeHtml([formatDate(event.date), event.time, event.area].filter(Boolean).join(' ▪︎ '))}</div>
    </div>

    <table style="width:100%;border-collapse:collapse;margin-top:20px;font-size:12.5px;color:${INK};">
      <thead>
        <tr style="text-align:left;">
          <th style="padding:0 8px 8px;font-size:10.5px;font-weight:700;letter-spacing:0.05em;text-transform:uppercase;color:${MUTED};border-bottom:1px solid ${RULE};width:1%;">STT</th>
          <th style="padding:0 8px 8px;font-size:10.5px;font-weight:700;letter-spacing:0.05em;text-transform:uppercase;color:${MUTED};border-bottom:1px solid ${RULE};">Nội dung ▪︎ Description</th>
          <th style="padding:0 8px 8px;font-size:10.5px;font-weight:700;letter-spacing:0.05em;text-transform:uppercase;color:${MUTED};border-bottom:1px solid ${RULE};text-align:center;">SL</th>
          <th style="padding:0 8px 8px;font-size:10.5px;font-weight:700;letter-spacing:0.05em;text-transform:uppercase;color:${MUTED};border-bottom:1px solid ${RULE};text-align:right;">Đơn giá</th>
          <th style="padding:0 8px 8px;font-size:10.5px;font-weight:700;letter-spacing:0.05em;text-transform:uppercase;color:${MUTED};border-bottom:1px solid ${RULE};text-align:right;">Thành tiền</th>
        </tr>
      </thead>
      <tbody>${lineRows}</tbody>
    </table>

    <div style="display:flex;justify-content:space-between;align-items:baseline;gap:16px;margin-top:16px;">
      <span style="font-size:12.5px;font-weight:600;color:${INK};">${L('Tổng cộng', 'Total')}</span>
      <span style="font-family:${SERIF};font-size:22px;font-weight:700;color:${INK};white-space:nowrap;">${escapeHtml(formatVnd(total))}</span>
    </div>
    <div style="margin-top:6px;font-size:12.5px;line-height:1.55;color:${INK};">
      <span style="color:${MUTED};">${L('Số tiền bằng chữ', 'In words')}:</span> <em>${escapeHtml(amountInWordsVi(total))}</em>
    </div>

    ${isReceipt ? `
    <div style="margin-top:18px;padding:12px 14px;border:1px solid ${RULE};border-radius:12px;font-size:12.5px;line-height:1.55;color:${INK};">
      ${L('Đã nhận đủ số tiền trên', 'The amount above has been received in full')}.
    </div>` : `
    <div style="margin-top:18px;padding:12px 14px;border:1px solid ${RULE};border-radius:12px;font-size:12.5px;line-height:1.55;color:${INK};">
      ${L('Vui lòng chuyển khoản theo thông tin bên bán, ghi nội dung', 'Please transfer using the seller details above, with the reference')}
      <strong>${escapeHtml(event.booking_code || '')}</strong>.
    </div>`}

    ${String(doc.note || '').trim() ? `
    <div style="margin-top:14px;font-size:12px;line-height:1.55;color:${MUTED};">${escapeHtml(doc.note)}</div>` : ''}

    <div style="display:flex;gap:28px;flex-wrap:wrap;margin-top:30px;">
      ${signatories.map(([vi, en]) => `
      <div style="flex:1 1 180px;text-align:center;">
        <div style="font-size:12px;font-weight:600;color:${INK};">${escapeHtml(vi)}</div>
        <div style="font-size:10.5px;color:${MUTED};margin-top:2px;">${escapeHtml(en)}</div>
        <div style="font-size:10px;color:${MUTED};margin-top:2px;">(Ký, ghi rõ họ tên)</div>
        <div style="height:52px;"></div>
        <div style="border-top:1px solid ${RULE};"></div>
      </div>`).join('')}
    </div>
  </div>

  <p style="margin:20px 4px 0;font-size:11px;line-height:1.6;color:${MUTED};">
    Chứng từ này do người tổ chức phát hành qua nền tảng banbe. banbe không thu hộ và không phải một bên của giao dịch.
    Đây <strong>không phải</strong> hoá đơn giá trị gia tăng và không có mã của cơ quan thuế theo Nghị định 123/2020/NĐ-CP.
  </p>
  <p style="margin:8px 4px 0;font-size:11px;line-height:1.6;color:${MUTED};">
    Issued by the organizer through banbe. banbe does not collect payment and is not a party to the transaction.
    This is <strong>not</strong> a Vietnamese VAT e-invoice and carries no tax authority code.
  </p>
  <p style="margin:20px 4px 0;font-size:12px;color:${MUTED};">banbe ▪︎ bạn mới mỗi tuần</p>
</div>
</body>
</html>`;
}

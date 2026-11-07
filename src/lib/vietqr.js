// Dynamic VietQR payload builder — NAPAS's profile of the EMVCo Merchant
// Presented QR spec, which is what every Vietnamese banking app scans.
//
// Built locally rather than fetched from img.vietqr.io or a bank SDK, for
// three reasons that matter here: the QR encodes the organizer's account
// number and the buyer's exact amount, so it has no business round-tripping
// through a third party; a network hop would put an outage between a buyer
// and paying; and the payload is fully deterministic, so it can be unit
// tested instead of eyeballed.
//
// Structure (EMVCo TLV — two-digit tag, two-digit length, value):
//   00 Payload format indicator      = "01"
//   01 Point of initiation           = "12" (dynamic: amount is baked in)
//   38 Merchant account information (NAPAS)
//      00 GUID                       = "A000000727"
//      01 Beneficiary
//         00 Acquirer BIN            (6 digits, identifies the bank)
//         01 Beneficiary account number
//      02 Service code               = "QRIBFTTA" (transfer to account)
//   53 Currency                      = "704" (VND, ISO 4217)
//   54 Amount                        (omitted entirely when zero)
//   58 Country                       = "VN"
//   62 Additional data
//      08 Purpose / transfer memo    <- our ART##### reference lands here
//   63 CRC                           CRC-16/CCITT-FALSE over everything
//                                    including the literal "6304"

/** NAPAS acquirer BINs for the banks a Vietnamese organizer is likely to use. */
export const BANK_BINS = {
  vietcombank: '970436', vcb: '970436',
  techcombank: '970407', tcb: '970407',
  mbbank: '970422', mb: '970422',
  vietinbank: '970415', ctg: '970415',
  bidv: '970418',
  agribank: '970405',
  acb: '970416',
  vpbank: '970432',
  tpbank: '970423',
  sacombank: '970403',
  vib: '970441',
  shb: '970443',
  eximbank: '970431',
  msb: '970426',
  ocb: '970448',
  seabank: '970440',
  hdbank: '970437',
  scb: '970429',
  namabank: '970428',
  bacabank: '970409',
  pvcombank: '970412',
  lpbank: '970449', lienvietpostbank: '970449',
  kienlongbank: '970452',
  abbank: '970425',
  bvbank: '970454', vietcapitalbank: '970454',
  saigonbank: '970400',
  pgbank: '970430',
  baovietbank: '970438',
  ncb: '970419',
  vietabank: '970427',
  vietbank: '970433',
  dongabank: '970406',
  gpbank: '970408',
  oceanbank: '970414',
  cake: '546034',
  ubank: '546035',
  timo: '963388',
  vietteolmoney: '971005', viettelmoney: '971005',
  vnptmoney: '971011',
};

/**
 * Normalises whatever an organizer typed into a bank BIN.
 * Accepts a 6-digit BIN as-is, or a bank name/short code in any casing.
 */
export function resolveBankBin(bank) {
  const raw = String(bank ?? '').trim();
  if (/^\d{6}$/.test(raw)) return raw;
  const key = raw.toLowerCase().replace(/[^a-z0-9]/g, '');
  return BANK_BINS[key] || null;
}

/**
 * CRC-16/CCITT-FALSE: polynomial 0x1021, init 0xFFFF, no input/output
 * reflection, no final XOR. This is the variant EMVCo specifies — the other
 * common CRC-16s (ARC, XMODEM, KERMIT) all produce a different checksum and
 * a QR that every banking app silently refuses.
 */
export function crc16ccitt(input) {
  let crc = 0xffff;
  for (let i = 0; i < input.length; i += 1) {
    crc ^= input.charCodeAt(i) << 8;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc & 0x8000) ? ((crc << 1) ^ 0x1021) : (crc << 1);
      crc &= 0xffff;
    }
  }
  return crc.toString(16).toUpperCase().padStart(4, '0');
}

/** One EMVCo TLV field. Length is a two-digit decimal count of characters. */
function tlv(tag, value) {
  const v = String(value ?? '');
  if (v.length > 99) throw new Error(`VietQR field ${tag} too long (${v.length})`);
  return `${tag}${String(v.length).padStart(2, '0')}${v}`;
}

/**
 * Vietnamese banks mangle transfer memos: many strip diacritics and
 * punctuation, uppercase the result and truncate it. Sending only what
 * survives that means the reference we later match on is the reference the
 * bank actually reports back through the webhook.
 */
export function sanitizeMemo(memo) {
  return String(memo ?? '')
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/đ/g, 'd').replace(/Đ/g, 'D')
    .replace(/[^A-Za-z0-9 ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .toUpperCase()
    .slice(0, 25);
}

/**
 * @param {object} o
 * @param {string} o.bank          bank name, short code, or 6-digit BIN
 * @param {string} o.accountNumber beneficiary account number
 * @param {number} [o.amountVnd]   exact amount; omitted from the QR when 0
 * @param {string} [o.memo]        transfer reference, e.g. "ART10492"
 * @returns {string} the QR payload string to render as a QR code
 */
export function buildVietQrPayload({ bank, accountNumber, amountVnd = 0, memo = '' }) {
  const bin = resolveBankBin(bank);
  if (!bin) throw new Error(`Unknown bank: ${bank}`);

  const account = String(accountNumber ?? '').replace(/\s+/g, '');
  if (!/^\d{4,19}$/.test(account)) throw new Error('Invalid account number');

  const beneficiary = tlv('00', bin) + tlv('01', account);
  const merchantAccount = tlv('00', 'A000000727') + tlv('01', beneficiary) + tlv('02', 'QRIBFTTA');

  let payload =
    tlv('00', '01') +
    tlv('01', '12') +
    tlv('38', merchantAccount) +
    tlv('53', '704');

  // A zero amount must be omitted, not sent as "0" — a present-but-zero
  // amount field makes some banking apps reject the code outright.
  const amount = Math.round(Number(amountVnd) || 0);
  if (amount > 0) payload += tlv('54', String(amount));

  payload += tlv('58', 'VN');

  const cleanMemo = sanitizeMemo(memo);
  if (cleanMemo) payload += tlv('62', tlv('08', cleanMemo));

  // The CRC covers the "6304" prefix itself, so it is appended before hashing.
  const withCrcTag = `${payload}6304`;
  return withCrcTag + crc16ccitt(withCrcTag);
}

/** Parses an EMVCo payload back into a tag map — used to verify our own output. */
export function parseEmvco(payload) {
  const out = {};
  let i = 0;
  while (i + 4 <= payload.length) {
    const tag = payload.slice(i, i + 2);
    const len = parseInt(payload.slice(i + 2, i + 4), 10);
    if (Number.isNaN(len)) break;
    out[tag] = payload.slice(i + 4, i + 4 + len);
    i += 4 + len;
  }
  return out;
}

/** True when the payload's trailing CRC matches its own contents. */
export function verifyVietQrChecksum(payload) {
  if (payload.length < 8) return false;
  const body = payload.slice(0, -4);
  const claimed = payload.slice(-4).toUpperCase();
  return body.endsWith('6304') && crc16ccitt(body) === claimed;
}

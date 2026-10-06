// Server-side image gatekeeper: decides the REAL format from magic bytes (the
// declared MIME type is never trusted), reads the REAL pixel dimensions from
// the container header, and rewrites the file without EXIF / XMP / GPS / text
// metadata. Pure JS, no dependencies, lossless (pixel data is copied verbatim).
// Throws Error('IMAGE_*') codes; callers map them to 4xx.

const err = (code) => new Error(code);

function sniff(buf) {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'jpeg';
  if (buf.length >= 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'png';
  if (buf.length >= 12 && buf.toString('latin1', 0, 4) === 'RIFF' && buf.toString('latin1', 8, 12) === 'WEBP') return 'webp';
  return null;
}

// ---------- JPEG ----------
function cleanJpeg(buf) {
  const out = [buf.subarray(0, 2)];
  let i = 2, width = 0, height = 0, sawEoi = false;
  while (i < buf.length) {
    if (buf[i] !== 0xff) throw err('IMAGE_CORRUPT');
    while (buf[i] === 0xff) i++;                       // fill bytes
    const marker = buf[i++];
    if (marker === 0xd9) { out.push(Buffer.from([0xff, 0xd9])); sawEoi = true; break; }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) { out.push(Buffer.from([0xff, marker])); continue; }
    if (i + 2 > buf.length) throw err('IMAGE_CORRUPT');
    const len = buf.readUInt16BE(i);
    if (len < 2 || i + len > buf.length) throw err('IMAGE_CORRUPT');
    const seg = buf.subarray(i + 2, i + len);
    const isSof = marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker);
    if (isSof) {
      if (seg.length < 6) throw err('IMAGE_CORRUPT');
      height = seg.readUInt16BE(1); width = seg.readUInt16BE(3);
    }
    let keep = true;
    if (marker >= 0xe1 && marker <= 0xef) {            // APP1..APP15: EXIF, XMP, IPTC, GPS…
      keep = marker === 0xee                           // APP14 Adobe: needed for correct colour
        || (marker === 0xe2 && seg.toString('latin1', 0, 11) === 'ICC_PROFILE'); // keep colour profile only
    } else if (marker === 0xfe) keep = false;          // COM
    if (keep) out.push(buf.subarray(i - 2, i + len));  // marker bytes + length + payload
    i += len;
    if (marker === 0xda) {                             // SOS: entropy-coded data until EOI, copied verbatim
      const rest = buf.subarray(i);
      if (rest.length < 2 || rest[rest.length - 2] !== 0xff || rest[rest.length - 1] !== 0xd9) throw err('IMAGE_CORRUPT');
      out.push(rest); sawEoi = true; break;
    }
  }
  if (!sawEoi || !width || !height) throw err('IMAGE_CORRUPT');
  return { width, height, data: Buffer.concat(out) };
}

// ---------- PNG ----------
const PNG_KEEP = new Set(['IHDR', 'PLTE', 'IDAT', 'IEND', 'tRNS', 'gAMA', 'cHRM', 'sRGB', 'iCCP', 'sBIT']);
function cleanPng(buf) {
  const out = [buf.subarray(0, 8)];
  let i = 8, width = 0, height = 0, sawIend = false, first = true;
  while (i + 12 <= buf.length) {
    const len = buf.readUInt32BE(i);
    const type = buf.toString('latin1', i + 4, i + 8);
    const end = i + 12 + len;
    if (end > buf.length) throw err('IMAGE_CORRUPT');
    if (first) {
      if (type !== 'IHDR' || len !== 13) throw err('IMAGE_CORRUPT');
      width = buf.readUInt32BE(i + 8); height = buf.readUInt32BE(i + 12);
      first = false;
    }
    if (type === 'acTL') throw err('IMAGE_ANIMATED');
    if (PNG_KEEP.has(type)) out.push(buf.subarray(i, end));
    i = end;
    if (type === 'IEND') { sawIend = true; break; }
  }
  if (!sawIend || !width || !height) throw err('IMAGE_CORRUPT');
  return { width, height, data: Buffer.concat(out) };
}

// ---------- WebP ----------
function cleanWebp(buf) {
  const riffLen = buf.readUInt32LE(4);
  if (riffLen + 8 > buf.length || riffLen < 4) throw err('IMAGE_CORRUPT');
  const end = riffLen + 8;
  let i = 12, width = 0, height = 0;
  const chunks = [];
  while (i + 8 <= end) {
    const type = buf.toString('latin1', i, i + 4);
    const len = buf.readUInt32LE(i + 4);
    const dataStart = i + 8, dataEnd = dataStart + len;
    if (dataEnd > end) throw err('IMAGE_CORRUPT');
    const padded = dataEnd + (len & 1);
    const data = buf.subarray(dataStart, dataEnd);
    if (type === 'ANIM' || type === 'ANMF') throw err('IMAGE_ANIMATED');
    if (type === 'VP8X') {
      if (len < 10) throw err('IMAGE_CORRUPT');
      width = 1 + (data[4] | (data[5] << 8) | (data[6] << 16));
      height = 1 + (data[7] | (data[8] << 8) | (data[9] << 16));
      const fixed = Buffer.from(data); fixed[0] &= ~(0x08 | 0x04 | 0x02);  // clear EXIF, XMP, animation flags
      chunks.push({ type, data: fixed });
    } else if (type === 'VP8 ') {
      if (len < 10 || data[3] !== 0x9d || data[4] !== 0x01 || data[5] !== 0x2a) throw err('IMAGE_CORRUPT');
      if (!width) { width = data.readUInt16LE(6) & 0x3fff; height = data.readUInt16LE(8) & 0x3fff; }
      chunks.push({ type, data });
    } else if (type === 'VP8L') {
      if (len < 5 || data[0] !== 0x2f) throw err('IMAGE_CORRUPT');
      if (!width) {
        const bits = data.readUInt32LE(1);
        width = (bits & 0x3fff) + 1; height = ((bits >> 14) & 0x3fff) + 1;
      }
      chunks.push({ type, data });
    } else if (type === 'EXIF' || type === 'XMP ') {
      // dropped
    } else {
      chunks.push({ type, data });
    }
    i = padded;
  }
  if (!width || !height || !chunks.some((c) => ['VP8 ', 'VP8L'].includes(c.type))) throw err('IMAGE_CORRUPT');
  const body = Buffer.concat(chunks.map((c) => {
    const head = Buffer.alloc(8); head.write(c.type, 0, 'latin1'); head.writeUInt32LE(c.data.length, 4);
    return Buffer.concat([head, c.data, c.data.length & 1 ? Buffer.from([0]) : Buffer.alloc(0)]);
  }));
  const riff = Buffer.alloc(12); riff.write('RIFF', 0, 'latin1'); riff.writeUInt32LE(body.length + 4, 4); riff.write('WEBP', 8, 'latin1');
  return { width, height, data: Buffer.concat([riff, body]) };
}

const EXT = { jpeg: 'jpg', png: 'png', webp: 'webp' };
const MIME = { jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };

/** @returns {{format, ext, mime, width, height, data: Buffer}} metadata-stripped copy */
export function inspectImage(buf, { maxBytes = 8 * 1024 * 1024, maxLongEdge = 8192, maxPixels = 40_000_000 } = {}) {
  if (!Buffer.isBuffer(buf) || buf.length < 16) throw err('IMAGE_CORRUPT');
  if (buf.length > maxBytes) throw err('IMAGE_TOO_LARGE');
  const format = sniff(buf);
  if (!format) throw err('IMAGE_UNSUPPORTED_FORMAT');
  const r = format === 'jpeg' ? cleanJpeg(buf) : format === 'png' ? cleanPng(buf) : cleanWebp(buf);
  if (Math.max(r.width, r.height) > maxLongEdge || r.width * r.height > maxPixels) throw err('IMAGE_DIMENSIONS_EXCEEDED');
  return { format, ext: EXT[format], mime: MIME[format], width: r.width, height: r.height, data: r.data };
}

export const MIME_TO_EXT = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };

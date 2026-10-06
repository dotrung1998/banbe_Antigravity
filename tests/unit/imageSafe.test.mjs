import test from 'node:test';
import assert from 'node:assert/strict';
import { inspectImage } from '../../api/_lib/imageSafe.js';

const u32be = (n) => { const b = Buffer.alloc(4); b.writeUInt32BE(n); return b; };
function pngChunk(type, data) { return Buffer.concat([u32be(data.length), Buffer.from(type, 'latin1'), data, Buffer.alloc(4)]); }
function png(w, h, extra = []) {
  const ihdr = Buffer.concat([u32be(w), u32be(h), Buffer.from([8, 2, 0, 0, 0])]);
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), pngChunk('IHDR', ihdr), ...extra, pngChunk('IDAT', Buffer.from([1, 2, 3])), pngChunk('IEND', Buffer.alloc(0))]);
}
function riff(chunks) {
  const body = Buffer.concat(chunks.map(([t, d]) => { const h = Buffer.alloc(8); h.write(t, 0, 'latin1'); h.writeUInt32LE(d.length, 4); return Buffer.concat([h, d, d.length & 1 ? Buffer.from([0]) : Buffer.alloc(0)]); }));
  const h = Buffer.alloc(12); h.write('RIFF', 0, 'latin1'); h.writeUInt32LE(body.length + 4, 4); h.write('WEBP', 8, 'latin1');
  return Buffer.concat([h, body]);
}
const vp8l = (w, h) => { const d = Buffer.alloc(5); d[0] = 0x2f; d.writeUInt32LE(((w - 1) & 0x3fff) | (((h - 1) & 0x3fff) << 14), 1); return d; };

test('png: real dimensions read, text/exif chunks stripped, pixel chunks kept', () => {
  const r = inspectImage(png(64, 32, [pngChunk('tEXt', Buffer.from('GPS=secret')), pngChunk('eXIf', Buffer.from('exif'))]));
  assert.equal(r.format, 'png'); assert.equal(r.width, 64); assert.equal(r.height, 32);
  assert.ok(!r.data.includes(Buffer.from('GPS=secret'))); assert.ok(!r.data.includes(Buffer.from('eXIf')));
  assert.ok(r.data.includes(Buffer.from('IDAT')));
});
test('png: truncated / animated rejected', () => {
  assert.throws(() => inspectImage(png(8, 8).subarray(0, 40)), /IMAGE_CORRUPT/);
  assert.throws(() => inspectImage(png(8, 8, [pngChunk('acTL', Buffer.alloc(8))])), /IMAGE_ANIMATED/);
});
test('webp: VP8X exif/xmp chunks dropped and flags cleared', () => {
  const vp8x = Buffer.alloc(10); vp8x[0] = 0x08 | 0x04; vp8x[4] = 15; vp8x[7] = 7;   // 16x8
  const buf = riff([['VP8X', vp8x], ['VP8L', vp8l(16, 8)], ['EXIF', Buffer.from('GPS-SECRET')], ['XMP ', Buffer.from('xmp')]]);
  const r = inspectImage(buf);
  assert.equal(r.format, 'webp'); assert.equal(r.width, 16); assert.equal(r.height, 8);
  assert.ok(!r.data.includes(Buffer.from('GPS-SECRET')));
  assert.equal(r.data[12 + 8] & 0x0c, 0);                  // VP8X flags cleared
  assert.equal(r.data.readUInt32LE(4) + 8, r.data.length);  // RIFF size consistent
});
test('size / dimension / format limits', () => {
  assert.throws(() => inspectImage(png(9000, 10)), /IMAGE_DIMENSIONS_EXCEEDED/);
  assert.throws(() => inspectImage(png(8, 8), { maxBytes: 20 }), /IMAGE_TOO_LARGE/);
  assert.throws(() => inspectImage(Buffer.from('GIF89a'.padEnd(40, 'x'))), /IMAGE_UNSUPPORTED_FORMAT/);
  assert.throws(() => inspectImage(Buffer.from('MZ'.padEnd(40, '\0'))), /IMAGE_UNSUPPORTED_FORMAT/);
});

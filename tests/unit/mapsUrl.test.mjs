import test from 'node:test';
import assert from 'node:assert/strict';
import { mapsUrl } from '../../src/data/events.js';

test('mapsUrl sends the verified street address, not coordinates', () => {
  const url = mapsUrl({
    name: 'Chợ Phiên Sân Thượng', addressLine: '12 Nguyễn Văn Đậu',
    area: 'Bình Thạnh', city: 'TP. Hồ Chí Minh', lat: 10.79, lng: 106.69,
  });
  assert.equal(url.startsWith('https://www.google.com/maps/search/?api=1&query='), true);
  const query = new URL(url).searchParams.get('query');
  assert.equal(query, 'Chợ Phiên Sân Thượng, 12 Nguyễn Văn Đậu, Bình Thạnh, TP. Hồ Chí Minh');
  assert.equal(query.includes('10.79'), false);
});

test('mapsUrl keeps exact coordinates when the event has no street address', () => {
  assert.equal(
    mapsUrl({ name: 'Chợ Phiên Sân Thượng', area: 'Quận 1', lat: 10.771408, lng: 106.698212 }),
    'https://www.google.com/maps/search/?api=1&query=10.771408,106.698212',
  );
});

test('mapsUrl is null without confirmed coordinates', () => {
  assert.equal(mapsUrl({ name: 'Somewhere', addressLine: '1 Lê Lợi' }), null);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { zoomToLngSpan, lngSpanToZoom, shapeMapKitPlace } from '../../src/lib/mapkitAdapter.js';

test('zoom <-> longitude span round-trips', () => {
  for (const z of [3, 10, 13, 15.5, 18]) assert.ok(Math.abs(lngSpanToZoom(zoomToLngSpan(z, 390), 390) - z) < 1e-9);
});

test('place with house number + street becomes a street address', () => {
  const r = shapeMapKitPlace({ subThoroughfare: '123', thoroughfare: 'Vĩnh Hội', subLocality: 'Khánh Hội', locality: 'Quận 4', administrativeArea: 'Hồ Chí Minh', countryCode: 'vn', postCode: '72821', coordinate: { latitude: 10.76, longitude: 106.7 } });
  assert.equal(r.addressLine, '123 Vĩnh Hội'); assert.equal(r.district, 'Khánh Hội'); assert.equal(r.city, 'Hồ Chí Minh');
  assert.equal(r.countryCode, 'VN'); assert.equal(r.isVenue, false); assert.equal(r.label, '123 Vĩnh Hội, Khánh Hội, Hồ Chí Minh');
});

test('named venue without house number is a venue; bare result is rejected', () => {
  const base = { locality: 'Quận 1', administrativeArea: 'Hồ Chí Minh', coordinate: { latitude: 1, longitude: 2 } };
  assert.equal(shapeMapKitPlace({ ...base, name: 'Tao Đàn' }).isVenue, true);
  assert.equal(shapeMapKitPlace({ ...base }), null);
  assert.equal(shapeMapKitPlace({ name: 'X', coordinate: { latitude: 1, longitude: 2 } }), null);
});

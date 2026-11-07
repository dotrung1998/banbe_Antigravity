// @ts-check
import { test, expect } from '@playwright/test';
import { densityHotspot } from '../src/lib/densityHotspot.js';

test.describe('densityHotspot', () => {
  test('returns null for no usable points', () => {
    expect(densityHotspot([])).toBeNull();
    expect(densityHotspot(null)).toBeNull();
    expect(densityHotspot([{ lat: null, lng: 106.7 }])).toBeNull();
  });

  test('a single point is its own hotspot', () => {
    expect(densityHotspot([{ lat: 10.77, lng: 106.70 }])).toEqual({ lat: 10.77, lng: 106.70 });
  });

  test('picks the densest cluster, not a lone outlier', () => {
    const cluster = [
      { lat: 10.770, lng: 106.700 },
      { lat: 10.771, lng: 106.701 },
      { lat: 10.769, lng: 106.699 },
    ];
    const outlier = [{ lat: 21.028, lng: 105.804 }]; // Hanoi — far away, alone
    const hotspot = densityHotspot([...cluster, ...outlier]);
    // Centroid of the 3-point cluster, not anywhere near the lone outlier.
    expect(hotspot.lat).toBeCloseTo(10.770, 2);
    expect(hotspot.lng).toBeCloseTo(106.700, 2);
  });

  test('ties broken by first-seen bin (stable, not random)', () => {
    const a = densityHotspot([{ lat: 10.7, lng: 106.7 }, { lat: 11.5, lng: 107.5 }]);
    expect(a).toEqual({ lat: 10.7, lng: 106.7 });
  });
});

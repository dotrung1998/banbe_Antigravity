// Map redesign phase 2: one committed geography drives pins, list and count. Shared fixture with iOS
// MapDiscoveryTests.swift.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  reasonCommits, referenceRect, boundsForRect, inBounds, mapResults, selectionAfter, pointsNear, fitCamera,
  boundsOfPoints, mercY, latFromMercY,
} from '../../src/lib/mapDiscovery.js';

const fx = JSON.parse(readFileSync(new URL('../fixtures/map-discovery.json', import.meta.url), 'utf8'));
const near = (a, b, msg) => assert.ok(Math.abs(a - b) < 1e-6, `${msg}: ${a} vs ${b}`);

test('only geographic navigation commits a new search area', () => {
  for (const c of fx.reasons) assert.equal(reasonCommits(c.reason), c.commits, c.reason);
});

test('reference rect: below the controls, above the peek sheet', () => {
  for (const c of fx.referenceRect) assert.deepEqual(referenceRect(c.in), c.expect, c.name);
});

test('bounds of a px rect follow Mercator', () => {
  for (const c of fx.boundsForRect) {
    const got = boundsForRect(c.full, c.size, c.rect);
    for (const k of ['north', 'south', 'east', 'west']) near(got[k], c.expect[k], `${c.name} ${k}`);
  }
});

test('inBounds, including a box across the antimeridian', () => {
  for (const c of fx.inBounds) assert.equal(inBounds(c.ev, c.b), c.expect, c.name);
});

test('results come only from the committed area', () => {
  for (const c of fx.mapResults) assert.deepEqual(mapResults(c.events, c.bounds).map(e => e.id), c.expect, c.name);
});

test('selection is kept only while it is still a result', () => {
  for (const c of fx.selectionAfter) assert.equal(selectionAfter(c.selected, c.results), c.expect, c.name);
});

test('first-open cluster stays within one city', () => {
  for (const c of fx.pointsNear) assert.deepEqual(pointsNear(c.points, c.center, c.radiusKm).map(p => p.id), c.expect, c.name);
});

test('fit camera matches the shared numbers', () => {
  for (const c of fx.fitCamera) {
    const got = fitCamera(c.bounds, c.size, c.padding, { tileSize: c.tileSize, maxZoom: c.maxZoom });
    near(got.center.lat, c.expect.lat, `${c.name} lat`);
    near(got.center.lng, c.expect.lng, `${c.name} lng`);
    near(got.zoom, c.expect.zoom, `${c.name} zoom`);
  }
});

test('a fitted box lands entirely inside the free area (above the mid sheet)', () => {
  const size = { width: 390, height: 844 };
  const padding = { top: 68, bottom: 380, left: 30, right: 30 };
  const box = { north: 10.81, south: 10.75, east: 106.74, west: 106.66 };
  const { center, zoom } = fitCamera(box, size, padding);
  // Rebuild the full view from the camera, then take the free area as a rect: it must contain the box.
  const world = 512 * 2 ** zoom;
  const cy = mercY(center.lat);
  const fullView = {
    north: latFromMercY(cy - size.height / 2 / world), south: latFromMercY(cy + size.height / 2 / world),
    west: center.lng - (size.width / 2 / world) * 360, east: center.lng + (size.width / 2 / world) * 360,
  };
  const free = boundsForRect(fullView, size, { top: padding.top, bottom: size.height - padding.bottom, left: padding.left, right: size.width - padding.right });
  const eps = 1e-9;
  assert.ok(free.north + eps >= box.north && free.south - eps <= box.south, 'latitudes inside');
  assert.ok(free.west - eps <= box.west && free.east + eps >= box.east, 'longitudes inside');
});

test('boundsOfPoints ignores rows without coordinates', () => {
  assert.equal(boundsOfPoints([{ lat: null, lng: null }]), null);
  assert.deepEqual(boundsOfPoints([{ lat: 1, lng: 2 }, { lat: 3, lng: 4 }]), { north: 3, south: 1, east: 4, west: 2 });
});

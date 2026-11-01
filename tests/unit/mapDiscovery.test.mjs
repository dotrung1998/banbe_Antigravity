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

test('clusters reduce markers, never results: shared cases', async () => {
  const { clusterPins } = await import('../../src/lib/mapDiscovery.js');
  for (const c of fx.clusterPins) {
    const got = clusterPins(c.points, c.zoom).map(g => [g.kind, g.ids]);
    assert.deepEqual(got, c.expect, c.name);
    assert.equal(got.reduce((n, g) => n + g[1].length, 0), c.points.length, `${c.name}: every result counted once`);
  }
});

test('sameSpot finds the stack of an event; padBounds grows the fetch box', async () => {
  const { sameSpot, padBounds } = await import('../../src/lib/mapDiscovery.js');
  const a = { id: 'a', lat: 10.7769, lng: 106.7009 }, b = { id: 'b', lat: 10.7769, lng: 106.7009 }, c = { id: 'c', lat: 10.78, lng: 106.7 };
  assert.deepEqual(sameSpot([a, c, b], b).map(e => e.id), ['a', 'b']);
  for (const k of fx.padBounds) assert.deepEqual(padBounds(k.b, k.factor), k.expect, k.name);
});

// ---- Map v5 (note 73): cities + the active filter summary (shared with iOS MapDiscoveryTests) ----
const { cities } = JSON.parse(readFileSync(new URL('../../src/data/cities.json', import.meta.url), 'utf8'));

test('cities.json: unique ids, sane boxes, centre inside its own box', () => {
  const ids = new Set();
  for (const c of cities) {
    assert.ok(!ids.has(c.id), c.id); ids.add(c.id);
    assert.ok(c.bounds.north > c.bounds.south && c.bounds.east > c.bounds.west, c.id);
    assert.ok(inBounds(c.center, c.bounds), `${c.id} centre`);
    assert.ok(['VN', 'US'].includes(c.country), c.id);
  }
});

test('cityFor: column names first, then the smallest box that contains the event', async () => {
  const { cityFor } = await import('../../src/lib/mapDiscovery.js');
  for (const k of fx.cityFor) assert.equal(cityFor(k.ev, cities), k.expect, k.name);
});

test('searchCities: accent-free word prefix, most events first, max three', async () => {
  const { searchCities } = await import('../../src/lib/mapDiscovery.js');
  for (const k of fx.searchCities) assert.deepEqual(searchCities(k.query, cities, k.counts), k.expect, k.name);
});

test('cityGroups: one bubble per city when zoomed out, never losing a result', async () => {
  const { cityGroups, cityFor, clusterPins } = await import('../../src/lib/mapDiscovery.js');
  for (const k of fx.cityGroups) {
    const got = cityGroups(k.points, k.zoom, p => cityFor(p, cities), cities);
    assert.equal(got.reduce((s, g) => s + g.ids.length, 0), k.points.length, `${k.name}: count`);
    if (k.expect === 'clusterPins') assert.deepEqual(got, clusterPins(k.points, k.zoom), k.name);
    else assert.deepEqual(got.map(g => ({ kind: g.kind, ...(g.cityId ? { cityId: g.cityId } : {}), ids: g.ids })), k.expect, k.name);
  }
});

test('activeFilterSummary: tokens in reading order with the badge count', async () => {
  const { activeFilterSummary } = await import('../../src/lib/mapDiscovery.js');
  for (const k of fx.activeFilterSummary) assert.deepEqual(activeFilterSummary(k.filters, k.opts), k.expect, k.name);
});

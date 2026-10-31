// Hosting Home guided empty states (Calm Pass pilot). Shared fixture with iOS HostHomeEmptyTests.swift.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { comingUpEmptyVariant, kpiSectionState, kpiRangeHeading } from '../../src/lib/hostHomeEmpty.js';

const fx = JSON.parse(readFileSync(new URL('../fixtures/host-home-empty.json', import.meta.url), 'utf8'));

test('Coming up: the guided state matches the shared cases', () => {
  for (const c of fx.comingUp) assert.equal(comingUpEmptyVariant(c.in), c.expect, c.name);
});

test('numbers section: loading / error / empty / tiles match the shared cases', () => {
  for (const c of fx.kpis) assert.equal(kpiSectionState(c.in), c.expect, c.name);
});

test('numbers heading names the range Reports used, in both languages', () => {
  const en = (_vi, e) => e;
  const vi = (v) => v;
  for (const c of fx.rangeHeading) {
    const range = c.range === 'custom' ? 'custom' : Number(c.range);
    assert.equal(kpiRangeHeading(range, en), c.en, c.range);
    assert.equal(kpiRangeHeading(range, vi), c.vi, c.range);
  }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { buildParticles, particleState, fibonacciSphere, REVEAL_TIMELINE, REVEAL_TOTAL, REVEAL_FLASH_START, flashLevel, mulberry32 } from '../../src/lib/hostReveal.js';
import { HOST_STOCK_COVERS } from '../../src/lib/hostStockCovers.js';

const view = { cx: 200, cy: 300, radius: 90 };
const mk = () => buildParticles({
  count: 300, seed: 3, ...view,
  sources: [{ left: 20, top: 100, width: 360, height: 160 }, { left: 20, top: 700, width: 360, height: 50 }],
  target: { left: 20, top: 120, width: 360, height: 90 },
});

test('fibonacci sphere points lie on the unit sphere', () => {
  for (const p of fibonacciSphere(50)) assert.ok(Math.abs(Math.hypot(p.x, p.y, p.z) - 1) < 1e-9);
});

test('prng is deterministic', () => {
  const a = mulberry32(5), b = mulberry32(5);
  assert.equal(a(), b());
});

test('timeline total is the sum of the phases', () => {
  const t = REVEAL_TIMELINE;
  assert.equal(REVEAL_TOTAL, t.gather + t.form + t.spin + t.coalesce + t.flash);
});

test('particles start in the sources, sit on the sphere mid-spin, and end inside the target card', () => {
  const parts = mk();
  for (const p of parts) {
    const s0 = particleState(p, 0, view);
    assert.ok(Number.isFinite(s0.x) && Number.isFinite(s0.y));
  }
  const midSpin = REVEAL_TIMELINE.gather + REVEAL_TIMELINE.form + REVEAL_TIMELINE.spin / 2;
  for (const p of parts) {
    const s = particleState(p, midSpin, view);
    assert.ok(Math.hypot(s.x - view.cx, s.y - view.cy) <= view.radius + 1e-6);
  }
  for (const p of parts) {
    const s = particleState(p, REVEAL_TOTAL, view);
    assert.ok(s.x >= 19 && s.x <= 381 && s.y >= 119 && s.y <= 211, 'ends inside target');
    assert.equal(s.alpha, 0);
  }
});

test('sphere has both near and far dots, and alpha stays in range throughout', () => {
  const parts = mk();
  const t = REVEAL_TIMELINE.gather + REVEAL_TIMELINE.form + 200;
  const depths = parts.map(p => particleState(p, t, view).depth);
  assert.ok(Math.max(...depths) > 0.5 && Math.min(...depths) < -0.5);
  for (let ms = 0; ms <= REVEAL_TOTAL; ms += 100) for (const p of parts) {
    const s = particleState(p, ms, view);
    assert.ok(s.alpha >= 0 && s.alpha <= 1 && s.r > 0);
  }
});

test('stock covers have unique ids and valid colours', () => {
  assert.equal(new Set(HOST_STOCK_COVERS.map(c => c.id)).size, HOST_STOCK_COVERS.length);
  for (const c of HOST_STOCK_COVERS) for (const k of ['a', 'b', 'glow']) assert.match(c[k], /^#[0-9A-F]{6}$/i);
});

test('dots stay at full strength while forming the card, then fade once it lights up', () => {
  const parts = mk();
  for (const p of parts) {
    assert.equal(particleState(p, REVEAL_FLASH_START - 1, view).alpha > 0.9, true);
    assert.equal(particleState(p, REVEAL_FLASH_START, view).alpha, 1);
    assert.equal(particleState(p, REVEAL_TOTAL, view).alpha, 0);
  }
});

test('flash level is dark before and after the flash phase and peaks inside it', () => {
  assert.equal(flashLevel(0), 0);
  assert.equal(flashLevel(REVEAL_FLASH_START), 0);
  assert.equal(flashLevel(REVEAL_TOTAL), 0);
  let peak = 0;
  for (let t = REVEAL_FLASH_START; t < REVEAL_TOTAL; t += 20) peak = Math.max(peak, flashLevel(t));
  assert.ok(peak > 0.9 && peak <= 1);
});

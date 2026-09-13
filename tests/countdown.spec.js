// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';
import { formatCountdown, msUntil, pickSoonest } from '../src/lib/countdown.js';

test.describe('countdown formatting', () => {
  test('mm:ss under an hour, h:mm:ss past it, never negative', () => {
    expect(formatCountdown(0)).toBe('00:00');
    expect(formatCountdown(59_000)).toBe('00:59');
    expect(formatCountdown(60_000)).toBe('01:00');
    expect(formatCountdown(59 * 60_000 + 59_000)).toBe('59:59');
    expect(formatCountdown(60 * 60_000)).toBe('1:00:00');
    expect(formatCountdown(90 * 60_000 + 5_000)).toBe('1:30:05');
    // A frozen PHASE 2 booking, or a lapsed deadline, must never show a
    // negative countdown — that reads as the clock having run away, not
    // stopped.
    expect(formatCountdown(-5000)).toBe('00:00');
  });

  test('msUntil floors at zero for a deadline already in the past', () => {
    const past = new Date(Date.now() - 60_000).toISOString();
    const future = new Date(Date.now() + 60_000).toISOString();
    expect(msUntil(past)).toBe(0);
    expect(msUntil(future)).toBeGreaterThan(50_000);
    expect(msUntil(null)).toBe(0);
    expect(msUntil(undefined)).toBe(0);
  });
});

test.describe('pickSoonest', () => {
  const iso = (ms) => new Date(Date.now() + ms).toISOString();

  test('picks the soonest still-live deadline in the given phase', () => {
    const bookings = [
      { id: 'a', payment_state: 'holding', hold_expires_at: iso(30 * 60_000) },
      { id: 'b', payment_state: 'holding', hold_expires_at: iso(5 * 60_000) },
      { id: 'c', payment_state: 'confirmed', hold_expires_at: iso(1 * 60_000) },
    ];
    expect(pickSoonest(bookings, 'holding', 'hold_expires_at')?.id).toBe('b');
  });

  test('excludes a lapsed deadline rather than sorting it last', () => {
    // 'b' has already passed its deadline (about to be swept to 'expired'
    // by the minutely cron) — showing a banner for it would be showing a
    // hold that is effectively already gone.
    const bookings = [
      { id: 'a', payment_state: 'holding', hold_expires_at: iso(30 * 60_000) },
      { id: 'b', payment_state: 'holding', hold_expires_at: iso(-60_000) },
    ];
    expect(pickSoonest(bookings, 'holding', 'hold_expires_at')?.id).toBe('a');
  });

  test('returns null when nothing in that phase is still live', () => {
    const bookings = [{ id: 'a', payment_state: 'holding', hold_expires_at: iso(-60_000) }];
    expect(pickSoonest(bookings, 'holding', 'hold_expires_at')).toBeNull();
    expect(pickSoonest([], 'holding', 'hold_expires_at')).toBeNull();
    expect(pickSoonest(undefined, 'holding', 'hold_expires_at')).toBeNull();
  });
});

test.describe('Home payment banners', () => {
  test('show nothing for a signed-out visitor and the page still renders', async ({ page }) => {
    await setupToHome(page);
    // No countdown banners of any kind without a session — there is nothing
    // to be a participant or organizer of yet.
    await expect(page.getByTestId('home-org-verifications-banner')).toHaveCount(0);
    await expect(page.getByTestId('home-org-holding-banner')).toHaveCount(0);
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
  });
});

// READ-ONLY diagnostics (no assertions on app behaviour) used to classify failing focused tests. Local stack only.
import { test } from '@playwright/test';
import { setupToHome } from '../../../tests/helpers.js';
import { adminClient } from '../../../tests/e2e/setup.mjs';
import { SHARED_EMAIL } from '../test-accounts.mjs';

test('probe: pulse X close transform timeline', async ({ page }) => {
  await setupToHome(page);
  await page.click('[data-testid="home-pulse-avatar"]');
  await page.waitForSelector('[data-testid="pulse-viewer"]');
  await page.waitForTimeout(600);
  const info = await page.evaluate(() => {
    const el = document.querySelector('[data-testid="pulse-viewer"]');
    return { anims: el.getAnimations().map(a => ({ name: a.animationName, state: a.playState })), inline: el.style.transform, computed: getComputedStyle(el).transform };
  });
  console.log('PULSE before close', JSON.stringify(info));
  await page.evaluate(() => {
    window.__samples = [];
    const t0 = performance.now();
    const el = document.querySelector('[data-testid="pulse-viewer"]');
    const tick = () => { const e = document.querySelector('[data-testid="pulse-viewer"]'); window.__samples.push([Math.round(performance.now() - t0), e ? getComputedStyle(e).transform : 'GONE', e ? e.style.transform : '']); if (performance.now() - t0 < 500) requestAnimationFrame(tick); };
    requestAnimationFrame(tick);
  });
  await page.click('[data-testid="pulse-close"]');
  await page.waitForTimeout(700);
  const s = await page.evaluate(() => window.__samples);
  console.log('PULSE samples', JSON.stringify(s.filter((_, i) => i % 3 === 0)));
});

test('probe: org public profile as genuinely signed-out vs the default (config-storageState) context', async ({ browser }) => {
  const admin = adminClient();
  const { data } = await admin.from('email_registrations').select('auth_user_id').eq('email', SHARED_EMAIL).maybeSingle();
  const ID = 'e2e-fixture-diag-org';
  await admin.from('organizers').upsert({ id: ID, owner_id: data.auth_user_id, name: 'E2E Fixture Diag Org', about: 'diag', verified: false });
  try {
    for (const [label, opts] of [['browser.newContext() default', undefined], ['explicit empty storageState', { storageState: { cookies: [], origins: [] } }]]) {
      const ctx = await browser.newContext(opts);
      const page = await ctx.newPage();
      await page.goto(`/org/${ID}`);
      await page.locator('[data-screen-label="Organizer profile"]').waitFor({ timeout: 8000 });
      await page.waitForTimeout(800);
      console.log('ORG', label, 'edit-button count =', await page.getByTestId('organizer-profile-edit').count(), '| login screen =', await page.locator('[data-screen-label="Login"]').count());
      await ctx.close();
    }
  } finally { await admin.from('organizers').delete().eq('id', ID); }
});

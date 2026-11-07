// @ts-check
import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// BUG 3 (07-notifications.md, 2026-09-22 eleventh follow-up) — StoryViewer
// preloads the adjacent host's cover in the background as soon as it
// opens, so a host-to-host swipe never shows a loading gap, and the
// gallery-drift companion shows that preloaded cover (not a blank panel).

const ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVrY2hkZ2Rud3l0cmV0dnFqanF1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg3MjMyMjYsImV4cCI6MjEwNDI5OTIyNn0.TgyEJLTXTZgCa6ulsseY3JlrdSmEfOgqVPNh0nSgu90';
const TEST_EMAIL = 'doqanh0906+banbe-fast-suite-shared@gmail.com';
const TEST_PASSWORD = 'BanbeE2e!Test1234';
const ORG_A = 'org_phong302';
const ORG_B = 'org_jazzgac';

function loadServiceEnv() {
  const raw = readFileSync(new URL('../.env.local', import.meta.url), 'utf8');
  return Object.fromEntries(raw.split(/\r?\n/).filter(l => l.includes('=')).map(l => {
    const i = l.indexOf('=');
    return [l.slice(0, i), l.slice(i + 1)];
  }));
}

test.describe('StoryViewer — background preload of adjacent host media (2026-09-22 eleventh follow-up)', () => {
  let admin, uid, storyIdA, storyIdB;

  test.beforeAll(async () => {
    const env = loadServiceEnv();
    admin = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY);
    const anon = createClient(env.SUPABASE_URL, ANON_KEY);
    const { data: signIn } = await anon.auth.signInWithPassword({ email: TEST_EMAIL, password: TEST_PASSWORD });
    uid = signIn.user.id;
    await admin.from('follows').upsert([
      { user_id: uid, organizer_id: ORG_A },
      { user_id: uid, organizer_id: ORG_B },
    ], { onConflict: 'user_id,organizer_id' });
    const { data: orgA } = await admin.from('organizers').select('owner_id').eq('id', ORG_A).maybeSingle();
    const { data: orgB } = await admin.from('organizers').select('owner_id').eq('id', ORG_B).maybeSingle();
    const { data: a } = await admin.from('stories').insert({
      organizer_id: ORG_A, author_id: orgA.owner_id, media_path: '', media_type: 'application/x-banbe-event-share',
      kind: 'event_share', event_id: 'phong302',
    }).select('id').maybeSingle();
    storyIdA = a.id;
    await new Promise(r => setTimeout(r, 50));
    const { data: b } = await admin.from('stories').insert({
      organizer_id: ORG_B, author_id: orgB.owner_id, media_path: '', media_type: 'application/x-banbe-event-share',
      kind: 'event_share', event_id: 'jazzgac',
    }).select('id').maybeSingle();
    storyIdB = b.id;
  });

  test.afterAll(async () => {
    await admin.from('stories').delete().in('id', [storyIdA, storyIdB]);
    await admin.from('follows').delete().eq('user_id', uid).eq('organizer_id', ORG_A);
    await admin.from('follows').delete().eq('user_id', uid).eq('organizer_id', ORG_B);
  });

  test('opening the viewer immediately requests the OTHER host\'s cover in the background, before any swipe happens', async ({ page }) => {
    const requestedPhotoUrls = [];
    page.on('request', (req) => {
      if (/\/photos\/DSCF\d+\.(jpg|webp)/.test(req.url())) requestedPhotoUrls.push(req.url());
    });

    await page.goto('/');
    await page.waitForSelector('[data-screen-label="Home"]', { timeout: 10000 });
    const avatars = page.locator('[data-testid="home-story-avatar"]');
    await expect(avatars.first()).toBeVisible({ timeout: 8000 });
    await avatars.first().click();
    await expect(page.locator('[data-screen-label="Story viewer"]')).toBeVisible();
    // Task 1 (2026-09-22 twelfth follow-up) — the viewer now opens with an
    // expand-from-ring clip-path animation (~DISMISS_MS/260ms); content
    // outside the still-growing clipped window isn't interactive yet (by
    // design — see StoryViewer.jsx's own comment on ringClipPath), so a
    // drag starting before it settles would target coordinates the browser
    // doesn't consider "on" the stage yet. Not a real UX loss — no finger
    // drags within an opening animation's own first ~300ms anyway.
    await page.waitForTimeout(320);

    // Both events' cover photos must have been REQUESTED (preloaded) by
    // the browser almost immediately, well before any drag — the whole
    // point of preloading ahead of the gesture, not during it.
    await expect(async () => {
      expect(requestedPhotoUrls.length).toBeGreaterThanOrEqual(2);
    }).toPass({ timeout: 3000 });

    // Now swipe to the other host and confirm the companion's own
    // backdrop layer actually painted a cover (not left blank) at some
    // point during the drag — since it was already preloaded, this must
    // be near-instant, not a network-triggered fetch mid-gesture.
    const stage = page.locator('[data-testid="story-viewer-stage"]');
    const box = await stage.boundingBox();
    const startX = box.x + box.width * 0.7;
    const y = box.y + box.height * 0.5;
    await page.mouse.move(startX, y);
    await page.mouse.down();
    await page.mouse.move(startX - 80, y, { steps: 5 });
    await page.waitForTimeout(50);

    const companionBg = await page.evaluate(() => {
      const stage = document.querySelector('[data-testid="story-viewer-stage"]');
      const companion = stage?.querySelector('div[style*="position: absolute"][style*="inset: -20px"]')
        || Array.from(stage.querySelectorAll('div')).find(d => getComputedStyle(d).filter.includes('blur'));
      return companion ? getComputedStyle(companion).backgroundImage : null;
    });
    expect(companionBg).not.toBe('none');
    expect(companionBg).toContain('http');

    await page.mouse.up();
  });
});

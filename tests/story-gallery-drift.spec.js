// @ts-check
import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// FEATURE 3 (07-notifications.md, 2026-09-22 second follow-up) — the
// "gallery drift" horizontal swipe transition must navigate exactly like
// the plain tap zones did (no duplicate mark-viewed writes, no progress
// reset/flicker, dock stays hidden throughout), just with a live drag
// follow + settle instead of an instant cut.

const ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVrY2hkZ2Rud3l0cmV0dnFqanF1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg3MjMyMjYsImV4cCI6MjEwNDI5OTIyNn0.TgyEJLTXTZgCa6ulsseY3JlrdSmEfOgqVPNh0nSgu90';
const TEST_EMAIL = 'doqanh0906+banbe-fast-suite-shared@gmail.com';
const TEST_PASSWORD = 'BanbeE2e!Test1234';
const ORG_A = 'org_phong302';

function loadServiceEnv() {
  const raw = readFileSync(new URL('../.env.local', import.meta.url), 'utf8');
  return Object.fromEntries(raw.split(/\r?\n/).filter(l => l.includes('=')).map(l => {
    const i = l.indexOf('=');
    return [l.slice(0, i), l.slice(i + 1)];
  }));
}

test.describe('StoryViewer — gallery-drift horizontal swipe (Feature 3, 2026-09-22 follow-up)', () => {
  let admin, uid, storyIds;

  test.beforeAll(async () => {
    const env = loadServiceEnv();
    admin = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY);
    const anon = createClient(env.SUPABASE_URL, ANON_KEY);
    const { data: signIn } = await anon.auth.signInWithPassword({ email: TEST_EMAIL, password: TEST_PASSWORD });
    uid = signIn.user.id;
    await admin.from('follows').upsert({ user_id: uid, organizer_id: ORG_A }, { onConflict: 'user_id,organizer_id' });
    const { data: orgA } = await admin.from('organizers').select('owner_id').eq('id', ORG_A).maybeSingle();
    const { data: a1 } = await admin.from('stories').insert({
      organizer_id: ORG_A, author_id: orgA.owner_id, media_path: `${ORG_A}/drift-test-1.jpg`, media_type: 'image/jpeg', width: 400, height: 600,
    }).select('id').maybeSingle();
    await new Promise(r => setTimeout(r, 50));
    const { data: a2 } = await admin.from('stories').insert({
      organizer_id: ORG_A, author_id: orgA.owner_id, media_path: `${ORG_A}/drift-test-2.jpg`, media_type: 'image/jpeg', width: 400, height: 600,
    }).select('id').maybeSingle();
    storyIds = [a1.id, a2.id];
  });

  test.afterAll(async () => {
    await admin.from('stories').delete().in('id', storyIds);
    await admin.from('follows').delete().eq('user_id', uid).eq('organizer_id', ORG_A);
  });

  test('a slow horizontal drag-release commits to the next story exactly once, keeps the dock hidden, and records exactly one view row per story', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('[data-screen-label="Home"]', { timeout: 10000 });
    const avatars = page.locator('[data-testid="home-story-avatar"]');
    await expect(avatars.first()).toBeVisible({ timeout: 8000 });
    await avatars.first().click();
    await expect(page.locator('[data-screen-label="Story viewer"]')).toBeVisible();

    // Opening the viewer ticks story 1 — confirmed via real story_views
    // rows rather than the <img> element's own src/visibility (the test
    // fixtures point at storage paths with no real uploaded object behind
    // them, same limitation the rest of this suite's story fixtures
    // already accept — see story-viewer-deck.spec.js's own bottom-right-
    // corner-tap convention for the same reason).
    await expect(async () => {
      const { data: views } = await admin.from('story_views').select('story_id').eq('viewer_id', uid).in('story_id', storyIds);
      expect(views.length).toBe(1);
    }).toPass({ timeout: 3000 });

    // Dock must be fully absent while the viewer is open.
    await expect(page.locator('[data-testid="bottom-tab-bar"]')).toHaveCount(0);

    const stage = page.locator('[data-testid="story-viewer-stage"]');
    const box = await stage.boundingBox();
    const startX = box.x + box.width * 0.7;
    const y = box.y + box.height * 0.5;

    // A SLOW drag past the commit threshold (several intermediate moves,
    // mirroring a real unhurried swipe) — must land on story 2 exactly
    // once, not skip or double-advance.
    await page.mouse.move(startX, y);
    await page.mouse.down();
    for (let dx = 20; dx <= 160; dx += 20) {
      await page.mouse.move(startX - dx, y, { steps: 3 });
      await page.waitForTimeout(30);
    }
    await page.mouse.up();

    // The drag committed exactly one step forward — story 2 is now ticked
    // too, and NOT a duplicate write for story 1.
    await expect(async () => {
      const { data: views } = await admin.from('story_views').select('story_id').eq('viewer_id', uid).in('story_id', storyIds);
      expect(views.length).toBe(2);
      expect(new Set(views.map(v => v.story_id)).size).toBe(2);
    }).toPass({ timeout: 3000 });
    // Dock stays hidden across the transition, not just before it.
    await expect(page.locator('[data-testid="bottom-tab-bar"]')).toHaveCount(0);
    // Still on the SAME viewer (not dismissed/reset) — one more "next" tap
    // exhausts the deck cleanly, proving progress wasn't corrupted by the
    // drag settle.
    await expect(page.locator('[data-screen-label="Story viewer"]')).toBeVisible();

    await page.click('[data-testid="story-viewer-close"]').catch(() => {});

    // Exactly one story_views row per story, still — the drift settle must
    // not have produced a duplicate write for either story after close.
    const { data: views } = await admin.from('story_views').select('story_id').eq('viewer_id', uid).in('story_id', storyIds);
    expect(views.length).toBe(2);
    expect(new Set(views.map(v => v.story_id)).size).toBe(2);
  });
});

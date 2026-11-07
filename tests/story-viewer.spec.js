// @ts-check
import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// Task 1/4/5 (07-notifications.md, 2026-09-22 follow-up) — dock suppression
// during a real StoryViewer session, and the goer-side negative check for
// "Share to Story". Uses service-role writes to set up a real, real-RLS
// story (rather than a mock), the same approach this suite already uses
// for chat-attachment fixtures.

function loadServiceEnv() {
  const raw = readFileSync(new URL('../.env.local', import.meta.url), 'utf8');
  const env = Object.fromEntries(raw.split(/\r?\n/).filter(l => l.includes('=')).map(l => {
    const i = l.indexOf('=');
    return [l.slice(0, i), l.slice(i + 1)];
  }));
  return env;
}

const ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVrY2hkZ2Rud3l0cmV0dnFqanF1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg3MjMyMjYsImV4cCI6MjEwNDI5OTIyNn0.TgyEJLTXTZgCa6ulsseY3JlrdSmEfOgqVPNh0nSgu90';
const TEST_EMAIL = 'doqanh0906+banbe-fast-suite-shared@gmail.com';
const TEST_PASSWORD = 'BanbeE2e!Test1234';
const ORG_ID = 'org_phong302';

test.describe('StoryViewer — dock suppression + goer-side Share-to-Story visibility (2026-09-22 follow-up)', () => {
  let admin;
  let uid;
  let storyId;

  test.beforeAll(async () => {
    const env = loadServiceEnv();
    admin = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY);
    const anon = createClient(env.SUPABASE_URL, ANON_KEY);
    const { data: signIn } = await anon.auth.signInWithPassword({ email: TEST_EMAIL, password: TEST_PASSWORD });
    uid = signIn.user.id;

    // Make the shared test account a real follower of org_phong302 (RLS
    // requires this to SELECT the story at all) and insert a real,
    // currently-active media story for it.
    await admin.from('follows').upsert({ user_id: uid, organizer_id: ORG_ID }, { onConflict: 'user_id,organizer_id' });
    const { data: org } = await admin.from('organizers').select('owner_id').eq('id', ORG_ID).maybeSingle();
    const { data: story } = await admin.from('stories').insert({
      organizer_id: ORG_ID, author_id: org.owner_id, media_path: `${ORG_ID}/e2e-dock-test.jpg`,
      media_type: 'image/jpeg', width: 400, height: 600,
    }).select('id').maybeSingle();
    storyId = story.id;
  });

  test.afterAll(async () => {
    if (storyId) await admin.from('stories').delete().eq('id', storyId);
    if (uid) await admin.from('follows').delete().eq('user_id', uid).eq('organizer_id', ORG_ID);
  });

  test('the bottom dock is fully absent (not just hidden) while a story is open, and reappears on close', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('[data-screen-label="Home"]', { timeout: 10000 });
    await expect(page.locator('[data-testid="bottom-tab-bar"]')).toBeVisible();

    await page.click('[data-testid="home-story-avatar"]');
    await expect(page.locator('[data-screen-label="Story viewer"]')).toBeVisible();
    // Fully absent from the DOM, not merely invisible/zero-opacity — a
    // stray tap on that screen region genuinely cannot reach it.
    await expect(page.locator('[data-testid="bottom-tab-bar"]')).toHaveCount(0);

    await page.click('[data-testid="story-viewer-close"]');
    await expect(page.locator('[data-screen-label="Story viewer"]')).toHaveCount(0);
    await expect(page.locator('[data-testid="bottom-tab-bar"]')).toBeVisible();
  });

  test('a goer (no owned organizer) never sees "Share to Story" on any event, even one they can view/save', async ({ page }) => {
    await page.goto('/?org=phong302');
    await expect(page.locator('[data-screen-label="Organizer"]')).toBeVisible({ timeout: 8000 });
    await page.waitForTimeout(2500);
    await page.click('[data-testid="organizer-message"]').catch(() => {}); // best-effort, just to reach a real event context
    // Navigate to the event itself via its own page instead, since the
    // organizer page doesn't always link directly — go through Home search
    // is unnecessary; Event Detail is reachable from the organizer's own
    // "Sự kiện đang mở" list, but simplest robust check: go straight to
    // the event via its chat "Chi tiết" link if the chat opened, else via
    // browser back to Organizer and its event card.
    if (await page.locator('[data-screen-label="Chat"]').isVisible().catch(() => false)) {
      await page.click('[data-testid="chat-details"]');
    }
    await expect(page.locator('[data-screen-label="Event"]')).toBeVisible({ timeout: 8000 });
    await expect(page.locator('[data-testid="event-share-to-story"]')).toHaveCount(0);
  });
});

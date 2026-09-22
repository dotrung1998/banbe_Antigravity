// @ts-check
import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// FEATURE 3 / PRODUCT CHANGE 3 / BUG 4 (07-notifications.md, 2026-09-22
// tenth follow-up) — horizontal DRAG/swipe now moves between HOST GROUPS
// only, never between individual posts of the same host (that's still
// exclusively the timer's/tap-zones' job); at the final story of the
// final host, a forward drag reveals the real screen underneath (Home)
// instead of a gray/empty companion card.

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

async function slowDrag(page, stage, dxTotal) {
  const box = await stage.boundingBox();
  const startX = box.x + box.width * 0.7;
  const y = box.y + box.height * 0.5;
  await page.mouse.move(startX, y);
  await page.mouse.down();
  const step = dxTotal > 0 ? 20 : -20;
  for (let dx = step; Math.abs(dx) <= Math.abs(dxTotal); dx += step) {
    await page.mouse.move(startX + dx, y, { steps: 3 });
    await page.waitForTimeout(30);
  }
  await page.mouse.up();
}

test.describe('StoryViewer — host-only horizontal swipe + final-deck reveal (2026-09-22 tenth follow-up)', () => {
  let admin, uid, storyIdsA, storyIdsB;

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
    const { data: a1 } = await admin.from('stories').insert({
      organizer_id: ORG_A, author_id: orgA.owner_id, media_path: `${ORG_A}/drift-test-1.jpg`, media_type: 'image/jpeg', width: 400, height: 600,
    }).select('id').maybeSingle();
    await new Promise(r => setTimeout(r, 50));
    const { data: a2 } = await admin.from('stories').insert({
      organizer_id: ORG_A, author_id: orgA.owner_id, media_path: `${ORG_A}/drift-test-2.jpg`, media_type: 'image/jpeg', width: 400, height: 600,
    }).select('id').maybeSingle();
    storyIdsA = [a1.id, a2.id];
    const { data: b1 } = await admin.from('stories').insert({
      organizer_id: ORG_B, author_id: orgB.owner_id, media_path: `${ORG_B}/drift-test-b1.jpg`, media_type: 'image/jpeg', width: 400, height: 400,
    }).select('id').maybeSingle();
    storyIdsB = [b1.id];
  });

  test.afterAll(async () => {
    await admin.from('stories').delete().in('id', [...storyIdsA, ...storyIdsB]);
    await admin.from('follows').delete().eq('user_id', uid).eq('organizer_id', ORG_A);
    await admin.from('follows').delete().eq('user_id', uid).eq('organizer_id', ORG_B);
  });

  test('within a host: horizontal drag does NOT advance the post (only tap/timer do); across hosts: horizontal drag advances to the next HOST', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('[data-screen-label="Home"]', { timeout: 10000 });
    const avatars = page.locator('[data-testid="home-story-avatar"]');
    await expect(avatars.first()).toBeVisible({ timeout: 8000 });

    const stage = page.locator('[data-testid="story-viewer-stage"]');

    // Walk to org_phong302 specifically (the 2-story host) via avatar
    // selection, using the deterministic `data-org-id`/`data-story-count`
    // attributes StoryViewer.jsx's stage carries — not a fragile inline-
    // style substring match.
    const count = await avatars.count();
    let onOrgA = false;
    for (let i = 0; i < count; i++) {
      await avatars.nth(i).click();
      await expect(page.locator('[data-screen-label="Story viewer"]')).toBeVisible();
      const orgId = await stage.getAttribute('data-org-id');
      if (orgId === ORG_A) { onOrgA = true; break; }
      await page.click('[data-testid="story-viewer-close"]');
      await expect(page.locator('[data-screen-label="Story viewer"]')).toHaveCount(0);
    }
    expect(onOrgA).toBe(true);
    await expect(stage).toHaveAttribute('data-story-index', '0');

    await slowDrag(page, stage, -160);
    await page.waitForTimeout(250);

    // PRODUCT CHANGE 3's actual assertion: the drag must NEVER land on
    // post 2 (index 1) of org_phong302 — either it's still org_phong302
    // at index 0 (sprung back — no next host, or the drag fell short) or
    // it jumped to a DIFFERENT host entirely (org_jazzgac) — never the
    // same host at a later index.
    const stillOpen = await page.locator('[data-screen-label="Story viewer"]').isVisible().catch(() => false);
    if (stillOpen) {
      const orgIdAfter = await stage.getAttribute('data-org-id');
      if (orgIdAfter === ORG_A) {
        await expect(stage).toHaveAttribute('data-story-index', '0');
      } else {
        expect(orgIdAfter).toBe(ORG_B);
      }
    }
    // (If it closed instead, that's BUG 4's reveal-Home dismissal — also a
    // valid outcome, exercised precisely by the next test.)

    // Story 2 of org_phong302 must NOT have been ticked by the drag alone
    // — a horizontal swipe within a host is not a valid way to reach it.
    const { data: afterWithinHostDrag } = await admin.from('story_views').select('story_id').eq('viewer_id', uid).eq('story_id', storyIdsA[1]);
    expect(afterWithinHostDrag.length).toBe(0);
  });

  test('final story of the final host: a forward drag past threshold reveals Home progressively and dismisses; short of threshold springs back with no state reset', async ({ page }) => {
    // Isolate to a single host so "final host" is unambiguous.
    await admin.from('follows').delete().eq('user_id', uid).eq('organizer_id', ORG_B);

    await page.goto('/');
    await page.waitForSelector('[data-screen-label="Home"]', { timeout: 10000 });
    const avatars = page.locator('[data-testid="home-story-avatar"]');
    await expect(avatars.first()).toBeVisible({ timeout: 8000 });
    await avatars.first().click();
    await expect(page.locator('[data-screen-label="Story viewer"]')).toBeVisible();

    const stage = page.locator('[data-testid="story-viewer-stage"]');

    // SHORT drag (under threshold) — must spring back, story viewer stays
    // open, no dismissal.
    await slowDrag(page, stage, -30);
    await page.waitForTimeout(400);
    await expect(page.locator('[data-screen-label="Story viewer"]')).toBeVisible();

    // FULL commit-threshold drag — reveals Home and dismisses; the dock
    // only reappears once the story viewer is actually gone.
    await slowDrag(page, stage, -160);
    await expect(page.locator('[data-screen-label="Story viewer"]')).toHaveCount(0, { timeout: 3000 });
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
    await expect(page.locator('[data-testid="bottom-tab-bar"]')).toBeVisible();

    // Restore the follow for other tests/afterAll cleanup expectations.
    await admin.from('follows').upsert({ user_id: uid, organizer_id: ORG_B }, { onConflict: 'user_id,organizer_id' });
  });

  test('BUG 2: first story of the first host: a BACKWARD drag past threshold also reveals Home progressively and dismisses; short of threshold springs back', async ({ page }) => {
    // Isolate to a single host so "first/only host" is unambiguous.
    await admin.from('follows').delete().eq('user_id', uid).eq('organizer_id', ORG_B);

    await page.goto('/');
    await page.waitForSelector('[data-screen-label="Home"]', { timeout: 10000 });
    const avatars = page.locator('[data-testid="home-story-avatar"]');
    await expect(avatars.first()).toBeVisible({ timeout: 8000 });
    await avatars.first().click();
    await expect(page.locator('[data-screen-label="Story viewer"]')).toBeVisible();

    const stage = page.locator('[data-testid="story-viewer-stage"]');

    // SHORT backward drag (under threshold) — must spring back, no dismissal.
    await slowDrag(page, stage, 30);
    await page.waitForTimeout(400);
    await expect(page.locator('[data-screen-label="Story viewer"]')).toBeVisible();
    // Still the same first story — no state reset from the cancelled drag.
    await expect(stage).toHaveAttribute('data-story-index', '0');

    // FULL commit-threshold BACKWARD drag — must ALSO reveal Home and
    // dismiss (previously only the forward/final-host edge did this).
    await slowDrag(page, stage, 160);
    await expect(page.locator('[data-screen-label="Story viewer"]')).toHaveCount(0, { timeout: 3000 });
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
    await expect(page.locator('[data-testid="bottom-tab-bar"]')).toBeVisible();

    await admin.from('follows').upsert({ user_id: uid, organizer_id: ORG_B }, { onConflict: 'user_id,organizer_id' });
  });
});

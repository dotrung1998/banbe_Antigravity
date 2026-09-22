// @ts-check
import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// Task 6 (2026-09-22 twelfth follow-up) — one shared unread definition
// (messages.read_at IS NULL AND sender_id != me) now backs Inbox row
// styling, the dock badge, AND is patched locally the instant
// markThreadMessagesRead() succeeds (GocContext.jsx), instead of waiting
// on Inbox's own next full reload. Real root cause found: chatBackFn()
// (Chat.jsx's own back arrow) returns straight to 'inbox' without ever
// re-calling loadInboxThreads(), so the Inbox row's local `unread` flag
// used to stay stale (bold/dotted) until Inbox was re-entered from
// OUTSIDE via a fresh goInbox() call.

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

test.describe('Inbox — unified unread computation (2026-09-22 twelfth follow-up)', () => {
  let admin, uid, threadId;

  test.beforeAll(async () => {
    const env = loadServiceEnv();
    admin = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY);
    const anon = createClient(env.SUPABASE_URL, ANON_KEY);
    const { data } = await anon.auth.signInWithPassword({ email: TEST_EMAIL, password: TEST_PASSWORD });
    uid = data.user.id;

    const { data: org } = await admin.from('organizers').select('owner_id').eq('id', ORG_A).maybeSingle();
    const { data: existing } = await admin.from('threads').select('id').eq('event_id', 'phong302').eq('guest_id', uid).maybeSingle();
    if (existing?.id) {
      threadId = existing.id;
    } else {
      const { data: created } = await admin.from('threads').insert({ event_id: 'phong302', guest_id: uid, organizer_id: ORG_A }).select('id').maybeSingle();
      threadId = created.id;
    }
    // Two unread incoming messages, authored by the organizer (not me).
    await admin.from('messages').insert([
      { thread_id: threadId, sender_id: org.owner_id, body: 'inbox-unread-test-1', kind: 'text' },
      { thread_id: threadId, sender_id: org.owner_id, body: 'inbox-unread-test-2', kind: 'text' },
    ]);
  });

  test.afterAll(async () => {
    await admin.from('messages').delete().eq('thread_id', threadId).in('body', ['inbox-unread-test-1', 'inbox-unread-test-2']);
  });

  test('a thread with unread incoming messages shows unread styling, becomes read immediately on return (no stale styling), and stays read on reload', async ({ page }) => {
    await page.goto('/');
    await page.waitForSelector('[data-screen-label="Home"]', { timeout: 10000 });
    await page.click('[data-testid="tab-inbox"]');
    await page.waitForSelector('[data-screen-label="Inbox"]', { timeout: 10000 });

    const row = page.locator(`[data-testid="inbox-row"][data-thread-id="${threadId}"]`);
    await expect(row).toBeVisible({ timeout: 8000 });
    await expect(row).toHaveAttribute('data-unread', 'true');
    await expect(row.locator('[data-testid="inbox-row-unread-dot"]')).toBeVisible();

    // Open it — this is the SAME markThreadMessagesRead() path production
    // uses, no test-only shortcut.
    await row.click();
    await expect(page.locator('[data-screen-label="Chat"]')).toBeVisible({ timeout: 8000 });

    // Back to Inbox via the real back arrow (chatBackFn) — the exact path
    // that used to leave a stale unread row.
    await page.click('[data-testid="chat-back"]');
    await expect(page.locator('[data-screen-label="Inbox"]')).toBeVisible();
    await expect(row).toHaveAttribute('data-unread', 'false', { timeout: 3000 });
    await expect(row.locator('[data-testid="inbox-row-unread-dot"]')).toHaveCount(0);

    // Reload from scratch — confirms the server-side read_at write (not
    // just the optimistic local patch) actually persisted.
    await page.reload();
    await page.waitForSelector('[data-screen-label="Home"]', { timeout: 10000 });
    await page.click('[data-testid="tab-inbox"]');
    await page.waitForSelector('[data-screen-label="Inbox"]', { timeout: 10000 });
    const rowAfterReload = page.locator(`[data-testid="inbox-row"][data-thread-id="${threadId}"]`);
    await expect(rowAfterReload).toBeVisible({ timeout: 8000 });
    await expect(rowAfterReload).toHaveAttribute('data-unread', 'false');
  });
});

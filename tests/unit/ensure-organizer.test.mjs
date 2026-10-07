import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  deriveDefaultOrganizerName, shouldEnsureOrganizer, normalizeEnsureResult,
  createSingleFlight, nextEnsureStatus, ensureOrganizerRpc,
} from '../../src/lib/ensureOrganizer.js';

const base = { userId: 'u1', organizerMode: true, idsStatus: 'loaded', ownedCount: 0, ensureStatus: 'idle' };

test('shouldEnsure: only when mode on, lookup confirmed empty, idle', () => {
  assert.equal(shouldEnsureOrganizer(base), true);
  assert.equal(shouldEnsureOrganizer({ ...base, organizerMode: false }), false);
  assert.equal(shouldEnsureOrganizer({ ...base, userId: null }), false);
  assert.equal(shouldEnsureOrganizer({ ...base, ownedCount: 1 }), false);
  for (const idsStatus of ['idle', 'loading', 'error']) assert.equal(shouldEnsureOrganizer({ ...base, idsStatus }), false);
  assert.equal(shouldEnsureOrganizer({ ...base, ensureStatus: 'loading' }), false);
  assert.equal(shouldEnsureOrganizer({ ...base, ensureStatus: 'error' }), false, 'no auto retry loop');
});

test('name derivation', () => {
  assert.equal(deriveDefaultOrganizerName('Linh', 'en'), 'Linh Events');
  assert.equal(deriveDefaultOrganizerName('Linh', 'vi'), 'Linh Sự kiện');
  assert.equal(deriveDefaultOrganizerName('  ', 'en'), 'My events');
  assert.equal(deriveDefaultOrganizerName(null, 'vi'), 'Sự kiện của tôi');
  assert.equal(deriveDefaultOrganizerName(undefined), 'My events');
});

test('name never derived from email or phone', () => {
  for (const v of ['a@b.com', 'linh@gmail.com', '+84 912 345 678', '0912345678']) {
    const n = deriveDefaultOrganizerName(v, 'en');
    assert.equal(n, 'My events');
    assert.ok(!n.includes('@') && !/\d/.test(n));
  }
});

test('single flight: two simultaneous ensure calls issue one RPC', async () => {
  let calls = 0;
  const supabase = { rpc: async (name) => { calls++; assert.equal(name, 'ensure_my_organizer'); await new Promise(r => setTimeout(r, 10)); return { data: { success: true, organizerId: 'org_1', created: true, name: 'X Events' }, error: null }; } };
  const run = ensureOrganizerRpc(supabase);
  const [a, b] = await Promise.all([run(), run()]);
  assert.equal(calls, 1);
  assert.deepEqual(a, b);
  assert.equal(a.organizerId, 'org_1');
  await run();
  assert.equal(calls, 2, 'a later call after settle is allowed');
});

test('normalize result', () => {
  assert.equal(normalizeEnsureResult({ data: null, error: { code: 'X' } }).ok, false);
  assert.equal(normalizeEnsureResult({ data: { success: false, error: 'ORGANIZER_MODE_REQUIRED' }, error: null }).error, 'ORGANIZER_MODE_REQUIRED');
  assert.equal(normalizeEnsureResult({ data: { success: true, organizerId: 'o', created: false, name: 'n' } }).created, false);
});

test('retry state machine', () => {
  let s = nextEnsureStatus('idle', 'start');
  assert.equal(s, 'loading');
  assert.equal(nextEnsureStatus(s, 'failure'), 'error');
  assert.equal(nextEnsureStatus('error', 'retry'), 'loading');
  assert.equal(nextEnsureStatus('idle', 'retry'), 'idle');
  assert.equal(nextEnsureStatus('loading', 'retry'), 'loading');
  assert.equal(nextEnsureStatus('loading', 'success'), 'idle');
  assert.equal(nextEnsureStatus('error', 'reset'), 'idle');
});

test('createSingleFlight propagates rejection then resets', async () => {
  let n = 0;
  const f = createSingleFlight(async () => { n++; if (n === 1) throw new Error('boom'); return 'ok'; });
  await assert.rejects(f());
  assert.equal(await f(), 'ok');
});

const sql = readFileSync(new URL('../../supabase/migrations/20261211000163_163_ensure_my_organizer.sql', import.meta.url), 'utf8');
const code = sql.split('\n').filter(l => !l.trim().startsWith('--')).join('\n');

test('migration: grants authenticated only, never anon', () => {
  assert.match(code, /SECURITY DEFINER/);
  assert.match(code, /SET search_path = public/);
  assert.match(code, /REVOKE EXECUTE ON FUNCTION public\.ensure_my_organizer\(\) FROM anon/);
  assert.match(code, /GRANT EXECUTE ON FUNCTION public\.ensure_my_organizer\(\) TO authenticated/);
  assert.doesNotMatch(code, /GRANT[^;]*\bTO\s+(anon|PUBLIC)\b/i);
});

test('migration: auth.uid only, no user id param, advisory lock', () => {
  assert.match(code, /ensure_my_organizer\(\)\s*RETURNS jsonb/);
  assert.match(code, /auth\.uid\(\)/);
  assert.match(code, /pg_advisory_xact_lock/);
});

test('migration: never touches organizer_members, roles, or verified', () => {
  assert.doesNotMatch(code, /organizer_members/);
  assert.doesNotMatch(code, /UPDATE\s+public\.profiles/i);
  assert.doesNotMatch(code, /verified\s*[,=)]/i);
  assert.doesNotMatch(code, /INSERT INTO public\.events/i);
});

test('migration: name never from email/phone/handle', () => {
  assert.doesNotMatch(code, /\bemail\b|\bphone\b|\bhandle\b/i);
  assert.match(code, /display_name/);
  assert.match(code, /My events/);
  assert.match(code, /Sự kiện của tôi/);
});

// Local copy of tests/global-setup.js: same shared test user, isolated stack, our origin, state kept OUTSIDE the repo.
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { assertIsolated } from './guard.mjs';
import { seedFixtures } from './fixtures.mjs';
import { SHARED_EMAIL, SHARED_PASSWORD } from './test-accounts.mjs';
assertIsolated();
const REPO = process.env.E2E_REPO;
const { adminClient, signIn } = await import(`${REPO}/tests/e2e/setup.mjs`);
const STORAGE = process.env.E2E_STORAGE_STATE;
const EMAIL = SHARED_EMAIL, PASSWORD = SHARED_PASSWORD; // the synthetic account tests/global-setup.js already defines
export default async function globalSetup() {
  assertIsolated();
  mkdirSync(dirname(STORAGE), { recursive: true });
  const admin = adminClient();
  const { data: ex } = await admin.from('email_registrations').select('auth_user_id').eq('email', EMAIL).maybeSingle();
  if (ex?.auth_user_id) await admin.auth.admin.updateUserById(ex.auth_user_id, { password: PASSWORD });
  else { const { error } = await admin.auth.admin.createUser({ email: EMAIL, password: PASSWORD, email_confirm: true, user_metadata: { display_name: 'Fast Suite Shared Test User' } }); if (error) throw error; }
  const reg = await admin.from('email_registrations').select('auth_user_id').eq('email', EMAIL).single();
  const uid = reg.data.auth_user_id;
  await admin.from('profiles').update({ locale: 'vi', theme: 'light', prefs_saved: true, role: 'participant' }).eq('id', uid);
  // Production's shared account is in the grandfathered cohort (migration 123); a fresh local one is not.
  const gf = await admin.from('account_phone_grandfathered').upsert({ user_id: uid, cohort: 'local-e2e-fixture' });
  if (gf.error) throw new Error('grandfather fixture failed: ' + gf.error.message);
  await admin.from('favorites').delete().eq('user_id', uid);
  console.log('[e2e-local] fixtures', JSON.stringify(await seedFixtures(admin)));
  const { session } = await signIn(EMAIL, PASSWORD);
  const key = `sb-${new URL(process.env.VITE_SUPABASE_URL).hostname.split('.')[0]}-auth-token`;
  writeFileSync(STORAGE, JSON.stringify({ cookies: [], origins: [{ origin: 'http://localhost:5199', localStorage: [{ name: key, value: JSON.stringify({ access_token: session.access_token, token_type: 'bearer', expires_in: session.expires_in, expires_at: session.expires_at, refresh_token: session.refresh_token, user: session.user }) }] }] }, null, 2));
  console.log('[e2e-local] shared test user signed in on', process.env.SUPABASE_URL);
}

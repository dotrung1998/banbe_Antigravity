// Real-backend fixtures for tests/dispute-flow-e2e.spec.js. Every function
// here talks to the actual production Supabase project (SUPABASE_URL) with
// the service-role key — bypassing RLS on purpose, the same way any other
// admin-API seeding script would. Nothing here should ever run against a
// project you don't intend to write real rows into.
import './loadEnv.mjs';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON_KEY = process.env.VITE_SUPABASE_ANON_KEY;

export function hasServiceRole() {
  return Boolean(SUPABASE_URL && SERVICE_ROLE_KEY && ANON_KEY);
}

export function adminClient() {
  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
}

// A fresh anon-key client per signed-in actor — mirrors how the real app's
// src/lib/supabase.js client is constructed, so signInWithPassword here goes
// through the exact same auth path the UI's password-login tab uses.
export function anonClient() {
  return createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
}

const RUN_ID = Date.now().toString(36);
const TEST_PASSWORD = 'BanbeE2e!Test1234';

// Gmail "+" aliases: distinct addresses (so Supabase Auth's unique-email
// constraint on auth.users is satisfied) that all deliver to the same real
// inbox this session can read via the Gmail connector — the only way to
// verify actual delivery without needing separate throwaway mailboxes.
const GMAIL_INBOX = 'doqanh0906@gmail.com';
function aliasEmail(label) {
  const [user, domain] = GMAIL_INBOX.split('@');
  return `${user}+banbe-e2e-${label}-${RUN_ID}@${domain}`;
}

async function findAuthUserIdByEmail(admin, email) {
  const { data } = await admin.from('email_registrations').select('auth_user_id').eq('email', email.toLowerCase()).maybeSingle();
  if (data?.auth_user_id) return data.auth_user_id;
  // Registry can be stale/missing — fall back to paging the admin API,
  // same last-resort this repo's own api/_lib/authLookup.js uses.
  for (let page = 1; page <= 5; page += 1) {
    const { data: list, error } = await admin.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw error;
    const match = (list?.users || []).find(u => (u.email || '').toLowerCase() === email.toLowerCase());
    if (match) return match.id;
    if (!list || (list.users || []).length < 200) break;
  }
  return null;
}

// Reuses the repo's established test admin (banbetestadmin@gmail.com,
// auto-promoted to role='admin' by handle_new_user() — migration 040) rather
// than minting a throwaway admin, per this ticket's instruction. Its
// password is unknown to this session, so it's reset to a known value —
// a normal thing to do to a designated test account, not a real user's.
export async function ensureAdminAccount(admin) {
  const email = 'banbetestadmin@gmail.com';
  let userId = await findAuthUserIdByEmail(admin, email);
  if (!userId) {
    const { data, error } = await admin.auth.admin.createUser({
      email, password: TEST_PASSWORD, email_confirm: true,
      user_metadata: { display_name: 'banbe test admin' },
    });
    if (error) throw error;
    userId = data.user.id;
  } else {
    const { error } = await admin.auth.admin.updateUserById(userId, { password: TEST_PASSWORD });
    if (error) throw error;
  }
  // Belt-and-suspenders: handle_new_user() already sets role='admin' for
  // this exact email on insert, but don't depend on that alone.
  await admin.from('profiles').update({ role: 'admin' }).eq('id', userId);
  return { email, password: TEST_PASSWORD, userId };
}

export async function createTestUser(admin, label, { role = 'participant', displayName } = {}) {
  const email = aliasEmail(label);
  const { data, error } = await admin.auth.admin.createUser({
    email, password: TEST_PASSWORD, email_confirm: true,
    user_metadata: { display_name: displayName || `E2E ${label}` },
  });
  if (error) throw error;
  const userId = data.user.id;
  if (role !== 'participant') {
    await admin.from('profiles').update({ role }).eq('id', userId);
  }
  return { email, password: TEST_PASSWORD, userId };
}

export async function createOrganizer(admin, ownerUserId, name) {
  const id = `e2e-org-${RUN_ID}`;
  const { error } = await admin.from('organizers').insert({
    id, owner_id: ownerUserId, name, verified: true,
    bank_name: 'Test Bank', bank_account_name: name, bank_account_no: '0000000000',
  });
  if (error) throw error;
  return id;
}

export async function createEvent(admin, organizerId, label) {
  const id = `e2e-event-${label}-${RUN_ID}`;
  const { error } = await admin.from('events').insert({
    id, key: id, slug: id, organizer_id: organizerId,
    name: `E2E dispute-flow test event (${label})`,
    price_vnd: 100000, capacity: 5, seats_remaining: 5,
    hold_minutes: 30, status: 'live', approval: 'instant', visibility: 'public',
  });
  if (error) throw error;
  return id;
}

export async function signIn(email, password) {
  const client = anonClient();
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return { client, session: data.session };
}

// Best-effort teardown — logs and continues rather than failing the whole
// test run if any one row is already gone or a delete races something else.
export async function cleanup(admin, { userIds = [], organizerId, eventIds = [] } = {}) {
  const errors = [];
  const guard = async (label, fn) => {
    try { await fn(); } catch (e) { errors.push(`${label}: ${e.message || e}`); }
  };

  if (eventIds.length) {
    const { data: bookings } = await admin.from('bookings').select('id').in('event_id', eventIds);
    const bookingIds = (bookings || []).map(b => b.id);
    if (bookingIds.length) {
      // No FK from dispute_resolution_stats to bookings (deliberately, see
      // migration 047) — delete explicitly, cascade won't reach it.
      await guard('dispute_resolution_stats', () => admin.from('dispute_resolution_stats').delete().in('booking_id', bookingIds));
    }
    await guard('bookings', () => admin.from('bookings').delete().in('event_id', eventIds));
    await guard('events', () => admin.from('events').delete().in('id', eventIds));
  }
  if (organizerId) {
    await guard('organizers', () => admin.from('organizers').delete().eq('id', organizerId));
  }
  for (const userId of userIds) {
    await guard(`auth user ${userId}`, () => admin.auth.admin.deleteUser(userId));
  }
  // email_registrations has no FK/cascade off auth.users (it's a standalone
  // lookup registry, see api/_lib/authLookup.js) — deleting the auth user
  // above leaves an orphaned row pointing at a now-nonexistent id unless
  // this cleans it up too.
  await guard('email_registrations', () => admin.from('email_registrations').delete().like('email', 'doqanh0906+banbe-e2e-%'));
  if (errors.length) console.warn('e2e cleanup had non-fatal errors:', errors);
}

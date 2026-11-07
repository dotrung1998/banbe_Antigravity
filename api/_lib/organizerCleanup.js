// Host-profile cleanup, shared by account deletion (api/auth) and scripts/cleanup-orphaned-media.mjs so
// both follow the same rules. Deleting an auth user cascades database rows but never Storage objects, and
// leaves the user's organizer row behind with no owner, still carrying the host's name, intro, photo,
// bank/MoMo details and contact info. This removes that.
//
// Rules per organizer (see planOrganizerCleanup):
//   skip       other accepted team members exist: the organizer lives on for them (ownership is cleared by
//              the database when the user is deleted); nothing is touched.
//   delete     nothing depends on it (no events, message threads or surveys): remove its files and its row.
//   anonymize  events/threads/surveys still reference it: keep the row (guests' records need it) but remove
//              its files and scrub every personal, contact and payment field.

// Buckets whose objects are keyed `<organizerId>/...`.
export const ORGANIZER_BUCKETS = ['organizer-photos', 'pay-qr'];

export const ANONYMIZED_NAME = 'Deleted organizer';

// Columns scrubbed on anonymize. `optional` ones come from later migrations and may not exist yet in every
// environment, so a missing-column error retries without them.
export const SCRUB_CORE = {
  name: ANONYMIZED_NAME, ig_handle: '', instagram: '', bio: '', about: '', intro_long: '', social_links: [],
  avatar_path: '', billing_address: '', tax_code: '', telegram_chat_id: '', alert_phone: '',
  bank_name: '', bank_account_name: '', bank_account_no: '', momo_phone: '', pay_qr_path: '', pay_note: '',
  pay_methods: [],
};
export const SCRUB_OPTIONAL = { avatar_r2_ref: null, share_card: null, pay_qr_payload: '' };

/** Pure: facts = { events, threads, surveys, otherMembers } counts for one organizer. */
export function planOrganizerCleanup(facts = {}) {
  const n = k => Number(facts[k]) || 0;
  if (n('otherMembers') > 0) return 'skip';
  if (n('events') + n('threads') + n('surveys') === 0) return 'delete';
  return 'anonymize';
}

const isMissingColumn = (error) => !!error && (error.code === '42703' || error.code === 'PGRST204' || /column .* does not exist|could not find the .* column/i.test(error.message || ''));

/** Remove every object under `prefix/` in a bucket, one folder level deep. Returns the number removed. */
export async function removeStoragePrefix(admin, bucket, prefix, depth = 0) {
  let removed = 0;
  for (let offset = 0; offset < 10000; offset += 100) {
    const { data, error } = await admin.storage.from(bucket).list(prefix, { limit: 100, offset });
    if (error) throw error;
    if (!data?.length) break;
    const files = data.filter(item => item.id).map(item => `${prefix}/${item.name}`);
    if (files.length) {
      const { error: rmError } = await admin.storage.from(bucket).remove(files);
      if (rmError) throw rmError;
      removed += files.length;
    }
    if (depth < 2) {
      for (const folder of data.filter(item => !item.id)) removed += await removeStoragePrefix(admin, bucket, `${prefix}/${folder.name}`, depth + 1);
    }
    if (data.length < 100) break;
  }
  return removed;
}

async function count(admin, table, column, value, extra) {
  let q = admin.from(table).select('*', { count: 'exact', head: true }).eq(column, value);
  if (extra) q = extra(q);
  const { count: c, error } = await q;
  if (error) throw error;
  return c || 0;
}

/** Counts that decide the plan for one organizer; `ownerId` is excluded when counting other members. */
export async function gatherOrganizerFacts(admin, organizerId, ownerId) {
  const [events, threads, surveys, otherMembers] = await Promise.all([
    count(admin, 'events', 'organizer_id', organizerId),
    count(admin, 'threads', 'organizer_id', organizerId),
    count(admin, 'surveys', 'organizer_id', organizerId),
    count(admin, 'organizer_members', 'organizer_id', organizerId, q => {
      let r = q.eq('status', 'accepted');
      if (ownerId) r = r.neq('user_id', ownerId);
      return r;
    }),
  ]);
  return { events, threads, surveys, otherMembers };
}

/**
 * Apply one organizer's cleanup. `action` is 'delete' | 'anonymize' (anything else is a no-op).
 * Returns { action, filesRemoved, notes[] }. Files go first so a failure never leaves files for a deleted row.
 */
export async function applyOrganizerCleanup(admin, organizerId, action) {
  const notes = [];
  if (action !== 'delete' && action !== 'anonymize') return { action, filesRemoved: 0, notes };
  let filesRemoved = 0;
  for (const bucket of ORGANIZER_BUCKETS) {
    try { filesRemoved += await removeStoragePrefix(admin, bucket, organizerId); }
    catch (error) { notes.push(`${bucket}: ${error?.message || error}`); }
  }
  if (action === 'delete') {
    const { error } = await admin.from('organizers').delete().eq('id', organizerId);
    if (error) throw error;
    return { action, filesRemoved, notes };
  }
  let { error } = await admin.from('organizers').update({ ...SCRUB_CORE, ...SCRUB_OPTIONAL }).eq('id', organizerId);
  if (isMissingColumn(error)) ({ error } = await admin.from('organizers').update(SCRUB_CORE).eq('id', organizerId));
  if (error) throw error;
  return { action, filesRemoved, notes };
}

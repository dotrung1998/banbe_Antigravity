import { createClient } from '@supabase/supabase-js';

// Hard-deletes payment_documents rows (and their storage object) past their
// purge_after — the 24h tail end of Task 5's replacement soft-delete
// (upload_payment_document(), migration 056): a superseded row is kept
// queryable for 24h in case of issues, then actually removed. Runs daily
// (vercel.json), same cadence as escalate-verifications.js — this project
// is on Vercel's Hobby plan, which only permits daily (not hourly) cron
// schedules, so this errs toward the later end of the 24h window rather
// than promising exact-to-the-hour purging.

function getSupabaseAdmin() {
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
    || 'https://ukchdgdnwytretvqjjqu.supabase.co';
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return null;
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

export default async function handler(req, res) {
  // Same signed-invocation check as escalate-verifications.js — without it
  // this is a free "delete anyone's superseded receipts early" button.
  const secret = process.env.CRON_SECRET;
  const auth = req.headers.authorization || '';
  if (secret && auth !== `Bearer ${secret}`) {
    return res.status(401).json({ error: 'UNAUTHORIZED' });
  }

  const admin = getSupabaseAdmin();
  if (!admin) return res.status(503).json({ error: 'SUPABASE_SERVICE_ROLE_KEY_NOT_SET' });

  const { data: due, error } = await admin
    .from('payment_documents')
    .select('id, file_path')
    .not('purge_after', 'is', null)
    .lte('purge_after', new Date().toISOString())
    .limit(200);

  if (error) {
    console.warn('purge-payment-documents: read failed', error.message);
    return res.status(500).json({ error: 'QUEUE_READ_FAILED' });
  }

  let purged = 0;
  const failures = [];

  for (const row of due || []) {
    try {
      if (row.file_path) {
        const { error: storageError } = await admin.storage.from('payment-documents').remove([row.file_path]);
        // Not fatal — an already-missing object (a retry after a partial
        // prior run) shouldn't block deleting the row itself.
        if (storageError) console.warn('purge-payment-documents: storage remove failed', row.id, storageError.message);
      }
      const { error: deleteError } = await admin.from('payment_documents').delete().eq('id', row.id);
      if (deleteError) throw deleteError;
      purged += 1;
    } catch (e) {
      failures.push({ id: row.id, error: e?.message });
    }
  }

  return res.status(200).json({ ok: true, purged, failures });
}

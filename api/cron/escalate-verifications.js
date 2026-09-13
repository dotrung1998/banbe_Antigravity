import { createClient } from '@supabase/supabase-js';
import { sendVerificationAlert, sendUrgentEscalation, isTelegramConfigured } from '../_lib/alerts.js';

// Drains alert_outbox. Runs on a Vercel Cron schedule (see vercel.json).
//
// Why the outbox exists at all rather than the database calling Telegram
// directly: Postgres cannot make outbound HTTP calls here without pg_net,
// and even with it, an outbound call inside the transaction that changes
// payment state would let a Telegram outage stall or roll back a payment.
// sweep_verification_slas() decides WHAT is overdue and commits; this
// decides whether the send succeeded, and retries independently.

function getSupabaseAdmin() {
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
    || 'https://ukchdgdnwytretvqjjqu.supabase.co';
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return null;
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

const MAX_ATTEMPTS = 5;

export default async function handler(req, res) {
  // Vercel Cron signs its invocations; without this the endpoint is a free
  // "spam the organizer's group chat" button for anyone who finds the URL.
  const secret = process.env.CRON_SECRET;
  const auth = req.headers.authorization || '';
  if (secret && auth !== `Bearer ${secret}`) {
    return res.status(401).json({ error: 'UNAUTHORIZED' });
  }

  const admin = getSupabaseAdmin();
  if (!admin) return res.status(503).json({ error: 'SUPABASE_SERVICE_ROLE_KEY_NOT_SET' });

  const { data: queue, error } = await admin
    .from('v_alert_queue')
    .select('*')
    .lte('attempts', MAX_ATTEMPTS)
    .order('created_at', { ascending: true })
    .limit(50);

  if (error) {
    console.warn('escalate-verifications: queue read failed', error.message);
    return res.status(500).json({ error: 'QUEUE_READ_FAILED' });
  }

  let sent = 0;
  let skipped = 0;
  const failures = [];

  for (const row of queue || []) {
    // The organizer may have answered between the sweep queueing this and
    // us getting to it — don't nag about a settled booking.
    if (row.payment_state !== 'pending_verification') {
      await admin.from('alert_outbox')
        .update({ sent_at: new Date().toISOString(), last_error: 'superseded: already resolved' })
        .eq('id', row.alert_id);
      skipped += 1;
      continue;
    }

    if (!row.telegram_chat_id || !isTelegramConfigured()) {
      await admin.from('alert_outbox')
        .update({ attempts: (row.attempts || 0) + 1, last_error: 'no telegram route configured' })
        .eq('id', row.alert_id);
      skipped += 1;
      continue;
    }

    try {
      if (row.kind === 'verification_escalation') {
        await sendUrgentEscalation(row);
      } else {
        await sendVerificationAlert(row, row.kind);
      }
      await admin.from('alert_outbox')
        .update({ sent_at: new Date().toISOString(), attempts: (row.attempts || 0) + 1, last_error: null })
        .eq('id', row.alert_id);
      sent += 1;
    } catch (e) {
      await admin.from('alert_outbox')
        .update({ attempts: (row.attempts || 0) + 1, last_error: String(e?.message).slice(0, 300) })
        .eq('id', row.alert_id);
      failures.push({ alert_id: row.alert_id, error: e?.message });
    }
  }

  return res.status(200).json({ ok: true, sent, skipped, failures });
}

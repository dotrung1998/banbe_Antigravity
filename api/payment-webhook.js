import crypto from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

// Inbound bank-transaction webhook — the automated reconciliation path.
//
// Supports the two services a Vietnamese organizer realistically uses to get
// real-time balance changes off a personal/business account (Casso and
// PayOS), plus a generic shape for a direct banking API. All three normalise
// to the same three facts the matcher needs: a provider-unique transaction
// id, an amount, and the transfer description.
//
// Everything that could go wrong under concurrency — a duplicate delivery, a
// race with the organizer tapping Approve at the same moment, a partial
// write — is handled inside record_bank_transaction() in one database
// transaction (migration 026). This handler's whole job is: authenticate the
// provider, normalise the payload, hand it over, and answer 200 fast.
//
// It answers 200 even for payloads it cannot match. Every one of these
// providers retries on a non-2xx, so returning 4xx for "this transfer isn't
// one of ours" (most of them won't be — it's the organizer's own bank
// account, with their rent and groceries going through it too) would earn an
// escalating retry storm for transactions that will never match.

function getSupabaseAdmin() {
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
    || 'https://ukchdgdnwytretvqjjqu.supabase.co';
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return null;
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

/** Constant-time compare that can't throw on length mismatch. */
function safeEqual(a, b) {
  const bufA = Buffer.from(String(a ?? ''), 'utf8');
  const bufB = Buffer.from(String(b ?? ''), 'utf8');
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

/**
 * PayOS signs an HMAC-SHA256 of its `data` object serialised as
 * key=value&... with keys sorted alphabetically, using the checksum key.
 */
function payosSignatureValid(data, signature, checksumKey) {
  if (!checksumKey || !signature) return false;
  const sorted = Object.keys(data || {}).sort()
    .map((k) => {
      const v = data[k];
      return `${k}=${v === null || v === undefined ? '' : v}`;
    })
    .join('&');
  const expected = crypto.createHmac('sha256', checksumKey).update(sorted).digest('hex');
  return safeEqual(expected, signature);
}

/** Normalises each provider into { externalId, amountVnd, memo }. */
function normalise(provider, body) {
  if (provider === 'casso') {
    // Casso posts a batch: { error: 0, data: [ {...}, {...} ] }
    const rows = Array.isArray(body?.data) ? body.data : [];
    return rows.map((r) => ({
      externalId: String(r.id ?? r.tid ?? ''),
      // Only money coming IN settles a ticket. Casso reports outgoing
      // transfers on the same feed as negative amounts.
      amountVnd: Math.round(Number(r.amount) || 0),
      memo: String(r.description ?? ''),
      raw: r,
    }));
  }

  if (provider === 'payos') {
    const d = body?.data || {};
    return [{
      externalId: String(d.reference ?? d.orderCode ?? d.transactionDateTime ?? ''),
      amountVnd: Math.round(Number(d.amount) || 0),
      memo: String(d.description ?? d.content ?? ''),
      raw: d,
    }];
  }

  // Generic: a bank API or a self-hosted bridge posting one transaction.
  return [{
    externalId: String(body?.id ?? body?.transaction_id ?? body?.reference ?? ''),
    amountVnd: Math.round(Number(body?.amount ?? body?.amount_vnd) || 0),
    memo: String(body?.description ?? body?.memo ?? body?.content ?? ''),
    raw: body ?? {},
  }];
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' });
  }

  const admin = getSupabaseAdmin();
  if (!admin) return res.status(503).json({ error: 'SUPABASE_SERVICE_ROLE_KEY_NOT_SET' });

  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const provider = String(req.query?.provider || 'casso').toLowerCase();

  // ---- authenticate the sender ----
  let signatureOk = false;
  if (provider === 'casso') {
    // Casso sends a fixed shared secret in a header. It is not a signature
    // over the body, so it proves origin but not integrity — which is
    // precisely why the amount is re-checked against the booking downstream
    // rather than trusted from this payload.
    const secret = process.env.CASSO_WEBHOOK_SECRET;
    const token = req.headers['secure-token'] || req.headers['x-secure-token'];
    signatureOk = !!secret && safeEqual(token, secret);
  } else if (provider === 'payos') {
    signatureOk = payosSignatureValid(body?.data, body?.signature, process.env.PAYOS_CHECKSUM_KEY);
  } else {
    const secret = process.env.BANK_WEBHOOK_SECRET;
    const given = req.headers['x-webhook-secret'];
    signatureOk = !!secret && safeEqual(given, secret);
  }

  if (!signatureOk) {
    // A wrong secret is a real 401 — this one should NOT be retried, and
    // silently accepting it would let anyone confirm any ticket for free.
    console.warn('payment-webhook: rejected unsigned/mis-signed delivery', { provider });
    return res.status(401).json({ error: 'INVALID_SIGNATURE' });
  }

  const transactions = normalise(provider, body).filter((t) => t.externalId);
  if (!transactions.length) {
    return res.status(200).json({ ok: true, processed: 0, note: 'no usable transactions' });
  }

  const results = [];
  for (const txn of transactions) {
    // Outgoing money never settles an incoming ticket payment.
    if (txn.amountVnd <= 0) {
      results.push({ externalId: txn.externalId, match_status: 'ignored_outgoing' });
      continue;
    }
    try {
      const { data, error } = await admin.rpc('record_bank_transaction', {
        p_provider: provider,
        p_external_id: txn.externalId,
        p_amount_vnd: txn.amountVnd,
        p_memo: txn.memo,
        p_raw: txn.raw,
        p_signature_ok: true,
      });
      if (error) throw error;
      results.push({ externalId: txn.externalId, ...(data || {}) });
    } catch (e) {
      // Log and keep going: one unmatchable row must not stop the rest of a
      // batch, and a 500 here would make the provider resend the whole batch
      // including the ones already settled.
      console.warn('payment-webhook: record_bank_transaction failed', txn.externalId, e?.message);
      results.push({ externalId: txn.externalId, match_status: 'error' });
    }
  }

  const matched = results.filter((r) => r.match_status === 'matched').length;
  return res.status(200).json({ ok: true, processed: results.length, matched, results });
}

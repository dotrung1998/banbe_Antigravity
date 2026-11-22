import crypto from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

// Inbound bank-transaction webhook — the automated reconciliation path.
//
// Supports the services a Vietnamese organizer realistically uses to get
// real-time balance changes off a personal/business account (SePay, Casso and
// PayOS), plus a generic shape for a direct banking API. All of them normalise
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

/**
 * SePay HMAC-SHA256: signs `${timestamp}.${rawBody}` with the webhook secret
 * and sends `X-SePay-Signature: sha256=<hex>` plus `X-SePay-Timestamp`
 * (Unix seconds). More than 5 minutes of clock drift is rejected (replay).
 * Docs: developer.sepay.vn/en/sepay-webhooks/xac-thuc
 *
 * IMPORTANT: SePay signs the raw request bytes. `rawBody` must be the body as
 * received, not JSON.stringify(parsedBody): escaping, key order and whitespace
 * can differ. Where the runtime only exposes a parsed body (Vercel Node
 * functions), use the API Key method instead — HMAC there is best-effort.
 */
function sepaySignatureValid({ signature, timestamp, rawBody, secret, now = Math.floor(Date.now() / 1000) }) {
  if (!secret || !signature || !timestamp || typeof rawBody !== 'string') return false;
  const ts = Number(timestamp);
  if (!Number.isFinite(ts) || Math.abs(now - ts) > 300) return false;
  const expected = `sha256=${crypto.createHmac('sha256', secret)
    .update(`${String(timestamp)}.${rawBody}`)
    .digest('hex')}`;
  return safeEqual(expected, signature);
}

/** SePay API Key: `Authorization: Apikey <key>`. */
function sepayApiKeyValid(authorization, key) {
  if (!key) return false;
  const match = /^Apikey\s+(.+)$/i.exec(String(authorization ?? '').trim());
  return !!match && safeEqual(match[1], key);
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

  if (provider === 'sepay') {
    // SePay posts one transaction per delivery:
    // { id, gateway, transactionDate, accountNumber, code, content,
    //   transferType: 'in'|'out', transferAmount, description, referenceCode }
    // `content` is what the payer typed (our ART reference lives there);
    // `description` is the bank's own text. `id` is stable across retries,
    // which is what the unique (provider, external_id) index dedupes on.
    const amount = Math.abs(Math.round(Number(body?.transferAmount) || 0));
    const incoming = String(body?.transferType ?? 'in').toLowerCase() !== 'out';
    return [{
      externalId: String(body?.id ?? body?.referenceCode ?? ''),
      // SePay reports outgoing transfers with a positive `transferAmount`;
      // flip the sign so the shared "amount <= 0" guard below ignores them.
      amountVnd: incoming ? amount : -amount,
      memo: [body?.content, body?.description]
        .filter((v) => typeof v === 'string' && v.trim()).join(' '),
      raw: body ?? {},
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

  // Raw body for SePay's HMAC. Some runtimes keep it (`req.rawBody`, or a
  // Worker's request.text()); Vercel's Node runtime parses JSON before this
  // handler and has no raw copy, so the fallback re-serialises. See
  // sepaySignatureValid().
  const rawBody = Buffer.isBuffer(req.rawBody) ? req.rawBody.toString('utf8')
    : typeof req.rawBody === 'string' ? req.rawBody
    : typeof req.body === 'string' ? req.body
    : JSON.stringify(req.body ?? {});

  let body = req.body;
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch { body = {}; }
  }
  if (!body || typeof body !== 'object') body = {};
  const provider = String(req.query?.provider || 'casso').toLowerCase();

  // SePay counts a delivery as successful only when the JSON body contains
  // `success: true` (HTTP 200/201); anything else is logged as failed.
  const reply = (status, payload) => res.status(status).json(
    provider === 'sepay'
      ? { success: status >= 200 && status < 300, ...payload }
      : payload,
  );

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
  } else if (provider === 'sepay') {
    // SePay offers API Key or HMAC-SHA256 per webhook. Accept either one that
    // is configured, so switching methods needs no downtime.
    signatureOk = sepayApiKeyValid(req.headers.authorization, process.env.SEPAY_API_KEY)
      || sepaySignatureValid({
        signature: req.headers['x-sepay-signature'],
        timestamp: req.headers['x-sepay-timestamp'],
        rawBody,
        secret: process.env.SEPAY_WEBHOOK_SECRET,
      });
  } else {
    const secret = process.env.BANK_WEBHOOK_SECRET;
    const given = req.headers['x-webhook-secret'];
    signatureOk = !!secret && safeEqual(given, secret);
  }

  if (!signatureOk) {
    // A wrong secret is a real 401 — this one should NOT be retried, and
    // silently accepting it would let anyone confirm any ticket for free.
    console.warn('payment-webhook: rejected unsigned/mis-signed delivery', { provider });
    return reply(401, { error: 'INVALID_SIGNATURE' });
  }

  const transactions = normalise(provider, body).filter((t) => t.externalId);
  if (!transactions.length) {
    return reply(200, { ok: true, processed: 0, note: 'no usable transactions' });
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
  return reply(200, { ok: true, processed: results.length, matched, results });
}

export { normalise, sepaySignatureValid, sepayApiKeyValid };

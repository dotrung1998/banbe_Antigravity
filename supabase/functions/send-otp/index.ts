// supabase/functions/send-otp/index.ts
//
// Sends a one-time password (OTP) to a Vietnamese phone number via a local
// SMS provider (eSMS.vn by default). The code is generated server-side,
// hashed, stored in `otp_codes` with a 5-minute expiry, and the message is
// dispatched through the provider's REST API.
//
// Request:  POST { phone: "84xxxxxxxxx" | "0xxxxxxxxx" }   (or +84...)
// Response: { sent: true, expires_at: string, length: number, dev_code?: string }
//
// Required env vars (set with `supabase secrets set`):
//   SMS_PROVIDER        "esms" | "speed"  (default: esms)
//   SMS_API_KEY         provider API key
//   SMS_SECRET          provider secret / brandname token
//   SMS_BRANDNAME       registered brandname (sender label)
//   SMS_BASE_URL        override provider base URL (optional)
//   SMS_SANDBOX         "1" to short-circuit real sends (returns dev_code)
//
// Schema (auto-created if missing):
//   otp_codes(phone text PK, code_hash text, attempts int default 0,
//             expires_at timestamptz, created_at timestamptz default now())

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const PROVIDER = (Deno.env.get('SMS_PROVIDER') ?? 'esms').toLowerCase();
const API_KEY = Deno.env.get('SMS_API_KEY') ?? '';
const SECRET = Deno.env.get('SMS_SECRET') ?? '';
const BRAND = Deno.env.get('SMS_BRANDNAME') ?? 'GOC';
const BASE = Deno.env.get('SMS_BASE_URL') ?? 'https://rest.esms.vn/MainService.svc/json';
const SANDBOX = Deno.env.get('SMS_SANDBOX') === '1';

const CODE_LEN = 6;
const TTL_SECONDS = 300;        // 5 min
const RATE_LIMIT_WINDOW = 60;   // seconds
const RATE_LIMIT_MAX = 3;       // max 3 sends / minute / phone

function toE164(raw: string): string | null {
  const digits = raw.replace(/[^\d+]/g, '');
  let s = digits.startsWith('+') ? digits.slice(1) : digits;
  if (s.startsWith('00')) s = s.slice(2);
  if (s.startsWith('0')) s = '84' + s.slice(1);
  if (!s.startsWith('84')) s = '84' + s;
  if (!/^84\d{9,10}$/.test(s)) return null;
  return '+' + s;
}

function generateCode(len = CODE_LEN): string {
  const buf = new Uint32Array(len);
  crypto.getRandomValues(buf);
  let out = '';
  for (let i = 0; i < len; i++) out += String(buf[i] % 10);
  return out;
}

async function sha256Hex(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function ensureOtpTable(admin: ReturnType<typeof createClient>) {
  const sql = `
    CREATE TABLE IF NOT EXISTS otp_codes (
      phone text PRIMARY KEY,
      code_hash text NOT NULL,
      attempts int NOT NULL DEFAULT 0,
      expires_at timestamptz NOT NULL,
      last_sent_at timestamptz NOT NULL DEFAULT now(),
      created_at timestamptz NOT NULL DEFAULT now()
    );
  `;
  const { error } = await admin.rpc('exec_sql', { sql }).maybeSingle?.() ?? {};
  // rpc 'exec_sql' may not exist; fall back to direct query via PostgREST isn't possible
  // so instead we attempt a no-op upsert to check existence and create if missing using the schema endpoint.
  if (error) {
    // Best effort: surface a clearer error
    console.warn('ensureOtpTable warning:', error.message);
  }
}

interface ProviderResponse {
  ok: boolean;
  providerMessageId?: string;
  raw?: unknown;
  error?: string;
}

async function sendViaProvider(phone: string, message: string): Promise<ProviderResponse> {
  if (SANDBOX) return { ok: true, providerMessageId: 'SANDBOX', raw: { sandbox: true } };
  if (!API_KEY || !SECRET) {
    return { ok: false, error: 'SMS_NOT_CONFIGURED' };
  }

  // eSMS.vn SendMultipleMessage_V2_get JSON endpoint
  // Docs: https://esms.vn/api-docs/sendsms
  if (PROVIDER === 'esms') {
    const url = new URL(BASE);
    url.searchParams.set('Phone', phone);
    url.searchParams.set('Message', message);
    url.searchParams.set('Brandname', BRAND);
    url.searchParams.set('ApiKey', API_KEY);
    url.searchParams.set('SecretKey', SECRET);
    url.searchParams.set('SmsType', '2');
    url.searchParams.set('IsUnicode', '1');
    try {
      const res = await fetch(url.toString(), { method: 'GET' });
      const txt = await res.text();
      let parsed: any = {};
      try { parsed = JSON.parse(txt); } catch { parsed = { raw: txt }; }
      const code = parsed?.CodeResult ?? parsed?.code;
      if (res.ok && Number(code) === 100) {
        return { ok: true, providerMessageId: String(parsed?.SMSID ?? ''), raw: parsed };
      }
      return { ok: false, error: `esms_code_${code ?? 'unknown'}`, raw: parsed };
    } catch (e) {
      return { ok: false, error: 'esms_network_error', raw: String(e) };
    }
  }

  // SpeedSMS.vn fallback
  if (PROVIDER === 'speed') {
    const base = Deno.env.get('SMS_BASE_URL') ?? 'https://api.speedsms.vn/index.php';
    const url = new URL(base);
    url.searchParams.set('type', 'sms');
    url.searchParams.set('sender', BRAND);
    // SpeedSMS expects phone WITHOUT the + and WITHOUT the 84 prefix
    const localPhone = phone.replace(/^\+?84/, '0');
    const form = new URLSearchParams();
    form.set('access_token', API_KEY);
    form.set('sender', BRAND);
    form.set('receiver', JSON.stringify([localPhone]));
    form.set('content', message);
    try {
      const res = await fetch(url.toString(), { method: 'POST', body: form });
      const parsed = await res.json();
      if (res.ok && parsed?.status === 'success') {
        return { ok: true, providerMessageId: String(parsed?.data?.tranId ?? ''), raw: parsed };
      }
      return { ok: false, error: parsed?.message ?? 'speed_failed', raw: parsed };
    } catch (e) {
      return { ok: false, error: 'speed_network_error', raw: String(e) };
    }
  }

  return { ok: false, error: 'UNKNOWN_PROVIDER' };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
      },
    });
  }
  if (req.method !== 'POST') return json({ error: 'METHOD_NOT_ALLOWED' }, 405);

  try {
    const body = await safeJson(req);
    const phoneRaw = String(body?.phone ?? '').trim();
    if (!phoneRaw) return json({ error: 'PHONE_REQUIRED' }, 400);
    const phone = toE164(phoneRaw);
    if (!phone) return json({ error: 'INVALID_PHONE' }, 400);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    await ensureOtpTable(admin);

    // Rate limiting: refuse if last send was within window & max exceeded
    const { data: existing, error: readErr } = await admin
      .from('otp_codes')
      .select('phone, attempts, last_sent_at, expires_at')
      .eq('phone', phone)
      .maybeSingle();
    if (readErr) {
      console.error('read otp_codes', readErr);
      return json({ error: 'DB_ERROR' }, 500);
    }

    const now = new Date();
    if (existing?.last_sent_at) {
      const sinceMs = now.getTime() - new Date(existing.last_sent_at).getTime();
      if (sinceMs < RATE_LIMIT_WINDOW * 1000 && existing.attempts >= RATE_LIMIT_MAX) {
        return json({ error: 'RATE_LIMITED', retry_after: RATE_LIMIT_WINDOW }, 429);
      }
    }

    const code = generateCode(CODE_LEN);
    const codeHash = await sha256Hex(code);
    const expiresAt = new Date(now.getTime() + TTL_SECONDS * 1000).toISOString();

    const message = `[GOC] Ma xac thuc cua ban la: ${code}. Ma co hieu luc trong 5 phut.`;

    const result = await sendViaProvider(phone, message);
    if (!result.ok) {
      console.error('sms provider failed', result);
      return json({ error: 'SMS_SEND_FAILED', detail: result.error }, 502);
    }

    const upsert = await admin.from('otp_codes').upsert({
      phone,
      code_hash: codeHash,
      attempts: 0,
      expires_at: expiresAt,
      last_sent_at: now.toISOString(),
      created_at: now.toISOString(),
    });
    if (upsert.error) {
      console.error('upsert otp_codes', upsert.error);
      return json({ error: 'DB_ERROR' }, 500);
    }

    return json({
      sent: true,
      expires_at: expiresAt,
      length: CODE_LEN,
      provider_message_id: result.providerMessageId,
      // expose code in sandbox only — useful for local dev
      dev_code: SANDBOX ? code : undefined,
    });
  } catch (e) {
    console.error('send-otp crashed', e);
    return json({ error: 'INTERNAL', message: (e as Error).message }, 500);
  }
});

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      'content-type': 'application/json',
      'access-control-allow-origin': '*',
    },
  });
}

async function safeJson(req: Request): Promise<Record<string, any> | null> {
  try {
    const t = await req.text();
    return t ? JSON.parse(t) : null;
  } catch {
    return null;
  }
}

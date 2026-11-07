// supabase/functions/send-otp/verify.ts
//
// Companion verifier: checks a code against the otp_codes table.
// Request:  POST { phone: string, code: string }
// Response: { valid: true } | { valid: false, reason: 'EXPIRED'|'NO_MATCH'|'NOT_FOUND' }

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

async function sha256Hex(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'content-type' },
    });
  }
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  try {
    const { phone, code } = await req.json();
    if (!phone || !code) return new Response(JSON.stringify({ valid: false, reason: 'BAD_INPUT' }), { status: 400 });

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });
    const { data: row } = await admin.from('otp_codes').select('*').eq('phone', phone).maybeSingle();
    if (!row) return new Response(JSON.stringify({ valid: false, reason: 'NOT_FOUND' }), { status: 200 });
    if (new Date(row.expires_at) < new Date()) {
      return new Response(JSON.stringify({ valid: false, reason: 'EXPIRED' }), { status: 200 });
    }
    const hash = await sha256Hex(String(code).trim());
    if (hash !== row.code_hash) {
      await admin.from('otp_codes').update({ attempts: (row.attempts ?? 0) + 1 }).eq('phone', phone);
      return new Response(JSON.stringify({ valid: false, reason: 'NO_MATCH' }), { status: 200 });
    }
    // success: consume the code
    await admin.from('otp_codes').delete().eq('phone', phone);
    return new Response(JSON.stringify({ valid: true }), {
      status: 200,
      headers: { 'content-type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ valid: false, reason: 'ERROR', detail: String(e) }), { status: 500 });
  }
});

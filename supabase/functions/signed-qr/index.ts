// supabase/functions/signed-qr/index.ts
//
// Returns a short-lived signed URL for an object stored in the private
// `pay-qr` bucket. Authorization mirrors the storage RLS policy:
//   1. caller must be authenticated
//   2. caller must be either the organizer owner (o.owner_id = auth.uid())
//      or hold a confirmed/attended booking for any event by that organizer
//
// Request: POST { path: string, expires_in?: number }   (or `?path=...&expires_in=...`)
// Response: { url: string, expires_at: string, path: string }

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const DEFAULT_TTL = 60; // seconds

// Path layout we expect in the bucket: `<organizer_id>/<filename>`
function parsePath(path: string): { organizerId: string; objectPath: string } {
  const clean = path.replace(/^\/+/, '').trim();
  const parts = clean.split('/');
  if (parts.length < 2) {
    throw new Error('INVALID_PATH');
  }
  return { organizerId: parts[0], objectPath: clean };
}

async function isOrganizerOwner(
  admin: ReturnType<typeof createClient>,
  organizerId: string,
  userId: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from('organizers')
    .select('id')
    .eq('id', organizerId)
    .or(`owner_id.eq.${userId},user_id.eq.${userId}`)
    .maybeSingle();
  if (error) throw error;
  return !!data;
}

async function hasActiveBooking(
  admin: ReturnType<typeof createClient>,
  organizerId: string,
  userId: string,
): Promise<boolean> {
  // active = confirmed or attended (matches storage policy)
  const { data, error } = await admin
    .from('bookings')
    .select('id, events!inner(organizer_id), status')
    .eq('user_id', userId)
    .in('status', ['confirmed', 'attended'])
    .eq('events.organizer_id', organizerId)
    .limit(1);
  if (error) throw error;
  return Array.isArray(data) && data.length > 0;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
        'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
      },
    });
  }

  if (req.method !== 'POST' && req.method !== 'GET') {
    return json({ error: 'METHOD_NOT_ALLOWED' }, 405);
  }

  try {
    // 1. Auth: validate the JWT sent by the client
    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.replace(/^Bearer\s+/i, '').trim();
    if (!token) return json({ error: 'AUTH_REQUIRED' }, 401);

    const userClient = createClient(SUPABASE_URL, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userErr } = await userClient.auth.getUser(token);
    if (userErr || !userData?.user) return json({ error: 'INVALID_TOKEN' }, 401);
    const userId = userData.user.id;

    // 2. Pull path + ttl
    let path: string | null = null;
    let expiresIn = DEFAULT_TTL;
    if (req.method === 'GET') {
      const url = new URL(req.url);
      path = url.searchParams.get('path');
      const t = url.searchParams.get('expires_in');
      if (t) expiresIn = Math.max(10, Math.min(600, parseInt(t, 10) || DEFAULT_TTL));
    } else {
      const body = await safeJson(req);
      path = body?.path ?? null;
      if (body?.expires_in) expiresIn = Math.max(10, Math.min(600, parseInt(body.expires_in, 10) || DEFAULT_TTL));
    }
    if (!path) return json({ error: 'PATH_REQUIRED' }, 400);

    const { organizerId, objectPath } = parsePath(path);

    // 3. Admin (service role) client for authz checks
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const [owner, active] = await Promise.all([
      isOrganizerOwner(admin, organizerId, userId),
      hasActiveBooking(admin, organizerId, userId),
    ]);
    if (!owner && !active) return json({ error: 'NOT_AUTHORIZED' }, 403);

    // 4. Generate signed URL (uses service role to bypass RLS as the user is already authorized)
    const { data: signed, error: signErr } = await admin
      .storage
      .from('pay-qr')
      .createSignedUrl(objectPath, expiresIn);
    if (signErr || !signed?.signedUrl) {
      console.error('signed-url error', signErr);
      return json({ error: 'SIGN_FAILED', detail: signErr?.message }, 500);
    }

    const expiresAt = new Date(Date.now() + expiresIn * 1000).toISOString();
    return json({ url: signed.signedUrl, expires_at: expiresAt, path: objectPath }, 200);
  } catch (e) {
    console.error('signed-qr crashed', e);
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

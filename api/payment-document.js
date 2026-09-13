import { createClient } from '@supabase/supabase-js';
import { renderPaymentDocument } from '../src/lib/paymentDocument.js';

// Renders one invoice or receipt as a standalone HTML page.
//
// Exists so the iOS app doesn't need its own copy of the document layout.
// A second renderer is a second thing to keep in sync, and the failure mode
// — a receipt that looks different depending on which app produced it — is
// exactly the kind of discrepancy a document is supposed to rule out. iOS
// loads this in a web view and prints from it; the web app renders the same
// module locally.
//
// Authorization is deliberately RLS and nothing else: the request is made
// with the caller's own access token, so the two policies from migration 024
// ("the guest it belongs to" / "the organizer who issued it") decide, and
// there is no second copy of that rule here to drift from them.

function getText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' });
  }

  // Same fallback constants src/lib/supabase.js bundles into the web app —
  // the anon key is meant to be public (it only ever acts as `anon` or
  // `authenticated` under RLS) and is already shipped in the client bundle
  // and committed in .env.example. Without this fallback, this endpoint 503s
  // on any deployment where only VITE_SUPABASE_* (baked in at build time,
  // not necessarily present as an actual Vercel env var) was ever set.
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL
    || 'https://ukchdgdnwytretvqjjqu.supabase.co';
  const anonKey = process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY
    || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVrY2hkZ2Rud3l0cmV0dnFqanF1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg3MjMyMjYsImV4cCI6MjEwNDI5OTIyNn0.TgyEJLTXTZgCa6ulsseY3JlrdSmEfOgqVPNh0nSgu90';
  if (!url || !anonKey) {
    return res.status(503).json({ error: 'SUPABASE_NOT_CONFIGURED' });
  }

  // Accept the token from the header (iOS sets it on the web view's initial
  // request) or from ?token= (a web view redirect can't always carry one).
  const headerToken = getText((req.headers.authorization || '').replace(/^Bearer\s+/i, ''));
  const token = headerToken || getText(req.query?.token);
  if (!token) return res.status(401).json({ error: 'AUTH_REQUIRED' });

  const id = getText(req.query?.id);
  if (!UUID_PATTERN.test(id)) return res.status(400).json({ error: 'VALID_DOCUMENT_REQUIRED' });

  const lang = getText(req.query?.lang) === 'en' ? 'en' : 'vi';

  const client = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  try {
    const { data: doc, error } = await client
      .from('payment_documents')
      .select('*')
      .eq('id', id)
      .maybeSingle();
    if (error) throw error;
    // Indistinguishable from "exists but isn't yours" on purpose — a 403
    // here would confirm the id of somebody else's receipt.
    if (!doc) return res.status(404).json({ error: 'DOCUMENT_NOT_FOUND' });

    const origin = `https://${req.headers.host || 'banbe-two.vercel.app'}`;
    const html = renderPaymentDocument(doc, { lang, origin });

    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    // It carries someone's name, address and tax code — never let a shared
    // cache hold on to it.
    res.setHeader('Cache-Control', 'private, no-store');
    return res.status(200).send(html);
  } catch (e) {
    console.warn('payment-document failed:', e);
    return res.status(500).json({ error: 'DOCUMENT_RENDER_FAILED' });
  }
}

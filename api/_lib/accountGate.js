// Server-side account gate for serverless endpoints that validate a user's
// token but then act with the SERVICE ROLE (which bypasses RLS and the API
// pre-request hook). Mirrors migration 123/126: a signed-in session that has
// not finished enrollment / not confirmed its date of birth may not use them.
//
// Calls the same `account_gate_ok()` RPC the database rules use, with the
// CALLER'S OWN token, so the answer is about that exact session.
//   true  -> allowed
//   false -> blocked (respond 403 ACCOUNT_GATE_REQUIRED)
// If the function doesn't exist yet (migration not deployed) it is allowed, so
// this can ship before the migration. Any other failure is treated as blocked.

export async function accountGateStatus(token) {
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY;
  if (!url || !anonKey || !token) return { ok: false, reason: 'GATE_CHECK_UNAVAILABLE' };
  try {
    const response = await fetch(`${url.replace(/\/$/, '')}/rest/v1/rpc/account_gate_ok`, {
      method: 'POST',
      headers: { apikey: anonKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: '{}',
    });
    if (response.status === 404) return { ok: true }; // function not deployed
    if (response.status === 403) return { ok: false, reason: 'ACCOUNT_GATE_REQUIRED' };
    if (!response.ok) return { ok: false, reason: 'GATE_CHECK_FAILED' };
    const value = await response.json();
    return value === true ? { ok: true } : { ok: false, reason: 'ACCOUNT_GATE_REQUIRED' };
  } catch {
    return { ok: false, reason: 'GATE_CHECK_FAILED' };
  }
}

/** Sends the 403/503 and returns true when the caller must stop. */
export async function rejectIfGated(res, token) {
  const gate = await accountGateStatus(token);
  if (gate.ok) return false;
  res.status(gate.reason === 'ACCOUNT_GATE_REQUIRED' ? 403 : 503).json({ error: gate.reason });
  return true;
}

import { createHmac, timingSafeEqual } from 'node:crypto';

// Stateless proof that the caller just completed the emailed-code re-authentication for account
// deletion. Verifying that code on the CLIENT (supabase.auth.verifyOtp) creates a brand-new session,
// which the server's account gate then answers with a date-of-birth re-confirmation, interrupting
// the deletion flow. Instead /api/auth verifies the code on a throwaway client (the user's own
// session is untouched) and hands back this short-lived HMAC proof, which delete_account requires.

export const REAUTH_PROOF_TTL_MS = 10 * 60 * 1000;

const mac = (payload, key) => createHmac('sha256', key).update(`reauth:${payload}`).digest('hex');

export function signReauthProof(userId, key, now = Date.now()) {
  if (!userId || !key) return '';
  const payload = `${userId}.${now + REAUTH_PROOF_TTL_MS}`;
  return `${payload}.${mac(payload, key)}`;
}

export function verifyReauthProof(proof, userId, key, now = Date.now()) {
  if (!proof || !userId || !key || typeof proof !== 'string') return false;
  const parts = proof.split('.');
  if (parts.length !== 3) return false;
  const [uid, exp, sig] = parts;
  if (uid !== userId) return false;
  const expiresAt = Number(exp);
  if (!Number.isFinite(expiresAt) || expiresAt < now) return false;
  const expected = Buffer.from(mac(`${uid}.${exp}`, key));
  const given = Buffer.from(sig);
  return expected.length === given.length && timingSafeEqual(expected, given);
}

// Event Project Hub invites (note 76): what a scanned QR, a pasted link or a typed code points at.
// iOS twin: apps/ios/BanbeApp/Lib/ProjectInviteLink.swift. Shared vectors: tests/fixtures/project-invite-links.json.
//
// The link only ever carries an opaque value. The role and lane live with the invite on the server, so editing a link
// can never change them. Two forms:
// - token: 22 URL-safe base64 characters (128 random bits), used in links and QR codes;
// - code: "BB-" + 4 characters from a 31-symbol alphabet with no 0/O/1/I/L, for typing by hand.
// Links: https://www.banbe.app/join/<value>, https://banbe.app/join/<value> and banbe://join/<value>, where value
// is a token or a code. This is not the referral link (https://www.banbe.app/?ref=CODE), which stays separate.

export const INVITE_CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
export const JOIN_URL_BASE = 'https://www.banbe.app/join/';

const TOKEN_RE = /^[A-Za-z0-9_-]{22}$/;
const CODE_BODY_RE = new RegExp(`^[${INVITE_CODE_ALPHABET}]{4}$`);
const WEB_RE = /^https:\/\/(?:www\.)?banbe\.app\/join\/([^/?#]+)\/?(?:[?#].*)?$/i;
const APP_RE = /^banbe:\/\/join\/([^/?#]+)\/?(?:[?#].*)?$/i;

/** "bb h3qd", "BB–H3QD", "bbh3qd" or "h3qd" -> "BB-H3QD"; null when it is not a valid code. */
export function normalizeInviteCode(input) {
  let s = String(input ?? '').trim().toUpperCase().replace(/[\s\-‐-―]/g, '');
  if (s.startsWith('BB') && s.length === 6) s = s.slice(2);
  return CODE_BODY_RE.test(s) ? `BB-${s}` : null;
}

function valueOf(raw) {
  let v;
  try { v = decodeURIComponent(raw); } catch { return null; }
  if (TOKEN_RE.test(v)) return { kind: 'token', token: v };
  const code = normalizeInviteCode(v);
  return code ? { kind: 'code', code } : null;
}

/** A join link, a bare token or a typed code -> { kind: 'token', token } | { kind: 'code', code } | null. */
export function parseInvite(input) {
  const s = String(input ?? '').trim();
  if (!s) return null;
  const m = s.match(WEB_RE) || s.match(APP_RE);
  if (m) return valueOf(m[1]);
  if (/^[a-z][a-z0-9+.-]*:/i.test(s)) return null; // some other link: never guess
  return valueOf(s);
}

/** The shareable link (and QR content) for a token. */
export function joinUrl(token) {
  if (!TOKEN_RE.test(String(token ?? ''))) throw new Error('joinUrl: not an invite token');
  return JOIN_URL_BASE + token;
}

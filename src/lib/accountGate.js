// ---- account gate (web parity) ----
// Client mirror of iOS AuthViewModel+Gate.swift. The server owns the rule
// (migration 123: account_gate_status()/account_gate_ok(), enforced by RLS);
// this module only reads it and exposes the RPCs the gate screen calls.
// Booleans only — the stored date of birth is never sent to a client.
//
// Own tiny store (not BanBeContext) so the gate can't be skipped by app
// navigation: App.jsx mounts <AccountGate/> as an overlay above every screen
// whenever `blocking` is true.

import { useSyncExternalStore } from 'react';
import { supabase } from './supabase.js';

// gate: 'none' (signed out) | 'unknown' (first check pending) | 'ready' | 'blocked' | 'unavailable'
let snap = { gate: 'none', status: null, uid: null };
const listeners = new Set();
const emit = (patch) => { snap = { ...snap, ...patch }; listeners.forEach(l => l()); };

const isMissingFn = (error) => !!error && (
  error.code === 'PGRST202' || error.code === '42883' || /could not find the function/i.test(error.message || '')
);

let inflight = null;
export function refreshGate() {
  if (inflight) return inflight;
  inflight = (async () => {
    try {
      const { data: sess } = await supabase.auth.getSession();
      if (!sess.session) { emit({ gate: 'none', status: null, uid: null }); return; }
      const { data, error } = await supabase.rpc('account_gate_status');
      if (error) {
        // Migration 123 not deployed: no server rule to enforce.
        if (isMissingFn(error)) emit({ gate: 'ready' });
        else if (snap.gate === 'unknown' || snap.gate === 'none') emit({ gate: 'unavailable' });
        return;
      }
      const wasBlocked = snap.gate === 'blocked' || snap.gate === 'unavailable' || snap.gate === 'unknown';
      emit({ gate: data?.ready ? 'ready' : 'blocked', status: data || null });
      // Profile/booking reads were blocked by RLS while gated; a token refresh
      // re-fires onAuthStateChange so BanBeContext re-syncs the user profile.
      if (data?.ready && wasBlocked) supabase.auth.refreshSession().catch(() => {});
    } catch {
      if (snap.gate === 'unknown' || snap.gate === 'none') emit({ gate: 'unavailable' });
    } finally { inflight = null; }
  })();
  return inflight;
}

let started = false;
function start() {
  if (started || typeof window === 'undefined') return;
  started = true;
  const onSession = (session) => {
    if (!session?.user) { emit({ gate: 'none', status: null, uid: null }); return; }
    if (snap.uid !== session.user.id) emit({ gate: 'unknown', status: null, uid: session.user.id });
    // Never call supabase from inside the auth callback itself.
    setTimeout(refreshGate, 0);
  };
  supabase.auth.getSession().then(({ data }) => onSession(data.session));
  supabase.auth.onAuthStateChange((_e, session) => onSession(session));
}

const subscribe = (l) => { start(); listeners.add(l); return () => listeners.delete(l); };
const getSnap = () => snap;
export function useAccountGate() {
  const s = useSyncExternalStore(subscribe, getSnap, getSnap);
  return { ...s, blocking: s.gate !== 'none' && s.gate !== 'ready' };
}

// ---- Phone (real SMS OTP, attached to THIS user as a pending phone change) ----
const phoneFailure = (error) => {
  const code = error?.code || '';
  if (code === 'phone_exists') return 'phoneInUse';
  if (code === 'over_sms_send_rate_limit' || code === 'over_request_rate_limit') return 'rateLimited';
  if (code === 'sms_send_failed' || code === 'phone_provider_disabled' || code === 'otp_disabled') return 'providerUnavailable';
  if (code === 'otp_expired') return 'expired';
  if (code === 'validation_failed') return 'invalidNumber';
  if (error && (error.name === 'AuthRetryableFetchError' || /fetch|network/i.test(error.message || ''))) return 'network';
  return 'other';
};
export const sendPhoneCode = async (e164) => {
  const { error } = await supabase.auth.updateUser({ phone: e164 });
  return error ? phoneFailure(error) : null;
};
export const resendPhoneCode = async (e164) => {
  const { error } = await supabase.auth.resend({ type: 'phone_change', phone: e164 });
  return error ? phoneFailure(error) : null;
};
export const verifyPhoneCode = async (e164, code) => {
  const { error } = await supabase.auth.verifyOtp({ phone: e164, token: code, type: 'phone_change' });
  if (error) { const f = phoneFailure(error); return f === 'other' || f === 'invalidNumber' ? 'wrongCode' : f; }
  await refreshGate();
  return null;
};

export function phoneFailureText(f, T) {
  switch (f) {
    case 'phoneInUse': return T('Số này đã được liên kết với tài khoản khác. Hãy dùng số khác.', 'This number is already linked to another account. Use a different number.');
    case 'rateLimited': return T('Bạn đã yêu cầu quá nhiều mã. Vui lòng thử lại sau.', 'Too many code requests. Please try again later.');
    case 'providerUnavailable': return T('Chưa gửi được SMS: dịch vụ SMS chưa được cấu hình hoặc đang lỗi. Số của bạn chưa được xác minh.', "Couldn't send the SMS: the SMS service isn't configured or is failing. Your number has NOT been verified.");
    case 'invalidNumber': return T('Số điện thoại chưa hợp lệ.', "That phone number isn't valid.");
    case 'expired': return T('Mã đã hết hạn. Hãy gửi lại mã mới.', 'That code expired. Request a new one.');
    case 'wrongCode': return T('Mã chưa đúng. Thử lại.', "That code isn't right. Try again.");
    case 'network': return T('Không có kết nối. Thử lại.', 'No connection. Try again.');
    default: return T('Chưa thực hiện được. Thử lại sau.', "That didn't work. Please try again later.");
  }
}

// ---- Date of birth ----
export async function submitEnrollmentDob(iso) {
  const { data, error } = await supabase.rpc('set_date_of_birth', { p_dob: iso });
  if (error || data?.success !== true) return false;
  await refreshGate();
  return true;
}

/** -> { result: 'success'|'incorrect'|'locked'|'failed', attemptsLeft?, retryAfter? } */
export async function confirmDob(iso) {
  const { data, error } = await supabase.rpc('confirm_date_of_birth', { p_dob: iso });
  if (error || !data) return { result: 'failed' };
  if (data.success === true) { await refreshGate(); return { result: 'success' }; }
  if (data.error === 'INCORRECT') return { result: 'incorrect', attemptsLeft: data.attempts_left };
  if (data.error === 'LOCKED') return { result: 'locked', retryAfter: data.retry_after_seconds };
  return { result: 'failed' };
}

// ---- Host promo consent (migration 123 §5) ----
export async function getHostPromoConsent() {
  const { data, error } = await supabase.rpc('get_host_promo_consent');
  return !error && data?.success === true ? !!data.consented : null;
}
export async function setHostPromoConsent(enabled) {
  const { data, error } = await supabase.rpc('set_host_promo_consent', { p_enabled: enabled });
  return !error && data?.success === true ? !!data.consented : null;
}

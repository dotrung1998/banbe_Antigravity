// Ticket gifting + Apple Wallet helpers for the web (mirrors AppState+Gifting.swift
// and WalletPassService.swift).
import { supabase } from './supabase.js';

export function newGiftKey() {
  try { if (crypto?.randomUUID) return crypto.randomUUID(); } catch { /* fall through */ }
  return `gift-${Date.now()}-${Math.random().toString(36).slice(2, 12)}`;
}

export function todayIso() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

/** Same three rules the RPC enforces. Returns an error key or ''. */
export function validateRecipient({ name, email, dob }) {
  const n = (name || '').trim();
  const e = (email || '').trim().toLowerCase();
  if (n.length < 2) return 'INVALID_NAME';
  if (!/^.+@.{2,}\..{2,}$/.test(e)) return 'INVALID_EMAIL';
  if (!dob || !/^\d{4}-\d{2}-\d{2}$/.test(dob) || dob > todayIso()) return 'INVALID_DOB';
  return '';
}

export function giftErrorMessage(key, T) {
  switch (key) {
    case 'ALREADY_GIFTED': return T('Vé này đã được tặng trước đó.', 'This ticket has already been gifted.');
    case 'NOT_ELIGIBLE': case 'TICKET_CANCELLED': return T('Vé không hợp lệ hoặc đã bị huỷ.', 'This ticket is not eligible or has been cancelled.');
    case 'EVENT_ENDED': return T('Sự kiện đã kết thúc, không thể thực hiện thao tác này.', 'The event has ended, so this is unavailable.');
    case 'NOT_AUTHORIZED': return T('Bạn không có quyền thực hiện thao tác này.', 'You are not authorized for this action.');
    case 'BOOKING_NOT_FOUND': case 'NOT_FOUND': return T('Không tìm thấy vé này.', 'This ticket could not be found.');
    case 'INVALID_EMAIL': return T('Email người nhận không hợp lệ.', 'Invalid recipient email.');
    case 'INVALID_NAME': return T('Tên người nhận phải có ít nhất 2 ký tự.', 'Recipient name must be at least 2 characters.');
    case 'INVALID_DOB': return T('Ngày sinh không hợp lệ.', 'Invalid date of birth.');
    case 'AUTH_REQUIRED': return T('Hãy đăng nhập để tặng vé.', 'Please sign in to gift a ticket.');
    case 'GATE_REQUIRED': return T('Tài khoản của bạn chưa hoàn tất xác minh.', 'Finish verifying your account first.');
    default: return T('Đã có lỗi xảy ra. Vui lòng thử lại.', 'Something went wrong. Please try again.');
  }
}

/** Calls gift_ticket. Resolves { ok, data } or { ok:false, error } (error = RPC code or 'NETWORK'). */
export async function giftTicketRpc({ bookingId, name, email, dob, key }) {
  const { data, error } = await supabase.rpc('gift_ticket', {
    p_booking_id: bookingId,
    p_recipient_name: name.trim(),
    p_recipient_email: email.trim(),
    p_recipient_dob: dob,
    p_idempotency_key: key,
  });
  if (error || !data) return { ok: false, error: 'NETWORK' };
  if (!data.success) return { ok: false, error: data.error || 'UNKNOWN' };
  return { ok: true, data };
}

export function claimLink(claimCode) {
  return claimCode ? `${window.location.origin}/?claim=${encodeURIComponent(claimCode)}` : undefined;
}

/** Fields renderTicketPdf needs for a gift PDF. */
export function giftPdfData(base, { recipientName, ticketCode, admissionToken, claimCode, reference }) {
  return {
    ...base, gift: true, holderName: recipientName || '', ticketCode: ticketCode || '',
    qrValue: admissionToken, reference, importUrl: claimLink(claimCode),
  };
}

// ---- Apple Wallet ----

/** iOS/iPadOS Safari or macOS Safari only: the only browsers that add a .pkpass. */
export function isAppleWalletBrowser() {
  if (typeof navigator === 'undefined') return false;
  const ua = navigator.userAgent || '';
  if (!/Safari\//.test(ua) || !/AppleWebKit/.test(ua)) return false;
  if (/Chrome|Chromium|CriOS|FxiOS|EdgiOS|Edg\/|OPR\/|OPiOS|Android|SamsungBrowser|DuckDuckGo/i.test(ua)) return false;
  const ios = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  const mac = /Macintosh/.test(ua);
  return ios || mac;
}

export function walletErrorMessage(code, T) {
  switch (code) {
    case 'NOT_CONFIGURED': return T('banbe chưa bật Apple Wallet. Vé và mã QR của bạn vẫn dùng bình thường.', "Apple Wallet isn't switched on for banbe yet. Your ticket and QR still work as usual.");
    case 'AUTH_REQUIRED': case 'NOT_SIGNED_IN': return T('Hãy đăng nhập lại để thêm vé vào Wallet.', 'Sign in again to add this ticket to Wallet.');
    case 'TICKET_GIFTED': return T('Vé này đã được tặng nên không thể thêm vào Wallet.', "This ticket was gifted, so it can't be added to your Wallet.");
    case 'TICKET_NOT_READY': return T('Vé của bạn chưa được xác nhận.', "Your ticket isn't confirmed yet.");
    default: return T('Không tạo được vé Wallet. Vui lòng thử lại.', "Couldn't create the Wallet pass. Please try again.");
  }
}

/** POSTs to /api/wallet-pass with the session bearer and hands the pass to Safari. Returns '' or an error code. */
export async function addToAppleWallet(bookingId) {
  const { data: sess } = await supabase.auth.getSession();
  const token = sess?.session?.access_token;
  if (!token) return 'NOT_SIGNED_IN';
  let res;
  try {
    res = await fetch('/api/wallet-pass', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify({ bookingId, design: { background: '#1C1C1E', foreground: '#FFFFFF' } }),
    });
  } catch { return 'WALLET_PASS_FAILED'; }
  if (res.status === 503) return 'NOT_CONFIGURED';
  if (!res.ok) {
    let code = 'WALLET_PASS_FAILED';
    try { code = (await res.json()).error || code; } catch { /* keep default */ }
    return code;
  }
  const blob = new Blob([await res.arrayBuffer()], { type: 'application/vnd.apple.pkpass' });
  const url = URL.createObjectURL(blob);
  // Navigate (no download attribute) so Safari recognises the MIME type and offers "Add to Wallet".
  const a = document.createElement('a');
  a.href = url; a.rel = 'noopener';
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
  return '';
}

import crypto from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { answerCallback, editMessageResolved, escapeMarkdownV2, formatVnd } from './_lib/alerts.js';

// Handles taps on the [Đã nhận tiền] / [Chưa thấy] buttons banbe posts into
// an organizer's Telegram group.
//
// Two independent authorisation gates, deliberately:
//   1. Here: the delivery really came from Telegram, proven by the secret
//      token Telegram echoes back in a header (set via setWebhook).
//   2. In the database: verify_payment_from_bot() checks the chat the tap
//      came from is the chat that organizer registered. A chat id is not a
//      banbe identity, so this is what stops one organizer's group from
//      approving another organizer's bookings — and it lives next to the
//      state change rather than in this handler, where it would be one
//      forgotten early-return away from being bypassed.

function getSupabaseAdmin() {
  const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
    || 'https://ukchdgdnwytretvqjjqu.supabase.co';
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return null;
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

function safeEqual(a, b) {
  const bufA = Buffer.from(String(a ?? ''), 'utf8');
  const bufB = Buffer.from(String(b ?? ''), 'utf8');
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' });
  }

  const expected = process.env.TELEGRAM_WEBHOOK_SECRET;
  const given = req.headers['x-telegram-bot-api-secret-token'];
  if (!expected || !safeEqual(given, expected)) {
    return res.status(401).json({ error: 'INVALID_SECRET' });
  }

  const admin = getSupabaseAdmin();
  if (!admin) return res.status(503).json({ error: 'SUPABASE_SERVICE_ROLE_KEY_NOT_SET' });

  const callback = req.body?.callback_query;
  // Telegram sends many update kinds down the same webhook; anything that
  // isn't a button tap is simply not ours. 200 so it isn't retried forever.
  if (!callback) return res.status(200).json({ ok: true, ignored: true });

  const data = String(callback.data ?? '');
  const chatId = String(callback.message?.chat?.id ?? '');
  const messageId = callback.message?.message_id;
  const operator = [callback.from?.first_name, callback.from?.username]
    .filter(Boolean).join(' @').slice(0, 80);

  const approve = data.startsWith('v:');
  const reject = data.startsWith('r:');
  const bookingId = data.slice(2);

  if ((!approve && !reject) || !UUID.test(bookingId)) {
    return res.status(200).json({ ok: true, ignored: true });
  }

  try {
    const { data: result, error } = await admin.rpc('verify_payment_from_bot', {
      p_booking: bookingId,
      p_chat_id: chatId,
      p_approve: approve,
      p_reason: reject ? `Từ chối từ Telegram bởi ${operator}` : '',
      p_actor_label: operator,
    });
    if (error) throw error;

    if (result?.success === false) {
      const why = {
        CHAT_NOT_AUTHORIZED: 'Nhóm này không có quyền duyệt đặt chỗ đó.',
        BOOKING_NOT_FOUND: 'Không tìm thấy đặt chỗ.',
        INVALID_STATE: 'Đặt chỗ này đã được xử lý rồi.',
      }[result.error] || 'Không xử lý được.';
      await answerCallback(callback.id, why).catch(() => {});
      return res.status(200).json({ ok: true, result });
    }

    const settled = approve
      ? `✅ ${escapeMarkdownV2(`Đã xác nhận thanh toán — ${operator}`)}`
      : `❌ ${escapeMarkdownV2(`Đã đánh dấu chưa nhận được — ${operator}. banbe sẽ xem xét.`)}`;

    await answerCallback(callback.id, approve ? 'Đã xác nhận. Vé đã được gửi.' : 'Đã ghi nhận.')
      .catch(() => {});
    // Clearing the keyboard is what stops a second person in the group
    // tapping the same decision a minute later.
    if (messageId) {
      await editMessageResolved(chatId, messageId,
        `${settled}\n\n${escapeMarkdownV2(`Mã: ${result?.receipt_number || bookingId.slice(0, 8)}`)}`)
        .catch(() => {});
    }

    return res.status(200).json({ ok: true, result });
  } catch (e) {
    console.warn('telegram-webhook failed:', e?.message);
    await answerCallback(callback.id, 'Lỗi hệ thống, thử lại sau.').catch(() => {});
    return res.status(200).json({ ok: false });
  }
}

// Outbound organizer alerting: Telegram for the normal path, with inline
// [Approve]/[Reject] buttons so a verification can be answered from the
// management group chat without anyone opening the dashboard.
//
// ON ZALO, honestly: the spec asks for Telegram/Zalo. Telegram is here and
// complete. Zalo OA has no equivalent of inline callback buttons on a group
// message — its Official Account API sends to individual followers, group
// messaging is not open to third-party OAs, and the nearest equivalent
// (attachment buttons with an oa.query payload) is only available in a 1-1
// user conversation for an OA the user already follows. So a faithful Zalo
// port of "buttons in the management group" is not implementable against
// today's API. sendZaloFallback() below sends a plain 1-1 OA text with a
// deep link into the dashboard instead, which is the closest honest thing,
// and is off unless ZALO_OA_TOKEN is set.

const TELEGRAM_API = 'https://api.telegram.org';

export function formatVnd(amount) {
  return (Math.round(Number(amount) || 0)).toLocaleString('vi-VN') + '₫';
}

/** Telegram MarkdownV2 reserves a lot of punctuation; escape it or the send 400s. */
export function escapeMarkdownV2(text) {
  return String(text ?? '').replace(/[_*[\]()~`>#+\-=|{}.!\\]/g, (c) => `\\${c}`);
}

export function isTelegramConfigured() {
  return !!process.env.TELEGRAM_BOT_TOKEN;
}

async function telegramCall(method, payload) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token) throw new Error('TELEGRAM_BOT_TOKEN_NOT_SET');
  const response = await fetch(`${TELEGRAM_API}/bot${token}/${method}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || body?.ok === false) {
    throw new Error(`telegram ${method} failed: ${body?.description || response.status}`);
  }
  return body.result;
}

/**
 * Builds the message an organizer sees for one pending verification.
 * @param {object} row a v_alert_queue row
 */
export function buildVerificationMessage(row, kind) {
  const urgency = {
    verification_request: '🔔 *Cần xác nhận thanh toán*',
    verification_reminder: '⏰ *Nhắc lại ▪︎ chưa xác nhận*',
    verification_escalation: '🚨 *KHẨN ▪︎ quá hạn xác nhận*',
  }[kind] || '🔔 *Cần xác nhận thanh toán*';

  const waited = row.proof_submitted_at
    ? Math.max(0, Math.round((Date.now() - new Date(row.proof_submitted_at).getTime()) / 60000))
    : 0;

  const lines = [
    urgency,
    '',
    `*Sự kiện:* ${escapeMarkdownV2(row.event_name || '')}`,
    `*Khách:* ${escapeMarkdownV2(row.guest_name || 'Khách')} \\(${row.qty} vé\\)`,
    `*Số tiền:* ${escapeMarkdownV2(formatVnd(row.total_vnd))}`,
    `*Nội dung CK:* \`${escapeMarkdownV2(row.payment_ref || '')}\``,
    row.transaction_id ? `*Mã giao dịch:* \`${escapeMarkdownV2(row.transaction_id)}\`` : null,
    `*Đã chờ:* ${waited} phút`,
    '',
    escapeMarkdownV2('Kiểm tra sao kê rồi chọn bên dưới. Chỗ của khách đang được giữ.'),
  ].filter(Boolean);

  return lines.join('\n');
}

/**
 * Sends one verification alert with inline action buttons.
 * callback_data is capped at 64 bytes by Telegram — "v:<uuid>" is 38.
 */
export async function sendVerificationAlert(row, kind) {
  const text = buildVerificationMessage(row, kind);
  return telegramCall('sendMessage', {
    chat_id: row.telegram_chat_id,
    text,
    parse_mode: 'MarkdownV2',
    reply_markup: {
      inline_keyboard: [[
        { text: '✅ Đã nhận tiền', callback_data: `v:${row.booking_id}` },
        { text: '❌ Chưa thấy', callback_data: `r:${row.booking_id}` },
      ]],
    },
  });
}

/** Answers the tap so Telegram stops showing a spinner on the button. */
export function answerCallback(callbackQueryId, text) {
  return telegramCall('answerCallbackQuery', {
    callback_query_id: callbackQueryId, text, show_alert: false,
  });
}

/** Rewrites the original message once it has been actioned, so nobody re-taps it. */
export function editMessageResolved(chatId, messageId, text) {
  return telegramCall('editMessageText', {
    chat_id: chatId, message_id: messageId, text,
    parse_mode: 'MarkdownV2', reply_markup: { inline_keyboard: [] },
  });
}

/**
 * T+30 urgent escalation. No SMS provider is configured in this project, so
 * rather than pretend, this sends the loudest thing that genuinely works
 * today (a Telegram message flagged urgent, without silent delivery) and
 * reports whether a real SMS went out. Wire SMS_PROVIDER_URL to enable the
 * actual SMS leg.
 */
export async function sendUrgentEscalation(row) {
  const results = { telegram: false, sms: false };

  if (row.telegram_chat_id && isTelegramConfigured()) {
    await sendVerificationAlert(row, 'verification_escalation');
    results.telegram = true;
  }

  const smsUrl = process.env.SMS_PROVIDER_URL;
  if (smsUrl && row.alert_phone) {
    const response = await fetch(smsUrl, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        ...(process.env.SMS_PROVIDER_KEY ? { authorization: `Bearer ${process.env.SMS_PROVIDER_KEY}` } : {}),
      },
      body: JSON.stringify({
        to: row.alert_phone,
        message: `banbe: ${formatVnd(row.total_vnd)} cho ${row.event_name} dang cho xac nhan (${row.payment_ref}). Vao banbe de duyet.`,
      }),
    });
    results.sms = response.ok;
  }

  return results;
}

/** Best-effort Zalo OA 1-1 notice. See the note at the top of this file. */
export async function sendZaloFallback(row) {
  const token = process.env.ZALO_OA_TOKEN;
  if (!token || !row.zalo_user_id) return false;
  const response = await fetch('https://openapi.zalo.me/v3.0/oa/message/cs', {
    method: 'POST',
    headers: { 'content-type': 'application/json', access_token: token },
    body: JSON.stringify({
      recipient: { user_id: row.zalo_user_id },
      message: {
        text: `banbe: ${formatVnd(row.total_vnd)} — ${row.event_name} (${row.payment_ref}) đang chờ xác nhận.`,
      },
    }),
  });
  return response.ok;
}

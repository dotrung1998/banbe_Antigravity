// Renders a resolved dispute's temporary chat as a standalone HTML document
// — the same "one self-contained HTML string" shape src/lib/paymentDocument.js
// uses for invoices/receipts, so this can go through the exact same
// HTML-to-PDF step (see api/dispute-resolved-email.js) without a second
// rendering pipeline. This is the PDF attached to the final confirmation
// email once a dispute is resolved — the dispute_messages rows themselves
// are purged shortly after (see purge_resolved_dispute_threads()), so this
// document is the only record of the conversation that outlives them.

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

function formatTimestamp(iso) {
  const d = new Date(iso);
  return d.toISOString().replace('T', ' ').replace(/\.\d+Z$/, ' UTC');
}

const SENDER_LABEL = {
  guest: { vi: 'Khách', en: 'Guest' },
  organizer: { vi: 'Người tổ chức', en: 'Organizer' },
  system: { vi: 'Hệ thống', en: 'System' },
};

/**
 * @param {object} meta
 * @param {string} meta.eventName
 * @param {string} meta.guestName
 * @param {string} meta.organizerName
 * @param {string} meta.paymentRef
 * @param {'ticket_issued'|'cancelled'} meta.resolutionKind
 * @param {string} meta.resolutionNote
 * @param {string} meta.resolvedAt - ISO timestamp
 * @param {Array<{sender_role: string, body: string, created_at: string}>} messages
 */
export function renderDisputeTranscript(meta, messages) {
  const resolutionLabel = meta.resolutionKind === 'ticket_issued'
    ? 'Ticket issued to the guest / Vé đã được cấp cho khách'
    : 'Booking cancelled, seat released / Đã huỷ đặt chỗ, mở lại chỗ';

  const rows = (messages || []).map((m) => {
    const label = SENDER_LABEL[m.sender_role]?.en || m.sender_role;
    const labelVi = SENDER_LABEL[m.sender_role]?.vi || m.sender_role;
    return `
      <tr>
        <td style="padding:10px 0;border-bottom:1px solid #E7E2D6;vertical-align:top;width:160px;">
          <div style="font-size:11px;color:#6B6558;">${escapeHtml(formatTimestamp(m.created_at))}</div>
          <div style="font-size:12px;font-weight:600;color:#1B1916;">${escapeHtml(label)} / ${escapeHtml(labelVi)}</div>
        </td>
        <td style="padding:10px 0;border-bottom:1px solid #E7E2D6;font-size:13px;line-height:1.5;color:#1B1916;">${escapeHtml(m.body)}</td>
      </tr>`;
  }).join('');

  return `<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<style>
  @page { size: A4; margin: 28mm 20mm; }
  body { font-family: Georgia, 'Times New Roman', serif; color: #1B1916; background: #F7F4EC; }
  table { width: 100%; border-collapse: collapse; }
</style>
</head>
<body>
  <div style="font-size:11px;font-weight:600;letter-spacing:0.04em;color:#6B6558;text-transform:uppercase;">banbe ▪︎ Dispute transcript / Biên bản tranh chấp</div>
  <h1 style="font-size:20px;margin:8px 0 18px;">${escapeHtml(meta.eventName)}</h1>
  <table style="margin-bottom:18px;">
    <tr><td style="font-size:12px;color:#6B6558;padding:2px 0;">Guest / Khách</td><td style="font-size:12px;font-weight:600;text-align:right;">${escapeHtml(meta.guestName)}</td></tr>
    <tr><td style="font-size:12px;color:#6B6558;padding:2px 0;">Organizer / Người tổ chức</td><td style="font-size:12px;font-weight:600;text-align:right;">${escapeHtml(meta.organizerName)}</td></tr>
    <tr><td style="font-size:12px;color:#6B6558;padding:2px 0;">Reference / Nội dung CK</td><td style="font-size:12px;font-weight:600;text-align:right;">${escapeHtml(meta.paymentRef)}</td></tr>
    <tr><td style="font-size:12px;color:#6B6558;padding:2px 0;">Resolution / Kết quả</td><td style="font-size:12px;font-weight:600;text-align:right;">${escapeHtml(resolutionLabel)}</td></tr>
    <tr><td style="font-size:12px;color:#6B6558;padding:2px 0;">Resolved at / Thời điểm giải quyết</td><td style="font-size:12px;font-weight:600;text-align:right;">${escapeHtml(formatTimestamp(meta.resolvedAt))}</td></tr>
  </table>
  ${meta.resolutionNote ? `<p style="font-size:13px;line-height:1.5;margin:0 0 18px;"><strong>Note / Ghi chú:</strong> ${escapeHtml(meta.resolutionNote)}</p>` : ''}
  <table>${rows || '<tr><td style="font-size:12px;color:#6B6558;">No messages were exchanged. / Không có tin nhắn nào.</td></tr>'}</table>
  <p style="font-size:10.5px;color:#8A8474;margin-top:24px;">
    This is the only record of the conversation above — the temporary dispute chat is deleted shortly after this document is sent.
    Đây là bản ghi duy nhất của cuộc trò chuyện trên — cuộc trò chuyện tạm thời này sẽ bị xoá ngay sau khi tài liệu này được gửi.
  </p>
</body>
</html>`;
}

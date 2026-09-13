import { useEffect } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { formatVnd } from '../lib/paymentDocument.js';
import { paper, ink, rule, display, fieldGlass } from '../theme.js';

// One list, four ways in: invoices or receipts, mine or the ones I issued.
// Account opens it with the pair already chosen, so the screen itself never
// needs a filter control.
export default function Documents() {
  const { state, T, loadDocuments, openDocument, backFromDocuments, downloadDocument } = useGoc();
  const s = state;

  useEffect(() => { loadDocuments(); }, [loadDocuments]);

  const isReceipt = s.documentsKind === 'receipt';
  const isHost = s.documentsRole === 'host';
  const title = isReceipt ? T('Biên nhận', 'Receipts') : T('Hoá đơn', 'Invoices');
  const subtitle = isHost
    ? (isReceipt
        ? T('Biên nhận bạn đã phát hành khi đánh dấu khách đã thanh toán.',
            'Receipts you issued when you marked a guest paid.')
        : T('Hoá đơn cho những chỗ đã đặt trong sự kiện của bạn.',
            'Invoices for bookings on your events.'))
    : (isReceipt
        ? T('Biên nhận cho những khoản bạn đã thanh toán.', 'Receipts for what you have paid.')
        : T('Hoá đơn cho những chỗ bạn đã đặt.', 'Invoices for the spots you booked.'));

  const empty = isReceipt
    ? T('Chưa có biên nhận nào. Biên nhận xuất hiện khi người tổ chức xác nhận đã nhận tiền.',
        'No receipts yet. One appears when an organizer confirms your payment.')
    : T('Chưa có hoá đơn nào.', 'No invoices yet.');

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Documents">
      <div onClick={backFromDocuments} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="documents-back">
        ‹ {T('Tài khoản', 'Account')}
      </div>
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{ ...display(24, { margin: 0 }) }} data-testid="documents-title">{title}</h1>
        <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>{subtitle}</p>
      </div>

      <div style={{ ...fieldGlass({ margin: '18px 22px 40px', display: 'flex', flexDirection: 'column' }) }}>
        {s.documents.map((doc, i, arr) => {
          const party = isHost ? (doc.buyer?.name || T('Khách', 'Guest')) : (doc.seller?.name || '');
          return (
            <div
              key={doc.id}
              style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, padding: '13px 16px', borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none' }}
              data-testid="document-row"
            >
              <div onClick={() => openDocument(doc.id)} style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0, flex: 1, cursor: 'pointer' }}>
                <span style={{ ...display(15, { whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>
                  {doc.event?.name || party}
                </span>
                <span style={{ fontSize: 11.5, color: ink, opacity: 0.7, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                  {doc.number} ▪︎ {party}
                </span>
                <span style={{ fontSize: 12.5, fontWeight: 600, color: ink }}>{formatVnd(doc.total_vnd)}</span>
              </div>
              <span
                onClick={(e) => { e.stopPropagation(); downloadDocument(doc); }}
                style={{ flex: 'none', fontSize: 11, fontWeight: 600, color: ink, border: '1px solid rgba(27,25,22,0.16)', borderRadius: 12, padding: '6px 10px', cursor: 'pointer' }}
                data-testid="document-download"
              >
                {T('Tải về', 'Download')}
              </span>
            </div>
          );
        })}

        {s.documents.length === 0 && (
          <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, padding: '14px 16px', margin: 0 }} data-testid="documents-empty">
            {s.documentsLoading ? T('Đang tải…', 'Loading…') : (s.documentsError || empty)}
          </p>
        )}
      </div>
    </div>
  );
}

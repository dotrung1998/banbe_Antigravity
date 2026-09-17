import { useEffect } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { formatVnd, formatShortDate, eventDateAnchor } from '../lib/paymentDocument.js';
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
        {(() => {
          // Only label the live row "Bản hiện tại" when its superseded twin
          // is also in this list (still within the 24h grace window) — in
          // the overwhelmingly common single-version case there's nothing
          // to disambiguate it from, so the label would just be noise.
          const bookingsWithOldCopy = new Set(s.documents.filter(d => d.superseded_at).map(d => d.booking_id));
          return s.documents.map((doc, i, arr) => {
          const party = isHost ? (doc.buyer?.name || T('Khách', 'Guest')) : (doc.seller?.name || '');
          // A raw uploaded file (migration 056) has no real total_vnd — it's
          // a snapshot-free file the organizer handed over, not a
          // structured invoice with actual line items. Showing "0đ" there
          // was never true; caption with the event + date instead, which a
          // legacy structured invoice's already-populated `event` jsonb (or
          // an upload's event_id join, see loadDocuments()) can both supply.
          const hasAmount = Number(doc.total_vnd) > 0;
          // The jsonb `event` snapshot (legacy structured invoices only)
          // shapes its date as {date, time}; the events(...) join used for
          // an uploaded file's row shapes it as {starts_at, event_date,
          // event_time} — same field names as the events table itself,
          // hence eventDateAnchor() (shared with the 057 retention anchor).
          const eventName = doc.event?.name || doc.events?.name || '';
          const eventDateRaw = doc.event?.name
            ? (doc.event.date ? `${doc.event.date}T${doc.event.time || '00:00:00'}` : null)
            : eventDateAnchor(doc.events);
          const eventDate = formatShortDate(eventDateRaw, s.lang);
          // 2026-09-17 follow-up #7 (BUG 2): line 1 below used to read
          // `doc.event?.name || party` directly — for an uploaded document
          // the jsonb `event` snapshot is always empty ({}) AND, from the
          // guest's own view, `party` (doc.seller?.name) is *also* always
          // empty (uploads never populate seller/buyer either) — so line 1
          // rendered as a genuinely blank <span>, which still consumes its
          // own line-height in the flex column. That invisible blank line
          // sitting above the real two-line content block was the actual
          // cause of "the caption still looks off/sits low" — not a
          // padding/line-height issue on the caption itself. Using the
          // already-robust `eventName` (join-aware) fixes line 1 for every
          // uploaded document; the caption below no longer repeats the
          // event name since line 1 now reliably carries it.
          const headline = eventName || party;
          const caption = eventDate; // headline above already carries the event name
          return (
            <div
              key={doc.id}
              style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, padding: '13px 16px', borderBottom: i < arr.length - 1 ? `1px solid ${rule}` : 'none' }}
              data-testid="document-row"
            >
              <div onClick={() => openDocument(doc.id)} style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0, flex: 1, cursor: 'pointer' }}>
                <span style={{ ...display(15, { lineHeight: 1.3, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }) }}>
                  {headline}
                </span>
                <span style={{ fontSize: 11.5, lineHeight: 1.3, color: ink, opacity: 0.7, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                  {doc.number} ▪︎ {party}
                </span>
                {/* Was invisible outside a bare version-count on Attendance
                    only (08-payment-documents.md's 2026-09-17 follow-up #7
                    — BUG 1) — now that loadDocuments() lists a still-live
                    superseded copy alongside the current one, both need a
                    clear label so it's obvious which is which; a superseded
                    row simply stops matching the query (and this label)
                    once purge_after passes, no separate hide-it step. */}
                {doc.superseded_at ? (
                  <span style={{ fontSize: 10.5, lineHeight: 1.3, color: ink, opacity: 0.6 }} data-testid="document-version-label">
                    {T('Bản cũ · xoá sau 24h', 'Old copy · deletes in 24h')}
                  </span>
                ) : bookingsWithOldCopy.has(doc.booking_id) && (
                  <span style={{ fontSize: 10.5, lineHeight: 1.3, color: ink, opacity: 0.6 }} data-testid="document-version-label">
                    {T('Bản hiện tại', 'Current copy')}
                  </span>
                )}
                {hasAmount ? (
                  <span style={{ fontSize: 12.5, lineHeight: 1.3, fontWeight: 600, color: ink }}>{formatVnd(doc.total_vnd)}</span>
                ) : caption ? (
                  // Was 11.5/opacity 0.7, matching the plain "number ▪︎ party"
                  // line above it — too small/faint to read at a glance, and
                  // relying on the browser's default font leading (no
                  // explicit lineHeight, unlike the other two lines here)
                  // let it visually drift low within its own line box.
                  // Bumped to the same size/weight as the amount line it
                  // replaces and given the same explicit lineHeight as its
                  // siblings so all three lines sit on a consistent rhythm.
                  <span style={{ fontSize: 12.5, lineHeight: 1.3, fontWeight: 600, color: ink, opacity: 0.75, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }} data-testid="document-caption">
                    {caption}
                  </span>
                ) : null}
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
        });
        })()}

        {s.documents.length === 0 && (
          <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, padding: '14px 16px', margin: 0 }} data-testid="documents-empty">
            {s.documentsLoading ? T('Đang tải…', 'Loading…') : (s.documentsError || empty)}
          </p>
        )}
      </div>
    </div>
  );
}

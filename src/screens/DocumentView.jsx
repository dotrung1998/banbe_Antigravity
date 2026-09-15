import { useRef, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { renderPaymentDocument } from '../lib/paymentDocument.js';
import { paper, ink, alert, inkButton } from '../theme.js';

// The document itself. Two shapes, depending on when it was issued:
//  - file_path set (migration 056 onward): the organizer's own uploaded
//    file, shown directly (an <img> for a photo/scan, an <iframe> for a
//    PDF) via a signed URL — banbe never re-renders it, so what the
//    participant sees is exactly the file the organizer handed over.
//  - no file_path (a document issued before this switch): the old
//    auto-generated HTML, kept as a read-only fallback so a historical
//    document doesn't just disappear.
export default function DocumentView() {
  const {
    state, T, currentDocument, backFromDocument, downloadDocument, uploadPaymentDocument,
  } = useGoc();
  const s = state;
  const doc = currentDocument;
  const isHost = s.documentsRole === 'host';
  const fileInputRef = useRef(null);
  const [replacing, setReplacing] = useState(false);
  const [reason, setReason] = useState('');
  const [pendingFile, setPendingFile] = useState(null);
  const [uploadError, setUploadError] = useState('');
  const [uploading, setUploading] = useState(false);

  if (!doc) {
    return (
      <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Document">
        <div onClick={backFromDocument} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Quay lại', 'Back')}</div>
        <p style={{ fontSize: 13, color: ink, margin: '18px 22px 0' }}>{T('Không tìm thấy chứng từ.', "Couldn't find that document.")}</p>
      </div>
    );
  }

  const isUploaded = Boolean(doc.file_path);
  const isPdf = /\.pdf($|\?)/i.test(doc.file_path || '');

  const pickReplacement = (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setPendingFile(file);
    setReplacing(true);
    setUploadError('');
  };

  const submitReplacement = async () => {
    if (!pendingFile) return;
    if (!reason.trim()) { setUploadError('REASON_REQUIRED'); return; }
    setUploading(true);
    const result = await uploadPaymentDocument(doc.booking_id, doc.kind, pendingFile, reason);
    setUploading(false);
    if (!result.success) { setUploadError(result.error || 'UPLOAD_FAILED'); return; }
    setReplacing(false);
    setPendingFile(null);
    setReason('');
    backFromDocument();
  };

  const errorMessage = uploadError === 'REASON_REQUIRED'
    ? T('Cần nêu lý do khi thay thế chứng từ đã có.', 'A reason is required when replacing an existing document.')
    : uploadError ? T('Không tải lên được. Thử lại nhé.', "Couldn't upload. Please try again.") : '';

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', height: '100%', display: 'flex', flexDirection: 'column', background: paper }} data-screen-label="Document">
      <div onClick={backFromDocument} style={{ flex: 'none', padding: '66px 22px 14px', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="document-view-back">
        ‹ {T('Quay lại', 'Back')}
      </div>

      {isUploaded ? (
        s.documentFileUrl ? (
          isPdf ? (
            <iframe title={doc.number} src={s.documentFileUrl} style={{ flex: 1, minHeight: 0, width: '100%', border: 'none', background: paper }} data-testid="document-frame" />
          ) : (
            <div style={{ flex: 1, minHeight: 0, overflow: 'auto', display: 'flex', justifyContent: 'center', padding: 16 }} data-testid="document-frame">
              <img src={s.documentFileUrl} alt={doc.number} style={{ maxWidth: '100%', height: 'auto' }} />
            </div>
          )
        ) : (
          <p style={{ fontSize: 13, color: ink, margin: '18px 22px' }}>{T('Đang tải…', 'Loading…')}</p>
        )
      ) : (
        <iframe
          title={doc.number}
          srcDoc={renderPaymentDocument(doc, { lang: s.lang, origin: typeof window === 'undefined' ? undefined : window.location.origin })}
          sandbox=""
          style={{ flex: 1, minHeight: 0, width: '100%', border: 'none', background: paper }}
          data-testid="document-frame"
        />
      )}

      {isUploaded ? (
        <a
          href={s.documentFileUrl || undefined}
          target="_blank" rel="noreferrer"
          style={{ ...inkButton({ flex: 'none', borderRadius: 0, padding: '18px 0 30px', display: 'block', textAlign: 'center', textDecoration: 'none' }), opacity: s.documentFileUrl ? 1 : 0.5, pointerEvents: s.documentFileUrl ? 'auto' : 'none' }}
          data-testid="document-view-download"
        >
          {T('Tải về ▪︎ In', 'Download ▪︎ Print')}
        </a>
      ) : (
        <div onClick={() => downloadDocument(doc)} style={{ ...inkButton({ flex: 'none', borderRadius: 0, padding: '18px 0 30px' }) }} data-testid="document-view-download">
          {T('Tải về ▪︎ In', 'Download ▪︎ Print')}
        </div>
      )}

      {isHost && (
        <div style={{ flex: 'none', padding: '0 22px 24px' }}>
          {!replacing ? (
            <>
              <input ref={fileInputRef} type="file" accept="image/jpeg,image/png,image/webp,application/pdf" style={{ display: 'none' }} onChange={pickReplacement} data-testid="document-replace-input" />
              <div onClick={() => fileInputRef.current?.click()} style={{ fontSize: 12, fontWeight: 600, color: ink, border: `1px solid rgba(27,25,22,0.16)`, borderRadius: 12, padding: '10px 14px', textAlign: 'center', cursor: 'pointer' }} data-testid="document-replace-button">
                {T('Thay bằng bản khác', 'Replace with a different file')}
              </div>
            </>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <p style={{ fontSize: 12, color: ink, margin: 0 }}>{pendingFile?.name}</p>
              <textarea
                value={reason} onChange={(e) => setReason(e.target.value)}
                placeholder={T('Lý do thay thế (bắt buộc) — khách sẽ thấy lý do này', 'Reason for replacing (required) — the guest will see this')}
                rows={2} data-testid="document-replace-reason"
                style={{ fontSize: 12.5, padding: 10, borderRadius: 10, border: `1px solid rgba(27,25,22,0.16)`, fontFamily: "'Be Vietnam Pro', sans-serif", resize: 'vertical' }}
              />
              {errorMessage && <p style={{ fontSize: 11.5, color: alert, margin: 0 }} data-testid="document-replace-error">{errorMessage}</p>}
              <div style={{ display: 'flex', gap: 8 }}>
                <div onClick={() => { setReplacing(false); setPendingFile(null); setUploadError(''); }} style={{ flex: 1, fontSize: 12, textAlign: 'center', color: ink, opacity: 0.7, padding: '10px 0', cursor: 'pointer' }}>
                  {T('Huỷ', 'Cancel')}
                </div>
                <div onClick={submitReplacement} style={{ flex: 1, fontSize: 12, fontWeight: 600, textAlign: 'center', color: paper, background: uploading ? 'rgba(27,25,22,0.5)' : ink, borderRadius: 12, padding: '10px 0', cursor: uploading ? 'default' : 'pointer' }} data-testid="document-replace-submit">
                  {uploading ? T('Đang tải lên…', 'Uploading…') : T('Xác nhận thay thế', 'Confirm replacement')}
                </div>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

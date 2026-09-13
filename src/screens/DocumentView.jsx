import { useGoc } from '../state/GocContext.jsx';
import { renderPaymentDocument } from '../lib/paymentDocument.js';
import { paper, ink, inkButton } from '../theme.js';

// The document itself, shown with exactly the renderer that prints and
// emails it — an iframe over the same HTML rather than a second React
// rendering of the same fields. A preview that can drift from the artifact
// it previews is worse than no preview.
export default function DocumentView() {
  const { state, T, currentDocument, backFromDocument, downloadDocument } = useGoc();
  const s = state;
  const doc = currentDocument;

  if (!doc) {
    return (
      <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Document">
        <div onClick={backFromDocument} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Quay lại', 'Back')}</div>
        <p style={{ fontSize: 13, color: ink, margin: '18px 22px 0' }}>{T('Không tìm thấy chứng từ.', "Couldn't find that document.")}</p>
      </div>
    );
  }

  const html = renderPaymentDocument(doc, {
    lang: s.lang,
    origin: typeof window === 'undefined' ? undefined : window.location.origin,
  });

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', height: '100%', display: 'flex', flexDirection: 'column', background: paper }} data-screen-label="Document">
      <div onClick={backFromDocument} style={{ flex: 'none', padding: '66px 22px 14px', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="document-view-back">
        ‹ {T('Quay lại', 'Back')}
      </div>
      <iframe
        title={doc.number}
        srcDoc={html}
        sandbox=""
        style={{ flex: 1, minHeight: 0, width: '100%', border: 'none', background: paper }}
        data-testid="document-frame"
      />
      <div
        onClick={() => downloadDocument(doc)}
        style={{ ...inkButton({ flex: 'none', borderRadius: 0, padding: '18px 0 30px' }) }}
        data-testid="document-view-download"
      >
        {T('Tải về ▪︎ In', 'Download ▪︎ Print')}
      </div>
    </div>
  );
}

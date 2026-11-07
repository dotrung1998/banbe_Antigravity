import QrCode from './QrCode.jsx';
import { ticketQrShowsToken } from '../../lib/ticketStatus.js';
import { moss, paper } from '../../theme.js';

// One QR slot with the ticket's mode (note 78, src/lib/ticketStatus.js). ok/in draw the real admission token; lock, void
// and past NEVER receive it: they draw a fixed decorative pattern (the same for everyone, blurred, not a valid code)
// with a status label, so a cancelled, ended or unconfirmed ticket can never be scanned or screenshotted as valid.
// 'in' keeps the real code but dimmed under a check. Display only: nothing here touches check-in, gifting or polling.

const N = 25;
// A fixed pseudo-random pattern (LCG with a constant seed). It is not derived from any booking data.
const PATTERN = (() => {
  let x = 20261105;
  const cells = [];
  for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0;
    if ((x >>> 16) & 1) cells.push([c, r]);
  }
  return cells;
})();

function Placeholder() {
  return (
    <svg aria-hidden width="100%" height="100%" viewBox={`0 0 ${N} ${N}`} shapeRendering="crispEdges" style={{ display: 'block' }}>
      {PATTERN.map(([c, r]) => <rect key={`${c}-${r}`} x={c} y={r} width="1" height="1" fill="#111111" />)}
    </svg>
  );
}

export default function TicketQr({ mode, value, size = 76, pad = 6, label = '' }) {
  const real = ticketQrShowsToken(mode);
  const small = size < 120;
  const shown = mode === 'in';
  return (
    <div style={{ position: 'relative', flex: 'none', width: size, height: size }} role="img" aria-label={label || undefined}
      data-testid="ticket-qr" data-qr-mode={mode}>
      {real ? (
        <div style={{ opacity: shown ? 0.35 : 1 }}>
          <QrCode value={value} size={size} pad={pad} testId="ticket-qr-real" />
        </div>
      ) : (
        <div data-testid="ticket-qr-placeholder" style={{ width: size, height: size, background: '#FFFFFF', padding: pad, boxSizing: 'border-box', overflow: 'hidden' }}>
          <div style={{ width: '100%', height: '100%', filter: 'blur(6px)', opacity: 0.35 }}><Placeholder /></div>
        </div>
      )}
      {(!real || shown) && (
        <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: small ? 4 : 14 }}>
          {shown ? (
            <span style={{ width: small ? 30 : 56, height: small ? 30 : 56, borderRadius: '50%', background: moss, color: paper, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <svg aria-hidden width={small ? 16 : 30} height={small ? 16 : 30} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>
            </span>
          ) : !small && label ? (
            // Fixed colours: the box behind is always the white QR card, in both themes.
            <span data-testid="ticket-qr-label" style={{ background: 'rgba(255,255,255,0.92)', color: '#1B1916', borderRadius: 12, padding: '8px 12px', fontSize: 13, fontWeight: 600, lineHeight: 1.3, textAlign: 'center', overflowWrap: 'anywhere' }}>{label}</span>
          ) : null}
        </div>
      )}
    </div>
  );
}
